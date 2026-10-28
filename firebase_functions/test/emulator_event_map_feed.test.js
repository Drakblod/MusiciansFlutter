const fs = require('fs');
const path = require('path');
const assert = require('assert');
const admin = require('firebase-admin');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

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

async function waitForValue(ref, predicate, timeoutMs = 25000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const snap = await ref.once('value');
    if (predicate(snap.val())) {
      return snap.val();
    }
    await new Promise((r) => setTimeout(r, 150));
  }
  const snap = await ref.once('value');
  if (predicate(snap.val())) return snap.val();
  throw new Error(`Timeout waiting for value at ${ref.toString()} matching predicate. Current: ${JSON.stringify(snap.val())}`);
}

describe('Real Firebase Emulator: MAP-VIEW-FEED-02 Event Feed & Rules Integration', function () {
  this.timeout(40000);

  let adminApp;
  let adminDb;
  let testEnv;

  const userA = 'user_emu_alice';
  const userB = 'user_emu_bob';
  const userC = 'user_emu_carol';

  before(async function () {
    adminApp = admin.initializeApp({
      projectId: PROJECT_ID,
      databaseURL: `http://${DB_HOST}:${DB_PORT}?ns=${PROJECT_ID}`,
    }, `emu-event-feed-${Date.now()}`);
    adminDb = adminApp.database();

    const finalRules = fs.readFileSync(
      path.join(__dirname, '../../database.rules.json'),
      'utf8'
    );

    try {
      testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        database: {
          host: DB_HOST,
          port: DB_PORT,
          rules: finalRules,
        },
      });
    } catch (err) {
      await new Promise(resolve => setTimeout(resolve, 500));
      testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        database: {
          host: DB_HOST,
          port: DB_PORT,
          rules: finalRules,
        },
      });
    }

    // Seed initial test data in feeds via admin
    await adminDb.ref(`publicMapEventFeed/seed_public_1`).set({
      mapItemId: 'seed_public_1',
      title: 'Initial Seed Public Event',
      visibility: 'public',
      latitude: 59.33,
      longitude: 18.06,
    });

    await adminDb.ref(`userMapEventFeed/${userA}/seed_private_a`).set({
      mapItemId: 'seed_private_a',
      title: 'Alice Private Seed Event',
      visibility: 'private',
    });

    await adminDb.ref(`mapEventProjectionIndex/public:seed_public_1`).set({
      sourceType: 'public_calendar',
      mapItemIds: { seed_public_1: true },
    });
  });

  after(async function () {
    if (adminApp) {
      await adminApp.delete().catch(() => {});
    }
    if (testEnv) await testEnv.cleanup();
  });

  describe('1. RTDB Security Rules Enforcement', () => {
    it('Authenticated user can read publicMapEventFeed', async () => {
      const authCtx = testEnv.authenticatedContext(userA);
      const ref = authCtx.database().ref('publicMapEventFeed/seed_public_1');
      await assertSucceeds(ref.get());
    });

    it('Unauthenticated user cannot read publicMapEventFeed', async () => {
      const unauthCtx = testEnv.unauthenticatedContext();
      const ref = unauthCtx.database().ref('publicMapEventFeed/seed_public_1');
      await assertFails(ref.get());
    });

    it('User A can read only userMapEventFeed/userA', async () => {
      const userACtx = testEnv.authenticatedContext(userA);
      const ref = userACtx.database().ref(`userMapEventFeed/${userA}/seed_private_a`);
      await assertSucceeds(ref.get());
    });

    it('User A cannot read user B’s feed (userMapEventFeed/userB)', async () => {
      const userACtx = testEnv.authenticatedContext(userA);
      const ref = userACtx.database().ref(`userMapEventFeed/${userB}/any_item`);
      await assertFails(ref.get());
    });

    it('Clients cannot write publicMapEventFeed', async () => {
      const userACtx = testEnv.authenticatedContext(userA);
      const ref = userACtx.database().ref('publicMapEventFeed/client_hacked_item');
      await assertFails(ref.set({ hacked: true }));
    });

    it('Clients cannot write any userMapEventFeed (even their own)', async () => {
      const userACtx = testEnv.authenticatedContext(userA);
      const ref = userACtx.database().ref(`userMapEventFeed/${userA}/client_hacked_item`);
      await assertFails(ref.set({ hacked: true }));
    });

    it('Clients cannot read or write the mapEventProjectionIndex', async () => {
      const userACtx = testEnv.authenticatedContext(userA);
      const indexRef = userACtx.database().ref('mapEventProjectionIndex/public:seed_public_1');
      await assertFails(indexRef.get());
      await assertFails(indexRef.set({ hacked: true }));

      const unauthCtx = testEnv.unauthenticatedContext();
      const unauthIndexRef = unauthCtx.database().ref('mapEventProjectionIndex/public:seed_public_1');
      await assertFails(unauthIndexRef.get());
      await assertFails(unauthIndexRef.set({ hacked: true }));
    });
  });

  describe('2. Real Emulator Triggers & Projection Lifecycle', function () {
    this.timeout(50000);
    const testPublicEventId = `evt_emu_pub_${Date.now()}`;
    const testBandId = `band_emu_${Date.now()}`;
    const testBandEventId = `evt_emu_priv_${Date.now()}`;

    it('Actual Event creation produces expected projection in publicMapEventFeed', async () => {
      const pubEventRef = adminDb.ref(`PublicEvents/${testPublicEventId}`);
      await pubEventRef.set({
        title: 'Emulator Live Concert',
        eventType: 'liveGig',
        status: 'published',
        organizerName: 'Stockholm Music Society',
        startDateTime: '2026-11-15T20:00:00Z',
        endDateTime: '2026-11-15T23:00:00Z',
        latitude: 59.3293,
        longitude: 18.0686,
        locationPrecision: 'exact',
        createdAt: Date.now(),
      });

      const feedRef = adminDb.ref(`publicMapEventFeed/event:public:${testPublicEventId}`);
      const projection = await waitForValue(feedRef, (val) => val !== null && val.title === 'Emulator Live Concert');

      assert.strictEqual(projection.mapItemId, `event:public:${testPublicEventId}`);
      assert.strictEqual(projection.title, 'Emulator Live Concert');
      assert.strictEqual(projection.visibility, 'public');
      assert.strictEqual(projection.latitude, 59.3293);
    });

    it('Actual Event update replaces projection', async () => {
      const pubEventRef = adminDb.ref(`PublicEvents/${testPublicEventId}`);
      await pubEventRef.update({
        title: 'Updated Concert Title',
      });

      const feedRef = adminDb.ref(`publicMapEventFeed/event:public:${testPublicEventId}`);
      const projection = await waitForValue(feedRef, (val) => val !== null && val.title === 'Updated Concert Title');

      assert.strictEqual(projection.title, 'Updated Concert Title');
    });

    it('Actual Event deletion removes projection', async () => {
      const pubEventRef = adminDb.ref(`PublicEvents/${testPublicEventId}`);
      await pubEventRef.remove();

      const feedRef = adminDb.ref(`publicMapEventFeed/event:public:${testPublicEventId}`);
      await waitForValue(feedRef, (val) => val === null);

      const snap = await feedRef.once('value');
      assert.strictEqual(snap.exists(), false);
    });

    it('Actual private Band Event creation projects only to authorized members', async () => {
      // 1. Create Band with userA as member
      await adminDb.ref(`Bands/${testBandId}`).set({
        Name: 'The Emulator Band',
        Members_band: {
          [userA]: { Role: 'Leader', Status: 'active' },
        },
      });

      // 2. Create Event with two schedule parts
      await adminDb.ref(`Bands/${testBandId}/Events/${testBandEventId}`).set({
        title: 'Album Rehearsal',
        eventType: 'Rehearsal',
        latitude: 59.3325,
        longitude: 18.0649,
        createdBy: userA,
        createdAt: Date.now(),
        rehearsals: [
          { id: 'part_tune', type: 'Rehearsal', startDateTime: '2026-11-18T16:00:00Z', endDateTime: '2026-11-18T17:00:00Z' },
          { id: 'part_full', type: 'Rehearsal', startDateTime: '2026-11-18T18:00:00Z', endDateTime: '2026-11-18T21:00:00Z' },
        ],
      });

      // User A should receive projections for both parts
      const userAFeedPart1 = adminDb.ref(`userMapEventFeed/${userA}/event:private:${testBandId}:${testBandEventId}:part_tune`);
      const userAFeedPart2 = adminDb.ref(`userMapEventFeed/${userA}/event:private:${testBandId}:${testBandEventId}:part_full`);

      await waitForValue(userAFeedPart1, (val) => val !== null);
      await waitForValue(userAFeedPart2, (val) => val !== null);

      // User B is not in the band, must receive nothing
      const userBFeedPart1 = adminDb.ref(`userMapEventFeed/${userB}/event:private:${testBandId}:${testBandEventId}:part_tune`);
      const snapB = await userBFeedPart1.once('value');
      assert.strictEqual(snapB.exists(), false);

      // Never leaked to public feed
      const pubLeakCheck = adminDb.ref(`publicMapEventFeed/event:private:${testBandId}:${testBandEventId}:part_tune`);
      const snapPub = await pubLeakCheck.once('value');
      assert.strictEqual(snapPub.exists(), false);
    });

    it('Actual schedule-part removal removes the stale item', async () => {
      // Remove part_tune from rehearsals, keep only part_full
      await adminDb.ref(`Bands/${testBandId}/Events/${testBandEventId}/rehearsals`).set([
        { id: 'part_full', type: 'Rehearsal', startDateTime: '2026-11-18T18:00:00Z', endDateTime: '2026-11-18T21:00:00Z' },
      ]);

      const userAFeedPart1 = adminDb.ref(`userMapEventFeed/${userA}/event:private:${testBandId}:${testBandEventId}:part_tune`);
      const userAFeedPart2 = adminDb.ref(`userMapEventFeed/${userA}/event:private:${testBandId}:${testBandEventId}:part_full`);

      // part_tune should be cleanly removed
      await waitForValue(userAFeedPart1, (val) => val === null);

      // part_full should be retained
      const snapPart2 = await userAFeedPart2.once('value');
      assert.strictEqual(snapPart2.exists(), true);
    });

    it('Actual membership addition updates private projections', async () => {
      // Add userB as a new band member
      await adminDb.ref(`Bands/${testBandId}/Members_band/${userB}`).set({
        Role: 'Member',
        Status: 'active',
      });

      // User B should now receive existing event projections for this band
      const userBFeedPart2 = adminDb.ref(`userMapEventFeed/${userB}/event:private:${testBandId}:${testBandEventId}:part_full`);
      await waitForValue(userBFeedPart2, (val) => val !== null);
    });

    it('Actual membership removal removes private projections', async () => {
      // Remove userB from the band
      await adminDb.ref(`Bands/${testBandId}/Members_band/${userB}`).remove();

      const userBFeedPart2 = adminDb.ref(`userMapEventFeed/${userB}/event:private:${testBandId}:${testBandEventId}:part_full`);
      await waitForValue(userBFeedPart2, (val) => val === null);
    });

    it('Trigger retries remain idempotent', async () => {
      // Rewriting identical event node preserves projections without duplication or deletion
      const eventSnap = await adminDb.ref(`Bands/${testBandId}/Events/${testBandEventId}`).once('value');
      await adminDb.ref(`Bands/${testBandId}/Events/${testBandEventId}`).set(eventSnap.val());

      const userAFeedPart2 = adminDb.ref(`userMapEventFeed/${userA}/event:private:${testBandId}:${testBandEventId}:part_full`);
      const snap = await userAFeedPart2.once('value');
      assert.strictEqual(snap.exists(), true);
      assert.strictEqual(snap.val().title, 'Album Rehearsal');
    });

    it('Scoped multi-band member removal: removes only Band A projections, preserves Band B and other users', async () => {
      const multiBandA = `band_multi_a_${Date.now()}`;
      const multiBandB = `band_multi_b_${Date.now()}`;
      const multiEventA = `evt_multi_a_${Date.now()}`;
      const multiEventB = `evt_multi_b_${Date.now()}`;

      // User A belongs to both Band A and Band B; User C belongs to Band A
      await adminDb.ref(`Bands/${multiBandA}`).set({
        Name: 'Multi Band Alpha',
        Members_band: {
          [userA]: { Role: 'Member', Status: 'active' },
          [userC]: { Role: 'Leader', Status: 'active' },
        },
      });

      await adminDb.ref(`Bands/${multiBandB}`).set({
        Name: 'Multi Band Beta',
        Members_band: {
          [userA]: { Role: 'Member', Status: 'active' },
        },
      });

      // Band A Event
      await adminDb.ref(`Bands/${multiBandA}/Events/${multiEventA}`).set({
        title: 'Alpha Band Rehearsal',
        eventType: 'Rehearsal',
        latitude: 59.34,
        longitude: 18.07,
        createdBy: userC,
        startDateTime: '2026-11-20T18:00:00Z',
        endDateTime: '2026-11-20T21:00:00Z',
      });

      // Band B Event
      await adminDb.ref(`Bands/${multiBandB}/Events/${multiEventB}`).set({
        title: 'Beta Band Gig',
        eventType: 'Gig',
        latitude: 59.35,
        longitude: 18.08,
        createdBy: userA,
        startDateTime: '2026-11-22T19:00:00Z',
        endDateTime: '2026-11-22T23:00:00Z',
      });

      const userAAlphaFeed = adminDb.ref(`userMapEventFeed/${userA}/event:private:${multiBandA}:${multiEventA}`);
      const userABetaFeed = adminDb.ref(`userMapEventFeed/${userA}/event:private:${multiBandB}:${multiEventB}`);
      const userCAlphaFeed = adminDb.ref(`userMapEventFeed/${userC}/event:private:${multiBandA}:${multiEventA}`);

      await waitForValue(userAAlphaFeed, (v) => v !== null);
      await waitForValue(userABetaFeed, (v) => v !== null);
      await waitForValue(userCAlphaFeed, (v) => v !== null);

      // Remove User A strictly from Band A
      await adminDb.ref(`Bands/${multiBandA}/Members_band/${userA}`).remove();

      // Band A projection disappears for User A
      await waitForValue(userAAlphaFeed, (v) => v === null);

      // Band B projection REMAINS for User A
      const betaSnap = await userABetaFeed.once('value');
      assert.strictEqual(betaSnap.exists(), true, 'Band B projection must remain for User A');
      assert.strictEqual(betaSnap.val().title, 'Beta Band Gig');

      // User C's projection for Band A is completely unaffected
      const cSnap = await userCAlphaFeed.once('value');
      assert.strictEqual(cSnap.exists(), true, 'User C projection must not be touched');
      assert.strictEqual(cSnap.val().title, 'Alpha Band Rehearsal');
    });

    it('Audience reconciliation: external invitee added receives projection, removed loses projection', async () => {
      const inviteBandId = `band_inv_${Date.now()}`;
      const inviteEventId = `evt_inv_${Date.now()}`;

      await adminDb.ref(`Bands/${inviteBandId}`).set({
        Name: 'Invite Host Band',
        Members_band: {
          [userA]: { Role: 'Leader', Status: 'active' },
        },
      });

      // Create event without userB
      await adminDb.ref(`Bands/${inviteBandId}/Events/${inviteEventId}`).set({
        title: 'Special Showcase with Guest',
        eventType: 'Concert',
        latitude: 59.33,
        longitude: 18.06,
        createdBy: userA,
        startDateTime: '2026-11-25T19:00:00Z',
        endDateTime: '2026-11-25T22:00:00Z',
      });

      const userBFeed = adminDb.ref(`userMapEventFeed/${userB}/event:private:${inviteBandId}:${inviteEventId}`);
      const snapInitial = await userBFeed.once('value');
      assert.strictEqual(snapInitial.exists(), false, 'User B initially has no projection');

      // Add userB as external invitee
      await adminDb.ref(`Bands/${inviteBandId}/Events/${inviteEventId}/externalInvitees/${userB}`).set({
        status: 'attending',
        displayName: 'Bob The Guest',
        instrument: 'Saxophone',
      });

      // User B should now receive projection via onBandEventWritten reconciliation
      await waitForValue(userBFeed, (v) => v !== null);
      const snapInvited = await userBFeed.once('value');
      assert.strictEqual(snapInvited.val().title, 'Special Showcase with Guest');

      // Remove external invitee
      await adminDb.ref(`Bands/${inviteBandId}/Events/${inviteEventId}/externalInvitees/${userB}`).remove();

      // Projection should be cleanly removed
      await waitForValue(userBFeed, (v) => v === null);
      const snapRemoved = await userBFeed.once('value');
      assert.strictEqual(snapRemoved.exists(), false, 'User B projection removed when uninvited');
    });

    it('Audience reconciliation: confirmed substitute receives projection, revoked loses projection', async () => {
      const subBandId = `band_sub_${Date.now()}`;
      const subEventId = `evt_sub_${Date.now()}`;

      await adminDb.ref(`Bands/${subBandId}`).set({
        Name: 'Substitutes Band',
        Members_band: {
          [userA]: { Role: 'Leader', Status: 'active' },
        },
      });

      await adminDb.ref(`Bands/${subBandId}/Events/${subEventId}`).set({
        title: 'Live Gig With Sub',
        eventType: 'Gig',
        latitude: 59.32,
        longitude: 18.05,
        createdBy: userA,
        startDateTime: '2026-11-26T20:00:00Z',
        endDateTime: '2026-11-26T23:30:00Z',
      });

      const userBFeed = adminDb.ref(`userMapEventFeed/${userB}/event:private:${subBandId}:${subEventId}`);
      const snapInitial = await userBFeed.once('value');
      assert.strictEqual(snapInitial.exists(), false);

      // Confirm userB as substitute
      await adminDb.ref(`Bands/${subBandId}/Events/${subEventId}/substituteAssignments/slot_guitar`).set({
        assignedUserId: userB,
        status: 'assigned',
        instrument: 'Lead Guitar',
      });

      // User B should receive projection
      await waitForValue(userBFeed, (v) => v !== null);
      const snapSubbed = await userBFeed.once('value');
      assert.strictEqual(snapSubbed.val().title, 'Live Gig With Sub');

      // Revoke substitute assignment
      await adminDb.ref(`Bands/${subBandId}/Events/${subEventId}/substituteAssignments/slot_guitar`).remove();

      // Projection removed
      await waitForValue(userBFeed, (v) => v === null);
      const snapRevoked = await userBFeed.once('value');
      assert.strictEqual(snapRevoked.exists(), false);
    });

    it('Audience reconciliation: excluded member loses projection, unselected applicant receives nothing', async () => {
      const exclBandId = `band_excl_${Date.now()}`;
      const exclEventId = `evt_excl_${Date.now()}`;

      // User A and User C are both members of the band
      await adminDb.ref(`Bands/${exclBandId}`).set({
        Name: 'Exclusion Test Band',
        Members_band: {
          [userA]: { Role: 'Leader', Status: 'active' },
          [userC]: { Role: 'Member', Status: 'active' },
        },
      });

      // Create event without exclusions
      await adminDb.ref(`Bands/${exclBandId}/Events/${exclEventId}`).set({
        title: 'Secret Session',
        eventType: 'Rehearsal',
        latitude: 59.31,
        longitude: 18.04,
        createdBy: userA,
        startDateTime: '2026-11-27T18:00:00Z',
        endDateTime: '2026-11-27T20:00:00Z',
      });

      const userCFeed = adminDb.ref(`userMapEventFeed/${userC}/event:private:${exclBandId}:${exclEventId}`);
      await waitForValue(userCFeed, (v) => v !== null);

      // Exclude User C from this specific event
      await adminDb.ref(`Bands/${exclBandId}/Events/${exclEventId}/excludedMemberIds`).set([userC]);

      // User C projection should be removed
      await waitForValue(userCFeed, (v) => v === null);

      // An unrelated applicant (userB) who is not confirmed must receive nothing
      const userBFeed = adminDb.ref(`userMapEventFeed/${userB}/event:private:${exclBandId}:${exclEventId}`);
      const snapB = await userBFeed.once('value');
      assert.strictEqual(snapB.exists(), false, 'Unselected applicant receives nothing');
    });
  });
});
