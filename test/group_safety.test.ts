import { env, applyD1Migrations } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { issueAppJwt } from '../src/auth';
import { apiRoutes } from '../src/routes/api';
import { handleMcp } from '../src/mcp/server';
import { createGroup, createInvite, deleteUserAccount, exportUserData, getGroupFeed, getInvitePreview, setGroupSharingRestriction } from '../src/db';
import { sharedText } from '../src/groupSafety';

const ownerSub = 'safety-test-owner';
const ts = Date.now();
const date = new Date(ts).toISOString().slice(0, 10);
beforeAll(async () => { await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });
async function user(name: string, sub = crypto.randomUUID()) {
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO users (id,apple_sub,display_name,created_at,timezone) VALUES (?1,?2,?3,?4,\'UTC\')')
    .bind(id, sub, name, ts).run();
  return { id, jwt: await issueAppJwt(id, 'test-secret') };
}
async function request(jwt: string, path: string, method = 'GET', body?: unknown, configured = true) {
  return apiRoutes.request(path, { method, headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) }, { ...env, OWNER_APPLE_SUB: configured ? ownerSub : undefined });
}
async function seed() {
  const a = await user('Alex', ownerSub), b = await user('Blair'), c = await user('Casey');
  const groups = [await createGroup(env.DB, a.id, 'Friends'), await createGroup(env.DB, b.id, 'Weekend')];
  for (const g of groups) for (const u of [a, b, c]) {
    await env.DB.prepare('INSERT OR IGNORE INTO group_members (group_id,user_id,joined_at) VALUES (?1,?2,?3)').bind(g.id, u.id, ts).run();
  }
  for (const u of [a, b, c]) {
    await env.DB.prepare("INSERT INTO activities (id,user_id,date,type,title,notes,logged_at,source) VALUES (?1,?2,?3,'walk','A walk','Private original',?4,'ios')")
      .bind(crypto.randomUUID(), u.id, date, ts).run();
    const p = crypto.randomUUID(), w = crypto.randomUUID();
    await env.DB.prepare("INSERT INTO plans (id,user_id,name,status,version,created_at,updated_at) VALUES (?1,?2,'Plan','active',1,?3,?3)").bind(p,u.id,ts).run();
    await env.DB.prepare("INSERT INTO workouts (id,plan_id,name,order_index,created_at,updated_at) VALUES (?1,?2,'Lower A',0,?3,?3)").bind(w,p,ts).run();
    await env.DB.prepare("INSERT INTO sessions (id,user_id,plan_id,workout_id,date,status,created_at,updated_at,completed_at) VALUES (?1,?2,?3,?4,?5,'completed',?6,?6,?6)")
      .bind(crypto.randomUUID(),u.id,p,w,date,ts).run();
    await env.DB.prepare("INSERT INTO external_activities (id,user_id,source,external_id,date,kind,name,synced_at) VALUES (?1,?2,'intervals',?1,?3,'ride','Morning ride',?4)")
      .bind(crypto.randomUUID(),u.id,date,ts).run();
  }
  return { a, b, c, groups };
}
async function block(jwt: string, target: string, active = true) {
  return request(jwt, `/me/group-blocks/${target}`, 'PUT', { active });
}
async function exportedUser(id: string) {
  return await exportUserData(env.DB, id) as {
    training: { activities: { notes: string | null }[] };
    group_safety: { blocks: { user_id: string }[] };
  };
}

