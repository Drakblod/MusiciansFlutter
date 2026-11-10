'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,signInAnonymously}=require('firebase/auth');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const gate=require('../city_verification');
const authority=require('../membership_authority');

for(const rules of ['database.rules.json','database.transitional.rules.json'])
describe(`INTERNATIONAL-CITY-PICKER-01 server grants and rules: ${rules}`,function(){
  this.timeout(120000);
  const project='demo-musicians-test',suffix=rules.includes('transitional')?'t':'p';
  const alice=`city_alice_${suffix}`,bob=`city_bob_${suffix}`;
  let app,db,env;
  before(async()=>{
    app=admin.initializeApp({projectId:project,
      databaseURL:`http://127.0.0.1:9000?ns=${project}`},`city_gate_${suffix}`);
    db=app.database();
    env=await initializeTestEnvironment({projectId:project,database:{host:'127.0.0.1',port:9000,
      rules:fs.readFileSync(path.join(__dirname,'../..',rules),'utf8')}});
  });
  after(async()=>{await env.cleanup();await app.delete();});

  async function cityClient(name, test) {
    assert.strictEqual(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__,true);
    assert.strictEqual(process.env.GCLOUD_PROJECT,project);
    const client=initializeApp({projectId:project,apiKey:'emulator-only'},`city_${suffix}_${name}`);
    try {
      const auth=getAuth(client);
      connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const {user}=await signInAnonymously(auth);
      const functions=getFunctions(client,'europe-west1');
      connectFunctionsEmulator(functions,'127.0.0.1',5001);
      const call=async (name,data)=>(await httpsCallable(functions,name)(data)).data;
      const {sessionToken}=await call('startCatalogueCitySession',{});
      await test(user.uid,sessionToken,call);
    } finally {await deleteApp(client);}
  }

  for (const city of ['Ljusdal','Stockholm','Lidingö']) {
    it(`resolves the selected ${city} prediction through real callables and commits its receipt`,async()=>{
      await cityClient(city,async(uid,sessionToken,call)=>{
        const {candidates}=await call('searchCatalogueCities',{query:city,sessionToken});
        assert.strictEqual(candidates.length,1);
        const [selected]=candidates;
        assert.strictEqual(selected.city,city);
        assert.strictEqual(selected.country,'Sweden');
        const request={placeId:selected.placeId,sessionToken,purpose:'profile',targetId:uid,
          city:`  ${selected.city.normalize('NFD')}  `,country:selected.country};
        const receipt=await call('resolveCatalogueCity',request);
        const location={version:1,precision:'city',confirmed:true,city,country:'Sweden'};
        assert.deepStrictEqual(receipt.location,location);
        assert.strictEqual(typeof receipt.nonce,'string');
        assert.strictEqual((await db.ref(`users/${uid}/info/PublicLocation`).get()).exists(),false);
        await assert.rejects(()=>call('resolveCatalogueCity',request),
          error=>error.code==='functions/failed-precondition');
        await call('commitUserCity',{nonce:receipt.nonce,operationId:'confirm_city',location});
        assert.deepStrictEqual((await db.ref(`users/${uid}/info/PublicLocation`).get()).val(),location);
      });
    });
  }

  it('rejects an edited city name that does not match Details and issues no receipt',async()=>{
    await cityClient('mismatch',async(uid,sessionToken,call)=>{
      const {candidates:[selected]}=await call('searchCatalogueCities',{query:'Ljusdal',sessionToken});
      await assert.rejects(()=>call('resolveCatalogueCity',{placeId:selected.placeId,sessionToken,
        purpose:'profile',targetId:uid,city:'Stockholm',country:selected.country}),
      error=>error.code==='functions/failed-precondition' && /must match/.test(error.message));
      assert.strictEqual((await db.ref(`cityVerificationGrants/${uid}`).get()).exists(),false);
    });
  });

  it('one signed session supports multiple queries, one selection and no cross-user or expired reuse',async()=>{
    const now=Date.now(),token=gate.createToken(alice,'local-test-secret',now);
    assert(gate.validateToken(token,alice,'local-test-secret',now));
    assert.throws(()=>gate.validateToken(token,bob,'local-test-secret',now));
    assert.throws(()=>gate.validateToken(token,alice,'local-test-secret',now+gate.SESSION_TTL_MS+1));
    assert.throws(()=>gate.validateToken('bad',alice,'local-test-secret',now));
    const first=await gate.searchSession(db,alice,token,now);
    const second=await gate.searchSession(db,alice,token,now+1);
    assert.strictEqual(first,second);
    await gate.rememberPredictions(db,alice,first,['PlaceBerlin123']);
    const storedSession=(await db.ref(`citySearchSessions/${alice}/${first}`).get()).val();
    assert(storedSession?.placeIds&&Object.keys(storedSession.placeIds).length===1,
      JSON.stringify(storedSession));
    await gate.closeSessionForDetails(db,alice,token,'PlaceBerlin123',now+2);
    await assert.rejects(()=>gate.closeSessionForDetails(db,alice,token,'PlaceBerlin123',now+3));
    await assert.rejects(()=>gate.searchSession(db,alice,token,now+4));
    await assert.rejects(()=>gate.closeSessionForDetails(db,bob,token,'PlaceBerlin123',now+4));
    const newToken=gate.createToken(alice,'local-test-secret',now+5);
    assert.notStrictEqual(token,newToken);
    await gate.searchSession(db,alice,newToken,now+5);
  });

  it('grant binds uid, purpose, target, authored fields and one operation atomically',async()=>{
    const now=Date.now(),bandA=`city_band_a_${suffix}`,bandB=`city_band_b_${suffix}`;
    const grant=await gate.issueGrant(db,alice,'band',bandA,'PlaceBerlin123','Berlin','Germany',now);
    assert((await db.ref(`cityVerificationGrants/${alice}/${grant.nonce}`).get()).exists());
    assert(!JSON.stringify(grant).includes('PlaceBerlin123'));
    await assert.rejects(()=>gate.consumeGrant(db,bob,'band',bandA,grant.nonce,'op1',grant.location,now));
    await assert.rejects(()=>gate.consumeGrant(db,alice,'profile',alice,grant.nonce,'op1',grant.location,now));
    await assert.rejects(()=>gate.consumeGrant(db,alice,'band',bandB,grant.nonce,'op1',grant.location,now));
    await assert.rejects(()=>gate.consumeGrant(db,alice,'band',bandA,grant.nonce,'op1',
      {...grant.location,city:'Imaginary'},now));
    const [a,b]=await Promise.allSettled([
      gate.consumeGrant(db,alice,'band',bandA,grant.nonce,'op1',grant.location,now),
      gate.consumeGrant(db,alice,'band',bandA,grant.nonce,'op2',grant.location,now)]);
    assert.strictEqual([a,b].filter(x=>x.status==='fulfilled').length,1);
    const winner=a.status==='fulfilled'?'op1':'op2';
    const retry=await gate.consumeGrant(db,alice,'band',bandA,grant.nonce,winner,grant.location,now+1);
    assert.strictEqual(retry.location.city,'Berlin');
    assert(!('placeId' in retry.location));
    await assert.rejects(()=>gate.consumeGrant(db,alice,'band',bandA,grant.nonce,winner,grant.location,
      now+gate.GRANT_TTL_MS+1));
  });

  it('per-user and global rate state bounds concurrent and repeated provider calls',async()=>{
    const now=Date.now();await db.ref('citySearchRateState').remove();
    for(let i=0;i<10;i++){
      const lease=await gate.reserveRate(db,alice,now);
      await gate.releaseRate(db,lease);
    }
    await assert.rejects(()=>gate.reserveRate(db,alice,now));
    const bobLease=await gate.reserveRate(db,bob,now);await gate.releaseRate(db,bobLease);
    const recovered=await gate.reserveRate(db,alice,now+60001);await gate.releaseRate(db,recovered);
    await db.ref('citySearchRateState').remove();
    const one=await gate.reserveRate(db,alice,now),two=await gate.reserveRate(db,alice,now);
    await assert.rejects(()=>gate.reserveRate(db,alice,now));
    await gate.releaseRate(db,one);await gate.releaseRate(db,two);
  });

  it('active exact-band manager consumes grant; revoked and cross-band attempts fail',async()=>{
    const bandA=`city_authority_a_${suffix}`,bandB=`city_authority_b_${suffix}`;
    const member={Role:'Leader',Status:'active'};
    await db.ref(`Bands/${bandA}`).set({Name:'A',Members_band:{[alice]:member}});
    await db.ref(`Bands/${bandB}`).set({Name:'B',Members_band:{[alice]:member}});
    const grant=await gate.issueGrant(db,alice,'band',bandA,'PlaceBerlin123','Berlin','Germany');
    const payload={action:'metadata',bandId:bandA,operationId:'city_op_a',
      cityGrantNonce:grant.nonce,metadata:{Name:'A',PublicLocation:grant.location}};
    await assert.rejects(()=>authority.mutate(db,alice,{...payload,bandId:bandB}));
    await authority.mutate(db,alice,payload);
    assert.strictEqual((await db.ref(`Bands/${bandA}/PublicLocation/city`).get()).val(),'Berlin');
    await authority.mutate(db,alice,payload); // same authorized retry
    await assert.rejects(()=>authority.mutate(db,alice,{...payload,operationId:'city_op_other'}));
    const revoked=await gate.issueGrant(db,alice,'band',bandA,'PlaceOslo123','Oslo','Norway');
    await db.ref(`Bands/${bandA}/Members_band/${alice}/Status`).set('inactive');
    await assert.rejects(()=>authority.mutate(db,alice,{...payload,operationId:'city_revoked',
      cityGrantNonce:revoked.nonce,metadata:{Name:'A',PublicLocation:revoked.location}}));
  });

  it('old grants are bounded and scheduled cleanup removes expired records',async()=>{
    const uid=`city_cleanup_${suffix}`,now=Date.now();
    for(let i=0;i<5;i++)await gate.issueGrant(db,uid,'profile',uid,`Place${i}123`,'Berlin','Germany',now);
    await assert.rejects(()=>gate.issueGrant(db,uid,'profile',uid,'Place999','Berlin','Germany',now));
    const removed=await gate.cleanup(db,now+gate.SESSION_TTL_MS+1);
    assert(removed>=5);
    assert.strictEqual((await db.ref(`cityVerificationGrants/${uid}`).get()).val(),null);
  });

  it('clients cannot read or write rate, session or grant roots or forge profile city',async()=>{
    const owner=env.authenticatedContext(alice).database();
    const other=env.authenticatedContext(bob).database();
    const anon=env.unauthenticatedContext().database();
    for(const root of ['citySearchRateState','citySearchSessions','cityVerificationGrants'])
      for(const client of [owner,other,anon]){
        await assertFails(client.ref(root).get());
        await assertFails(client.ref(`${root}/${alice}`).set({forged:true}));
      }
    await db.ref(`users/${alice}/info`).set({DisplayName:'Alice'});
    await assertFails(owner.ref(`users/${alice}/info/PublicLocation`).set(
      {version:1,precision:'city',confirmed:true,city:'Imaginary',country:'Nowhere'}));
    await assertFails(owner.ref(`users/${alice}/info/Location`).set('Imaginary, Nowhere'));
    await assertFails(owner.ref(`users/${alice}/info`).set({DisplayName:'Alice',
      Location:'Imaginary, Nowhere',PublicLocation:{city:'Imaginary',country:'Nowhere'}}));
    await assertSucceeds(owner.ref(`users/${alice}/info/About`).set('Updated'));
  });
});
