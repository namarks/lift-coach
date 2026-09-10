# First App Store Submission

Slug: app-store-submission · Status: active · Updated: 2026-09-10 · Theme: release

## Goal

Prepare a verified Très Fort 1.0 build and complete App Store review package
for a free, United States-only first release. Completion requires an exact
candidate, compatible production backend, physical-device evidence, accurate
privacy disclosures, listing and reviewer access. App Review submission and
public release require separate authorization and are outside this goal.

## Phases

- [x] **P0 — Submission foundations and release defects**
  - Add privacy/support links before sign-in and in Profile, and bundle a
    required-reason manifest for actual API use.
  - Explain optional Claude/Anthropic and Apple Health data sharing at the
    authorization controls; preserve manual use without integrations.
  - Diagnose feedback replacement failure without weakening saved-text
    assertions; pass focused behavioral and required full checks.
  - Align marketing version with the App Store 1.0 record; choose the build
    number only after a fresh App Store Connect read.
- [ ] **P1 — Privacy and public-user review readiness**
  - Trace deletion/export, HealthKit cache/backup behavior, coach access and
    withdrawal, and private-group content through the actual paths.
  - Resolve essential reporting/blocking/filtering requirements for group
    content with a bounded design before changing member/data policy.
  - Prepare accurate App Privacy and age-rating answers against final source
    and provider behavior. Confirm public policy/support URLs work.
- [ ] **P2 — Review package**
  - Prepare copy, category, synthetic-data screenshots from the actual candidate
    UI, and reviewer instructions for manual onboarding, logging, optional
    integrations, export and deletion.
  - Confirm viable reviewer access without personal training data; any reviewer
    credentials remain owner-managed.
  - Verify free pricing, US-only availability and applicable agreements; request
    owner confirmation for fields inaccessible to existing tools.
- [ ] **P3 — Exact candidate and production verification**
  - Independently review the final head and pass all required checks.
  - Read deployed source/configuration and migration ledger; prepare an exact
    migration/deployment proposal if the candidate needs a newer backend.
  - After separate release authorization, archive/upload the chosen build,
    verify Apple processing and version, and retain source identity.
  - Verify physical-iPhone onboarding, workout completion/recovery, integration
    permissions and real speech behavior against the matching backend. Reuse
    the [feedback device procedure](../completed/coaching-feedback-loop/device-verification.md).
- [ ] **P4 — Submission-ready handoff**
  - After approval of concrete App Store changes, publish metadata, screenshots,
    privacy answers and reviewer details, and select the verified build.
  - Re-read App Store Connect and audit every requirement. Select manual release
    after approval. Do not submit to review or publicly release the app.

## Execution frontier

- P1
- P2

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P3 | gated_by | external:owner-appstore-candidate-release | Production changes, TestFlight upload and device actions need a concrete authorized proposal. |
| P4 | gated_by | external:owner-appstore-metadata-publication | Publish only the concrete approved package. |

## Next step

**Now (@agent):** Complete verification, independent review and merge of the
protected-storage integration on the merged backend error-privacy fix. Preserve
account/revision fencing and demonstrate failure recovery before claiming
privacy readiness. Continue review-package preparation; await the owner's
decisions on the [group-safety proposal](group-safety-proposal.md) and
[diagnostics policy](diagnostics-policy-proposal.md) before changing those policies.
Preserve external release and publication gates.

## Notes / open questions

- Within this plan, P3 requires P0/P1, and P4 requires P2/P3. These are phase
  order requirements, not cross-plan dependency edges.
