import { getActivePlan, getPlanTree, preparePlanWriteStart, preparePlanWriteFinish,
  validateExercisePrescription, type PlanWriteAttribution, type PlanVersionConflict,
  type PrescriptionValidationError } from './db';
import { emptyExerciseGroup, isGroupId, validateExerciseGroups, validatePlanExerciseGroups, type GroupConflict } from './exerciseGroups';
import { runWorkoutWriteBatch } from './workout-write-fence';
import type { PlanRow, TemplateExerciseRow } from './types';

export interface ExerciseGroupAcknowledgement {
  ok: true;
  plan_id: string;
  version: number;
  group_id: string;
  day_id: string | null;
  members: string[];
  round_rest: number | null;
  transition_rest: number | null;
  target_sets: number | null;
  cleared: boolean;
  unchanged?: true;
  replayed?: true;
}
export type ExerciseGroupResult = ExerciseGroupAcknowledgement | PlanVersionConflict
  | PrescriptionValidationError | GroupConflict | { error: 'no_active_plan' | 'day_not_found' };
export interface SetExerciseGroupOptions {
  expected_version: number;
  round_rest: number;
  transition_rest?: number;
  target_sets?: number;
  /** Destination for the complete member block in the resulting day. */
  order_index?: number;
}

async function receipt(db: D1Database, userId: string, actor: string, key: string): Promise<ExerciseGroupAcknowledgement | null> {
  const row = await db.prepare(
    `SELECT result FROM audit_log WHERE user_id=?1 AND actor=?2 AND json_valid(result)
      AND json_extract(CASE WHEN json_valid(result) THEN result ELSE '{}' END,'$.exercise_group_receipt')=?3 LIMIT 1`,
  ).bind(userId, actor, key).first<{ result: string }>();
  if (!row) return null;
  const { exercise_group_receipt: _, ...result } = JSON.parse(row.result) as ExerciseGroupAcknowledgement & { exercise_group_receipt: string };
  return { ...result, replayed: true };
}

async function commitGroup(
  db: D1Database, plan: PlanRow, changed: readonly TemplateExerciseRow[],
  result: ExerciseGroupAcknowledgement, key: string, attribution: PlanWriteAttribution,
): Promise<ExerciseGroupResult> {
  const nonce = crypto.randomUUID();
  const ts = Date.now();
  const statements = preparePlanWriteStart(db, plan, attribution, ts, nonce);
  for (const slot of changed) statements.push(db.prepare(
    `UPDATE template_exercises SET group_id=?2,group_rest_seconds=?3,group_transition_seconds=?4,
       target_sets=?5,order_index=?6,updated_at=?7 WHERE id=?1
       AND EXISTS (SELECT 1 FROM plans p JOIN day_templates d ON d.plan_id=p.id
         WHERE d.id=template_exercises.day_template_id AND p.id=?8 AND p.user_id=?9
           AND p.version=-?10 AND p.plan_write_nonce=?11)`,
  ).bind(slot.id, slot.group_id ?? null, slot.group_rest_seconds ?? null,
    slot.group_transition_seconds ?? null, slot.target_sets, slot.order_index, ts,
    plan.id, plan.user_id, plan.version, nonce));
  const versionIndex = statements.length;
  statements.push(...preparePlanWriteFinish(db, plan, {
    ...attribution,
    note: attribution.note ?? (result.cleared ? 'Ungrouped exercises.' : `Grouped ${result.members.length} exercises for ${result.target_sets} rounds.`),
    result: { ...result, exercise_group_receipt: key },
  }, ts, nonce));
  const rows = await runWorkoutWriteBatch(db, statements);
  if ((rows[0]?.meta.changes ?? 0) !== 1 || !rows[versionIndex]?.results[0]) {
    // A concurrent copy may have committed the same request while we read.
    const replay = await receipt(db, plan.user_id, attribution.actor, key);
    if (replay) return replay;
    const latest = await getActivePlan(db, plan.user_id);
    return { conflict: true, current_version: latest?.version ?? plan.version };
  }
  return result;
}

