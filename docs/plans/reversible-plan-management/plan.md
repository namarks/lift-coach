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
  - Authorize and apply the pending migration sequence through the snapshot and
    coach-grant migrations before deploying the reviewed Worker. Retain a
    snapshot/lineage-aware rollback or forward-fix plan.
  - Release the reviewed iOS build through a separately authorized TestFlight
    upload, then verify shared app/coach history and conflict-safe restore with
    an approved canary. Do not infer release from repository checks.

## Execution frontier

- P3

## Next step

**Now (@owner):** Authorize P3's reviewed migration/Worker release and separate
TestFlight upload with a compatible rollback. P0–P2 are complete for repository
delivery. The [snapshot contract, growth measurement and release boundary](decisions.md)
record local proof; deployed history and restore remain unexercised here.

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P0 | blocked_by | plan:prescription-integrity#P1 | A snapshot cannot repair partial or lost edits; mutation/version/audit must share a proven boundary first. |
| P3 | gated_by | external:owner-training-trust-production-release | Production migrations, Worker deployment and TestFlight are explicit owner release actions. |

## Notes / open questions

- Source: the August 2026 functionality review at commit `91fd622`; current audit
  rows are not a complete recoverable plan representation.
- Keep this as full-document snapshots over the existing small plan tree. Do not
  introduce event sourcing, branches, arbitrary merge logic, or retention
  machinery without measured need.
