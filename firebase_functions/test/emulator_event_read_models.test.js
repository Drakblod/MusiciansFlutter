'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=
  require('@firebase/rules-unit-testing');
const {reconcile}=require('../event_read_models');
const {mutate}=require('../event_mutations');
const {run}=require('../scripts/backfill_event_read_models');

for(const ruleFile of ['database.rules.json','database.transitional.rules.json'])
describe(`SANITIZED-EVENT-READ-MODEL-01 real rules and trigger: ${ruleFile}`,function(){
  this.timeout(180000);
  const projectId='demo-musicians-test';
  const suffix=ruleFile.includes('transitional')?'trans':'final';
  const bandId=`event_read_${suffix}`;
  const eventId='concert';
  const eventPath=`Bands/${bandId}/Events/${eventId}`;
  let env,app,db;
  const client=uid=>env.authenticatedContext(uid).database();
  async function waitFor(ref,predicate){
    for(let i=0;i<240;i++){
      const value=(await db.ref(ref).get()).val();
      if(predicate(value))return value;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw new Error('Event projection trigger did not converge');
  }
  before(async()=>{
    app=admin.initializeApp({projectId,databaseURL:`http://127.0.0.1:9000?ns=${projectId}`},
      `event_read_${suffix}`);
    db=app.database();
    env=await initializeTestEnvironment({projectId,database:{host:'127.0.0.1',port:9000,
      rules:fs.readFileSync(path.join(__dirname,'../..',ruleFile),'utf8')}});
    await db.ref(`Bands/${bandId}`).set({Name:'Private Band',Members_band:{
      [`leader_${suffix}`]:{Role:'Leader',Status:'active'},
      [`admin_${suffix}`]:{Role:'Admin',Status:'active'},
      [`member_${suffix}`]:{Role:'Member',Status:'on_hold'},
      [`off_${suffix}`]:{Role:'Member',Status:'temporarily_off'},
      [`former_${suffix}`]:{Role:'Leader',Status:'inactive'},
    },Events:{[eventId]:{title:'Private Concert',startDateTime:'2027-01-01T19:00:00Z',
      description:'Participant instructions',createdBy:`former_${suffix}`,
      Responses:{[`member_${suffix}`]:{status:'YES',timestamp:'2026-11-01T00:00:00Z',
        comment:'Private RSVP comment'}},
      externalInvitees:{[`invite_${suffix}`]:{source:'manual',status:'pending'},
        [`ambiguous_${suffix}`]:{status:'attending'},
        [`applicant_${suffix}`]:{source:'subRequest',status:'pending',
          subRequestId:`pending_${suffix}`,comment:'Private application'}},
      substituteAssignments:{slot:{subRequestId:`assigned_${suffix}`,
        assignedUserId:`sub_${suffix}`,assignedUserName:'Confirmed substitute',status:'assigned'}}}}});
    await db.ref(`SubRequests/assigned_${suffix}`).set({BandId:bandId,EventId:eventId,
      AssignedUserId:`sub_${suffix}`,Status:'assigned'});
    await reconcile(db,bandId,eventId);
  });
  after(async()=>{await env?.cleanup();await app?.delete();});

  it('separates active members, managers, targets and unrelated users',async()=>{
    const member=client(`member_${suffix}`),off=client(`off_${suffix}`),
      leader=client(`leader_${suffix}`),adminClient=client(`admin_${suffix}`),
      former=client(`former_${suffix}`),other=client(`other_${suffix}`),
      invite=client(`invite_${suffix}`),applicant=client(`applicant_${suffix}`),
      anonymous=env.unauthenticatedContext().database();
    for(const who of [member,off,leader,adminClient])
      await assertSucceeds(who.ref(`bandMemberEvents/${bandId}/${eventId}`).get());
    for(const who of [former,other,invite,applicant,anonymous])
      await assertFails(who.ref(`bandMemberEvents/${bandId}/${eventId}`).get());
    for(const who of [leader,adminClient])
      await assertSucceeds(who.ref(`bandManagerEvents/${bandId}/${eventId}`).get());
    for(const who of [member,former,other,invite,anonymous])
      await assertFails(who.ref(`bandManagerEvents/${bandId}/${eventId}`).get());
    await assertSucceeds(invite.ref(`userEventReadModels/invite_${suffix}/${bandId}/${eventId}`).get());
    await assertFails(other.ref(`userEventReadModels/invite_${suffix}/${bandId}/${eventId}`).get());
    await assertFails(applicant.ref(`userEventReadModels/applicant_${suffix}/${bandId}/${eventId}`).get());
    const projected=(await member.ref(`bandMemberEvents/${bandId}/${eventId}`).get()).val();
    assert.equal(projected.title,'Private Concert');
    assert.equal(projected.confirmedParticipants[0].userId,`sub_${suffix}`);
    for(const field of ['Responses','ScheduleResponses','externalInvitees','excludedMemberIds'])
      assert.equal(Object.hasOwn(projected,field),false,field);
    assert(!JSON.stringify(projected).includes('Private RSVP comment'));
    assert(!JSON.stringify(projected).includes('Private application'));
    const own=(await member.ref(`userEventReadModels/member_${suffix}/${bandId}/${eventId}`).get()).val();
    assert.equal(own.Responses[`member_${suffix}`].comment,'Private RSVP comment');
  });

  it('denies all projection client writes and permits only own RSVP leaf',async()=>{
    for(const who of [client(`member_${suffix}`),client(`leader_${suffix}`),
      client(`other_${suffix}`),env.unauthenticatedContext().database()]){
      for(const root of ['bandMemberEvents','bandManagerEvents','bandMemberCalendarEvents']){
        await assertFails(who.ref(`${root}/${bandId}/forged`).set({title:'forged'}));
        await assertFails(who.ref(`${root}/${bandId}/${eventId}`).update({title:'forged'}));
        await assertFails(who.ref(`${root}/${bandId}/${eventId}`).remove());
      }
      await assertFails(who.ref(`userEventReadModels/member_${suffix}/${bandId}/${eventId}`).set({forged:true}));
      await assertFails(who.ref(`eventReadProjectionIndex/${bandId}/${eventId}`).set({forged:true}));
    }
    const member=client(`member_${suffix}`);
    await assertSucceeds(member.ref(`${eventPath}/Responses/member_${suffix}`).set({
      status:'NO',timestamp:'2026-11-02T00:00:00Z'}));
    await assertFails(member.ref(`${eventPath}/Responses/leader_${suffix}`).set({
      status:'NO',timestamp:'2026-11-02T00:00:00Z'}));
    await assertFails(member.ref(eventPath).update({title:'forged'}));
    await waitFor(`userEventReadModels/member_${suffix}/${bandId}/${eventId}`,
      value=>value?.Responses?.[`member_${suffix}`]?.status==='NO');
  });

  it('denies canonical Event descendants after the clean-schema ancestor cutover',async()=>{
    const unrelated=client(`other_${suffix}`);
    await assertFails(unrelated.ref(eventPath).get());
    await assertFails(unrelated.ref(`${eventPath}/Responses/member_${suffix}`).get());
    await assertFails(unrelated.ref(`${eventPath}/externalInvitees/applicant_${suffix}`).get());
    await assertFails(env.unauthenticatedContext().database().ref(eventPath).get());
  });

  it('manager mutation and targeted invitation response work through server authority',async()=>{
    await assert.rejects(mutate(db,`member_${suffix}`,{action:'save',bandId,eventId,
      event:{title:'Forged'}}),error=>error.code==='permission-denied');
    await assert.rejects(mutate(db,`former_${suffix}`,{action:'lock',bandId,eventId}),
      error=>error.code==='permission-denied');
    await mutate(db,`leader_${suffix}`,{action:'save',bandId,eventId,
      event:{title:'Manager Updated Concert'}});
    await waitFor(`bandMemberEvents/${bandId}/${eventId}`,
      value=>value?.title==='Manager Updated Concert');
    await mutate(db,`admin_${suffix}`,{action:'addInvitees',bandId,eventId,
      userIds:[`new_invite_${suffix}`]});
    await mutate(db,`invite_${suffix}`,{action:'inviteResponse',bandId,eventId,
      status:'attending',comment:'I can attend'});
    const own=await waitFor(`userEventReadModels/invite_${suffix}/${bandId}/${eventId}`,
      value=>value?.externalInvitees?.[`invite_${suffix}`]?.status==='attending');
    assert.equal(own.externalInvitees[`invite_${suffix}`].comment,'I can attend');
    await assert.rejects(mutate(db,`applicant_${suffix}`,{action:'inviteResponse',bandId,eventId,
      status:'attending'}),error=>error.code==='permission-denied');
    await mutate(db,`leader_${suffix}`,{action:'lock',bandId,eventId});
    await assertFails(client(`member_${suffix}`).ref(`${eventPath}/Responses/member_${suffix}`)
      .set({status:'YES',timestamp:'2026-11-03T00:00:00Z'}));
    await mutate(db,`leader_${suffix}`,{action:'unlock',bandId,eventId});
  });

  it('canonical membership loss revokes the exact own Event projection',async()=>{
    await db.ref(`Bands/${bandId}/Members_band/member_${suffix}/Status`).set('inactive');
    await waitFor(`userEventReadModels/member_${suffix}/${bandId}/${eventId}`,
      value=>value===null);
    await assertFails(client(`member_${suffix}`).ref(`bandMemberEvents/${bandId}/${eventId}`).get());
    await db.ref(`Bands/${bandId}/Members_band/member_${suffix}/Status`).set('on_hold');
    await waitFor(`userEventReadModels/member_${suffix}/${bandId}/${eventId}`,
      value=>value?.Responses?.[`member_${suffix}`]?.status==='NO');
    await assertSucceeds(client(`member_${suffix}`).ref(`bandMemberEvents/${bandId}/${eventId}`).get());
  });

  it('refreshes source updates, fails closed on malformed data, and deletes stale projections',async()=>{
    await db.ref(`${eventPath}/title`).set('Updated Concert');
    await waitFor(`bandMemberEvents/${bandId}/${eventId}`,
      value=>value?.title==='Updated Concert');
    await db.ref(eventPath).set({title:'Missing time',externalInvitees:{private:true}});
    await waitFor(`bandMemberEvents/${bandId}/${eventId}`,value=>value===null);
    await db.ref(eventPath).remove();
    await waitFor(`bandManagerEvents/${bandId}/${eventId}`,value=>value===null);
    assert.equal((await db.ref(`userEventReadModels/invite_${suffix}/${bandId}/${eventId}`).get()).val(),null);
  });
});

describe('SANITIZED-EVENT-READ-MODEL-01 backfill on isolated local Database Emulator',function(){
  this.timeout(60000);
  let app,db;
  before(async()=>{
    const projectId='demo-event-read-backfill';
    app=admin.initializeApp({projectId,
      databaseURL:`http://127.0.0.1:9000?ns=${projectId}`},'event_read_backfill');
    db=app.database();
    await db.ref('Bands/backfill_band').set({Name:'Backfill band',
      Members_band:{backfill_member:{Role:'Member',Status:'active'}},
      Events:{backfill_event:{title:'Backfill Concert',
        startDateTime:'2027-02-01T19:00:00Z',
        Responses:{backfill_member:{status:'YES',comment:'Private comment'}}}}});
    await db.ref('bandMemberEvents/backfill_band/stale').set({title:'Stale'});
  });
  after(async()=>{await app?.delete();});
  it('dry-run does zero writes; apply projects safely; second apply is unchanged',async()=>{
    const canonicalBefore=(await db.ref('Bands/backfill_band/Events').get()).val();
    const dry=await run(db,{apply:false});
    assert.equal(dry.writes,0);
    assert.equal((await db.ref('bandMemberEvents/backfill_band/backfill_event').get()).val(),null);
    assert(dry.proposedWrites>0);
    assert(dry.proposedDeletions>0);
    const applied=await run(db,{apply:true});
    assert(applied.writes>0);
    assert.equal((await db.ref('bandMemberEvents/backfill_band/stale').get()).val(),null);
    const member=(await db.ref('bandMemberEvents/backfill_band/backfill_event').get()).val();
    assert.equal(member.title,'Backfill Concert');
    assert(!JSON.stringify(member).includes('Private comment'));
    assert.deepEqual((await db.ref('Bands/backfill_band/Events').get()).val(),canonicalBefore);
    const second=await run(db,{apply:true});
    assert.equal(second.writes,0);
    assert(!JSON.stringify(second).includes('backfill_member'));
    assert(!JSON.stringify(second).includes('Private comment'));
  });
});
