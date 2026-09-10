import { metricCohorts, positiveSetTonnage } from './metrics';
import type { SummaryExercise, SummarySet } from './workoutSummary';

export type CoachingSet = SummarySet & { session_id: string; logged_at: number };
export type CoachingExercise = SummaryExercise & { primary_muscle: string };
export type CoachingSession = {
  id: string; date: string; status: string; notes?: string | null; perceived_fatigue?: number | null;
};

/** Presentation only. Raw logs remain authoritative; no effort or body mass is inferred. */
export function coachingSession(session: CoachingSession, sets: CoachingSet[], catalog: CoachingExercise[]) {
  const live = sets.filter(s => s.session_id === session.id && !s.is_warmup && s.deleted_at == null)
    .sort((a, b) => a.logged_at - b.logged_at || a.id.localeCompare(b.id));
  const cohorts = catalog.flatMap(ex => metricCohorts(live.filter(s => s.exercise_id === ex.id), ex));
  const representativeIDs = new Set(cohorts.map(c => c.top.id));
  // One best observed rep/hold set per exact comparable condition, not a PR.
  // Unknown catalog rows remain raw examples rather than fabricated cohorts.
  const representatives = live.filter(s => representativeIDs.has(s.id) || !catalog.some(e => e.id === s.exercise_id));
  const keySets = representatives.map(s => {
    const ex = catalog.find(e => e.id === s.exercise_id);
    const timed = s.is_timed === 1;
    const signed = ex?.modality === 'bw' || ex?.modality === 'timed';
    const unit = ex?.modality === 'cardio' ? null : ex?.unit === 'sec' ? 'lb' : ex?.unit ?? null;
    const load = ex?.modality === 'cardio' ? null : s.weight;
    const condition = load == null ? 'unavailable' : !ex ? 'unknown'
      : signed ? load < 0 ? 'assistance' : load > 0 ? 'added' : 'bodyweight' : 'external';
    const reps = timed ? null : s.reps;
    const duration = timed ? s.duration_s ?? s.reps : null;
    const loadLabel = load == null ? '' : condition === 'bodyweight' ? 'bodyweight'
      : `${condition === 'assistance' ? Math.abs(load) : load} ${unit ?? 'unit unknown'}${condition === 'assistance' ? ' assistance' : condition === 'added' ? ' added' : ''}`;
    const label = `${ex?.name ?? s.exercise_id}: ${timed ? `${duration}s` : `${reps} reps`}`
      + (ex?.laterality === 'unilateral' ? ' per side' : '')
      + (loadLabel ? ` · ${loadLabel}` : '')
      + (ex?.load_mode === 'per_hand' ? ' each hand' : '')
      + (s.rpe == null ? '' : ` · RPE ${s.rpe}`);
    return { id: s.id, exercise_id: s.exercise_id, name: ex?.name ?? null,
      unit, modality: ex?.modality ?? null, laterality: ex?.laterality ?? null,
      load_mode: ex?.load_mode ?? null, weight: load, load_condition: condition,
      reps, duration_s: duration, is_timed: timed, rpe: s.rpe, label };
  });
  const muscles = [...new Set(live.map(s => catalog.find(e => e.id === s.exercise_id)?.primary_muscle ?? 'unknown'))].sort();
  const volumes = new Map<string, { value: number; sets: number }>();
  for (const s of live) {
    const ex = catalog.find(e => e.id === s.exercise_id);
    if (!ex || ex.modality === 'cardio' || ex.unit === 'sec') continue;
    const value = positiveSetTonnage(s, ex);
    if (value == null) continue;
    const old = volumes.get(ex.unit) ?? { value: 0, sets: 0 };
    volumes.set(ex.unit, { value: old.value + value, sets: old.sets + 1 });
  }
  return {
    id: session.id, date: session.date, status: session.status,
    notes: session.notes ?? null, perceived_fatigue: session.perceived_fatigue ?? null,
    logged_working_sets: live.length, sets_with_effort: live.filter(s => s.rpe != null).length,
    primary_muscle_sets: muscles.map(muscle => ({ muscle,
      logged_working_sets: live.filter(s => (catalog.find(e => e.id === s.exercise_id)?.primary_muscle ?? 'unknown') === muscle).length })),
    external_load_volume: [...volumes].sort(([a], [b]) => a.localeCompare(b))
      .map(([unit, v]) => ({ unit, value: v.value, contributing_sets: v.sets })),
    // Keep the legacy string array, now carrying explicit semantics.
    key_sets: keySets.map(s => s.label), sets: keySets,
    comparable_cohorts: cohorts.map(c => ({ exercise_id: c.exercise_id, weight: c.weight, unit: c.unit,
        laterality: c.laterality, load_mode: c.load_mode, is_timed: c.is_timed,
        best_reps: c.best_reps, best_duration_s: c.best_duration_s, set_count: c.set_count })),
  };
}

/** Retain authored values, including freeform stress settings; do not interpret them. */
export function coachingPlanMeta(raw: string | null) {
  let meta: Record<string, unknown> = {};
  try { const parsed = JSON.parse(raw ?? '{}'); if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) meta = parsed; } catch { /* unknown */ }
  return Object.fromEntries(['schedule', 'race', 'periodization', 'trips', 'stress_model'].map(key => [key, meta[key] ?? null]));
}
