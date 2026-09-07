import { describe, expect, it } from 'vitest';
import {
  comparePlanSnapshots,
  type PlanSnapshotDay,
  type PlanSnapshotDocument,
  type PlanSnapshotExercise,
} from '../src/planSnapshots';

function slot(id: string, exerciseId: string, overrides: Partial<PlanSnapshotExercise> = {}): PlanSnapshotExercise {
  return {
    id, exercise_id: exerciseId, order_index: 0, target_sets: 3, target_reps: 5,
    target_reps_max: null, target_rpe: null, rest_seconds: 120, target_weight: 100,
    target_duration_s: null, progression: null, cues: null, is_warmup: 0, ...overrides,
  };
}

function day(id: string, name: string, label: string | null, exercises: PlanSnapshotExercise[]): PlanSnapshotDay {
  return { id, name, day_label: label, order_index: 0, notes: null, exercises };
}

function document(days: PlanSnapshotDay[], schedule: Record<string, string | null> = {}): PlanSnapshotDocument {
  return {
    schema_version: 1,
    plan: { name: 'Training', meta: JSON.stringify({ schedule: { week: schedule } }) },
    days,
  };
}

describe('plan snapshot comparison', () => {
  it('matches rebuilt days and repeated exercise occurrences while reporting prescription changes', () => {
    const before = document([
      day('old-day', 'Strength', 'A', [
        slot('old-bench-1', 'bench'),
        slot('old-bench-2', 'bench', { order_index: 1, target_weight: 80 }),
      ]),
    ], { mon: 'old-day' });
    const after = document([
      day('new-day', 'Strength', 'A', [
        slot('new-bench-1', 'bench'),
        slot('new-bench-2', 'bench', { order_index: 1, target_weight: 85 }),
      ]),
    ], { mon: 'new-day' });

    const result = comparePlanSnapshots(before, after, { exerciseNames: { bench: 'Bench Press' } });

    expect(result.summary).toMatchObject({
      schedule_days: 0, days_added: 0, days_removed: 0,
      exercises_added: 0, exercises_removed: 0, exercises_changed: 1,
    });
    expect(result.changes).toHaveLength(1);
    expect(result.changes[0]).toMatchObject({
      kind: 'exercise', path: 'Strength · Bench Press',
      before: { id: 'old-bench-2', exercise_id: 'bench', exercise_name: 'Bench Press', target_weight: 80 },
      after: { id: 'new-bench-2', exercise_id: 'bench', exercise_name: 'Bench Press', target_weight: 85 },
    });
  });

  it('shows full prescriptions for added and removed workouts', () => {
    const removed = day('old', 'Pull', 'B', [slot('row-slot', 'row', { target_sets: 4, target_reps: 8 })]);
    const added = day('new', 'Conditioning', 'C', [slot('bike-slot', 'bike', { target_duration_s: 900 })]);
    const result = comparePlanSnapshots(document([removed]), document([added]), {
      exerciseNames: new Map([['row', 'Cable Row'], ['bike', 'Stationary Bike']]),
    });

    expect(result.summary).toMatchObject({ days_added: 1, days_removed: 1, exercises_added: 1, exercises_removed: 1 });
    expect(result.changes).toEqual(expect.arrayContaining([
      expect.objectContaining({
        path: 'Workout · Pull',
        before: expect.objectContaining({
          day_id: 'old', exercises: [expect.objectContaining({ exercise_id: 'row', exercise_name: 'Cable Row', target_sets: 4 })],
        }),
      }),
      expect.objectContaining({
        path: 'Workout · Conditioning',
        after: expect.objectContaining({
          day_id: 'new', exercises: [expect.objectContaining({ exercise_id: 'bike', exercise_name: 'Stationary Bike', target_duration_s: 900 })],
        }),
      }),
    ]));
  });

  it('renders changed schedule assignments with workout names and canonical IDs', () => {
    const pull = day('pull-id', 'Pull', 'P', []);
    const legs = day('legs-id', 'Legs', 'L', []);
    const result = comparePlanSnapshots(
      document([pull, legs], { tue: 'pull-id' }),
      document([pull, legs], { tue: 'legs-id' }),
    );

    expect(result.changes).toContainEqual({
      kind: 'schedule', path: 'Weekly schedule · tue',
      before: { day_id: 'pull-id', day_name: 'Pull', day_label: 'P' },
      after: { day_id: 'legs-id', day_name: 'Legs', day_label: 'L' },
    });
  });

  it('does not guess a match when day labels and names are ambiguous', () => {
    const before = document([
      day('old-1', 'Strength', 'A', [slot('one', 'bench')]),
      day('old-2', 'Strength', 'A', [slot('two', 'row')]),
    ]);
    const after = document([
      day('new-1', 'Strength', 'A', [slot('three', 'bench')]),
      day('new-2', 'Strength', 'A', [slot('four', 'row')]),
    ]);

    const result = comparePlanSnapshots(before, after);
    expect(result.summary).toMatchObject({ days_added: 2, days_removed: 2, exercises_added: 2, exercises_removed: 2 });
  });
});
