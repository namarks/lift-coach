# Coach Access Integrity

Slug: coach-access-integrity · Status: gated · Updated: 2026-09-07 · Theme: training-trust

## Goal

Make a coach authorization code and refresh token single-use under concurrent
requests, preserve the authorized user/client/scope through renewal, and let a
member reliably end a coach grant. Keep the existing per-user MCP architecture
and Apple/app-session lifecycle; this is a focused repair of the OAuth grant
boundary uncovered in the [September app review](../../reviews/2026-09-app-review/report.md).

## Phases

- [x] **P0 — Atomic, validated token exchange**
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
- [x] **P1 — Detect replay and revoke a coach grant**
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
  - [x] **(a) Approve lifetime and existing-connection transition**
    - Nick approved 90 days without successful renewal and a one-year absolute
      lifetime. Existing authorized connections start both clocks at activation;
      later renewal slides only inactivity. Revoked connections stay revoked.
- [x] **P2 — Implement the approved lifecycle and activation boundary**
  - Enforce the approved deadlines on refresh and bearer validation. New grants
    start from authorization; existing grants receive the approved activation
    grace. Use 90 and 365 elapsed days, with epoch-ms grant timestamps.
  - Keep policy activation disabled until an explicit production action. Make
    activation atomic and idempotent, including repeated identical requests.
  - Prove deadline equality, sliding inactivity, fixed absolute expiry, legacy
    adoption, replay/deletion fences, and activation/expiry interleavings in D1.
- [ ] **P3 — Owner-approved production release and activation**
  - [x] **(a) Release the approved service source and schema**
    - Nick approved source `2e67f93`, migrations `0040`–`0042`, the client check
      and one-time activation with compatible forward recovery. The exact
      reviewed Worker is deployed and its source/schema independently verified.
  - [ ] **(b) Verify an existing client and activate the approved policy**
    - Complete a real authenticated read through an existing client, then
      activate once and repeat the read. Activation is already authorized.
      Do not reset clocks on retry or revive revoked/expired grants.

## Execution frontier

- P3(b)

## Dependencies

| Local phase | Relationship | Target | Reason |
|---|---|---|---|
| P1 | coordinates_with | plan:member-activation-and-adherence#P0 | Both touch Coach Connect and first-use connection state. |
| P3(b) | gated_by | external:existing-authorized-coach-client | Activation is approved, but the required authenticated client check is unexercised: the Mac was locked and the normal CLI client was logged out. |

## Next step

**Now (@owner):** Make an existing authorized client available for P3(b)'s
read-only check, for example by unlocking the Mac. The agent can then finish
the already-approved activation and postactivation read using the
[release procedure](release.md), without another release approval. The service
and migrations are live; the policy remains disabled. TestFlight is separate.
See [decisions.md](decisions.md).

## Notes / open questions

- Original failure evidence: `src/oauth.ts` at the September review's code
  source `696c1d34` and the runnable
  [OAuth reproducer](../../reviews/2026-09-app-review/evidence/oauth-consumption-repro.mjs).
  It exercises the actual Hono route with a synthetic D1 interleaving, not a
  deployed service. This is the pre-fix review baseline, not delivery evidence.
  No compromise or production exploitation was established.
- [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14) informs
  refresh replay protection. Do not expand this repair into an identity-provider
  migration, per-tool authorization redesign or blanket credential rotation.
- Existing Apple sign-in, account deletion and app renewal tests remain
  regression boundaries. Their completed plan did not establish atomic MCP
  authorization-code/refresh redemption.
