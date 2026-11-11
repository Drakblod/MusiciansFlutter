'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const admin=require('firebase-admin');
const {reconcile}=require('../catalogue_projections');
const {run}=require('../scripts/backfill_catalogue_projections');
for(const rules of ['database.rules.json','database.transitional.rules.json'])describe(`SAFE-CATALOGUE-PROJECTIONS-01 actual trigger/rules integration: ${rules}`,function(){
 this.timeout(300000);let env,app,db;const ns='demo-musicians-test';const prefix=rules.includes('transitional')?'cpt':'cpf';
 async function wait(p,test){for(let i=0;i<300;i++){const v=(await db.ref(p).get()).val();if(test(v))return v;await new Promise(r=>setTimeout(r,100));}throw new Error('Catalogue trigger did not converge');}
 before(async()=>{app=admin.initializeApp({projectId:ns,databaseURL:`http://127.0.0.1:9000?ns=${ns}`},`catalogue_${prefix}`);db=app.database();env=await initializeTestEnvironment({projectId:ns,database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',rules),'utf8')}});});
 after(async()=>{await env.cleanup();await app.delete();});
 it('actual user trigger projects approved aliases/secondary skills and no private fields',async()=>{
  await db.ref(`users/${prefix}_u`).set({info:{displayName:'Public',userType:'Guitar',instruments:['Guitar',' Piano ','piano'],genres:['Jazz'],Location:'Stockholm',Email:'secret@example.test',PushToken:'secret',Contact:'5550000000'},AppliedSubRequests:{secret:true},Agreements:{secret:true},unknown:{secret:true}});
  const v=await wait(`publicUserProfiles/${prefix}_u`,v=>v?.DisplayName==='Public');assert.deepStrictEqual(v.SecondarySkills,['Piano']);assert.strictEqual(v.userId,`${prefix}_u`);assert(!JSON.stringify(v).includes('secret'));assert(!('info'in v));
 });
 it('owner cannot forge server-written structured city or city authority markers',async()=>{
  const id=`${prefix}_city_owner`;
  await db.ref(`users/${id}`).set({info:{DisplayName:'Owner'}});
  const owner=env.authenticatedContext(id).database();
  const city={version:1,precision:'city',confirmed:true,city:'Berlin',country:'Germany'};
  await assertFails(owner.ref(`users/${id}/info/PublicLocation`).set(city));
  await assertFails(owner.ref(`users/${id}/info`).update({PublicLocation:city,LocationCleared:false}));
  await assertSucceeds(owner.ref(`users/${id}/info/About`).set('Public biography'));
  for(const root of ['citySearchRateState','citySearchSessions','cityVerificationGrants']){
    await assertFails(owner.ref(`${root}/${id}`).get());
    await assertFails(owner.ref(`${root}/${id}`).set({forged:true}));
  }
 });
 it('an owner can rename a track without changing its URL and only the server can project its title',async()=>{
  const id=`${prefix}_track_owner`, info=`users/${id}/info`, projection=`publicUserProfiles/${id}`;
  const owner=env.authenticatedContext(id).database();
  const other=env.authenticatedContext('track_other').database();
  const url='https://example.test/uploads/private-storage-object.mp3';
  await db.ref(info).set({DisplayName:'Track owner',AudioSnippetUrl:url,Email:'private@example.test'});
  const legacy=await wait(projection,v=>v?.AudioSnippetUrl===url);
  assert(!('AudioSnippetTitle' in legacy));
  await assertSucceeds(owner.ref(info).update({AudioSnippetTitle:'First Track',About:'Updated'}));
  const titled=await wait(projection,v=>v?.AudioSnippetTitle==='First Track');
  assert.strictEqual(titled.AudioSnippetUrl,url);
  assert.strictEqual(titled.About,'Updated');
  assert(!('Email' in titled));
  const title=owner.ref(`${info}/AudioSnippetTitle`);
  await assertSucceeds(title.set('Andra låten / Repris!'));
  assert.strictEqual((await title.get()).val(),'Andra låten / Repris!');
  await assertFails(other.ref(`${info}/AudioSnippetTitle`).get());
  await assertFails(other.ref(`${info}/AudioSnippetTitle`).set('Forged'));
  await assertFails(owner.ref(`${projection}/AudioSnippetTitle`).set('Forged'));
  for(const invalid of [true,'x'.repeat(81),'Line\nBreak','A\u0001B','A\u0085B','A\u2028B','Leading  spaces','Non\u00a0breaking','/private/local.wav','C:\\private.wav']) {
   await assertFails(title.set(invalid));
  }
  const replacement='https://example.test/uploads/replacement.wav';
  await assertSucceeds(owner.ref(info).update({AudioSnippetUrl:replacement,AudioSnippetTitle:'Second Take: Finale!'}));
  const replaced=await wait(projection,v=>v?.AudioSnippetUrl===replacement);
  assert.strictEqual(replaced.AudioSnippetTitle,'Second Take: Finale!');
  await assertFails(owner.ref(`${info}/AudioSnippetUrl`).remove());
  await assertSucceeds(owner.ref(info).update({AudioSnippetUrl:null,AudioSnippetTitle:null}));
  await wait(projection,v=>v?.DisplayName==='Track owner'&&!v.AudioSnippetUrl&&!v.AudioSnippetTitle);
  await assertFails(title.set('Without an audio clip'));
 });
 it('explicitly cleared profile never republishes a legacy root city',async()=>{
  const id=`${prefix}_cleared_city`;
  await db.ref(`users/${id}`).set({Location:'Stockholm',info:{DisplayName:'Cleared',LocationCleared:true}});
  const profile=await wait(`publicUserProfiles/${id}`,v=>v?.DisplayName==='Cleared');
  assert(!('Location' in profile));
  assert(!('PublicLocation' in profile));
 });
 it('user update and removed fields replace projection without stale descendants',async()=>{
  await db.ref(`users/${prefix}_u/info`).set({DisplayName:'Updated',About:'Now public'});const v=await wait(`publicUserProfiles/${prefix}_u`,v=>v?.DisplayName==='Updated');assert.strictEqual(v.About,'Now public');assert(!('Genres'in v));assert(!('Instruments'in v));
  const before=JSON.stringify(v);await reconcile(db,'user',`${prefix}_u`);assert.strictEqual(JSON.stringify((await db.ref(`publicUserProfiles/${prefix}_u`).get()).val()),before);
 });
 it('user malformed replacement and deletion remove projection',async()=>{await db.ref(`users/${prefix}_u`).set('malformed');await wait(`publicUserProfiles/${prefix}_u`,v=>v===null);await db.ref(`users/${prefix}_u`).set({info:{DisplayName:'Restored'}});await wait(`publicUserProfiles/${prefix}_u`,v=>v?.DisplayName==='Restored');await db.ref(`users/${prefix}_u`).remove();await wait(`publicUserProfiles/${prefix}_u`,v=>v===null);});
 it('actual band trigger excludes private descendants and derives active-access membership count',async()=>{
  await db.ref(`Bands/${prefix}_b`).set({Name:'Public band',Genres:['Jazz'],Location:'Malmö',Address:'Private',Members_band:{a:{Role:'Leader',Status:'active'},b:{Role:'Member',Status:'on_hold'},c:{Role:'Member'},d:{Role:'Member',Status:'removed'},e:{Role:'Member',Status:'inactive'}},Events:{secret:{externalInvitees:{secret:true}}},settings:{secret:true},files:{secret:true},conversations:{secret:true}});
  const v=await wait(`publicBandProfiles/${prefix}_b`,v=>v?.activeMemberCount===3);assert.strictEqual(v.Name,'Public band');assert(!('Members_band'in v));assert(!('Events'in v));assert(!('Address'in v));assert(!JSON.stringify(v).includes('secret'));
 });
 it('membership changes and source updates refresh band count and remove stale public fields',async()=>{await db.ref(`Bands/${prefix}_b/Members_band/b/Status`).set('inactive');await wait(`publicBandProfiles/${prefix}_b`,v=>v?.activeMemberCount===2);await db.ref(`Bands/${prefix}_b`).update({Name:'Renamed',Genres:null});const v=await wait(`publicBandProfiles/${prefix}_b`,v=>v?.Name==='Renamed'&&!v.Genres);assert.strictEqual(v.activeMemberCount,2);});
 it('band deletion removes its projection',async()=>{await db.ref(`Bands/${prefix}_b`).set('malformed');await wait(`publicBandProfiles/${prefix}_b`,v=>v===null);await db.ref(`Bands/${prefix}_b`).set({Name:'Restored band'});await wait(`publicBandProfiles/${prefix}_b`,v=>v?.Name==='Restored band');await db.ref(`Bands/${prefix}_b`).remove();await wait(`publicBandProfiles/${prefix}_b`,v=>v===null);});
 for(const root of ['publicUserProfiles','publicBandProfiles']) {
  it(`${root}: authenticated read allowed; anonymous denied; all client create/update/delete denied`,async()=>{
   await db.ref(`${root}/${prefix}_existing`).set({[root==='publicUserProfiles'?'userId':'bandId']:`${prefix}_existing`});
   const own=env.authenticatedContext('catalogue_user').database(),other=env.authenticatedContext('catalogue_other').database(),anon=env.unauthenticatedContext().database();
   await assertSucceeds(own.ref(root).get());await assertFails(anon.ref(root).get());
   await assertSucceeds(env.authenticatedContext('catalogue_anonymous',{firebase:{sign_in_provider:'anonymous'}}).database().ref(root).get());
   for(const client of [own,other,anon]) {await assertFails(client.ref(`${root}/${prefix}_forged`).set({Name:'Forged'}));await assertFails(client.ref(`${root}/${prefix}_existing`).update({Name:'Forged'}));await assertFails(client.ref(`${root}/${prefix}_existing`).remove());}
  });
 }
 it('existing protected index and private conversation boundaries remain denied',async()=>{const client=env.authenticatedContext('catalogue_other').database();await assertFails(client.ref('userBandMembershipIndex/catalogue_owner').get());await assertFails(client.ref('membershipMutationOperations/private_catalogue_test').get());});
 it('complete >100 catalogue, repeated events and dry-run/apply remain idempotent',async()=>{
  // Keep the Functions emulator below its worker/socket limit while still
  // requiring every one of the 250 real triggers to populate the catalogue.
  for(let start=0;start<125;start+=10){
    const changes={};
    for(let i=start;i<Math.min(start+10,125);i++){
      changes[`users/${prefix}_catalogue_${i}`]={info:{DisplayName:`Public ${i}`}};
      changes[`Bands/${prefix}_catalogue_${i}`]={Name:`Band ${i}`};
    }
    await db.ref().update(changes);
    const last=Math.min(start+9,124);
    await wait(`publicUserProfiles/${prefix}_catalogue_${last}`,v=>v?.DisplayName===`Public ${last}`);
    await wait(`publicBandProfiles/${prefix}_catalogue_${last}`,v=>v?.Name===`Band ${last}`);
  }
  await wait(`publicUserProfiles/${prefix}_catalogue_124`,v=>v?.DisplayName==='Public 124');await wait(`publicBandProfiles/${prefix}_catalogue_124`,v=>v?.Name==='Band 124');
  for(const root of ['publicUserProfiles','publicBandProfiles']) {const all=await wait(root,v=>Object.keys(v||{}).filter(k=>k.startsWith(`${prefix}_catalogue_`)).length===125);assert.strictEqual(Object.keys(all).filter(k=>k.startsWith(`${prefix}_catalogue_`)).length,125);}
  const dry=await run(db,{apply:false});assert.strictEqual(dry.writes,0);
  await db.ref(`publicUserProfiles/${prefix}_orphan`).set({userId:`${prefix}_orphan`});const applied=await run(db,{apply:true});assert(applied.writes>=1);assert.strictEqual((await db.ref(`publicUserProfiles/${prefix}_orphan`).get()).val(),null);
  const second=await run(db,{apply:true});assert.strictEqual(second.writes,0);
 });
});
