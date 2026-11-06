'use strict';

// Server-owned Event read models. Every property below is an explicit public,
// participant, or manager choice; canonical Event objects are never copied.
const {validMember} = require('./band_membership_index');
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const key = value => typeof value === 'string' && value.length > 0 && value.length <= 128 &&
  !/[.#$\[\]/\u0000-\u001f\u007f]/.test(value) && !['__proto__','constructor','prototype'].includes(value);
const string = (value, max=4000) => typeof value === 'string' && value.trim() &&
  value.trim().length <= max ? value.trim() : undefined;
const integer = value => Number.isSafeInteger(value) && value >= 0 ? value : undefined;
const selected = (source, fields, max=4000) => {
  const out={};
  for(const field of fields){const value=string(source?.[field],max);if(value!==undefined)out[field]=value;}
  return out;
};
const stable = value => Array.isArray(value) ? value.map(stable) : record(value) ?
  Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])])) : value;
const equal = (a,b) => JSON.stringify(stable(a??null))===JSON.stringify(stable(b??null));

function parts(source) {
  const raw=source?.rehearsals ?? source?.Rehearsals;
  const entries=Array.isArray(raw) ? raw.map((value,index)=>[String(index),value]) :
    record(raw) ? Object.entries(raw).sort(([a],[b])=>a.localeCompare(b)) : [];
  return entries.slice(0,100).flatMap(([id,value])=>{
    if(!record(value))return [];
    const item={id:string(value.id,128)||id,
      ...selected(value,['title','date','startTime','endTime','location','description','type'])};
    return [item];
  });
}

function memberEvent(bandId,eventId,bandName,source,confirmed=[]) {
  if(!key(bandId)||!key(eventId)||!record(source))return null;
  if(!string(source.title,200)||!string(source.startDateTime,100))return null;
  const out={bandId,eventId};
  const name=string(bandName,200);if(name)out.bandName=name;
  Object.assign(out,selected(source,['title','description','eventType','location',
    'startDateTime','endDateTime','additionalNotes','createdBy','parentEventId'],4000));
  for(const field of ['createdAt','updatedAt','rsvpDeadline','subEventSequence']) {
    const value=integer(source[field]);if(value!==undefined)out[field]=value;
  }
  for(const field of ['requireResponse','isLocked'])if(typeof source[field]==='boolean')out[field]=source[field];
  const room=string(source.temporaryRoomId,128);if(room)out.temporaryRoomId=room;
  const schedule=parts(source);if(schedule.length)out.rehearsals=schedule;
  if(confirmed.length)out.confirmedParticipants=confirmed;
  return out;
}

function response(value) {
  if(!record(value))return null;
  const status=string(value.status,32);if(!status)return null;
  const out={status};
  Object.assign(out,selected(value,['timestamp','comment','uncertainReason']));
  return out;
}

function responseMap(source) {
  if(!record(source))return {};
  return Object.fromEntries(Object.entries(source).filter(([uid])=>key(uid))
    .map(([uid,value])=>[uid,response(value)]).filter(([,value])=>value));
}

function scheduleResponseMap(source) {
  if(!record(source))return {};
  const out={};
  for(const [partId,users] of Object.entries(source))if(key(partId)){
    const rows=responseMap(users);if(Object.keys(rows).length)out[partId]=rows;
  }
  return out;
}

function excludedIds(source) {
  const value=source?.excludedMemberIds??source?.ExcludedMemberIds;
  if(Array.isArray(value))return value.filter(key).slice(0,500);
  if(record(value))return Object.entries(value).filter(([id,flag])=>key(id)&&
    (flag===true||flag===1||flag==='true')).map(([id])=>id).slice(0,500);
  return [];
}

function manualInvite(value) {
  if(!record(value))return false;
  const source=value.source;
  if(!['manual','direct'].includes(String(source||'').trim().toLowerCase()))return false;
  return ['pending','attending','maybe','declined'].includes(String(value.status||'').trim().toLowerCase());
}

