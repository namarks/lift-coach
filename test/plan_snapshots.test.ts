import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  comparePlanVersions,
  createPlan,
  deleteUserAccount,
  exportUserData,
  getOrCreateSession,
  getPlanSnapshot,
  getPlanTree,
  listPlanHistory,
  restorePlanSnapshot,
  updatePlanTree,
} from '../src/db';
import { comparePlanSnapshots, serializePlanSnapshot } from '../src/planSnapshots';

beforeAll(async () => applyD1Migrations(env.DB, env.TEST_MIGRATIONS));

async function fixture(label: string) {
  const userId = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO users (id,apple_sub,display_name,created_at) VALUES (?1,?2,?3,?4)',
  ).bind(userId, `sub-${userId}`, label, Date.now()).run();
  await createPlan(env.DB, userId, `${label} plan`);
  const built = await updatePlanTree(env.DB, userId, {
    name: `${label} plan`,
    days: [{ name: 'Strength A', day_label: 'A', exercises: [
      { exercise: 'bench', target_sets: 3, target_reps: 5, target_weight: 135 },
    ] }],
  });
  if (!('plan' in built)) throw new Error('fixture_plan_failed');
  return { userId, plan: built.plan };
}

describe('plan snapshots', () => {
  it('round trips the canonical writable document and reports a useful comparison', async () => {
    const { userId, plan } = await fixture('roundtrip');
    const stored = await getPlanSnapshot(env.DB, userId, plan.id, plan.version);
    expect(stored?.parsed).toEqual(serializePlanSnapshot(plan));
    const changed = structuredClone(stored!.parsed);
    changed.days[0]!.exercises[0]!.target_weight = 145;
    const diff = comparePlanSnapshots(stored!.parsed, changed);
    expect(diff.summary.exercises_changed).toBe(1);
    expect(diff.changes[0]?.path).toContain('Strength A');
  });

  it('compares a labeled current version from its immutable snapshot', async () => {
    const { userId, plan } = await fixture('comparison fence');
    const snapshotOnlyDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'prepare') return (sql: string) => {
          if (sql.includes('FROM day_templates WHERE plan_id')) {
            throw new Error('live_tree_read_not_allowed');
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    }) as D1Database;
    const comparison = await comparePlanVersions(snapshotOnlyDb, userId, plan.version);
    expect(comparison).toMatchObject({
      from_version: plan.version, to_version: plan.version, changes: [],
    });
  });

  it('returns the acknowledged plan version when another write wins before response refresh', async () => {
    const { userId, plan } = await fixture('response race');
    let injected = false;
    const racingDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          const result = await target.batch(statements);
          if (!injected) {
            injected = true;
            const concurrent = await updatePlanTree(env.DB, userId, {
              expected_version: plan.version + 1,
              name: 'Concurrent second write',
              days: [{ name: 'Second', exercises: [] }],
            });
            if (!('plan' in concurrent)) throw new Error('concurrent_write_failed');
          }
          return result;
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    }) as D1Database;
    const acknowledged = await updatePlanTree(racingDb, userId, {
      expected_version: plan.version,
      name: 'Acknowledged first write',
      days: [{ name: 'First', exercises: [] }],
    });
    expect(acknowledged).toMatchObject({
      conflict: false,
      plan: { name: 'Acknowledged first write', version: plan.version + 1 },
    });
    expect((await getPlanTree(env.DB, userId))?.name).toBe('Concurrent second write');
  });

  it('restores a caller-owned snapshot as a new version and retains both versions', async () => {
    const { userId, plan } = await fixture('restore');
    const changed = await updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      name: 'Changed plan',
      days: [{ name: 'Strength B', day_label: 'B', exercises: [
        { exercise: 'squat', target_sets: 4, target_reps: 6 },
      ] }],
    });
    if (!('plan' in changed)) throw new Error('changed_plan_failed');
    const restored = await restorePlanSnapshot(env.DB, userId, {
      plan_id: plan.id, snapshot_version: plan.version,
      expected_version: changed.plan.version, actor: 'ios', reason: 'Undo change',
    });
    expect(restored).toMatchObject({ ok: true, restored_from_version: plan.version, version: changed.plan.version + 1 });
    expect((await getPlanTree(env.DB, userId))?.name).toBe(plan.name);
    expect(await getPlanSnapshot(env.DB, userId, plan.id, plan.version)).not.toBeNull();
    expect(await getPlanSnapshot(env.DB, userId, plan.id, changed.plan.version + 1)).not.toBeNull();
    const history = await listPlanHistory(env.DB, userId);
    if (!('items' in history) || !Array.isArray(history.items)) throw new Error('history_missing');
    expect(history.items[0]?.operation).toBe('restore_plan');
    const comparison = await comparePlanVersions(env.DB, userId, plan.version);
    expect('changes' in comparison && comparison.changes).toHaveLength(0);
  });

  it('rejects stale, cross-user, and active-workout restore attempts', async () => {
    const one = await fixture('owner-one');
    const two = await fixture('owner-two');
    expect(await restorePlanSnapshot(env.DB, two.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: two.plan.version, actor: 'mcp',
    })).toMatchObject({ conflict: true });
    expect(await restorePlanSnapshot(env.DB, one.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: one.plan.version - 1, actor: 'mcp',
    })).toMatchObject({ conflict: true });
    const session = await getOrCreateSession(
      env.DB, one.userId, one.plan.id, '2026-09-07', one.plan.days[0]!.id,
    );
    await env.DB.prepare("UPDATE sessions SET status='in_progress' WHERE id=?1").bind(session.id).run();
    expect(await restorePlanSnapshot(env.DB, one.userId, {
      plan_id: one.plan.id, snapshot_version: one.plan.version,
      expected_version: one.plan.version, actor: 'ios',
    })).toEqual({ error: 'active_workout' });
  });

  it('rejects a workout that starts after restore prechecks but before its write batch', async () => {
    const { userId, plan } = await fixture('restore race');
    const changed = await updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      days: [{ name: 'Current', day_label: 'C', exercises: [
        { exercise: 'squat', target_sets: 3, target_reps: 5 },
      ] }],
    });
    if (!('plan' in changed)) throw new Error('changed_plan_failed');
    let intercepted = false;
    const racingDb = new Proxy(env.DB, {
      get(target, property) {
        if (property === 'batch') return async (statements: D1PreparedStatement[]) => {
          if (!intercepted) {
            intercepted = true;
            const ts = Date.now();
            await env.DB.prepare(
              `INSERT INTO sessions
               (id,user_id,plan_id,day_template_id,date,status,started_at,created_at,updated_at)
               VALUES (?1,?2,?3,?4,'2026-09-07','in_progress',?5,?5,?5)`,
            ).bind(crypto.randomUUID(), userId, plan.id, changed.plan.days[0]!.id, ts).run();
          }
          return target.batch(statements);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    }) as D1Database;
    expect(await restorePlanSnapshot(racingDb, userId, {
      plan_id: plan.id, snapshot_version: plan.version,
      expected_version: changed.plan.version, actor: 'ios',
    })).toEqual({ error: 'active_workout' });
    expect((await getPlanTree(env.DB, userId))?.version).toBe(changed.plan.version);
  });

  it('includes immutable plan history in the portable export', async () => {
    const { userId } = await fixture('export');
    const exported = await exportUserData(env.DB, userId) as {
      schema_version: number; training: { plan_snapshots: unknown[] };
    };
    expect(exported.schema_version).toBe(2);
    expect(exported.training.plan_snapshots).toHaveLength(2);
  });

  it('does not leave an empty plan when first-plan snapshot contribution fails', async () => {
    const userId = crypto.randomUUID();
    await env.DB.prepare(
      'INSERT INTO users (id,apple_sub,display_name,created_at) VALUES (?1,?2,?3,?4)',
    ).bind(userId, `sub-${userId}`, 'atomic bootstrap', Date.now()).run();
    await env.DB.prepare(
      `CREATE TRIGGER fail_bootstrap_snapshot BEFORE INSERT ON plan_snapshots
       WHEN NEW.user_id='${userId}' BEGIN SELECT RAISE(ABORT,'snapshot_failure'); END`,
    ).run();
    try {
      await expect(updatePlanTree(env.DB, userId, {
        name: 'First plan',
        days: [{ name: 'A', exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 5 }] }],
      })).rejects.toThrow();
    } finally {
      await env.DB.prepare('DROP TRIGGER fail_bootstrap_snapshot').run();
    }
    expect(await getPlanTree(env.DB, userId)).toBeNull();
  });

  it('rolls back the document, version, audit, and note when a result snapshot fails', async () => {
    const { userId, plan } = await fixture('rollback');
    const stored = await getPlanSnapshot(env.DB, userId, plan.id, plan.version);
    await env.DB.prepare(
      `INSERT INTO plan_snapshots
       (id,user_id,plan_id,version,document,actor,operation,reason,created_at)
       VALUES (?1,?2,?3,?4,?5,'system','collision',NULL,?6)`,
    ).bind(crypto.randomUUID(), userId, plan.id, plan.version + 1,
      stored!.document, Date.now()).run();
    const beforeAudit = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM audit_log WHERE user_id=?1',
    ).bind(userId).first<{ n: number }>();
    const beforeNotes = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM notes WHERE user_id=?1',
    ).bind(userId).first<{ n: number }>();
    await expect(updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      days: [{ name: 'Should roll back', exercises: [{ exercise: 'squat', target_sets: 3, target_reps: 5 }] }],
    }, { actor: 'mcp', operation: 'update_plan', note: 'Must not survive' })).rejects.toThrow();
    const after = await getPlanTree(env.DB, userId);
    expect(after?.version).toBe(plan.version);
    expect(after?.days[0]?.name).toBe('Strength A');
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM audit_log WHERE user_id=?1').bind(userId).first<{ n: number }>())?.n)
      .toBe(beforeAudit?.n);
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM notes WHERE user_id=?1').bind(userId).first<{ n: number }>())?.n)
      .toBe(beforeNotes?.n);
  });

  it('does not add history after account deletion has claimed the user', async () => {
    const { userId, plan } = await fixture('deletion fence');
    const before = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM plan_snapshots WHERE user_id=?1',
    ).bind(userId).first<{ n: number }>();
    await env.DB.prepare(
      `INSERT INTO account_deletion_intents
       (user_id,idempotency_key_sha256,apple_revocation,created_at)
       VALUES (?1,?2,'manual_required',?3)`,
    ).bind(userId, 'f'.repeat(64), Date.now()).run();
    expect(await updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      days: [{ name: 'Blocked', exercises: [] }],
    })).toMatchObject({ conflict: true });
    expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM plan_snapshots WHERE user_id=?1').bind(userId).first<{ n: number }>())?.n)
      .toBe(before?.n);
    expect((await getPlanTree(env.DB, userId))?.version).toBe(plan.version);
  });

  it('deletes user-owned snapshots while retaining the deletion receipt', async () => {
    const { userId } = await fixture('snapshot deletion');
    expect(await deleteUserAccount(env.DB, userId, undefined, crypto.randomUUID()))
      .toMatchObject({ ok: true });
    expect(await env.DB.prepare('SELECT 1 FROM plan_snapshots WHERE user_id=?1').bind(userId).first())
      .toBeNull();
    expect(await env.DB.prepare('SELECT 1 FROM users WHERE id=?1').bind(userId).first()).toBeNull();
    expect(await env.DB.prepare('SELECT 1 FROM account_deletion_receipts WHERE user_id=?1').bind(userId).first())
      .not.toBeNull();
  });

  it('preserves historical session and set values while safely detaching replaced refs', async () => {
    const { userId, plan } = await fixture('historical refs');
    const day = plan.days[0]!;
    const slot = day.exercises[0]!;
    const session = await getOrCreateSession(env.DB, userId, plan.id, '2026-08-01', day.id);
    const setId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT INTO set_logs
       (id,session_id,exercise_id,template_exercise_id,set_index,weight,reps,is_warmup,logged_at,source)
       VALUES (?1,?2,?3,?4,1,135,5,0,?5,'ios')`,
    ).bind(setId, session.id, slot.exercise_id, slot.id, Date.now()).run();
    const changed = await updatePlanTree(env.DB, userId, {
      expected_version: plan.version,
      days: [{ name: 'Different', day_label: 'B', exercises: [
        { exercise: 'squat', target_sets: 3, target_reps: 5 },
      ] }],
    });
    if (!('plan' in changed)) throw new Error('changed_plan_failed');
    const restored = await restorePlanSnapshot(env.DB, userId, {
      plan_id: plan.id, snapshot_version: plan.version,
      expected_version: changed.plan.version, actor: 'ios',
    });
    expect(restored).toMatchObject({ ok: true });
    expect(await env.DB.prepare('SELECT day_template_id,date FROM sessions WHERE id=?1').bind(session.id).first())
      .toEqual({ day_template_id: null, date: '2026-08-01' });
    expect(await env.DB.prepare('SELECT template_exercise_id,weight,reps FROM set_logs WHERE id=?1').bind(setId).first())
      .toEqual({ template_exercise_id: null, weight: 135, reps: 5 });
  });

  it('keeps a large canonical snapshot within a measured portable bound', async () => {
    const { userId, plan } = await fixture('growth');
    const stored = (await getPlanSnapshot(env.DB, userId, plan.id, plan.version))!.parsed;
    stored.days = Array.from({ length: 50 }, (_, dayIndex) => ({
      ...structuredClone(stored.days[0]!), id: crypto.randomUUID(), name: `Day ${dayIndex}`,
      exercises: Array.from({ length: 20 }, (_, slotIndex) => ({
        ...structuredClone(stored.days[0]!.exercises[0]!), id: crypto.randomUUID(),
        order_index: slotIndex, cues: 'Controlled eccentric and consistent setup.',
      })),
    }));
    const bytes = new TextEncoder().encode(JSON.stringify(stored)).byteLength;
    console.log(JSON.stringify({ event: 'plan_snapshot_growth', days: 50, slots: 1000, bytes }));
    expect(bytes).toBeGreaterThan(100_000);
    expect(bytes).toBeLessThan(1_000_000);
  });
});
