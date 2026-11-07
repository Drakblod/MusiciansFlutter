'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const authority = require('../membership_authority');

for (const ruleFile of ['database.rules.json','database.transitional.rules.json']) {
  describe(`AUTH-FEEDBACK-AND-MANAGE-GUARD-01 ${ruleFile}`, function() {
    this.timeout(30000);
    let env;
    const band='auth_guard_band', other='auth_guard_other';
    const uid='auth_guard_owner', applicant='auth_guard_applicant';
    const request='auth_guard_request';
    const record={BandId:band,CreatorUserId:uid,Responses:{[applicant]:{comment:'private'}}};
    const dbFor = id => (id ? env.authenticatedContext(id) : env.unauthenticatedContext()).database();
    async function seed(member, value=record) {
      await env.withSecurityRulesDisabled(async context => {
        const db=context.database();
        await db.ref(`Bands/${band}`).set({Name:'Guard band',Members_band:member ? {[uid]:member}:null});
        await db.ref(`SubRequests/${request}`).set(value);
      });
    }
    before(async()=>{
      env=await initializeTestEnvironment({projectId:'demo-auth-manage-guard',database:{host:'127.0.0.1',port:9000,rules:fs.readFileSync(path.join(__dirname,'../..',ruleFile),'utf8')}});
    });
    after(async()=>env.cleanup());
    for (const role of ['Leader','Admin']) it(`active exact-band ${role} reads canonical request and aggregate`,async()=>{
      await seed({Role:role,Status:'active'});
      await assertSucceeds(dbFor(uid).ref(`SubRequests/${request}`).get());
      await assertSucceeds(dbFor(uid).ref(`SubRequests/${request}/Responses`).get());
    });
    for (const [name,member] of [
      ['ordinary Member',{Role:'Member',Status:'active'}],
      ['inactive creator',{Role:'Leader',Status:'inactive'}],
      ['removed creator',null],
      ['demoted creator',{Role:'Member',Status:'active'}],
      ['conflicting roles',{Role:'Member',role:'Admin',Status:'active'}],
      ['conflicting statuses',{Role:'Leader',Status:'active',status:'inactive'}],
    ]) it(`${name} cannot read canonical request or aggregate`,async()=>{
      await seed(member);
      await assertFails(dbFor(uid).ref(`SubRequests/${request}`).get());
      await assertFails(dbFor(uid).ref(`SubRequests/${request}/Responses`).get());
    });
    for(const who of ['auth_guard_outsider',null]) it(`${who || 'signed-out'} is denied`,async()=>{
      await seed({Role:'Leader',Status:'active'});
      await assertFails(dbFor(who).ref(`SubRequests/${request}`).get());
    });
    it('other-band manager has no authority',async()=>{
      await seed(null);
      await env.withSecurityRulesDisabled(c=>c.database().ref(`Bands/${other}/Members_band/${uid}`).set({Role:'Admin',Status:'active'}));
      await assertFails(dbFor(uid).ref(`SubRequests/${request}/Responses`).get());
    });
    for(const marker of ['freelance','standalone']) it(`only exact ${marker} creator manages`,async()=>{
      await seed(null,{...record,BandId:marker});
      await assertSucceeds(dbFor(uid).ref(`SubRequests/${request}/Responses`).get());
      await assertFails(dbFor('auth_guard_outsider').ref(`SubRequests/${request}/Responses`).get());
    });
    for(const [label,patch] of [
      ['missing band',{BandId:null}],['empty band',{BandId:''}],
      ['malformed band',{BandId:'bad/path'}],['ambiguous band',{bandId:'freelance'}],
      ['missing owner',{CreatorUserId:null}],['malformed owner',{CreatorUserId:{bad:true}}],
      ['conflicting owner',{creatorUserId:'another'}],
    ]) it(`${label} fails closed`,async()=>{
      await seed({Role:'Leader',Status:'active'},{...record,...patch});
      await assertFails(dbFor(uid).ref(`SubRequests/${request}/Responses`).get());
    });
    it('applicant own leaf remains isolated',async()=>{
      await seed(null);
      await assertSucceeds(dbFor(applicant).ref(`SubRequests/${request}/Responses/${applicant}`).get());
      await assertFails(dbFor(applicant).ref(`SubRequests/${request}/Responses`).get());
      await assertFails(dbFor(applicant).ref(`SubRequests/${request}/Responses/another`).get());
    });
    it('clients cannot modify ownership, band or classification',async()=>{
      await seed({Role:'Leader',Status:'active'});
      for(const [field,value] of Object.entries({BandId:'freelance',bandId:'standalone',CreatorUserId:'another',creatorUserId:'another',NotificationMode:'map_pin'}))
        await assertFails(dbFor(uid).ref(`SubRequests/${request}/${field}`).set(value));
    });
    it('server request policy denies former managers and keeps explicit freelance',async()=>{
      const db={ref:()=>({get:async()=>({val:()=>({Role:'Leader',Status:'inactive'})})})};
      await assert.rejects(authority.authorizeRequest(db,uid,record),e=>e.code==='permission-denied');
      await authority.authorizeRequest(db,uid,{...record,BandId:'freelance'});
      await assert.rejects(authority.authorizeRequest(db,uid,record,other),e=>e.code==='permission-denied');
    });
  });
}