function invite(value,uid) {
  if(!record(value)||!key(uid))return null;
  const status=string(value.status,32);if(!status)return null;
  const out={userId:uid,status,
    ...selected(value,['instrument','source','subRequestId','displayName','comment'],200)};
  const at=integer(value.invitedAt);if(at!==undefined)out.invitedAt=at;
  return out;
}

function assignment(value,slotId) {
  if(!record(value)||!key(slotId)||!key(value.assignedUserId))return null;
  return {slotId,assignedUserId:value.assignedUserId,status:'assigned',
    ...selected(value,['assignedUserName','instrument','replacedMemberName'],200)};
}

function verifiedAssignments(source,requests={},bandId,eventId) {
  const raw=source?.substituteAssignments;
  if(!record(raw))return [];
  const result=[];
  for(const [slotId,value] of Object.entries(raw)){
    const requestId=value?.subRequestId;
    const request=requests[requestId];
    if(!key(requestId)||!record(request)||!['assigned','filled'].includes(String(value.status||'').toLowerCase())||
      !['assigned','filled'].includes(String(request.Status??request.status??'').toLowerCase())||
      request.AssignedUserId!==value.assignedUserId||
      (request.BandId??request.bandId)!==bandId||
      (request.EventId??request.eventId)!==eventId)continue;
    const safe=assignment(value,slotId);if(safe)result.push(safe);
  }
  return result.sort((a,b)=>a.slotId.localeCompare(b.slotId));
}

function project(bandId,eventId,bandName,event,members={},requests={}) {
  const assignments=verifiedAssignments(event,requests,bandId,eventId);
  const invitees=record(event?.externalInvitees)?event.externalInvitees:{};
  const confirmed=[...assignments.map(a=>({userId:a.assignedUserId,
    ...(a.assignedUserName?{displayName:a.assignedUserName}:{}),
    ...(a.instrument?{instrument:a.instrument}:{}),source:'assignedSubstitute'}))];
  for(const [uid,value] of Object.entries(invitees))if(key(uid)&&manualInvite(value)&&
    String(value.status).trim().toLowerCase()==='attending'){
    confirmed.push({userId:uid,...selected(value,['displayName','instrument'],200),source:'confirmedGuest'});
  }
  const base=memberEvent(bandId,eventId,bandName,event,confirmed);
  if(!base)return {member:null,manager:null,users:{}};
  if(assignments.length)base.substituteAssignments=Object.fromEntries(assignments.map(a=>[a.slotId,a]));
  const responses=responseMap(event.Responses??event.responses);
  const schedule=scheduleResponseMap(event.ScheduleResponses??event.scheduleResponses);
  const excluded=excludedIds(event);
  const manager={...base};
  for(const field of ['lockedAt','reminderIntervalHours']){
    const value=integer(event[field]);if(value!==undefined)manager[field]=value;
  }
  Object.assign(manager,selected(event,['lockedBy','city','placeId','locationPrecision'],200));
  for(const field of ['latitude','longitude'])if(typeof event[field]==='number'&&
      Number.isFinite(event[field]))manager[field]=event[field];
  if(Object.keys(responses).length)manager.Responses=responses;
  if(Object.keys(schedule).length)manager.ScheduleResponses=schedule;
  if(excluded.length)manager.excludedMemberIds=excluded;
  const safeInvitees={};
  for(const [uid,value] of Object.entries(invitees))if(key(uid)&&manualInvite(value)){
    const safe=invite(value,uid);if(safe)safeInvitees[uid]=safe;
  }
  if(Object.keys(safeInvitees).length)manager.externalInvitees=safeInvitees;
  if(assignments.length)manager.substituteAssignments=Object.fromEntries(assignments.map(a=>{
    const raw=event.substituteAssignments[a.slotId];
    const detail={...a,...selected(raw,['subRequestId','replacedMemberId','assignedBy'],128)};
    const at=integer(raw.assignedAt);if(at!==undefined)detail.assignedAt=at;
    return [a.slotId,detail];
  }));
  const users={};
  const candidates=new Set([...Object.keys(responses),...Object.keys(invitees),...excluded,
    ...assignments.map(a=>a.assignedUserId),...Object.values(schedule).flatMap(x=>Object.keys(x))]);
  if(candidates.size>500)throw new Error('Event audience exceeds bounded fan-out');
  for(const uid of candidates)if(key(uid)){
    const isMember=validMember(members[uid]);
    const isManual=manualInvite(invitees[uid]);
    const isAssigned=assignments.some(a=>a.assignedUserId===uid)&&isMember;
    if(!isMember&&!isManual&&!isAssigned)continue;
    const state={...base,accessKind:isMember?'member':'invitee'};
    if(!isMember){
      delete state.confirmedParticipants;
      delete state.substituteAssignments;
    }
    if(responses[uid])state.Responses={[uid]:responses[uid]};
    const ownSchedule=Object.fromEntries(Object.entries(schedule).filter(([,users])=>users[uid])
      .map(([partId,users])=>[partId,{[uid]:users[uid]}]));
    if(Object.keys(ownSchedule).length)state.ScheduleResponses=ownSchedule;
    if(isManual&&safeInvitees[uid])state.externalInvitees={[uid]:safeInvitees[uid]};
    if(excluded.includes(uid))state.excludedMemberIds=[uid];
    users[uid]=state;
  }
  return {member:base,manager,users};
}

