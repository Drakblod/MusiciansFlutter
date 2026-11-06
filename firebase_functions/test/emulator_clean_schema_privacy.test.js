'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,createUserWithEmailAndPassword,signOut,signInWithEmailAndPassword}=require('firebase/auth');
const {getDatabase,connectDatabaseEmulator,ref,get}=require('firebase/database');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');

for(const ruleFile of ['database.rules.json','database.transitional.rules.json']){
 describe(`CLEAN-SCHEMA-PRIVACY-CUTOVER-01 ${ruleFile}`,function(){
  this.timeout(180000);
  const projectId='demo-musicians-test',tag=ruleFile.includes('transitional')?'t':'f';
  const band=`clean_band_${tag}`,request=`clean_request_${tag}`;
  let env,app,db;const clients=[];const ids={};
  const client=uid=>env.authenticatedContext(uid).database();
  async function call(who,name,data){return (await httpsCallable(clients[who].functions,name)(data)).data;}
  async function waitFor(p,test){
    for(let i=0;i<200;i++){const v=(await db.ref(p).get()).val();if(test(v))return v;await new Promise(r=>setTimeout(r,100));}
    throw new Error(`Projection did not converge: ${p}`);
  }
  before(async()=>{
    app=admin.initializeApp({projectId,databaseURL:`http://127.0.0.1:9000?ns=${projectId}`},`clean_schema_${tag}`);db=app.database();
    env=await initializeTestEnvironment({projectId,database:{host:'127.0.0.1',port:9000,
      rules:fs.readFileSync(path.join(__dirname,'../..',ruleFile),'utf8')}});
    for(const role of ['leader','member','applicant','outsider']){
      const a=initializeApp({projectId,apiKey:'fake-api-key'},`clean_${tag}_${role}`);
      const auth=getAuth(a);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const credential=await createUserWithEmailAndPassword(auth,`clean_${tag}_${role}_${Date.now()}@example.test`,'local-test-password');
      const functions=getFunctions(a,'europe-west1');connectFunctionsEmulator(functions,'127.0.0.1',5001);
      const database=getDatabase(a,`https://${projectId}.firebaseio.com`);connectDatabaseEmulator(database,'127.0.0.1',9000);
      clients[role]={app:a,functions,auth,database,email:credential.user.email};ids[role]=credential.user.uid;
    }
  });
  after(async()=>{for(const c of Object.values(clients))await deleteApp(c.app);await env.cleanup();await app.delete();});

  it('bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies',async()=>{
    assert.equal((await db.ref(`Bands/${band}`).get()).exists(),false);
    for(const uid of Object.values(ids)){
      assert.equal((await db.ref(`users/${uid}`).get()).exists(),false);
      await assertSucceeds(client(uid).ref(`users/${uid}/info`).set({DisplayName:'New musician',Email:'private@example.test',MainInstrument:'Guitar'}));
      await waitFor(`publicUserProfiles/${uid}`,v=>v?.DisplayName==='New musician');
      const profile=(await client(ids.outsider).ref(`publicUserProfiles/${uid}`).get()).val();
      assert(!JSON.stringify(profile).includes('private@example.test'));
    }
    await call('leader','mutateBandMembership',{action:'create',bandId:band,operationId:'create',metadata:{Name:'New Band'}});
    let members=(await db.ref(`Bands/${band}/Members_band`).get()).val();
    assert.deepEqual(Object.keys(members),[ids.leader]);assert.equal(members[ids.leader].Role,'Leader');
    await call('leader','mutateBandMembership',{action:'add',bandId:band,operationId:'add',userId:ids.member,role:'Member'});
    await waitFor(`publicBandProfiles/${band}`,v=>v?.Name==='New Band'&&v?.activeMemberCount===2);
    await assertSucceeds(client(ids.outsider).ref(`publicBandProfiles/${band}`).get());
    await call('leader','mutateBandEvent',{action:'save',bandId:band,eventId:'event',event:{title:'Private concert',startDateTime:'2027-12-01T18:00:00Z',description:'Participant instructions'}});
    await waitFor(`bandMemberEvents/${band}/event`,v=>v?.title==='Private concert');
    await assertSucceeds(client(ids.member).ref(`Bands/${band}/Events/event/Responses/${ids.member}`).set({status:'YES',timestamp:'2027-01-01T00:00:00Z'}));
    await waitFor(`userEventReadModels/${ids.member}/${band}/event`,v=>v?.Responses?.[ids.member]?.status==='YES');
    const participant=clients.member;
    const projected=ref(participant.database,`userEventReadModels/${ids.member}/${band}/event`);
    await assertSucceeds(get(projected));
    await signOut(participant.auth);
    await assertFails(get(projected));
    await signInWithEmailAndPassword(participant.auth,participant.email,'local-test-password');
    assert.equal((await assertSucceeds(get(projected))).val().Responses[ids.member].status,'YES');
    await call('leader','publishSubRequestGroup',{bandId:band,requestGroupId:`group_${tag}`,slots:[{subRequestId:request,slotId:request,eventId:'event',voicePart:'Guitar',searchSource:'search_all',date:'2027-12-01'}]});
    await call('applicant','respondToSubRequest',{subRequestId:request});
    assert.equal((await db.ref(`SubRequests/${request}/Responses/${ids.applicant}`).get()).exists(),true);
    const result=await call('leader','assignSubstitute',{subRequestId:request,candidateUserId:ids.applicant});
    const conversations=(await db.ref(`userConversations/${ids.applicant}`).get()).val();
    const entry=Object.entries(conversations||{}).find(([,v])=>v.conversationType==='agreement');
    assert(entry,'Assignment creates indexed Agreement');
    await assertSucceeds(client(ids.applicant).ref(`conversations/${entry[0]}`).get());
    await assertFails(client(ids.outsider).ref(`conversations/${entry[0]}`).get());
    for(const uid of Object.values(ids))for(const root of ['Bands','SubRequests','Agreements'])
      assert.equal((await db.ref(`users/${uid}/${root}`).get()).exists(),false,`legacy users/${root}`);
    for(const root of ['SubRequestResponses','Agreements','PublishedSubRequests','Notifications'])
      assert.equal((await db.ref(`BandEvents/${root}/${request}`).get()).exists(),false);
    assert(result);
  });

  for(const audience of ['anonymous','outsider']){
    it(`${audience} cannot enumerate private roots or read canonical private descendants`,async()=>{
      const c=audience==='anonymous'?env.unauthenticatedContext().database():client(ids.outsider);
      for(const p of ['users','Bands','BandEvents',`users/${ids.leader}/info`,`Bands/${band}`,`Bands/${band}/Events/event`,
        `Bands/${band}/Events/event/substituteAssignments`,`SubRequests/${request}/Responses`,
        'subRequestAudience','eventReadProjectionIndex','membershipMutationOperations'])await assertFails(c.ref(p).get());
    });
  }
  it('ordinary member reads approved data and only own target, never manager or applicants',async()=>{
    const c=client(ids.member);
    await assertSucceeds(c.ref(`Bands/${band}/Name`).get());
    await assertSucceeds(c.ref(`bandMemberEvents/${band}/event`).get());
    await assertSucceeds(c.ref(`userEventReadModels/${ids.member}/${band}/event`).get());
    for(const p of [`bandManagerEvents/${band}/event`,`userEventReadModels/${ids.leader}/${band}/event`,
      `SubRequests/${request}/Responses`,`Bands/${band}/Events/event`])await assertFails(c.ref(p).get());
  });
  it('applicant reads only own canonical response and cannot forge another response',async()=>{
    const c=client(ids.applicant);
    await assertSucceeds(c.ref(`SubRequests/${request}/Responses/${ids.applicant}`).get());
    await assertFails(c.ref(`SubRequests/${request}/Responses/${ids.member}`).get());
    await assertFails(c.ref(`SubRequests/${request}/Responses/${ids.member}`).set(true));
  });
  it('legacy reads and writes fail closed even for their former owner',async()=>{
    const c=client(ids.leader);
    for(const p of [`users/${ids.leader}/Bands`,`users/${ids.leader}/SubRequests`,`users/${ids.leader}/Agreements`,
      'BandEvents/SubRequestResponses','BandEvents/Agreements','BandEvents/Notifications']){
      await assertFails(c.ref(p).get());await assertFails(c.ref(`${p}/forged`).set({value:true}));
    }
  });
  it('all projection and server-index roots reject forged client writes',async()=>{
    const c=client(ids.leader);
    for(const p of ['publicUserProfiles','publicBandProfiles','bandMemberEvents','bandManagerEvents','bandMemberCalendarEvents',
      'userEventReadModels','userBandMembershipIndex','subRequestAudience','eventReadProjectionIndex'])
      await assertFails(c.ref(`${p}/forged`).set({value:true}));
  });
  it('a noncreator Admin has exact-band aggregate access and loses it on demotion',async()=>{
    await call('leader','mutateBandMembership',{action:'role',bandId:band,operationId:'promote',userId:ids.member,role:'Admin'});
    const manager=client(ids.member);
    await assertSucceeds(manager.ref(`SubRequests/${request}/Responses`).get());
    await assertSucceeds(manager.ref(`bandManagerEvents/${band}/event`).get());
    await assertFails(manager.ref('bandManagerEvents/another_band/event').get());
    await call('leader','mutateBandMembership',{action:'role',bandId:band,operationId:'demote',userId:ids.member,role:'Member'});
    await assertFails(manager.ref(`SubRequests/${request}/Responses`).get());
    await assertFails(manager.ref(`bandManagerEvents/${band}/event`).get());
  });
  it('Calendar creation uses canonical callable and existing member projection, never BandEvents',async()=>{
    await call('leader','mutateBandEvent',{action:'saveCalendar',bandId:band,eventId:'calendar',event:{Title:'Calendar rehearsal',Date:'2027-12-01'}});
    await waitFor(`bandMemberCalendarEvents/${band}/calendar`,v=>v?.Title==='Calendar rehearsal');
    await assertSucceeds(client(ids.member).ref(`bandMemberCalendarEvents/${band}/calendar`).get());
    await assertFails(client(ids.outsider).ref(`bandMemberCalendarEvents/${band}/calendar`).get());
    await assertFails(client(ids.member).ref(`Bands/${band}/Calendar/calendar`).get());
    assert.equal((await db.ref(`BandEvents/${band}/calendar`).get()).exists(),false);
    await assert.rejects(call('member','mutateBandEvent',{action:'saveCalendar',bandId:band,eventId:'forged',event:{Title:'Forbidden'}}),e=>e.code==='functions/permission-denied');
  });
  it('Session RSVP comments are creator-and-own only, never included in discovery',async()=>{
    const session=`session_${tag}`;
    const owner=client(ids.leader),member=client(ids.member),other=client(ids.outsider);
    const source={CreatorId:ids.leader,Title:'Public session',Description:'Public description',SessionType:'Remote',Status:'active'};
    await assertFails(owner.ref(`Collabs/Sessions/${session}`).set({...source,Responses:{private:{comment:'secret'}}}));
    await assertSucceeds(owner.ref(`Collabs/Sessions/${session}`).set(source));
    await assertSucceeds(member.ref(`Collabs/Applications/${session}/${ids.member}`).set({CreatorId:ids.leader,Status:'pending'}));
    await call('leader','updateSessionApplicationStatus',{sessionId:session,applicantId:ids.member,status:'accepted'});
    const response={status:'UNCERTAIN',timestamp:'2027-01-01T12:00:00Z',comment:'Private comment',uncertainReason:'Private reason'};
    await assertSucceeds(member.ref(`Collabs/SessionResponses/${session}/${ids.member}`).set(response));
    await assertSucceeds(member.ref(`Collabs/SessionResponses/${session}/${ids.member}`).get());
    await assertSucceeds(owner.ref(`Collabs/SessionResponses/${session}`).get());
    for(const p of [`Collabs/SessionResponses/${session}`,`Collabs/SessionResponses/${session}/${ids.member}`])
      await assertFails(other.ref(p).get());
    await assertFails(member.ref(`Collabs/SessionResponses/${session}`).get());
    await assertFails(member.ref(`Collabs/SessionResponses/${session}/${ids.outsider}`).set(response));
    const listed=(await other.ref(`Collabs/Sessions/${session}`).get()).val();
    assert.deepEqual(listed,source);
    await assertSucceeds(other.ref(`Collabs/Applications/${session}/${ids.outsider}`).set({CreatorId:ids.leader,Status:'pending'}));
    await call('leader','updateSessionApplicationStatus',{sessionId:session,applicantId:ids.outsider,status:'accepted'});
    await assertFails(other.ref(`Collabs/SessionResponses/${session}/${ids.member}`).get());
    await assertSucceeds(owner.ref(`Collabs/Applications/${session}`).get());
    await assertFails(member.ref(`Collabs/Applications/${session}`).get());
    await assertFails(other.ref(`Collabs/Applications/${session}`).get());
  });

  it('current Leader reads manager data; role loss denies member/manager projections but preserves exact creator request access',async()=>{
    const c=client(ids.leader);
    const section=await call('leader','createBandSectionConversation',{
      bandId:band,groupName:'Private section',participantIds:[ids.member],
    });
    await assertSucceeds(c.ref(`SubRequests/${request}/Responses`).get());
    await assertSucceeds(c.ref(`bandManagerEvents/${band}/event`).get());
    await db.ref(`Bands/${band}/Members_band/${ids.leader}/Status`).set('inactive');
    await assertFails(c.ref(`bandManagerEvents/${band}/event`).get());
    // Exact creator access is explicitly retained for their own request.
    await assertSucceeds(c.ref(`SubRequests/${request}/Responses`).get());
    await assertFails(c.ref(`bandMemberEvents/${band}/event`).get());
    await assertFails(c.ref(`conversations/${section.conversationId}`).get());
    await waitFor(`userConversations/${ids.leader}/${section.conversationId}`,value=>value==null);
  });
 });
}
