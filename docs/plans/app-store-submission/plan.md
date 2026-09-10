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

**Now (@agent):** Prepare the exact candidate-release proposal from PR #175 after
its required independent review, CI and merge. Resolve any remaining review
findings in that same PR. Keep the existing service, email and Profile screens;
production changes, TestFlight distribution, physical-device verification and
App Store publication remain separately authorized steps.

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
- The [review package](review-package.md) is a draft. The owner approved group controls, the daily inbox / 24-hour response
  commitment and aggregate-only diagnostics on 2026-09-10, with an explicit
  preference against overengineering. The implementation is prepared for exact-head
  independent review and CI. Persisted
  HealthKit records now use the candidate's protected, backup-excluded
  app-owned storage; verification and release gates remain in P1/P3.
- The group-safety candidate is in [PR #175](https://github.com/namarks/tres-fort/pull/175),
  using the existing Worker/D1 and Profile screens:
  mutual member blocking, reviewed email drafts with copyable references,
  conservative shared-text filtering and audited, reversible operator sharing
  restrictions. Migration `0048` is additive and must precede the new Worker.
  TypeScript, plan checks and Wrangler 4.92 dry-run/type generation passed.
  Local backend verification passed 980 tests; the remaining assertion assumed
  a random group sort order. Selecting the intended group by ID corrected that
  test, and all 12 safety/export tests then passed. Export controls use the same
  D1 batch snapshot as the training projection. All 489 iOS unit tests completed
  without failures (one physical-protection test explicitly skipped), and both
  safety journeys passed on iPhone 17 / iOS 26.2. All 274 iOS input hashes matched;
  the synthetic report screen was visually inspected. Independent review and
  remote CI remain required. The CI selection check now accounts for the added
  safety suite; all 11 verification-workflow checks, seven asset checks, six CI
  scope checks and two review-submission checks pass locally. An unsigned
  generic-iOS Release build at `03b50c043a0d239721038becacc3ce23c78c8162` passed:
  version 1.0, iPhone-only, embedded widget, `CA92.1` manifest and no synthetic
  fixture markers. Its build 29 is an unreserved placeholder, not an upload
  candidate. Independent review identified cached secondary groups on foreground;
  the app now invalidates every shared projection before authentication waits and
  reloads all rosters. A stale detail task cannot supersede that reload. All
  three safety unit tests and five safety/Intervals journeys passed after the
  correction, including background/foreground use. Rejected block requests now
  revalidate membership rather than leaving a false empty-group screen; an offline
  reload exposes retry while preserving the original block error. The regression
  reproduced both failures before the fix; all four safety unit tests pass after
  it. No production or App Store changes occurred.
- P1 protected-storage repository work was delivered in
  [PR #172](https://github.com/namarks/tres-fort/pull/172), reviewed head
  `9bdcbee7a3de96b2384a3c9de9e64cefa86f5df9`, merged as
  `310327b7a0d779b8a905e7b18588bda30f1bd808`. Independent Codex review found no
  remaining issues, all review threads were resolved, and
  [all eight configured checks passed](https://github.com/namarks/tres-fort/actions/runs/34518979841).
  The reviewed and merged tree is `c7dcfecfe6fddc69aee93a6e92532d6d0eb529e3`;
  remote-main ancestry and tree equality were verified after merge.
  Training blobs now use protected, backup-excluded storage with account/revision
  fences, durable-write gates, inactive-account migration and explicit recovery.
  Unreadable training queues remain intact; acknowledged deletion erases only
  the relevant account. Explicit Health disconnect can rebuild an unreadable
  cursor, preserves failed reset intent, and rejects stale sync checkpoints.
  Tab models have one lazy owner; invite retry has a full 44-point touch target.
  The final Health follow-up passed 96 focused authentication/storage tests with
  one explicit simulator protection skip; all 268 tested iOS source hashes
  matched. Earlier full/focused checks and failure diagnoses are retained in the
  [release audit](release-audit-2026-09-10.md). Physical-iPhone file protection,
  upgrade, lock/unlock and recovery verification remain P3 requirements.
  A rollback must retain the new storage reader or first reconcile pending work.
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
  [diagnostics policy proposal](diagnostics-policy-proposal.md) is owner-approved; production changes, historical exports and final privacy declarations
  remain separate gates.
- [Release audit, 2026-09-10](release-audit-2026-09-10.md): production version
  `c5a298d1-a72a-4fa8-a24f-bd2cf0e27a6b`, source annotation `ff512825779f90b630a4a5dfd11a68e6a113825a`,
  migration ledger through `0045`; source migrations `0046` and `0047` remain
  unapplied. Normal-browser checks successfully rendered both public marketing
  and privacy pages with support links; HTTP clients still returned 403.
  Mailbox delivery is untested. No production change was made.
  A SELECT-only refresh at 17:47–17:48 UTC confirmed the same deployment and ledger
  through `0045`, with zero rows written.
- P2 screenshot workflow was delivered in [PR #174](https://github.com/namarks/tres-fort/pull/174),
  refreshed onto the verified storage merge. The complete workflow passed on
  clean capture source `d1ef8111419cd0fcae0cf01c1df5a73881ef7acf`: both UI journeys
  passed, all 270 iOS source hashes matched, and five opaque RGB 1320 × 2868
  images were visually inspected. The framing follow-up also passed both
  journeys on CI's smaller iPhone 17. Build and capture now share source
  selection; added/removed/changed inputs and checkout changes abort capture.
  PNG checks cover structure, checksums, compression, pixels and transparency.
  Seven optimized-Python asset tests and 11 build-workflow tests passed; reported
  validation bypasses reproduced before the fixes. A generic-iOS unsigned
  Release build of the same iOS inputs passed with version 1.0, embedded widget,
  `CA92.1` manifest and no synthetic fixture markers. Build 29 remains an
  unreserved placeholder. Reviewed head `a3b5849f9035d71097119d8e319c545a13db60b9`
  merged as `efa16e84fcddc1ea44bd1082ea435b63b1d84a03`, with identical tree
  `88808504401105f61116e253a05700050fe2308b`. Independent review found no issues,
  all threads were resolved and all eight checks in run `34521185926` passed.
  Source ancestry and tree equality were verified after merge. Subsequent group
  changes require a fresh candidate build; the prior Release proof covers only
  its recorded source inputs.
  Final candidate selection, device verification and capture comparison remain
  open. Nothing was uploaded or published to App Store Connect.
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
