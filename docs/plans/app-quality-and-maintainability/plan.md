# App Quality and Maintainability

Slug: app-quality-and-maintainability · Status: active · Updated: 2026-09-08 · Theme: platform

## Goal

Make the main training journey accessible and reproducibly verifiable, then
reduce measured client costs and change risk without replacing Tres Fort's
architecture. Existing unit tests, the service facade, civil-date parity and
durable account/attempt-bound writes remain the foundation.

## Phases

- [ ] **P0 — Reproducible iOS and contract verification**
  - Provide one documented command for unsigned XcodeGen build and existing
    iOS tests on an explicitly selected simulator/runtime, with disposable
    output cleanup and useful retained failure evidence. Add iOS build/tests
    to the repository's CI alongside backend checks using authorized capacity;
    no paid runner purchase or TestFlight publication is implied.
  - Include plan-graph validation in documentation-change checks. Document which
    CI results are required and make branch-protection changes only with their
    appropriate repository authority.
  - Establish deterministic, synthetic UI fixtures for fresh sign-in, verified
    empty plan, failed initial load, ordinary/bw/timed workout, pending write,
    correction failure and ready-to-finish states. Fixtures must not contact
    production or persist a real user's health data. Retain representative
    screenshots/walkthrough evidence and a small behavioral smoke suite for
    sign-in intent, creation, logging, correction and completion.
  - Keep numerical/calendar contracts comparable across TypeScript and Swift
    with shared fixture cases. Run checks tied to the changed surface; a green
    backend job alone is not proof of an iOS change.
- [ ] **P1 — Accessible end-to-end gym journey**
  - Fix confirmed enabled-control/text contrast and tiny unlabeled destructive
    actions. Provide contextual VoiceOver names/values, adequate touch targets
    (44 by 44 points for ordinary interactive controls), logical focus order
    and non-color state cues without losing the scoreboard visual identity.
  - Honor Reduce Motion for rest-complete animation. Make onboarding, load
    entry, error/recovery messages and completion controls reachable with large
    accessibility text and the keyboard. Preserve custom-font scaling; do not
    infer a Dynamic Type defect merely from use of custom fonts.
  - Verify the P0 fixtures on the smallest supported layout and a current
    device size, with VoiceOver, large text and Reduce Motion. Record simulator
    versus physical-device evidence separately. Audio/lock-screen cues and
    interruption behavior require an authorized device walkthrough before a
    release claim.
- [ ] **P2 — Measured hot paths and bounded module extraction**
  - Measure cached cold launch, calendar open/scroll, exercise history and
    log/acknowledgment with a small history and a synthetic multi-year history.
    Record dataset dimensions, hardware/runtime, main-thread duration, snapshot
    size and repeatable baselines; select budgets from those observations.
  - Investigate repeated session/date/exercise scans, eager History rows and
    full-snapshot encoding/decoding on the main actor. Add indexes/cached
    projections/lazy rows or move work only where measurement supports it.
    Incremental network sync alone does not prove bounded client processing.
  - Extract tested pure metrics/projection and cohesive persistence/runner
    responsibilities from `SyncModel` during those changes. For backend
    prescription work, use focused internal service modules behind `db.ts`'s
    public facade when that reduces duplicated validation/transaction logic.
    No file-size quota, wholesale rewrite, new database, generic repository
    framework or speculative optimization is a completion requirement.
  - Preserve account epochs, attempt tokens, tombstone ordering, authoritative
    ACK handling and calendar parity in behavioral tests. Compare before/after
    results and record any tradeoff in memory or retained history.
  - Reconcile current README/DESIGN/agent guidance with verified behavior:
    manual authoring, in-memory/account-scoped snapshot persistence, MCP
    structured conflicts, and the exact atomicity of field edits. Separate
    historical design intent from current implementation claims.

## Dependencies

[Completed Gym Runner Depth](../completed/gym-runner-depth/plan.md) supplies
the shared prescription controls, durable corrections and runner presentation.
Reuse that delivered path when changing the runner.

P2 preserves the completed [validated atomic prescription writer](../completed/prescription-integrity/decisions.md) during backend extraction.

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P1 | coordinates_with | plan:member-activation-and-adherence#P0 | Entry copy, errors and large-text layouts touch the same surfaces. |

## Next step

**Now (@agent):** Land P0 through current-head independent review and all three
CI jobs, then continue P1 accessibility from the synthetic fixture baseline.
The September 8 instruction activates this plan until human input is needed.
Physical-device walkthroughs remain owner work; measure P2 before choosing
performance changes.

## Notes / open questions

- [Completed bodyweight support](../completed/bodyweight-training-support/plan.md)
  supplies variation replacement and comparable metrics. Reuse the shared
  `BodyweightProgress.json` contract for bodyweight PR/hold claims; this is a
  delivered repository foundation, not an unresolved dependency.

- Source: [September app review](../../reviews/2026-09-app-review/report.md).
  The reviewed repository already has substantial XCTest coverage; the gap is
  CI and UI-state evidence, not an absence of iOS unit tests.
- Static repeated scans and large modules establish investigation targets.
  They do not establish measured jank, a battery regression or a need to move
  away from the single Worker/D1 design.
- [Apple design guidance](https://developer.apple.com/design/tips/) supplies
  control/legibility criteria. A compile, unit test or screenshot alone does
  not establish screen-reader or gym usability.

- P0 implementation: [verification command and CI contract](../../IOS-VERIFICATION.md),
  simulator-only synthetic UI fixtures and smoke suite, shared calendar cases
  alongside the existing bodyweight numerical fixtures. The
  [synthetic simulator baseline](evidence/p0/README.md) retains the passing
  walkthrough screenshots and exact copied-source hashes. A confirmed initial-load
  failure now offers retry instead of claiming an empty plan. Repository delivery
  and P0 completion remain pending current-head review and terminal-green CI.
