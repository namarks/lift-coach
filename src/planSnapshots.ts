import type { PlanTree } from './types';
import { parsePlanMeta } from './types';

export interface PlanSnapshotExercise {
  id: string;
  exercise_id: string;
  order_index: number;
  target_sets: number;
  target_reps: number;
  target_reps_max: number | null;
  target_rpe: number | null;
  rest_seconds: number;
  target_weight: number | null;
  target_duration_s: number | null;
  progression: string | null;
  cues: string | null;
  is_warmup: number;
}

export interface PlanSnapshotDay {
  id: string;
  name: string;
  day_label: string | null;
  order_index: number;
  notes: string | null;
  exercises: PlanSnapshotExercise[];
}

export interface PlanSnapshotDocument {
  schema_version: 1;
  plan: { name: string; meta: string | null };
  days: PlanSnapshotDay[];
}

export interface PlanSnapshotChange {
  kind: 'plan' | 'schedule' | 'day' | 'exercise';
  path: string;
  before: unknown;
  after: unknown;
}

export interface PlanSnapshotSummary {
  plan_fields: number;
  schedule_days: number;
  days_added: number;
  days_removed: number;
  days_changed: number;
  exercises_added: number;
  exercises_removed: number;
  exercises_changed: number;
}

export function serializePlanSnapshot(tree: PlanTree): PlanSnapshotDocument {
  return {
    schema_version: 1,
    plan: { name: tree.name, meta: tree.meta },
    days: tree.days.map((day) => ({
      id: day.id,
      name: day.name,
      day_label: day.day_label,
      order_index: day.order_index,
      notes: day.notes,
      exercises: day.exercises.map((slot) => ({
        id: slot.id,
        exercise_id: slot.exercise_id,
        order_index: slot.order_index,
        target_sets: slot.target_sets,
        target_reps: slot.target_reps,
        target_reps_max: slot.target_reps_max,
        target_rpe: slot.target_rpe,
        rest_seconds: slot.rest_seconds,
        target_weight: slot.target_weight,
        target_duration_s: slot.target_duration_s,
        progression: slot.progression,
        cues: slot.cues,
        is_warmup: slot.is_warmup,
      })),
    })),
  };
}

export function parsePlanSnapshot(raw: string): PlanSnapshotDocument {
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_plan_snapshot');
  const doc = value as Partial<PlanSnapshotDocument>;
  if (doc.schema_version !== 1 || !doc.plan || !Array.isArray(doc.days)) {
    throw new Error('unsupported_plan_snapshot');
  }
  return doc as PlanSnapshotDocument;
}

const stable = (value: unknown): string => JSON.stringify(value);

export function comparePlanSnapshots(
  before: PlanSnapshotDocument,
  after: PlanSnapshotDocument,
): { changes: PlanSnapshotChange[]; summary: PlanSnapshotSummary } {
  const changes: PlanSnapshotChange[] = [];
  const summary: PlanSnapshotSummary = {
    plan_fields: 0, schedule_days: 0, days_added: 0, days_removed: 0,
    days_changed: 0, exercises_added: 0, exercises_removed: 0, exercises_changed: 0,
  };
  if (before.plan.name !== after.plan.name) {
    changes.push({ kind: 'plan', path: 'name', before: before.plan.name, after: after.plan.name });
    summary.plan_fields++;
  }
  const parsedBeforeMeta = parsePlanMeta(before.plan.meta);
  const parsedAfterMeta = parsePlanMeta(after.plan.meta);
  const beforeMeta = { ...parsedBeforeMeta, schedule: undefined };
  const afterMeta = { ...parsedAfterMeta, schedule: undefined };
  if (stable(beforeMeta) !== stable(afterMeta)) {
    changes.push({ kind: 'plan', path: 'meta', before: beforeMeta, after: afterMeta });
    summary.plan_fields++;
  }
  for (const weekday of ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const) {
    const a = parsedBeforeMeta.schedule.week[weekday];
    const b = parsedAfterMeta.schedule.week[weekday];
    if (a !== b) {
      changes.push({ kind: 'schedule', path: `schedule.${weekday}`, before: a, after: b });
      summary.schedule_days++;
    }
  }
  const beforeDays = new Map(before.days.map((day) => [day.id, day]));
  const afterDays = new Map(after.days.map((day) => [day.id, day]));
  for (const [id, day] of beforeDays) {
    if (!afterDays.has(id)) {
      changes.push({ kind: 'day', path: `days.${id}`, before: day.name, after: null });
      summary.days_removed++;
    }
  }
  for (const [id, day] of afterDays) {
    const prior = beforeDays.get(id);
    if (!prior) {
      changes.push({ kind: 'day', path: `days.${id}`, before: null, after: day.name });
      summary.days_added++;
      continue;
    }
    const beforeFields = { name: prior.name, day_label: prior.day_label, order_index: prior.order_index, notes: prior.notes };
    const afterFields = { name: day.name, day_label: day.day_label, order_index: day.order_index, notes: day.notes };
    if (stable(beforeFields) !== stable(afterFields)) {
      changes.push({ kind: 'day', path: `days.${id}`, before: beforeFields, after: afterFields });
      summary.days_changed++;
    }
    const oldSlots = new Map(prior.exercises.map((slot) => [slot.id, slot]));
    const newSlots = new Map(day.exercises.map((slot) => [slot.id, slot]));
    for (const [slotId, slot] of oldSlots) if (!newSlots.has(slotId)) {
      changes.push({ kind: 'exercise', path: `days.${id}.exercises.${slotId}`, before: slot, after: null });
      summary.exercises_removed++;
    }
    for (const [slotId, slot] of newSlots) {
      const old = oldSlots.get(slotId);
      if (!old) {
        changes.push({ kind: 'exercise', path: `days.${id}.exercises.${slotId}`, before: null, after: slot });
        summary.exercises_added++;
      } else if (stable(old) !== stable(slot)) {
        changes.push({ kind: 'exercise', path: `days.${id}.exercises.${slotId}`, before: old, after: slot });
        summary.exercises_changed++;
      }
    }
  }
  return { changes, summary };
}
