# Bodyweight Training Support

Slug: bodyweight-training-support · Status: active · Updated: 2026-09-07 · Theme: gym-floor

## Goal

Let a calisthenics or bodyweight-first member prescribe, run, progress, and
review their training with the same fidelity a barbell lifter gets, with or
without Claude. Done means holds, rep ranges, added load, and assistance are
first-class on bodyweight slots; history and volume report numbers that mean
something for zero-load work; and the catalog covers the standard
gymnastic-strength movements.

## Phases

- [x] **P0 — Holds, rep ranges, and the missing catalog rows**
  - Seed the catalog with the gymnastic-strength staples that are absent:
    ring dip, ring row, ring push-up, ring support hold, bar and ring
    muscle-up, L-sit, tuck and full front lever, back lever, tuck planche and
    planche lean, handstand hold, wall walk, crow pose, skin the cat, dragon
    flag, typewriter pull-up, eccentric pull-up, back extension, reverse
    hyper, and gymnastic bridge. Use `timed`/`sec` for static holds and
    `bw`/`lb` for rep work, add spoken-name aliases for the resolver, and
    follow the additive `INSERT OR IGNORE` pattern of migration `0021` with a
    catalog replay test. Update both exact row-count assertions
    (`test/catalog.test.ts` and `test/catalog_v2.test.ts`, 254 today) and
    re-check the alias-uniqueness and alias-determinism tests in both files:
    `ex_dips` already owns the plain dip aliases and `ex_superman` carries
    "back extension bw".
  - Let the iOS configure-exercise screen mark any exercise as a timed hold
    and prescribe a rep range, using the existing `target_duration_s` and
    `target_reps_max` slot fields; the REST editor route and MCP already
    accept both. The runner already declares per-set `is_timed` when it logs
    (migration `0024`) and the per-set value labels consume it, but the
    history duration chart still gates on catalog modality, so a
    duration-pinned hold on a `bw` exercise needs that chart re-keyed to
    `is_timed` in the same slice.
  - Close out the timed auto-log report. Open issues #71 and #92 are
    re-mirrors of the same TestFlight submission as #55, which `9a533e8`
    fixed with `finishTimedSetAuto`; the residual gap is that the runner's
    countdown task is cancelled when the view disappears while `timedActive`
    stays true. Cover the backgrounded and view-dismissed cases and close
    #71 and #92 as duplicates of #55. The mirror that re-filed them is an
    open question below, not a deliverable here. Planks, L-sits, and hangs
    are the timed slots a bodyweight plan leans on.
  - Completion evidence (2026-09-03): PR #113 delivers the 22-row additive
    catalog migration, hold/rep-range authoring, per-set timed history, and
    model-owned timed completion with foreground catch-up. Local verification
    passed TypeScript typecheck, all 492 Worker tests, iOS build-for-testing,
    and all 164 iOS unit tests after reconciling current `main`. Issues #71 and
    #92 are closed as duplicates of #55. The checked phase and this evidence
    land atomically with the reviewed
    PR; no remote migration, Worker deployment, or TestFlight publication is
    part of the merge.
- [x] **P1 — Added load, assistance, and honest metrics**
  - Define `weight` on a `bw` or `timed` slot or set as added load: positive
    for a belt or vest, negative for band or machine assistance, zero for
    strict bodyweight. Write the convention into the `log_set` and
    `add_exercise` tool descriptions so Claude and iOS agree; no schema
    change. Today iOS hides the weight control and pins the logged weight to
    zero whenever the catalog modality is `bw`, the timed runner hard-codes
    weight zero when it commits a hold, and `adjustWeight` / `setWeight`
    clamp at zero, so the clamp must be lifted for these slots before a
    negative value can be entered.
  - Show an added-load / assist control in the runner for bodyweight and
    timed exercises, defaulting to zero, and render "BW+45 × 5", "BW−30 × 8",
    "BW × 8", and "45s" consistently in Today, history, the day agenda, and
    the group feed. The group feed's server DTO must start carrying
    `is_timed` and `duration_s`; today it renders every set as weight × reps.
  - Report rep-based metrics for bodyweight exercises (best set, total reps
    per session) and best hold for timed exercises; show estimated 1RM only
    when added load is positive. Keep tonnage undefined for zero-load work
    rather than reporting zero or inventing a body mass, and exclude
    negative-load (assisted) sets from tonnage rather than letting them
    subtract from it. Today the Epley top-set and tonnage rollups compute to
    zero for every bodyweight set.
  - Cover the convention with backend tests on the history and volume
    rollups and with iOS rendering tests for the three value forms.
  - Completion evidence (2026-09-03): the runner now uses one load-entry path
    for conventional, bodyweight, and static-hold exercises; bodyweight and
    hold work accept signed external load while cardio retains its duration-only
    control. One formatter renders persisted, pending, agenda, history, and
    group-feed values. Backend and iOS history use reps or duration for
    zero/assisted work, expose Epley estimates only for positive loads, and
    leave tonnage undefined when no positive rep-based load exists. Local
    verification passed TypeScript typecheck, all 495 Worker tests, and all 168
    iOS unit tests. The checked phase and this evidence land atomically with the
    reviewed PR; no remote migration, Worker deployment, or TestFlight
    publication is part of the merge.
