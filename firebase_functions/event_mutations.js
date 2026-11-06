'use strict';
const {HttpsError}=require('firebase-functions/v2/https');
const {key,manualInvite}=require('./event_read_models');
const {requireManager}=require('./membership_authority');
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const text=(value,max=4000)=>typeof value==='string'&&value.trim().length>0&&
  value.trim().length<=max?value.trim():undefined;
const boundedInt=value=>Number.isSafeInteger(value)&&value>=0?value:undefined;
function fields(input,previous={}) {
  if(!record(input)||JSON.stringify(input).length>65536)
    throw new HttpsError('invalid-argument','Invalid Event data.');
  const out={};
  for(const field of ['title','description','eventType','location','startDateTime',
    'endDateTime','additionalNotes','parentEventId','city','placeId','locationPrecision',
    'locationStatus']){
    if(!Object.hasOwn(input,field))continue;
    const value=text(input[field],field==='title'?200:4000);
    if(value)out[field]=value;
    else if(input[field]===null||input[field]==='')out[field]=null;
    else throw new HttpsError('invalid-argument',`Invalid ${field}.`);
  }
  if(!text(out.title??previous.title,200)||!text(out.startDateTime??previous.startDateTime,100))
    throw new HttpsError('invalid-argument','Event title and start time are required.');
  for(const field of ['requireResponse'])if(Object.hasOwn(input,field)){
    if(typeof input[field]!=='boolean')throw new HttpsError('invalid-argument',`Invalid ${field}.`);
    out[field]=input[field];
  }
  for(const field of ['rsvpDeadline','reminderIntervalHours','subEventSequence'])
    if(Object.hasOwn(input,field)){
      if(input[field]===null){out[field]=null;continue;}
      const value=boundedInt(input[field]);
      if(value===undefined)throw new HttpsError('invalid-argument',`Invalid ${field}.`);
      out[field]=value;
    }
  for(const field of ['latitude','longitude'])if(Object.hasOwn(input,field)){
    const value=input[field];
    if(value===null){out[field]=null;continue;}
    if(typeof value!=='number'||!Number.isFinite(value)||
      Math.abs(value)>(field==='latitude'?90:180))
      throw new HttpsError('invalid-argument',`Invalid ${field}.`);
    out[field]=value;
  }
  if(Object.hasOwn(input,'rehearsals')){
    if(!Array.isArray(input.rehearsals)||input.rehearsals.length>100)
      throw new HttpsError('invalid-argument','Invalid Event schedule.');
    out.rehearsals=input.rehearsals.map((part,index)=>{
      if(!record(part))throw new HttpsError('invalid-argument','Invalid Event schedule item.');
      const safe={id:key(part.id)?part.id:String(index)};
      for(const field of ['title','date','startTime','endTime','location','description',
        'type','city','placeId','locationPrecision','locationStatus']){
        const value=text(part[field],4000);if(value)safe[field]=value;
      }
      for(const field of ['latitude','longitude'])if(typeof part[field]==='number'&&
        Number.isFinite(part[field])&&Math.abs(part[field])<=(field==='latitude'?90:180))
        safe[field]=part[field];
      return safe;
    });
  }
  if(Object.hasOwn(input,'excludedMemberIds')){
    if(!Array.isArray(input.excludedMemberIds)||input.excludedMemberIds.length>500||
      !input.excludedMemberIds.every(key))
      throw new HttpsError('invalid-argument','Invalid excluded member list.');
    out.excludedMemberIds=[...new Set(input.excludedMemberIds)];
  }
  if(Object.hasOwn(input,'externalInvitees')){
    if(!record(input.externalInvitees)||Object.keys(input.externalInvitees).length>100)
      throw new HttpsError('invalid-argument','Invalid invitation list.');
    const preserved=record(previous.externalInvitees)?previous.externalInvitees:{};
    const next={};
    for(const [uid,invite] of Object.entries(preserved))
      if(key(uid)&&!manualInvite(invite))next[uid]=invite;
    for(const [uid,invite] of Object.entries(input.externalInvitees)){
      if(!key(uid)||!record(invite))throw new HttpsError('invalid-argument','Invalid invitation.');
      if(invite.source!=null&&!['manual','direct'].includes(String(invite.source).toLowerCase()))continue;
      const old=preserved[uid];
      if(manualInvite(old)){next[uid]=old;continue;}
      next[uid]={userId:uid,status:'pending',source:'manual',
        invitedAt:Date.now(),...(text(invite.displayName,200)?{displayName:text(invite.displayName,200)}:{}),
        ...(text(invite.instrument,200)?{instrument:text(invite.instrument,200)}:{})};
    }
    out.externalInvitees=next;
  }
  return out;
}

async function mutate(db,uid,data) {
  if(!key(uid)||!record(data)||JSON.stringify(data).length>70000)
    throw new HttpsError('invalid-argument','Invalid Event mutation.');
  const {action,bandId,eventId}=data;
  if(!key(bandId)||!key(eventId))throw new HttpsError('invalid-argument','Invalid Event identity.');
  const ref=db.ref(`Bands/${bandId}/Events/${eventId}`);
  if(action==='inviteResponse'){
    if((await ref.child('isLocked').get()).val()===true)
      throw new HttpsError('failed-precondition','Event responses are locked.');
    const prior=(await ref.child(`externalInvitees/${uid}`).get()).val();
    if(!manualInvite(prior))throw new HttpsError('permission-denied','Invitation unavailable.');
    const status=text(data.status,20)?.toLowerCase();
    if(!['attending','maybe','declined'].includes(status))
      throw new HttpsError('invalid-argument','Invalid invitation response.');
    const comment=data.comment==null?null:text(data.comment,1000);
    if(data.comment!=null&&!comment)throw new HttpsError('invalid-argument','Invalid comment.');
    const update={status,comment};
    await ref.child(`externalInvitees/${uid}`).update(update);
    return {success:true,eventId};
  }
  await requireManager(db,bandId,uid);
  if(action==='delete'){
    await ref.remove();return {success:true,eventId};
  }
  const prior=(await ref.get()).val();
  if(action==='save'){
    const safe=fields(data.event,prior||{});
    if(prior==null){
      await ref.set({...safe,createdBy:uid,createdAt:Date.now(),updatedAt:Date.now()});
    }else{
      await ref.update({...safe,updatedAt:Date.now()});
    }
    return {success:true,eventId};
  }
  if(!record(prior))throw new HttpsError('not-found','Event unavailable.');
  if(action==='lock'||action==='unlock'){
    const locked=action==='lock';
    await ref.update({isLocked:locked,lockedAt:locked?Date.now():null,
      lockedBy:locked?uid:null,updatedAt:Date.now()});
  }else if(action==='setRoom'){
    if(!key(data.roomId))throw new HttpsError('invalid-argument','Invalid Event room.');
    await ref.update({temporaryRoomId:data.roomId,updatedAt:Date.now()});
  }else if(action==='addInvitees'){
    if(!Array.isArray(data.userIds)||data.userIds.length>100||!data.userIds.every(key))
      throw new HttpsError('invalid-argument','Invalid invitation targets.');
    const updates={};
    for(const target of new Set(data.userIds)){
      if(prior.externalInvitees?.[target])continue;
      updates[`externalInvitees/${target}`]={userId:target,status:'pending',source:'manual',invitedAt:Date.now()};
    }
    updates.updatedAt=Date.now();await ref.update(updates);
  }else throw new HttpsError('invalid-argument','Unknown Event mutation.');
  return {success:true,eventId};
}
module.exports={mutate,fields};
