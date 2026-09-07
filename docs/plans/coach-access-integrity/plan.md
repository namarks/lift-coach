# Coach Access Integrity

Slug: coach-access-integrity · Status: planned · Updated: 2026-09-07 · Theme: training-trust

## Goal

Make a coach authorization code and refresh token single-use under concurrent
requests, preserve the authorized user/client/scope through renewal, and let a
member reliably end a coach grant. Keep the existing per-user MCP architecture
and Apple/app-session lifecycle; this is a focused repair of the OAuth grant
boundary uncovered in the [September app review](../../reviews/2026-09-app-review/report.md).

## Phases

- [ ] **P0 — Atomic, validated token exchange**
  - Reproduce concurrent code redemption and refresh in the Workers/D1 runtime.
    The review's synthetic interleaving harness already shows two HTTP 200
    responses and two token pairs when one DELETE reports zero changes.
  - Validate expiry, client binding, redirect and PKCE before an invalid request
    can consume another request's valid code. Treat a public client identifier
    as a binding value, not as authentication of that client.
  - Consume the validated grant and issue its sole successor at one database
    commit boundary, or an equivalently proven conditional transition. Checking
    an earlier SELECT is insufficient. A failed insertion must not leave an
    unexplained consumed grant or a second live successor.
  - Preserve user, scope and account-deletion fences, including explicitly
    supported legacy owner-bound grants. Return stable invalid-grant outcomes
    for losing contenders without falling back to another user.
  - Tests cover concurrent code/refresh requests, wrong client, bad verifier,
    expiry, insertion failure, account deletion interleavings, and a lost
    response. Document the reauthorization outcome when the client cannot
    safely recover a consumed token; do not replay a credential to an unproven
    requester as an availability shortcut.
- [ ] **P1 — Detect replay and revoke a coach grant**
  - Retain enough grant-family identity to detect reuse of a rotated refresh
    token and invalidate the affected grant's surviving successor. Align with
    RFC 9700 section 4.14; keep account and independent grants isolated.
  - Add a caller-scoped grant listing/revocation service and the smallest
    Profile/Coach Connect control needed to disconnect a coach. Explain the
    distinction between changing a connect code and revoking an existing grant.
  - Define refresh inactivity/absolute lifetime, legacy-grant transition and
    reauthorization behavior in a reviewed contract before enforcement. Do not
    silently expire or revoke existing production grants in this workstream.
  - Cover replay after rotation, repeat revocation, cross-user attempts,
    independent grants, and clear reconnect UI without deleting workout data.
  - [ ] **(a) Approve lifecycle and production transition**
    - Record the owner's chosen lifetime/legacy transition and authorize any
      production grant invalidation separately from repository implementation.

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P1 | coordinates_with | plan:member-activation-and-adherence#P0 | Both touch Coach Connect and first-use connection state. |
| P1(a) | gated_by | external:owner-coach-grant-lifecycle | Refresh lifetime, legacy transition and production invalidation are explicit owner decisions. |

## Next step

**Now (@owner):** Activate P0 as a focused security repair. P0's local
implementation and concurrency tests need no production credentials; P1(a)
retains the lifecycle and production transition decision.

## Notes / open questions

- Evidence: `src/oauth.ts` at reviewed commit `696c1d34` and the runnable
  [OAuth reproducer](../../reviews/2026-09-app-review/evidence/oauth-consumption-repro.mjs).
  It exercises the actual Hono route with a synthetic D1 interleaving, not a
  deployed service. No compromise or production exploitation was established.
- [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14) informs
  refresh replay protection. Do not expand this repair into an identity-provider
  migration, per-tool authorization redesign or blanket credential rotation.
- Existing Apple sign-in, account deletion and app renewal tests remain
  regression boundaries. Their completed plan did not establish atomic MCP
  authorization-code/refresh redemption.