async function requestsFor(db,event) {
  const raw=event?.substituteAssignments;
  const ids=record(raw)?[...new Set(Object.values(raw).map(x=>x?.subRequestId).filter(key))]:[];
  if(ids.length>500)throw new Error('Event assignments exceed bounded fan-out');
  const requests={};
  await Promise.all(ids.map(async id=>{requests[id]=(await db.ref(`SubRequests/${id}`).get()).val();}));
  return requests;
}

async function reconcile(db,bandId,eventId,extraPrior=[]) {
  if(!key(bandId)||!key(eventId))throw new Error('Invalid Event identity');
  const sourceRef=db.ref(`Bands/${bandId}/Events/${eventId}`);
  for(let attempt=0;attempt<5;attempt++){
    const [sourceSnap,nameSnap,membersSnap,indexSnap]=await Promise.all([
      sourceRef.get(),db.ref(`Bands/${bandId}/Name`).get(),
      db.ref(`Bands/${bandId}/Members_band`).get(),
      db.ref(`eventReadProjectionIndex/${bandId}/${eventId}`).get()]);
    const source=sourceSnap.val();
    const requests=await requestsFor(db,source);
    const next=project(bandId,eventId,nameSnap.val(),source,membersSnap.val()||{},requests);
    const prior=[...new Set([...(record(indexSnap.val())?Object.keys(indexSnap.val()):[]),...extraPrior])];
    if(prior.length>500)throw new Error('Prior Event audience exceeds bounded fan-out');
    const paths={
      [`bandMemberEvents/${bandId}/${eventId}`]:next.member,
      [`bandManagerEvents/${bandId}/${eventId}`]:next.manager,
      [`eventReadProjectionIndex/${bandId}/${eventId}`]:Object.keys(next.users).length?
        Object.fromEntries(Object.keys(next.users).map(uid=>[uid,true])):null,
    };
    for(const uid of new Set([...prior,...Object.keys(next.users)]))
      paths[`userEventReadModels/${uid}/${bandId}/${eventId}`]=next.users[uid]??null;
    const current=(await Promise.all(Object.keys(paths).map(p=>db.ref(p).get()))).map(s=>s.val());
    const updates={};let index=0;
    for(const [path,value] of Object.entries(paths))if(!equal(current[index++],value))updates[path]=value;
    if(!equal(source,(await sourceRef.get()).val()))continue;
    if(Object.keys(updates).length)await db.ref().update(updates);
    return {changed:Object.keys(updates).length,projectedUsers:Object.keys(next.users).length,
      malformed:source!=null&&!record(source)};
  }
  throw new Error('Event source changed repeatedly; retry reconciliation');
}

