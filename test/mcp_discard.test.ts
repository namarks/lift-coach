import { applyD1Migrations, env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';

const BASE = 'https://tres-fort.test';
const TOKEN = 'test-mcp-token';

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

let rpcId = 0;
async function call(name: string, args: unknown) {
  const response = await SELF.fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: ++rpcId,
      method: 'tools/call',
      params: { name, arguments: args },
    }),
  });
  const body = await response.json<any>();
  return JSON.parse(body.result.content[0].text);
}

async function seedOwner() {
  const authResponse = await SELF.fetch(`${BASE}/auth/dev`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ secret: 'test-dev' }),
  });
  const { jwt } = await authResponse.json<{ jwt: string }>();
  await call('update_plan', {
    name: 'Discard tests',
    days: [
      {
        day_label: 'A',
        name: 'Day A',
        exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 5 }],
      },
    ],
  });
  const plan = await env.DB.prepare("SELECT id,user_id FROM plans WHERE status='active'")
    .first<{ id: string; user_id: string }>();
  return { ...plan!, jwt };
}

async function seedSession(
  userId: string,
  planId: string,
  date: string,
  attempt = 0,
) {
  const sessionId = crypto.randomUUID();
  const setId = crypto.randomUUID();
  const ts = Date.now();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO sessions
         (id,user_id,plan_id,date,status,started_at,created_at,updated_at,attempt,write_protocol)
       VALUES (?1,?2,?3,?4,'in_progress',?5,?5,?5,?6,'legacy')`,
    ).bind(sessionId, userId, planId, date, ts, attempt),
    env.DB.prepare(
      `INSERT INTO set_logs
         (id,session_id,exercise_id,set_index,weight,reps,is_warmup,logged_at,source)
       VALUES (?1,?2,'ex_bench',1,100,5,0,?3,'ios')`,
    ).bind(setId, sessionId, ts),
  ]);
  return { sessionId, setId };
}

async function discardAuditCount(sessionId: string) {
  return (
    await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM audit_log WHERE tool='discard_session' AND json_extract(args,'$.session_id')=?1",
    )
      .bind(sessionId)
      .first<{ count: number }>()
  )!.count;
}

describe('discard_workout MCP tool', () => {
  it('uses the owned discard transaction with mandatory generation CAS and no duplicate audit', async () => {
    const owner = await seedOwner();
    const legacy = await seedSession(owner.user_id, owner.id, '2039-01-01');
    const v1 = await seedSession(owner.user_id, owner.id, '2039-01-02');
    const unrelated = await seedSession(owner.user_id, owner.id, '2039-01-03');
    const stale = await seedSession(owner.user_id, owner.id, '2039-01-04', 1);

    const foreignUserId = crypto.randomUUID();
    const foreignPlanId = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(
        'INSERT INTO users (id,apple_sub,display_name,created_at) VALUES (?1,?2,?3,?4)',
      ).bind(foreignUserId, `apple-${foreignUserId}`, 'Other', Date.now() + 1),
      env.DB.prepare(
        "INSERT INTO plans (id,user_id,name,status,version,created_at,updated_at) VALUES (?1,?2,'Other','active',1,?3,?3)",
      ).bind(foreignPlanId, foreignUserId, Date.now() + 1),
    ]);
    const foreign = await seedSession(foreignUserId, foreignPlanId, '2039-01-05');

    await env.DB.prepare(
      'UPDATE workout_write_fence SET enabled=1, activated_at=?1 WHERE id=1',
    ).bind(Date.now()).run();
    for (const candidate of [
      { sessionId: v1.sessionId, attempt: 0 },
      { sessionId: stale.sessionId, attempt: 1 },
    ]) {
      const claim = await SELF.fetch(
        `${BASE}/api/sessions/${candidate.sessionId}?expected_attempt=${candidate.attempt}`,
        {
        method: 'PATCH',
        headers: {
          'content-type': 'application/json',
          Authorization: `Bearer ${owner.jwt}`,
          'X-TresFort-Write-Protocol': 'attempt-v1',
        },
        body: JSON.stringify({ notes: 'claim protocol for test' }),
        },
      );
      expect(claim.status).toBe(200);
    }

    const malformed = await call('discard_workout', {
      session_id: legacy.sessionId,
      expected_attempt: '0',
    });
    expect(malformed).toEqual({ error: 'invalid_fields', fields: ['expected_attempt'] });
    expect(await call('discard_workout', { session_id: legacy.sessionId })).toEqual({
      error: 'invalid_fields',
      fields: ['expected_attempt'],
    });
    expect(await call('discard_workout', { session_id: '', expected_attempt: 0 })).toEqual({
      error: 'invalid_fields',
      fields: ['session_id'],
    });
    expect(await discardAuditCount(legacy.sessionId)).toBe(0);

    const legacyResult = await call('discard_workout', {
      session_id: legacy.sessionId,
      expected_attempt: 0,
    });
    expect(legacyResult).toMatchObject({
      ok: true,
      session: { id: legacy.sessionId, status: 'discarded', attempt: 0, write_protocol: 'legacy' },
    });
    expect(await discardAuditCount(legacy.sessionId)).toBe(1);

    const retry = await call('discard_workout', {
      session_id: legacy.sessionId,
      expected_attempt: 0,
    });
    expect(retry).toMatchObject({ ok: true, session: { status: 'discarded' } });
    expect(await discardAuditCount(legacy.sessionId)).toBe(1);
    expect(
      await env.DB.prepare("SELECT COUNT(*) AS count FROM audit_log WHERE tool='discard_workout'")
        .first<{ count: number }>(),
    ).toEqual({ count: 0 });

    const v1Result = await call('discard_workout', {
      session_id: v1.sessionId,
      expected_attempt: 0,
    });
    expect(v1Result).toMatchObject({
      ok: true,
      session: { id: v1.sessionId, status: 'discarded', write_protocol: 'attempt-v1' },
    });

    const staleResult = await call('discard_workout', {
      session_id: stale.sessionId,
      expected_attempt: 0,
    });
    expect(staleResult).toMatchObject({
      error: 'session_attempt_conflict',
      expected_attempt: 0,
      current_attempt: 1,
      current_session: { id: stale.sessionId, status: 'in_progress', attempt: 1 },
    });
    expect(await discardAuditCount(stale.sessionId)).toBe(0);

    expect(
      await call('discard_workout', { session_id: foreign.sessionId, expected_attempt: 0 }),
    ).toEqual({ error: 'not_found', session_id: foreign.sessionId });
    expect(
      await call('discard_workout', { session_id: crypto.randomUUID(), expected_attempt: 0 }),
    ).toMatchObject({ error: 'not_found' });

    const rows = await env.DB.prepare(
      `SELECT id,status,write_protocol FROM sessions
       WHERE id IN (?1,?2,?3,?4,?5) ORDER BY date`,
    )
      .bind(legacy.sessionId, v1.sessionId, unrelated.sessionId, stale.sessionId, foreign.sessionId)
      .all<{ id: string; status: string; write_protocol: string }>();
    expect(rows.results).toEqual([
      { id: legacy.sessionId, status: 'discarded', write_protocol: 'legacy' },
      { id: v1.sessionId, status: 'discarded', write_protocol: 'attempt-v1' },
      { id: unrelated.sessionId, status: 'in_progress', write_protocol: 'legacy' },
      { id: stale.sessionId, status: 'in_progress', write_protocol: 'attempt-v1' },
      { id: foreign.sessionId, status: 'in_progress', write_protocol: 'legacy' },
    ]);
    for (const item of [legacy, v1]) {
      expect(
        await env.DB.prepare('SELECT deleted_at FROM set_logs WHERE id=?1')
          .bind(item.setId)
          .first<{ deleted_at: number | null }>(),
      ).toEqual({ deleted_at: expect.any(Number) });
    }
    for (const item of [unrelated, stale, foreign]) {
      expect(
        await env.DB.prepare('SELECT deleted_at FROM set_logs WHERE id=?1')
          .bind(item.setId)
          .first<{ deleted_at: number | null }>(),
      ).toEqual({ deleted_at: null });
    }
  });
});
