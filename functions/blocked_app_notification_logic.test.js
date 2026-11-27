'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { newlyBlocked, notificationId, handleRuleChange } = require('./blocked_app_notification_logic');
const rule = (name, restricted = true) => ({packageName: `com.${name}`, appName: name, restrictEnabled: restricted});
const rules = (...items) => ({ parentId: 'p', rules: items });

test('only newly restricted packages, grouped and deduplicated', () => {
  assert.deepEqual(newlyBlocked(rules(rule('A'), rule('B', false), rule('D')),
    rules(rule('A'), rule('B'), rule('C'), rule('C'), rule('D', false))).map(x=>x.appName), ['B','C']);
});
test('no-op, unblocking, monitor-only, website/schedule changes, malformed and deletion', () => {
  const old = rules(rule('A'));
  for (const after of [old, rules(rule('A', false)), {...old, schedules: {}},
    rules({...rule('A'), monitorEnabled: true}), {rules:'bad'}, undefined]) {
    assert.deepEqual(newlyBlocked(old, after), []);
  }
  assert.deepEqual(newlyBlocked({rules:[{}]}, old), []);
});
test('first block and reblock after unblocking are new events', () => {
  assert.equal(newlyBlocked(undefined, rules(rule('A'))).length, 1);
  assert.equal(newlyBlocked(rules(rule('A', false)), rules(rule('A'))).length, 1);
  assert.notEqual(notificationId('p','c','first'), notificationId('p','c','second'));
});

function fixture(token = 'tok') {
  const store = new Map([
    ['child_profiles/c', {parentId:'p', childAccountId:'u', pairingStatus:'connected'}],
    ['users/u', {role:'child', pairedParentId:'p', pairedChildProfileId:'c', pairingStatus:'connected', fcmToken:token}],
    ['child_profiles/other', {parentId:'p', childAccountId:'v', pairingStatus:'connected'}],
    ['users/v', {role:'child', pairedParentId:'different', pairedChildProfileId:'other', pairingStatus:'connected', fcmToken:'wrong'}],
  ]);
  const ref = path => ({path, collection: name => col(`${path}/${name}`), update: async data => Object.assign(store.get(path), data)});
  const snap = path => ({id:path.split('/').at(-1), ref:ref(path), exists:store.has(path), data:()=>store.get(path)});
  const col = path => ({doc:id=>ref(`${path}/${id}`), where:(field,op,value)=>({get:async()=>({docs:[...store.keys()].filter(k=>k.startsWith(path+'/') && k.split('/').length===2 && store.get(k)[field]===value).map(snap)})})});
  const db = {collection:col, runTransaction:async fn=>fn({get:async r=>snap(r.path),create:(r,data)=>{assert(!store.has(r.path));store.set(r.path,data);}})};
  const sent=[];
  const messaging={send:async message=>{sent.push(message);}};
  const event = {id:'e1',params:{parentId:'p'},time:'2026-11-28T01:00:00Z',data:{before:{data:()=>rules(rule('A',false))},after:{data:()=>rules(rule('A'),rule('B')),updateTime:new Date('2026-11-28T01:00:00Z')}}};
  const path = 'users/u/notifications/'+notificationId('p','c','e1');
  return {store, db, sent, messaging, event, path};
}
test('inbox before push, correct recipient, grouped, repeated event preserves read state', async () => {
  const f=fixture();
  f.messaging.send=async m=>{assert(f.store.has(f.path)); f.sent.push(m);};
  await handleRuleChange(f.event,f.db,f.messaging);
  const row=f.store.get(f.path);
  assert.equal(row.type,'app_restrictions_changed');
  assert.equal(row.readAt,null);
  assert.equal(row.apps.length,2);
  assert.equal(row.pushStatus,'sent');
  assert.equal(f.sent[0].token,'tok');
  assert.equal(f.sent[0].data.notificationId,f.path.split('/').at(-1));
  row.readAt='read';
  await handleRuleChange(f.event,f.db,f.messaging);
  assert.equal(f.sent.length,1);
  assert.equal(row.readAt,'read');
  assert.equal([...f.store.keys()].filter(k=>k.includes('/notifications/')).length,1);
});
test('no token still saves inbox', async () => {
  const f=fixture('');
  await handleRuleChange(f.event,f.db,f.messaging);
  assert.equal(f.store.get(f.path).pushStatus,'no_token');
  assert.equal(f.sent.length,0);
});
test('failed push preserves inbox and is not blindly retried', async () => {
  const f=fixture();
  f.messaging.send=async m=>{f.sent.push(m);throw Error('FCM failed');};
  await handleRuleChange(f.event,f.db,f.messaging,{warn:()=>{}});
  await handleRuleChange(f.event,f.db,f.messaging);
  assert.equal(f.store.get(f.path).pushStatus,'failed');
  assert.equal(f.sent.length,1);
});
