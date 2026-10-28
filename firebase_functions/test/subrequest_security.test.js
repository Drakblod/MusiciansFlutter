const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-musicians-test';
const DB_PORT = 9000;

describe('SUBREQUEST-SECURITY-MIGRATION-01: Permanent Security Rules & Feed Isolation Tests', function () {
  this.timeout(20000);

  let testEnv;
  const creatorUid = 'creator_alice';
  const targetUid = 'target_bob';
  const unrelatedUid = 'unrelated_eve';

  before(async function () {
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';

    const rules = fs.readFileSync(
      path.join(__dirname, '../../database.rules.json'),
      'utf8'
    );

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      database: {
        host: '127.0.0.1',
        port: DB_PORT,
        rules: rules,
      },
    });

    // Seed test fixtures via Admin SDK (bypasses rules)
    await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
      const db = adminCtx.database();
      await db.ref().set(null);

      // 1. Public staffing request
      await db.ref('SubRequests/sub_pub_1').set({
        SubRequestId: 'sub_pub_1',
        CreatorUserId: creatorUid,
        VoicePart: 'Drums',
        Status: 'published',
        SearchSource: 'search_all',
        IsPaid: true,
        PayAmount: 1500,
      });
      await db.ref('publicSubRequests/sub_pub_1').set({
        subRequestId: 'sub_pub_1',
        creatorUserId: creatorUid,
        voicePart: 'Drums',
        status: 'published',
      });
      await db.ref(`creatorSubRequestFeed/${creatorUid}/sub_pub_1`).set({
        subRequestId: 'sub_pub_1',
        creatorUserId: creatorUid,
        voicePart: 'Drums',
        status: 'published',
      });

      // 2. Direct Invitation
      await db.ref('SubRequests/sub_direct_2').set({
        SubRequestId: 'sub_direct_2',
        CreatorUserId: creatorUid,
        VoicePart: 'Bass',
        Status: 'published',
        SearchSource: 'favorites',
        TargetUserIds: [targetUid],
      });
      await db.ref(`subRequestAudience/sub_direct_2/${targetUid}`).set(true);
      await db.ref(`userSubRequestFeed/${targetUid}/sub_direct_2`).set({
        subRequestId: 'sub_direct_2',
        creatorUserId: creatorUid,
        voicePart: 'Bass',
        status: 'published',
      });
      await db.ref(`creatorSubRequestFeed/${creatorUid}/sub_direct_2`).set({
        subRequestId: 'sub_direct_2',
        creatorUserId: creatorUid,
        voicePart: 'Bass',
        status: 'published',
      });

      // 3. Favorites-only request
      await db.ref('SubRequests/sub_fav_3').set({
        SubRequestId: 'sub_fav_3',
        CreatorUserId: creatorUid,
        VoicePart: 'Guitar',
        Status: 'published',
        SearchSource: 'favorites',
        TargetUserIds: [targetUid],
      });
      await db.ref(`subRequestAudience/sub_fav_3/${targetUid}`).set(true);
      await db.ref(`userSubRequestFeed/${targetUid}/sub_fav_3`).set({
        subRequestId: 'sub_fav_3',
        creatorUserId: creatorUid,
        voicePart: 'Guitar',
        status: 'published',
      });
      await db.ref(`creatorSubRequestFeed/${creatorUid}/sub_fav_3`).set({
        subRequestId: 'sub_fav_3',
        creatorUserId: creatorUid,
        voicePart: 'Guitar',
        status: 'published',
      });

      // 4. Map Pin (Music Promotion)
      await db.ref('SubRequests/pin_promo_4').set({
        SubRequestId: 'pin_promo_4',
        CreatorUserId: creatorUid,
        NotificationMode: 'map_pin',
        subCategory: 'Music',
        eventType: 'gigConcert',
        Latitude: 59.33,
        Longitude: 18.06,
        Status: 'published',
      });

      // 5. Cancelled/legacy items in legacy path
      await db.ref('BandEvents/PublishedSubRequests/sub_legacy_5').set({
        SubRequestId: 'sub_legacy_5',
        CreatorUserId: creatorUid,
        VoicePart: 'Saxophone',
      });
      await db.ref('BandEvents/CancelledSubRequests/sub_legacy_5').set(true);
    });
  });

  after(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  it('1. Authenticated users CAN read publicSubRequests', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    const ref = eveCtx.database().ref('publicSubRequests/sub_pub_1');
    await assertSucceeds(ref.get());
  });

  it('2. Unauthenticated users CANNOT read publicSubRequests', async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const ref = unauthCtx.database().ref('publicSubRequests/sub_pub_1');
    await assertFails(ref.get());
  });

  it('3. Private Direct and Favorites requests are NEVER in publicSubRequests', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    const directSnap = await eveCtx.database().ref('publicSubRequests/sub_direct_2').get();
    assert.strictEqual(directSnap.exists(), false);
    const favSnap = await eveCtx.database().ref('publicSubRequests/sub_fav_3').get();
    assert.strictEqual(favSnap.exists(), false);
  });

  it('4. Target user CAN read targeted request in userSubRequestFeed', async () => {
    const bobCtx = testEnv.authenticatedContext(targetUid);
    const ref = bobCtx.database().ref(`userSubRequestFeed/${targetUid}/sub_direct_2`);
    await assertSucceeds(ref.get());
  });

  it('5. Unrelated user CANNOT read other userSubRequestFeed', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    const ref = eveCtx.database().ref(`userSubRequestFeed/${targetUid}/sub_direct_2`);
    await assertFails(ref.get());
  });

  it('6. Creator CAN read own requests in creatorSubRequestFeed', async () => {
    const aliceCtx = testEnv.authenticatedContext(creatorUid);
    const ref = aliceCtx.database().ref(`creatorSubRequestFeed/${creatorUid}/sub_direct_2`);
    await assertSucceeds(ref.get());
  });

  it('7. Unrelated user CANNOT read other user creatorSubRequestFeed', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    const ref = eveCtx.database().ref(`creatorSubRequestFeed/${creatorUid}/sub_direct_2`);
    await assertFails(ref.get());
  });

  it('8. Clients CANNOT write to publicSubRequests', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    const ref = eveCtx.database().ref('publicSubRequests/injected_req');
    await assertFails(ref.set({ title: 'Hacked' }));
  });

  it('9. Clients CANNOT write to userSubRequestFeed', async () => {
    const bobCtx = testEnv.authenticatedContext(targetUid);
    const ref = bobCtx.database().ref(`userSubRequestFeed/${targetUid}/injected_req`);
    await assertFails(ref.set({ title: 'Hacked' }));
  });

  it('10. Clients CANNOT write to creatorSubRequestFeed', async () => {
    const aliceCtx = testEnv.authenticatedContext(creatorUid);
    const ref = aliceCtx.database().ref(`creatorSubRequestFeed/${creatorUid}/injected_req`);
    await assertFails(ref.set({ title: 'Hacked' }));
  });

  it('11. Clients CANNOT read or write subRequestAudience', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    await assertFails(eveCtx.database().ref('subRequestAudience/sub_direct_2').get());
    await assertFails(eveCtx.database().ref('subRequestAudience/sub_direct_2/eve').set(true));
  });

  it('12. Legacy mirrors BandEvents/PublishedSubRequests CANNOT be read or written by clients', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    await assertFails(eveCtx.database().ref('BandEvents/PublishedSubRequests').get());
    await assertFails(eveCtx.database().ref('BandEvents/PublishedSubRequests/sub_legacy_5').get());
    await assertFails(eveCtx.database().ref('BandEvents/PublishedSubRequests/sub_hack').set({ title: 'Hack' }));
  });

  it('13. Legacy mirrors BandEvents/CancelledSubRequests CANNOT be read or written by clients', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    await assertFails(eveCtx.database().ref('BandEvents/CancelledSubRequests').get());
    await assertFails(eveCtx.database().ref('BandEvents/CancelledSubRequests/sub_legacy_5').get());
    await assertFails(eveCtx.database().ref('BandEvents/CancelledSubRequests/sub_hack').set(true));
  });

  it('14. Other BandEvents paths (Agreements, Notifications, Responses, bandId) remain accessible', async () => {
    const eveCtx = testEnv.authenticatedContext(unrelatedUid);
    // Agreements
    await assertSucceeds(eveCtx.database().ref('BandEvents/Agreements/conv_123').get());
    // Notifications for own UID
    await assertSucceeds(eveCtx.database().ref(`BandEvents/Notifications/${unrelatedUid}`).get());
    // SubRequestResponses
    await assertSucceeds(eveCtx.database().ref('BandEvents/SubRequestResponses/sub_pub_1').get());
  });
});
