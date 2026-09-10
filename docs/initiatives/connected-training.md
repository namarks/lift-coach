# Connected Training

Slug: connected-training · Status: planned · Updated: 2026-09-07

## Objective

Give athletes one trustworthy view of connected workouts and a dependable
private-group experience, without expanding Tres Fort into an endurance
authoring platform or general social network.

The [completed coaching context](../plans/completed/coaching-feedback-loop/plan.md)
provides the shared scheduling heuristic and unknown-input projection.

## Scope

- plan:activity-integration-integrity#P0
- plan:activity-integration-integrity#P1
- plan:activity-integration-integrity#P2
- plan:group-experience-and-governance

## Priority policy

1. Establish canonical activity identity and civil dates before claiming feed
   correctness.
2. Favor reconciliation, invite continuity, and essential controls over new
   engagement features.
3. Add the bounded reaction and notification slice only after the core feed and
   join path are reliable.
4. Keep source truth distinct from interpretation: missing load/duration stays
   unknown and conflict labels explain their scheduling heuristic through the
   shared coaching context, not a new physiology engine.

## Completion condition

Connected activities converge once on the correct local day through connect,
correction, and deletion; the private-group feed, invites, reactions,
notifications, and essential controls pass their multi-user behavioral
contracts. Optional HealthKit write-back is decided separately and is not
required for this initiative.
Calendar and coaching views also preserve the same unknown/incomplete input
state instead of turning missing endurance data into a known easy workout.

## Stop rules

- Stop at production credentials, new health-data permissions, production
  notifications, deployment, or release until separately authorized.
- Keep the M5 intervals.icu endurance write bridge outside this initiative; it
  remains a candidate behind its existing provider and product-value gates.
- Stop if the work requires public social features, organization roles, or a
  generalized event-processing platform rather than the bounded outcomes in
  the member plans.
