import { applyD1Migrations, env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { workoutInput, workoutWire } from '../src/workoutWire';

beforeAll(async () => applyD1Migrations(env.DB, env.TEST_MIGRATIONS.filter(m => m.name !== '0045_workouts.sql')));
const base = 'https://tres-fort.test';
async function tool(name: string, args: unknown = {}) {
  const response = await SELF.fetch(`${base}/mcp`, { method: 'POST',
    headers: { Authorization: 'Bearer test-mcp-token', 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }) });
  const rpc = await response.json<any>();
  return JSON.parse(rpc.result.content[0].text);
}

it('keeps opaque content unchanged and rejects contradictory aliases', () => {
  const opaque = { workouts: ['user text'], workout_id: 'not a field to rename' };
  expect(workoutWire({ workouts: [{ id: 'w' }], meta: opaque, notes: opaque, document: opaque }))
    .toEqual({ workouts: [{ id: 'w' }], days: [{ id: 'w' }], meta: opaque, notes: opaque, document: opaque });
  expect(workoutInput({ workouts: [{ name: 'A', exercises: [] }], days: [{ exercises: [], name: 'A' }] }))
    .toEqual({ workouts: [{ exercises: [], name: 'A' }] });
  expect(() => workoutInput({ workout_id: null, day_template_id: 'w' })).toThrow('conflicting_workout_fields');
});

it('serves old and new REST/MCP clients before and after the rename, without changing schedule or history', async () => {
  const auth = await SELF.fetch(`${base}/auth/dev`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ secret: 'test-dev' }) });
  const { jwt } = await auth.json<{ jwt: string }>();
  async function api(path: string, method = 'GET', body?: unknown) {
    const response = await SELF.fetch(`${base}/api/${path}`, { method,
      headers: { Authorization: `Bearer ${jwt}`, 'content-type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, body: await response.json<any>() };
  }
  for (const migrated of [false, true]) {
    if (migrated) await applyD1Migrations(env.DB, env.TEST_MIGRATIONS.filter(m => m.name === '0045_workouts.sql'));
    const label = migrated ? 'new' : 'old';
    const original = await tool('update_plan', { days: [{ name: `Gym ${label}`, exercises: [{ exercise: 'bench', target_sets: 3, target_reps: 5 }] }] });
    expect(original).toHaveProperty('plan');
    expect(original.plan.days).toEqual(original.plan.workouts);
    const gym = original.plan.workouts[0];
    const add = await api('workouts', 'POST', { name: `Hotel ${label}` });
    expect(add.status).toBe(201);
    const hotel = add.body.id;
    expect((await api(`days/${hotel}`, 'PATCH', { name: `Travel ${label}` })).status).toBe(200);
    const oldTool = await tool('add_day', { name: `Old coach ${label}` });
    const newTool = await tool('add_workout', { name: `New coach ${label}` });
    expect(oldTool.id).toBeTruthy(); expect(newTool.id).toBeTruthy();
    expect(await tool('update_workout', { workout_id: hotel, patch: { notes: 'On demand' } })).not.toHaveProperty('error');
    expect(await tool('update_day', { day_template_id: hotel, patch: { name: `Travel ${label}` } })).not.toHaveProperty('error');
    let tree = (await api('plan/active')).body;
    const today = (await tool('get_today_workout')).date;
    const weekday = ['sun','mon','tue','wed','thu','fri','sat'][new Date(`${today}T12:00:00Z`).getUTCDay()]!;
    const week = { [weekday]: gym.id };
    expect((await api('plan/schedule', 'PUT', { week, expected_plan_id: tree.id, expected_version: tree.version })).status).toBe(200);
    tree = (await api('plan/active')).body;
    const beforeSession = (await tool('get_today_workout')).session;
    const assigned = await api(`calendar/${today}`, 'PUT', { day_template_id: hotel, expected_attempt: beforeSession?.attempt ?? 0 });
    expect(assigned.status).toBe(200);
    expect(assigned.body.session).toMatchObject({ workout_id: hotel, day_template_id: hotel });
    const read = (await api('state')).body;
    expect(read.plan.version).toBe(tree.version);
    expect(read.plan.meta).toBe(tree.meta);
    expect(read.sessions.find((s: any) => s.id === assigned.body.session.id).workout_id).toBe(hotel);
    expect((await tool('get_today_workout')).session.workout_id).toBe(hotel);
    expect((await api(`calendar/${today}`, 'PUT', { workout_id: gym.id, day_template_id: hotel, expected_attempt: assigned.body.session.attempt })).status).toBe(400);
    const retry = await api(`calendar/${today}`, 'PUT', { workout_id: hotel, expected_attempt: assigned.body.session.attempt });
    expect(retry.body.session.attempt).toBe(assigned.body.session.attempt);
    const exported = (await api('me/export')).body;
    expect(exported.training.day_templates).toEqual(exported.training.workouts);
    expect(await tool('delete_workout', { workout_id: newTool.id, expected_version: tree.version })).toMatchObject({ ok: true });
    const audit = await env.DB.prepare('SELECT tool FROM audit_log WHERE user_id=? ORDER BY created_at').bind(tree.user_id).all<{ tool: string }>();
    expect(audit.results.map(r => r.tool)).toEqual(expect.arrayContaining(['add_day', 'add_workout', 'update_day', 'update_workout', 'delete_workout']));
  }
});
