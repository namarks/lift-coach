# Bodyweight implementation contracts

## Saved prescription and identity

`POST /api/days/:id/exercises/:teId/swap` accepts `to_exercise` and a required
positive integer `expected_version`. It resolves the exact slot within the
caller's active plan and the URL's day. Foreign, archived, or mismatched slots
return 404. Malformed input and targets invalid for the destination modality
return 400. A stale version, including a write racing the D1 commit, returns
409 without replaying the replacement against a newer prescription.

The existing shared `swapExercise` writer changes only the slot's exercise and
update timestamp. Targets, rest, progression, cues, ordering, warm-up flag, and
slot ID remain intact. The swap, plan version, audit, and full-plan snapshot
commit together. Historical set IDs, exercise IDs, values, and slot references
remain unchanged. MCP retains its legacy day/name lookup and bounded conflict
retry, plus its atomic coaching note. The ignored `carry_targets` option is
removed from the service interface and advertised MCP schema; swaps consistently
carry the saved prescription rather than invent destination defaults.

## Client behavior

The exercise row's options menu opens a searchable replacement picker. The
picker captures the reviewed plan version and confirms the destination. A
changed plan disables further selection until the picker is reopened. The
server remains authoritative for prescription compatibility.

A successful response closes the picker even when the following state pull
fails. Further editor actions require refresh in that case. A conflict refreshes
the plan and asks the member to review the latest targets; it never silently
reissues the old selection. Account/session ownership is checked again after
awaited work so a late response cannot modify a signed-out feature model.

## Verification and release

Real Workers/D1 tests cover duplicate slots, preserved historical logs and
targets, timed assistance, tenant/day/active-plan scoping, malformed requests,
concurrent target edits, snapshot-failure rollback, and MCP note/schema parity.
Client tests cover successful replacement, failed post-write refresh, stale
version recovery, validation rejection, and a late acknowledgement after sign-out.
The existing runner replacement tests cover identity changes during execution.

No migration is required. Deploy the reviewed Worker before distributing an iOS
build that exposes replacement. This implementation has local simulator evidence;
it does not claim a production canary or physical-device verification. The P2
request authorized repository delivery only. The separately authorized P3
contract follows below; production/TestFlight release remains separate.

## P3 comparable metrics (2026-09-07)

P3 supersedes the P1 positive-added-load Epley policy. Bodyweight and timed
catalog modalities never produce an estimated 1RM, even with positive added
load. Conventional barbell, dumbbell and machine rep work retains Epley;
unknown modalities fail closed. No body mass, equipment normalization or
exercise-family model is inferred.

A rep or hold comparison is keyed by catalog exercise/variation ID, per-set
execution mode, exact signed external load, unit, laterality and load mode.
Strict work, each assistance amount, each added load and each hold load have
separate best values and history series. Seconds come from `duration_s`, with
legacy timed `reps` as a fallback. An explicit rep flag overrides incidental
wall-clock duration. Per-side reps and per-hand loads remain independently
multiplied for work totals; best-set reps stay per side and Epley stays per
logged implement. Warm-ups and deleted sets never enter these comparisons.

History exposes `cohorts` alongside its existing session work totals. Mixed
bodyweight/hold conditions have `top: null` and `metric: mixed`; scalar best
reps/hold fields are null when multiple loads compete for that metric. A
conventional estimate may still summarize eligible rep work. Pooled reps are
work logged, not a strength claim. `tonnage_basis: external_load` labels
history, volume and MCP write results; unsupported strict, assisted and timed
work retains null tonnage. The projection does not rewrite any set record.

The feed adds `cohort_top_sets`. Updated iOS uses it, falling back to legacy
`top_sets` from older servers. For installed clients that key rows by exercise
name, `top_sets` remains one row per exercise: a single condition or a valid
conventional estimate. It omits incompatible bodyweight/hold combinations.
The legacy numeric estimate stays zero when unavailable. Both fields preserve
the feed's existing exclusion of notes and RPE. New iOS also suppresses old
servers' unsupported bodyweight estimates.

History charts and both completion surfaces use the same Swift cohort
projection. Hold value labels include nonzero load, and all sessions remain
expandable to inspect their individual working sets. This slice supplies
comparable best values; it does not add the runner's future PR notification
feature. `BodyweightProgress.json` is shared by real-D1 REST/MCP/feed tests and
iOS history, completion and feed-rendering tests.

P3 requires no migration. Worker deployment and TestFlight distribution remain
separate owner actions. Existing application builds retain their local P1
history behavior until upgraded, even after a Worker release; repository merge
alone does not make the correction live.