export async function setGroup(
  db: D1Database, userId: string, dayId: string, groupId: string, memberIds: string[],
  options: SetExerciseGroupOptions,
  attribution: PlanWriteAttribution = { actor: 'system', operation: 'group_exercises' },
): Promise<ExerciseGroupResult> {
  const invalid = new Set<string>();
  if (!isGroupId(groupId)) invalid.add('group_id');
  if (!Number.isSafeInteger(options.expected_version) || options.expected_version < 1) invalid.add('expected_version');
  if (!Number.isSafeInteger(options.round_rest) || options.round_rest < 0) invalid.add('round_rest');
  const transition = options.transition_rest === undefined ? 0 : options.transition_rest;
  if (!Number.isSafeInteger(transition) || transition < 0) invalid.add('transition_rest');
  if (options.order_index !== undefined && (!Number.isSafeInteger(options.order_index) || options.order_index < 0)) invalid.add('order_index');
  if (options.target_sets !== undefined && (!Number.isSafeInteger(options.target_sets) || options.target_sets < 1)) invalid.add('target_sets');
  if (!Array.isArray(memberIds) || memberIds.some((id) => typeof id !== 'string') || new Set(memberIds).size !== memberIds.length || memberIds.length < 2) invalid.add('members');
  if (invalid.size) return { error: 'invalid_fields', fields: [...invalid].sort() };
  const plan = await getActivePlan(db, userId);
  if (!plan) return { error: 'no_active_plan' };
  const key = JSON.stringify({ kind: 'set', plan_id: plan.id, day_id: dayId, group_id: groupId,
    members: memberIds, expected_version: options.expected_version,
    round_rest: options.round_rest, transition_rest: transition, target_sets: options.target_sets ?? null, order_index: options.order_index ?? null });
  const replay = await receipt(db, userId, attribution.actor, key);
  if (replay) return replay;
  if (plan.version !== options.expected_version) return { conflict: true, current_version: plan.version };
  const tree = await getPlanTree(db, userId);
  if (!tree || tree.id !== plan.id || tree.version !== plan.version) {
    return { conflict: true, current_version: tree?.version ?? plan.version };
  }
  const day = tree.days.find((day) => day.id === dayId);
  if (!day) return { error: 'day_not_found' };
  if (tree.days.some((day) => day.id !== dayId && day.exercises.some((slot) => slot.group_id === groupId))) {
    return { error: 'group_conflict', fields: ['group_id'] };
  }
  const selected = memberIds.map((id) => day.exercises.find((slot) => slot.id === id));
  if (selected.some((slot) => !slot)) return { error: 'group_conflict', fields: ['members'] };
  if (selected.some((slot) => slot!.group_id != null && slot!.group_id !== groupId)) {
    return { error: 'group_conflict', fields: ['group_id'] };
  }
  const memberSet = new Set(memberIds);
  const positions = day.exercises.filter((slot) => memberSet.has(slot.id)).map((slot) => slot.order_index).sort((a, b) => a - b);
  let proposed = day.exercises.map((slot) => {
    const index = memberIds.indexOf(slot.id);
    if (index !== -1) return { ...slot, group_id: groupId, group_rest_seconds: options.round_rest,
      group_transition_seconds: transition, target_sets: options.target_sets ?? slot.target_sets,
      order_index: positions[index]! };
    return slot.group_id === groupId ? { ...slot, ...emptyExerciseGroup } : slot;
  });
  if (options.order_index !== undefined) {
    const others = proposed.filter((slot) => !memberSet.has(slot.id));
    const members = memberIds.map((id) => proposed.find((slot) => slot.id === id)!);
    const target = Math.min(options.order_index, others.length);
    proposed = [...others.slice(0, target), ...members, ...others.slice(target)]
      .map((slot, index) => ({ ...slot, order_index: index }));
  }
  const groupInvalid = validateExerciseGroups(proposed);
  if (groupInvalid) return groupInvalid;
  for (const slot of proposed.filter((slot) => memberSet.has(slot.id) || day.exercises.find((old) => old.id === slot.id)?.group_id === groupId)) {
    let progression: unknown;
    try { progression = slot.progression == null ? null : JSON.parse(slot.progression); }
    catch { return { error: 'invalid_fields', fields: ['progression'] }; }
    const invalid = validateExercisePrescription({ ...slot, progression }, { modality: slot.exercise_modality });
    if (invalid) return invalid;
  }
  const changed = proposed.filter((slot) => {
    const old = day.exercises.find((old) => old.id === slot.id)!;
    return slot.group_id !== old.group_id || slot.group_rest_seconds !== old.group_rest_seconds
      || slot.group_transition_seconds !== old.group_transition_seconds || slot.target_sets !== old.target_sets
      || slot.order_index !== old.order_index;
  });
  const result: ExerciseGroupAcknowledgement = { ok: true, plan_id: plan.id,
    version: plan.version + (changed.length ? 1 : 0), group_id: groupId, day_id: dayId,
    members: memberIds, round_rest: options.round_rest, transition_rest: transition,
    target_sets: proposed.find((slot) => slot.id === memberIds[0])!.target_sets, cleared: false };
  if (!changed.length) return { ...result, unchanged: true };
  return commitGroup(db, plan, changed, result, key, attribution);
}

