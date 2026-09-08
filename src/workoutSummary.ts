import { metricCohorts, type MetricExercise, type MetricSet } from './metrics';

export type SummarySet = MetricSet & {
  id: string; template_exercise_id: string | null; is_warmup: number;
  deleted_at: number | null; rpe: number | null;
};
export type SummaryExercise = MetricExercise & { id: string; name: string };
export interface RunnerTarget {
  slot_id: string; exercise_id: string; name: string; is_warmup: number; is_timed: number;
  sets: number; reps: number; reps_max: number | null; weight: number | null;
  duration_s: number | null; rpe: number | null;
}
export interface RunnerTargetSnapshot {
  version: 1; captured_at: number; plan_version: number; slots: RunnerTarget[];
}

export function parseRunnerTargets(raw: string | null | undefined): RunnerTargetSnapshot | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as RunnerTargetSnapshot;
    return value.version === 1 && Array.isArray(value.slots) ? value : null;
  } catch { return null; }
}

/** One completion policy, fed exclusively by persisted rows. The app renders
 * this result; history and MCP use this same projection. No body-mass/e1RM
 * proxy is introduced for bodyweight work. */
export function summarizeWorkout(
  session: { id: string; date: string; attempt: number; status: string },
  sets: SummarySet[], previousBests: MetricSet[], exercises: SummaryExercise[],
  targets: RunnerTargetSnapshot | null,
) {
  const live = sets.filter((set) => set.deleted_at == null && set.is_warmup === 0);
  const cohorts = exercises.flatMap((exercise) => metricCohorts(
    live.filter((set) => set.exercise_id === exercise.id), exercise)
    .map((cohort) => ({ ...cohort, name: exercise.name })));
  const previous = exercises.flatMap((exercise) => metricCohorts(
    previousBests.filter((set) => set.exercise_id === exercise.id), exercise));
  const records = session.status !== 'completed' ? [] : cohorts.flatMap((cohort) => {
    const old = previous.find((candidate) => candidate.key === cohort.key);
    const value = cohort.best_duration_s ?? cohort.best_reps ?? 0;
    const prior = old?.best_duration_s ?? old?.best_reps;
    // An initial baseline or a different assistance/load condition is not a PR.
    return prior != null && value > prior ? [{
      exercise_id: cohort.exercise_id, name: cohort.name, weight: cohort.weight,
      unit: cohort.unit, modality: cohort.modality, laterality: cohort.laterality,
      load_mode: cohort.load_mode, metric: cohort.metric, value, previous: prior,
    }] : [];
  });
  const targetResults = (targets?.slots ?? []).filter((target) => target.is_warmup === 0).map((target) => {
    const actual = live.filter((set) => set.template_exercise_id === target.slot_id
      && set.exercise_id === target.exercise_id && set.is_timed === target.is_timed);
    // Plan rebuilds detach old slot foreign keys. Do not turn that loss of
    // attribution into a false missed-target claim.
    const comparisonAvailable = !live.some((set) => set.exercise_id === target.exercise_id
      && set.template_exercise_id == null && set.is_timed === target.is_timed);
    const changed = actual.filter((set) =>
      (target.weight != null && set.weight !== target.weight)
      || (target.is_timed === 1
        ? (set.duration_s ?? set.reps) !== (target.duration_s ?? target.reps)
        : set.reps < target.reps || set.reps > (target.reps_max ?? target.reps))
      || (target.rpe != null && set.rpe != null && set.rpe !== target.rpe)).length;
    const below = actual.filter((set) => target.is_timed === 1
      ? (set.duration_s ?? set.reps) < (target.duration_s ?? target.reps)
      : set.reps < target.reps).length;
    return { ...target, comparison_available: comparisonAvailable, actual_sets: actual.length, missed_sets: Math.max(0, target.sets - actual.length),
      changed_sets: changed, below_target_sets: below };
  });
  const volumes = cohorts.map((cohort) => cohort.tonnage).filter((volume): volume is number => volume != null);
  return {
    version: 1 as const, session_id: session.id, date: session.date, attempt: session.attempt,
    final: session.status === 'completed', working_sets: live.length,
    total_reps: cohorts.reduce((sum, cohort) => sum + (cohort.total_reps ?? 0), 0),
    external_load_volume: volumes.length ? volumes.reduce((sum, volume) => sum + volume, 0) : null,
    cohorts: cohorts.map((cohort) => ({ exercise_id: cohort.exercise_id, name: cohort.name,
      weight: cohort.weight, unit: cohort.unit, modality: cohort.modality, laterality: cohort.laterality,
      load_mode: cohort.load_mode, metric: cohort.metric, value: cohort.best_duration_s ?? cohort.best_reps ?? 0,
      set_count: cohort.set_count })),
    records, targets_available: targets != null, targets_captured_at: targets?.captured_at ?? null,
    targets: targetResults,
  };
}
export type WorkoutSummary = ReturnType<typeof summarizeWorkout>;
