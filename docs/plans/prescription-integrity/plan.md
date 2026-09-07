# Prescription Integrity

Slug: prescription-integrity · Status: active · Updated: 2026-09-07 · Theme: training-trust

## Goal

Every accepted workout prescription is valid, concurrent field edits cannot
silently overwrite each other, and a requested reduction cannot make a target
harder. Preserve one versioned plan tree and shared REST/MCP service boundary.
Snapshots and undo complement these guarantees; they do not replace them.

## Phases

- [ ] **P0 — Validate prescription values at the shared boundary**
  - Define runtime validation for complete and partial exercise prescriptions:
    integer counts/order, finite numeric load, RPE domain, nonnegative rest,
    positive timed duration when present, ordered rep ranges, string/JSON
    shapes and modality-aware signed assistance. Preserve intentional nulls
    and reject wrong types rather than relying on TypeScript annotations or
    advertised MCP input schemas.
  - Apply the contract to all existing create, add, patch, swap and full-plan
    replacement paths, including service calls used by REST and MCP. Validate
    the merged prescription for partial updates and check the destination
    modality when carrying targets during a swap.
  - Return stable field errors without mutating the tree, version or successful
    audit history. Audit existing rows with local/synthetic fixtures and design
    an explicit recovery path for invalid legacy rows; do not silently coerce
    production history or weaken the Swift decoder.
  - Verify REST and MCP reject `target_sets: "three"`, `target_rpe: 99`,
    inverted ranges and invalid durations, while accepting legitimate holds,
    fractional load and negative assistance. Round-trip accepted values through
    the Swift models. Use real Workers/D1 tests beyond the review reproducer.
- [ ] **P1 — Commit patches, version and audit consistently**
  - Remove read-merge-write lost updates in `updateExercise`: disjoint patches
    must compose, or a stale writer must receive an explicit conflict. Never
    report two successful edits while restoring a stale value from one caller's
    whole-row snapshot.
  - Use the existing atomic plan-write conventions for field edits, reorder,
    swap and adjustment. Keep changed fields, order normalization, version
    increment, audit and required note/snapshot contributions within a proven
    commit boundary. Snapshot storage itself belongs to reversible-plan-management.
  - Decide and document same-field concurrency for legacy callers before adding
    expected-version inputs. New authoring operations use explicit version
    checks; do not break released callers by silently making a new field
    mandatory. Keep a bounded compatibility path with equivalent data integrity.
  - Tests force disjoint and same-field interleavings, mutation/version/audit
    failures, duplicate retries where idempotency is promised, and deletion or
    plan replacement racing an edit. Acknowledged data must remain visible at
    the corresponding plan version.
- [ ] **P2 — Honest adjustment scope and monotonic reductions**
  - Make `adjust_today` state in its description and result that it changes
    recurring template targets, and name the affected workouts. Preserve the
    current omitted-day whole-plan behavior only with explicit wording; do not
    imply a one-date override or quietly introduce session template copies.
  - A positive target must never increase during reduce-intensity; negative
    assistance must never move toward zero. Use units and supported increments
    deliberately, preserve zero and report an honest no-op when no representable
    reduction exists. Verify all magnitudes with 4 lb, fractional loads,
    zero-load work, assisted exercises and one-set volume prescriptions.
  - Route adjustment through P0/P1 validation and mutation semantics. Explain
    which dimension changed, the before/after values and persistent scope in
    audit/notes and the returned result. Do not characterize a fixed scalar as
    an individualized physiological deload prescription.

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P1 | coordinates_with | plan:reversible-plan-management#P0 | Establish one commit boundary for field edits and snapshots. |
| P1 | coordinates_with | plan:bodyweight-training-support#P2 | Swap exposure must reuse the repaired writer and destination validation. |

## Next step

**Now (@agent):** Implement P0 validation, P1 atomic writers, and P2 honest
reductions in that order, with focused Workers/D1 regression proof. Nick
activated repository delivery through the Training Data Trust initiative on
2026-09-07; changes to stored production prescriptions remain unauthorized.

## Notes / open questions

- Source: [September app review](../../reviews/2026-09-app-review/report.md).
  Its [reproducer](../../reviews/2026-09-app-review/evidence/prescription-write-repro.mjs)
  exercises the actual service over in-memory SQLite with all reviewed
  migrations: invalid types persist and two disjoint successful patches lose
  a value. It is not a production or Workers-runtime reproduction.
- Keep the completed server-mutation-integrity work as history. Its successful
  set/session validation does not prove value validation or atomicity for every
  plan-slot writer. Do not reopen completed phases to rewrite that history.
- Expected-version checks, an allowlist of fields and a successful audit call
  are separate properties. Tests must prove each promised behavior together.
