import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  comparePlanVersions,
  createPlan,
  exportUserData,
  getOrCreateSession,
  getPlanSnapshot,
  getPlanTree,
  listPlanHistory,
  restorePlanSnapshot,
  updatePlanTree,
} from '../src/db';
import { comparePlanSnapshots, serializePlanSnapshot } from '../src/planSnapshots';

beforeAll(async () => applyD1Migrations(env.DB, env.TEST_MIGRATIONS));

async function fixture(label: string) {
  const userId = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO users (id,apple_sub,display_name,created_at) VALUES (?1,?2,?3,?4)',
  ).bind(userId, `sub-${userId}`, label, Date.now()).run();
  await createPlan(env.DB, userId, `${label} plan`);
  const built = await updatePlanTree(env.DB, userId, {
    name: `${label} plan`,
    days: [{ name: 'Strength A', day_label: 'A', exercises: [
      { exercise: 'bench', target_sets: 3, target_reps: 5, target_weight: 135 },
    ] }],
  });
  if (!('plan' in built)) throw new Error('fixture_plan_failed');
  return { userId, plan: built.plan };
}

describe('plan snapshots', () => {
  it('round trips the canonical writable document and reports a useful comparison', async () => {
    const { userId, plan } = await fixture('roundtrip');
    const stored = await getPlanSnapshot(env.DB, userId, plan.id, plan.version);
    expect(stored?.parsed).toEqual(serializePlanSnapshot(plan));
    const changed = structuredClone(stored!.parsed);
    changed.days[0]!.exercises[0]!.target_weight = 145;
    const diff = comparePlanSnapshots(stored!.parsed, changed);
    expect(diff.summary.exercises_changed).toBe(1);
    expect(diff.changes[0]?.path).toContain('exercises');
  });

  it('restores a caller-owned snapshot as a new version and retains both versions', async () => {
    const { userId, plan } = await fixture('restore');
    const changed = await updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      name: 'Changed plan',
      days: [{ name: 'Strength B', day_label: 'B', exercises: [
        { exercise: 'squat', target_sets: 4, target_reps: 6 },
      ] }],
    });
    if (!('plan' in changed)) throw new Error('changed_plan_failed');
    const restored = await restorePlanSnapshot(env.DB, userId, {
      plan_id: plan.id, snapshot_version: plan.version,
      expected_version: changed.plan.version, actor: 'ios', reason: 'Undo change',
    });
    expect(restored).toMatchObject({ ok: true, restored_from_version: plan.version, version: changed.plan.version + 1 });
    expect((await getPlanTree(env.DB, userId))?.name).toBe(plan.name);
    expect(await getPlanSnapshot(env.DB, userId, plan.id, plan.version)).not.toBeNull();
    expect(await getPlanSnapshot(env.DB, userId, plan.id, changed.plan.version + 1)).not.toBeNull();
    const history = await listPlanHistory(env.DB, userId);
    if (!('items' in history) || !Array.isArray(history.items)) throw new Error('history_missing');
    expect(history.items[0]?.operation).toBe('restore_plan');
    const comparison = await comparePlanVersions(env.DB, userId, plan.version);
    expect('changes' in comparison && comparison.changes).toHaveLength(0);
  });

  it('rejects stale, cross-user, and active-workout restore attempts', async () => {
    const one = await fixture('owner-one');
    const two = await fixture('owner-two');
    expect(await restorePlanSnapshot(env.DB, two.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: two.plan.version, actor: 'mcp',
    })).toMatchObject({ conflict: true });
    expect(await restorePlanSnapshot(env.DB, one.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: one.plan.version - 1, actor: 'mcp',
    })).toMatchObject({ conflict: true });
    const session = await getOrCreateSession(
      env.DB, one.userId, one.plan.id, '2026-09-07', one.plan.days[0]!.id,
    );
    await env.DB.prepare("UPDATE sessions SET status='in_progress' WHERE id=?1").bind(session.id).run();
    expect(await restorePlanSnapshot(env.DB, one.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: one.plan.version, actor: 'ios',
    })).toEqual({ error: 'active_workout' });
  });

  it('includes immutable plan history in the portable export', async () => {
    const { userId } = await fixture('export');
    const exported = await exportUserData(env.DB, userId) as {
      schema_version: number; training: { plan_snapshots: unknown[] };
    };
    expect(exported.schema_version).toBe(2);
    expect(exported.training.plan_snapshots).toHaveLength(2);
  });
});
