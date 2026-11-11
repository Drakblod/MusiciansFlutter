'use strict';
const assert=require('assert');
const {userProfile,bandProfile,countMembers,plan,equal,city}=require('../catalogue_projections');
const {configuration,run}=require('../scripts/backfill_catalogue_projections');
describe('SAFE-CATALOGUE-PROJECTIONS-01 sanitizers and safe backfill',()=>{
 const privateData={Email:'private@example.test',Contact:'5551234567',PushToken:'secret',AppliedSubRequests:{private:true},SubRequests:{private:true},Agreements:{private:true},conversations:{private:true},notifications:{private:true},Favorites:{private:true},Bands:{private:true},Coordinates:{lat:59,lng:18},Address:'Private street',arbitrary:{secret:'hidden'}};
 it('user allowlist projects every audited public field and no private descendants',()=>{
  const p=userProfile('u',{...privateData,info:{...privateData,DisplayName:'Public',Nickname:'Nick',UserType:'Guitar',MainInstrument:'Guitar',Instruments:['Guitar',' Piano ','piano','null','Vocals'],Styles:['Jazz'],Genres:['Rock'],Location:'Stockholm, Sweden',About:'Public biography',Level:'A = PRO',ProfilePictureUrl:'https://example.test/p.png',SpotifyUrl:'https://open.spotify.com/artist/1',YoutubeUrl:'https://youtube.com/watch?v=1',AudioSnippetUrl:'https://example.test/a.mp3',CollabRoles:['Musician'],CollabRemote:true,CollabBio:'Collaboration'}});
  assert.deepStrictEqual(Object.keys(p).sort(),['userId','DisplayName','Nickname','UserType','MainInstrument','Instruments','SecondarySkills','Styles','Genres','Location','PublicLocation','About','Level','ProfilePictureUrl','SpotifyUrl','YoutubeUrl','AudioSnippetUrl','CollabRoles','CollabRemote','CollabBio'].sort());
  assert.deepStrictEqual(p.SecondarySkills,['Piano','Vocals']);assert(!JSON.stringify(p).includes('private'));assert(!JSON.stringify(p).includes('secret'));
 });
 it('only projects normalized canonical Music Snippet titles alongside audio',()=>{
  const url='https://example.test/filename.mp3';
  const source=title=>({AudioSnippetTitle:'Root title',info:{AudioSnippetUrl:url,AudioSnippetTitle:title,Email:'private'}});
  assert.deepStrictEqual(userProfile('u',source('  Vår\u00a0  låt / Repris!  ')),
    {userId:'u',AudioSnippetUrl:url,AudioSnippetTitle:'Vår låt / Repris!'});
  for(const title of [null, true, 'x'.repeat(81), 'File\nname', 'C:\\secret.mp3','/secret.mp3']){
   assert.deepStrictEqual(userProfile('u',source(title)),{userId:'u',AudioSnippetUrl:url});
  }
  assert.deepStrictEqual(userProfile('u',{info:{AudioSnippetTitle:'No audio'}}),{userId:'u'});
 });
 for(const alias of ['infoPascal','rootPascal','infoCamel','rootCamel'])it(`normalizes legacy user fields ${alias}`,()=>{
  const v=alias.endsWith('Pascal')?{DisplayName:'Name',Instruments:'Guitar',Genres:{b:'Jazz',a:'Rock'}}:{displayName:'Name',instruments:'Guitar',genres:{b:'Jazz',a:'Rock'}};
  const p=userProfile('key',alias.startsWith('info')?{info:v}:v);assert.strictEqual(p.DisplayName,'Name');assert.deepStrictEqual(p.Genres,['Rock','Jazz']);assert.strictEqual(p.userId,'key');
 });
 for(const v of [null,'bad',42,true,[]])it(`malformed user/band source ${JSON.stringify(v)} fails safely`,()=>{assert.strictEqual(userProfile('u',v),null);assert.strictEqual(bandProfile('b',v),null);});
 it('legacy main-instrument primary precedence matches the existing Flutter model',()=>{
  const p=userProfile('u',{UserType:'Guitar',MainInstrument:'Piano',Instruments:['Guitar','Piano','Vocals']});assert.deepStrictEqual(p.SecondarySkills,['Guitar','Vocals']);
  const stale=userProfile('u',{MainInstrument:'Piano',Instruments:['Guitar','Vocals']});assert.deepStrictEqual(stale.SecondarySkills,['Piano','Vocals']);
 });
 it('skill collections beyond 100 items retain every legitimate normalized match',()=>{const skills=Array.from({length:140},(_,i)=>`Skill ${i}`);const p=userProfile('u',{UserType:'Skill 0',Instruments:skills});assert.strictEqual(p.Instruments.length,140);assert.strictEqual(p.SecondarySkills.length,139);assert(p.SecondarySkills.includes('Skill 139'));});
 it('identity comes from key, not embedded IDs; missing optional fields stay absent',()=>{assert.deepStrictEqual(userProfile('u',{UserId:'forged',Email:'hidden'}),{userId:'u'});assert.deepStrictEqual(bandProfile('b',{bandId:'forged'}),{bandId:'b',activeMemberCount:0});});
 for(const v of ['Private street 123, Stockholm','59.32,18.06','Unknown private place','me@example.test','Stockholm, Private Street'])it(`omits non-approved location ${v}`,()=>{assert.strictEqual(city(v),undefined);});
 it('retains exact approved coarse location without inventing values',()=>{assert.strictEqual(city(' Stockholm, Sweden '),'Stockholm, Sweden');assert.strictEqual(city(null),undefined);});
 it('structured international cities retain city-level fields and exclude private provider data',()=>{
  for(const [c,country] of [['Berlin','Germany'],['Oslo','Norway'],['Växjö','Sweden'],['New York','United States'],['Łódź','Poland']]){
   const input={version:1,precision:'city',confirmed:true,city:c,country,countryCode:'us',
     placeId:'private',latitude:52,longitude:13,providerPayload:{secret:true}};
   // The canonical contract itself must not contain provider/private fields.
   const safe={version:1,precision:'city',confirmed:true,city:c,country,countryCode:'us'};
   const user=userProfile('u',{Location:'Unknown legacy',PublicLocation:safe});
   const band=bandProfile('b',{Location:'Unknown legacy',PublicLocation:safe});
   assert.strictEqual(user.Location,`${c}, ${country}`);assert.strictEqual(band.Location,user.Location);
   assert.strictEqual(user.PublicLocation.countryCode,'US');assert(!JSON.stringify(user).includes('placeId'));
   assert(!JSON.stringify(band).includes('latitude'));
   assert(!userProfile('u',{PublicLocation:input}).Location);
  }
 });
 it('region label deterministic and invalid structured record leaves identity intact',()=>{
  const value={version:1,precision:'city',confirmed:true,city:'New York',region:'New York',country:'United States',countryCode:'US'};
  assert.strictEqual(userProfile('u',{PublicLocation:value}).Location,'New York, New York, United States');
  assert.deepStrictEqual(userProfile('u',{PublicLocation:{...value,precision:'exact'}}),{userId:'u'});
 });
 it('exact Swedish aliases normalize; addresses and unknown international legacy locations omit',()=>{
  assert.strictEqual(city('Gothenburg, Sverige'),'Göteborg, Sweden');
  assert.strictEqual(city('Göteborg'),'Göteborg, Sweden');
  for(const value of ['Berlin, Germany','Private street 123, Stockholm','Unknown private place']){
   assert.strictEqual(userProfile('u',{Location:value}).Location,undefined);
   assert.strictEqual(bandProfile('b',{Location:value}).bandId,'b');
  }
 });
 it('explicit profile clear suppresses an older root-level legacy city',()=>{
  const source={Location:'Stockholm',info:{LocationCleared:true}};
  assert.deepStrictEqual(userProfile('u',source),{userId:'u'});
  assert.deepStrictEqual(plan({u:source},{}).updates['publicUserProfiles/u'],{userId:'u'});
 });
 it('omits arbitrary nested values and invalid/oversized/unsafe media',()=>{const p=userProfile('u',{DisplayName:{Email:'hidden'},About:'x'.repeat(4001),Instruments:[{nested:'secret'}],ProfilePictureUrl:'javascript:alert(1)',YoutubeUrl:'https://user:password@example.test/'});assert.deepStrictEqual(p,{userId:'u'});});
 it('normalizes approved legacy public social URLs',()=>{assert.strictEqual(userProfile('u',{YoutubeUrl:'youtube.com/watch?v=1'}).YoutubeUrl,'https://youtube.com/watch?v=1');});
 it('band allowlist excludes private roster, events, invitations, assignments and settings',()=>{
  const p=bandProfile('b',{...privateData,Name:'Band',Description:'Public',EnsembleType:'Choir',Genres:['Jazz'],Style_band:['Classical'],Style:'Style',Level:'Pro',Qualification:'Public',Location:'Malmö',About:'About',Members_band:{a:{Role:'Leader',Status:'active'}},Events:{externalInvitees:'secret'},responses:{secret:true},substituteAssignments:{secret:true},settings:{secret:true},files:{secret:true}});
  assert.strictEqual(p.activeMemberCount,1);assert(!JSON.stringify(p).includes('secret'));for(const k of Object.keys(privateData))assert(!(k in p));assert(!('Members_band'in p));assert(!('Events'in p));
 });
 for(const status of [undefined,'active',' ACTIVE ','on_hold','temporarily_off','inactive','removed','pending','invited','archived','rejected','unknown'])it(`server member count follows canonical status ${status}`,()=>{
  assert.strictEqual(countMembers({u:{Role:'Member',...(status===undefined?{}:{Status:status})}}),[undefined,'active',' ACTIVE ','on_hold','temporarily_off'].includes(status)?1:0);
 });
 it('malformed/empty memberships and conflicting status aliases do not count',()=>assert.strictEqual(countMembers({a:{},b:'Leader',c:{Role:'Leader',Status:'active',status:'inactive'}}),0));
 it('projection plan retains complete 251-user/251-band catalogue and deterministic IDs',()=>{
  const users=Object.fromEntries(Array.from({length:251},(_,i)=>[`u${i}`,{DisplayName:`Musician ${i}`} ]));const bands=Object.fromEntries(Array.from({length:251},(_,i)=>[`b${i}`,{Name:`Band ${i}`} ]));
  const result=plan(users,bands);assert.strictEqual(Object.keys(result.updates).length,502);assert.strictEqual(result.counts.eligible,502);assert('publicUserProfiles/u250' in result.updates);assert('publicBandProfiles/b250' in result.updates);
  const pu=Object.fromEntries(Object.entries(result.updates).filter(([p])=>p.startsWith('publicUser')).map(([p,v])=>[p.split('/')[1],v]));const pb=Object.fromEntries(Object.entries(result.updates).filter(([p])=>p.startsWith('publicBand')).map(([p,v])=>[p.split('/')[1],v]));assert.deepStrictEqual(plan(users,bands,pu,pb).updates,{});
 });
 it('stale fields and orphan projection removal never target canonical data',()=>{const p=plan({u:{DisplayName:'A'}},{},{u:{userId:'u',DisplayName:'A',Email:'secret'},gone:{userId:'gone'}});assert.strictEqual(p.counts.proposedDeletions,1);assert(!('Email' in p.updates['publicUserProfiles/u']));assert(Object.keys(p.updates).every(k=>k.startsWith('publicUserProfiles/')));});
 it('stable equality ignores object key insertion order',()=>assert(equal({a:1,b:2},{b:2,a:1})));
 const local=['--project=demo-musicians-test','--database-url=http://127.0.0.1:9000?ns=demo-musicians-test'];
 it('dry-run is default; only explicit apply enables writes',()=>{assert(!configuration(local,{}).apply);assert(configuration([...local,'--apply'],{}).apply);});
 for(const args of [[],['--project=demo-musicians-test'],['--database-url=http://127.0.0.1:9000?ns=demo-musicians-test'],['--project=demo-musicians-test','--database-url=http://127.0.0.1:9000?ns=wrong'],['--project=real-project','--database-url=https://real-project.firebaseio.com'],['--project=real-project','--database-url=https://real-project.firebaseio.com','--allow-production']])it(`refuses unsafe/ambiguous target ${args.join(' ')}`,()=>assert.throws(()=>configuration(args,{})));
 it('remote target requires both production confirmations even for dry-run and matching project',()=>{const args=['--project=real-project','--database-url=https://real-project.firebaseio.com','--allow-production','--confirm-production'];assert(!configuration(args,{}).apply);assert.throws(()=>configuration(args,{FIREBASE_DATABASE_EMULATOR_HOST:'localhost:9000'}));});
 it('dry-run implementation performs zero writes and reports aggregate counts only',async()=>{
  let writes=0;const db={ref:path=>({orderByKey(){return this;},limitToFirst(){return this;},get:async()=>({forEach:cb=>{if(path==='users')cb({key:'private_uid',val:()=>({Email:'secret',DisplayName:'Personal Name'})});}}),update:async()=>{writes++;}})};
  const result=await run(db,{apply:false});assert.strictEqual(writes,0);assert.strictEqual(result.writes,0);assert.strictEqual(result.scanned,1);assert(!JSON.stringify(result).includes('private_uid'));assert(!JSON.stringify(result).includes('Personal Name'));assert(!JSON.stringify(result).includes('secret'));
 });
});
