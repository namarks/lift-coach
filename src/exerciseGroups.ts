/** Cross-slot prescription rules, shared by every plan-tree writer. */
export interface ExerciseGroupFields {
  group_id?: string | null;
  group_rest_seconds?: number | null;
  group_transition_seconds?: number | null;
}
export type GroupConflict = { error: 'group_conflict'; fields: string[] };
export type GroupSlot = ExerciseGroupFields & { id: string; order_index: number; target_sets: number };
export const isGroupId = (value: unknown): value is string => typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export const emptyExerciseGroup = { group_id: null, group_rest_seconds: null, group_transition_seconds: null };

export function validateExerciseGroups(slots: readonly GroupSlot[]): GroupConflict | null {
  const bad = new Set<string>();
  const groups = new Map<string, Array<{ slot: GroupSlot; index: number }>>();
  const ordered = [...slots].sort((a, b) => a.order_index - b.order_index || a.id.localeCompare(b.id));
  ordered.forEach((slot, index) => {
    if (slot.group_id == null) {
      if (slot.group_rest_seconds != null || slot.group_transition_seconds != null) bad.add('group_id');
      return;
    }
    if (!isGroupId(slot.group_id)) bad.add('group_id');
    if (!Number.isSafeInteger(slot.target_sets) || slot.target_sets < 1) bad.add('target_sets');
    if (!Number.isSafeInteger(slot.group_rest_seconds) || slot.group_rest_seconds! < 0) bad.add('group_rest_seconds');
    if (!Number.isSafeInteger(slot.group_transition_seconds) || slot.group_transition_seconds! < 0) bad.add('group_transition_seconds');
    groups.set(slot.group_id, [...(groups.get(slot.group_id) ?? []), { slot, index }]);
  });
  for (const members of groups.values()) {
    const first = members[0]!;
    if (members.length < 2) bad.add('members');
    for (const [index, member] of members.entries()) {
      if (member.index !== first.index + index) bad.add('order_index');
      if (member.slot.target_sets !== first.slot.target_sets) bad.add('target_sets');
      if (member.slot.group_rest_seconds !== first.slot.group_rest_seconds) bad.add('group_rest_seconds');
      if (member.slot.group_transition_seconds !== first.slot.group_transition_seconds) bad.add('group_transition_seconds');
      if (ordered.some((other) => other.id !== member.slot.id && other.order_index === member.slot.order_index)) bad.add('order_index');
    }
  }
  return bad.size ? { error: 'group_conflict', fields: [...bad].sort() } : null;
}

export function validatePlanExerciseGroups(days: readonly { exercises: readonly GroupSlot[] }[]): GroupConflict | null {
  const seen = new Set<string>();
  for (const day of days) {
    const invalid = validateExerciseGroups(day.exercises);
    if (invalid) return invalid;
    const ids = new Set(day.exercises.flatMap((slot) => slot.group_id ? [slot.group_id] : []));
    for (const id of ids) {
      if (seen.has(id)) return { error: 'group_conflict', fields: ['group_id'] };
      seen.add(id);
    }
  }
  return null;
}

/** Removing a slot dissolves a remaining singleton; ordinary rest is retained. */
export function normalizeRemovedGroupMember<T extends GroupSlot>(slots: readonly T[], groupId?: string | null): T[] {
  if (groupId == null || slots.filter((slot) => slot.group_id === groupId).length !== 1) return [...slots];
  return slots.map((slot) => slot.group_id === groupId ? { ...slot, ...emptyExerciseGroup } : slot);
}
