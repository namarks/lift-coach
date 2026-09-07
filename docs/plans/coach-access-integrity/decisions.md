# Coach access integrity decisions

## 2026-09-07: repository implementation and lifecycle boundary

Nick activated the Training Data Trust initiative with an Astra orchestrator
and Sol implementation workers. This authorizes repository work and its normal
reviewed delivery; it does not authorize production grant invalidation,
migration, deployment, or a new grant lifetime policy.

P0 and the P1 repository implementation were integrated with the shared
prescription/snapshot work. Independent Sol reviews found and verified fixes
for a concurrent refresh loser that missed replay detection and a revocation
whose post-commit audit could falsely report failure. Revocation and its audit
now share the transaction. The initial baseline passed 672 tests in 47 files;
the final initiative verification is recorded with the
[shared delivery evidence](../reversible-plan-management/decisions.md).

Code exchange inserts the successor and consumes the validated code in one
D1 batch. Refresh conditionally replaces the existing token pair and retains
the authorized client, scope and principal. Invalid client/PKCE requests do
not consume a code, and insertion failure rolls the transaction back. An
explicitly bound missing user never falls back to the owner. Legacy grants
resolve only to an existing distinguished owner.

Access-token expiry remains distinct from refresh lifetime. P0 preserves
refresh after access expiry. A lost successful exchange response does not
permit replaying its successor credential to a retrying requester; the client
must reauthorize.

The P1 implementation contract uses one opaque grant identity per independent
authorization and hashed consumed-refresh lineage. Reuse of a rotated refresh
token with its bound client revokes that grant's surviving successor, following
[RFC 9700 section 4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).
Grant listing and revocation are caller-scoped and expose no credentials.
Existing and post-migration legacy token rows must remain representable.

The initial delivery left inactivity and absolute expiry fields unset, with no
new expiry enforcement. Additive schema compatibility alone does not establish
a safe rollback: an older Worker cannot maintain new rotation lineage or replay
guarantees. Production activation must retain a compatible rollback or choose a
forward fix.

## 2026-09-07: approved coach lifetime and existing-connection transition

Nick approved both choices during the initiative's decision walkthrough:

- Expire a coach grant after 90 elapsed days without a successful refresh, with
  an absolute maximum of one year (365 elapsed days) from authorization.
- Preserve currently authorized connections at policy activation. Start both
  of their clocks at that activation instant. Subsequent successful refreshes
  move the inactivity deadline only; the absolute deadline remains fixed.
- Preserve existing revocations. Activation and renewal never revive a revoked
  grant. An expired grant requires new authorization, without deleting training
  data.

Inactivity refers to token renewal, not an observed coaching conversation. The
OAuth static bearer and Apple/app sessions have their own existing contracts.
The 30-day OAuth access-token lifetime remains an upper bound; access must also
respect its grant's deadlines. The selected durations are a product policy,
informed by OAuth's recommendation for inactivity expiry; they are not durations
mandated by [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14.2).

These approvals authorize the policy's repository implementation and reviewed
delivery. They do not authorize production migration, deployment, clock
activation or TestFlight. Activation must be explicit, atomic and one-time:
retrying it cannot restart existing clocks. The next release proposal must pin
source, migration order, verification, and a lifecycle-aware recovery path.

## Lifecycle implementation and verification

Migration `0042` creates a disabled singleton policy. A single conditional
UPDATE and its SQL trigger atomically initialize existing live grants; invalid
activation values or unexpected existing deadline state abort the operation.
The policy cannot be deleted or changed after activation. Exact helper retries
return idempotent success, while a different timestamp or nonce is rejected.
New authorizations start at the later of authorization and activation; legacy
adoption receives the original activation epoch, never a fresh grace period.

Refresh, bearer validation and grant listing require consistent policy/deadline
state. Missing policy, partial deadlines, revocation or reaching either deadline
fails closed. Refresh evaluates millisecond time inside D1, moves only the
inactivity deadline and caps its successor access token at the absolute limit.
Production D1 was confirmed to support the millisecond SQL expression through a
read-only query reporting no changes or rows written.

The full regression run passed 730 tests in 52 files, plus five uploader-script
checks and the storage query-plan guard. Final policy-guard refinements passed
all 26 focused OAuth tests and TypeScript. Tests cover atomic activation failure,
exact/conflicting retry, preserved revocations, stale pre-read activation,
legacy adoption, precise deadline rejection, capped sliding renewal, and
inconsistent/missing policy state. The final pull request must also pass the
complete suite and independent review at its exact current head. iOS, dependency
lockfile and deployment configuration are unchanged by this follow-up.

The [release procedure](release.md) records the verified production starting
point, executable activation and recovery boundary. No production migration,
deployment, policy activation or TestFlight upload was performed by this
repository delivery.
