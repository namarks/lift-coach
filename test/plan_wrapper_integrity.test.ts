import { applyD1Migrations, env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { issueAppJwt } from '../src/auth';
import { createPlan, updatePlanTree } from '../src/db';
import { handleMcp } from '../src/mcp/server';
import type { Env } from '../src/types';

const BASE = 'https://tres-fort.test';
beforeAll(async () => applyD1Migrations(env.DB, env.TEST_MIGRATIONS));

async function fixture(label: string) {
  const userId = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO users(id,apple_sub,display_name,created_at) VALUES(?1,?2,?3,?4)',
  ).bind(userId, `sub-${userId}`, label, Date.now()).run();
  const plan = await createPlan(env.DB, userId, `${label} plan`, null, {
    actor: 'ios', operation: 'create_plan', args: { name: `${label} plan` },
  });
  const built = await updatePlanTree(env.DB, userId, {
    expected_version: plan.version,
    days: [{ name: 'Strength', day_label: 'A', exercises: [
      { exercise: 'bench', target_sets: 3, target_reps: 5 },
    ] }],
  }, { actor: 'mcp', operation: 'update_plan', note: 'Fixture plan.' });
  if (!('plan' in built)) throw new Error('fixture_failed');
  return { userId, plan: built.plan, jwt: await issueAppJwt(userId, 'test-secret') };
}

async function footprint(userId: string) {
  const plan = await env.DB.prepare(
    "SELECT id,name,version FROM plans WHERE user_id=?1 AND status='active'",
  ).bind(userId).first<{ id: string; name: string; version: number }>();
  const counts = await env.DB.prepare(
    `SELECT
       (SELECT COUNT(*) FROM audit_log WHERE user_id=?1) AS audits,
       (SELECT COUNT(*) FROM notes WHERE user_id=?1) AS notes,
       (SELECT COUNT(*) FROM plan_snapshots WHERE user_id=?1) AS snapshots`,
  ).bind(userId).first<{ audits: number; notes: number; snapshots: number }>();
  return { plan, counts };
}

async function mcp(userId: string, name: string, args: Record<string, unknown>) {
  const response = await handleMcp({
    jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args },
  }, env as Env, userId);
  const body = response.json as { result: { content: Array<{ text: string }> } };
  return JSON.parse(body.result.content[0]!.text) as unknown;
}

describe('plan REST and MCP wrapper integrity', () => {
  it('rejects malformed replacement plans without changing durable plan state', async () => {
    const { userId, jwt } = await fixture('bad-rest-plan');
    const before = await footprint(userId);
    for (const [body, expected] of [
      [JSON.stringify({ name: 123 }), { error: 'invalid_fields', fields: ['name'] }],
      [JSON.stringify({ name: 'Replacement', meta: [] }), { error: 'invalid_fields', fields: ['meta'] }],
      [JSON.stringify([]), { error: 'invalid_body' }],
      ['{', { error: 'invalid_json' }],
    ] as const) {
      const response = await SELF.fetch(`${BASE}/api/plan`, {
        method: 'POST',
        headers: { authorization: `Bearer ${jwt}`, 'content-type': 'application/json' },
        body,
      });
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual(expected);
      expect(await footprint(userId)).toEqual(before);
    }
  });

  it('rejects wrong-type MCP history arguments without restoring or contributing records', async () => {
    const { userId, plan } = await fixture('bad-mcp-history');
    const before = await footprint(userId);
    expect(await mcp(userId, 'restore_plan', {
      snapshot_version: String(plan.version),
      plan_id: plan.id,
      expected_version: String(plan.version),
      reason: 'Wrong runtime types',
    })).toEqual({ error: 'invalid_fields', fields: ['snapshot_version', 'expected_version'] });
    expect(await mcp(userId, 'compare_plan_versions', { from_version: String(plan.version) }))
      .toEqual({ error: 'invalid_fields', fields: ['from_version'] });
    expect(await mcp(userId, 'get_plan_history', { limit: '30', before_version: 0 }))
      .toEqual({ error: 'invalid_fields', fields: ['limit', 'before_version'] });
    expect(await footprint(userId)).toEqual(before);
  });

  it('accepts explicit current comparisons and rejects malformed history query values', async () => {
    const { jwt, plan } = await fixture('rest-history-query');
    const headers = { authorization: `Bearer ${jwt}` };
    const comparison = await SELF.fetch(
      `${BASE}/api/plan/history/${plan.version}/compare?to_version=current`, { headers },
    );
    expect(comparison.status).toBe(200);
    expect(await comparison.json()).toMatchObject({
      plan_id: plan.id, from_version: plan.version, to_version: plan.version,
    });

    for (const [query, fields] of [
      ['limit=abc', ['limit']],
      ['limit=1e2', ['limit']],
      ['limit=101', ['limit']],
      ['before_version=-1', ['before_version']],
      ['limit=1.5&before_version=nope', ['limit', 'before_version']],
    ] as const) {
      const response = await SELF.fetch(`${BASE}/api/plan/history?${query}`, { headers });
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: 'invalid_fields', fields });
    }

    const exponentVersion = await SELF.fetch(
      `${BASE}/api/plan/history/1e2/compare?to_version=current`, { headers },
    );
    expect(exponentVersion.status).toBe(400);
    expect(await exponentVersion.json()).toEqual({ error: 'invalid_version' });
  });

  it('maps an invalid legacy snapshot restore to a stable 400 without side effects', async () => {
    const { userId, jwt, plan } = await fixture('invalid-legacy-restore');
    const snapshot = await env.DB.prepare(
      'SELECT document FROM plan_snapshots WHERE user_id=?1 AND plan_id=?2 AND version=?3',
    ).bind(userId, plan.id, plan.version).first<{ document: string }>();
    const document = JSON.parse(snapshot!.document) as {
      days: Array<{ exercises: Array<Record<string, unknown>> }>;
    };
    document.days[0]!.exercises[0]!.target_sets = '3';
    await env.DB.prepare(
      'UPDATE plan_snapshots SET document=?1 WHERE user_id=?2 AND plan_id=?3 AND version=?4',
    ).bind(JSON.stringify(document), userId, plan.id, plan.version).run();
    const before = await footprint(userId);

    const response = await SELF.fetch(`${BASE}/api/plan/history/${plan.version}/restore`, {
      method: 'POST',
      headers: { authorization: `Bearer ${jwt}`, 'content-type': 'application/json' },
      body: JSON.stringify({ expected_plan_id: plan.id, expected_version: plan.version }),
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: 'invalid_fields', fields: ['A/ex_bench.target_sets'],
    });
    expect(await footprint(userId)).toEqual(before);
  });
});
