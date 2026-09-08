# Gym Runner Depth delivery contract

## Prescriptions and corrections

The active slot shows prescribed values and cues separately from the last
comparable session. History respects slot, warm-up/working and timed/rep
context. Explicit targets win; an intentional input draft survives recovery
only while its prescription signature matches. Optional RPE and the displayed
plan id/version/day are persisted with the original set intent before network
work begins.

Set edits and deletes use a durable account-local correction queue. The queue
retains the original set UUID and session attempt; it binds the observed row
revision once, after the original create is acknowledged if necessary. A
canonical session alias or server-detached historical slot can be acknowledged
without creating another set. A stale competing edit returns 409 for review.
Pending deletes remain visible, failed actions offer recovery, and the final
set remains editable before finishing. A correction acknowledgement merges
the authoritative set and session before clearing the queue entry. If local
cache persistence fails, the app requests a full refresh and retains the saved
status; a later refresh failure cannot turn it into an unsaved edit. Runner position and the
current rest deadline remain intact.

## Loading and timers

The barbell guide uses standard lb plates and an editable bar weight. It shows
the exact achievable load and any remainder. The deterministic warm-up guide
starts with the bar and rounded-down 50%/75% steps, deduplicating light loads;
its editable steps are guidance and do not create logged sets. Equipment
inventory, optimization and automated programming are outside this delivery.

Rest and timed-set controls reuse the existing notification and Live Activity
paths. Each timer has an account-owned token, so obsolete controls cannot act
on a replacement timer or another account. Rest supports extension/end; timed
sets support stop-and-log. Timed completion durably queues the captured values
before awaiting notification cleanup. Sound preference changes update the
active cue without altering the timer deadline. The shared control uses
Apple's [LiveActivityIntent app-process execution contract](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
Physical-device locked/background sound delivery is a release smoke check;
simulator tests establish deterministic ownership, deadline and logging behavior.

## Persisted completion feedback

Migration `0043_runner_targets.sql` adds nullable starting-target JSON to each
session. New app log intents name the immutable plan snapshot shown at the tap,
so an offline upload after a coach edit retains the original prescription.
Missing snapshot history remains unavailable. Older callers snapshot the
selected day when the first set is accepted. No old started workout is
backfilled. Explicit restart clears the snapshot, and detached slot attribution
never becomes a false missed-target claim.

One server projection supplies Today completion, history and MCP. It reads
persisted rows, excludes warm-ups/deletions, and uses Bodyweight P3's shared
metric cohorts. A PR requires a strictly better rep/hold result at the same
exercise, load/assistance and mode with an existing baseline. No body mass,
bodyweight e1RM or cross-assistance normalization is introduced. Queued
completion stays pending until acknowledgement; summary failure cannot revoke
an accepted finish. Corrections and deletions recompute future summaries.

## Verification and release handoff

Final verification is recorded in the sibling plan and delivery PR. Regression
coverage includes prescription changes, offline RPE recovery, failed/delayed
corrections, final-set review, canonical identity, discard/restart races,
notification races, obsolete timer controls, tap-time plan history, shared
bodyweight metric fixtures, and acknowledged completion with failed refresh.
Synthetic simulator renders cover active runner, final review, loading guide
and persisted summary; the temporary rendering harness is not shipped.

Repository delivery does not activate migration `0043`, deploy a Worker, or
publish TestFlight. Under separate owner release authority, apply pending
migrations through `0043`, deploy the reviewed Worker, then distribute the iOS
build. The new correction acknowledgement and summary endpoints require that
Worker before the new app. Retain the additive column on rollback; a previous
Worker/app pair can ignore it. Before distribution, smoke-test foreground,
background and locked rest/timed controls and sound on a physical device.
