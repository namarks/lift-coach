# Coaching Feedback Loop

Slug: coaching-feedback-loop · Status: planned · Updated: 2026-09-07 · Theme: coaching

## Goal

Close the loop between training and coaching: a member can record concise,
useful feedback after a workout; the coach can read it alongside the actual
session; and the member can see what changed in response. Done means feedback
and plan-change context travel through the existing Tres Fort data and MCP
surfaces without adding AI to the Worker or creating a second coaching record.

## Phases

- [ ] **P0 — Workout feedback reaches the coach**
  - Add an optional, quick finish flow for perceived fatigue and a short note;
    pain can be described in the note, and completing a workout must not
    require a questionnaire.
  - Persist those existing session fields and expose them through the relevant
    history, current-state, and coaching-brief reads so the next coaching
    conversation receives the member's words and the recorded workout without
    a schema change.
  - Verify one end-to-end path from iOS capture to MCP read, including an edit
    made before the session is finalized.
  - Decode the stored feedback into iOS session models and carry optional
    fatigue/notes through the durable finish envelope, retries, relaunch and
    final-set review. Missing feedback stays absent rather than becoming a
    zero score. Preserve member-authored discomfort/constraints verbatim as
    data for the coach; keep these private fields out of group projections.
  - Include session notes in both recent-session and last-completed-session
    brief paths. Verify a skipped/in-progress latest session does not hide the
    prior completed session's feedback and that delayed acknowledgments cannot
    overwrite a newer feedback edit.
- [ ] **P1 — Coaching changes are visible and correctable**
  - Show recent plan changes in iOS with actor, time, concise rationale, and the
    affected day or exercise, using the canonical audit, note, and plan-history
    records rather than a parallel notification feed.
  - Let a member revisit dismissed changes and reach the correction or revert
    path owned by `reversible-plan-management`.
  - Keep manual and AI-authored edits equally visible; actor labels explain who
    changed the plan without giving either path a different data model.
- [ ] **P2 — Coaching uses the whole training context**
  - Include the existing schedule, recent feedback, races, periodization,
    trips, and stress settings in one compact coaching context where relevant.
  - Correct misleading trend labels and pair simple load or volume trends with
    the feedback that explains them; retain raw session history as the source.
  - Represent key sets with exercise identity, units, timed duration, signed
    assistance/added load, per-hand/per-side semantics and optional effort.
    A 45-second hold must not become an unexplained `0x45` in the brief. Reuse
    one semantic projection for recent and last-completed sessions and preserve
    relevant authored schedule/race/periodization/trip/stress metadata.
  - Describe counted non-warm-up sets as logged working sets, with primary-muscle
    attribution and effort coverage stated explicitly. If legacy wire fields
    retain `hard_sets`, document their limited meaning and provide compatible
    clearer labels; do not claim measured stimulus or complete muscle volume.
  - Use bodyweight P3's comparable cohorts; label positive-load tonnage as
    external-load volume, with unsupported measures absent. No automatic
    readiness score, fabricated body mass or unvalidated strength conversion.
  - Mark lift/endurance conflict output as a scheduling heuristic. Missing
    load/duration must yield unknown/incomplete context instead of an easy-work
    judgment. Keep TypeScript and Swift projection fixtures in parity and name
    the available source data; thresholds are not individualized safety or
    interference advice.
  - Verify that iOS and MCP describe the same recent sessions and plan state.

## Dependencies

P1 reuses the completed [shared snapshot/history projection](../completed/reversible-plan-management/decisions.md) for visibility and reversion, preserving one change feed.

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P2 | coordinates_with | plan:activity-integration-integrity#P0 | Identity/civil-date fixes and unknown-load labels need consistent source context. |

## Next step

**Now (@owner):** Activate P0 when member-to-coach feedback should enter the
executable backlog; it does not require the later change-history work to start.

## Notes / open questions

- [Completed bodyweight support](../completed/bodyweight-training-support/plan.md)
  supplies variation replacement and comparable metrics. Reuse the shared
  `BodyweightProgress.json` contract for bodyweight PR/hold claims; this is a
  delivered repository foundation, not an unresolved dependency.

- The [September app review](../../reviews/2026-09-app-review/report.md)
  found that current compact strings omit timed/load semantics and session
  notes. These are projection gaps even though fuller tools expose much of
  the underlying data. P0 remains independent of later metrics/history work.

- The first slice captures only feedback a coach can act on. Readiness scores,
  questionnaires, automated recommendations, and model-generated diagnoses are
  outside this workstream unless real usage demonstrates a need.
- Per-set RPE remains part of ordinary set logging and later runner refinement;
  P0 does not add a separate session-RPE field.
- The Worker remains deterministic data infrastructure. Claude interprets the
  feedback in conversation; the backend stores and returns it.
- Reuse the durable terminal session-write path completed in
  [Workout Write Reliability](../completed/workout-write-reliability/plan.md);
  it is historical foundation rather than an unresolved dependency.
