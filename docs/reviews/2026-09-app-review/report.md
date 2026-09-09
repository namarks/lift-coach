# Tres Fort app review — September 2026

Reviewed: 2026-09-07 · Code source: `696c1d34c98d956a3e1fddf78fcfd5eba168e874`

Planning reconciliation: `e1b142a44ef5948eb4a2e8a76623a9dd6532a95a`.

Tres Fort has a well-chosen architecture and an unusually careful foundation
for durable workout logging. Its main weakness is the translation of intent:
valid coaching instructions can be lost between concurrent edits, historical
input defaults and incomplete summaries. The next investment should make the
existing training loop trustworthy and easy to use before expanding it.

The unfinished roadmap covers most product gaps. It did not adequately cover
OAuth token-consumption races, prescription validation/atomicity, or systematic
iOS quality verification. This review adds three plans for those gaps, tightens
eight existing workstreams and updates all four initiatives. It preserves
completed work and owner decisions. Application fixes are planned here, not
implemented by this review.

## Basis and limits

The review used the advertised remote default branch, fetched it, and verified
that `FETCH_HEAD` and `origin/main` both matched the source above. The shared
checkout was clean at `cbb7d5ff`; another Tres Fort task was active there, so
all work occurred on the isolated `codex/app-review-gap-plans-20260907` branch.
Source links below are pinned to the reviewed commit.

During finalization, remote main advanced to `e1b142a` with PR #137's storage
closeout. Fetch/diff verification showed only documentation changes and no
change to application source, migrations, dependencies or tests. This branch
incorporates that closeout: storage stays archived as completed and its
retired dependency is removed. The original code-test/reproduction evidence
therefore still applies. The current planning graph is compiled after this
reconciliation, not from the initial 11-plan snapshot.

Three independent reviews covered backend/security, iOS/product, and
workout/coaching semantics. The lead reconciled their findings against all
11 current plans, four initiatives and relevant completed histories, ran the
baseline tests, and revised the canonical plans. Evidence is classified as:

- **Reproduced:** actual route/service code with synthetic interleavings or
  in-memory SQLite. These harnesses have narrower scope than Workers integration.
- **Source-confirmed:** an explicit data path or missing behavior in this source.
- **Investigation:** a credible complexity/layout concern needing measurement.

No personal workouts, credentials or production health records were read.
No deployed Worker, migration, provider, TestFlight build or actual athlete
outcomes were independently validated. The separate task's merged storage
closeout is accepted as canonical repository evidence; this review does not
claim a fresh production audit. UI judgments are based
on source and simulator unit tests, not a visual/device usability study.

## Assessment across dimensions

| Dimension | Assessment | Main implication |
|---|---|---|
| Architecture and elegance | Strong core; implementation boundaries need care | Keep one Worker/D1 and shared domain behavior. Clarify atomic writers and extract cohesive modules as they change. |
| Efficiency and scale | Backend access patterns materially improved; client costs unmeasured | Incremental cursors, bounded reconciliation and query-plan guards exist. Measure full-snapshot client processing and repeated history scans next. |
| Data correctness | Strong set/session recovery, weaker prescription editing | Invalid targets and acknowledged lost patches are confirmed. Durable logging alone does not make the programmed workout trustworthy. |
| Security and privacy | Good account isolation and deletion fences; a material OAuth gap | Repair grant consumption and replay handling. Preserve private feedback boundaries and production authority. |
| Gym interaction | Clear primary action and timing; weak correction/intent presentation | Expose prescribed versus prior values and retain correction through the last-set boundary. |
| Visual/accessibility design | Coherent scoreboard language; uneven legibility and control semantics | Preserve the identity while fixing contrast, descriptive controls and large-text/keyboard states. |
| Activation and product framing | Manual foundations work; onboarding copy lags capability | Correct “coach owns everything” messaging and expose both manual and personal-coach paths. |
| Workout/coaching quality | Capable primitives; incomplete execution/feedback loop | Faithful targets, effort/context, comparable metrics and honest uncertainty matter before additional programming machinery. |
| Verification and delivery | Broad unit/integration suite; backend-only CI | Put existing iOS tests and representative UI-state evidence into the delivery contract. |

These are qualitative judgments, not validated usability or security scores.

## What is already working

The **versioned plan tree plus idempotent workout log** is appropriate for two
clients sharing a training record. UUID/slot identity, account epochs, attempt
tokens, durable outboxes and authoritative acknowledgment handling address
real gym problems: offline logging, repeated taps, interruption and edits made
while a workout is in progress. The review passed the existing regression
suite; it does not recommend replacing this model.

