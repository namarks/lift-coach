import { applyD1Migrations, env, fetchMock, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { issueAppJwt } from '../src/auth';
import {
  consumeIntervalsOAuthAttempt, createIntervalsOAuthState, getIntervalsConnectionStatus,
  getUserIntervalsCreds, reconcileIntervalsConnection, setUserIntervalsCreds,
  setUserIntervalsOAuth, type IntervalsImportResult,
} from '../src/db';
import type { ExternalActivityRow } from '../src/types';
import type { Fetcher } from '../src/intervals';

beforeAll(async () => { await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });
beforeEach(() => { fetchMock.activate(); fetchMock.disableNetConnect(); });
afterEach(() => { fetchMock.deactivate(); });

const origin = 'https://intervals.icu';
const today = new Date().toISOString().slice(0, 10);
const activity = { id: 'ride-1', type: 'Ride', start_date_local: `${today}T08:00:00`,
  start_date: `${today}T08:00:00Z`, name: 'Morning ride', moving_time: 1800 };
const success: Fetcher = async () => ({ ok: true, status: 200, json: async () => [activity] });

async function member() {
  const id = crypto.randomUUID();
  await env.DB.prepare("INSERT INTO users(id,apple_sub,created_at,timezone) VALUES (?1,?1,1,'UTC')").bind(id).run();
  return { id, jwt: await issueAppJwt(id, 'test-secret') };
}
function headers(jwt: string) { return { Authorization: `Bearer ${jwt}`, 'content-type': 'application/json' }; }
async function connect(jwt: string, api_key: string | null = 'synthetic-key', athlete_id: string | null = 'athlete-a') {
  return SELF.fetch('https://test/api/me/integrations/intervals', {
    method: 'PATCH', headers: headers(jwt), body: JSON.stringify({ api_key, athlete_id }),
  });
}
function importResponse(status = 200, body: object = [activity]) {
  fetchMock.get(origin).intercept({ path: /\/api\/v1\/athlete\/[^/]+\/activities\?/ })
    .reply(status, body);
}
async function rows(userId: string) {
  return (await env.DB.prepare("SELECT * FROM external_activities WHERE user_id=?1 AND source='intervals'")
    .bind(userId).all<ExternalActivityRow>()).results;
}

describe('Intervals connection reconciliation', () => {
  it('imports immediately after API-key connect and refreshes the same rows on an identical retry', async () => {
    const user = await member();
    importResponse();
    const response = await connect(user.jwt);
    expect(response.status).toBe(200);
    const first = await response.json<{ connected: boolean; credential_generation: number; initial_sync: IntervalsImportResult }>();
    expect(first).toMatchObject({ connected: true, initial_sync: { status: 'synced', connection: { sync_pending: false } } });
    expect(await rows(user.id)).toHaveLength(1);
    const saved = (await rows(user.id))[0]!;
    importResponse();
    const retry = await (await connect(user.jwt)).json<typeof first>();
    expect(retry.credential_generation).toBe(first.credential_generation);
    expect((await rows(user.id))[0]!.synced_at).toBe(saved.synced_at);
    const state = await SELF.fetch('https://test/api/state', { headers: headers(user.jwt) });
    expect((await state.json<{ external_activities: ExternalActivityRow[] }>()).external_activities.map(row => row.id))
      .toEqual([saved.id]);
  });

  it('keeps a successful credential acknowledgement on a provider outage, then retries without resubmitting credentials', async () => {
    const user = await member();
    importResponse(503, { error: 'temporary' });
    const response = await connect(user.jwt);
    expect(response.status).toBe(200);
    const saved = await response.json<{ credential_generation: number; initial_sync: IntervalsImportResult }>();
    expect(saved.initial_sync).toMatchObject({ status: 'retry', connection: { connected: true, sync_pending: true } });
    importResponse();
    const retried = await SELF.fetch('https://test/api/me/integrations/intervals/sync', {
      method: 'POST', headers: headers(user.jwt), body: JSON.stringify({ expected_generation: saved.credential_generation }),
    });
    expect(await retried.json()).toMatchObject({ status: 'synced', connection: { sync_pending: false } });
    expect(await rows(user.id)).toHaveLength(1);
  });

  it('preserves history on rejected credentials, clears the auth error on reconnect, and preserves it on disconnect', async () => {
    const user = await member();
    const stored = await setUserIntervalsCreds(env.DB, user.id, 'old-key', 'athlete-a');
    await reconcileIntervalsConnection(env.DB, env, user.id, stored.credential_generation, { fetcher: success, today });
    const previous = await rows(user.id);
    importResponse(401, {});
    const rejected = await (await connect(user.jwt, 'rejected-key')).json<{ initial_sync: IntervalsImportResult }>();
    expect(rejected.initial_sync).toMatchObject({ status: 'reconnect', connection: { connected: false, needs_reauth: true } });
    expect(await rows(user.id)).toEqual(previous);
    importResponse();
    expect(await (await connect(user.jwt, 'new-key')).json()).toMatchObject({ initial_sync: { status: 'synced', connection: { needs_reauth: false } } });
    expect(await (await connect(user.jwt, null, null)).json()).toMatchObject({ connected: false });
    expect(await rows(user.id)).toEqual(previous);
    const status = await getIntervalsConnectionStatus(env.DB, user.id);
    const calls: string[] = [];
    const result = await reconcileIntervalsConnection(env.DB, env, user.id, status.credential_generation, {
      fetcher: async (input) => { calls.push(input); return success(input); },
    });
    expect(result.status).toBe('disconnected');
    expect(calls).toEqual([]);
  });

  it.each(['disconnect', 'replace'] as const)('fences an import that finishes after %s', async (change) => {
    const user = await member();
    const stored = await setUserIntervalsCreds(env.DB, user.id, 'old-key', 'athlete-a');
    let started!: () => void;
    const began = new Promise<void>(resolve => { started = resolve; });
    let release!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
    const running = reconcileIntervalsConnection(env.DB, env, user.id, stored.credential_generation, {
      today, fetcher: async () => { started(); await gate; return success(''); },
    });
    await began;
    await setUserIntervalsCreds(env.DB, user.id, change === 'replace' ? 'new-key' : null, change === 'replace' ? 'athlete-b' : null);
    release();
    expect((await running).status).toBe('superseded');
    expect(await rows(user.id)).toEqual([]);
    expect((await getIntervalsConnectionStatus(env.DB, user.id)).last_synced_at).toBeNull();
  });

  it('reconciles only the authenticated member and rejects a stale retry before provider I/O', async () => {
    const a = await member(), b = await member();
    const old = await setUserIntervalsCreds(env.DB, a.id, 'a-key', 'athlete-a');
    await setUserIntervalsCreds(env.DB, b.id, 'b-key', 'athlete-b');
    importResponse();
    await SELF.fetch('https://test/api/me/integrations/intervals/sync', { method: 'POST', headers: headers(a.jwt),
      body: JSON.stringify({ expected_generation: old.credential_generation }) });
    expect(await rows(a.id)).toHaveLength(1);
    expect(await rows(b.id)).toEqual([]);
    await setUserIntervalsCreds(env.DB, a.id, null, null);
    const stale = await SELF.fetch('https://test/api/me/integrations/intervals/sync', { method: 'POST', headers: headers(a.jwt),
      body: JSON.stringify({ expected_generation: old.credential_generation }) });
    expect(await stale.json()).toMatchObject({ status: 'superseded' });
    expect((await getUserIntervalsCreds(env.DB, b.id)).api_key).toBe('b-key');
  });

  it('requires authentication and a valid generation for explicit retry', async () => {
    expect((await SELF.fetch('https://test/api/me/integrations/intervals/sync', { method: 'POST' })).status).toBe(401);
    const user = await member();
    for (const body of [null, {}, { expected_generation: -1 }, { expected_generation: 1.5 }, { expected_generation: 1, userId: 'other' }]) {
      const response = await SELF.fetch('https://test/api/me/integrations/intervals/sync', {
        method: 'POST', headers: headers(user.jwt), body: JSON.stringify(body),
      });
      expect(response.status).toBe(400);
    }
  });

  it('imports through the actual OAuth callback and rejects replay without another exchange', async () => {
    const user = await member();
    const state = await createIntervalsOAuthState(env.DB, user.id);
    fetchMock.get(origin).intercept({ path: '/api/oauth/token', method: 'POST' })
      .reply(200, { access_token: 'synthetic-oauth-token', athlete: { id: 'oauth-athlete' } });
    importResponse();
    const callback = `https://test/auth/intervals/callback?code=synthetic-code&state=${state}`;
    const response = await SELF.fetch(callback, { redirect: 'manual' });
    expect(response.status).toBe(302);
    expect(response.headers.get('Location')).toBe('tresfort://intervals-connected?ok=1&sync=synced');
    expect(await rows(user.id)).toHaveLength(1);
    const retry = await SELF.fetch(callback, { redirect: 'manual' });
    expect(retry.headers.get('Location')).toContain('error=bad_state');
  });

  it.each([503, 401])('keeps OAuth acceptance separate from initial import HTTP %i', async (status) => {
    const user = await member();
    const state = await createIntervalsOAuthState(env.DB, user.id);
    fetchMock.get(origin).intercept({ path: '/api/oauth/token', method: 'POST' })
      .reply(200, { access_token: 'synthetic-token', athlete: { id: 'oauth-athlete' } });
    importResponse(status, {});
    const response = await SELF.fetch(`https://test/auth/intervals/callback?code=synthetic-code&state=${state}`, { redirect: 'manual' });
    expect(response.headers.get('Location')).toBe(`tresfort://intervals-connected?ok=1&sync=${status === 401 ? 'reconnect' : 'retry'}`);
    expect(await getIntervalsConnectionStatus(env.DB, user.id)).toMatchObject({
      connected: status !== 401, needs_reauth: status === 401,
    });
  });

  it('cancels pending OAuth intents on disconnect and rejects consumed callbacks that cross a credential change', async () => {
    const user = await member();
    const pending = await createIntervalsOAuthState(env.DB, user.id);
    const consumed = await consumeIntervalsOAuthAttempt(env.DB, await createIntervalsOAuthState(env.DB, user.id));
    expect(consumed).toMatchObject({ user_id: user.id, credential_generation: 0 });
    await setUserIntervalsCreds(env.DB, user.id, null, null);
    expect(await consumeIntervalsOAuthAttempt(env.DB, pending)).toBeNull();
    expect(await setUserIntervalsOAuth(env.DB, user.id, 'late-token', null, null, 'late-athlete', consumed!.credential_generation)).toBeNull();
    expect((await getIntervalsConnectionStatus(env.DB, user.id)).connected).toBe(false);
  });
});
