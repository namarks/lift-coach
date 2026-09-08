import { env, applyD1Migrations, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import fixtures from '../ios/TresFortTests/Fixtures/BodyweightProgress.json';
import { metricCohorts, estimatedOneRepMax } from '../src/metrics';

beforeAll(async () => { await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });
const base = 'https://tres-fort.test';
async function rpc(name: string, args: unknown) {
  const response = await SELF.fetch(`${base}/mcp`, {
    method: 'POST', headers: { 'content-type': 'application/json', Authorization: 'Bearer test-mcp-token' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }),
  });
  expect(response.status).toBe(200);
  const body = await response.json<any>();
  expect(body.error).toBeUndefined();
  expect(body.result.isError).not.toBe(true);
  return JSON.parse(body.result.content[0].text);
}

for (const fixture of fixtures) {
  it(`shares ${fixture.name} expectations across history, volume, MCP and group feed without changing raw sets`, async () => {
    const auth = await SELF.fetch(`${base}/auth/dev`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ secret: 'test-dev' }),
    });
    const { jwt, user } = await auth.json<any>();
    const headers = { 'content-type': 'application/json', Authorization: `Bearer ${jwt}` };
    const ex = fixture.catalog[0]!;
    await env.DB.prepare(`INSERT INTO exercises
      (id,name,primary_muscle,secondary_muscles,modality,unit,aliases,created_at,laterality,load_mode)
      VALUES (?1,?2,?3,'[]',?4,?5,'[]',0,?6,?7)`)
      .bind(ex.id, ex.name, ex.primary_muscle, ex.modality, ex.unit, ex.laterality, ex.load_mode).run();
    await env.DB.prepare('INSERT INTO plans (id,user_id,name,version,created_at,updated_at) VALUES (?1,?2,?1,1,0,0)')
      .bind(fixture.name, user.id).run();
    await env.DB.prepare(`INSERT INTO sessions (id,user_id,plan_id,date,status,created_at,updated_at,completed_at)
      VALUES (?1,?2,?1,'2026-09-01','completed',?3,?3,?3)`)
      .bind(fixture.name, user.id, 1788220800000).run();
    for (const set of fixture.sets) {
      await env.DB.prepare(`INSERT INTO set_logs
        (id,session_id,user_id,exercise_id,set_index,weight,reps,is_warmup,logged_at,source,duration_s,is_timed,deleted_at)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,'ios',?10,?11,?12)`)
        .bind(set.id, set.session_id, user.id, set.exercise_id, set.set_index, set.weight,
          set.reps, set.is_warmup, set.logged_at, set.duration_s, set.is_timed, set.deleted_at).run();
    }
    const raw = await env.DB.prepare('SELECT * FROM set_logs WHERE session_id = ?').bind(fixture.name).all();
    const history = await (await SELF.fetch(`${base}/api/history?exercise_id=${ex.id}&from=0`, { headers })).json<any>();
    const coach = await rpc('get_history', { exercise: ex.id, range: 'all' });
    expect(coach.by_session).toEqual(history.by_session);
    expect(history.sets).toHaveLength(fixture.sets.filter((s) => s.is_warmup === 0 && s.deleted_at == null).length);
    const summary = history.by_session[0];
    expect(summary.cohorts).toHaveLength(fixture.expected_cohorts.length);
    for (const expected of fixture.expected_cohorts) {
      const cohort = summary.cohorts.find((c: any) => c.weight === expected.weight && c.is_timed === expected.is_timed);
      const { value_label, feed_label, ...metrics } = expected;
      expect(cohort).toMatchObject(metrics);
    }
    expect(summary.tonnage).toBe(fixture.expected_tonnage);
    expect(summary.tonnage_basis).toBe('external_load');
    if (ex.modality === 'bw' || ex.modality === 'timed') {
      expect(summary.est_1rm).toBeNull();
      if (summary.cohorts.length > 1) expect(summary.top).toBeNull();
    }
    const volume = await (await SELF.fetch(`${base}/api/volume?muscle=${ex.primary_muscle}&from=0`, { headers })).json<any>();
    expect(await rpc('get_volume_trend', { muscle_group: ex.primary_muscle, range: 'all' })).toEqual(volume);
    expect(volume).toMatchObject({ tonnage_basis: 'external_load', buckets: [{
      hard_sets: history.sets.length, tonnage: fixture.expected_tonnage,
    }] });
    const group = await (await SELF.fetch(`${base}/api/groups`, {
      method: 'POST', headers, body: JSON.stringify({ name: fixture.name }),
    })).json<any>();
    const feed = await (await SELF.fetch(`${base}/api/groups/${group.id}/feed`, { headers })).json<any>();
    const feedSession = feed.items.find((item: any) => item.id === fixture.name).session;
    const topSets = feedSession.cohort_top_sets;
    expect(new Set(feedSession.top_sets.map((s: any) => s.exercise)).size).toBe(feedSession.top_sets.length);
    if (['bw', 'timed'].includes(ex.modality) && topSets.length > 1) expect(feedSession.top_sets).toEqual([]);
    expect(topSets).toHaveLength(fixture.expected_cohorts.length);
    expect(new Set(topSets.map((s: any) => s.cohort_key)).size).toBe(topSets.length);
    for (const expected of fixture.expected_cohorts) {
      const top = topSets.find((s: any) => s.weight === expected.weight && s.is_timed === expected.is_timed);
      expect(top).toMatchObject({ exercise_id: ex.id, weight: expected.weight,
        is_timed: expected.is_timed, est_1rm: expected.est_1rm ?? 0,
        laterality: ex.laterality, load_mode: ex.load_mode });
      expect(expected.is_timed ? top.duration_s : top.reps).toBe(expected.best_duration_s ?? expected.best_reps);
      expect(top).not.toHaveProperty('notes');
      expect(top).not.toHaveProperty('rpe');
    }
    expect((await env.DB.prepare('SELECT * FROM set_logs WHERE session_id = ?').bind(fixture.name).all()).results).toEqual(raw.results);
  });
}

it('never pools variations or unknown-model estimates', () => {
  const ex = fixtures[0]!.catalog[0]!;
  const set = fixtures[0]!.sets[0]!;
  expect(metricCohorts([set, { ...set, exercise_id: 'another-variation', reps: 100 }], ex)).toHaveLength(2);
  expect(estimatedOneRepMax({ ...set, weight: 10 }, { ...ex, modality: 'unknown' })).toBeNull();
});
