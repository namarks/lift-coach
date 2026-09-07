# Training Data Trust

Slug: training-data-trust · Status: gated · Updated: 2026-09-07

## Objective

Make training and plan mutations trustworthy at the points where the deep
functionality review found real loss or corruption: server writes stay scoped
and deterministic, gym-floor intents survive interruption, authentication does
not erase local data, and plan changes can be inspected and restored.

## Scope

- plan:coach-access-integrity
- plan:prescription-integrity
- plan:reversible-plan-management

## Priority policy

1. Prioritize confirmed grant-consumption, invalid-prescription and lost-edit
   failures from the September review. Activate member plans only under explicit
   planned-work authority; serialize only real collisions.
2. Fix confirmed snapshot, revert-history, and invalid-write failures before
   adjacent cleanup. Each slice carries its own focused regression proof instead
   of waiting for a portfolio-wide audit.
3. Reuse the completed server, workout-write, and identity contracts as
   historical foundation; reopen them only for a concrete regression.

## Completion condition

The completed server-set/session, workout-write and Apple account-lifecycle
work remains the foundation. Completion now also requires concurrent coach
exchanges to have one successor, prescriptions to be valid and atomically
audited, reductions to respect their stated scope/direction, and AI/manual
edits to share readable snapshot-and-revert history. Repository proof and
owner-approved production/lifecycle transition evidence remain distinct.

## Stop rules

- Stop before any TestFlight/App Store release, production migration, or deletion
  of a real account without the authority specific to that action.
- Do not expand a verified finding into a blanket security audit, generic sync
  platform, event-sourced plan model, or unrelated product cleanup.
- Stop when no selected node is ready or canonical state has drifted.