Manual authoring and coach authoring already converge on that tree. The
recurring schedule is separate from reusable templates, and calendar
projection has matching civil-date rules in Swift and TypeScript. This makes
the library's presentation-first phase a small, credible product improvement.

Training support is richer than a generic weight-times-reps tracker: warm-ups,
holds, rep ranges, signed assistance, per-hand/per-side semantics, exercise
demos and rest cues are already represented. Bodyweight P0/P1 genuinely
delivered useful capability. Their remaining metric-policy flaw should be
corrected without erasing that progress.

The storage work at this source includes server-owned incremental cursors,
tombstones, indexed member reads, bounded source reconciliation and stale
provider-response fencing. Production/retention closeout evidence is retained
in the [completed storage plan](../../plans/completed/data-storage-scalability/plan.md).
It would be incorrect to propose those source fixes
as missing, or to infer deployment from their presence in Git.

## Findings and closure

Priorities: **P1** means a concrete integrity/security or prescription-fidelity
failure to address before adding complexity; **P2** means a material product,
semantic or maintainability gap. Confidence applies to the stated scenario,
not to a claim about production incidence.

### F01 — P1: malformed targets can poison plan sync

**Reproduced.** `updateExercise` checks field names but not values. The actual
service, with all 39 reviewed migrations applied to in-memory SQLite, accepted
`target_sets: "three"` and `target_rpe: 99`; SQLite stored the count as TEXT.
The Swift model requires an integer, so that changed plan cannot decode.
TypeScript request annotations and advertised MCP schemas do not validate
runtime input. See the [REST path](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/routes/api.ts#L508),
[shared writer](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L5696)
and [Swift model](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/Models.swift#L35).

**Closure:** new [prescription-integrity P0](../../plans/completed/prescription-integrity/plan.md)
validates every create/patch/rebuild/swap path, including merged cross-field
constraints and legitimate assistance. Rejections must leave data, version
and successful audit history unchanged. Existing set/session validation did
not cover this boundary.

### F02 — P1: OAuth single-use exchange can mint two successors

**Reproduced.** Code and refresh exchange SELECT, DELETE, then issue tokens.
Neither branch checks whether it actually consumed a row. A deterministic
two-reader interleaving through the actual Hono route returned two HTTP 200s,
minted two pairs, and observed DELETE changes of `[1, 0]` in both flows.
Refresh also accepted an unrelated supplied client identifier. That binding
gap alone is not evidence of unauthenticated takeover: these are public clients.
See [token exchange](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/oauth.ts#L324).

**Closure:** new [coach-access-integrity](../../plans/completed/coach-access-integrity/plan.md)
covers atomic validated consumption/issuance, replay handling and scoped
revocation. Refresh lifetime and legacy production transition remain explicit
decisions. The design should follow grant-family replay protection in
[OAuth Security BCP §4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).
The reproducer uses a synthetic D1 adapter; it establishes a code-path defect,
not observed exploitation.

### F03 — P1: last working performance overrides a new prescription

**Source-confirmed.** The runner seeds load/reps from the last working set
before the current target and considers exercise/timed mode, but not the
current warm-up class or distinct slot intent. A previous 185 lb working squat
can therefore seed both a prescribed 45 lb warm-up and a new 135 lb deload.
Warm-up logs are already excluded; the defect is working history overriding
warm-up or changed working targets. See [seeding](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/SyncModel.swift#L4066).
The [runner header](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/TodayView.swift#L901)
does not show prescribed load, RPE or cues beside the entry.

**Closure:** strengthen [gym-runner-depth P0](../../plans/completed/gym-runner-depth/plan.md)
with explicit input precedence, prescription/history provenance, duplicate-slot
and warm-up tests, and preservation of intentional edits during recovery.
This does not require a new programming engine or session-copy model.

### F04 — P1: “reduce intensity” can increase a target

**Source-confirmed; arithmetic checked.** Positive targets are scaled then
rounded to the nearest five. A 4 lb target becomes 5 lb for every offered
reduction magnitude. The operation changes recurring template targets and,
when no day is supplied, every template. The name `adjust_today` obscures
that persistent scope. See [adjustment](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L5843).

**Closure:** [prescription-integrity P2](../../plans/completed/prescription-integrity/plan.md)
requires monotonic reductions, assistance in the correct direction, explicit
no-ops, deliberate increments/units and returned scope/before-after values.
Reversible history helps recover an edit; it cannot make wrong arithmetic
correct. A genuine one-session override remains a separate product choice.

### F05 — P2: successful disjoint edits can lose data, and audit is not atomic

**Lost update reproduced; commit boundaries source-confirmed.** Two callers
read the same slot. One changes weight from 100 to 110, the other changes only
the cue. Both return success, but the second whole-row UPDATE restores weight
100 from its stale snapshot. Order normalization and version increment follow
as separate operations; MCP audit/note writing happens after the handler.
See [writer](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L5700)
and [MCP dispatch](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/mcp/server.ts#L1524).

**Closure:** [prescription-integrity P1](../../plans/completed/prescription-integrity/plan.md)
establishes mutation/version/audit ownership and tested concurrency behavior.
[Reversible plan management](../../plans/completed/reversible-plan-management/plan.md)
now depends on that boundary; its earlier instruction to reuse a universal
existing transaction was too strong. New group/library writers share this
prerequisite instead of replicating the current pattern.

### F06 — P2: bodyweight “best” and e1RM compare unsupported quantities

**Source-confirmed policy flaw.** Highest reps across strict, assisted and
weighted sets can rank assisted 15 above strict eight without showing the
conditions. Positive added load also enters Epley: BW+10 by five can become
about 12 lb “estimated 1RM,” despite absent body mass/system load. Holds pool
durations across load conditions too. See [backend history](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L5948),
[Swift aggregation](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/SyncModel.swift#L2222)
and [chart](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/HistoryView.swift#L172).

**Closure:** new [bodyweight P3](../../plans/completed/bodyweight-training-support/plan.md)
supersedes the completed P1 policy while retaining its delivery history.
Compare compatible load/assistance/mode cohorts, label pooled work honestly,
and suppress unsupported bodyweight e1RM. This is a conservative product
inference, not a claim that another formula is universally correct. No body
mass is invented and raw history remains inspectable.

### F07 — P2: effort and coaching context are lost in projection

**Source-confirmed.** The iOS durable set body has no RPE field and its session
model does not decode fatigue/notes. Finish presents totals without feedback.
The brief omits session notes and renders key sets as `weight x reps`, so a
45-second hold becomes `0x45`; units and assistance/per-hand semantics are
missing. See [set envelope](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/SetOutbox.swift#L6)
and [brief](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/mcp/server.ts#L1439).

**Closure:** [coaching-feedback-loop P0/P2](../../plans/coaching-feedback-loop/plan.md)
now names durable optional feedback, typed/semantic key sets, last-completed
context and relevant authored metadata. Runner P0 owns set RPE. Missing
feedback stays missing, completion requires no questionnaire, and private
member comments stay out of group feeds.

### F08 — P2: volume and endurance labels imply more knowledge than exists

**Source-confirmed.** [`getVolume`](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L6073)
labels every non-warm-up set `hard_sets` without an effort criterion and assigns
only primary muscle. The [endurance conflict heuristic](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/src/db.ts#L9347)
uses universal load/duration cutoffs; absent values become zero and can yield
a benign brick/easy classification. Athlete and strength-day specifics are
not inputs to an individualized interference judgment.

**Closure:** coaching P2 now requires logged-working-set terminology, attribution
and effort limitations, external-load volume labels and explicit unknown
endurance inputs, with Swift/TypeScript parity. Activity integrity still owns
source identity/dates; it cannot supply missing physiological context.

### F09 — P2: failure and final-set states weaken correction

**Source-confirmed.** After a failed initial state pull without a cache, Today
can say “NO PLAN YET” instead of showing a retry state. Active/finished runner
views omit ordinary `loadError` presentation; a failed set delete can be
invisible. The last locally durable set switches to a finish view with no
review/edit return path. See [state selection](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/TodayView.swift#L342),
[delete](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/SyncModel.swift#L4786)
and [finish](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/TodayView.swift#L1504).

**Closure:** activation P0 distinguishes verified empty from failed loading;
runner P0/P2 covers contextual errors and final-set correction with original
UUID/attempt identity. Successful mutation followed by refresh failure must
remain a success with separately visible sync uncertainty.

### F10 — P2: onboarding describes an obsolete product

**Source-confirmed.** Nonowner onboarding says a group owner's Claude programs
the member's plan and personal coaching is coming “soon,” while personal Coach
Connect already exists. Signed-out copy implies a coach is required, although
manual authoring is shipped. See [onboarding](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/Onboarding/OnboardingView.swift#L284)
and [Profile](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/Profile/ProfileView.swift#L222).

**Closure:** [member activation P0](../../plans/member-activation-and-adherence/plan.md)
is updated around the working manual baseline: accurate capability copy,
direct coach action, retained invite intent and async step ownership. Library
P0 improves discoverability; archive/freestyle do not solve misleading entry.

### F11 — P2: accessibility needs explicit acceptance

**Source-confirmed controls/contrast; layout risks unmeasured.** The delete-set
icon is 10 pt with no explicit minimum touch frame or contextual accessible
name. Enabled Skip and some metric labels use `Theme.dim`: calculated contrast
is about 2.10:1 on `Theme.surface`, versus 5.37:1 for `Theme.muted`.
Rest completion blinks without a Reduce Motion branch. Non-scrolling onboarding
and fixed load-editor height warrant large-text/keyboard walkthroughs; clipping
was not observed on a device. See [controls](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/TodayView.swift#L1294)
and [palette](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/Theme.swift#L8).

**Closure:** [app-quality P0/P1](../../plans/completed/app-quality-and-maintainability/plan.md)
adds synthetic UI states and VoiceOver/large-text/Reduce Motion evidence, with
adequate interactive sizing and descriptive values. This follows
[Apple's control and legibility guidance](https://developer.apple.com/design/tips/).
Custom fonts alone are not evidence that Dynamic Type fails.

### F12 — P2: maintainability and client performance lack a measured contract

**Source-confirmed structure; performance investigation.** `db.ts` has 10,278
lines and `SyncModel.swift` 5,443. Their size matters because transaction,
persistence, runner and metric responsibilities meet there, not because large
files are intrinsically defective. Calendar repeatedly builds date/session
maps and scans sets; History eagerly recalculates per-exercise aggregations;
snapshot ownership paths serialize complete cached state on the main actor.
See [calendar](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/CalendarView.swift#L192),
[history](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/HistoryView.swift#L75)
and [snapshot store](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/ios/TresFort/WorkoutRecoveryStore.swift#L209).
These are measurable work multipliers, not established latency/battery failures.

The [CI workflow](https://github.com/namarks/tres-fort/blob/696c1d34c98d956a3e1fddf78fcfd5eba168e874/.github/workflows/ci.yml#L14)
runs backend checks only, despite substantial existing iOS tests. README/DESIGN
also retain obsolete read-mostly, SwiftData and blanket conflict/atomicity
descriptions that can mislead future work.

**Closure:** app-quality P0 makes iOS verification reproducible/visible; P2
measures small and multi-year histories before choosing cached indexes, lazy
rows or work movement. Extract cohesive tested helpers behind existing facades
and reconcile documentation. No microservice split, new persistence engine or
blanket rewrite is justified.

## Workout-quality interpretation

The app can represent useful conventional strength/hypertrophy work and many
bodyweight progressions. Whether a particular athlete's program is good also
depends on goals, weekly distribution, technique, adherence, constraints and
observed adaptation; none was measured here. Catalog breadth and passing tests
do not establish an effective individualized program.

The 2026 ACSM position stand supports progressive resistance training with
prescription variables selected for the desired adaptation. It does not find
consistent outcome advantages for every added complexity, equipment type or
periodization choice. My product inference is to prioritize faithful targets,
interpretable feedback and adherence before more programming infrastructure.
The evidence concerns healthy adults and does not validate Tres Fort itself.
[ACSM position stand](https://pubmed.ncbi.nlm.nih.gov/41843416/)

Supersets are a real missing execution format, and the existing plan directly
addresses it. Races, trips and endurance context are useful inputs, but fixed
thresholds should remain transparent scheduling aids. Automatic diagnosis,
readiness scoring and a prescriptive starter program are not gap-closing
requirements supported by this review.

## Will the unfinished plans solve these issues?

| Existing workstream | Coverage before review | Action and remaining boundary |
|---|---|---|
| Reversible plan management | Correct recovery/history direction; assumed atomic writers | Added hard prerequisite on prescription P1 and corrected snapshot boundary language. Undo does not replace validation. |
| Coaching feedback loop | Directly covers feedback and context; semantic acceptance too broad | Added durable feedback/notes, typed sets, honest metrics, unknown endurance data and bodyweight P3 dependency. |
| Gym runner depth | Directly covers intent/correction/completion | Added exact seed precedence, final-set correction, observable failures, RPE envelope and comparable PR requirements. |
| Member activation and adherence | Right entry/adherence direction; understated shipped manual path | Rebased P0 on current capabilities, cold-load errors and async/invite intent. Starter policy remains gated. |
| Bodyweight training support | P0/P1 delivered; P2 swaps still pending | Retained history; added corrective P3 metrics. P2 now waits on the safe shared prescription writer. |
| Workout library | Solves reusable-workout discovery, archive and freestyle | Kept P0 independent; gated new writers on prescription integrity and required reviewed comparable targets for save-as-workout. |
| Workouts and multi-session | Solves naming and additional-session limitation | Retained owner-requested outcome; encoded existing rename rollout decision as a named gate. Recommend later sequencing. |
| Supersets and circuits | Directly solves authored grouping and round execution | Added validated atomic-writer prerequisite and explicit version checks on group rewrites/clear. |
| Activity integration integrity | Correct owner for identity, civil dates, reconnect and deletion | No plan rewrite needed. Coaching P2 owns interpretation/unknown inputs; existing coordination connects them. |
| Group experience and governance | Covers pagination, own visibility, invites and controls | No plan rewrite needed. Keep engagement after feed truth; it does not fix workout semantics. |
| Data storage scalability | Source fixes already delivered; concurrent PR #137 completed and archived the plan | Incorporated the merged closeout without altering its evidence. Added client measurement to the new quality plan instead. |

New plans are **coach-access-integrity**, **prescription-integrity**, and
**app-quality-and-maintainability**. They remain planned. The revised graph has
13 plans, 39 edges and four initiatives; bodyweight retains P2 as its selected
frontier but is now blocked on the repaired writer. No existing phase was
marked complete merely because this report describes its solution.

The four existing initiatives are enough: training-data-trust now includes
coach access and prescription safety; closed-loop-coaching includes faithful
execution/comparable metrics; gym-floor-experience includes accessible verified
journeys; connected-training includes unknown-data interpretation. Their
completion conditions now cover these outcomes without duplicating live phase
checkboxes or granting implementation/release authority.

## Recommended order and tradeoffs

1. **Repair trust and prescription fidelity:** coach-access P0,
   prescription P0/P1/P2, runner P0. In parallel where touch surfaces allow,
   establish app-quality P0. This removes concrete errors before increasing
   the number of writers and formats.
2. **Close the useful training loop:** coaching P0, bodyweight P2 then P3 after
   prescription P1 (the existing selected frontier remains P2), accessibility
   P1 and entry P0, followed by comparable summaries/context. Preserve optional
   feedback and avoid making every workout a form.
3. **Add depth to a trustworthy journey:** library P0 is a small independent
   win; supersets, reversible history, archive/freestyle and connected-feed
   correctness follow their actual prerequisites. Measure client history costs
   before performance extraction.
4. **Defer high-cost structural/engagement breadth:** the three-release
   storage/wire rename and multi-session change remain owner-requested plans,
   but do not fix current prescription/feedback issues. Reactions, notifications,
   Watch execution and new programming machinery rank below core journey trust.

This is an investment recommendation, not an activated execution wave. Numeric
performance budgets, starter policy, coach-grant lifetime/legacy transition,
rename compatibility and production outcomes need the evidence/decisions named
in their canonical plans. No new broad initiative or second workout data model
is required.

## Verification evidence

| Check on reviewed source | Result |
|---|---|
| Lockfile installation | Offline `npm ci --ignore-scripts --no-audit --no-fund` succeeded in the isolated worktree. |
| TypeScript | `npm run typecheck` passed. |
| Backend baseline | `npm test`: 672 tests in 47 files passed, plus five TestFlight-uploader checks and the query-plan guard. |
| iOS baseline | XcodeGen; Xcode 26.3; unsigned TresFort scheme on a disposable iPhone 17 Pro / iOS 26.3 simulator: 273 tests, zero failures. |
| OAuth evidence | Actual route + synthetic D1 interleaving reproduced concurrent successor issuance and missing supplied-client binding. |
| Prescription evidence | Actual service + real in-memory SQLite/all 39 migrations reproduced invalid persisted values and acknowledged lost disjoint patch. |
| Planning | Shared compiler passed after revisions and storage closeout reconciliation: 13 plans, 39 edges, four initiatives. |

Sandbox restrictions initially blocked the Workers loopback listener and
CoreSimulator access. Those were diagnosed as environment permissions; tests
passed with local runtime access. No failed assertion was dismissed as flaky.
The local Node runtime was v26.0.0; configured backend CI uses Node 20, and no
new remote CI run is claimed here.

Runnable, synthetic evidence is retained in
[oauth-consumption-repro.mjs](evidence/oauth-consumption-repro.mjs) and
[prescription-write-repro.mjs](evidence/prescription-write-repro.mjs).
Both assert the historical defect, not desired behavior, and are intentionally
outside the ordinary regression suite. The prescription harness needs a Node
runtime with `node:sqlite` (the review used Node 26). Repair work must replace
these observations with desired-state Workers/D1 and Swift regressions.

Passing baseline tests establish regression coverage for current contracts.
They do not refute the uncovered counterexamples, prove device usability,
certify production security or establish workout efficacy. Live phase state
and next actions remain solely in the linked canonical plans.
