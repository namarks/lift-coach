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
