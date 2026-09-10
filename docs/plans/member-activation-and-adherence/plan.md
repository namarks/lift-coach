# Member Activation and Adherence

Slug: member-activation-and-adherence · Status: active · Updated: 2026-09-09 · Theme: gym-floor

## Goal

Help a newly signed-in or invited member reach a real first workout and return
for the next one without requiring Claude. Done means entry intent survives
authentication, the no-plan state offers honest manual and coach-assisted
paths, and lightweight schedule-based reminders bring the member back to the
correct workout.

## Phases

- [ ] **P0 — Reach the first workout**
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

**Now (@agent):** Complete P0 repository delivery from verified main, preserving
manual authoring, account isolation, workout write reliability and coaching
feedback. Integrate Coaching Feedback Loop P1 before final verification and
review, then merge after all configured gates pass. P1 and P2 remain inactive.

## Notes / open questions

- P0 activated on 2026-09-09 from verified main `4ec8a9e`. Reconciliation:
  manual creation and returned-load-error recovery already exist; remaining
  gaps are durable account-bound entry intent, personal Coach Connect copy and
  direct setup entry, first-read/cached-empty authority, and onboarding callbacks
  bound to their originating step and feature session. Synthetic journeys will
  exercise entry through first completion and interrupted/retried entry.
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