- Owner decision, 2026-09-10: **free, United States only**.
- P0 delivered in [PR #171](https://github.com/namarks/tres-fort/pull/171),
  reviewed head `3629ab656ba6b99d8a852d8fdf8473e71480431b`, merged as
  `95f90307deaf4993a2cadc4546480933d785a048`. Independent Codex review completed
  without findings; no unresolved threads; [all configured CI checks passed](https://github.com/namarks/tres-fort/actions/runs/34491716466).
  The merge and reviewed head have identical tree
  `122d8e9c537ad7e3fb15d2512b419432d2ae9a4c`. Final build-number selection remains
  part of P3 after the final source and App Store Connect read are established.
- Foundation implementation: privacy/support links, optional integration
  disclosures, UserDefaults required-reason manifest, marketing version 1.0,
  reliable transcript replacement assertions, and an explicitly selected
  version/build in the review-submission lane. No upload or submission occurred.
- Local verification, 2026-09-10: TypeScript typecheck and all 967 backend tests
  passed; final OAuth checks passed (8 tests). On Xcode 26.3 / iOS 26.2 / iPhone
  17 simulator, all 448 unit tests and five feedback journeys passed; the final
  onboarding and affected feedback rerun passed all nine tests. The built app
  contained marketing version 1.0 and the UserDefaults `CA92.1` manifest.
  Release-lane boundary tests, verification-script tests, plan validation and
  whitespace checks passed. Exact-head independent review and remote CI passed
  as recorded above.
- A paired physical iPhone was unavailable on 2026-09-10; simulator evidence
  does not satisfy the P3 physical-device gate.
- The [review package](review-package.md) is a draft. The proposed group controls
  and daily inbox / 24-hour response commitment await owner approval. Persisted
  HealthKit records now use the candidate's protected, backup-excluded
  app-owned storage; verification and release gates remain in P1/P3.
- P1 integration: `LocalPersistence` routes app-owned data blobs through
  `ProtectedTrainingStore`, including inactive-account migration, snapshots,
  every training outbox, runner recovery, HealthKit anchors and account cleanup.
  Failed saves stop new requests, corrupt durable queues are preserved, and
  cleanup failures retain the deletion receipt for retry. Full local verification
  executed 468 unit tests with zero failures and one explicit simulator
  protection skip, plus 14 passing onboarding/workout/feedback UI journeys.
  The final account-isolation and foreground-recovery follow-up passed 71 focused
  unit tests and the manual onboarding journey. Independent review identified
  two navigation-persistence gaps; the follow-up preserves unreadable intents,
  requires durable saves before navigation changes and reloads account binding
  after recovery. Its 77 focused unit tests and eight onboarding/invite UI
  journeys passed, with all 268 iOS source-manifest entries matching the tested
  files. Further review fixes scope deletion cleanup to its own account, remove
  the legacy identity marker only after cleanup succeeds, and stop stale-workout
  fallback requests when the replacement queue cannot be saved. The follow-up
  ran all 478 unit tests (one simulator protection skip, zero failures) and the
  workout-completion UI journey; all 268 source-manifest entries matched.
  Fresh independent review and remote CI must finish before repository delivery
  is complete. The preceding CI run connected Intervals successfully but left
  History empty. Investigation reproduced eager construction of unused tab
  models invalidating a shared snapshot request. The tab now owns one lazily
  installed model container. The regression failed before the fix; afterward,
  72 focused unit tests and all 12 connection/onboarding/workout UI journeys
  passed, with all 268 source-manifest entries matching the final iOS files.
  A further review found corrupt presentation metadata could gate all feature
  requests. The follow-up classifies dismissal markers and Intervals connection
  mirrors as replaceable, retries failed cleanup after storage recovers, and
  preserves corrupt workout queues, checkpoints, navigation and Health anchors.
  All 83 focused unit tests and five affected connection/plan-history UI journeys
  passed, with all 268 source-manifest entries matching. Fresh exact-head review
  and CI remain required. The runner save-failure follow-up immediately restores
  the last durable selection, skips and inputs rather than losing visible changes
  during storage retry. A regression reproduced the prior behavior; all 328
  affected unit tests and the workout-completion UI journey passed after the fix.
  The storage branch was refreshed onto the reviewed backend merge below.
  The next remote run failed at invite preview retry. Its hierarchy exposed a
  20.3-point button inside a 44-point container; a local regression reproduced
  the undersized target. The button label now owns the full touch area. All
  eight onboarding journeys passed, including retry from the expanded area,
  group joining and workout completion; all 268 tested iOS source hashes match.
  [CI run 34513974066](https://github.com/namarks/tres-fort/actions/runs/34513974066)
  passed all 20 UI journeys, including invite retry, but failed one of 483 unit
  tests (one additional simulator protection skip). The assertion regenerated an
  equivalent JWT whose JSON claims serialized in a different key order. It now
  compares the retained token with the exact original fixture token. All 72
  authentication tests passed locally, with all 268 tested iOS source hashes
  matching. [CI run 34517031117](https://github.com/namarks/tres-fort/actions/runs/34517031117)
  then passed all configured checks. Independent review identified a corrupt
  Health anchor that ordinary disconnect could not clear. The follow-up permits
  an explicit, account-scoped Health reset while preserving unreadable training
  queues and another account's legacy data. Failed resets remain retryable after
  relaunch, and disconnected or retired syncs cannot restore their anchors.
  The regression reproduced before the fix; afterward all 96 focused tests
  passed with one explicit simulator protection skip and all 268 iOS source
  hashes matching. Fresh exact-head independent review and CI remain required.
  An unsigned Release build for generic iOS also passed: version 1.0, iPhone-only
  family, embedded widget and `CA92.1` manifest verified; the synthetic fixture
  switch was absent. This used the unreserved project build placeholder 29,
  not an upload candidate. No archive or upload was made.
  The file-protection test must pass on a physical iPhone; simulator results do
  not prove this property. See the release audit for upgrade/rollback constraints.
- The backend diagnostics fix was delivered in [PR #173](https://github.com/namarks/tres-fort/pull/173),
  reviewed head `528aa8c7f79d5624c89f9ac4e31a98f1b76afb74`, merged as
  `0f82e0ad045c21a5f0bda0215b9d1b8b07c020f8`. Independent Codex review completed
  without findings, all threads were resolved, and [required CI passed](https://github.com/namarks/tres-fort/actions/runs/34508210971).
  The reviewed and merged tree is `530be6e14b42dd6a50b127031e99e3282bd8f6a9`.
  Local verification included TypeScript, all 972 backend tests, then 85 focused
  tests for the validation-code follow-up. It removes raw unexpected error text from application logs and HTTP/MCP
  responses. Read-only provider metadata at 17:07:31 UTC confirmed persisted
  invocation logs with 100% sampling and URL query redaction disabled. Tracing
  is disabled; no tail consumers or export destinations were returned. Logpush
  is not exposed by the download path. No request logs were opened. The
  [diagnostics policy proposal](diagnostics-policy-proposal.md) awaits an owner
  choice; production changes, historical exports and final privacy declarations
  remain separate gates.
- [Release audit, 2026-09-10](release-audit-2026-09-10.md): production version
  `c5a298d1-a72a-4fa8-a24f-bd2cf0e27a6b`, source annotation `ff512825779f90b630a4a5dfd11a68e6a113825a`,
  migration ledger through `0045`; source migrations `0046` and `0047` remain
  unapplied. Normal-browser checks successfully rendered both public marketing
  and privacy pages with support links; HTTP clients still returned 403.
  Mailbox delivery is untested. No production change was made.
  A SELECT-only refresh at 17:47–17:48 UTC confirmed the same deployment and ledger
  through `0045`, with zero rows written.
- P2 draft screenshot preparation is isolated in `codex/app-store-screenshots`.
  Two UI capture journeys produced five opaque RGB 1320 × 2868 images through
  real views with fictional data, preserving source/image hashes and test logs.
  The complete workflow passed again on source `55477d7` after integration with
  the corrected storage candidate: both UI journeys passed, all 270 tested iOS
  source hashes matched, and every image was visually inspected. The command
  rejects PNG transparency, validates dimensions and source identity, and
  removes its owned build/simulator. An unsigned Release build of the same app
  sources passed with synthetic markers absent; later differences were confined
  to tests and the capture script. The workflow is ready for independent review
  as a focused change based on the storage PR. Both require their own final
  review and CI before merging. Capture against the selected release source
  remains required. No images or App Store metadata were published.
- Source baseline `bb4db9c40675ba6be6a0b8ff42f8cdbabcf14a4c`;
  [main CI](https://github.com/namarks/tres-fort/actions/runs/34486074011) passed.
  The preceding run failed transcript replacement: its helper could delete
  backward from an arbitrary cursor after missing the selection menu. A later
  pass does not explain that failure.
- App Store Connect read on 2026-09-10: app `6772375823`, version `1.0` in
  `PREPARE_FOR_SUBMISSION`, no selected build/screenshots and empty description,
  support/privacy URLs, category, review details and age answers. Latest build
  `0.1.0 (34)` was `VALID`, `APP_STORE_ELIGIBLE`, `IN_BETA_TESTING`. Re-read before
  writes. Existing API permissions did not allow pricing/availability reads;
  agreements and App Privacy answers remain unverified.
- Owner App Store Connect readback, 2026-09-10: after a phone screenshot showed
  unset pricing/availability, the owner confirmed saving **Free / United States
  only**. This is owner-confirmed configuration; direct API readback remains
  unavailable to the existing key. The owner deferred checking App Store
  agreements; agreement readiness remains pending.
- Website hosting belongs to [PR #170](https://github.com/namarks/tres-fort/pull/170);
  do not duplicate its edits. Merged source is not public-URL evidence.
- Repository work is authorized through required review and merge. Production
  changes, upload, metadata publication, submission and release remain gated.
- Apple references checked 2026-09-10: [review guidelines](https://developer.apple.com/app-store/review/guidelines/),
  [required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
  [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).
