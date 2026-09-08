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
    - [x] The owner installed build 32 and verified an app-authored edit in
      shared snapshot history. The attempted restore returned the active-workout
      rejection; successful restoration remains unverified.
    - [ ] Complete the now-authorized coordinated production canary: verify
      shared app/coach history, stale-version rejection, successful app restore,
      and persistence of the original prescription. See [evidence](decisions.md).
    - The remaining restore blocker is a historical session that the owner
      explicitly authorized discarding. The app service supports discard, but
      the deployed coach interface lacks the action. Deliver the focused MCP
      wrapper through the existing service before performing that cleanup.

## Execution frontier

- P3(b)

## Next step

**Now (@owner):** Authorize the exact merged Worker source containing the MCP
discard wrapper after its review and CI gates pass. The historical workout's
discard is already authorized. After release, verify its sets are
soft-deleted and the restore blocker is gone, then complete the temporary coach
edit and app restoration. Invalid-prescription and stale-restore rejection have
passed live; successful restoration remains unverified. See [evidence](decisions.md).

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P0 | blocked_by | plan:prescription-integrity#P1 | A snapshot cannot repair partial or lost edits; mutation/version/audit must share a proven boundary first. |
| P3(b) | gated_by | external:owner-training-trust-discard-service-release | The canary and historical workout discard are authorized; the missing MCP capability requires a reviewed Worker release before the remaining live checks can proceed. |

## Notes / open questions

- Source: the August 2026 functionality review at commit `91fd622`; current audit
  rows are not a complete recoverable plan representation.
- Keep this as full-document snapshots over the existing small plan tree. Do not
  introduce event sourcing, branches, arbitrary merge logic, or retention
  machinery without measured need.
