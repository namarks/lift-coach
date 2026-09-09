import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { addTemplateExercise, adjustToday, clearGroup, dedupeDayOrderIndexes, deleteWorkout,
  deleteTemplateExercise, getActivePlan, getPlanTree, getPlanSnapshot, restorePlanSnapshot,
  setGroup, swapExercise, updateExercise, updatePlanTree, type ExerciseInput } from '../src/db';
import { comparePlanSnapshots, parsePlanSnapshot, serializePlanSnapshot } from '../src/planSnapshots';
import type { PlanTree } from '../src/types';

beforeAll(async () => { await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });

async function fixture() {
  const userId = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO users(id,apple_sub,created_at) VALUES(?1,?2,?3)')
    .bind(userId, `group-${userId}`, Date.now()).run();
  const result = await updatePlanTree(env.DB, userId, { name: 'Groups', workouts: [
    { name: 'A', day_label: 'A', exercises: ['bench', 'squat', 'row', 'deadlift'].map((exercise, index) => ({
      exercise, target_sets: 3, target_reps: 10, rest_seconds: 60 + index * 10, is_warmup: index < 2 ? 1 : 0,
    })) },
    { name: 'B', day_label: 'B', exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 8 }] },
  ] });
  if (!('plan' in result)) throw new Error('fixture failed');
  const tree = result.plan; const day = tree.workouts[0]!;
  const groupId = crypto.randomUUID();
  return { userId, tree, day, groupId, ids: day.exercises.map((slot) => slot.id) };
}
async function counts(userId: string) {
  return (await env.DB.prepare(`SELECT
    (SELECT version FROM plans WHERE user_id=?1 AND status='active') version,
    (SELECT COUNT(*) FROM audit_log WHERE user_id=?1) audits,
    (SELECT COUNT(*) FROM notes WHERE user_id=?1) notes,
    (SELECT COUNT(*) FROM plan_snapshots WHERE user_id=?1) snapshots`).bind(userId)
    .first<{ version: number; audits: number; notes: number; snapshots: number }>())!;
}
async function current(userId: string) { return (await getPlanTree(env.DB, userId))!; }
function rebuild(tree: PlanTree) {
  return { name: tree.name, expected_version: tree.version, workouts: tree.workouts.map((day) => ({
    name: day.name, day_label: day.day_label, exercises: day.exercises.map((slot): ExerciseInput => ({
      exercise: slot.exercise_id, target_sets: slot.target_sets, target_reps: slot.target_reps,
      rest_seconds: slot.rest_seconds, is_warmup: slot.is_warmup,
      group_id: slot.group_id, group_rest_seconds: slot.group_rest_seconds,
      group_transition_seconds: slot.group_transition_seconds,
    })),
  })) };
}
const attribution = { actor: 'mcp' as const, operation: 'group_exercises' };

