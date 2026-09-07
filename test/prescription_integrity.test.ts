import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  getActivePlan,
  getPlanTree,
  updateExercise,
  updatePlanTree,
} from '../src/db';

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
