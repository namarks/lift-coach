# Coaching Feedback Loop

Slug: coaching-feedback-loop · Status: paused · Updated: 2026-09-09 · Theme: coaching

## Goal

Close the loop between training and coaching: a member can record concise,
useful feedback after a workout; the coach can read it alongside the actual
session; and the member can see what changed in response. Done means feedback
and plan-change context travel through the existing Tres Fort data and MCP
surfaces without adding AI to the Worker or creating a second coaching record.

## Phases

- [x] **P0 — Workout feedback reaches the coach**
  - [x] **(a) Coach-facing feedback reads**
    - Expose the existing session fatigue and note fields through the relevant
      history, current-state, and coaching-brief reads so the next coaching
      conversation receives the member's words and the recorded workout without
      a schema change. Keep these private fields out of group projections.
    - Include session notes in both recent-session and last-completed-session
      brief paths. Verify a skipped/in-progress latest session does not hide the
      prior completed session's feedback. This read-path slice can be implemented
      independently of the iOS runner and finish flow.
  - [x] **(b) Voice and typed finish input**
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
      with fresh-install grant and denial checks on the supported iPhone
      deferred by the owner to a future TestFlight build (2026-09-09).
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
- [x] **P1 — Coaching changes are visible and correctable**
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

- P2

## Dependencies

P1 reuses the completed [shared snapshot/history projection](../completed/reversible-plan-management/decisions.md) for visibility and reversion, preserving one change feed.

P0(b) reuses the completed [superset runner/editor integration](../completed/supersets-and-circuits/plan.md), including shared recovery, models, API/cache handling and synthetic fixtures. Its temporary shared-file blockers are satisfied; preserve those delivered contracts when adding finish-flow feedback.

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P2 | coordinates_with | plan:activity-integration-integrity#P0 | Identity/civil-date fixes and unknown-load labels need consistent source context. |

## Next step

**Now (@owner):** P1 implementation and local verification are complete. Its
repository delivery requires the P1 pull request's exact-head independent review,
green CI, merge and integration evidence; the active delivery goal closes only
after those gates. Keep P2 paused until explicitly activated. Production
deployment, migrations and TestFlight distribution require separate authorization.

The [physical iPhone feedback checks](device-verification.md) remain deferred to
an eventual separately authorized build containing P0. They are a release
follow-up and do not block P1 repository delivery.

## Notes / open questions

- P1 activation (2026-09-09): live main and fetched `origin/main` both verified at
  `4ec8a9ef43b377c76458f57f32cd94e9d63da4ef`, the merge of P0 PR #163.
  GitHub confirms P0 merged with all configured checks green. Existing iOS
  Workout history already lists actor/time/reason, pages versions, compares
  snapshots and restores with reviewed plan/version and active-workout guards.
  P1 closes discovery, affected-target summaries, and durable local dismissal
  with a permanent route back to the same history. Preserve P0 privacy/recovery.
- P1 implementation milestone (2026-09-09): Today surfaces the newest canonical
  change with Coach/You attribution, time, recorded reason and named affected
  targets. Dismissal persists only an account/plan-scoped version marker and is
  cleared on account deletion; it never removes history. Workout history remains
  reachable from Today and Workouts, including dismissed entries, correction
  controls and comparison of a change's predecessor with the current plan before
  the existing full-plan restore. Restore retains the reviewed plan/version,
  active-workout and successful-acknowledgement contracts.
- History adds optional `previous_version` and `affected` fields derived from the
  same snapshot comparison that supplies its summary. Existing audit/note-derived
  actor/reason values remain canonical; missing rationale is explicitly absent.
  No new feed, mutation API, schema, background notification or stored audio.
  Older history responses still decode and retain direct version comparison.
  Recent-history reads require the exact plan version from the single state
  pull and reject superseded requests and account/plan changes. A newer history
  response stays undisplayed and undismissible until state refresh catches up;
  read failures do not replace workout sync errors or block training.
- P1 local verification (2026-09-09): typecheck, plan graph, verification-script
  checks and all 908 backend tests (62 files) passed. All 423 iOS unit tests,
  both P1 iPhone 17 simulator journeys and all five P0 feedback UI journeys passed.
  The P1 path covers visibility, dismissal, relaunch, both actors in revisited
  history, predecessor comparison, restore as a new visible version and reaching
  the existing editor. Additional deterministic checks cover legacy decoding,
  account/plan scoping and deletion, late requests, read failure, concurrent
  history writes, and dismissal pinned to the rendered version. Both P1 journeys
  now run in CI smoke coverage. These are synthetic simulator/D1 checks, not
  production, physical microphone or on-device recognition evidence.
- P0(a) implementation milestone (2026-09-09): session notes/fatigue now travel
  through private exercise history and both brief paths. Focused real-D1/MCP
  checks passed 20/20, including skipped/in-progress latest sessions and group
  privacy. The coherent P0 delivery is tracked in PR #163.
- P0(b) uses a local approved-feedback checkpoint and immutable terminal
  envelope. Explicitly saved empty fields clear feedback; Skip omits feedback.
  Finish requests compare the original note/rating in the same atomic write,
  so retries cannot overwrite different newer feedback. A conflict retains the
  local words and requires an explicit choice. No schema migration is needed.
- Recording Stop finalizes on-device transcription with a bounded wait;
  cancellation, editing and leaving immediately invalidate callbacks and release
  capture resources. The draft comparison baseline belongs to the editor's
  lifetime. Only explicitly approved text is persisted.
- Verification milestone (2026-09-09): typecheck, plan graph, and the full
  backend suite passed (62 files / 906 tests). Final iPhone 17 simulator checks
  passed all 419 unit tests and all 5 feedback UI journeys, including both
  conflict choices. The broader smoke run passed 9 UI journeys. Recovery covers
  approved feedback before any sets, relaunch, stale app views and first-set
  session binding. Independent review cleared `6a2606a` against main `fd560e4`,
  and every configured check passed in [CI run 34391201635](https://github.com/namarks/tres-fort/actions/runs/34391201635).
  The final owner-decision/cleanup head `e7bd91f` subsequently passed fresh
  review and CI and merged through PR #163 as `4ec8a9e`. Main integration CI
  passed in [run 34398139340](https://github.com/namarks/tres-fort/actions/runs/34398139340).
- Release ordering after separate owner authorization: deploy the compatible
  Worker before distributing the iOS build that sends `expected_feedback`.
  Older Workers can reject that new field. No schema migration is required;
  no production or TestFlight action is part of repository delivery.
- Owner decision (2026-09-09): proceed through PR, merge and integration
  verification now; the owner will test on a future TestFlight version. Fresh
  physical permission and successful on-device transcription evidence remains
  unverified and is a release follow-up, not a pre-merge gate. The temporary
  separate checker and installer are retired; no tailnet link was hosted and
  no TestFlight upload ran. This decision does not authorize deployment or app
  distribution. Synthetic recognition, simulator and D1/MCP tests remain the
  repository evidence and must not be described as physical-device results.

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
