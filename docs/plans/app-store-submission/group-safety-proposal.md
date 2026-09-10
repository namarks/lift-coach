# Private-group safety proposal

This is a proposed product/data policy for owner approval, not an implemented
feature or an assertion of App Review approval. Live status belongs to
[plan.md](plan.md).

The existing app shares member-authored names, activity titles and notes in
private groups. Apple Guideline 1.2 calls for objectionable-content filtering,
reporting, blocking and reachable support. Leaving a group does not provide
those controls. Preserve private training history and existing group features.

## Proposed member behavior

1. **Block a member:** from the member's group profile/settings row, confirm
   that the two accounts will stop seeing one another's shared profiles,
   activity details and contributions to member statistics in every common
   group. Apply the same boundary to REST and MCP. Personal history and other
   group members' access remain unchanged. The block persists across devices;
   the blocker can undo it in Profile. Show a neutral unavailable-member state
   wherever an existing selection becomes blocked. Do not notify the blocked
   person or promise that past views, exports or Claude conversations disappear.
2. **Report content or a member:** open an email draft to `nick@tresfort.app`
   with a concise category and reference identifiers. The member reviews and
   sends the message in their mail app; nothing is sent automatically. Do not
   automatically attach workout/health content, tokens or invite codes. Also
   offer blocking immediately. If mail is unavailable, show the support address
   and a copyable report reference.
3. **Filter shared text:** apply a maintained, conservative English
   objectionable-term filter to group-facing display names, group names,
   activity titles and notes. Apply it consistently to REST, MCP, invite pages
   and UI; imported/private originals remain unchanged. Preserve legitimate
   exercise names. Make filtered text neutral, not a disclosure of the original.
   Automated filtering is limited; reports provide human review for context
   and evasion rather than claiming the list detects every abusive phrase.
4. **Operator response:** check the support inbox at least daily and address
   actionable abuse reports within 24 hours. The operator can restrict an
   offending account from group sharing, with an audit trail and a reversible
   reason/status. Restriction affects group sharing, not the account's private
   workout records. Support correspondence follows the published support/privacy
   policy; do not create an additional report-content database in this slice.

## Data and implementation boundary

Store the blocker's ID, blocked account ID, creation timestamp and active state;
validate two distinct accounts sharing a group before creating a block. The
block's owner can revoke it. Account deletion removes associated blocks. Store
operator group-sharing restrictions separately from training rows, with
authorized operator-only writes, reason/status and audited updates. Existing
member, account-deletion, pagination and tenant-isolation tests must cover both
REST and MCP paths, including caches and reconnects.

This proposal adds no chat, public discovery, paid service or AI moderation.
Migration/deployment remains a later exact-source owner gate. Do not promise a
24-hour response in public policy unless the owner accepts that operational
commitment. Inspect all relevant source paths and refine the implementation
contract before writing enforcement code.

Reference: [Apple Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content),
checked 2026-09-10.
