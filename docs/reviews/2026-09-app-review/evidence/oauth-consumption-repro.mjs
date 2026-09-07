/**
 * Reproduce the OAuth consumption findings at review source 696c1d34.
 * Run from the repository after npm ci:
 *   node docs/reviews/2026-09-app-review/evidence/oauth-consumption-repro.mjs
 *
 * Loads the repository's unmodified OAuth route with in-memory TypeScript
 * transpilation and the installed Hono router. Only the D1 adapter and three
 * account helpers are synthetic. A two-reader barrier forces a legal
 * SELECT/SELECT/DELETE/DELETE interleaving, returning DELETE changes 1 then 0.
 * This is a deterministic route/control-flow reproduction, NOT a real D1 or
 * Workers integration test. It makes no network requests or filesystem writes,
 * uses no real accounts or credentials, and never prints issued token values.
 *
 * Expected at the reviewed source: concurrent code and refresh requests both
 * return [200,200] and mint two successors; an unrelated refresh client_id is
 * accepted. Assertions describe the observed defects, not desired behavior.
 * Once repaired, replace this historical reproducer with regression assertions
 * in the real Workers/D1 suite; failure here can mean the defect was fixed.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const sourceRequire = createRequire(new URL('../../../../package.json', import.meta.url));
const ts = sourceRequire('typescript');
const source = readFileSync(new URL('../../../../src/oauth.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
  },
}).outputText;
const module = { exports: {} };
const accountStubs = {
  ensureOwnerUser: async () => ({ id: 'synthetic-user' }),
  findUserByMcpPassphrase: async () => null,
  isAccountDeletionInProgress: async () => false,
};
new Function('require', 'module', 'exports', output)(
  (id) => id === './db' ? accountStubs : sourceRequire(id),
  module,
  module.exports,
);
const { oauthRoutes } = module.exports;

function syntheticDb(kind, concurrent = false) {
  const row = kind === 'code'
    ? {
        code: 'synthetic-code',
        client_id: 'registered-client',
        redirect_uri: 'https://client.example/cb',
        code_challenge: null,
        scope: 'mcp',
        user_id: 'synthetic-user',
        expires_at: Date.now() + 10_000,
      }
    : {
        refresh_token: 'synthetic-refresh',
        client_id: 'registered-client',
        scope: 'mcp',
        user_id: 'synthetic-user',
      };
  let present = true;
  let reads = 0;
  let releaseReaders;
  const barrier = new Promise((resolve) => { releaseReaders = resolve; });
  const result = { minted: 0, deleteChanges: [] };
  return {
    row,
    result,
    prepare(sql) {
      return {
        bind() { return this; },
        async first() {
          if (!/SELECT \* FROM oauth_(codes|tokens)/.test(sql)) {
            throw new Error('Unexpected first SQL; review the adapter for source changes');
          }
          const snapshot = present ? { ...row } : null;
          if (concurrent) {
            if (++reads === 2) releaseReaders();
            await barrier;
          }
          return snapshot;
        },
        async run() {
          if (/DELETE FROM oauth_(codes|tokens)/.test(sql)) {
            const changes = present ? 1 : 0;
            present = false;
            result.deleteChanges.push(changes);
            return { meta: { changes } };
          }
          // Every synthetic request uses the same live account. Account-deletion
          // guards in INSERT ... SELECT therefore permit issuance in this fixture.
          if (/INSERT INTO oauth_tokens/.test(sql)) {
            result.minted++;
            return { meta: { changes: 1 } };
          }
          throw new Error('Unexpected run SQL; review the adapter for source changes');
        },
      };
    },
  };
}

function tokenRequest(kind, clientId = 'registered-client') {
  const form = new FormData();
  form.set('grant_type', kind === 'code' ? 'authorization_code' : 'refresh_token');
  form.set('client_id', clientId);
  if (kind === 'code') {
    form.set('code', 'synthetic-code');
    form.set('redirect_uri', 'https://client.example/cb');
    form.set('code_verifier', 'synthetic-verifier');
  } else {
    form.set('refresh_token', 'synthetic-refresh');
  }
  return new Request('https://app.example/oauth/token', { method: 'POST', body: form });
}

for (const kind of ['code', 'refresh']) {
  const db = syntheticDb(kind, true);
  db.row.code_challenge = Buffer.from(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode('synthetic-verifier')),
  ).toString('base64url');
  const responses = await Promise.all([
    oauthRoutes.fetch(tokenRequest(kind), { DB: db }),
    oauthRoutes.fetch(tokenRequest(kind), { DB: db }),
  ]);
  const observed = {
    probe: `${kind} simultaneous consumption`,
    statuses: responses.map((response) => response.status),
    ...db.result,
  };
  assert.deepEqual(observed.statuses, [200, 200]);
  assert.equal(observed.minted, 2);
  assert.deepEqual(observed.deleteChanges, [1, 0]);
  console.log(JSON.stringify(observed));
}

const db = syntheticDb('refresh');
const response = await oauthRoutes.fetch(tokenRequest('refresh', 'unrelated-client'), { DB: db });
assert.equal(response.status, 200);
assert.equal(db.result.minted, 1);
console.log(JSON.stringify({ probe: 'refresh with wrong client_id', status: response.status, ...db.result }));
