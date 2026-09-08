# Reversible Plan Management

Slug: reversible-plan-management · Status: gated · Updated: 2026-09-07 · Theme: training-trust

## Goal

Make every successful AI- or app-authored workout-plan change inspectable and
reversible without replacing the existing versioned-document model. A revert
restores a prior complete plan as a new version, preserving the history and
audit trail rather than rewriting them.

## Phases

- [x] **P0 — Atomic plan snapshots**
  - Store the canonical plan tree, schedule, and plan metadata alongside the
    resulting version for each successful plan mutation.
  - Reuse the canonical serializer and the commit boundary established for all
    writers by prescription-integrity P1. Current slot updates and audit calls
    are not universally atomic. A failed mutation must produce neither a
    partial edit, new version nor a misleading snapshot.
  - Prove snapshot round trips for representative MCP and iOS edit paths.
- [x] **P1 — Conflict-safe revert**
  - Add one user-scoped service operation and MCP tool that restore a selected
    snapshot only when the caller supplies the current expected version.
  - Commit the restored document as a new version with audit and coaching-note
    records; retain the version being reverted and reject foreign-plan history.
  - Cover stale-version, repeated, and cross-user attempts in the Workers/D1
    test runtime.
- [x] **P2 — Readable change history**
  - Expose a compact recent-version list with actor, reason/note, timestamp, and
    a useful plan-level summary so MCP and iOS can explain what changed before a
    revert.
  - Add a simple comparison view only for fields users need to decide whether to
    restore; measure snapshot growth before adding pruning policy.
  - Verify both AI and manual app edits appear in the same history.
- [ ] **P3 — Owner-approved service and app release**
  - [x] **(a) Release the reviewed service and migrations**
    - Migrations through `0042` and exact reviewed Worker source `2e67f93` are
      live. The source/schema were independently verified. Recovery must retain
      snapshot, lineage and active-fence guarantees.
  - [ ] **(b) Release and verify the app with an approved canary**
    - [x] Release the reviewed app: `0.1.0 (32)` from merged source `0d39656`
      is Apple `VALID`, `IN_BETA_TESTING`, and assigned to the existing internal
      Testers group. This includes the reviewed target-save acknowledgement fix.
    - [ ] Install and exercise the released app, then run the separately
      approved production edit/restore canary. Verify shared app/coach history
      and conflict-safe restore; TestFlight availability alone does not prove
      these behaviors. See [release evidence](decisions.md).

## Execution frontier

- P3(b)

## Next step

**Now (@owner):** Install TestFlight `0.1.0 (32)` and approve the concrete
production edit/restore canary. The service, authenticated reads, app upload,
and internal tester availability are verified. Device installation and the
production mutation/restore path remain unexercised; the
[release evidence](decisions.md) preserves the exact source and artifact.

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P0 | blocked_by | plan:prescription-integrity#P1 | A snapshot cannot repair partial or lost edits; mutation/version/audit must share a proven boundary first. |
| P3(b) | gated_by | external:owner-training-trust-app-canary-release | TestFlight is available; a concrete production edit/restore canary still needs explicit owner authority and device verification. |

## Notes / open questions

- Source: the August 2026 functionality review at commit `91fd622`; current audit
  rows are not a complete recoverable plan representation.
- Keep this as full-document snapshots over the existing small plan tree. Do not
  introduce event sourcing, branches, arbitrary merge logic, or retention
  machinery without measured need.
