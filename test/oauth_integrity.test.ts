import { applyD1Migrations, env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';

const BASE = 'https://tres-fort.test';

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

async function challenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function seedCode(options: { expired?: boolean; userId?: string; clientId?: string } = {}) {
  const suffix = crypto.randomUUID();
  const userId = options.userId ?? `oauth-user-${suffix}`;
  const clientId = options.clientId ?? `oauth-client-${suffix}`;
  const code = `oauth-code-${suffix}`;
  const verifier = `oauth-verifier-${suffix}`;
  const redirect = `https://client.example/${suffix}`;
  const now = Date.now();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT OR IGNORE INTO users (id, apple_sub, display_name, created_at)
       VALUES (?1, ?2, 'OAuth test', ?3)`,
    ).bind(userId, `oauth-sub-${userId}`, now),
    env.DB.prepare(
      `INSERT OR IGNORE INTO oauth_clients
         (client_id, client_secret, redirect_uris, client_name, created_at)
       VALUES (?1, NULL, ?2, 'OAuth integrity', ?3)`,
    ).bind(clientId, JSON.stringify([redirect]), now),
    env.DB.prepare(
      `INSERT INTO oauth_codes
         (code, client_id, redirect_uri, code_challenge, code_challenge_method,
          scope, resource, expires_at, created_at, user_id)
       VALUES (?1, ?2, ?3, ?4, 'S256', 'mcp', NULL, ?5, ?6, ?7)`,
    ).bind(code, clientId, redirect, await challenge(verifier), options.expired ? now - 1 : now + 60_000, now, userId),
  ]);
  return { code, verifier, redirect, clientId, userId };
}

function codeRequest(grant: Awaited<ReturnType<typeof seedCode>>, overrides: Record<string, string> = {}) {
  const form = new FormData();
  form.set('grant_type', 'authorization_code');
  form.set('code', grant.code);
  form.set('client_id', grant.clientId);
  form.set('redirect_uri', grant.redirect);
  form.set('code_verifier', grant.verifier);
  for (const [key, value] of Object.entries(overrides)) form.set(key, value);
  return SELF.fetch(`${BASE}/oauth/token`, { method: 'POST', body: form });
}

async function seedRefresh(options: { expired?: boolean; userId?: string } = {}) {
  const suffix = crypto.randomUUID();
  const userId = options.userId ?? `refresh-user-${suffix}`;
  const clientId = `refresh-client-${suffix}`;
  const refresh = `refresh-${suffix}`;
  const access = `access-${suffix}`;
  const now = Math.floor(Date.now() / 1000);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT OR IGNORE INTO users (id, apple_sub, display_name, created_at)
       VALUES (?1, ?2, 'Refresh test', ?3)`,
    ).bind(userId, `refresh-sub-${userId}`, Date.now()),
    env.DB.prepare(
      `INSERT INTO oauth_tokens
         (access_token, refresh_token, client_id, scope, expires_at, created_at, user_id)
       VALUES (?1, ?2, ?3, 'mcp', ?4, ?5, ?6)`,
    ).bind(access, refresh, clientId, options.expired ? now - 1 : now + 600, now, userId),
  ]);
  return { access, refresh, clientId, userId };
}

function refreshRequest(grant: Awaited<ReturnType<typeof seedRefresh>>, clientId = grant.clientId) {
  const form = new FormData();
  form.set('grant_type', 'refresh_token');
  form.set('refresh_token', grant.refresh);
  form.set('client_id', clientId);
  return SELF.fetch(`${BASE}/oauth/token`, { method: 'POST', body: form });
}

