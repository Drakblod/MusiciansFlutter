'use strict';

const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');

const SESSION_TTL_MS = 10 * 60 * 1000;
const GRANT_TTL_MS = 5 * 60 * 1000;
const RATE_WINDOW_MS = 60 * 1000;
const MAX_SESSIONS_PER_USER = 20;
const MAX_GRANTS_PER_USER = 5;
const MAX_RATE_USERS = 1000;
const MAX_USER_REQUESTS = 10;
const MAX_GLOBAL_REQUESTS = 120;
const MAX_USER_CONCURRENT = 2;
const MAX_GLOBAL_CONCURRENT = 20;

const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const nonce = () => crypto.randomBytes(24).toString('hex');
function createToken(uid,secret,now=Date.now()) {
  if(!safeId(uid)||typeof secret!=='string'||!secret)
    throw new HttpsError('failed-precondition','City search unavailable.');
  const body=Buffer.alloc(30);
  body.writeUIntBE(now,0,6);
  crypto.createHash('sha256').update(uid).digest().copy(body,6,0,8);
  crypto.randomBytes(16).copy(body,14);
  const mac=crypto.createHmac('sha256',secret).update(body).digest().subarray(0,16);
  return Buffer.concat([body,mac]).toString('base64url');
}
function validateToken(token,uid,secret,now=Date.now()) {
  if(typeof token!=='string'||!/^[A-Za-z0-9_-]{62}$/.test(token)||
      typeof secret!=='string'||!secret)
    throw new HttpsError('invalid-argument','Invalid city session.');
  const bytes=Buffer.from(token,'base64url');
  if(bytes.length!==46||bytes.toString('base64url')!==token)
    throw new HttpsError('invalid-argument','Invalid city session.');
  const body=bytes.subarray(0,30),mac=bytes.subarray(30);
  const expected=crypto.createHmac('sha256',secret).update(body).digest().subarray(0,16);
  if(!crypto.timingSafeEqual(mac,expected))
    throw new HttpsError('invalid-argument','Invalid city session.');
  const owner=crypto.createHash('sha256').update(uid).digest().subarray(0,8);
  if(!crypto.timingSafeEqual(body.subarray(6,14),owner))
    throw new HttpsError('permission-denied','City session belongs to another user.');
  const createdAt=body.readUIntBE(0,6);
  if(createdAt>now+5000||createdAt+SESSION_TTL_MS<=now)
    throw new HttpsError('failed-precondition','City session expired.');
  return true;
}
const safeId = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 128 && !/[.#$[\]/\u0000-\u001f\u007f]/.test(value) &&
  !['__proto__','constructor','prototype'].includes(value);
const authoredPart = value => typeof value === 'string' && value.trim().length >= 2 &&
  value.trim().length <= 100 && !/[,\u0000-\u001f\u007f]/.test(value) ?
  value.trim().replace(/\s+/g,' ').normalize('NFC') : null;
function scope(purpose,targetId,uid) {
  if (!['profile','band'].includes(purpose) || !safeId(targetId) ||
      (purpose === 'profile' && targetId !== uid)) {
    throw new HttpsError('invalid-argument','Invalid city target.');
  }
  return {purpose,targetId};
}
function authored(city,country) {
  const c=authoredPart(city),nation=authoredPart(country);
  if (!c || !nation) throw new HttpsError('invalid-argument','Enter a city and country.');
  return {city:c,country:nation};
}
const same = (a,b) => a.toLocaleLowerCase('en') === b.toLocaleLowerCase('en');

// One bounded global transaction protects both provider callables. Leases are
// removed in finally and expire after the provider timeout if a worker dies.
async function reserveRate(db,uid,now=Date.now()) {
  if(!safeId(uid))throw new HttpsError('unauthenticated','Sign in first.');
  const ref=db.ref('citySearchRateState');
  const lease=nonce(),expiresAt=now+15000;
  let denial;
  const result=await ref.transaction(value=>{
    denial=null;
    value ||= {windowStart:now,globalCount:0,users:{},leases:{}};
    value.users ||= {};value.leases ||= {};
    for(const [id,row] of Object.entries(value.leases))if(row.expiresAt<=now)delete value.leases[id];
    for(const [id,row] of Object.entries(value.users))if(row.windowStart+RATE_WINDOW_MS<=now)delete value.users[id];
    if(value.windowStart+RATE_WINDOW_MS<=now){value.windowStart=now;value.globalCount=0;}
    if(!value.users[uid]&&Object.keys(value.users).length>=MAX_RATE_USERS){
      denial='Rate capacity reached.';return;
    }
    const user=value.users[uid]||{windowStart:now,count:0};
    const active=Object.values(value.leases);
    if(user.count>=MAX_USER_REQUESTS||value.globalCount>=MAX_GLOBAL_REQUESTS||
       active.length>=MAX_GLOBAL_CONCURRENT||active.filter(x=>x.uid===uid).length>=MAX_USER_CONCURRENT){
      denial='City search is temporarily limited.';return;
    }
    user.count++;value.globalCount++;value.users[uid]=user;
    value.leases[lease]={uid,expiresAt};
    return value;
  },undefined,false);
  if(!result.committed)throw new HttpsError('resource-exhausted',denial||'City search is temporarily limited.');
  return lease;
}
async function releaseRate(db,lease) {
  await db.ref(`citySearchRateState/leases/${lease}`).remove();
}

async function searchSession(db,uid,token,now=Date.now()) {
  const hash=digest(token),ref=db.ref(`citySearchSessions/${uid}`);
  let denial;
  const result=await ref.transaction(value=>{
    denial=null;value ||= {};
    for(const [id,row] of Object.entries(value))if(row.expiresAt<=now)delete value[id];
    let row=value[hash];
    if(!row){
      if(Object.keys(value).length>=MAX_SESSIONS_PER_USER){denial='Too many city sessions.';return;}
      row={createdAt:now,expiresAt:now+SESSION_TTL_MS,queryCount:0,state:'open',placeIds:{}};
    }
    if(row.state!=='open'||row.expiresAt<=now||row.queryCount>=MAX_USER_REQUESTS){
      denial='City session expired or closed.';return;
    }
    row.queryCount++;value[hash]=row;return value;
  },undefined,false);
  if(!result.committed)throw new HttpsError('failed-precondition',denial||'City session unavailable.');
  return hash;
}
async function rememberPredictions(db,uid,hash,ids) {
  const ref=db.ref(`citySearchSessions/${uid}/${hash}`);
  const row=(await ref.get()).val();
  if(!row||row.state!=='open')return;
  const updates={};
  for(const id of ids.slice(0,5))updates[digest(id)]=true;
  if(Object.keys(updates).length)await ref.child('placeIds').update(updates);
}
async function closeSessionForDetails(db,uid,token,id,now=Date.now()) {
  const hash=digest(token),ref=db.ref(`citySearchSessions/${uid}`);
  let denial;
  const result=await ref.transaction(value=>{
    denial=null;
    value ||= {};
    const row=value[hash];
    if(!row||row.expiresAt<=now||row.state!=='open'||row.placeIds?.[digest(id)]!==true){
      denial='City session expired or selection was not suggested.';return value;
    }
    row.state='closed';row.selectedPlaceId=id;value[hash]=row;return value;
  },undefined,false);
  if(!result.committed||denial)throw new HttpsError('failed-precondition',denial||'City session unavailable.');
}
async function issueGrant(db,uid,purpose,targetId,placeId,city,country,now=Date.now()) {
  scope(purpose,targetId,uid);
  const names=authored(city,country),id=nonce(),ref=db.ref(`cityVerificationGrants/${uid}`);
  let denial;
  const result=await ref.transaction(value=>{
    denial=null;value ||= {};
    for(const [key,row] of Object.entries(value))if(row.expiresAt<=now)delete value[key];
    if(Object.keys(value).length>=MAX_GRANTS_PER_USER){denial='Too many pending city confirmations.';return;}
    value[id]={purpose,targetId,placeId,...names,createdAt:now,expiresAt:now+GRANT_TTL_MS};
    return value;
  },undefined,false);
  if(!result.committed)throw new HttpsError('resource-exhausted',denial||'City confirmation unavailable.');
  return {nonce:id,location:{version:1,precision:'city',confirmed:true,...names}};
}
async function consumeGrant(db,uid,purpose,targetId,id,operationId,location,now=Date.now()) {
  scope(purpose,targetId,uid);
  if(!safeId(id)||!safeId(operationId))throw new HttpsError('invalid-argument','Invalid city confirmation.');
  const names=authored(location?.city,location?.country);
  const ref=db.ref(`cityVerificationGrants/${uid}`);
  let denial;
  const result=await ref.transaction(value=>{
    denial=null;
    value ||= {};
    const row=value[id];
    if(!row||row.expiresAt<=now){denial='City confirmation expired.';return value;}
    if(row.purpose!==purpose||row.targetId!==targetId){denial='City target does not match.';return value;}
    if(row.city!==names.city||row.country!==names.country){denial='City fields changed after confirmation.';return value;}
    if(row.usedOperationId&&row.usedOperationId!==operationId){denial='City confirmation was already used.';return value;}
    row.usedOperationId=operationId;row.consumedAt ||= now;
    value[id]=row;return value;
  },undefined,false);
  if(!result.committed||denial)throw new HttpsError('failed-precondition',denial||'City confirmation unavailable.');
  return {location:{version:1,precision:'city',confirmed:true,...names},
    consumedAt:result.snapshot.val()[id].consumedAt};
}
async function cleanup(db,now=Date.now()) {
  const updates={};
  for(const root of ['citySearchSessions','cityVerificationGrants']) {
    const users=(await db.ref(root).get()).val()||{};
    for(const [uid,rows] of Object.entries(users))for(const [id,row] of Object.entries(rows||{})){
      if(row.expiresAt<=now)updates[`${root}/${uid}/${id}`]=null;
    }
  }
  if(Object.keys(updates).length)await db.ref().update(updates);
  await db.ref('citySearchRateState').transaction(value=>{
    if(!value)return value;
    value.users ||= {};value.leases ||= {};
    for(const [id,row] of Object.entries(value.users))
      if(row.windowStart+RATE_WINDOW_MS<=now)delete value.users[id];
    for(const [id,row] of Object.entries(value.leases))
      if(row.expiresAt<=now)delete value.leases[id];
    if(value.windowStart+RATE_WINDOW_MS<=now){
      value.windowStart=now;value.globalCount=0;
    }
    return Object.keys(value.users).length||Object.keys(value.leases).length?value:null;
  },undefined,false);
  return Object.keys(updates).length;
}
module.exports={SESSION_TTL_MS,GRANT_TTL_MS,authored,scope,same,createToken,validateToken,
  reserveRate,releaseRate,
  searchSession,rememberPredictions,closeSessionForDetails,issueGrant,consumeGrant,cleanup};
