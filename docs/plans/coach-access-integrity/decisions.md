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

Inactivity and absolute expiry fields remain unset, with no new expiry
enforcement. Their values, the legacy transition and any production grant
invalidation require the owner's decision in P1(a). Additive schema
compatibility alone does not establish a safe rollback: an older Worker cannot
maintain new rotation lineage or replay guarantees. Production activation must
retain a compatible rollback or choose a forward fix.