describe('atomic OAuth grant transitions', () => {
  it('allows exactly one concurrent authorization-code redemption', async () => {
    const grant = await seedCode();
    const responses = await Promise.all([codeRequest(grant), codeRequest(grant)]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 400]);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE user_id = ?1')
      .bind(grant.userId).first<{ n: number }>('n')).toBe(1);
  });

  it('allows exactly one concurrent refresh and preserves the grant binding', async () => {
    const grant = await seedRefresh();
    const responses = await Promise.all([refreshRequest(grant), refreshRequest(grant)]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 400]);
    const row = await env.DB.prepare(
      'SELECT client_id, scope, user_id FROM oauth_tokens WHERE user_id = ?1',
    ).bind(grant.userId).first<{ client_id: string; scope: string; user_id: string }>();
    expect(row).toEqual({ client_id: grant.clientId, scope: 'mcp', user_id: grant.userId });
  });

  it('does not consume a code for a wrong client, verifier, redirect, or expiry', async () => {
    for (const [kind, overrides] of [
      ['client', { client_id: 'wrong-client' }],
      ['verifier', { code_verifier: 'wrong-verifier' }],
      ['redirect', { redirect_uri: 'https://attacker.example/cb' }],
    ] as const) {
      const grant = await seedCode();
      const response = await codeRequest(grant, overrides);
      expect(response.status, kind).toBe(400);
      expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_codes WHERE code = ?1')
        .bind(grant.code).first<number>('n')).toBe(1);
    }
    const expired = await seedCode({ expired: true });
    expect((await codeRequest(expired)).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_codes WHERE code = ?1')
      .bind(expired.code).first<number>('n')).toBe(1);
  });

  it('keeps the code when successor insertion fails', async () => {
    const grant = await seedCode();
    await env.DB.prepare(
      `CREATE TRIGGER oauth_integrity_fail_insert
       BEFORE INSERT ON oauth_tokens WHEN NEW.client_id = '${grant.clientId}'
       BEGIN SELECT RAISE(ABORT, 'synthetic_insert_failure'); END`,
    ).run();
    try {
      expect((await codeRequest(grant)).status).toBe(500);
      expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_codes WHERE code = ?1')
        .bind(grant.code).first<number>('n')).toBe(1);
      expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE client_id = ?1')
        .bind(grant.clientId).first<number>('n')).toBe(0);
    } finally {
      await env.DB.prepare('DROP TRIGGER oauth_integrity_fail_insert').run();
    }
  });

  it('rejects refresh client mismatch without consuming the grant', async () => {
    const grant = await seedRefresh();
    expect((await refreshRequest(grant, 'wrong-client')).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE refresh_token = ?1')
      .bind(grant.refresh).first<number>('n')).toBe(1);
  });

  it('continues to refresh after access expiry without choosing a P1 lifetime policy', async () => {
    const grant = await seedRefresh({ expired: true });
    expect((await refreshRequest(grant)).status).toBe(200);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE user_id = ?1')
      .bind(grant.userId).first<number>('n')).toBe(1);
  });

  it('fences code redemption and refresh rotation once account deletion starts', async () => {
    const code = await seedCode();
    const refresh = await seedRefresh({ userId: code.userId });
    await env.DB.prepare(
      `INSERT INTO account_deletion_intents
         (user_id, idempotency_key_sha256, apple_revocation, created_at)
       VALUES (?1, 'test-digest', NULL, ?2)`,
    ).bind(code.userId, Date.now()).run();
    expect((await codeRequest(code)).status).toBe(400);
    expect((await refreshRequest(refresh)).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_codes WHERE code = ?1')
      .bind(code.code).first<number>('n')).toBe(1);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE refresh_token = ?1')
      .bind(refresh.refresh).first<number>('n')).toBe(1);
  });

  it('does not consume a scoped code when its explicit principal disappeared', async () => {
    const grant = await seedCode();
    await env.DB.prepare('DELETE FROM users WHERE id = ?1').bind(grant.userId).run();
    expect((await codeRequest(grant)).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_codes WHERE code = ?1')
      .bind(grant.code).first<number>('n')).toBe(1);
  });

  it('turns a retry after a lost successful response into invalid_grant', async () => {
    const grant = await seedCode();
    const lost = await codeRequest(grant);
    expect(lost.status).toBe(200);
    // The client never receives the body. Replaying does not disclose the
    // committed successor; reauthorization is the recovery path.
    expect((await codeRequest(grant)).status).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM oauth_tokens WHERE user_id = ?1')
      .bind(grant.userId).first<number>('n')).toBe(1);
  });
});
