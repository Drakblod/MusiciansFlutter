const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithCustomToken, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut } = require('firebase/auth');
const { getDatabase, connectDatabaseEmulator, ref: databaseRef, get: databaseGet, set: databaseSet, update: databaseUpdate } = require('firebase/database');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { manager, authorizeRequest } = require('../membership_authority');

for (const status of [undefined,'active',' ACTIVE ','on_hold','temporarily_off']) {
  it(`authority policy accepts normalized legacy/active-access manager ${status}`, () => {
    assert(manager({Role:' aDmIn ',Status:status}));
  });
}
for (const status of ['inactive','removed','excluded','pending','invited','archived','unknown','']) {
  it(`authority policy rejects manager status ${status}`, () => assert(!manager({Role:'Leader',Status:status})));
}
it('authority policy rejects conflicting legacy role/status aliases', () => {
  assert(!manager({Role:'Leader',role:'Member',Status:'active'}));
  assert(!manager({Role:'Leader',Status:'active',status:'inactive'}));
});

for (const ruleFile of ['database.rules.json','database.transitional.rules.json']) {
 describe(`Membership authority real emulators: ${ruleFile}`, function () {
  this.timeout(120000);
  let env, adminApp, db;
  const clients = {};
  const namespace = 'demo-musicians-test';
  const uid = { leader:'ma_leader',admin:'ma_admin',member:'ma_member',other:'ma_other',target:'ma_target' };
  let seq = 0, band;
  async function call(who, name, data) {
    return (await httpsCallable(clients[who].functions,name)(data)).data;
  }
  async function mutation(who, action, data={}) {
    return call(who,'mutateBandMembership',{action,bandId:band,operationId:`op_${++seq}`,...data});
  }
  async function denied(promise) {
    await assert.rejects(promise, e => ['functions/permission-denied','functions/failed-precondition','functions/invalid-argument','functions/not-found','functions/already-exists'].includes(e.code));
  }
  async function members() { return (await db.ref(`Bands/${band}/Members_band`).get()).val(); }
  function leaderCount(value) { return Object.values(value || {}).filter(m => String(m.Role ?? m.role).trim().toLowerCase()==='leader').length; }
  async function request(overrides={}) {
    const id=`req_${++seq}`;
    await db.ref(`SubRequests/${id}`).set({CreatorUserId:uid.leader,BandId:band,EventId:'event',Status:'published',Role:'Substitute',Responses:{[uid.target]:true},...overrides});
    return id;
  }
  before(async () => {
    process.env.FIREBASE_DATABASE_EMULATOR_HOST='127.0.0.1:9000';
    process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';
    const admin=require('firebase-admin');
    adminApp=admin.initializeApp({projectId:namespace,databaseURL:`http://127.0.0.1:9000?ns=${namespace}`},`authority_${ruleFile}`);
    db=adminApp.database();
    for (const id of ['target_leader','target_admin']) {
      try { await adminApp.auth().getUser(id); }
      catch (e) { if (e.code !== 'auth/user-not-found') throw e; await adminApp.auth().createUser({uid:id}); }
    }
    env=await initializeTestEnvironment({projectId:namespace,database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',ruleFile),'utf8')}});
    for (const [name,id] of Object.entries(uid)) {
      const app=initializeApp({projectId:namespace,apiKey:'fake-api-key'},`authority_${ruleFile}_${name}`);
      const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      await signInWithCustomToken(auth,await adminApp.auth().createCustomToken(id));
      const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,'127.0.0.1',5001);
      clients[name]={app,functions};
    }
  });
  beforeEach(async () => {
    band=`authority_band_${ruleFile.includes('transitional')?'t':'f'}_${++seq}`;
    await db.ref(`Bands/${band}`).set({Name:'Authority band',Members_band:{
      [uid.leader]:{Role:'Leader',Status:'active'},[uid.admin]:{Role:'Admin',Status:'active'},
      [uid.member]:{Role:'Member',Status:'active'}},Events:{event:{createdBy:uid.leader,title:'Event'}}});
    await db.ref(`Bands/authority_other/Members_band/${uid.other}`).set({Role:'Leader',Status:'active'});
  });
  after(async () => {
    for (const client of Object.values(clients)) await deleteApp(client.app);
    if (env) await env.cleanup();
    if (adminApp) await adminApp.delete();
  });
  for (const [name,value] of [['fabricated Leader',{Role:'Leader',Status:'active'}],['fabricated Admin',{Role:'Admin'}]]) {
    it(`denies ${name} in an existing band`,async()=>assertFails(env.authenticatedContext(uid.other).database().ref(`Bands/${band}/Members_band/${uid.other}`).set(value)));
  }
  for (const role of ['Admin','Leader']) {
    it(`denies Member self promotion to ${role}`,async()=>assertFails(env.authenticatedContext(uid.member).database().ref(`Bands/${band}/Members_band/${uid.member}/Role`).set(role)));
  }
  it('denies self inactive-to-active status',async()=>{
    await db.ref(`Bands/${band}/Members_band/${uid.member}/Status`).set('inactive');
    await assertFails(env.authenticatedContext(uid.member).database().ref(`Bands/${band}/Members_band/${uid.member}/Status`).set('active'));
  });
  it('denies partial update and membership-parent overwrite',async()=>{
    const client=env.authenticatedContext(uid.member).database();
    await assertFails(client.ref(`Bands/${band}/Members_band/${uid.member}`).update({Role:'Admin'}));
    await assertFails(client.ref(`Bands/${band}/Members_band`).set({[uid.member]:{Role:'Leader'}}));
    await assertFails(client.ref(`Bands/${band}`).update({Members_band:{[uid.member]:{Role:'Leader'}}}));
  });
  it('denies client whole-band creation with embedded Leader',async()=>assertFails(env.authenticatedContext(uid.member).database().ref(`Bands/forged_${band}`).set({Members_band:{[uid.member]:{Role:'Leader'}}})));
  it('denies forged index, legacy snapshot and conversation membership',async()=>{
    const client=env.authenticatedContext(uid.member).database();
    for (const p of [`userBandMembershipIndex/${uid.member}/${band}`,`userBandMemberships/${uid.member}/${band}`,`users/${uid.member}/Bands/${band}`,`bandconversations/${band}/members/${uid.member}`]) await assertFails(client.ref(p).set(true));
    await assertFails(client.ref(`users/${uid.member}`).set({Bands:{[band]:{Members_band:{[uid.member]:{Role:'Leader'}}}}}));
  });
  it('preserves owner profile writes and active member messages without granting protected siblings',async()=>{
    const client=env.authenticatedContext(uid.member).database();
    await assertSucceeds(client.ref(`users/${uid.member}/info/DisplayName`).set('Member'));
    await db.ref(`bandconversations/${band}/members/${uid.member}`).set(true);
    await assertSucceeds(client.ref(`bandconversations/${band}/messages/message`).set({SenderId:uid.member,Text:'Hello'}));
  });
  it('reserved object keys and nonexistent targets fail without changing canonical members',async()=>{
    const before=await members();
    for (const userId of ['__proto__','constructor','nonexistent_auth_account']) await denied(mutation('leader','role',{userId,role:'Admin'}));
    assert.deepStrictEqual(await members(),before);
  });
  it('internal account-departure and delete operations are not public mutation actions',async()=>{
    await denied(mutation('leader','departAccount'));
    await denied(mutation('leader','delete'));
    assert.strictEqual(leaderCount(await members()),1);
  });
  it('ordinary Member cannot promote another member through callable',async()=>denied(mutation('member','role',{userId:uid.admin,role:'Member'})));
  it('Admin cannot remove or demote Leader',async()=>{
    await denied(mutation('admin','remove',{userId:uid.leader}));
    await denied(mutation('admin','role',{userId:uid.leader,role:'Member'}));
  });
  it('Admin cannot promote self or transfer ownership',async()=>{
    await denied(mutation('admin','role',{userId:uid.admin,role:'Leader'}));
    await denied(mutation('admin','transfer',{userId:uid.admin}));
  });
  it('Leader and Admin add ordinary members with reconciled discovery/chat/compatibility',async()=>{
    for (const who of ['leader','admin']) {
      const target=`target_${who}`;
      await mutation(who,'add',{userId:target,role:'Member'});
      assert.strictEqual((await members())[target].Role,'Member');
      assert.strictEqual((await db.ref(`userBandMembershipIndex/${target}/${band}`).get()).val(),true);
      assert.strictEqual((await db.ref(`bandconversations/${band}/members/${target}`).get()).val(),true);
      assert.strictEqual((await db.ref(`users/${target}/Bands/${band}`).get()).val().Events,undefined);
    }
  });
  it('Leader promotes Member to Admin then demotes to Member',async()=>{
    await mutation('leader','role',{userId:uid.member,role:'Admin'});
    assert.strictEqual((await members())[uid.member].Role,'Admin');
    await mutation('leader','role',{userId:uid.member,role:'Member'});
    assert.strictEqual((await members())[uid.member].Role,'Member');
  });
  it('Leader transfer is atomic and idempotent with exactly one Leader',async()=>{
    const op={userId:uid.member,operationId:'transfer_once'};
    await mutation('leader','transfer',op);
    await mutation('leader','transfer',op);
    const value=await members();assert.strictEqual(leaderCount(value),1);
    assert.strictEqual(value[uid.member].Role,'Leader');assert.strictEqual(value[uid.leader].Role,'Admin');
  });
  it('concurrent transfers cannot create two Leaders',async()=>{
    const result=await Promise.allSettled([mutation('leader','transfer',{userId:uid.member}),mutation('leader','transfer',{userId:uid.admin})]);
    assert.strictEqual(result.filter(x=>x.status==='fulfilled').length,1);
    assert.strictEqual(leaderCount(await members()),1);
  });
  it('band creation creates sole Leader and retries without overwrite',async()=>{
    const id=`created_${band}`;
    const payload={bandId:id,operationId:'create_once',metadata:{Name:'Created band',Members_band:{[uid.other]:{Role:'Leader'}}}};
    await mutation('leader','create',payload);await mutation('leader','create',payload);
    const value=(await db.ref(`Bands/${id}/Members_band`).get()).val();
    assert.strictEqual(leaderCount(value),1);assert.strictEqual(value[uid.leader].Role,'Leader');assert.strictEqual(value[uid.other],undefined);
    await denied(mutation('other','create',{...payload,operationId:'collision'}));
  });
  it('Leader cannot orphan band by self leave; Member may leave',async()=>{
    await denied(mutation('leader','leave'));
    await mutation('member','leave');
    assert.strictEqual((await members())[uid.member],undefined);
    assert.strictEqual(leaderCount(await members()),1);
  });
  it('removal reconciles canonical membership, discovery, conversation and compatibility',async()=>{
    await mutation('leader','remove',{userId:uid.member});
    for (const p of [`Bands/${band}/Members_band/${uid.member}`,`userBandMembershipIndex/${uid.member}/${band}`,`bandconversations/${band}/members/${uid.member}`,`users/${uid.member}/Bands/${band}`]) assert.strictEqual((await db.ref(p).get()).val(),null);
  });
  it('inactive managers cannot mutate or publish',async()=>{
    for (const who of ['leader','admin']) {
      await db.ref(`Bands/${band}/Members_band/${uid[who]}/Status`).set('inactive');
      await denied(mutation(who,'add',{userId:uid.target}));
      await denied(call(who,'publishSubRequestGroup',{bandId:band,requestGroupId:`g_${++seq}`,slots:[{slotId:`s_${seq}`}]}));
    }
  });
  for (const who of ['member','other']) {
    it(`${who} cannot manage staffing for another authority`,async()=>{
      const id=await request();
      await denied(call(who,'assignSubstitute',{subRequestId:id,candidateUserId:uid.target}));
      await denied(call(who,'deleteSubRequest',{subRequestId:id}));
      await denied(call(who,'revokeSubstituteAssignment',{subRequestId:id}));
    });
  }
  it('all management callables reject mismatching client band',async()=>{
    const id=await request({Status:'assigned',AssignedUserId:uid.target});
    for (const name of ['assignSubstitute','revokeSubstituteAssignment','createAgreementConversation','deleteSubRequest']) {
      await denied(call('other',name,{subRequestId:id,bandId:'authority_other',candidateUserId:uid.target,applicantId:uid.target}));
      assert.strictEqual((await db.ref(`SubRequests/${id}/Status`).get()).val(),'assigned');
    }
  });
  it('missing and conflicting canonical band identity fail closed',async()=>{
    for (const record of [{BandId:null},{bandId:'authority_other'}]) {
      const id=await request(record);
      await denied(call('leader','deleteSubRequest',{subRequestId:id}));
    }
  });
  it('canonical exact creator retains allowed assign/agreement/revoke retries with one agreement',async()=>{
    const id=await request({CreatorUserId:uid.member,BandId:'freelance',EventId:null});
    const payload={subRequestId:id,candidateUserId:uid.target};
    await call('member','assignSubstitute',payload);
    const beforeRetry = (await db.ref(`userNotifications/${uid.target}`).get()).val() || {};
    const beforeIds = Object.keys(beforeRetry).filter(k=>beforeRetry[k].data?.subRequestId===id).sort();
    await call('member','assignSubstitute',payload);
    const afterRetry = (await db.ref(`userNotifications/${uid.target}`).get()).val() || {};
    assert.deepStrictEqual(Object.keys(afterRetry).filter(k=>afterRetry[k].data?.subRequestId===id).sort(),beforeIds);
    const a=await call('member','createAgreementConversation',{subRequestId:id,applicantId:uid.target});
    const b=await call('member','createAgreementConversation',{subRequestId:id,applicantId:uid.target});
    assert.strictEqual(a.conversationId,b.conversationId);
    const conversations=(await db.ref('conversations').get()).val()||{};
    assert.strictEqual(Object.values(conversations).filter(c=>(c.Agreement?.SubRequestId ?? c.Agreement?.subRequestId)===id).length,1);
    const notifications=(await db.ref(`userNotifications/${uid.target}`).get()).val()||{};
    const matching=Object.values(notifications).filter(n=>n.data?.subRequestId===id);
    const ids=matching.map(n=>n.id);assert.strictEqual(new Set(ids).size,ids.length);
    await call('member','revokeSubstituteAssignment',{subRequestId:id});
    await call('member','revokeSubstituteAssignment',{subRequestId:id});
    assert.strictEqual((await db.ref(`SubRequests/${id}/Status`).get()).val(),'published');
  });
  for (const status of ['active','inactive']) {
    it(`former Leader creator now ${status} Member cannot manage band requests or write partial results`,async()=>{
      const id=await request();
      await db.ref(`Bands/${band}/Members_band/${uid.leader}`).set({Role:'Member',Status:status});
      await db.ref(`Bands/${band}/Members_band/${uid.admin}/Role`).set('Leader');
      const before=(await db.ref(`SubRequests/${id}`).get()).val();
      const roster=await members();
      const conversations=(await db.ref('conversations').get()).val();
      for (const name of ['assignSubstitute','revokeSubstituteAssignment','createAgreementConversation','deleteSubRequest']) {
        await denied(call('leader',name,{subRequestId:id,candidateUserId:uid.target,applicantId:uid.target}));
      }
      for (const supplied of [undefined,'freelance',band]) {
        await denied(call('leader','publishSubRequestGroup',{bandId:supplied,requestGroupId:`g_${id}`,slots:[{slotId:id,subRequestId:id}]}));
      }
      assert.deepStrictEqual((await db.ref(`SubRequests/${id}`).get()).val(),before);
      assert.deepStrictEqual(await members(),roster);
      assert.deepStrictEqual((await db.ref('conversations').get()).val(),conversations);
    });
  }
  it('retry ledger rejects injection, oversized IDs and changed payload; stays private and bounded',async()=>{
    for(const operationId of ['x/y','x.y','x#y','x$y','x[y','x]y','x'.repeat(129)]) {
      await denied(mutation('leader','metadata',{operationId,metadata:{Name:'Invalid'}}));
    }
    await mutation('leader','metadata',{operationId:'same_id',metadata:{Name:'Same'}});
    await mutation('leader','metadata',{operationId:'same_id',metadata:{Name:'Same'}});
    await denied(mutation('leader','metadata',{operationId:'same_id',metadata:{Name:'Different'}}));
    await denied(mutation('leader','metadata',{operationId:'same_id',metadata:{Name:'Same'},nickname:'Changed'}));
    const ledger=`membershipMutationOperations/${band}`;
    for(const who of ['leader','member','other']) {
      const client=env.authenticatedContext(uid[who]).database();
      await assertFails(client.ref(ledger).get());
      await assertFails(client.ref(ledger).set({forged:true}));
    }
    for(let i=0;i<66;i++) await mutation('leader','metadata',{operationId:`bounded_${i}`,metadata:{Name:`Bounded ${i}`}});
    const privateLedger=(await db.ref(ledger).get()).val();
    const receipts=(await db.ref(`Bands/${band}/_membershipOperations`).get()).val();
    assert.strictEqual(Object.keys(privateLedger).length,64);
    assert.strictEqual(Object.keys(receipts).length,64);
    assert(Object.values(privateLedger).every(r=>Object.keys(r).sort().join(',')==='fingerprint,timestamp' && /^[a-f0-9]{64}$/.test(r.fingerprint)));
    assert(Object.values(receipts).every(r=>typeof r==='number'));
    await denied(mutation('member','metadata',{operationId:'outsider',metadata:{Name:'No'}}));
    assert.strictEqual(Object.keys((await db.ref(ledger).get()).val()).length,64);
  });
  it('production registration/profile write shapes survive rules and auth reload without protected siblings',async()=>{
    const app=initializeApp({projectId:namespace,apiKey:'fake-api-key'},`registration_${ruleFile}`);
    const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
    const email=`profile_${ruleFile.replace(/\W/g,'')}_${Date.now()}@example.test`,password='ProfilePass123!';
    try {
      const credential=await createUserWithEmailAndPassword(auth,email,password);
      const id=credential.user.uid;
      // Use the same real Auth session for production-shaped RTDB writes and reload.
      const realDb=getDatabase(app,`https://${namespace}.firebaseio.com`);
      connectDatabaseEmulator(realDb,'127.0.0.1',9000);
      const client={ref:(path='')=>{
        const reference=path ? databaseRef(realDb,path) : databaseRef(realDb);
        return {set:value=>databaseSet(reference,value),update:value=>databaseUpdate(reference,value),get:()=>databaseGet(reference)};
      }};
      const fields={DisplayName:'New Musician',Email:email,Level:'A = PRO',About:'About',Instruments:['Guitar','Piano'],Styles:['Jazz'],Genres:['Rock'],Contact:email,History:'History',Projects:'Projects',ProfilePictureUrl:'',SpotifyUrl:'',YoutubeUrl:'',AudioSnippetUrl:'',CollabRoles:['Musician'],CollabRemote:true,CollabBio:'Bio',MainInstrument:'Guitar',UserType:'Musician',Nickname:'Nick'};
      const updates={};
      for(const [k,v] of Object.entries(fields)) {
        updates[`users/${id}/info/${k}`]=v;
        if(['UserType','Nickname','DisplayName'].includes(k))updates[`users/${id}/${k}`]=v;
      }
      await assertSucceeds(client.ref().update(updates));
      await assertFails(client.ref(`users/${id}/info/Location`).set('Stockholm'));
      await assertSucceeds(client.ref().update({[`users/${id}/info/MainInstrument`]:'Piano',[`users/${id}/info/Instruments`]:['Piano','Guitar','Vocals'],[`users/${id}/info/Genres`]:['Jazz']}));
      await assertSucceeds(client.ref(`users/${id}/info/PushToken`).set('local-test-token'));
      for(const [p,v] of [['Favorites/target',true],['metrics/buttonClicks/profile',2],['PublicEvents/event',{Title:'Public event'}]]) await assertSucceeds(client.ref(`users/${id}/${p}`).set(v));
      await assertFails(client.ref(`users/${id}/Bands/forged`).set({Role:'Leader'}));
      await assertFails(client.ref().update({[`users/${id}/info/DisplayName`]:'Atomic forbidden',[`users/${id}/Bands/forged`]:true}));
      assert.strictEqual((await client.ref(`users/${id}/info/DisplayName`).get()).val(),'New Musician');
      const outsider=env.authenticatedContext(uid.other).database();
      for(const p of ['info/MainInstrument','info/Instruments','info/Genres','info/DisplayName','info/PushToken','Nickname','DisplayName','Favorites/target','metrics/buttonClicks/profile','PublicEvents/event']) await assertFails(outsider.ref(`users/${id}/${p}`).set('forged'));
      await signOut(auth);await signInWithEmailAndPassword(auth,email,password);
      assert.strictEqual(auth.currentUser.uid,id);
      const profile=(await client.ref(`users/${id}`).get()).val();
      assert.strictEqual(profile.info.MainInstrument,'Piano');assert.deepStrictEqual(profile.info.Instruments,['Piano','Guitar','Vocals']);assert.deepStrictEqual(profile.info.Genres,['Jazz']);assert.strictEqual(profile.info.PushToken,'local-test-token');
    } finally { await deleteApp(app); }
  });
  it('account deletion end-to-end owns auth identity, safely retries interrupted RTDB work and removes Auth',async()=>{
    const app=initializeApp({projectId:namespace,apiKey:'fake-api-key'},`delete_e2e_${ruleFile}`);
    const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
    const email=`delete_${ruleFile.replace(/\W/g,'')}_${Date.now()}@example.test`,password='DeletePass123!';
    try {
      const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,'127.0.0.1',5001);
      const invoke=data=>httpsCallable(functions,'deleteUserAccount')(data);
      await assert.rejects(invoke({}),e=>e.code==='functions/unauthenticated');
      const credential=await createUserWithEmailAndPassword(auth,email,password),id=credential.user.uid;
      await denied(invoke({userId:uid.member}));
      assert((await adminApp.auth().getUser(uid.member)).uid===uid.member);
      const owned=`deletion_${band}`;
      await db.ref(`Bands/${owned}`).set({Name:'Deletion',Members_band:{[id]:{Role:'Leader',Status:'active'},[uid.admin]:{Role:'Admin',Status:'active'}}});
      await db.ref().update({[`userBandMembershipIndex/${id}/${owned}`]:true,[`users/${id}/Bands/${owned}`]:{Name:'Deletion'},[`users/${id}/info`]:{DisplayName:'Delete me'},[`bandconversations/${owned}/members/${id}`]:true,[`userNotifications/${id}/n`]:{text:'Notice'},[`userSubRequestFeed/${id}/r`]:true,[`creatorSubRequestGroups/${id}/g`]:true,[`userConversations/${id}/c`]:true});
      await db.ref(`SubRequests/retained_${owned}`).set({CreatorUserId:id,BandId:owned,Status:'published'});
      await db.ref(`SubRequests/freelance_${owned}`).set({CreatorUserId:id,BandId:'freelance',Status:'published'});
      // Simulate interruption after the canonical departure succeeded but before account deletion.
      await require('../membership_authority').mutate(db,id,{action:'departAccount',bandId:owned,operationId:'delete_account'});
      const first=(await db.ref(`Bands/${owned}/Members_band`).get()).val();assert.strictEqual(first[uid.admin].Role,'Leader');
      await db.ref().update({[`userBandMembershipIndex/${id}/${owned}`]:true,[`users/${id}/Bands/${owned}`]:{Name:'Interrupted projection'},[`bandconversations/${owned}/members/${id}`]:true});
      await invoke({});
      assert.strictEqual((await db.ref(`Bands/${owned}/Members_band/${id}`).get()).val(),null);
      for(const p of [`users/${id}`,`userBandMembershipIndex/${id}`,`bandconversations/${owned}/members/${id}`,`userNotifications/${id}`,`userSubRequestFeed/${id}`,`creatorSubRequestGroups/${id}`,`userConversations/${id}`]) assert.strictEqual((await db.ref(p).get()).val(),null);
      assert.strictEqual((await db.ref(`SubRequests/retained_${owned}/Status`).get()).val(),'published');
      assert.strictEqual((await db.ref(`SubRequests/freelance_${owned}`).get()).val(),null);
      await assert.rejects(adminApp.auth().getUser(id),e=>e.code==='auth/user-not-found');
      await signOut(auth);await assert.rejects(signInWithEmailAndPassword(auth,email,password));
      const second=await createUserWithEmailAndPassword(auth,`sole_${email}`,password),sole=second.user.uid;
      const soleBand=`sole_${owned}`;
      await db.ref(`Bands/${soleBand}`).set({Name:'Sole',Members_band:{[sole]:{Role:'Leader',Status:'active'},[uid.member]:{Role:'Member',Status:'inactive'}}});
      await db.ref(`userBandMembershipIndex/${sole}/${soleBand}`).set(true);
      await denied(invoke({})); // No active successor: no false success, no Auth deletion.
      assert.strictEqual((await adminApp.auth().getUser(sole)).uid,sole);
      assert.strictEqual((await db.ref(`Bands/${soleBand}/Members_band/${sole}/Role`).get()).val(),'Leader');
      await db.ref(`Bands/${soleBand}/Members_band/${uid.member}`).remove();
      await invoke({});
      assert.strictEqual((await db.ref(`Bands/${soleBand}`).get()).val(),null);
      await assert.rejects(adminApp.auth().getUser(sole),e=>e.code==='auth/user-not-found');
      await signOut(auth);
      const finalAttempt=await createUserWithEmailAndPassword(auth,`partial_${email}`,password);
      // RTDB stage already completed; retry still deletes the remaining Auth account.
      await invoke({});
      await assert.rejects(adminApp.auth().getUser(finalAttempt.user.uid),e=>e.code==='auth/user-not-found');
    } finally { await deleteApp(app); }
  });
  it('inactive managers are denied assign, revoke, agreement and deletion for an exact band request',async()=>{
    const id=await request({CreatorUserId:uid.member,Status:'assigned',AssignedUserId:uid.target});
    for (const who of ['leader','admin']) {
      await db.ref(`Bands/${band}/Members_band/${uid[who]}/Status`).set('inactive');
      for (const name of ['assignSubstitute','revokeSubstituteAssignment','createAgreementConversation','deleteSubRequest']) {
        await denied(call(who,name,{subRequestId:id,candidateUserId:uid.target,applicantId:uid.target}));
      }
    }
    assert.strictEqual((await db.ref(`SubRequests/${id}/Status`).get()).val(),'assigned');
  });
  it('republishing another canonical owning band is denied before overwrite',async()=>{
    const id=await request();
    await denied(call('other','publishSubRequestGroup',{bandId:'authority_other',requestGroupId:`cross_${band}`,slots:[{subRequestId:id,slotId:id}]}));
    assert.strictEqual((await db.ref(`SubRequests/${id}/BandId`).get()).val(),band);
  });
  it('unavailable candidate is rejected before canonical assignment or membership changes',async()=>{
    const id=await request({Responses:{missing_candidate:true}});
    await denied(call('leader','assignSubstitute',{subRequestId:id,candidateUserId:'missing_candidate'}));
    assert.strictEqual((await db.ref(`SubRequests/${id}/Status`).get()).val(),'published');
    assert.strictEqual((await db.ref(`Bands/${band}/Members_band/missing_candidate`).get()).val(),null);
  });
  it('normalized legacy manager role/status retains publication authority',async()=>{
    await db.ref(`Bands/${band}/Members_band/${uid.admin}`).set({role:' aDmIn '});
    const result=await call('admin','publishSubRequestGroup',{bandId:band,requestGroupId:`${band}_group_${++seq}`,slots:[{slotId:`${band}_slot_${seq}`,eventId:'event'}]});
    assert.strictEqual(result.success,true);
  });
  it('only active Leader deletes a band and deletion clears derived membership indexes',async()=>{
    await denied(call('admin','deleteBand',{bandId:band}));
    await call('leader','deleteBand',{bandId:band});
    await call('leader','deleteBand',{bandId:band});
    assert.strictEqual((await db.ref(`Bands/${band}`).get()).val(),null);
    for (const id of [uid.leader,uid.admin,uid.member]) assert.strictEqual((await db.ref(`userBandMembershipIndex/${id}/${band}`).get()).val(),null);
  });
  it('own account deletion transfers leadership atomically to an active successor',async()=>{
    // The fixture writes canonical membership directly. Wait for its actual
    // index trigger before exercising account deletion's index discovery.
    let indexed=false;
    for(let attempt=0;attempt<100;attempt++){
      indexed=(await db.ref(`userBandMembershipIndex/${uid.leader}/${band}`).get()).exists();
      if(indexed)break;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    assert(indexed,'Membership index trigger did not converge');
    await call('leader','deleteUserAccount',{});
    const value=await members();
    assert.strictEqual(value[uid.leader],undefined);assert.strictEqual(leaderCount(value),1);
    assert.strictEqual(value[uid.admin].Role,'Leader');
    assert.strictEqual((await db.ref(`userBandMembershipIndex/${uid.leader}`).get()).val(),null);
    assert.strictEqual((await db.ref(`userBandMembershipIndex/${uid.leader}/${band}`).get()).val(),null);
  });

 });
}

// No Functions binding in these namespaces: triggers cannot mask stale grants.
for (const file of ['database.rules.json','database.transitional.rules.json']) {
 describe(`Canonical chat membership rules: ${file}`,function(){
  this.timeout(20000);let env;
  before(async()=>{env=await initializeTestEnvironment({projectId:`demo-chat-authority-${file.includes('transitional')?'t':'f'}`,database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',file),'utf8')}});});
  after(async()=>{if(env)await env.cleanup();});
  for(const status of [null,' ACTIVE ','on_hold','temporarily_off','inactive','removed','pending']) {
   it(`canonical status ${status} controls chat despite a stale true projection`,async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{
      await ctx.database().ref('Bands/b/Members_band/u').set({Role:'Member',...(status==null?{}:{Status:status})});
      await ctx.database().ref('bandconversations/b/members/u').set(true);
      await ctx.database().ref('bandconversations/b/messages/m').remove();
    });
    const write=env.authenticatedContext('u').database().ref('bandconversations/b/messages/m').set({SenderId:'u',Text:'Hello'});
    if(['inactive','removed','pending'].includes(status))await assertFails(write);else await assertSucceeds(write);
   });
  }
  it('missing canonical membership cannot use a true conversation projection',async()=>{
    await env.withSecurityRulesDisabled(async ctx=>{await ctx.database().ref('Bands/b/Members_band/u').remove();await ctx.database().ref('bandconversations/b/members/u').set(true);});
    await assertFails(env.authenticatedContext('u').database().ref('bandconversations/b/messages/missing').set({SenderId:'u',Text:'No'}));
  });
 });
}
