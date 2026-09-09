# Coaching Feedback Loop

Slug: coaching-feedback-loop · Status: planned · Updated: 2026-09-08 · Theme: coaching

## Goal

Close the loop between training and coaching: a member can record concise,
useful feedback after a workout; the coach can read it alongside the actual
session; and the member can see what changed in response. Done means feedback
and plan-change context travel through the existing Tres Fort data and MCP
surfaces without adding AI to the Worker or creating a second coaching record.

## Phases

- [ ] **P0 — Workout feedback reaches the coach**
  - [ ] **(a) Coach-facing feedback reads**
    - Expose the existing session fatigue and note fields through the relevant
      history, current-state, and coaching-brief reads so the next coaching
      conversation receives the member's words and the recorded workout without
      a schema change. Keep these private fields out of group projections.
    - Include session notes in both recent-session and last-completed-session
      brief paths. Verify a skipped/in-progress latest session does not hide the
      prior completed session's feedback. This read-path slice can be implemented
      independently of the iOS runner and finish flow.
  - [ ] **(b) Voice and typed finish input**
    - Add an optional, quick finish flow for perceived fatigue and a short note;
      pain can be described in the note, and completing a workout must not
      require a questionnaire.
    - Make speaking an obvious input choice with **Talk about your workout**.
      The member starts and stops recording, reviews an editable transcript,
      then explicitly saves it as the session note. Keep **Type instead** and
      **Skip** available; keyboard dictation alone does not satisfy the visible
      voice-entry requirement. Do not infer fatigue or rewrite the member's
      words from the recording.
    - Use on-device transcription for the initial voice path. Request microphone
      and any required speech permission only after the member chooses to talk.
      Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`
      purpose strings in `ios/TresFort/Info.plist` before requesting permission,
      and verify fresh-install grant and denial paths on the supported iPhone.
      If permission is denied or recognition is unavailable, preserve any text
      draft and offer typing or skipping. No cloud transcription fallback or
      audio upload is included in this scope.
    - Keep audio in memory only for recording and transcription; release it on
      completion, cancellation, interruption, or leaving the flow. Persist
      only the member-approved transcript through the existing private session
      note path; do not add stored voice messages or an audio retention system.
      A late recognition result must not overwrite a typed correction, restore a
      canceled draft, or submit feedback without the member's save action.
    - Decode the stored feedback into iOS session models and carry optional
      fatigue/notes through the durable finish envelope, retries, relaunch and
      final-set review. Missing feedback stays absent rather than becoming a
      zero score. Preserve member-authored discomfort/constraints verbatim as
      data for the coach. Delayed acknowledgments must not overwrite a newer
      feedback edit.
    - Verify voice-to-editable-text-to-MCP, including an edit before the session
      is finalized, plus typing, skip, denied permission, unavailable recognition,
      cancellation and interruption with synthetic recognition outcomes. Use
      current iPhones at normal text sizes. Neither a failed recording nor empty
      recognition output may block workout completion or erase existing feedback.
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

## Execution frontier

- P0(a)

## Dependencies

P1 reuses the completed [shared snapshot/history projection](../completed/reversible-plan-management/decisions.md) for visibility and reversion, preserving one change feed.

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P0(b) | blocked_by | plan:supersets-and-circuits#P1 | Voice/typed finish input and durable feedback share the runner and recovery files; the superset runner must land before this client slice. |
| P0(b) | blocked_by | plan:supersets-and-circuits#P2 | The supersets task also owns shared client models, API/cache handling and synthetic UI fixtures; its client integration must land before feedback edits to those files. |
| P2 | coordinates_with | plan:activity-integration-integrity#P0 | Identity/civil-date fixes and unknown-load labels need consistent source context. |

## Next step

**Now (@owner):** Activate P0(a) when member-to-coach feedback should enter the
executable backlog; it does not require the later change-history work to start.
The approved scope includes voice input with transcript review. P0(a) is the
independent coach-facing read slice. After it completes, advance the frontier
to P0(b), which remains blocked until the supersets runner/editor integration
lands before shared iOS finish-flow edits begin.

## Notes / open questions

- Owner decision (2026-09-08): offer spoken feedback because talking after
  training may be easier than typing. This is an adoption hypothesis to check
  through use, not a measured usage claim. Save the approved transcript as the
  existing session note and discard the recording. Cloud transcription or
  retained audio would require a separate product/privacy decision.

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
