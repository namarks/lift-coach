# App Store review package

Prepared for owner review; not published. Live completion and gates belong to
[plan.md](plan.md). Reconcile claims/screenshots with the final candidate before
upload. No credentials or personal training records belong in this file.

## Product page

| Field | Proposed value |
|---|---|
| Name | Très Fort |
| Version | 1.0 |
| Subtitle | Strength training, your way |
| Primary category | Health & Fitness |
| Price / availability | Free / United States only (owner-approved 2026-09-10) |
| Marketing URL | https://tresfort.app/ |
| Support URL | https://tresfort.app/#contact |
| Privacy policy URL | https://tresfort.app/privacy |
| Copyright | 2026 Nicholas Marks |
| Release option | Manual release after approval |
| Keywords | workout,strength,lifting,gym,sets,reps,rest,training,fitness,log,barbell,dumbbell |

Description:

Très Fort helps you plan your strength training and follow it set by set on
iPhone. Build your own workouts, or connect your own Claude account to review
and adapt your plan.

TRAIN WITH A PLAN
Create reusable workouts, choose exercises and targets, and organize your
training schedule. Follow working sets, warm-ups, timed holds, supersets and
circuits in the gym.

KEEP YOUR PLACE
Log repetitions, weight or duration, use rest timers, and return to an
interrupted workout. Review your history and correct supported training entries.

REFLECT ON YOUR WORKOUT
Save optional notes and fatigue ratings. Type feedback or use on-device speech
recognition where available, then review and edit the text before saving.

CONNECT YOUR TRAINING
Optionally import workouts from Apple Health or connect Intervals.icu to keep
your other activities in view. An authorized Claude connection can use your
training history to help adapt your plan.

TRAIN WITH YOUR CREW
Join a private group to share training progress with people you know. Apple
Health group sharing has a separate setting that is off by default.

YOUR ACCOUNT, YOUR CHOICE
Apple Health, Intervals.icu, Claude and groups are optional. Sign in with Apple
to sync training, export your account data, or delete your account in Profile.
Claude coaching requires a separate Claude account that supports custom
connectors; access to third-party services is governed by their own terms.

## Screenshots

Capture actual candidate screens using synthetic training data. Do not include
personal accounts, connection codes, fixture banners, fabricated features or
overlaid claims that hide the UI. Use the required current iPhone dimensions
from App Store Connect; iPad is not a supported device family in project.yml.

Suggested sequence: Today with a scheduled workout; workout runner with set
targets and rest controls; reusable workouts; training history; editable private
feedback. Add group or integration screenshots only after their release review
requirements are resolved. Preserve source SHA, build, simulator/device, locale
and dimensions with the resulting image set.

## Reviewer instructions

The app requires Sign in with Apple to synchronize a member's training.
Manual workout creation/logging works without Claude, Apple Health,
Intervals.icu or group membership. Describe and verify an approved reviewer
access path before submitting; a fresh-account walkthrough alone does not prove
that Apple's account-access requirement is satisfied.

Manual path: sign in; continue setup while skipping optional groups and
Intervals.icu; choose **Build my first workout**; create a workout and add an
exercise; open Today and start that workout; log a set; finish; inspect History.
Exercise targets can be edited from Workouts. Profile contains account export,
account deletion and privacy/support links.

Feedback: near workout completion, choose **Talk about your workout**. Type a
note or choose the microphone option, stop recording, edit the transcript and
choose **Save feedback**. Microphone/speech permission denial permits typing or
skipping. Real transcription depends on supported on-device language/model
availability; simulator synthetic speech is not a demo of actual recognition.

Claude: Profile → Coach explains access to training/health records through
Anthropic. A member uses their own compatible Claude account, generates a connect
code, adds the Très Fort connector and explicitly authorizes it. Profile can
revoke the connection. Never place a real connect code in public review notes.

Apple Health: Profile → Apple Health explains server upload and coach access
before the member opens Apple's permission sheet. The app reads workouts and
available summaries; it does not write to Health. Optional group sharing is
off by default. Intervals.icu requires the reviewer's own authorized account or
an explicitly approved nonpersonal review arrangement.

Account deletion: Profile → Delete Account, confirm, and complete fresh Apple
authentication if requested. Verify with a designated review/test account;
never delete the operator's account to demonstrate this path.

## Privacy and rating preparation

The following is an evidence worksheet, not completed App Store answers.
No advertising/tracking SDK is present in the examined source. App functionality
is the proposed purpose for account and training data; verify all provider log
and diagnostic practices before finalizing the declaration.

| Data | Observed source/use | Proposed classification to verify |
|---|---|---|
| Apple identity, optional name, relay/ordinary email | Sign in with Apple; account profile | User ID, name, email; linked to user; app functionality |
| Exercises, sets, durations, training load | Shared training service and history | Fitness; linked to user; app functionality |
| Imported heart-rate/health workout summaries | Optional HealthKit and Intervals imports | Health and fitness; linked to user; app functionality |
| Saved notes, fatigue, plan details, group names | Member/coach authoring, history and group feed | Other user content and relevant health/fitness data; linked to user |
| Request/error diagnostics | Cloudflare observability and provider operation | Confirm actual retained fields and linkage before selecting diagnostic categories |
| Microphone recording | On-device transcription; discarded | Audio is not uploaded; saved transcript is user content |

The required-reason manifest declares app-private UserDefaults use (`CA92.1`).
It does not substitute for App Privacy answers or assert that the backend
collects no data. Audit the final archive for every required-reason API and any
third-party SDK manifest before upload.

Age questionnaire: health/wellness topics and user-generated group names/notes
must be evaluated truthfully. There is no general chat, gambling, purchase,
advertising or open-web browsing feature in the examined source. Do not select
a final age rating or attest answers until the group review scope is resolved.

## Public-group and backup design requirements

Private membership does not by itself settle Apple's Guideline 1.2. Members see
other members' display names, activity titles and notes. Existing controls allow
leaving, not reporting or blocking. Prepare a narrow design for reporting,
blocking and objectionable-content handling; keep enforcement shared across
REST/MCP feed and statistics. Owner policy must specify report handling and
retention before storing reports or changing another member's visibility.

The candidate migrates training snapshots, queued writes, runner recovery,
HealthKit anchors and Intervals metadata into app-owned files with complete
file protection and backup exclusion. Ordinary settings and account identifiers
remain in UserDefaults. Protected copies and deletion markers take precedence
over stale preference values; a failed migration preserves its source bytes.
Unreadable durable work pauses feature requests, and failed saves do not claim
a queued write. Foreground return retries storage after a normal device unlock;
unresolved failures expose Retry and support controls.
An unsuccessful navigation save asks the member to retry storage and reopen
the link or choose the destination again. Sign-out preserves the account until
saved navigation can be cleared; confirmed account deletion can explicitly
erase unreadable local data.
An explicit Apple Health disconnect can reset an unreadable sync cursor without
erasing workouts. Failed resets stop Health syncing and retain a retry control
across relaunch; a later connection rebuilds its cursor through idempotent import.

Verify protection on a physical iPhone and audit the final archive before
finalizing privacy answers. The old TestFlight build cannot read the new local
format: a rollback must retain the protected-storage reader or first reconcile
all pending work. Backup exclusion also means unsynced device-only work is not
recoverable from an iCloud device backup; server-acknowledged history can sync
again after sign-in.

Sources checked 2026-09-10: [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[UserDefaults](https://developer.apple.com/documentation/Foundation/UserDefaults),
[backup exclusions](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup).
