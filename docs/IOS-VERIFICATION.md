# iOS verification

Run from the repository root with Xcode 26.3, XcodeGen 2.45.3, Python 3,
and the iOS 26.2 simulator runtime installed:

```bash
npm run ios:verify -- --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2 --device com.apple.CoreSimulator.SimDeviceType.iPhone-17
```

The command copies iOS sources to a disposable directory, generates the project
there, creates a new simulator, and runs unsigned `xcodebuild test` using the
**TresFort** scheme. It includes the widget build, existing unit tests, shared
numerical/calendar contracts, and `TrainingJourneyTests`. It neither needs nor
uses signing credentials. It does not migrate D1, deploy a Worker, or upload an
app. Existing simulator data, generated projects, and build directories are not
reused. Parallel test cloning is disabled so the command owns every simulator
it creates. Its exit status fails if building/testing or simulator deletion fails.

Select an installed runtime/device explicitly; list choices with
`xcrun simctl list runtimes` and `xcrun simctl list devicetypes`. Missing choices
fail before creating a device. Runtime installation and upgrading Xcode are
separate machine setup actions. On macOS, the simulator service must be accessible;
a sandbox that denies CoreSimulator or its caches cannot run this command.

For a focused check, append `--only-testing TresFortTests/CalendarProjectionTests`
or `--only-testing TresFortUITests/TrainingJourneyTests`. A focused result does
not substitute for the full suite before merging an iOS change.

## Evidence and cleanup

Build copies, DerivedData, and the created simulator are deleted on success,
failure, and interrupt. Failure retains `xcodebuild.log`, environment/toolchain
identity, copied-source SHA-256 manifest, runtime inventories, cleanup diagnostics,
and `Tests.xcresult` under
`.artifacts/ios/<unique-run>/`. Set `IOS_KEEP_RESULTS=1` to retain successful results
and their synthetic screenshot attachments too. `IOS_EVIDENCE_DIR` may select a
different durable output directory. These artifacts are ignored by Git. The
log records the Git revision and local overlay; tests run on the copied working
files, including any uncommitted changes.

Open a result bundle in Xcode or export its UI attachments:

```bash
xcrun xcresulttool export attachments --path .artifacts/ios/<run>/Tests.xcresult --test-id TrainingJourneyTests --output-path .artifacts/ios/<run>/screenshots
```

Delete retained local evidence when it is no longer needed. An uncatchable kill
or host crash can leave the named `TresFort verification` simulator and
`tres-fort-ios.*` scratch directory; remove only those belonging to that run.

## Synthetic UI fixtures

The Debug simulator build accepts `TRESFORT_UI_FIXTURE` through its launch
environment. Available cases are `sign-in`, `empty`, `load-failure`, `ordinary`,
`bodyweight`, `timed`, `pending`, `correction-failure`, and `ready-to-finish`.
An unknown value aborts before real authentication is constructed. Fixture code
is excluded from Release builds and physical-device builds.

Each launch uses a reset synthetic defaults namespace and a token store that
never reads or writes Keychain. Training dates are fixed at September 8, 2026.
The fixture mounts the real Today, routine editor, runner, correction, and
completion views over the real SyncModel. It avoids MainTabView's HealthKit,
group, credential-renewal, and connectivity lifecycle. APIClient switches to
`ui-fixture.invalid` and an ephemeral URLSession whose protocol answers only
bounded in-memory routes. Unknown routes fail; nothing forwards to the network.
No real user's health data is loaded or persisted. Use a disposable simulator
for walkthroughs too; the verification command already provides this isolation.

The sign-in fixture substitutes only the provider button to record a synthetic
intent; even a manual tap cannot launch AuthenticationServices. The behavioral
smoke exercises that intent, creates a
routine and first workout, logs a set and acknowledges completion, retains an
offline write, and checks that a rejected correction preserves its original
values. It also distinguishes verified empty state from initial-load failure.
Representative screenshots are XCTest attachments, not fragile pixel baselines.
The fixture server is a transport stub, not proof of backend validation or an
Apple authorization exchange. Unit/integration tests verify those separate
contracts. Native Apple authorization and its provider UI remain a separate walkthrough.

`ios/TresFortTests/Fixtures/CalendarProjection.json` supplies the same civil-date,
DST, leap-day, real-session, dangling schedule, and blackout expectations to
Swift and TypeScript. `BodyweightProgress.json` continues sharing numerical
expectations for reps, timed holds, assistance, unilateral, and loaded metrics.

## CI and merge evidence

CI runs `plan graph`, `iOS build + tests`, and `typecheck + tests`. The iOS job
uses the public repository's standard `macos-15` runner, Xcode 26.3, iOS 26.2,
and checksum-pinned XcodeGen 2.45.3. It does not use paid large runners. The job
is disabled for a private repository; enabling private capacity requires an
explicit capacity decision. Toolchain changes should update this document and
the workflow together. A missing pinned toolchain must fail, not silently select
another runtime. The source image can evolve, so the environment log records
what actually ran.

CI uploads synthetic results with a seven-day artifact retention. No production
credentials or account data are supplied to these jobs. Dependency installation
and GitHub action permissions follow the existing repository workflow.

As verified September 8, 2026, GitHub branch protection requires only
`typecheck + tests`. This change does not modify branch protection. For work
changing iOS, all three jobs and the current-head independent review must pass
before merge; backend green alone is insufficient. Making the additional check
names enforced repository settings requires separate repository authority.

A compile, screenshot, or automated smoke test does not establish VoiceOver
usability, physical-device keyboard reachability, audio/lock-screen cues, or
interruption behavior. P1 records simulator evidence separately from the
owner's physical-device walkthrough before any release claim.
