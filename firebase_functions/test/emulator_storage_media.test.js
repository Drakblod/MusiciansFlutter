'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, signInWithCustomToken} = require('firebase/auth');
const {ref, uploadBytes, getBytes, deleteObject} = require('firebase/storage');
const media = require('../storage_media');

describe('Production region preflight',()=>{
  const {databaseRegion} = require('../deployment_region');
  for(const env of [{},{FUNCTIONS_EMULATOR:'true'},
    {GCLOUD_PROJECT:'real-project',FUNCTIONS_EMULATOR:'true',FIREBASE_EMULATOR_HUB:'127.0.0.1:4400'},
    {GCLOUD_PROJECT:'real-project',FIREBASE_DATABASE_EMULATOR_HOST:'127.0.0.1:9000'}]) {
    it(`keeps europe-west1 for production/ambient flags ${JSON.stringify(env)}`,()=>
      assert.equal(databaseRegion(env),'europe-west1'));
  }
  it('uses emulator compatibility only for an explicit demo project and active hub',()=>{
    assert.equal(databaseRegion({GCLOUD_PROJECT:'demo-musicians-test',FUNCTIONS_EMULATOR:'true',FIREBASE_EMULATOR_HUB:'127.0.0.1:4400'}),'us-central1');
    const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
    assert.match(source,/exports\.checkEventReminders = functions\.region\('europe-west1'\)\.pubsub/);
    assert.match(source,/exports\.storageMedia = onRequest\(\{region:'europe-west1'/);
  });
});

for (const rules of ['database.rules.json', 'database.transitional.rules.json']) {
  describe(`Storage privacy ${rules}`, function() {
    this.timeout(120000);
    const projectId = 'demo-musicians-test';
    const tag = rules.includes('transitional') ? 't' : 'f';
    const bandId = `media_band_${tag}`;
    const uids = ['owner','member','admin','outsider'].map(role => `media_${tag}_${role}`);
    const tokens = {}, apps = [];
    let app, db, env, object;
    const bytes = Buffer.from('private score');
    async function request(uid, method, query, body, range) {
      const url = new URL(`http://127.0.0.1:5001/${projectId}/europe-west1/storageMedia`);
      for (const [k,v] of Object.entries(query)) url.searchParams.set(k,v);
      const headers = uid ? {Authorization:`Bearer ${tokens[uid]}`} : {};
      if(range)headers.Range=range;
      if (body) headers['Content-Type'] = Buffer.isBuffer(body) ? 'application/octet-stream' : 'application/json';
      return fetch(url, {method, headers, body:body ? Buffer.isBuffer(body) ? body : JSON.stringify(body) : undefined});
    }
    async function upload(kind='band', owner=uids[0], selectedBand=bandId) {
      let response = await request(owner,'POST',{action:'begin'}, {
        kind, bandId:selectedBand, fileName:'score.pdf', contentType:'application/pdf',byteLength:bytes.length});
      assert.equal(response.status,200,await response.clone().text());
      const {id,chunkBytes} = await response.json();
      assert.equal(chunkBytes,media.CHUNK_BYTES);
      response=await request(owner,'PUT',{action:'part',id,index:'0'},bytes);
      assert.equal(response.status,200);
      response=await request(owner,'POST',{action:'finish',id});
      assert.equal(response.status,200,await response.clone().text());
      return id;
    }
    before(async()=>{
      assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST,'127.0.0.1:9199');
      app=admin.initializeApp({projectId,databaseURL:`http://127.0.0.1:9000?ns=${projectId}`},`media_${tag}`);
      db=app.database();
      env=await initializeTestEnvironment({projectId,
        database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',rules),'utf8')},
        storage:{host:'127.0.0.1',port:9199,rules:fs.readFileSync(path.join(__dirname,'../../storage.rules'),'utf8')}});
      for(const uid of uids) {
        await app.auth().createUser({uid});
        const client=initializeApp({projectId,apiKey:'emulator-only'},uid);apps.push(client);
        const auth=getAuth(client);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
        const user=await signInWithCustomToken(auth,await app.auth().createCustomToken(uid));
        tokens[uid]=await user.user.getIdToken();
      }
      await db.ref(`Bands/${bandId}`).set({Name:'Private file band',Members_band:{
        [uids[0]]:{Role:'Leader',Status:'active'},[uids[1]]:{Role:'Member',Status:'active'},
        [uids[2]]:{Role:'Admin',Status:'active'}}});
    });
    after(async()=>{for(const client of apps)await deleteApp(client);await env.cleanup();await app.delete();});

    for(const kind of ['profilePictures','profileAudio','marketplaceImages','publicEventImages']) {
      it(`${kind}: public reads, exact owner upload/delete, cross-owner denied`,async()=>{
        const p=`publicMedia/${kind}/${uids[0]}/file`;
        const owner=ref(env.authenticatedContext(uids[0]).storage(),p);
        const other=ref(env.authenticatedContext(uids[3]).storage(),p);
        await assertSucceeds(uploadBytes(owner,bytes));
        assert.deepEqual(Buffer.from(await getBytes(ref(env.unauthenticatedContext().storage(),p))),bytes);
        await assertFails(uploadBytes(other,bytes));await assertFails(deleteObject(other));
        await assertSucceeds(deleteObject(owner));
      });
    }
    it('private/unknown Storage paths cannot be written or read directly by any client',async()=>{
      for(const prefix of ['bandFiles','profileAudio','privateMedia','privateMediaParts','unknown']) {
        const file=ref(env.authenticatedContext(uids[0]).storage(),`${prefix}/${uids[0]}/file`);
        await assertFails(uploadBytes(file,bytes));await assertFails(getBytes(file));
      }
    });
    it('uploads and registers private files without public tokens, and retries are idempotent',async()=>{
      object=await upload();
      for(let i=0;i<2;i++) {
        assert.equal((await request(uids[0],'POST',{action:'finish',id:object})).status,200);
        assert.equal((await request(uids[0],'POST',{action:'register-band-file',id:object}, {bandId,category:'scores'})).status,200);
      }
      const files=(await db.ref(`files/${bandId}`).get()).val();
      assert.deepEqual(Object.keys(files),[object]);assert.equal(files[object].FileUrl,`secure-media:${object}`);
      const response=await request(uids[1],'GET',{id:object});assert.equal(response.status,200);
      assert.equal(response.headers.get('cache-control'),'private, no-store');
      assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);
      const partial=await request(uids[1],'GET',{id:object},null,'bytes=2-5');
      assert.equal(partial.status,206);assert.equal(partial.headers.get('content-range'),`bytes 2-5/${bytes.length}`);
      assert.deepEqual(Buffer.from(await partial.arrayBuffer()),bytes.subarray(2,6));
      assert.equal((await request(uids[1],'GET',{id:object},null,'bytes=999-')).status,416);
    });
    it('anonymous, unrelated and removed members cannot read, forge metadata or upload',async()=>{
      for(const uid of [null,uids[3]]) assert.equal((await request(uid,'GET',{id:object})).status,403);
      await db.ref(`Bands/${bandId}/Members_band/${uids[1]}/Status`).set('removed');
      assert.equal((await request(uids[1],'GET',{id:object})).status,403);
      for(const p of [`files/${bandId}/${object}`,`storageMediaObjects/${object}`,`storageUploadSessions/${object}`])
        await assertFails(env.authenticatedContext(uids[0]).database().ref(p).set({ownerId:uids[0]}));
      await db.ref(`Bands/${bandId}/Members_band/${uids[1]}/Status`).set('active');
    });
    it('only uploader or current exact-band manager may delete a band object',async()=>{
      assert.equal((await request(uids[1],'DELETE',{id:object})).status,403);
      await db.ref(`Bands/${bandId}/Members_band/${uids[2]}/Status`).set('inactive');
      assert.equal((await request(uids[2],'DELETE',{id:object})).status,403);
      await db.ref(`Bands/${bandId}/Members_band/${uids[2]}/Status`).set('active');
      assert.equal((await request(uids[2],'DELETE',{id:object})).status,200);
      assert.equal((await request(uids[0],'GET',{id:object})).status,403);
    });
    it('Map draft is private until authoritative publication; revocation closes public reads',async()=>{
      const id=await upload('map',uids[0],null);
      assert.equal((await request(null,'GET',{id})).status,403);
      assert.equal((await request(uids[3],'GET',{id})).status,403);
      await assert.rejects(media.bindMap(db,uids[3],'pin',null,`secure-media:${id}`,projectId));
      const binding=await media.bindMap(db,uids[0],`media_pin_${tag}`,null,`secure-media:${id}`,projectId);
      await db.ref().update({[binding.path]:`media_pin_${tag}`,[`SubRequests/media_pin_${tag}`]:{
        NotificationMode:'map_pin',Status:'published',MediaObjectId:id,CreatorUserId:uids[0]}});
      assert.equal((await request(null,'GET',{id})).status,200);
      assert.equal((await request(uids[3],'DELETE',{id})).status,403);
      await db.ref(`SubRequests/media_pin_${tag}/Status`).set('draft');
      assert.equal((await request(null,'GET',{id})).status,403);
      assert.equal((await request(uids[0],'DELETE',{id})).status,200);
    });
    it('band Map audio requires current canonical management, never creator or stale role alone',async()=>{
      const id=await upload('map');
      assert.equal((await request(uids[1],'DELETE',{id})).status,403);
      await db.ref(`Bands/${bandId}/Members_band/${uids[0]}/Status`).set('removed');
      assert.equal((await request(uids[0],'DELETE',{id})).status,403);
      assert.equal((await request(uids[2],'DELETE',{id})).status,200);
      await db.ref(`Bands/${bandId}/Members_band/${uids[0]}/Status`).set('active');
    });
  });
}
