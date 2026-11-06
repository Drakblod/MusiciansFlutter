'use strict';

const {project,requestsFor,reconcile,equal,key,legacyCalendarEvent,
  reconcileLegacyCalendar}=require('../event_read_models');
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);

function configuration(args,env=process.env) {
  const allowed=/^--(project|database-url|confirm-production)=/;
  if(args.some(arg=>!['--apply','--allow-production'].includes(arg)&&!allowed.test(arg)))
    throw new Error('Unknown backfill option');
  const option=name=>args.find(arg=>arg.startsWith(`--${name}=`))?.slice(name.length+3);
  const projectId=option('project'),databaseURL=option('database-url');
  if(!projectId||!databaseURL||!apiProject(projectId))
    throw new Error('Explicit project and database URL are required');
  const url=new URL(databaseURL);
  if(url.username||url.password||url.hash||url.pathname!=='/')
    throw new Error('Database URL must be an uncredentialed root');
  const local=['localhost','127.0.0.1','[::1]'].includes(url.hostname);
  if(local){
    if(!projectId.startsWith('demo-')||url.protocol!=='http:'||
      url.searchParams.get('ns')!==projectId||
      [...url.searchParams.keys()].some(name=>name!=='ns')||
      env.FIREBASE_DATABASE_EMULATOR_HOST&&env.FIREBASE_DATABASE_EMULATOR_HOST!==url.host)
      throw new Error('Local target must be an explicit matching demo emulator');
  }else{
    throw new Error('Event projection validation is local/emulator only; remote targets are forbidden');
  }
  return {projectId,databaseURL,local,apply:args.includes('--apply')};
}
function apiProject(value){return /^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(value);}
const valueAt=(root,band,event)=>root?.[band]?.[event]??null;
function userIdsAt(root,band,event){
  return Object.keys(root||{}).filter(uid=>root[uid]?.[band]?.[event]!=null);
}

async function run(db,options={apply:false}) {
  const roots=['Bands','bandMemberEvents','bandManagerEvents',
    'userEventReadModels','eventReadProjectionIndex','bandMemberCalendarEvents'];
  const [bands,member,manager,users,index,calendar]=await Promise.all(roots.map(async root=>
    (await db.ref(root).get()).val()||{}));
  const identities=new Set();
  for(const [bandId,band] of Object.entries(bands))for(const eventId of Object.keys(band?.Events||{}))
    identities.add(`${bandId}\0${eventId}`);
  for(const root of [member,manager,index])for(const [bandId,events] of Object.entries(root))
    for(const eventId of Object.keys(events||{}))identities.add(`${bandId}\0${eventId}`);
  for(const [uid,bandMap] of Object.entries(users))for(const [bandId,events] of Object.entries(bandMap||{}))
    for(const eventId of Object.keys(events||{}))identities.add(`${bandId}\0${eventId}`);
  const counts={mode:options.apply?'apply':'dry-run',canonicalEvents:0,
    legacyCalendarEvents:0,eligibleCalendarProjections:0,
    eligibleMemberProjections:0,userTargetedProjections:0,malformedRecords:0,
    staleProjections:0,proposedWrites:0,proposedDeletions:0,unchangedRecords:0,writes:0};
  for(const identity of [...identities].sort()){
    const [bandId,eventId]=identity.split('\0');
    if(!key(bandId)||!key(eventId)){counts.malformedRecords++;continue;}
    const source=bands[bandId]?.Events?.[eventId]??null;
    if(source!=null)counts.canonicalEvents++;
    if(source!=null&&!record(source))counts.malformedRecords++;
    const projected=project(bandId,eventId,bands[bandId]?.Name,source,
      bands[bandId]?.Members_band||{},await requestsFor(db,source));
    if(projected.member)counts.eligibleMemberProjections++;
    counts.userTargetedProjections+=Object.keys(projected.users).length;
    const existingUsers=[...new Set([...userIdsAt(users,bandId,eventId),
      ...Object.keys(index?.[bandId]?.[eventId]||{})])];
    const existing={
      [`bandMemberEvents/${bandId}/${eventId}`]:valueAt(member,bandId,eventId),
      [`bandManagerEvents/${bandId}/${eventId}`]:valueAt(manager,bandId,eventId),
      [`eventReadProjectionIndex/${bandId}/${eventId}`]:valueAt(index,bandId,eventId),
    };
    const desired={
      [`bandMemberEvents/${bandId}/${eventId}`]:projected.member,
      [`bandManagerEvents/${bandId}/${eventId}`]:projected.manager,
      [`eventReadProjectionIndex/${bandId}/${eventId}`]:Object.keys(projected.users).length?
        Object.fromEntries(Object.keys(projected.users).map(uid=>[uid,true])):null,
    };
    for(const uid of new Set([...existingUsers,...Object.keys(projected.users)])){
      existing[`userEventReadModels/${uid}/${bandId}/${eventId}`]=users?.[uid]?.[bandId]?.[eventId]??null;
      desired[`userEventReadModels/${uid}/${bandId}/${eventId}`]=projected.users[uid]??null;
    }
    for(const path of Object.keys(desired)){
      if(equal(existing[path],desired[path]))counts.unchangedRecords++;
      else if(desired[path]==null){counts.proposedDeletions++;counts.staleProjections++;}
      else counts.proposedWrites++;
    }
    if(options.apply){
      const result=await reconcile(db,bandId,eventId,existingUsers);
      counts.writes+=result.changed;
    }
  }
  const calendars=new Set();
  for(const [bandId,events] of Object.entries(bands))
    for(const eventId of Object.keys(events?.Calendar||{}))calendars.add(`${bandId}\0${eventId}`);
  for(const [bandId,events] of Object.entries(calendar))
    for(const eventId of Object.keys(events||{}))calendars.add(`${bandId}\0${eventId}`);
  for(const identity of [...calendars].sort()){
    const [bandId,eventId]=identity.split('\0');
    if(!key(bandId)||!key(eventId)){counts.malformedRecords++;continue;}
    const source=bands?.[bandId]?.Calendar?.[eventId]??null;
    if(source!=null)counts.legacyCalendarEvents++;
    const next=bands[bandId]?legacyCalendarEvent(bandId,eventId,source):null;
    if(next)counts.eligibleCalendarProjections++;
    if(source!=null&&!next)counts.malformedRecords++;
    const old=calendar?.[bandId]?.[eventId]??null;
    if(equal(old,next))counts.unchangedRecords++;
    else if(next==null){counts.proposedDeletions++;counts.staleProjections++;}
    else counts.proposedWrites++;
    if(options.apply){const result=await reconcileLegacyCalendar(db,bandId,eventId);
      if(result.changed)counts.writes++;}
  }
  return counts;
}

if(require.main===module){
  (async()=>{
    const options=configuration(process.argv.slice(2));
    if(options.local)process.env.FIREBASE_DATABASE_EMULATOR_HOST=new URL(options.databaseURL).host;
    const admin=require('firebase-admin');
    const app=admin.initializeApp({projectId:options.projectId,databaseURL:options.databaseURL});
    try{console.log(JSON.stringify(await run(app.database(),options)));}
    finally{await app.delete();}
  })().catch(()=>{console.error('Event read-model backfill refused or failed.');process.exitCode=1;});
}
module.exports={configuration,run};
