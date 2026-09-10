# Member Activation and Adherence

Slug: member-activation-and-adherence · Status: paused · Updated: 2026-09-09 · Theme: gym-floor

## Goal

Help a newly signed-in or invited member reach a real first workout and return
for the next one without requiring Claude. Done means entry intent survives
authentication, the no-plan state offers honest manual and coach-assisted
paths, and lightweight schedule-based reminders bring the member back to the
correct workout.

## Phases

- [x] **P0 — Reach the first workout**
  - Preserve invite and Coach Connect intent through sign-in, then return the
    member to the intended group or setup action instead of a generic home
    screen.
  - Keep the shipped manual-builder CTA and add a direct coach setup choice.
    Explain both paths and allow either one to be completed later. Reconcile
    signed-out/onboarding/Profile copy: independent and invited members already
    have personal Coach Connect; do not say it is coming soon or that a group
    owner's coach controls another member's plan.
  - Distinguish a verified empty account from initial read failure and cached
    stale state. A cold offline/500 response must offer retry without claiming
    that the member has no plan or encouraging a duplicate replacement.
  - Keep pending invite/coach intent across sign-in and onboarding. Bind async
    step completions to the step that started them so a delayed result after
    Skip cannot advance a different step. Verify owner, invited, independent,
    manual-only and coach-connected entry with the shared synthetic fixtures.
  - Verify the invite, manual, and coach-connected paths through focused
    end-to-end walkthroughs from entry to first completed workout; fix concrete
    breaks without adding an activation analytics system.
- [ ] **P1 — Return for the next workout**
  - Offer opt-in local reminders derived from the existing recurring schedule
    and deep-link each reminder to the correct Today workout.
  - Add a compact Today widget using the same projection and refresh it after
    schedule, skip, completion, or sign-out changes.
  - Keep notification timing and copy editable in app settings; do not require
    a new server notification system for the initial adherence loop.
- [ ] **P2 — Recommend the starter path from evidence**
  - Use direct member feedback and observed walkthroughs of the manual and
    coach-connected paths to recommend whether a built-in starter plan would
    materially improve activation; gathering this evidence requires no starter
    policy decision.
  - Tune reminders and onboarding copy from concrete member feedback rather
    than add a generalized analytics, growth, or messaging platform.
  - [ ] **(a) Implement the decided starter path**
    - After the product decision, either seed an approved starter through the
      completed manual builder and the same versioned plan tree, or record the
      decision not to offer one and retain the manual and coach choices.

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P0 | coordinates_with | plan:coaching-feedback-loop#P1 | Start onboarding/authentication independently; integrate after PR #164 lands and rerun affected tests and exact-head review for shared SyncModel, Today and fixtures. |
| P2(a) | gated_by | external:starter-plan-policy | Implementing or explicitly declining the starter path requires the product decision; evidence and recommendation do not. |

## Next step

**Now (@owner):** P0 is complete for repository delivery. Leave P1 and P2
inactive until explicitly activated. Production and distribution retain their
separate authority boundaries.

## Notes / open questions

- P0 was activated from verified main `4ec8a9e`; reconciliation preserved the
  shipped manual builder and returned-error recovery. This change closes the
  remaining entry-intent, capability-copy, initial-read and delayed-callback gaps.
- Pending invite, coach and manual setup destinations persist through failed
  sign-in/relaunch, bind to the authenticated account and are consumed once at
  sheet dismissal. Onboarding completion is account-scoped; unfinished setup
  survives relaunch. Step/feature-session checkpoints reject late completions
  after Skip, reauthentication or account changes.
- Today and direct manual setup require an accepted live read before offering
  empty-account creation. Cold offline/500 and cached-empty states offer retry;
  an existing cached plan remains available under the existing freshness rules.
- Coaching Feedback Loop P1 is integrated from main `4828842` (PR #164), whose
  reviewed tree and main CI were verified. Its recent-change card, permanent
  history entry, account-bound dismissal and private feedback remain intact.
- Verification: 431 iOS unit tests; nine existing manual/onboarding,
  coaching-feedback and plan-change journeys; and all eight new
  `MemberActivationJourneyTests` journeys passed locally (including a focused
  rerun after correcting the combined handoff test's heading selector).
  New journeys cover owner, invited, independent/manual-only and connected-coach
  entry through first completion, sign-in/invite-preview retry, cold offline/500,
  cached empty/existing state, and sequential invite/coach handoff. Model tests
  cover interrupted onboarding relaunch and late completions after Skip/account
  boundaries. All 17 verification-command/scope tests and the plan graph passed.
  The activation journeys are included in standard CI smoke coverage; exact-head
  independent review and terminal-green CI are required before this change merges.
- Repository delivery is the P0 boundary. Production deployment/migrations,
  TestFlight distribution and actual member messages remain separately
  authorized. Existing physical-device coaching feedback checks remain release
  follow-up; no new pre-merge device gate is introduced here.

- The [September app review](../../reviews/2026-09-app-review/report.md)
  revalidated the working manual entry path. P0 closes remaining intent,
  capability-copy and error-state gaps rather than rebuilding manual authoring.

- P0 does not require a user to choose between AI and manual control forever.
  Both paths converge on the same active plan and can be used later.
- The initial adherence loop is local and schedule-driven. Social campaigns,
  generalized push automation, and predictive churn scoring are out of scope.
