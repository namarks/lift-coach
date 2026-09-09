# Exercise grouping contract

## Storage and shared writers

Migration `0044_exercise_groups.sql` adds nullable group identity, round rest,
and transition rest to each prescribed slot. Ordinary `rest_seconds` remains
unchanged. Groups are day-local contiguous blocks with at least two members,
equal round counts, and equal group rests. Each set retains its own slot ID;
sessions, logged sets, and analytics do not acquire a grouping identity.

`db.ts` remains the public service facade. `exerciseGroups.ts` owns pure group
validation and singleton normalization. Group writes and receipt lookup stay
in `db.ts`, reusing its existing plan claim, mutation, version, audit, note,
and snapshot transaction.
Existing slot, rebuild, restore, and recurring-adjustment paths also validate
the final group structure. Removing the penultimate member dissolves the
remaining singleton without changing its ordinary rest.

An accepted group mutation records its normalized request and acknowledgement
inside its atomic audit result. An exact retry is scoped to the same user,
actor, operation, and expected version, and returns the original plan and committed version
before checking the now-stale version. It does not reapply an old membership
after a subsequent rewrite. A changed payload at a stale version conflicts.
A request whose current membership and values already match makes no new
version or history. Clearing all members follows the same acknowledgement rule.

Snapshots include all three group fields in both SQL and TypeScript serializers.
Historical snapshots with no group fields decode them as null. Restore remains
a new validated, version-checked write, never an in-place history rewrite.

## Authoring and compatibility

The REST operation is `PUT /api/days/:id/groups`:

```json
{
  "group_id": "caller-generated UUID",
  "expected_version": 12,
  "exercises": ["first slot UUID", "second slot UUID"],
  "round_rest": 60,
  "transition_rest": 0
}
```

Optional `target_sets` changes every member's round count. Optional `order_index`
places the entire member block at that index in the resulting day, preserving
other relative order. A destination that splits another group is rejected.
An empty `exercises` list explicitly clears the group; omit rest, target-set,
and order fields when clearing. These writes record iOS attribution.

MCP exposes `group_exercises` and `ungroup_exercises` with the same shared
operations. Grouping accepts a day ID, label, or name and slot IDs or
unambiguous exercise names/aliases. Prefer IDs from `get_current_plan` for
repeat occurrences. Before resolving current names, an exact MCP retry matches
the original audited arguments, so rebuilt IDs or a removed day cannot hide its
acknowledgement. Object key order is irrelevant; member order and argument values
remain part of the request identity. Unknown or malformed arguments still reject
before replay, and another user's receipt is never visible. A1/A2
labels are response annotations derived from the member order; both rest
values remain visible in plan/today reads and the compact coach brief.
Single-slot authoring rejects raw group columns with `unknown_fields`. Full-plan
replacement requires `expected_version` whenever the current tree has groups
or the request explicitly supplies group fields, including explicit nulls.
Legacy ungrouped replacements retain their optional-version contract.

Clients declare `groups` in the comma-separated `X-TresFort-Capabilities` header.
Without it, `/api/state`, `/api/plan/active`, and a successful snapshot restore's
embedded plan omit all group columns and return the round rest as each grouped
member's ordinary rest. This projection never writes to storage. Other
capabilities compose in the same header.

## Delivery boundary

The backend migration is additive and must be applied before deploying code
that selects its columns. The current repository work does not authorize a
production migration, deployment, TestFlight upload, or mutation of a real
training plan. Use synthetic integration and simulator evidence for repository
verification. The canonical plan retains execution status and cross-task
ownership; this document describes the stable contract only.
