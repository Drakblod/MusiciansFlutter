const fs = require('fs');
const path = require('path');
const assert = require('assert');
const admin = require('firebase-admin');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

// Firebase Client SDK for Callable Functions
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithCustomToken } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');

const PROJECT_ID = 'demo-musicians-test';
const DB_HOST = '127.0.0.1';
const DB_PORT = 9000;
const AUTH_PORT = 9099;
const FUNCTIONS_PORT = 5001;

process.env.FIREBASE_DATABASE_EMULATOR_HOST = `${DB_HOST}:${DB_PORT}`;
process.env.FIREBASE_AUTH_EMULATOR_HOST = `${DB_HOST}:${AUTH_PORT}`;
process.env.FUNCTIONS_EMULATOR_HOST = `${DB_HOST}:${FUNCTIONS_PORT}`;
process.env.GCLOUD_PROJECT = PROJECT_ID;
process.env.IS_EMULATOR_TEST = 'true';

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: PROJECT_ID,
    databaseURL: `http://${DB_HOST}:${DB_PORT}?ns=${PROJECT_ID}`,
  });
}

describe('MAP-VIEW-FEED-03B: Real Firebase Emulator Security & Projection Test Suite', function () {
  this.timeout(45000);

  let testEnv;
  let adminDb;

  const userAlice = 'user_alice_creator';
  const userBob = 'user_bob_recipient';
  const userCarol = 'user_carol_unrelated';

  let clientAppAlice, clientFunctionsAlice;
  let clientAppBob, clientFunctionsBob;
  let clientAppCarol, clientFunctionsCarol;

  let createdPinId = null;

  before(async function () {
    adminDb = admin.database();

    const rules = fs.readFileSync(
      path.join(__dirname, '../../database.rules.json'),
      'utf8'
    );

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      database: {
        host: DB_HOST,
        port: DB_PORT,
        rules: rules,
      },
    });

    // Client Contexts for callables
    async function setupClient(uid) {
      const app = initializeApp({ projectId: PROJECT_ID, apiKey: 'fake-api-key' }, `client_${uid}_${Date.now()}`);
      const auth = getAuth(app);
      connectAuthEmulator(auth, `http://${DB_HOST}:${AUTH_PORT}`, { disableWarnings: true });
      const functions = getFunctions(app, 'europe-west1');
      connectFunctionsEmulator(functions, DB_HOST, FUNCTIONS_PORT);

      const token = await admin.auth().createCustomToken(uid);
      await signInWithCustomToken(auth, token);
      return { app, functions };
    }

    const aliceCtx = await setupClient(userAlice);
    clientAppAlice = aliceCtx.app;
    clientFunctionsAlice = aliceCtx.functions;

    const bobCtx = await setupClient(userBob);
    clientAppBob = bobCtx.app;
    clientFunctionsBob = bobCtx.functions;

    const carolCtx = await setupClient(userCarol);
    clientAppCarol = carolCtx.app;
    clientFunctionsCarol = carolCtx.functions;

    // Seed test fixtures via Admin SDK
    await adminDb.ref().set(null);

    // Seed seed_pin_1 in publicMapPinFeed
    await adminDb.ref('publicMapPinFeed/seed_pin_1').set({
      pinId: 'seed_pin_1',
      creatorUserId: userAlice,
      title: 'Initial Seed Map Pin',
      subCategory: 'Music',
      eventType: 'gigConcert',
      latitude: 59.33,
      longitude: 18.06,
      createdAt: Date.now(),
    });

    // 1. Canonical public staffing request
    await adminDb.ref('SubRequests/sub_pub_1').set({
      SubRequestId: 'sub_pub_1',
      CreatorUserId: userAlice,
      VoicePart: 'Drums',
      Status: 'published',
      SearchSource: 'search_all',
    });
    await adminDb.ref('publicSubRequests/sub_pub_1').set({
      subRequestId: 'sub_pub_1',
      creatorUserId: userAlice,
      voicePart: 'Drums',
      status: 'published',
    });

    // 2. Canonical Direct Invitation to Bob
    await adminDb.ref('SubRequests/sub_direct_2').set({
      SubRequestId: 'sub_direct_2',
      CreatorUserId: userAlice,
      VoicePart: 'Bass',
      Status: 'published',
      NotificationMode: 'direct',
      TargetUserIds: [userBob],
    });
    await adminDb.ref(`subRequestAudience/sub_direct_2/${userBob}`).set(true);
    await adminDb.ref(`userSubRequestFeed/${userBob}/sub_direct_2`).set({
      subRequestId: 'sub_direct_2',
      creatorUserId: userAlice,
      voicePart: 'Bass',
    });

    // 3. Canonical Favorites-only request to Bob
    await adminDb.ref('SubRequests/sub_fav_3').set({
      SubRequestId: 'sub_fav_3',
      CreatorUserId: userAlice,
      VoicePart: 'Guitar',
      Status: 'published',
      SearchSource: 'favorites',
      NotificationMode: 'favorites',
      TargetUserIds: [userBob],
    });
    await adminDb.ref(`subRequestAudience/sub_fav_3/${userBob}`).set(true);
    await adminDb.ref(`userSubRequestFeed/${userBob}/sub_fav_3`).set({
      subRequestId: 'sub_fav_3',
      creatorUserId: userAlice,
      voicePart: 'Guitar',
    });
  });

  after(async function () {
    if (clientAppAlice) await deleteApp(clientAppAlice).catch(() => {});
    if (clientAppBob) await deleteApp(clientAppBob).catch(() => {});
    if (clientAppCarol) await deleteApp(clientAppCarol).catch(() => {});
    if (testEnv) await testEnv.cleanup();
  });

  // 1. Authenticated user can read publicMapPinFeed
  it('1. Authenticated user can read publicMapPinFeed', async () => {
    const carolCtx = testEnv.authenticatedContext(userCarol);
    const ref = carolCtx.database().ref('publicMapPinFeed/seed_pin_1');
    await assertSucceeds(ref.get());
  });

  // 2. Unauthenticated user cannot read it
  it('2. Unauthenticated user cannot read publicMapPinFeed', async () => {
    const unauthCtx = testEnv.unauthenticatedContext();
    const ref = unauthCtx.database().ref('publicMapPinFeed/seed_pin_1');
    await assertFails(ref.get());
  });

  // 3. Client cannot create a projection
  it('3. Client cannot create a projection in publicMapPinFeed', async () => {
    const aliceCtx = testEnv.authenticatedContext(userAlice);
    const ref = aliceCtx.database().ref('publicMapPinFeed/injected_pin');
    await assertFails(ref.set({ pinId: 'injected_pin', title: 'Hacked' }));
  });

  // 4. Client cannot update a projection
  it('4. Client cannot update a projection in publicMapPinFeed', async () => {
    const aliceCtx = testEnv.authenticatedContext(userAlice);
    const ref = aliceCtx.database().ref('publicMapPinFeed/seed_pin_1/title');
    await assertFails(ref.set('Hacked Title'));
  });

  // 5. Client cannot delete a projection
  it('5. Client cannot delete a projection in publicMapPinFeed', async () => {
    const aliceCtx = testEnv.authenticatedContext(userAlice);
    const ref = aliceCtx.database().ref('publicMapPinFeed/seed_pin_1');
    await assertFails(ref.remove());
  });

  // 6. createMapPin creates canonical plus one sanitized projection
  it('6. createMapPin creates canonical plus one sanitized projection', async () => {
    const createCallable = httpsCallable(clientFunctionsAlice, 'createMapPin');
    const result = await createCallable({
      eventType: 'gigConcert',
      latitude: 59.332,
      longitude: 18.064,
      title: 'Alice Live Showcase',
      venue: 'Stockholm Hall',
      city: 'Stockholm',
      genre: 'Jazz',
      description: 'Public music showcase',
      date: '2026-11-15',
      startTime: '20:00',
      endTime: '23:00',
      audioSnippetUrl: 'https://example.com/audio.mp3',
      audioSnippetTitle: 'Jazz Solo',
    });

    assert.strictEqual(result.data.success, true);
    createdPinId = result.data.id;
    assert.ok(createdPinId, 'Pin ID must be generated');

    const canonicalSnap = await adminDb.ref(`SubRequests/${createdPinId}`).get();
    assert.strictEqual(canonicalSnap.exists(), true);
    assert.strictEqual(canonicalSnap.val().NotificationMode, 'map_pin');

    const projectionSnap = await adminDb.ref(`publicMapPinFeed/${createdPinId}`).get();
    assert.strictEqual(projectionSnap.exists(), true);
    assert.strictEqual(projectionSnap.val().title, 'Alice Live Showcase');
  });

  // 7. Projection contains only allowlisted fields
  it('7. Projection contains only allowlisted fields', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');
    const projectionSnap = await adminDb.ref(`publicMapPinFeed/${createdPinId}`).get();
    const projection = projectionSnap.val();

    const ALLOWED_PROJECTION_KEYS = new Set([
      'id', 'pinId', 'subRequestId', 'mapItemId', 'creatorUserId',
      'status', 'NotificationMode', 'notificationMode', 'subCategory', 'eventType',
      'latitude', 'longitude', 'Latitude', 'Longitude', 'createdAt', 'updatedAt',
      'title', 'Title', 'bandName', 'BandName', 'bandId', 'BandId',
      'description', 'Description', 'location', 'Location',
      'venue', 'city', 'genre', 'style', 'Style', 'date', 'Date',
      'startTime', 'StartTime', 'endTime', 'EndTime',
      'audioSnippetUrl', 'audioSnippetTitle', 'infoAudioTrack', 'locationPrecision',
    ]);

    for (const key of Object.keys(projection)) {
      assert.ok(
        ALLOWED_PROJECTION_KEYS.has(key),
        `Unexpected non-allowlisted field in projection: ${key}`
      );
    }

    // Explicitly verify sensitive/staffing fields are NOT present
    assert.strictEqual(projection.SearchSource, undefined);
    assert.strictEqual(projection.TargetUserIds, undefined);
    assert.strictEqual(projection.targetUserIds, undefined);
    assert.strictEqual(projection.Responses, undefined);
    assert.strictEqual(projection.applicants, undefined);
    assert.strictEqual(projection.audience, undefined);
    assert.strictEqual(projection.email, undefined);
    assert.strictEqual(projection.phone, undefined);
    assert.strictEqual(projection.token, undefined);
  });

  // 8. Map pin creates zero staffing-feed records
  it('8. Map pin creates zero staffing-feed records', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');

    const pubSubSnap = await adminDb.ref(`publicSubRequests/${createdPinId}`).get();
    assert.strictEqual(pubSubSnap.exists(), false, 'Map pin must NOT exist in publicSubRequests');

    const userFeedSnap = await adminDb.ref(`userSubRequestFeed/${userBob}/${createdPinId}`).get();
    assert.strictEqual(userFeedSnap.exists(), false, 'Map pin must NOT exist in userSubRequestFeed');

    const creatorFeedSnap = await adminDb.ref(`creatorSubRequestFeed/${userAlice}/${createdPinId}`).get();
    assert.strictEqual(creatorFeedSnap.exists(), false, 'Map pin must NOT exist in creatorSubRequestFeed');
  });

  // 9. Map pin creates zero staffing notifications
  it('9. Map pin creates zero staffing notifications', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');

    const legacyMirror = await adminDb.ref(`BandEvents/PublishedSubRequests/${createdPinId}`).get();
    assert.strictEqual(legacyMirror.exists(), false, 'Map pin must NOT exist in PublishedSubRequests');

    const audienceSnap = await adminDb.ref(`subRequestAudience/${createdPinId}`).get();
    assert.strictEqual(audienceSnap.exists(), false, 'Map pin must NOT exist in subRequestAudience');

    const notifAlice = await adminDb.ref(`BandEvents/Notifications/${userAlice}/${createdPinId}`).get();
    assert.strictEqual(notifAlice.exists(), false, 'Map pin must NOT create staffing notifications');

    const notifBob = await adminDb.ref(`BandEvents/Notifications/${userBob}/${createdPinId}`).get();
    assert.strictEqual(notifBob.exists(), false, 'Map pin must NOT create staffing notifications');
  });

  // 10. updateMapPin updates exactly one projection
  it('10. updateMapPin updates exactly one projection', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');
    const updateCallable = httpsCallable(clientFunctionsAlice, 'updateMapPin');

    const updateRes = await updateCallable({
      pinId: createdPinId,
      title: 'Alice Updated Showcase',
      venue: 'Stockholm Grand Arena',
    });
    assert.strictEqual(updateRes.data.success, true);

    const canonicalSnap = await adminDb.ref(`SubRequests/${createdPinId}`).get();
    assert.strictEqual(canonicalSnap.val().title, 'Alice Updated Showcase');
    assert.strictEqual(canonicalSnap.val().venue, 'Stockholm Grand Arena');

    const projectionSnap = await adminDb.ref(`publicMapPinFeed/${createdPinId}`).get();
    assert.strictEqual(projectionSnap.val().title, 'Alice Updated Showcase');
    assert.strictEqual(projectionSnap.val().venue, 'Stockholm Grand Arena');
  });

  // 11. deleteMapPin removes projection
  it('11. deleteMapPin removes projection', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');
    const deleteCallable = httpsCallable(clientFunctionsAlice, 'deleteMapPin');

    const deleteRes = await deleteCallable({ pinId: createdPinId });
    assert.strictEqual(deleteRes.data.success, true);

    const canonicalSnap = await adminDb.ref(`SubRequests/${createdPinId}`).get();
    assert.strictEqual(canonicalSnap.exists(), false, 'Canonical record must be deleted');

    const projectionSnap = await adminDb.ref(`publicMapPinFeed/${createdPinId}`).get();
    assert.strictEqual(projectionSnap.exists(), false, 'Projection record must be deleted');
  });

  // 12. Retry remains idempotent
  it('12. deleteMapPin retry remains idempotent', async () => {
    assert.ok(createdPinId, 'createdPinId must be set');
    const deleteCallable = httpsCallable(clientFunctionsAlice, 'deleteMapPin');

    const retryRes = await deleteCallable({ pinId: createdPinId });
    assert.strictEqual(retryRes.data.success, true);
    assert.strictEqual(retryRes.data.alreadyDeleted, true);
  });

  // 13. Unauthorized user cannot update/delete another creator’s pin
  it('13. Unauthorized user cannot update/delete another creator’s pin', async () => {
    const createCallable = httpsCallable(clientFunctionsAlice, 'createMapPin');
    const newPin = await createCallable({
      eventType: 'jamSession',
      latitude: 59.33,
      longitude: 18.06,
      title: 'Protected Alice Jam',
    });
    const pinId = newPin.data.id;

    // Bob tries to update Alice's pin
    const updateCallableBob = httpsCallable(clientFunctionsBob, 'updateMapPin');
    await assert.rejects(
      updateCallableBob({ pinId, title: 'Bob Hijacked Pin' }),
      (err) => err.code === 'functions/permission-denied' || err.message.includes('permission-denied')
    );

    // Bob tries to delete Alice's pin
    const deleteCallableBob = httpsCallable(clientFunctionsBob, 'deleteMapPin');
    await assert.rejects(
      deleteCallableBob({ pinId }),
      (err) => err.code === 'functions/permission-denied' || err.message.includes('permission-denied')
    );

    // Verify pin still exists intact in canonical and projection
    const canonicalSnap = await adminDb.ref(`SubRequests/${pinId}`).get();
    assert.strictEqual(canonicalSnap.exists(), true);
    assert.strictEqual(canonicalSnap.val().title, 'Protected Alice Jam');

    const projectionSnap = await adminDb.ref(`publicMapPinFeed/${pinId}`).get();
    assert.strictEqual(projectionSnap.exists(), true);
    assert.strictEqual(projectionSnap.val().title, 'Protected Alice Jam');

    // Clean up with creator
    const deleteCallableAlice = httpsCallable(clientFunctionsAlice, 'deleteMapPin');
    await deleteCallableAlice({ pinId });
  });

  // 14. Direct Invitation never appears in publicMapPinFeed
  it('14. Direct Invitation never appears in publicMapPinFeed', async () => {
    const directInMapFeed = await adminDb.ref('publicMapPinFeed/sub_direct_2').get();
    assert.strictEqual(directInMapFeed.exists(), false);
  });

  // 15. Favorites-only request never appears in publicMapPinFeed
  it('15. Favorites-only request never appears in publicMapPinFeed', async () => {
    const favInMapFeed = await adminDb.ref('publicMapPinFeed/sub_fav_3').get();
    assert.strictEqual(favInMapFeed.exists(), false);
  });

  // 16. Ordinary public staffing request never appears in publicMapPinFeed
  it('16. Ordinary public staffing request never appears in publicMapPinFeed', async () => {
    const pubInMapFeed = await adminDb.ref('publicMapPinFeed/sub_pub_1').get();
    assert.strictEqual(pubInMapFeed.exists(), false);
  });

  // 17. Unrelated authenticated user cannot read private canonical request data (sub_direct_2, sub_fav_3)
  it('17. Unrelated authenticated user cannot read private canonical request data (sub_direct_2, sub_fav_3)', async () => {
    const carolCtx = testEnv.authenticatedContext(userCarol);

    // Direct invitation read denied
    const directRef = carolCtx.database().ref('SubRequests/sub_direct_2');
    await assertFails(directRef.get());

    const directResponsesRef = carolCtx.database().ref('SubRequests/sub_direct_2/Responses');
    await assertFails(directResponsesRef.get());

    // Favorites-only request read denied
    const favRef = carolCtx.database().ref('SubRequests/sub_fav_3');
    await assertFails(favRef.get());

    const favResponsesRef = carolCtx.database().ref('SubRequests/sub_fav_3/Responses');
    await assertFails(favResponsesRef.get());
  });

  // 18. Existing response/application authorization remains functional
  it('18. Existing response/application authorization remains functional', async () => {
    const aliceCtx = testEnv.authenticatedContext(userAlice);
    const bobCtx = testEnv.authenticatedContext(userBob);

    // Creator Alice CAN read own direct request
    await assertSucceeds(aliceCtx.database().ref('SubRequests/sub_direct_2').get());

    // Recipient Bob in subRequestAudience CANNOT read raw canonical request directly, but CAN read authorized userSubRequestFeed
    await assertFails(bobCtx.database().ref('SubRequests/sub_direct_2').get());
    await assertSucceeds(bobCtx.database().ref(`userSubRequestFeed/${userBob}/sub_direct_2`).get());

    // Bob can write response to SubRequests/sub_direct_2/Responses/user_bob
    await assertSucceeds(
      bobCtx.database().ref(`SubRequests/sub_direct_2/Responses/${userBob}`).set(true)
    );

    // Bob CANNOT read whole responses collection, but CAN read own leaf response
    await assertFails(bobCtx.database().ref('SubRequests/sub_direct_2/Responses').get());
    await assertSucceeds(bobCtx.database().ref(`SubRequests/sub_direct_2/Responses/${userBob}`).get());

    // Creator Alice can read Bob's response
    await assertSucceeds(aliceCtx.database().ref(`SubRequests/sub_direct_2/Responses/${userBob}`).get());
  });
});
