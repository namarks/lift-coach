# Bodyweight P2 replacement contract

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
request authorizes repository delivery only. P3 metrics and production/TestFlight
release remain outside this execution scope.
