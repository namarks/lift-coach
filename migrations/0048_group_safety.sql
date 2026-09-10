-- Private-group controls. No report bodies or training content are stored.
CREATE TABLE group_member_blocks (
  blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  active INTEGER NOT NULL CHECK (active IN (0, 1)),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX ix_group_blocks_reverse ON group_member_blocks(blocked_id, blocker_id);

CREATE TABLE group_sharing_restrictions (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  active INTEGER NOT NULL CHECK (active IN (0, 1)),
  reason TEXT NOT NULL CHECK (reason IN ('harassment', 'hate', 'sexual_content', 'threats', 'other')),
  updated_at INTEGER NOT NULL
);
