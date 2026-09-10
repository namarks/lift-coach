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
protected-storage integration. Preserve account/revision fencing and demonstrate
failure recovery before claiming privacy readiness. Continue review-package preparation;
await the owner's decision on the
[group-safety proposal](group-safety-proposal.md) before changing group policy.
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
  unit tests and the manual onboarding journey. Independent review and remote CI
  must finish before repository delivery is complete.
  The file-protection test must pass on a physical iPhone; simulator results do
  not prove this property. See the release audit for upgrade/rollback constraints.
- [Release audit, 2026-09-10](release-audit-2026-09-10.md): production version
  `c5a298d1-a72a-4fa8-a24f-bd2cf0e27a6b`, source annotation `ff512825779f90b630a4a5dfd11a68e6a113825a`,
  migration ledger through `0045`; source migrations `0046` and `0047` remain
  unapplied. Normal-browser checks successfully rendered both public marketing
  and privacy pages with support links; HTTP clients still returned 403.
  Mailbox delivery is untested. No production change was made.
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
- Website hosting belongs to [PR #170](https://github.com/namarks/tres-fort/pull/170);
  do not duplicate its edits. Merged source is not public-URL evidence.
- Repository work is authorized through required review and merge. Production
  changes, upload, metadata publication, submission and release remain gated.
- Apple references checked 2026-09-10: [review guidelines](https://developer.apple.com/app-store/review/guidelines/),
  [required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
  [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).
