/** One compatibility cycle for released clients and existing coach conversations.
 * This module is the only wire boundary that creates deprecated workout keys.
 * Never parse/rewrite serialized audit arguments, snapshots, notes or metadata. */
const legacyKeys: Readonly<Record<string, string>> = {
  workout_id: 'day_template_id', workouts: 'days', plan_workouts: 'plan_days',
};
const opaqueKeys = new Set(['meta', 'progression', 'args', 'result', 'document', 'notes', 'runner_targets']);

export function workoutWire<T>(value: T): T {
  if (Array.isArray(value)) return value.map(workoutWire) as T;
  if (!value || typeof value !== 'object') return value;
  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    result[key] = opaqueKeys.has(key) ? child : workoutWire(child);
    const legacy = legacyKeys[key];
    if (legacy) result[legacy] = result[key];
  }
  return result as T;
}

function sameJSON(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) && left.length === right.length
      && left.every((item, index) => sameJSON(item, right[index]));
  }
  const a = left as Record<string, unknown>;
  const b = right as Record<string, unknown>;
  return Object.keys(a).length === Object.keys(b).length
    && Object.keys(a).every((key) => Object.hasOwn(b, key) && sameJSON(a[key], b[key]));
}

/** Accept either spelling, rejecting contradictory dual-key requests before a
 * mutation. Only defined workout identity/tree fields are normalized. */
export function workoutInput(value: Record<string, unknown>): Record<string, unknown> {
  const result = { ...value };
  for (const [canonical, legacy] of Object.entries(legacyKeys)) {
    if (!Object.hasOwn(result, legacy)) continue;
    if (Object.hasOwn(result, canonical) && !sameJSON(result[canonical], result[legacy])) {
      throw new Error(`conflicting_workout_fields:${canonical}`);
    }
    result[canonical] = result[legacy];
    delete result[legacy];
  }
  // update_exercise/delete_exercise selectors can carry an explicit workout id.
  if (result.target && typeof result.target === 'object' && !Array.isArray(result.target)) {
    result.target = workoutInput(result.target as Record<string, unknown>);
  }
  return result;
}

/** Account export historically called the table collection day_templates,
 * whereas plan responses called it days. Retain that distinct v2 field. */
export function workoutExportWire(value: Record<string, unknown>): Record<string, unknown> {
  const result = workoutWire(value);
  const training = result.training as Record<string, unknown>;
  return { ...result, training: { ...training, day_templates: training.workouts } };
}
