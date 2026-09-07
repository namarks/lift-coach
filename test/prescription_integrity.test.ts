import { applyD1Migrations, env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  getActivePlan,
  getPlanTree,
  updateExercise,
  updatePlanTree,
} from '../src/db';
import { handleMcp } from '../src/mcp/server';
import type { Env } from '../src/types';

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

async function user(label: string): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO users(id,apple_sub,display_name,created_at) VALUES(?1,?2,?3,?4)',
  ).bind(id, `sub-${id}`, label, Date.now()).run();
  return id;
}

describe('prescription integrity', () => {
  it('rejects malformed first-plan payloads without creating state', async () => {
    const userId = await user('invalid-first-plan');
    const result = await updatePlanTree(env.DB, userId, {
      days: [{ name: 'A', exercises: [{ exercise: 'bench', target_sets: 'three', target_reps: 5 } as never] }],
    });
    expect(result).toEqual({ error: 'invalid_fields', fields: ['days.0.exercises.0.target_sets'] });
    expect(await getActivePlan(env.DB, userId)).toBeNull();

    const unknown = await updatePlanTree(env.DB, userId, {
      days: [{ name: 'A', exercises: [{ exercise: 'not in catalog', target_sets: 3, target_reps: 5 }] }],
    });
    expect(unknown).toMatchObject({ error: 'unknown_exercise' });
    expect(await getActivePlan(env.DB, userId)).toBeNull();
  });

  it('validates complete and merged shapes while preserving legitimate values', async () => {
    const userId = await user('valid-values');
    const built = await updatePlanTree(env.DB, userId, {
      days: [{ name: 'A', exercises: [
        { exercise: 'pull-up', target_sets: 3, target_reps: 5, target_reps_max: 8, target_weight: -12.5, target_rpe: 8.5, rest_seconds: 0 },
      ] }],
    });
    expect('conflict' in built && built.conflict).toBe(false);
    const tree = await getPlanTree(env.DB, userId);
    const slot = tree!.days[0]!.exercises[0]!;
    expect(slot).toMatchObject({ target_weight: -12.5, target_rpe: 8.5, rest_seconds: 0 });

    const before = (await getActivePlan(env.DB, userId))!.version;
    expect(await updateExercise(env.DB, userId, { template_exercise_id: slot.id }, { target_reps: 9 }))
      .toEqual({ error: 'invalid_fields', fields: ['target_reps_max'] });
    expect(await updateExercise(env.DB, userId, { template_exercise_id: slot.id }, { target_rpe: 99 }))
      .toEqual({ error: 'invalid_fields', fields: ['target_rpe'] });
    expect((await getActivePlan(env.DB, userId))!.version).toBe(before);
    expect((await getPlanTree(env.DB, userId))!.days[0]!.exercises[0]!.target_reps).toBe(5);
  });

  it('rejects signed assistance for a destination that cannot represent it', async () => {
    const userId = await user('signed-load');
    const result = await updatePlanTree(env.DB, userId, {
      days: [{ name: 'A', exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 5, target_weight: -5 }] }],
    });
    expect(result).toEqual({ error: 'invalid_fields', fields: ['days.0.exercises.0.target_weight'] });
    expect(await getActivePlan(env.DB, userId)).toBeNull();
  });

  it('rejects malformed values through MCP and REST wrappers without coercion', async () => {
    const userId = await user('wrappers');
    await updatePlanTree(env.DB, userId, { days: [{ name: 'A', day_label: 'A', exercises: [] }] });
    const mcp = await handleMcp({
      jsonrpc: '2.0', id: 1, method: 'tools/call',
      params: { name: 'add_exercise', arguments: {
        day: 'A', exercise: 'bench', target_sets: '3', target_reps: 5,
        rest_seconds: '120', order_index: '0', is_warmup: 'false',
      } },
    }, env as Env, userId);
    const mcpBody = mcp.json as { result: { content: { text: string }[] } };
    expect(JSON.parse(mcpBody.result.content[0]!.text)).toEqual({
      error: 'invalid_fields',
      fields: ['is_warmup', 'order_index', 'rest_seconds', 'target_sets'],
    });

    const auth = await SELF.fetch('https://tres-fort.test/auth/dev', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ secret: 'test-dev' }),
    });
    const jwt = (await auth.json<{ jwt: string }>()).jwt;
    const active = await SELF.fetch('https://tres-fort.test/api/plan', {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${jwt}` },
      body: JSON.stringify({ name: 'REST wrapper plan' }),
    });
    expect(active.status).toBe(201);
    const day = await SELF.fetch('https://tres-fort.test/api/days', {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${jwt}` },
      body: JSON.stringify({ name: 'A' }),
    });
    const dayId = (await day.json<{ id: string }>()).id;
    const before = (await SELF.fetch('https://tres-fort.test/api/plan/active', {
      headers: { authorization: `Bearer ${jwt}` },
    }).then((r) => r.json<{ version: number }>())).version;
    const rejected = await SELF.fetch(`https://tres-fort.test/api/days/${dayId}/exercises`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${jwt}` },
      body: JSON.stringify({ exercise: 'bench', target_sets: 3, target_reps: 5, rest_seconds: '120', is_warmup: 'false' }),
    });
    expect(rejected.status).toBe(400);
    expect(await rejected.json()).toEqual({ error: 'invalid_fields', fields: ['is_warmup', 'rest_seconds'] });
    const after = await SELF.fetch('https://tres-fort.test/api/plan/active', {
      headers: { authorization: `Bearer ${jwt}` },
    }).then((r) => r.json<{ version: number }>());
    expect(after.version).toBe(before);
  });

  it('composes disjoint legacy patches instead of restoring stale fields', async () => {
    const userId = await user('disjoint');
    await updatePlanTree(env.DB, userId, {
      days: [{ name: 'A', exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 5, target_weight: 100, cues: 'old' }] }],
    });
    const slot = (await getPlanTree(env.DB, userId))!.days[0]!.exercises[0]!;
    await Promise.all([
      updateExercise(env.DB, userId, { template_exercise_id: slot.id }, { target_weight: 110 }),
      updateExercise(env.DB, userId, { template_exercise_id: slot.id }, { cues: 'new' }),
    ]);
    expect((await getPlanTree(env.DB, userId))!.days[0]!.exercises[0]).toMatchObject({ target_weight: 110, cues: 'new' });
  });
});