describe('exercise groups service contract', () => {
  it('commits the group, its original rests, attribution and canonical snapshots together', async () => {
    const f = await fixture(); const before = await counts(f.userId);
    const result = await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), {
      expected_version: f.tree.version, round_rest: 90, transition_rest: 5,
    }, attribution);
    expect(result).toMatchObject({ ok: true, version: before.version + 1, members: f.ids.slice(0, 2) });
    const after = await counts(f.userId);
    expect(after).toEqual({ version: before.version + 1, audits: before.audits + 1,
      notes: before.notes + 1, snapshots: before.snapshots + 1 });
    const tree = await current(f.userId);
    expect(tree.workouts[0]!.exercises.slice(0, 2).map((slot) => [slot.group_id, slot.group_rest_seconds,
      slot.group_transition_seconds, slot.rest_seconds, slot.is_warmup])).toEqual([
      [f.groupId, 90, 5, 60, 1], [f.groupId, 90, 5, 70, 1],
    ]);
    expect((await getPlanSnapshot(env.DB, f.userId, tree.id, tree.version))!.parsed).toEqual(serializePlanSnapshot(tree));
  });

  it('recognizes only the caller-scoped exact acknowledged stale retry', async () => {
    const f = await fixture(); const options = { expected_version: f.tree.version, round_rest: 90 };
    const first = await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options, attribution);
    const before = await counts(f.userId);
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options, attribution))
      .toEqual({ ...first, replayed: true });
    expect(await counts(f.userId)).toEqual(before);
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { ...options, round_rest: 100 }, attribution))
      .toEqual({ conflict: true, current_version: before.version });
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options,
      { actor: 'ios', operation: 'group_exercises' })).toEqual({ conflict: true, current_version: before.version });
    const other = await fixture();
    expect(await setGroup(env.DB, other.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options, attribution))
      .toEqual({ error: 'day_not_found' });
  });

  it('does not restore old membership when replayed after a rewrite or full rebuild', async () => {
    const f = await fixture(); const firstOptions = { expected_version: f.tree.version, round_rest: 90 };
    const first = await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), firstOptions, attribution);
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(1, 3), {
      expected_version: f.tree.version + 1, round_rest: 120, target_sets: 4,
    }, attribution);
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), firstOptions, attribution))
      .toEqual({ ...first, replayed: true });
    const tree = await current(f.userId);
    expect(tree.workouts[0]!.exercises.map((slot) => slot.group_id)).toEqual([null, f.groupId, f.groupId, null]);
    await updatePlanTree(env.DB, f.userId, rebuild(tree));
    const before = await counts(f.userId);
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), firstOptions, attribution))
      .toEqual({ ...first, replayed: true });
    expect(await counts(f.userId)).toEqual(before);
  });

  it('clears once, retains ordinary rest, and safely replays old clears after regrouping', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 90 });
    const version = f.tree.version + 1;
    const cleared = await clearGroup(env.DB, f.userId, f.groupId, version);
    const before = await counts(f.userId);
    expect(await clearGroup(env.DB, f.userId, f.groupId, version)).toEqual({ ...cleared, replayed: true });
    expect(await clearGroup(env.DB, f.userId, f.groupId, before.version)).toMatchObject({ ok: true, unchanged: true });
    expect(await counts(f.userId)).toEqual(before);
    expect((await current(f.userId)).workouts[0]!.exercises.slice(0, 2).map((slot) => [slot.group_id, slot.rest_seconds]))
      .toEqual([[null, 60], [null, 70]]);
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: before.version, round_rest: 45 });
    expect(await clearGroup(env.DB, f.userId, f.groupId, version)).toEqual({ ...cleared, replayed: true });
    expect((await current(f.userId)).workouts[0]!.exercises[0]!.group_id).toBe(f.groupId);
  });

  it('rejects invalid group values, nonadjacent members and unequal counts without writes', async () => {
    const f = await fixture(); const before = await counts(f.userId);
    for (const options of [{ round_rest: 1.5 }, { round_rest: -1 }, { round_rest: 0, transition_rest: -1 },
      { round_rest: 0, target_sets: 2.5 }, { round_rest: 0, order_index: -1 }]) {
      expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), {
        expected_version: f.tree.version, ...options,
      })).toMatchObject({ error: 'invalid_fields' });
    }
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, [f.ids[0]!, f.ids[2]!], {
      expected_version: f.tree.version, round_rest: 30,
    })).toMatchObject({ error: 'group_conflict', fields: ['order_index'] });
    expect(await counts(f.userId)).toEqual(before);
    await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[0] }, { target_sets: 4 });
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), {
      expected_version: f.tree.version + 1, round_rest: 30,
    })).toMatchObject({ error: 'group_conflict', fields: ['target_sets'] });
  });

  it('protects group-owned fields and rejects single-slot additions or moves that split a group', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    const before = await counts(f.userId);
    for (const patch of [{ target_sets: 4 }, { order_index: 3 }]) {
      expect(await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[0] }, patch))
        .toMatchObject({ error: 'group_conflict' });
    }
    for (const key of ['group_id', 'group_rest_seconds', 'group_transition_seconds']) {
      expect(await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[0] }, { [key]: null } as never))
        .toEqual({ error: 'unknown_fields', fields: [key] });
    }
    expect(await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[3] }, { order_index: 1 }))
      .toMatchObject({ error: 'group_conflict' });
    const { id, created_at, updated_at, ...slot } = f.day.exercises[3]!;
    expect(await addTemplateExercise(env.DB, f.tree.id, { ...slot, order_index: 1 })).toMatchObject({ error: 'group_conflict' });
    expect(await counts(f.userId)).toEqual(before);
    expect(await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[0] }, { cues: 'Smooth reps' }))
      .toMatchObject({ cues: 'Smooth reps', group_id: f.groupId });
    expect(await swapExercise(env.DB, f.userId, { template_exercise_id: f.ids[0], to_exercise: 'deadlift' }))
      .toMatchObject({ group_id: f.groupId });
  });

  it('moves the complete block and updates every member count atomically', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    const options = { expected_version: f.tree.version + 1, round_rest: 50, target_sets: 5, order_index: 2 };
    const moved = await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options);
    expect(moved).toMatchObject({ ok: true, target_sets: 5 });
    const slots = (await current(f.userId)).workouts[0]!.exercises;
    expect(slots.map((slot) => slot.id)).toEqual([f.ids[2], f.ids[3], f.ids[0], f.ids[1]]);
    expect(slots.slice(2).map((slot) => [slot.target_sets, slot.rest_seconds])).toEqual([[5, 60], [5, 70]]);
    const before = await counts(f.userId);
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), options)).toEqual({ ...moved, replayed: true });
    expect(await counts(f.userId)).toEqual(before);
  });

  it('normalizes a deleted group member and validates every write even for unrelated fields', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 3), { expected_version: f.tree.version, round_rest: 30 });
    await deleteTemplateExercise(env.DB, f.userId, { template_exercise_id: f.ids[0] });
    expect((await current(f.userId)).workouts[0]!.exercises.slice(0, 2).map((slot) => slot.group_id)).toEqual([f.groupId, f.groupId]);
    await env.DB.prepare('UPDATE template_exercises SET group_rest_seconds=31 WHERE id=?1').bind(f.ids[1]).run();
    const before = await counts(f.userId);
    expect(await updateExercise(env.DB, f.userId, { template_exercise_id: f.ids[1] }, { cues: 'Fix later' }))
      .toMatchObject({ error: 'group_conflict' });
    expect(await swapExercise(env.DB, f.userId, { template_exercise_id: f.ids[1], to_exercise: 'bench' }))
      .toMatchObject({ error: 'group_conflict' });
    expect(await dedupeDayOrderIndexes(env.DB, f.day.id)).toMatchObject({ error: 'group_conflict' });
    expect(await counts(f.userId)).toEqual(before);
    await deleteTemplateExercise(env.DB, f.userId, { template_exercise_id: f.ids[1] });
    expect((await current(f.userId)).workouts[0]!.exercises[0]).toMatchObject({ id: f.ids[2], group_id: null,
      group_rest_seconds: null, group_transition_seconds: null, rest_seconds: 80 });
  });

  it('preserves group serialization through rebuilds and rejects a split rebuild', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    let tree = await current(f.userId);
    const rebuilt = await updatePlanTree(env.DB, f.userId, rebuild(tree));
    expect(rebuilt).toHaveProperty('plan');
    tree = await current(f.userId);
    expect(tree.workouts[0]!.exercises[0]).toMatchObject({ group_id: f.groupId, group_rest_seconds: 30, group_transition_seconds: 0 });
    const legacy = rebuild(tree);
    for (const day of legacy.workouts) for (const slot of day.exercises) {
      delete slot.group_id; delete slot.group_rest_seconds; delete slot.group_transition_seconds;
    }
    expect(await updatePlanTree(env.DB, f.userId, legacy)).toHaveProperty('plan');
    tree = await current(f.userId);
    expect(tree.workouts[0]!.exercises[0]!.group_id).toBe(f.groupId);
    const split = rebuild(tree);
    [split.workouts[0]!.exercises[1], split.workouts[0]!.exercises[2]] = [split.workouts[0]!.exercises[2]!, split.workouts[0]!.exercises[1]!];
    const before = await counts(f.userId);
    expect(await updatePlanTree(env.DB, f.userId, split)).toMatchObject({ error: 'group_conflict' });
    expect(await counts(f.userId)).toEqual(before);
    const removal = rebuild(tree); removal.workouts[0]!.exercises.splice(0, 1);
    expect(await updatePlanTree(env.DB, f.userId, removal)).toHaveProperty('plan');
    expect((await current(f.userId)).workouts[0]!.exercises[0]!.group_id).toBeNull();
  });

  it('rejects singleton and cross-day group payloads before creating a plan document', async () => {
    const f = await fixture(); const before = await counts(f.userId);
    const payload = rebuild(f.tree);
    Object.assign(payload.workouts[0]!.exercises[0]!, { group_id: f.groupId, group_rest_seconds: 30, group_transition_seconds: 0 });
    expect(await updatePlanTree(env.DB, f.userId, payload)).toMatchObject({ error: 'group_conflict' });
    payload.workouts[0]!.exercises[1] = { ...payload.workouts[0]!.exercises[1]!, group_id: f.groupId, group_rest_seconds: 30, group_transition_seconds: 0 };
    payload.workouts[1]!.exercises = [0, 1].map(() => ({ ...payload.workouts[0]!.exercises[0]! }));
    expect(await updatePlanTree(env.DB, f.userId, payload)).toMatchObject({ error: 'group_conflict', fields: ['group_id'] });
    expect(await counts(f.userId)).toEqual(before);
  });

  it('restores grouped snapshots and treats old absent group columns as ungrouped', async () => {
    const f = await fixture(); const oldSnapshot = serializePlanSnapshot(f.tree);
    for (const day of oldSnapshot.workouts) for (const slot of day.exercises) {
      delete slot.group_id; delete slot.group_rest_seconds; delete slot.group_transition_seconds;
    }
    expect(parsePlanSnapshot(JSON.stringify(oldSnapshot))).toEqual(serializePlanSnapshot(f.tree));
    expect(comparePlanSnapshots(oldSnapshot, serializePlanSnapshot(f.tree)).changes).toEqual([]);
    await env.DB.prepare('UPDATE plan_snapshots SET document=?1 WHERE plan_id=?2 AND version=?3')
      .bind(JSON.stringify(oldSnapshot), f.tree.id, f.tree.version).run();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    const groupedVersion = f.tree.version + 1;
    await clearGroup(env.DB, f.userId, f.groupId, groupedVersion);
    expect(await restorePlanSnapshot(env.DB, f.userId, { plan_id: f.tree.id, snapshot_version: groupedVersion,
      expected_version: groupedVersion + 1, actor: 'ios' })).toMatchObject({ ok: true });
    expect((await current(f.userId)).workouts[0]!.exercises[0]!.group_id).toBe(f.groupId);
    const version = (await getActivePlan(env.DB, f.userId))!.version;
    expect(await restorePlanSnapshot(env.DB, f.userId, { plan_id: f.tree.id, snapshot_version: f.tree.version,
      expected_version: version, actor: 'ios' })).toMatchObject({ ok: true });
    expect((await current(f.userId)).workouts[0]!.exercises[0]!.group_id).toBeNull();
  });

  it('validates prescriptions during grouping and clearing and keeps adjustments in lockstep', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    expect(await adjustToday(env.DB, f.userId, 'reduce_volume', 'moderate', 'A')).toMatchObject({ no_op: false });
    expect((await current(f.userId)).workouts[0]!.exercises.slice(0, 2).map((slot) => slot.target_sets)).toEqual([2, 2]);
    await env.DB.prepare('UPDATE template_exercises SET target_reps=0 WHERE id=?1').bind(f.ids[0]).run();
    const before = await counts(f.userId);
    expect(await clearGroup(env.DB, f.userId, f.groupId, before.version)).toMatchObject({ error: 'invalid_fields', fields: ['target_reps'] });
    expect(await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: before.version, round_rest: 90 }))
      .toMatchObject({ error: 'invalid_fields', fields: ['target_reps'] });
    expect(await counts(f.userId)).toEqual(before);
  });

  it('deletes a whole grouped day and preserves other days', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    expect(await deleteWorkout(env.DB, f.userId, f.day.id, f.tree.version + 1)).toMatchObject({ ok: true });
    const tree = await current(f.userId);
    expect(tree.workouts.map((day) => day.name)).toEqual(['B']);
    expect(tree.workouts[0]!.exercises[0]!.group_id).toBeNull();
  });


  it('conflicts simultaneous different rewrites and acknowledges simultaneous identical retries once', async () => {
    const f = await fixture(); const before = await counts(f.userId);
    const results = await Promise.all([40, 50].map((round_rest) => setGroup(env.DB, f.userId, f.day.id,
      f.groupId, f.ids.slice(0, 2), { expected_version: before.version, round_rest })));
    expect(results.filter((result) => 'ok' in result)).toHaveLength(1);
    expect(results.filter((result) => 'conflict' in result)).toEqual([{ conflict: true, current_version: before.version + 1 }]);
    const options = { expected_version: before.version + 1, round_rest: 100 };
    const same = await Promise.all([0, 1].map(() => setGroup(env.DB, f.userId, f.day.id,
      f.groupId, f.ids.slice(0, 2), options)));
    expect(same.every((result) => 'ok' in result && result.version === before.version + 2)).toBe(true);
    expect(await counts(f.userId)).toEqual({ version: before.version + 2, audits: before.audits + 2,
      notes: before.notes + 2, snapshots: before.snapshots + 2 });
  });

  it('rejects orphan rest attributes in a full rebuild without discarding the invalid input', async () => {
    const f = await fixture(); const payload = rebuild(f.tree); const before = await counts(f.userId);
    payload.workouts[0]!.exercises[0]!.group_rest_seconds = 45;
    expect(await updatePlanTree(env.DB, f.userId, payload)).toMatchObject({ error: 'group_conflict', fields: ['group_id'] });
    expect(await counts(f.userId)).toEqual(before);
  });


  it('keeps scoped clear receipts retryable after day removal without permitting a wrong-day clear', async () => {
    const f = await fixture();
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    const version = f.tree.version + 1;
    const attrs = { actor: 'ios' as const, operation: 'ungroup_exercises' };
    expect(await clearGroup(env.DB, f.userId, f.groupId, version, attrs, f.tree.workouts[1]!.id))
      .toMatchObject({ error: 'group_conflict' });
    const cleared = await clearGroup(env.DB, f.userId, f.groupId, version, attrs, f.day.id);
    await deleteWorkout(env.DB, f.userId, f.day.id, version + 1);
    const before = await counts(f.userId);
    expect(await clearGroup(env.DB, f.userId, f.groupId, version, attrs, f.day.id)).toEqual({ ...cleared, replayed: true });
    expect(await clearGroup(env.DB, f.userId, f.groupId, version, attrs, f.tree.workouts[1]!.id))
      .toMatchObject({ error: 'group_conflict' });
    expect(await counts(f.userId)).toEqual(before);
  });


  it('requires an expected version for explicit group fields and every rebuild of a grouped plan', async () => {
    const f = await fixture();
    const payload = rebuild(f.tree);
    const { expected_version: _, ...unversioned } = payload;
    Object.assign(unversioned.workouts[0]!.exercises[0]!, { group_id: f.groupId, group_rest_seconds: 30, group_transition_seconds: 0 });
    Object.assign(unversioned.workouts[0]!.exercises[1]!, { group_id: f.groupId, group_rest_seconds: 30, group_transition_seconds: 0 });
    const beforeCreate = await counts(f.userId);
    expect(await updatePlanTree(env.DB, f.userId, unversioned)).toEqual({ error: 'invalid_fields', fields: ['expected_version'] });
    expect(await counts(f.userId)).toEqual(beforeCreate);
    await setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), { expected_version: f.tree.version, round_rest: 30 });
    const before = await counts(f.userId);
    for (const day of unversioned.workouts) for (const slot of day.exercises) {
      slot.group_id = null; slot.group_rest_seconds = null; slot.group_transition_seconds = null;
    }
    expect(await updatePlanTree(env.DB, f.userId, unversioned)).toEqual({ error: 'invalid_fields', fields: ['expected_version'] });
    for (const day of unversioned.workouts) for (const slot of day.exercises) {
      delete slot.group_id; delete slot.group_rest_seconds; delete slot.group_transition_seconds;
    }
    expect(await updatePlanTree(env.DB, f.userId, unversioned)).toEqual({ error: 'invalid_fields', fields: ['expected_version'] });
    expect(await updatePlanTree(env.DB, f.userId, { workouts: [] })).toEqual({ error: 'invalid_fields', fields: ['expected_version'] });
    expect(await counts(f.userId)).toEqual(before);
  });

  it('rolls back group fields, version, audit and snapshot when the required note fails', async () => {
    const f = await fixture(); const before = await counts(f.userId);
    await env.DB.prepare(`CREATE TRIGGER reject_group_note BEFORE INSERT ON notes
      WHEN NEW.user_id='${f.userId}' BEGIN SELECT RAISE(ABORT,'forced_group_note_failure'); END`).run();
    try {
      await expect(setGroup(env.DB, f.userId, f.day.id, f.groupId, f.ids.slice(0, 2), {
        expected_version: f.tree.version, round_rest: 30,
      }, attribution)).rejects.toThrow('forced_group_note_failure');
      expect(await counts(f.userId)).toEqual(before);
      expect((await current(f.userId)).workouts[0]!.exercises[0]!.group_id).toBeNull();
    } finally { await env.DB.prepare('DROP TRIGGER reject_group_note').run(); }
  });
});