async function reconcileBand(db,bandId,uid) {
  if(!key(bandId))throw new Error('Invalid band identity');
  const [eventSnap,memberSnap,managerSnap,indexSnap]=await Promise.all([
    db.ref(`Bands/${bandId}/Events`).get(),db.ref(`bandMemberEvents/${bandId}`).get(),
    db.ref(`bandManagerEvents/${bandId}`).get(),db.ref(`eventReadProjectionIndex/${bandId}`).get()]);
  const events=eventSnap.val();
  if(events!=null&&!record(events))return {scanned:0};
  const ids=[...new Set([...Object.keys(events||{}),...Object.keys(memberSnap.val()||{}),
    ...Object.keys(managerSnap.val()||{}),...Object.keys(indexSnap.val()||{})])];
  if(ids.length>500)throw new Error('Band Event count exceeds bounded reconciliation');
  let scanned=0;
  for(const id of ids)if(key(id)){
    const event=events?.[id];
    if(uid && !event?.Responses?.[uid] && !event?.responses?.[uid] &&
      !event?.externalInvitees?.[uid] && !excludedIds(event).includes(uid) &&
      !Object.values(event?.ScheduleResponses||{}).some(users=>users?.[uid]) &&
      !indexSnap.val()?.[id]?.[uid])continue;
    await reconcile(db,bandId,id);scanned++;
  }
  if(!(await db.ref(`Bands/${bandId}/Name`).get()).exists())
    await db.ref(`bandMemberCalendarEvents/${bandId}`).remove();
  return {scanned};
}

function legacyCalendarEvent(bandId,eventId,source) {
  if(!key(bandId)||!key(eventId)||!record(source))return null;
  const title=string(source.Title,200);
  if(!title)return null;
  const out={BandId:bandId,eventId,Title:title,
    ...selected(source,['Description','Location','CreatorName','Date','StartTime','EndTime'],4000)};
  if(typeof source.IsFinalized==='boolean')out.IsFinalized=source.IsFinalized;
  if(Number.isInteger(source.Type)&&source.Type>=0&&source.Type<=3)out.Type=source.Type;
  else {const type=string(source.Type,40);if(type)out.Type=type;}
  if(Array.isArray(source.ProposedDates)){
    const dates=source.ProposedDates.filter(value=>typeof value==='string'&&
      value.length<=40&&Number.isFinite(Date.parse(value))).slice(0,50);
    if(dates.length)out.ProposedDates=dates;
  }
  return out;
}

async function reconcileLegacyCalendar(db,bandId,eventId) {
  if(!key(bandId)||!key(eventId))return {changed:false};
  const sourceRef=db.ref(`BandEvents/${bandId}/${eventId}`);
  for(let attempt=0;attempt<5;attempt++){
    const [source,band]=await Promise.all([sourceRef.get(),db.ref(`Bands/${bandId}/Name`).get()]);
    const next=band.exists()?legacyCalendarEvent(bandId,eventId,source.val()):null;
    const path=`bandMemberCalendarEvents/${bandId}/${eventId}`;
    const prior=(await db.ref(path).get()).val();
    if(!equal(source.val(),(await sourceRef.get()).val()))continue;
    if(equal(prior,next))return {changed:false};
    await db.ref(path).set(next);
    return {changed:true};
  }
  throw new Error('Legacy Calendar Event changed repeatedly');
}

module.exports={memberEvent,project,manualInvite,verifiedAssignments,reconcile,
  reconcileBand,legacyCalendarEvent,reconcileLegacyCalendar,requestsFor,equal,key};
