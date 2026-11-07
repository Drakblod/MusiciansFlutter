'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase/app');
const {getAuth,connectAuthEmulator,createUserWithEmailAndPassword,signInWithEmailAndPassword,signOut}=require('firebase/auth');
const {getDatabase,connectDatabaseEmulator,ref,get,set}=require('firebase/database');
const {getFunctions,connectFunctionsEmulator,httpsCallable}=require('firebase/functions');
const {getStorage,connectStorageEmulator,ref:storageRef,uploadBytes,deleteObject}=require('firebase/storage');

for(const rules of ['database.rules.json','database.transitional.rules.json']) {
  describe(`Empty-store release lifecycle ${rules}`,function(){
    this.timeout(180000);
    const projectId='demo-musicians-test',bucketName=`${projectId}.appspot.com`;
    let env,server,db;const clients=[];
    const call=async(c,name,data)=>(await httpsCallable(c.functions,name)(data)).data;
    const read=(c,p)=>get(ref(c.db,p));
    const write=(c,p,v)=>set(ref(c.db,p),v);
    function until(p,predicate) {
      const source=db.ref(p);
      return new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>{source.off('value',listener);reject(new Error(`Did not converge: ${p}`));},60000);
        function listener(snapshot) {if(predicate(snapshot.val())){clearTimeout(timer);source.off('value',listener);resolve(snapshot.val());}}
        source.on('value',listener,error=>{clearTimeout(timer);source.off('value',listener);reject(error);});
      });
    }
    async function client(name) {
      const app=initializeApp({projectId,apiKey:'emulator-only',storageBucket:bucketName},`release_${rules}_${name}`);
      const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const database=getDatabase(app,`https://${projectId}.firebaseio.com`);connectDatabaseEmulator(database,'127.0.0.1',9000);
      const functions=getFunctions(app,'europe-west1');connectFunctionsEmulator(functions,'127.0.0.1',5001);
      const storage=getStorage(app);connectStorageEmulator(storage,'127.0.0.1',9199);
      const value={app,auth,db:database,functions,storage,email:`release_${name}@example.test`};clients.push(value);return value;
    }
    before(async()=>{
      // This reset is confined to disposable emulators and cannot select a live
      // project, ambient credential or non-loopback endpoint.
      assert.equal(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__,true);
      for(const [key,value] of Object.entries({GCLOUD_PROJECT:projectId,
        FIREBASE_DATABASE_EMULATOR_HOST:'127.0.0.1:9000',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',
        FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:9199'}))assert.equal(process.env[key],value);
      server=admin.initializeApp({projectId,databaseURL:`http://127.0.0.1:9000?ns=${projectId}`,storageBucket:bucketName},`release_${rules}`);
      db=server.database();
      const cleared=await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${projectId}/accounts`,{method:'DELETE'});
      assert.equal(cleared.status,200);
      const [files]=await server.storage().bucket().getFiles();
      for(const file of files)await file.delete();
      await db.ref().set(null);
      assert.equal((await server.auth().listUsers()).users.length,0);
      assert.equal((await server.storage().bucket().getFiles())[0].length,0);
      assert.equal((await db.ref().get()).val(),null);
      env=await initializeTestEnvironment({projectId,
        database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',rules),'utf8')},
        storage:{host:'127.0.0.1',port:9199,rules:fs.readFileSync(path.join(__dirname,'../../storage.rules'),'utf8')}});
    });
    after(async()=>{for(const c of clients)await deleteApp(c.app);await env?.cleanup();await server?.delete();});
    it('registers, discovers, staffs two isolated positions, assigns/revokes and deletes through real server contracts',async()=>{
      const a=await client('a');assert.equal(a.auth.currentUser,null);
      await createUserWithEmailAndPassword(a.auth,a.email,'local-test-password');const uidA=a.auth.currentUser.uid;
      await assertSucceeds(write(a,`users/${uidA}/info`,{DisplayName:'Release A',Email:a.email,MainInstrument:'Guitar'}));
      const publicA=await until(`publicUserProfiles/${uidA}`,v=>v?.DisplayName==='Release A');assert(!('Email' in publicA));
      await signOut(a.auth);
      await assert.rejects(signInWithEmailAndPassword(a.auth,a.email,'wrong-password'),e=>e.code.startsWith('auth/'));
      assert.equal(a.auth.currentUser,null);
      await signInWithEmailAndPassword(a.auth,a.email,'local-test-password');
      assert.equal((await read(a,`userBandMembershipIndex/${uidA}`)).exists(),false);
      const band='release_band',event='release_event';
      await call(a,'mutateBandMembership',{action:'create',bandId:band,operationId:'create',metadata:{Name:'Release Band'}});
      const roster=(await db.ref(`Bands/${band}/Members_band`).get()).val();
      assert.deepEqual(Object.keys(roster),[uidA]);assert.equal(roster[uidA].Role,'Leader');assert.equal(roster[uidA].Status,'active');
      await until(`publicBandProfiles/${band}`,v=>v?.Name==='Release Band');
      const b=await client('b');await createUserWithEmailAndPassword(b.auth,b.email,'local-test-password');const uidB=b.auth.currentUser.uid;
      await write(b,`users/${uidB}/info`,{DisplayName:'Release B',MainInstrument:'Guitar',Instruments:['Guitar','Bass']});
      await until(`publicUserProfiles/${uidB}`,v=>v?.DisplayName==='Release B');
      await call(a,'mutateBandMembership',{action:'add',bandId:band,userId:uidB,role:'Member',operationId:'add'});
      await until(`userBandMembershipIndex/${uidB}/${band}`,v=>v===true);
      await assertSucceeds(read(b,`publicBandProfiles/${band}`));
      await assertFails(read(b,`users/${uidA}/info`));
      // Public visibility never grants edit/delete ownership. Missing ownership
      // fails closed, including old orphan records; client transfer is forbidden.
      const publicPath='PublicEvents/release_public_ownership';
      const publicRecord={title:'Public release event',createdBy:uidA};
      await assertFails(write(a,publicPath,{title:'Missing owner'}));
      await assertFails(write(b,publicPath,publicRecord));
      await assertSucceeds(write(a,publicPath,publicRecord));
      await assertSucceeds(read(b,publicPath));
      await assertFails(write(b,publicPath,{...publicRecord,title:'Forged edit'}));
      await assertFails(write(b,publicPath,null));
      await assertFails(write(a,publicPath,{...publicRecord,createdBy:uidB}));
      await assertFails(write(a,publicPath,{title:'Removed owner'}));
      await assertSucceeds(write(a,publicPath,{...publicRecord,title:'Owner edit'}));
      await assertSucceeds(write(a,publicPath,null));
      await db.ref(publicPath).set({title:'Unproven legacy owner'});
      await assertFails(write(a,publicPath,publicRecord));
      await assertFails(write(b,publicPath,null));
      await db.ref(publicPath).remove();

      await call(a,'mutateBandEvent',{action:'save',bandId:band,eventId:event,event:{title:'Release concert',startDateTime:'2099-12-01T18:00:00Z',endDateTime:'2099-12-01T21:00:00Z'}});
      for(const p of [`bandMemberEvents/${band}/${event}`,`bandManagerEvents/${band}/${event}`])await until(p,v=>v?.title==='Release concert');
      // The own-user overlay is sparse: no RSVP, exclusion or invitation means
      // no private overlay yet. Ordinary event details come from the member model.
      assert.equal((await read(b,`userEventReadModels/${uidB}/${band}/${event}`)).exists(),false);
      await call(a,'mutateBandEvent',{action:'saveCalendar',bandId:band,eventId:'calendar',event:{Title:'Release calendar',Date:'2099-12-01'}});
      await until(`bandMemberCalendarEvents/${band}/calendar`,v=>v?.Title==='Release calendar');
      await write(a,`Bands/${band}/Events/${event}/Responses/${uidA}`,{status:'YES',timestamp:'2099-01-01T00:00:00Z',comment:'A private comment'});
      await write(b,`Bands/${band}/Events/${event}/Responses/${uidB}`,{status:'YES',timestamp:'2099-01-01T00:00:00Z',comment:'B private comment'});
      const own=await until(`userEventReadModels/${uidB}/${band}/${event}`,v=>v?.Responses?.[uidB]?.status==='YES');
      assert(!JSON.stringify(own).includes('A private comment'));
      await assertFails(read(b,`Bands/${band}/Events/${event}/Responses/${uidA}`));
      await write(a,`users/${uidA}/Favorites/${uidB}`,true);
      const one='release_slot_one',two='release_slot_two';
      await call(a,'publishSubRequestGroup',{bandId:band,requestGroupId:'release_group',slots:[
        {subRequestId:one,slotId:one,eventId:event,voicePart:'Guitar',searchSource:'search_all',date:'2099-12-01'},
        {subRequestId:two,slotId:two,eventId:event,voicePart:'Bass',searchSource:'favorites',targetUserIds:[uidB],date:'2099-12-01'}]});
      assert((await read(b,`publicSubRequests/${one}`)).exists());assert(!(await read(b,`publicSubRequests/${two}`)).exists());
      assert((await read(b,`userSubRequestFeed/${uidB}/${two}`)).exists());
      for(const id of [one,two])assert((await read(a,`creatorSubRequestFeed/${uidA}/${id}`)).exists());
      await call(b,'respondToSubRequest',{subRequestId:one});
      assert((await read(b,`users/${uidB}/AppliedSubRequests/${one}`)).exists());
      assert(!(await read(b,`SubRequests/${two}/Responses/${uidB}`)).exists());
      await assertFails(read(b,`SubRequests/${one}/Responses`));await assertSucceeds(read(a,`SubRequests/${one}/Responses`));
      await assert.rejects(call(b,'assignSubstitute',{subRequestId:one,candidateUserId:uidB}),e=>e.code==='functions/permission-denied');
      const assigned=await call(a,'assignSubstitute',{subRequestId:one,candidateUserId:uidB});
      assert.equal(assigned.status,'assigned');assert(assigned.conversationId);
      assert(!(await read(b,`userSubRequestFeed/${uidB}/${one}`)).exists());assert(!(await read(b,`publicSubRequests/${one}`)).exists());
      assert((await read(b,`userSubRequestFeed/${uidB}/${two}`)).exists());
      const agreement=(await read(b,`conversations/${assigned.conversationId}/agreement`)).val();assert(agreement);
      assert.equal((await call(a,'assignSubstitute',{subRequestId:one,candidateUserId:uidB})).conversationId,assigned.conversationId);
      await call(a,'revokeSubstituteAssignment',{subRequestId:one,candidateUserId:uidB,bandId:band,eventId:event,slotId:one});
      assert.equal((await db.ref(`SubRequests/${one}/Status`).get()).val(),'published');
      assert.equal((await call(a,'assignSubstitute',{subRequestId:one,candidateUserId:uidB})).conversationId,assigned.conversationId);
      const picture=storageRef(b.storage,`publicMedia/profilePictures/${uidB}/avatar.jpg`);
      await uploadBytes(picture,Buffer.from('public profile fixture'));await deleteObject(picture);
      await signOut(b.auth);await assertFails(read(b,`userEventReadModels/${uidB}/${band}/${event}`));
      await signInWithEmailAndPassword(b.auth,a.email,'local-test-password');
      await assertFails(read(b,`userEventReadModels/${uidB}/${band}/${event}`));
      await signOut(b.auth);await signInWithEmailAndPassword(b.auth,b.email,'local-test-password');
      await call(b,'deleteUserAccount',{});
      await assert.rejects(server.auth().getUser(uidB),e=>e.code==='auth/user-not-found');
      await call(a,'deleteBand',{bandId:band});assert(!(await db.ref(`Bands/${band}`).get()).exists());
      await call(a,'deleteUserAccount',{});await assert.rejects(server.auth().getUser(uidA),e=>e.code==='auth/user-not-found');
      for(const uid of [uidA,uidB])for(const legacy of ['Bands','SubRequests','Agreements'])
        assert(!(await db.ref(`users/${uid}/${legacy}`).get()).exists());
      assert(!(await db.ref('BandEvents').get()).exists());
    });
  });
}
