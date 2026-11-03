const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

describe('Membership index permissions in both rule sets', function () {
  this.timeout(15000);
  for (const file of ['database.rules.json', 'database.transitional.rules.json']) {
    describe(file, () => {
      let env;
      before(async () => {
        env = await initializeTestEnvironment({ projectId: `demo-membership-${file.includes('transitional') ? 'transitional' : 'final'}`,
          database: { host: '127.0.0.1', port: 9000, rules: fs.readFileSync(path.join(__dirname, '../..', file), 'utf8') } });
        await env.withSecurityRulesDisabled(ctx => ctx.database().ref('userBandMembershipIndex').set({ a: { band: true }, b: { band: true } }));
      });
      after(async () => { if (env) await env.cleanup(); });
      it('own read succeeds', async () => assertSucceeds(env.authenticatedContext('a').database().ref('userBandMembershipIndex/a').get()));
      it('other user and root enumeration fail', async () => {
        const db = env.authenticatedContext('a').database();
        await assertFails(db.ref('userBandMembershipIndex/b').get());
        await assertFails(db.ref('userBandMembershipIndex').get());
      });
      it('unauthenticated read fails', async () => assertFails(env.unauthenticatedContext().database().ref('userBandMembershipIndex/a').get()));
      for (const uid of ['a', 'b']) {
        it(`client cannot write ${uid}`, async () => {
          const db = env.authenticatedContext('a').database();
          await assertFails(db.ref(`userBandMembershipIndex/${uid}/band`).set(true));
          await assertFails(db.ref(`userBandMembershipIndex/${uid}/band`).remove());
          await assertFails(db.ref().update({ [`userBandMembershipIndex/${uid}/band`]: true }));
        });
      }
      it('unauthenticated writes fail', async () => assertFails(env.unauthenticatedContext().database().ref('userBandMembershipIndex/a/band').set(true)));
    });
  }
});

describe('Actual canonical member trigger maintains server index', function () {
  this.timeout(40000);
  let app, db;
  const band = 'index_integration_band';
  const uid = 'index_integration_user';
  async function wait(expected) {
    const start = Date.now();
    while (Date.now() - start < 30000) {
      const value = (await db.ref(`userBandMembershipIndex/${uid}/${band}`).get()).val();
      if (value === expected) return;
      await new Promise(resolve => setTimeout(resolve, 120));
    }
    assert.fail(`Trigger did not reach ${expected}`);
  }
  before(() => {
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';
    const admin = require('firebase-admin');
    app = admin.initializeApp({ projectId: 'demo-musicians-test', databaseURL: 'http://127.0.0.1:9000?ns=demo-musicians-test' }, 'membership-index-integration');
    db = app.database();
  });
  after(async () => {
    if (db) await db.ref(`Bands/${band}`).remove();
    if (app) await app.delete();
  });
  it('add, role, inactive, restore, delete and band deletion converge', async () => {
    const member = db.ref(`Bands/${band}/Members_band/${uid}`);
    await db.ref(`Bands/${band}`).set({ Name: 'Membership integration', Members_band: { [uid]: { Role: 'Leader' } } });
    await wait(true);
    await member.child('Role').set('Member'); await wait(true);
    await member.child('Status').set('inactive'); await wait(null);
    await member.child('Status').set('active'); await wait(true);
    await member.remove(); await wait(null);
    await member.set({ Role: 'Admin', Status: 'active' }); await wait(true);
    await db.ref(`Bands/${band}`).remove(); await wait(null);
  });
});
