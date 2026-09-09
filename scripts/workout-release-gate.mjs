// Remove this temporary guard only in workouts-and-multi-session P0(c).
console.error(`Workout rename requires the staged rollout in
  docs/plans/workouts-and-multi-session/rollout.md
The combined migration-before-deploy release and unqualified remote migration
are disabled for this compatibility window. Release A must be verified live
before migration 0045. No remote command was executed.`);
process.exitCode = 1;