export async function clearGroup(
  db: D1Database, userId: string, groupId: string, expectedVersion: number,
  attribution: PlanWriteAttribution = { actor: 'system', operation: 'ungroup_exercises' },
  scopeDayId?: string,
): Promise<ExerciseGroupResult> {
  const fields: string[] = [];
  if (!isGroupId(groupId)) fields.push('group_id');
  if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 1) fields.push('expected_version');
  if (fields.length) return { error: 'invalid_fields', fields };
  const plan = await getActivePlan(db, userId);
  if (!plan) return { error: 'no_active_plan' };
  const key = JSON.stringify({ kind: 'clear', plan_id: plan.id, group_id: groupId, expected_version: expectedVersion });
  const replay = await receipt(db, userId, attribution.actor, key);
  if (replay) return scopeDayId !== undefined && replay.day_id !== scopeDayId
    ? { error: 'group_conflict', fields: ['group_id'] } : replay;
  if (plan.version !== expectedVersion) return { conflict: true, current_version: plan.version };
  const tree = await getPlanTree(db, userId);
  if (!tree || tree.id !== plan.id || tree.version !== plan.version) return { conflict: true, current_version: tree?.version ?? plan.version };
  if (scopeDayId !== undefined && !tree.days.some((day) => day.id === scopeDayId)) return { error: 'day_not_found' };
  const members = tree.days.flatMap((day) => day.exercises.filter((slot) => slot.group_id === groupId));
  if (scopeDayId !== undefined && members.some((slot) => slot.day_template_id !== scopeDayId)) {
    return { error: 'group_conflict', fields: ['group_id'] };
  }
  const changed = members.map((slot) => ({ ...slot, ...emptyExerciseGroup }));
  for (const slot of changed) {
    let progression: unknown;
    try { progression = slot.progression == null ? null : JSON.parse(slot.progression); }
    catch { return { error: 'invalid_fields', fields: ['progression'] }; }
    const invalid = validateExercisePrescription({ ...slot, progression }, { modality: slot.exercise_modality });
    if (invalid) return invalid;
  }
  const candidate = tree.days.map((day) => ({ ...day, exercises: day.exercises.map((slot) => slot.group_id === groupId ? { ...slot, ...emptyExerciseGroup } : slot) }));
  const groupInvalid = validatePlanExerciseGroups(candidate);
  if (groupInvalid) return groupInvalid;
  const result: ExerciseGroupAcknowledgement = { ok: true, plan_id: plan.id,
    version: plan.version + (changed.length ? 1 : 0), group_id: groupId,
    day_id: members[0]?.day_template_id ?? scopeDayId ?? null, members: [], round_rest: null,
    transition_rest: null, target_sets: null, cleared: true };
  if (!changed.length) return { ...result, unchanged: true };
  return commitGroup(db, plan, changed, result, key, attribution);
}