- [x] **P2 — Progress by variation in the app**
  - Expose the shared swap-exercise service over the authenticated REST
    editor path and add a "Replace with…" action in the iOS editor that keeps
    the slot's targets, order, and warm-up flag. Swaps always preserve saved
    targets; remove the previously ignored `carry_targets` option from the
    service interface and advertised MCP schema.
  - Record the swap in the same audit trail and version bump as other plan
    edits so Claude can see that the member advanced a progression.
  - Validate carried targets for the destination modality and reuse the shared
    prescription writer. Reuse the completed prescription-integrity contract
    so REST exposure retains validation and atomic swap semantics.
  - Completion evidence (2026-09-07): exact-slot REST replacement requires the
    observed plan version, validates carried targets, and commits the swap,
    version, audit, and snapshot through the shared writer. iOS provides a
    searchable replacement picker, confirmation, conflict recovery, and
    acknowledged-write handling when refresh fails. Logged exercise identities
    and values remain unchanged. Local checks passed all 737 Worker tests,
    TypeScript, and all 287 iOS tests, including seven new D1 regressions and
    five new client tests. See [the P2 contract](decisions.md). Repository
    delivery does not deploy the endpoint or publish an iOS build.
- [ ] **P3 — Compare like-for-like progress**
  - Supersede P1's positive-added-load Epley policy: added load alone is not
    system load, so suppress bodyweight e1RM until an exercise-specific model
    with required inputs has been justified. Keep the completed P1 delivery as
    history; do not relabel it as unimplemented or invent body mass.
  - Separate strict, assisted and added-load rep/hold cohorts. Compare PRs only
    within a compatible exercise/variation, execution mode and external-load
    condition. Show load next to rep/duration summaries; pooled rep totals may
    describe work but cannot imply like-for-like strength progress.
  - Share fixture expectations across backend history/volume, group-feed
    DTOs/rendering, iOS history, runner completion and MCP. Cases include strict
    8 reps versus heavily
    assisted 15; BW+10 by 5 with no body mass; lighter versus heavier holds;
    per-hand/per-side work; warm-ups, deleted rows and mixed rep/timed history.
  - Preserve historical raw records, nullable tonnage for unsupported work and
    the ability to inspect all sets. Label positive-load volume as external
    load, not total bodyweight tonnage. Do not create arbitrary normalization
    across equipment or progression variations.

## Execution frontier

- P3

## Dependencies

P2 reuses the completed [prescription validation and atomic writer](../completed/prescription-integrity/decisions.md) for carried targets and swap exposure.

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P1 | coordinates_with | plan:gym-runner-depth#P0 | Both change the runner's value-entry controls; serialize the shared surface. |
| P1 | feeds | plan:coaching-feedback-loop#P2 | Rep-based and hold-based history gives the coach usable bodyweight progress signals; it does not block coaching work. |

## Next step

**Now (@agent):** P3 is the next repository slice: compare compatible
bodyweight/load/hold cohorts and suppress unsupported bodyweight e1RM. P2
implementation is complete; release of its new REST endpoint and iOS picker
requires separate owner authority, with the Worker deployed before the app.
The P2 execution request does not authorize P3 implementation or release.

## Notes / open questions

- P3 responds to the [September app review](../../reviews/2026-09-app-review/report.md):
  the shipped implementation followed P1, but a positive-added-load Epley
  estimate and highest-reps comparison across assistance levels are not
  supported strength claims. The correction preserves P1's signed-load and
  timed-work improvements.

- Source: [research/calisthenics-readiness-review-2026-09.md](research/calisthenics-readiness-review-2026-09.md),
  a static review at commit `c71e3f9` plus the corrections from the two
  exact-head reviews of this plan. Its line references drift; verify against
  current code before acting.
- The TestFlight mirror that re-filed #55 as #71 and #92 is not the in-repo
  `beta:feedback` script, whose label (`beta-feedback`) and dedupe marker
  (`asc-feedback`) differ from the `testflight-feedback` / `ASC-ID` pair
  those issues carry. Finding and fixing that mirror is an owner question
  outside this repository.
- Body-mass tracking is deliberately out of scope. True tonnage for weighted
  or assisted bodyweight work is the one need it would serve; rep-based
  metrics cover the coaching decision without it, so the roadmap candidate
  stays deferred.
- A stored progression family (knee push-up → push-up → archer → one-arm) is
  a schema decision. P2's swap plus rep ranges is the bounded alternative;
  promote the family model only if members outgrow it.
- Circuits, supersets, AMRAP, and EMOM are not representable in the flat slot
  list and are not in scope. Document the interim convention (reps is the
  minimum, reps-max unset, cue "AMRAP") in the tool descriptions during P1.
- Custom exercises stay a candidate; the P0 seed is the first answer to
  catalog gaps.
