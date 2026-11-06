'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert=require('node:assert/strict');
const {project,memberEvent,verifiedAssignments,manualInvite,equal}=require('../event_read_models');

describe('SANITIZED-EVENT-READ-MODEL-01 explicit projection policy',()=>{
  it('pins deployable Event functions to europe-west1 outside the Functions emulator',()=>{
    const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
    const declaration=source.match(/const databaseTriggerRegion = ([\s\S]*?);/);
    assert(declaration,'missing Database trigger region declaration');
    const region=env=>vm.runInNewContext(`${declaration[0]} databaseTriggerRegion;`,
      {process:{env}});
    assert.equal(region({}),'europe-west1');
    assert.equal(region({FIREBASE_DATABASE_EMULATOR_HOST:'127.0.0.1:9000',
      FIREBASE_EMULATOR_HUB:'127.0.0.1:4400'}),'europe-west1');
    assert.equal(region({FUNCTIONS_EMULATOR:'true'}),'us-central1');
    assert.match(source,/exports\.mutateBandEvent = onCall\(\{region:'europe-west1'\}/);
    for(const name of ['onBandEventReadModelWritten','onLegacyBandCalendarEventWritten']){
      assert.equal(source.split(`exports.${name} =`).length-1,1,`duplicate ${name} export`);
      assert.match(source,new RegExp(`exports\\.${name} = onValueWritten\\(\\{[\\s\\S]*?region:databaseTriggerRegion`));
    }
  });
  const band='band_one',id='event_one';
  const members={leader:{Role:'Leader',Status:'active'},member:{Role:'Member',Status:'on_hold'},
    removed:{Role:'Member',Status:'removed'},sub:{Role:'Member',Status:'active'}};
  const source={title:'Concert',eventType:'Concert',description:'For participants',
    location:'Venue for participants',startDateTime:'2026-12-01T18:00:00Z',
    endDateTime:'2026-12-01T20:00:00Z',requireResponse:true,parentEventId:'parent',
    subEventSequence:2,rehearsals:[{id:'part_1',date:'2026-12-01',startTime:'18:00',
      location:'Participant venue',address:'private address',contact:'private contact'}],
    Responses:{member:{status:'YES',timestamp:'2026-11-01T00:00:00Z',comment:'private RSVP'},
      removed:{status:'NO',comment:'former member'}},
    ScheduleResponses:{part_1:{member:{status:'UNCERTAIN',comment:'private part comment'}}},
    externalInvitees:{manual:{status:'pending',source:'manual',displayName:'Manual Guest',comment:'private invitation'},
      guest:{status:'attending',displayName:'Confirmed Guest',source:'manual'},
      applicant:{status:'pending',source:'subRequest',subRequestId:'request_pending',comment:'private applicant'},
      sub:{status:'attending',source:'subRequest',subRequestId:'request_assigned'},
      revoked:{status:'attending',source:'subRequest',subRequestId:'request_revoked'},
      malformed:{email:'private@example.test'}},
    substituteAssignments:{slot:{slotId:'slot',subRequestId:'request_assigned',assignedUserId:'sub',
      assignedUserName:'Assigned Substitute',instrument:'Guitar',status:'assigned',payment:500},
      revokedSlot:{subRequestId:'request_revoked',assignedUserId:'revoked',status:'revoked'}},
    excludedMemberIds:['member'],notificationTokens:{secret:true},payAmount:500,
    internalMutationReceipt:'secret',contact:'private@example.test'};
  const requests={request_assigned:{Status:'assigned',AssignedUserId:'sub',BandId:band,EventId:id},
    request_revoked:{Status:'published',AssignedUserId:null,BandId:band,EventId:id}};

  it('retains participant fields and exact multi-part identity, omitting private descendants',()=>{
    const result=project(band,id,'Band One',source,members,requests);
    assert.equal(result.member.eventId,id);
    assert.equal(result.member.parentEventId,'parent');
    assert.equal(result.member.subEventSequence,2);
    assert.equal(result.member.rehearsals[0].id,'part_1');
    const serialized=JSON.stringify(result.member);
    for(const value of ['private RSVP','private applicant','private address','private contact',
      'private@example.test','notificationTokens','payAmount','internalMutationReceipt',
      'request_pending','request_revoked'])assert(!serialized.includes(value),value);
    assert(!('Responses' in result.member));
    assert(!('ScheduleResponses' in result.member));
    assert(!('externalInvitees' in result.member));
    assert(!('excludedMemberIds' in result.member));
  });

  it('puts only each user own RSVP, schedule response, exclusion and invitation in its target',()=>{
    const {users}=project(band,id,'Band One',source,members,requests);
    assert.equal(users.member.Responses.member.comment,'private RSVP');
    assert.equal(users.member.ScheduleResponses.part_1.member.comment,'private part comment');
    assert.deepEqual(users.member.excludedMemberIds,['member']);
    assert(!JSON.stringify(users.manual).includes('private RSVP'));
    assert.equal(users.manual.externalInvitees.manual.status,'pending');
    assert(!('removed' in users));
    assert(!('applicant' in users));
    assert(!('revoked' in users));
    assert(!('malformed' in users));
  });

  it('requires exact assigned SubRequest authority for confirmed substitutes',()=>{
    const {member,manager}=project(band,id,'Band One',source,members,requests);
    assert.deepEqual(member.confirmedParticipants.map(x=>x.userId).sort(),['guest','sub']);
    assert.equal(member.substituteAssignments.slot.assignedUserId,'sub');
    assert.equal(manager.substituteAssignments.slot.subRequestId,'request_assigned');
    assert(!JSON.stringify(member).includes('payment'));
    assert(!JSON.stringify(manager).includes('payment'));
    assert.equal(verifiedAssignments(source,{request_assigned:{...requests.request_assigned,
      AssignedUserId:'other'}},band,id).length,0);
  });

  it('does not infer confirmation from an externalInvitee alone',()=>{
    const event={...source,substituteAssignments:{}};
    const result=project(band,id,'Band One',event,members,{});
    assert(!result.member.confirmedParticipants.some(x=>x.userId==='sub'));
    assert(!result.users.sub?.externalInvitees);
  });

  it('fails closed on malformed event and unknown invite sources',()=>{
    assert.equal(memberEvent(band,id,'Band One','malformed'),null);
    assert.equal(manualInvite({status:'attending',source:'unknown'}),false);
    assert.equal(manualInvite({status:'attending'}),false);
    assert.deepEqual(project(band,id,'Band One','malformed',members,{}),
      {member:null,manager:null,users:{}});
  });

  it('is deterministic and omits stale projected fields',()=>{
    const first=project(band,id,'Band One',source,members,requests);
    const second=project(band,id,'Band One',source,members,requests);
    assert(equal(first,second));
    const updated=project(band,id,'Band One',{...source,Responses:{},contact:'private'},members,requests);
    assert(!('Responses' in updated.manager));
    assert(!('Responses' in (updated.users.member||{})));
  });
});
