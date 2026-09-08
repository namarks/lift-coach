# Prescription integrity contract

## 2026-09-07: shared validation and recurring adjustment

The shared database boundary validates complete prescriptions and the merged
result of a partial patch. Counts and order are safe integers; loads are finite;
RPE is bounded; rest is nonnegative; provided timed duration is positive; rep
ranges are ordered. Nullable values retain their meaning. REST and MCP pass
supplied values through validation rather than converting strings, booleans or
malformed objects into plausible defaults. Destination modality is checked when
swapping an exercise with carried targets.

Released callers may omit an expected version for slot edits. The writer uses
a bounded retry with fresh plan/slot state, validates again, and writes only
supplied fields. Disjoint patches compose when retried; same-field patches
serialize, with the later accepted patch taking effect. Exhausted or explicitly
versioned stale writes return a conflict. Mutation, ordering, version, audit,
required coaching note and snapshot share one transaction. Failed contributions
roll the transaction back. Snapshots preserve each accepted intermediate version.

Nick explicitly approved the repository arithmetic correction for `adjust_today`
on 2026-09-07. It retains the existing recurring-template scope and five-unit
rounding grid. A reduction is clamped so positive load never increases and
negative assistance never moves toward zero. Small/fractional loads and zero
may stay unchanged; one-set volume cannot reduce further. Results disclose
`recurring`, affected workouts, the changed dimension and before/after targets,
and `no_op`. These are deterministic target changes, not individualized
physiological recommendations. Omitted day selection means the whole plan.

## Invalid legacy prescription recovery

`test/prescription_integrity.test.ts` models an invalid pre-validation row with
text counts, reversed reps, excessive RPE, negative rest, unsupported signed
load and invalid warm-up values. The diagnostic returns field paths and leaves
the row/version/audit unchanged. A partial cue edit cannot launder invalid
stored values into an accepted prescription.

For an authorized audit, work from a local/synthetic copy, resolve catalog
modality, and parse stored progression JSON before calling
`validateExercisePrescription`. Report malformed JSON and invalid field paths;
do not coerce values or expose training contents in logs. A repair requires a
reviewed complete replacement containing valid values and the observed current
`expected_version`. On conflict, refetch and re-audit before proposing a new
replacement. Verify typed values and atomic attribution after acceptance.
The local regression proves this recovery path; it does not establish the
health of production rows or authorize modifying them.

## 2026-09-07: reviewed service released

Nick approved exact source `2e67f93` and migrations through `0042`. Production
now serves that source at 100%, with independent source/schema verification
recorded in the [shared release evidence](../completed/coach-access-integrity/decisions.md).
No production prescription was edited or corrected, and no validation or
attribution canary was executed. A concrete production canary and any legacy
repair remain separate owner decisions.

A subsequent aggregate SELECT found zero violations in the assessed count and
numeric domains, rep-range ordering, signed-load modality, warm-up flag,
progression JSON object/null shape and catalog references. The successful direct
query returned counts only and reported `changed_db=false`, `changes=0` and
`rows_written=0`. This is bounded evidence: cues storage, nonfinite REAL edge
encoding, complete plan/day structure, order density, snapshots, client decoding
and production mutation behavior were not established by that query. No legacy
repair is proposed from these results.

One diagnostic transport attempt needs a distinct caveat. The agent submitted
the single aggregate SELECT through Wrangler `--file`, which uses D1's import
endpoint. The service reported one query, zero rows written, `last_row_id=0`
and unchanged observed database size, but also `changed_db=true`, `changes=1`
and an advanced bookmark. The file contained no DDL, DML or additional statement;
Wrangler's inspected client implementation appended no SQL. This supports zero
reported application-row writes, not a claim of zero internal/control-plane
state change. The cause of the import metadata was not established. That path
was stopped; the authoritative aggregate result came from a later direct
`--command` SELECT. Use direct commands for future read-only diagnostics.

## 2026-09-07: coordinated live verification authorized

The owner installed TestFlight build 32 and supplied evidence of an iOS-authored
exercise edit and its baseline/change snapshots. Restore was rejected because
the server still reported an active workout. The owner subsequently asked the
assistant to perform the remaining verification and close the initiative.

The bounded invalid-edit, temporary coach-edit, attribution/history, and
conflict-safe restoration checks are now authorized. No legacy correction or
workout-record deletion is included. See the shared
[device verification and client-access evidence](../reversible-plan-management/decisions.md).
The successful app save establishes only its observed path. The subsequent
invalid-RPE and stale-restore probes both returned their expected rejection,
and independent connector/SQL reads confirmed unchanged version, snapshots,
successful mutation audits, and coaching notes. The accepted coach mutation and
successful restore remain pending the shared historical-workout discard path.