describe('private group safety', () => {
  it('blocks mutually in every shared roster, feed, stats and series; other members and private history stay intact', async () => {
    const { a,b,c,groups } = await seed();
    expect((await block(a.jwt,b.id)).status).toBe(200);
    for (const g of groups) for (const [viewer,hidden] of [[a,b],[b,a]]) {
      for (const suffix of ['', '/feed', '/stats', '/activity']) {
        const res = await request(viewer!.jwt, `/groups/${g.id}${suffix}`);
        expect(res.status).toBe(200); expect(res.headers.get('cache-control')).toBe('no-store');
        const body = await res.json<any>();
        const ids = (body.items ?? body.members).map((r: any) => r.user_id);
        expect(ids).not.toContain(hidden!.id); expect(ids).toContain(viewer!.id); expect(ids).toContain(c.id);
      }
      const list = await (await request(viewer!.jwt,'/groups')).json<any>();
      expect(list.groups.every((g: any) => g.members.every((m: any) => m.user_id !== hidden!.id))).toBe(true);
    }
    expect((await getGroupFeed(env.DB, groups[0]!.id,null,null,30,c.id))).toHaveLength(9);
    expect((await exportedUser(b.id)).training.activities).toHaveLength(1);
  });
  it('uses the same boundary in the MCP dispatcher and does not lose visible rows at page boundaries', async () => {
    const { a,b,groups } = await seed();
    await block(a.jwt,b.id);
    const mcp = await handleMcp({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'get_group_feed',arguments:{group_id:groups[0]!.id}}},env,a.id);
    const response = mcp.json as { result: { content: { text: string }[] } };
    const data = JSON.parse(response.result.content[0]!.text);
    expect(data.items).toHaveLength(6); expect(data.stats.map((m: any) => m.user_id)).not.toContain(b.id);
    const seen: string[] = [];
    let time: number | null = null, id: string | null = null;
    for (let n=0;n<7;n++) {
      const page = await getGroupFeed(env.DB, groups[0]!.id,time,id,1,a.id);
      if (!page.length) break;
      expect(page[0]!.user_id).not.toBe(b.id);
      time=page[0]!.occurred_at; id=page[0]!.id; seen.push(id);
    }
    expect(new Set(seen).size).toBe(6);
  });
  it('only lets a caller block a distinct common-group member, keeps retry idempotent, and only undoes their own block', async () => {
    const {a,b,c}=await seed(); const stranger=await user('Stranger');
    expect((await block(a.jwt,a.id)).status).toBe(404);
    expect((await block(a.jwt,stranger.id)).status).toBe(404);
    expect((await request(a.jwt,`/me/group-blocks/${b.id}`,'PUT',{active:'yes'})).status).toBe(400);
    await block(a.jwt,b.id); await block(a.jwt,b.id); await block(b.jwt,a.id);
    await block(c.jwt,b.id,false);
    expect((await (await request(a.jwt,'/me/group-safety')).json<any>()).blocks).toHaveLength(1);
    await block(a.jwt,b.id,false);
    expect((await (await request(a.jwt,'/me/group-safety')).json<any>()).blocks).toHaveLength(0);
    expect((await (await request(b.jwt,'/me/group-safety')).json<any>()).blocks).toHaveLength(1);
  });
  it('unblocks after leaving the group and applies existing blocks when members rejoin', async () => {
    const {a,b,groups}=await seed(); await block(a.jwt,b.id);
    await env.DB.prepare('DELETE FROM group_members WHERE user_id = ?1').bind(a.id).run();
    await env.DB.prepare('INSERT INTO group_members (group_id,user_id,joined_at) VALUES (?1,?2,?3)').bind(groups[0]!.id,a.id,ts).run();
    expect((await getGroupFeed(env.DB,groups[0]!.id,null,null,30,a.id)).some(x=>x.user_id===b.id)).toBe(false);
    await env.DB.prepare('DELETE FROM group_members WHERE user_id = ?1').bind(a.id).run();
    expect((await block(a.jwt,b.id,false)).status).toBe(200);
  });
  it('restricts sharing with explicit operator identity, audit and reversal, preserving private records', async () => {
    const {a,b,c,groups}=await seed();
    for (const [jwt,configured] of [[b.jwt,true],[a.jwt,false]] as const) {
      expect((await request(jwt,`/group-safety/restrictions/${b.id}`,'PUT',{active:true,reason:'harassment'},configured)).status).toBe(403);
    }
    expect((await request(a.jwt,`/group-safety/restrictions/${b.id}`,'PUT',{active:true,reason:'freeform'})).status).toBe(400);
    expect((await request(a.jwt,`/group-safety/restrictions/${b.id}`,'PUT',{active:true,reason:'harassment'})).status).toBe(200);
    const res = await (await request(c.jwt,`/groups/${groups[1]!.id}`)).json<any>();
    expect(res.name).toBe('Private group'); expect(res.members.map((m:any)=>m.user_id)).not.toContain(b.id);
    expect((await getGroupFeed(env.DB,groups[0]!.id,null,null,30,c.id))).toHaveLength(6);
    expect((await exportedUser(b.id)).training.activities).toHaveLength(1);
    expect((await env.DB.prepare("SELECT result FROM audit_log WHERE tool='set_group_sharing_restriction'").all()).results).toEqual([{result:'restricted'}]);
    expect((await request(a.jwt,`/group-safety/restrictions/${b.id}`,'PUT',{active:false,reason:'harassment'})).status).toBe(200);
    expect((await getGroupFeed(env.DB,groups[0]!.id,null,null,30,c.id))).toHaveLength(9);
  });
  it('rolls back a restriction if its audit fails', async () => {
    const {a,b}=await seed();
    await env.DB.exec("CREATE TRIGGER fail_safety_audit BEFORE INSERT ON audit_log WHEN NEW.tool='set_group_sharing_restriction' BEGIN SELECT RAISE(ABORT, 'audit unavailable'); END;");
    await expect(setGroupSharingRestriction(env.DB,a.id,ownerSub,b.id,true,'other')).rejects.toThrow();
    expect(await env.DB.prepare('SELECT * FROM group_sharing_restrictions WHERE user_id=?1').bind(b.id).first()).toBeNull();
  });
  it('filters shared names and activity text including previews, leaving private originals and exercise names intact', async () => {
    const {a,b,groups}=await seed();
    await env.DB.prepare("UPDATE users SET display_name='FUCK' WHERE id=?1").bind(b.id).run();
    await env.DB.prepare("UPDATE groups SET name='FUCK club' WHERE id=?1").bind(groups[0]!.id).run();
    await env.DB.prepare("UPDATE activities SET title='fucking loser',notes='kill yourself' WHERE user_id=?1").bind(b.id).run();
    const list=await (await request(a.jwt,'/groups')).json<any>();
    const filteredGroup = list.groups.find((g: any) => g.id === groups[0]!.id);
    expect(filteredGroup.name).toBe('Private group');
    expect(filteredGroup.members.find((m:any)=>m.user_id===b.id).effective_display_name).toBe('Member');
    const feed=await getGroupFeed(env.DB,groups[0]!.id,null,null,30,a.id);
    const activity=feed.find(x=>x.user_id===b.id&&x.type==='activity');
    expect(activity).toMatchObject({user_display_name:'Member',activity:{title:'Content hidden',notes:'Content hidden'}});
    expect((await exportedUser(b.id)).training.activities[0]?.notes).toBe('kill yourself');
    const invite=await createInvite(env.DB,a.id,groups[0]!.id);
    expect((await getInvitePreview(env.DB,invite.code)).group_name).toBe('Private group');
    for (const name of ['Skull Crusher','Assisted pull-up','Snatch','Scunthorpe runners']) expect(sharedText(name)).toBe(name);
    expect(sharedText('ＦＵＣＫ')).toBe('Content hidden'); expect(sharedText('f\u200buck')).toBe('Content hidden');
  });
  it('removes associated blocks and restrictions with account deletion and does not export incoming blockers', async () => {
    const {a,b,c}=await seed(); await block(a.jwt,b.id); await block(b.jwt,c.id);
    await setGroupSharingRestriction(env.DB,a.id,ownerSub,b.id,true,'other');
    const exported=await exportedUser(b.id);
    expect(exported.group_safety.blocks.map(x=>x.user_id)).toEqual([c.id]);
    const result=await deleteUserAccount(env.DB,b.id,ownerSub,crypto.randomUUID());
    expect(result).not.toHaveProperty('error');
    expect((await env.DB.prepare('SELECT * FROM group_member_blocks WHERE blocker_id=?1 OR blocked_id=?1').bind(b.id).all()).results).toHaveLength(0);
    expect(await env.DB.prepare('SELECT * FROM group_sharing_restrictions WHERE user_id=?1').bind(b.id).first()).toBeNull();
  });
});
