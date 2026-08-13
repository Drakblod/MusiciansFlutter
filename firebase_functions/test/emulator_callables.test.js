const assert = require('assert');
const admin = require('firebase-admin');

// Firebase Client SDK Imports
const { initializeApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithCustomToken } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getDatabase, connectDatabaseEmulator } = require('firebase/database');

const PROJECT_ID = 'demo-musicians-test';
const DB_HOST = '127.0.0.1';
const DB_PORT = 9000;
const AUTH_PORT = 9099;
const FUNCTIONS_PORT = 5001;

// Route all Admin SDK & Client traffic strictly to local emulators
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

function isAuthError(err) {
  return err && (err.code === 'functions/unauthenticated' || err.code === 'unauthenticated' || (err.message && err.message.includes('unauthenticated')));
}

function isPermissionError(err) {
  return err && (err.code === 'functions/permission-denied' || err.code === 'permission-denied' || (err.message && err.message.includes('permission-denied')));
}

describe('Real Cloud Functions Emulator Integration Tests (JS Client SDK + Emulators)', function () {
  this.timeout(30000);
  const adminDb = admin.database();

  let appUserA, authUserA, functionsUserA, dbUserA;
  let appUserB, authUserB, functionsUserB, dbUserB;
  let appUserC, authUserC, functionsUserC, dbUserC;
  let appUnauth, functionsUnauth;

  before(async () => {
    async function createClientContext(uid) {
      const appName = uid ? `app_${uid}` : 'app_unauth';
      const app = initializeApp({ projectId: PROJECT_ID, apiKey: 'fake-api-key' }, appName);
      const auth = getAuth(app);
      connectAuthEmulator(auth, `http://${DB_HOST}:${AUTH_PORT}`, { disableWarnings: true });
      const functions = getFunctions(app, 'europe-west1');
      connectFunctionsEmulator(functions, DB_HOST, FUNCTIONS_PORT);
      const db = getDatabase(app);
      connectDatabaseEmulator(db, DB_HOST, DB_PORT);

      if (uid) {
        const token = await admin.auth().createCustomToken(uid);
        await signInWithCustomToken(auth, token);
      }

      return { app, auth, functions, db };
    }

    const ctxA = await createClientContext('user_a');
    appUserA = ctxA.app; authUserA = ctxA.auth; functionsUserA = ctxA.functions; dbUserA = ctxA.db;

    const ctxB = await createClientContext('user_b');
    appUserB = ctxB.app; authUserB = ctxB.auth; functionsUserB = ctxB.functions; dbUserB = ctxB.db;

    const ctxC = await createClientContext('user_c');
    appUserC = ctxC.app; authUserC = ctxC.auth; functionsUserC = ctxC.functions; dbUserC = ctxC.db;

    const ctxUnauth = await createClientContext(null);
    appUnauth = ctxUnauth.app; functionsUnauth = ctxUnauth.functions;
  });

  beforeEach(async () => {
    // Clear root RTDB state before each test
    await adminDb.ref('/').set(null);
  });

  it('1. Unauthenticated callable rejection', async () => {
    const callable = httpsCallable(functionsUnauth, 'getOrCreateDirectConversation');
    await assert.rejects(
      callable({ otherUserId: 'user_b' }),
      (err) => isAuthError(err)
    );
  });

  it('2. Direct-chat creation and participant index setup', async () => {
    const callable = httpsCallable(functionsUserA, 'getOrCreateDirectConversation');
    const result = await callable({ otherUserId: 'user_b' });

    assert(result.data && result.data.conversationId);
    const conversationId = result.data.conversationId;

    // Verify canonical conversation in RTDB emulator
    const convSnap = await adminDb.ref(`conversations/${conversationId}`).get();
    assert(convSnap.exists());
    assert.strictEqual(convSnap.val().participants['user_a'], true);
    assert.strictEqual(convSnap.val().participants['user_b'], true);

    // Verify both user index entries
    const idxA = await adminDb.ref(`userConversations/user_a/${conversationId}`).get();
    const idxB = await adminDb.ref(`userConversations/user_b/${conversationId}`).get();
    assert(idxA.exists());
    assert(idxB.exists());
    assert.strictEqual(idxA.val().otherUserId, 'user_b');
    assert.strictEqual(idxB.val().otherUserId, 'user_a');
  });

  it('3. Concurrent creation resolves to the same pair-key conversation', async () => {
    const callableA = httpsCallable(functionsUserA, 'getOrCreateDirectConversation');
    const callableB = httpsCallable(functionsUserB, 'getOrCreateDirectConversation');

    const [resA, resB] = await Promise.all([
      callableA({ otherUserId: 'user_b' }),
      callableB({ otherUserId: 'user_a' }),
    ]);

    assert.strictEqual(resA.data.conversationId, resB.data.conversationId);
  });

  it('4. Incomplete pair-key recovery repair', async () => {
    const crypto = require('crypto');
    const sorted = ['user_a', 'user_b'].sort();
    const pairHash = crypto.createHash('sha256').update(`${sorted[0]}_${sorted[1]}`).digest('hex');

    // Create orphaned pair key claim
    await adminDb.ref(`directConversationKeys/${pairHash}`).set({
      conversationId: 'orphaned_conv_999',
      createdTimestamp: new Date().toISOString(),
    });

    const callableA = httpsCallable(functionsUserA, 'getOrCreateDirectConversation');
    const res = await callableA({ otherUserId: 'user_b' });

    assert.strictEqual(res.data.conversationId, 'orphaned_conv_999');
    const convSnap = await adminDb.ref('conversations/orphaned_conv_999').get();
    assert(convSnap.exists());
    assert.strictEqual(convSnap.val().participants['user_a'], true);
  });

  it('5. Message creation updates conversation messages and both user indexes', async () => {
    const callableCreate = httpsCallable(functionsUserA, 'getOrCreateDirectConversation');
    const callableSend = httpsCallable(functionsUserA, 'sendDirectMessage');

    const createRes = await callableCreate({ otherUserId: 'user_b' });
    const conversationId = createRes.data.conversationId;

    await callableSend({
      conversationId,
      text: 'Hello from Emulator SDK!',
      receiverUserId: 'user_b',
    });

    const idxA = await adminDb.ref(`userConversations/user_a/${conversationId}`).get();
    const idxB = await adminDb.ref(`userConversations/user_b/${conversationId}`).get();

    assert.strictEqual(idxA.val().lastMessageText, 'Hello from Emulator SDK!');
    assert.strictEqual(idxA.val().hasUnread, false);
    assert.strictEqual(idxB.val().lastMessageText, 'Hello from Emulator SDK!');
    assert.strictEqual(idxB.val().hasUnread, true);
  });

  it('6. Mark-as-read clears hasUnread for recipient and rejects third user', async () => {
    const callableCreate = httpsCallable(functionsUserA, 'getOrCreateDirectConversation');
    const callableSend = httpsCallable(functionsUserA, 'sendDirectMessage');
    const callableReadB = httpsCallable(functionsUserB, 'markDirectConversationRead');
    const callableReadC = httpsCallable(functionsUserC, 'markDirectConversationRead');

    const { conversationId } = (await callableCreate({ otherUserId: 'user_b' })).data;
    await callableSend({ conversationId, text: 'Read me!', receiverUserId: 'user_b' });

    // Unauthorized third user C rejected
    await assert.rejects(
      callableReadC({ conversationId }),
      (err) => isPermissionError(err)
    );

    // Recipient user B succeeds
    await callableReadB({ conversationId });
    const idxB = await adminDb.ref(`userConversations/user_b/${conversationId}`).get();
    assert.strictEqual(idxB.val().hasUnread, false);
  });

  it('7. Agreement-chat creation is genuinely idempotent across repeated and concurrent calls', async () => {
    await adminDb.ref('SubRequests/sub_200').set({
      CreatorUserId: 'user_a',
      SubRequestId: 'sub_200',
      VoicePart: 'Tenor',
      BandName: 'Gospel Choir',
    });

    const callableAgreementA = httpsCallable(functionsUserA, 'createAgreementConversation');
    const callableAgreementB = httpsCallable(functionsUserB, 'createAgreementConversation');

    // First call by applicant User B
    const res1 = await callableAgreementB({ subRequestId: 'sub_200', applicantId: 'user_b' });
    const convId1 = res1.data.conversationId;
    assert(convId1);

    // Repeated call by creator User A returns the exact same conversation ID
    const res2 = await callableAgreementA({ subRequestId: 'sub_200', applicantId: 'user_b' });
    assert.strictEqual(res2.data.conversationId, convId1);

    // Concurrent call returns the exact same conversation ID
    const [resConcurrent1, resConcurrent2] = await Promise.all([
      callableAgreementB({ subRequestId: 'sub_200', applicantId: 'user_b' }),
      callableAgreementA({ subRequestId: 'sub_200', applicantId: 'user_b' }),
    ]);
    assert.strictEqual(resConcurrent1.data.conversationId, convId1);
    assert.strictEqual(resConcurrent2.data.conversationId, convId1);

    // Different applicant User C receives a different agreement conversation ID
    const resC = await callableAgreementA({ subRequestId: 'sub_200', applicantId: 'user_c' });
    assert.notStrictEqual(resC.data.conversationId, convId1);

    // Unauthorized third user C rejected when trying to forge applicant reference
    const callableAgreementC = httpsCallable(functionsUserC, 'createAgreementConversation');
    await assert.rejects(
      callableAgreementC({ subRequestId: 'sub_200', applicantId: 'user_b' }),
      (err) => isPermissionError(err)
    );
  });

  it('8. Leader/Admin reminder authorization & ordinary member rejection', async () => {
    await adminDb.ref('Bands/band_1/Members_band/user_a/Role').set('Leader');
    await adminDb.ref('Bands/band_1/Members_band/user_c/Role').set('Member');
    await adminDb.ref('Bands/band_1/Events/evt_1').set({ title: 'Gig', isLocked: false });

    const callableReminderA = httpsCallable(functionsUserA, 'triggerEventReminder');
    const callableReminderC = httpsCallable(functionsUserC, 'triggerEventReminder');

    // Ordinary member C rejected
    await assert.rejects(
      callableReminderC({ bandId: 'band_1', eventId: 'evt_1', reminderType: '24h' }),
      (err) => isPermissionError(err)
    );

    // Leader A succeeds (returns no_valid_tokens because no tokens seeded)
    const res = await callableReminderA({ bandId: 'band_1', eventId: 'evt_1', reminderType: '24h' });
    assert.strictEqual(res.data.status, 'no_valid_tokens');
  });

  it('9. Duplicate reminder claims with completed audit record return already_sent', async () => {
    await adminDb.ref('Bands/band_1/Members_band/user_a/Role').set('Leader');
    await adminDb.ref('Bands/band_1/Events/evt_1').set({ title: 'Gig', isLocked: false });
    await adminDb.ref('eventReminderAudit/band_1/evt_1/24h').set({
      status: 'completed',
      requestedBy: 'user_a',
      requestedAt: new Date().toISOString(),
      recipients: { user_b: { status: 'sent', sentAt: new Date().toISOString() } },
      successCount: 1,
      attemptedCount: 1,
      failureCount: 0,
    });

    const callableReminderA = httpsCallable(functionsUserA, 'triggerEventReminder');
    const res = await callableReminderA({ bandId: 'band_1', eventId: 'evt_1', reminderType: '24h' });

    assert.strictEqual(res.data.status, 'already_sent');
  });

  it('10. Repeated calls with no_valid_tokens continue returning no_valid_tokens and do NOT become already_sent', async () => {
    await adminDb.ref('Bands/band_1/Members_band/user_a/Role').set('Leader');
    await adminDb.ref('Bands/band_1/Members_band/user_b/Role').set('Member');
    await adminDb.ref('Bands/band_1/Events/evt_10').set({ title: 'Rehearsal', isLocked: false });

    const callableReminderA = httpsCallable(functionsUserA, 'triggerEventReminder');

    const res1 = await callableReminderA({ bandId: 'band_1', eventId: 'evt_10', reminderType: '24h' });
    assert.strictEqual(res1.data.status, 'no_valid_tokens');

    const res2 = await callableReminderA({ bandId: 'band_1', eventId: 'evt_10', reminderType: '24h' });
    assert.strictEqual(res2.data.status, 'no_valid_tokens');
    assert.notStrictEqual(res2.data.status, 'already_sent');
  });
});
