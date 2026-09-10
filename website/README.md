# Très Fort public website

Small, dependency-free static site for `tresfort.app` with an app landing page
and `/privacy`. The iOS API, database, and authentication stay in the existing
Worker. The website does not receive app credentials or training data.

Run `npm ci`, `npm run dev`, `npm run build`, or `npm test` in this directory.
The build produces only public files in `dist/`. Node 20 or later is supported.
The Sites project is recorded in `.openai/hosting.json`; reuse that ID.

## Policy source

`privacy.mjs` owns the policy. `src/routes/privacy.ts` imports that same content,
preserving the policy URL already used by the app. Editing this file changes
both builds; deployment of the website does not deploy the app Worker.

Disclosures were checked against source at `69729d6`:

- `ios/TresFort/Health/HealthKitSyncModel.swift`: permissions, on-device
  heart-rate summary, uploaded workout fields, disconnect preserving imports.
- `ios/TresFort/Health/AppleHealthSettingsView.swift` and `src/db.ts` group
  projections: Apple Health group sharing is separate and off by default.
- `src/intervals.ts`, `src/routes/intervalsAuth.ts`, and `src/db.ts`: optional
  credentials, activity/event records and raw responses, strength-load export.
- `src/mcp/server.ts`, `src/oauth.ts`, and Profile: authorized coach reads and
  writes, group access, and revocation; no claim of deleting provider copies.
- `src/db.ts` `deleteUserAccount` and Profile: account export and active-record
  deletion, retained deletion receipts, and group transfer. No invented backup
  deletion deadline or automatic history purge on disconnect.

Before public release, review operational retention and current deployment
behavior with the operator. Repository behavior is not proof that the newest
Worker or iPhone build has been released. No new consent or retention policy
is activated by this website change. Direct Garmin integration is not advertised.

## Assets

Fonts and icon come from the iPhone app. Both font licenses are retained in
`public/assets/`. Screenshots are unedited captures of the real app with
synthetic data, taken from source `69729d6` on an iPhone 17 Pro simulator,
iOS 26.2, on 2026-09-10. No member data was used.

The captures came from these existing passing journeys:

- `TrainingJourneyTests/testOrdinarySetLogsAndCompletesThroughAcknowledgement`
  (`ordinary-workout` attachment → `workout.png`).
- `WorkoutLibraryJourneyTests/testLibraryBadgesUnscheduleAndDateAssignment`
  (`workout-library` attachment → `library.png`).

Run those selections with `scripts/verify-ios.sh` and `IOS_KEEP_RESULTS=1` to
capture again; export the attachments with `xcrun xcresulttool export attachments`.
The simulator is disposable and the verification script removes it afterward.

## Publication boundary

Private preview is authorized by the website build request. Public access,
custom-domain DNS changes, and deployment of the existing app Worker are
separate release actions. The email MX, SPF, DKIM and Apple verification records
must be preserved when connecting the website domain.

Only this directory is the Sites source repository. A subtree split of
`website/` can be pushed to the Sites source remote without publishing the
backend repository or its history. Build and package that exact source state
using the Sites packaging helper before saving a version.
