const assert = require('assert');
const admin = require('firebase-admin');

// Firebase Client SDK Imports
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, signInWithCustomToken } = require('firebase/auth');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');
const { getDatabase, connectDatabaseEmulator, goOffline } = require('firebase/database');

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

function isAlreadyExistsError(err) {
  return err && (
    err.code === 'functions/already-exists' ||
    err.code === 'already-exists' ||
    (err.message && (err.message.includes('already-exists') || err.message.includes('already assigned') || err.message.includes('already been assigned')))
  );
}

describe('Real Cloud Functions Emulator Integration Tests (JS Client SDK + Emulators)', function () {
  this.timeout(30000);
  const adminDb = admin.database();

  let appUserA, authUserA, functionsUserA, dbUserA;
  let appUserB, authUserB, functionsUserB, dbUserB;
  let appUserC, authUserC, functionsUserC, dbUserC;
  let appUnauth, functionsUnauth;

  before(async function () {
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

  after(async () => {
    if (dbUserA) goOffline(dbUserA);
    if (dbUserB) goOffline(dbUserB);
    if (dbUserC) goOffline(dbUserC);
    if (appUserA) await deleteApp(appUserA).catch(() => {});
    if (appUserB) await deleteApp(appUserB).catch(() => {});
    if (appUserC) await deleteApp(appUserC).catch(() => {});
    if (appUnauth) await deleteApp(appUnauth).catch(() => {});
    if (admin.apps.length) {
      await Promise.all(admin.apps.map(app => app.delete().catch(() => {})));
    }
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

  it('11. createBandSectionConversation allows ordinary member to create group with band members', async () => {
    await adminDb.ref('Bands/band_sec/Name').set('Horn Power');
    await adminDb.ref('Bands/band_sec/Members_band/user_a').set({ Role: 'Member' });
    await adminDb.ref('Bands/band_sec/Members_band/user_b').set({ Role: 'Member' });

    const createFn = httpsCallable(functionsUserA, 'createBandSectionConversation');
    const res = await createFn({
      bandId: 'band_sec',
      groupName: 'Horns',
      participantIds: ['user_b'],
    });

    assert(res.data.conversationId);
    const convSnap = await adminDb.ref(`conversations/${res.data.conversationId}`).get();
    assert.strictEqual(convSnap.val().groupName, 'Horns');
    assert.strictEqual(convSnap.val().bandName, 'Horn Power');
    assert.strictEqual(convSnap.val().participantCount, 2);
  });

  it('12. sendBandSectionMessage updates all participants inboxes', async () => {
    await adminDb.ref('Bands/band_sec/Members_band/user_a').set({ Role: 'Member' });
    await adminDb.ref('Bands/band_sec/Members_band/user_b').set({ Role: 'Member' });

    const createFn = httpsCallable(functionsUserA, 'createBandSectionConversation');
    const createRes = await createFn({
      bandId: 'band_sec',
      groupName: 'Horns',
      participantIds: ['user_b'],
    });
    const convId = createRes.data.conversationId;

    const sendFn = httpsCallable(functionsUserA, 'sendBandSectionMessage');
    const sendRes = await sendFn({
      conversationId: convId,
      text: 'Section rehearsal tomorrow',
    });
    assert(sendRes.data.messageId);

    const inboxSnapB = await adminDb.ref(`userConversations/user_b/${convId}`).get();
    assert.strictEqual(inboxSnapB.val().hasUnread, true);
    assert.strictEqual(inboxSnapB.val().lastMessageText, 'Section rehearsal tomorrow');

    const inboxSnapA = await adminDb.ref(`userConversations/user_a/${convId}`).get();
    assert.strictEqual(inboxSnapA.val().hasUnread, false);
  });

  it('13. markBandSectionConversationRead sets caller unread flag to false', async () => {
    await adminDb.ref('Bands/band_sec/Members_band/user_a').set({ Role: 'Member' });
    await adminDb.ref('Bands/band_sec/Members_band/user_b').set({ Role: 'Member' });

    const createFn = httpsCallable(functionsUserA, 'createBandSectionConversation');
    const createRes = await createFn({
      bandId: 'band_sec',
      groupName: 'Horns',
      participantIds: ['user_b'],
    });
    const convId = createRes.data.conversationId;

    const sendFn = httpsCallable(functionsUserA, 'sendBandSectionMessage');
    await sendFn({ conversationId: convId, text: 'Hello!' });

    const markFnB = httpsCallable(functionsUserB, 'markBandSectionConversationRead');
    await markFnB({ conversationId: convId });

    const inboxSnapB = await adminDb.ref(`userConversations/user_b/${convId}`).get();
    assert.strictEqual(inboxSnapB.val().hasUnread, false);
  });

  it('14. manageBandSectionConversation rename and leave actions', async () => {
    await adminDb.ref('Bands/band_sec/Members_band/user_a').set({ Role: 'Member' });
    await adminDb.ref('Bands/band_sec/Members_band/user_b').set({ Role: 'Member' });
    await adminDb.ref('Bands/band_sec/Members_band/user_c').set({ Role: 'Member' });

    const createFn = httpsCallable(functionsUserA, 'createBandSectionConversation');
    const createRes = await createFn({
      bandId: 'band_sec',
      groupName: 'Horns',
      participantIds: ['user_b', 'user_c'],
    });
    const convId = createRes.data.conversationId;

    // Creator renames
    const manageFnA = httpsCallable(functionsUserA, 'manageBandSectionConversation');
    await manageFnA({ conversationId: convId, action: 'rename', groupName: 'Super Horns' });

    const convSnap = await adminDb.ref(`conversations/${convId}`).get();
    assert.strictEqual(convSnap.val().groupName, 'Super Horns');

    // Participant leaves
    const manageFnC = httpsCallable(functionsUserC, 'manageBandSectionConversation');
    await manageFnC({ conversationId: convId, action: 'leave' });

    const convSnapAfterLeave = await adminDb.ref(`conversations/${convId}`).get();
    assert.strictEqual(convSnapAfterLeave.val().participantCount, 2);
    assert.strictEqual(convSnapAfterLeave.val().participants.user_c, undefined);
  });

  it('15. createSessionConversation authorization, creation, and idempotency', async () => {
    // Setup session created by user_a
    await adminDb.ref('Collabs/Sessions/sess_100').set({
      CreatorId: 'user_a',
      Title: 'Pop Workshop',
      Description: 'Writing hooks',
      SessionType: 'Remote',
      SessionCategory: 'Workshop',
      IsDateFlexible: false,
      Status: 'active',
    });

    // Unauthenticated caller is rejected
    const unauthFn = httpsCallable(functionsUnauth, 'createSessionConversation');
    await assert.rejects(
      unauthFn({ sessionId: 'sess_100', sessionTitle: 'Pop Workshop' }),
      (err) => isAuthError(err)
    );

    // Non-creator (user_b) is rejected with permission-denied
    const userBFn = httpsCallable(functionsUserB, 'createSessionConversation');
    await assert.rejects(
      userBFn({ sessionId: 'sess_100', sessionTitle: 'Pop Workshop' }),
      (err) => isPermissionError(err)
    );

    // Creator (user_a) creates session chat
    const userAFn = httpsCallable(functionsUserA, 'createSessionConversation');
    const res = await userAFn({ sessionId: 'sess_100', sessionTitle: 'Pop Workshop' });
    assert(res.data && res.data.conversationId);
    const convId = res.data.conversationId;

    // Verify canonical conversation in RTDB emulator
    const convSnap = await adminDb.ref(`conversations/${convId}`).get();
    assert.strictEqual(convSnap.val().conversationType, 'session_chat');
    assert.strictEqual(convSnap.val().sessionId, 'sess_100');
    assert.strictEqual(convSnap.val().participants.user_a, true);

    // Verify user_a conversation index
    const userSnap = await adminDb.ref(`userConversations/user_a/${convId}`).get();
    assert.strictEqual(userSnap.val().conversationType, 'session_chat');
    assert.strictEqual(userSnap.val().sessionId, 'sess_100');

    // Idempotent: repeating creation returns same conversationId
    const resRepeat = await userAFn({ sessionId: 'sess_100', sessionTitle: 'Pop Workshop' });
    assert.strictEqual(resRepeat.data.conversationId, convId);
  });

  it('16. updateSessionApplicationStatus authorization and atomic chat provisioning', async () => {
    // Setup session with chat
    await adminDb.ref('Collabs/Sessions/sess_200').set({
      CreatorId: 'user_a',
      Title: 'Jazz Jam',
      SessionChatId: 'conv_sess_200',
      Status: 'active',
    });
    await adminDb.ref('conversations/conv_sess_200').set({
      conversationType: 'session_chat',
      sessionId: 'sess_200',
      participants: { user_a: true },
    });

    // Applicant user_b applies
    await adminDb.ref('Collabs/Applications/sess_200/user_b').set({
      SessionId: 'sess_200',
      CreatorId: 'user_a',
      Status: 'pending',
    });

    // Applicant (user_b) cannot accept themselves
    const userBFn = httpsCallable(functionsUserB, 'updateSessionApplicationStatus');
    await assert.rejects(
      userBFn({ sessionId: 'sess_200', applicantId: 'user_b', status: 'accepted' }),
      (err) => isPermissionError(err)
    );

    // Unrelated user (user_c) cannot accept application
    const userCFn = httpsCallable(functionsUserC, 'updateSessionApplicationStatus');
    await assert.rejects(
      userCFn({ sessionId: 'sess_200', applicantId: 'user_b', status: 'accepted' }),
      (err) => isPermissionError(err)
    );

    // Creator (user_a) accepts application
    const userAFn = httpsCallable(functionsUserA, 'updateSessionApplicationStatus');
    const acceptRes = await userAFn({ sessionId: 'sess_200', applicantId: 'user_b', status: 'accepted' });
    assert.strictEqual(acceptRes.data.status, 'accepted');

    // Verify application status is accepted
    const appSnap = await adminDb.ref('Collabs/Applications/sess_200/user_b/Status').get();
    assert.strictEqual(appSnap.val(), 'accepted');

    // Verify user_b was atomically added to canonical conversation participants
    const convSnap = await adminDb.ref('conversations/conv_sess_200/participants/user_b').get();
    assert.strictEqual(convSnap.val(), true);

    // Verify user_b received conversation index entry
    const userBConvSnap = await adminDb.ref('userConversations/user_b/conv_sess_200').get();
    assert.strictEqual(userBConvSnap.val().conversationType, 'session_chat');
    assert.strictEqual(userBConvSnap.val().sessionId, 'sess_200');
  });

  it('17. Declined applicant is not added to conversation or user index', async () => {
    await adminDb.ref('Collabs/Sessions/sess_300').set({
      CreatorId: 'user_a',
      Title: 'Rock Audition',
      SessionChatId: 'conv_sess_300',
      Status: 'active',
    });
    await adminDb.ref('conversations/conv_sess_300').set({
      conversationType: 'session_chat',
      sessionId: 'sess_300',
      participants: { user_a: true },
    });

    await adminDb.ref('Collabs/Applications/sess_300/user_c').set({
      SessionId: 'sess_300',
      CreatorId: 'user_a',
      Status: 'pending',
    });

    const userAFn = httpsCallable(functionsUserA, 'updateSessionApplicationStatus');
    await userAFn({ sessionId: 'sess_300', applicantId: 'user_c', status: 'declined' });

    const appSnap = await adminDb.ref('Collabs/Applications/sess_300/user_c/Status').get();
    assert.strictEqual(appSnap.val(), 'declined');

    // user_c must NOT be added to participants
    const partSnap = await adminDb.ref('conversations/conv_sess_300/participants/user_c').get();
    assert.strictEqual(partSnap.exists(), false);

    // user_c must NOT have conversation index entry
    const userCConvSnap = await adminDb.ref('userConversations/user_c/conv_sess_300').get();
    assert.strictEqual(userCConvSnap.exists(), false);
  });

  it('18. sendDirectMessage in session chat broadcasts to participants and blocks non-participants', async () => {
    await adminDb.ref('Collabs/Sessions/sess_msg').set({
      CreatorId: 'user_a',
      Title: 'Broadcast Jam',
      SessionChatId: 'conv_sess_msg',
      Status: 'active',
    });
    await adminDb.ref('conversations/conv_sess_msg').set({
      conversationType: 'session_chat',
      sessionId: 'sess_msg',
      participants: { user_a: true, user_b: true },
    });
    await adminDb.ref('userConversations/user_a/conv_sess_msg').set({
      conversationType: 'session_chat',
      sessionId: 'sess_msg',
      lastMessageText: '',
      hasUnread: false,
    });
    await adminDb.ref('userConversations/user_b/conv_sess_msg').set({
      conversationType: 'session_chat',
      sessionId: 'sess_msg',
      lastMessageText: '',
      hasUnread: false,
    });

    // Participant user_a sends message
    const sendFnA = httpsCallable(functionsUserA, 'sendDirectMessage');
    const msgRes = await sendFnA({ conversationId: 'conv_sess_msg', text: 'Welcome to the session!' });
    assert(msgRes.data && msgRes.data.messageId);

    // Verify inbox updates
    const inboxSnapB = await adminDb.ref('userConversations/user_b/conv_sess_msg').get();
    assert.strictEqual(inboxSnapB.val().lastMessageText, 'Welcome to the session!');
    assert.strictEqual(inboxSnapB.val().hasUnread, true);

    const inboxSnapA = await adminDb.ref('userConversations/user_a/conv_sess_msg').get();
    assert.strictEqual(inboxSnapA.val().hasUnread, false);

    // Non-participant user_c is blocked
    const sendFnC = httpsCallable(functionsUserC, 'sendDirectMessage');
    await assert.rejects(
      sendFnC({ conversationId: 'conv_sess_msg', text: 'Intruder message' }),
      (err) => isPermissionError(err)
    );
  });

  it('19. updateSessionApplicationStatus rejects nonexistent session or application', async () => {
    const userAFn = httpsCallable(functionsUserA, 'updateSessionApplicationStatus');
    // Nonexistent session
    await assert.rejects(
      userAFn({ sessionId: 'sess_ghost', applicantId: 'user_b', status: 'accepted' }),
      (err) => err && (err.code === 'functions/not-found' || err.code === 'not-found')
    );

    // Existing session but nonexistent application
    await adminDb.ref('Collabs/Sessions/sess_real').set({
      CreatorId: 'user_a',
      Title: 'Real Session',
      Status: 'active',
    });
    await assert.rejects(
      userAFn({ sessionId: 'sess_real', applicantId: 'user_ghost', status: 'accepted' }),
      (err) => err && (err.code === 'functions/not-found' || err.code === 'not-found')
    );
  });

  async function seedBandAndUsers() {
    await adminDb.ref('Bands/band_tour_test').set({
      Name: 'Touring Rockers',
      Members_band: {
        user_a: { Role: 'Leader' },
        user_b: { Role: 'Member' },
      },
      Events: {
        event_day1: { Title: 'Tour Day 1', Date: '2026-09-20' },
        event_day2: { Title: 'Tour Day 2', Date: '2026-09-21' },
      },
    });

    await adminDb.ref('users/user_b/info').set({
      UserType: 'Electric Guitar',
      Instruments: ['Electric Guitar'],
      PushToken: 'token_b',
    });
    await adminDb.ref('users/user_c/info').set({
      UserType: 'Keyboard',
      Instruments: ['Keyboard'],
      PushToken: 'token_c',
    });
  }

  it('20. publishSubRequestGroup callable: end-to-end group publication, canonical records, audience indexing, and user feeds', async () => {
    await seedBandAndUsers();

    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    const res = await publishFn({
      bandId: 'band_tour_test',
      requestGroupId: 'group_tour_2026',
      bandName: 'Touring Rockers',
      slots: [
        {
          subRequestId: 'slot_day1_guitar',
          slotId: 'slot_day1_guitar',
          eventId: 'event_day1',
          voicePart: 'Electric Guitar',
          searchSource: 'search_all',
          eventTitle: 'Tour Day 1',
          eventSequence: 1,
          date: '2026-09-20',
          payAmountMinor: 150000,
        },
        {
          subRequestId: 'slot_day2_guitar',
          slotId: 'slot_day2_guitar',
          eventId: 'event_day2',
          voicePart: 'Electric Guitar',
          searchSource: 'search_all',
          eventTitle: 'Tour Day 2',
          eventSequence: 2,
          date: '2026-09-21',
          payAmountMinor: 150000,
        },
      ],
    });

    assert.strictEqual(res.data.success, true);
    assert(res.data.publicationId);
    assert.strictEqual(res.data.requestGroupId, 'group_tour_2026');

    // 1. Confirm canonical SubRequests are published
    const req1Snap = await adminDb.ref('SubRequests/slot_day1_guitar').get();
    assert.strictEqual(req1Snap.val().Status, 'published');
    assert.strictEqual(req1Snap.val().RequestGroupId, 'group_tour_2026');

    // 2. Confirm publication manifest exists
    const pubSnap = await adminDb.ref(`subRequestPublications/${res.data.publicationId}`).get();
    assert.strictEqual(pubSnap.val().requestGroupId, 'group_tour_2026');
    assert.strictEqual(pubSnap.val().slots.length, 2);

    // 3. Confirm eligible candidate (user_b) receives audience entries & userSubRequestFeed
    const audienceB1 = await adminDb.ref('subRequestAudience/slot_day1_guitar/user_b').get();
    assert.strictEqual(audienceB1.val(), true);
    const feedB1 = await adminDb.ref('userSubRequestFeed/user_b/slot_day1_guitar').get();
    assert.strictEqual(feedB1.val().voicePart, 'Electric Guitar');

    // 4. Confirm ineligible candidate (user_c) receives neither audience nor feed
    const audienceC1 = await adminDb.ref('subRequestAudience/slot_day1_guitar/user_c').get();
    assert.strictEqual(audienceC1.exists(), false);
    const feedC1 = await adminDb.ref('userSubRequestFeed/user_c/slot_day1_guitar').get();
    assert.strictEqual(feedC1.exists(), false);

    // 5. Confirm creator management view index is populated
    const creatorIndex = await adminDb.ref('creatorSubRequestGroups/user_a/group_tour_2026').get();
    assert.strictEqual(creatorIndex.val(), true);
  });

  it('21. publishSubRequestGroup idempotency: repeating same operation returns identical publicationId', async () => {
    await seedBandAndUsers();
    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    const payload = {
      bandId: 'band_tour_test',
      requestGroupId: 'group_tour_2026',
      bandName: 'Touring Rockers',
      slots: [
        {
          subRequestId: 'slot_day1_guitar',
          slotId: 'slot_day1_guitar',
          eventId: 'event_day1',
          voicePart: 'Electric Guitar',
          searchSource: 'search_all',
        },
        {
          subRequestId: 'slot_day2_guitar',
          slotId: 'slot_day2_guitar',
          eventId: 'event_day2',
          voicePart: 'Electric Guitar',
          searchSource: 'search_all',
        },
      ],
    };

    const res1 = await publishFn(payload);
    const res2 = await publishFn(payload);
    assert.strictEqual(res1.data.publicationId, res2.data.publicationId, 'Repeated call must yield identical publicationId');
  });

  it('22. publishSubRequestGroup update: adding a genuinely new slot creates a distinct update publication', async () => {
    await seedBandAndUsers();
    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    const updateRes = await publishFn({
      bandId: 'band_tour_test',
      requestGroupId: 'group_tour_2026',
      bandName: 'Touring Rockers',
      slots: [
        {
          subRequestId: 'slot_day3_bass',
          slotId: 'slot_day3_bass',
          eventId: 'event_day1',
          voicePart: 'Bass',
          searchSource: 'search_all',
        },
      ],
    });

    assert(updateRes.data.publicationId);
    assert.notStrictEqual(updateRes.data.publicationId, 'pub_group_tour_2026_original');
    const pubSnap = await adminDb.ref(`subRequestPublications/${updateRes.data.publicationId}`).get();
    assert.strictEqual(pubSnap.val().slots.length, 1);
  });

  it('23. publishSubRequestGroup rejects unauthenticated caller and non-Leader/Admin caller', async () => {
    await seedBandAndUsers();
    const unauthFn = httpsCallable(functionsUnauth, 'publishSubRequestGroup');
    await assert.rejects(
      unauthFn({ bandId: 'band_tour_test', requestGroupId: 'grp_unauth', slots: [{ slotId: 's1', eventId: 'event_day1', voicePart: 'Bass' }] }),
      (err) => isAuthError(err)
    );

    // user_b is ordinary Member of band_tour_test, not Leader/Admin
    const memberFn = httpsCallable(functionsUserB, 'publishSubRequestGroup');
    await assert.rejects(
      memberFn({ bandId: 'band_tour_test', requestGroupId: 'grp_member', slots: [{ slotId: 's2', eventId: 'event_day1', voicePart: 'Bass' }] }),
      (err) => isPermissionError(err)
    );
  });

  it('24. publishSubRequestGroup rejects mixed-band slots and invalid event ownership', async () => {
    await seedBandAndUsers();
    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    // Mixed band slot
    await assert.rejects(
      publishFn({
        bandId: 'band_tour_test',
        requestGroupId: 'grp_mixed',
        slots: [
          { slotId: 's_ok', eventId: 'event_day1', voicePart: 'Vocals', bandId: 'band_tour_test' },
          { slotId: 's_alien', eventId: 'event_day1', voicePart: 'Vocals', bandId: 'band_other_alien' },
        ],
      }),
      (err) => err && (err.code === 'functions/invalid-argument' || err.code === 'invalid-argument')
    );

    // Event not belonging to band
    await assert.rejects(
      publishFn({
        bandId: 'band_tour_test',
        requestGroupId: 'grp_fake_event',
        slots: [
          { slotId: 's_ev_ghost', voicePart: 'Vocals', eventId: 'event_ghost_999' },
        ],
      }),
      (err) => isPermissionError(err)
    );
  });

  it('25. publishSubRequestGroup validates Favorites against caller real Favorites and ignores fabricated targets', async () => {
    await seedBandAndUsers();
    // Seed user_a Favorites: user_b is starred, user_c is NOT
    await adminDb.ref('users/user_a/Favorites').set({
      user_b: true,
    });

    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    const favRes = await publishFn({
      bandId: 'band_tour_test',
      requestGroupId: 'group_fav_security_test',
      bandName: 'Touring Rockers',
      slots: [
        {
          subRequestId: 'slot_fav_secured',
          slotId: 'slot_fav_secured',
          eventId: 'event_day1',
          voicePart: 'Vocals',
          searchSource: 'favorites',
          targetUserIds: ['user_b', 'user_c'], // user_c is fabricated
        },
      ],
    });

    assert.strictEqual(favRes.data.success, true);
    // Real favorite (user_b) is in audience and feed
    const audB = await adminDb.ref('subRequestAudience/slot_fav_secured/user_b').get();
    assert.strictEqual(audB.val(), true);

    // Fabricated target (user_c) is NOT in audience or feed
    const audC = await adminDb.ref('subRequestAudience/slot_fav_secured/user_c').get();
    assert.strictEqual(audC.exists(), false);
  });

  it('26. publishSubRequestGroup atomic consistency: all audience, feed, creator index, and manifest records are committed atomically', async () => {
    await seedBandAndUsers();
    const publishFn = httpsCallable(functionsUserA, 'publishSubRequestGroup');
    const res = await publishFn({
      bandId: 'band_tour_test',
      requestGroupId: 'group_tour_atomic_test',
      bandName: 'Touring Rockers',
      slots: [
        {
          subRequestId: 'slot_atomic_guitar',
          slotId: 'slot_atomic_guitar',
          eventId: 'event_day1',
          voicePart: 'Electric Guitar',
          searchSource: 'search_all',
        },
      ],
    });

    assert.strictEqual(res.data.success, true);
    const pubSnap = await adminDb.ref(`subRequestPublications/${res.data.publicationId}`).get();
    const audSnap = await adminDb.ref('subRequestAudience/slot_atomic_guitar/user_b').get();
    const feedSnap = await adminDb.ref('userSubRequestFeed/user_b/slot_atomic_guitar').get();
    const creatorSnap = await adminDb.ref('creatorSubRequestGroups/user_a/group_tour_atomic_test').get();

    assert.strictEqual(pubSnap.exists(), true);
    assert.strictEqual(audSnap.val(), true);
    assert.strictEqual(feedSnap.exists(), true);
    assert.strictEqual(creatorSnap.val(), true);
  });

  it('27. Real assignSubstitute callable concurrency race: exactly one caller wins, loser receives already-exists, and retry is idempotent', async () => {
    await seedBandAndUsers();
    // Authorize user_b as Band Admin alongside Leader user_a
    await adminDb.ref('Bands/band_tour_test/Members_band/user_b').set({ Role: 'Admin' });

    // Seed unassigned subrequest slot
    await adminDb.ref('SubRequests/slot_race_guitar').set({
      SubRequestId: 'slot_race_guitar',
      SlotId: 'slot_race_guitar',
      CreatorUserId: 'user_a',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
      VoicePart: 'Electric Guitar',
      Status: 'published',
    });

    const assignLeaderFn = httpsCallable(functionsUserA, 'assignSubstitute');
    const assignAdminFn = httpsCallable(functionsUserB, 'assignSubstitute');

    const runLeaderAssign = assignLeaderFn({
      subRequestId: 'slot_race_guitar',
      candidateUserId: 'user_cand_1',
      candidateName: 'Candidate 1',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
      roleOrInstrument: 'Electric Guitar',
    });

    const runAdminAssign = assignAdminFn({
      subRequestId: 'slot_race_guitar',
      candidateUserId: 'user_cand_2',
      candidateName: 'Candidate 2',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
      roleOrInstrument: 'Electric Guitar',
    });

    const results = await Promise.allSettled([runLeaderAssign, runAdminAssign]);
    const fulfilled = results.filter(r => r.status === 'fulfilled');
    const rejected = results.filter(r => r.status === 'rejected');

    assert.strictEqual(fulfilled.length, 1, 'Exactly one concurrent assignSubstitute callable must succeed');
    assert.strictEqual(rejected.length, 1, 'The competing callable must be rejected with conflict');
    assert(
      isAlreadyExistsError(rejected[0].reason),
      `Expected already-exists or already assigned conflict error but got: ${rejected[0].reason.message}`
    );

    // Verify canonical state in RTDB
    const winningUid = fulfilled[0].value.data.assignedUserId;
    assert(winningUid === 'user_cand_1' || winningUid === 'user_cand_2');

    const subReqSnap = await adminDb.ref('SubRequests/slot_race_guitar').get();
    assert.strictEqual(subReqSnap.val().AssignedUserId, winningUid);
    assert.strictEqual(subReqSnap.val().Status, 'assigned');
    assert.strictEqual(subReqSnap.val().IsSelected, true);

    const eventAssignSnap = await adminDb.ref('Bands/band_tour_test/Events/event_day1/substituteAssignments/slot_race_guitar').get();
    assert.strictEqual(eventAssignSnap.val().assignedUserId, winningUid);
    assert.strictEqual(eventAssignSnap.val().status, 'assigned');

    // Winning caller retry is idempotent and succeeds
    const winningFn = winningUid === 'user_cand_1' ? assignLeaderFn : assignAdminFn;
    const retryRes = await winningFn({
      subRequestId: 'slot_race_guitar',
      candidateUserId: winningUid,
      bandId: 'band_tour_test',
      eventId: 'event_day1',
    });
    assert.strictEqual(retryRes.data.success, true);

    // Losing caller retry still fails
    const losingUid = winningUid === 'user_cand_1' ? 'user_cand_2' : 'user_cand_1';
    const losingFn = winningUid === 'user_cand_1' ? assignAdminFn : assignLeaderFn;
    await assert.rejects(
      losingFn({
        subRequestId: 'slot_race_guitar',
        candidateUserId: losingUid,
        bandId: 'band_tour_test',
        eventId: 'event_day1',
      }),
      (err) => isAlreadyExistsError(err)
    );
  });

  it('28. assignSubstitute rejects unauthorized caller without Leader/Admin/Creator role', async () => {
    await seedBandAndUsers();
    await adminDb.ref('SubRequests/slot_unauth_test').set({
      SubRequestId: 'slot_unauth_test',
      CreatorUserId: 'user_a',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
      Status: 'published',
    });

    const outsiderFn = httpsCallable(functionsUserC, 'assignSubstitute');
    await assert.rejects(
      outsiderFn({
        subRequestId: 'slot_unauth_test',
        candidateUserId: 'user_cand_1',
        bandId: 'band_tour_test',
        eventId: 'event_day1',
      }),
      (err) => isPermissionError(err)
    );
  });

  it('29. revokeSubstituteAssignment clears assignment fields and resets status to published', async () => {
    await seedBandAndUsers();
    await adminDb.ref('SubRequests/slot_revoke_test').set({
      SubRequestId: 'slot_revoke_test',
      SlotId: 'slot_revoke_test',
      CreatorUserId: 'user_a',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
      Status: 'assigned',
      AssignedUserId: 'user_cand_1',
      IsSelected: true,
    });
    await adminDb.ref('Bands/band_tour_test/Events/event_day1/substituteAssignments/slot_revoke_test').set({
      assignedUserId: 'user_cand_1',
      status: 'assigned',
    });

    const revokeFn = httpsCallable(functionsUserA, 'revokeSubstituteAssignment');
    const revokeRes = await revokeFn({
      subRequestId: 'slot_revoke_test',
      candidateUserId: 'user_cand_1',
      bandId: 'band_tour_test',
      eventId: 'event_day1',
    });

    assert.strictEqual(revokeRes.data.success, true);
    const subReqSnap = await adminDb.ref('SubRequests/slot_revoke_test').get();
    assert.strictEqual(subReqSnap.val().Status, 'published');
    assert.strictEqual(subReqSnap.val().IsSelected, false);
    assert(!subReqSnap.val().AssignedUserId);

    const eventAssignSnap = await adminDb.ref('Bands/band_tour_test/Events/event_day1/substituteAssignments/slot_revoke_test').get();
    assert.strictEqual(eventAssignSnap.exists(), false);
  });

  it('30. markNotificationRead marks notification read in caller feed and prevents cross-user modification', async () => {
    // Seed notifications for user_a and user_b
    await adminDb.ref('userNotifications/user_a/notif_test_a1').set({
      id: 'notif_test_a1',
      type: 'event_invite',
      category: 'events',
      title: 'Event Invite A',
      body: 'Invite details',
      createdAt: Date.now(),
      isRead: false,
      readAt: null,
    });
    await adminDb.ref('userNotifications/user_b/notif_test_b1').set({
      id: 'notif_test_b1',
      type: 'direct_message',
      category: 'messages',
      title: 'DM for B',
      body: 'Hello B',
      createdAt: Date.now(),
      isRead: false,
      readAt: null,
    });

    // Unauthenticated call should fail
    const unauthFn = httpsCallable(functionsUnauth, 'markNotificationRead');
    await assert.rejects(
      unauthFn({ notificationId: 'notif_test_a1' }),
      (err) => isAuthError(err)
    );

    // User A marking own notification should succeed
    const markReadFnA = httpsCallable(functionsUserA, 'markNotificationRead');
    const resA = await markReadFnA({ notificationId: 'notif_test_a1' });
    assert.strictEqual(resA.data.success, true);

    const snapA = await adminDb.ref('userNotifications/user_a/notif_test_a1').get();
    assert.strictEqual(snapA.val().isRead, true);
    assert(snapA.val().readAt !== null);

    // User A trying to mark User B's notification should fail with not-found
    await assert.rejects(
      markReadFnA({ notificationId: 'notif_test_b1' }),
      (err) => err && (err.code === 'functions/not-found' || err.code === 'not-found' || err.message.includes('not found'))
    );

    // Verify User B's notification remains unread
    const snapB = await adminDb.ref('userNotifications/user_b/notif_test_b1').get();
    assert.strictEqual(snapB.val().isRead, false);
  });

  it('31. markAllNotificationsRead marks all notifications read for caller and returns count', async () => {
    // Seed 2 unread notifications for user_a and 1 for user_b
    await adminDb.ref('userNotifications/user_a/notif_a_batch1').set({
      id: 'notif_a_batch1',
      type: 'event_reminder',
      category: 'events',
      title: 'Reminder 1',
      createdAt: Date.now(),
      isRead: false,
    });
    await adminDb.ref('userNotifications/user_a/notif_a_batch2').set({
      id: 'notif_a_batch2',
      type: 'gig_finalized',
      category: 'requests',
      title: 'Gig Finalized',
      createdAt: Date.now(),
      isRead: false,
    });
    await adminDb.ref('userNotifications/user_b/notif_b_batch1').set({
      id: 'notif_b_batch1',
      type: 'event_reminder',
      category: 'events',
      title: 'Reminder B',
      createdAt: Date.now(),
      isRead: false,
    });

    const markAllFnA = httpsCallable(functionsUserA, 'markAllNotificationsRead');
    const resA = await markAllFnA();
    assert.strictEqual(resA.data.success, true);
    assert(resA.data.updatedCount >= 2);

    const snapA1 = await adminDb.ref('userNotifications/user_a/notif_a_batch1').get();
    const snapA2 = await adminDb.ref('userNotifications/user_a/notif_a_batch2').get();
    assert.strictEqual(snapA1.val().isRead, true);
    assert.strictEqual(snapA2.val().isRead, true);

    // User B's notification must still be unread
    const snapB1 = await adminDb.ref('userNotifications/user_b/notif_b_batch1').get();
    assert.strictEqual(snapB1.val().isRead, false);
  });

  describe('HOME-ACTIVITY-BADGES-01: Real Emulator Callables & Triggers', () => {
    it('1. markFeatureNotificationsRead rejects unauthenticated callers', async () => {
      const fn = httpsCallable(functionsUnauth, 'markFeatureNotificationsRead');
      let rejected = false;
      try {
        await fn({ featureId: 'find_gigs' });
      } catch (err) {
        rejected = isAuthError(err);
      }
      assert.strictEqual(rejected, true, 'Unauthenticated call must be rejected');
    });

    it('2. markFeatureNotificationsRead rejects invalid or unknown featureId', async () => {
      const fn = httpsCallable(functionsUserA, 'markFeatureNotificationsRead');
      let rejected = false;
      try {
        await fn({ featureId: 'invalid_feature' });
      } catch (err) {
        rejected = true;
      }
      assert.strictEqual(rejected, true, 'Invalid featureId must be rejected');
    });

    it('3. markFeatureNotificationsRead clears caller notifications and sets server timestamp, leaving others intact', async () => {
      const now = Date.now();
      // user_a notifications
      await adminDb.ref('userNotifications/user_a/n_gig_explicit').set({
        id: 'n_gig_explicit',
        type: 'sub_request_invite',
        featureId: 'find_gigs',
        isRead: false,
        readAt: null,
      });
      await adminDb.ref('userNotifications/user_a/n_gig_legacy').set({
        id: 'n_gig_legacy',
        type: 'grouped_sub_request', // legacy fallback -> find_gigs
        isRead: false,
        readAt: null,
      });
      await adminDb.ref('userNotifications/user_a/n_band').set({
        id: 'n_band',
        type: 'band_room_message',
        featureId: 'band_room',
        isRead: false,
        readAt: null,
      });

      // user_b notification (must not be affected)
      await adminDb.ref('userNotifications/user_b/n_user_b').set({
        id: 'n_user_b',
        type: 'sub_request_invite',
        featureId: 'find_gigs',
        isRead: false,
        readAt: null,
      });

      const fn = httpsCallable(functionsUserA, 'markFeatureNotificationsRead');
      const res = await fn({ featureId: 'find_gigs' });
      assert.strictEqual(res.data.success, true);
      assert.strictEqual(res.data.updatedCount, 2);

      const snapGig1 = await adminDb.ref('userNotifications/user_a/n_gig_explicit').get();
      const snapGig2 = await adminDb.ref('userNotifications/user_a/n_gig_legacy').get();
      const snapBand = await adminDb.ref('userNotifications/user_a/n_band').get();
      const snapUserB = await adminDb.ref('userNotifications/user_b/n_user_b').get();

      assert.strictEqual(snapGig1.val().isRead, true);
      assert(snapGig1.val().readAt >= now);
      assert.strictEqual(snapGig2.val().isRead, true);
      assert(snapGig2.val().readAt >= now);

      // user_a band_room remains unread
      assert.strictEqual(snapBand.val().isRead, false);

      // user_b notification remains unread (isolation)
      assert.strictEqual(snapUserB.val().isRead, false);
    });

    it('4. User B cannot clear User A notifications', async () => {
      await adminDb.ref('userNotifications/user_a/n_victim').set({
        id: 'n_victim',
        type: 'sub_request_invite',
        featureId: 'find_gigs',
        isRead: false,
        readAt: null,
      });

      const fnB = httpsCallable(functionsUserB, 'markFeatureNotificationsRead');
      await fnB({ featureId: 'find_gigs' });

      const snap = await adminDb.ref('userNotifications/user_a/n_victim').get();
      assert.strictEqual(snap.val().isRead, false);
    });

    it('5. onSubRequestResponseCreated trigger notifies request creator and prevents duplicate notifications', async () => {
      const subReqId = 'sub_req_test_1';
      const creatorUid = 'user_a';
      const applicantUid = 'user_b';

      await adminDb.ref(`SubRequests/${subReqId}`).set({
        CreatorUserId: creatorUid,
        BandName: 'The Emulator Band',
        eventType: 'Gig',
        Role: 'Bassist',
      });
      await adminDb.ref(`users/${applicantUid}/info`).set({
        displayName: 'Applicant Bob',
      });

      // Write applicant response
      await adminDb.ref(`SubRequests/${subReqId}/Responses/${applicantUid}`).set(true);

      // Wait for trigger to write notification
      const notifRef = adminDb.ref(`userNotifications/${creatorUid}/notif_sub_resp_${subReqId}_${applicantUid}`);
      let created = false;
      for (let i = 0; i < 50; i++) {
        const snap = await notifRef.get();
        if (snap.exists() && snap.val()) {
          created = true;
          assert.strictEqual(snap.val().type, 'sub_request_response');
          assert.strictEqual(snap.val().featureId, 'find_musicians');
          assert.strictEqual(snap.val().data.subRequestId, subReqId);
          assert.strictEqual(snap.val().data.applicantId, applicantUid);
          break;
        }
        await new Promise(r => setTimeout(r, 200));
      }
      assert.strictEqual(created, true, 'Notification should be created by trigger');

      // Test idempotency: rewrite response
      await adminDb.ref(`SubRequests/${subReqId}/Responses/${applicantUid}`).set(true);
      await new Promise(r => setTimeout(r, 400));

      const notifsSnap = await adminDb.ref(`userNotifications/${creatorUid}`).get();
      const notifs = notifsSnap.val() || {};
      const matching = Object.values(notifs).filter(n => n.data && n.data.subRequestId === subReqId);
      assert.strictEqual(matching.length, 1, 'Duplicate response write must not duplicate notification');
    });

    it('6. onBandFileUploaded trigger notifies band members and excludes uploader', async () => {
      const bandId = 'band_file_test';
      const uploaderUid = 'user_a';
      const memberUid = 'user_b';

      await adminDb.ref(`Bands/${bandId}`).set({
        Name: 'Emulator Band Files',
        Members_band: {
          [uploaderUid]: true,
          [memberUid]: true,
        },
      });

      const fileId = 'file_test_123';
      await adminDb.ref(`files/${bandId}/${fileId}`).set({
        FileName: 'Chart_A.pdf',
        FileUrl: 'https://storage/Chart_A.pdf',
        UploadedBy: uploaderUid,
        UploadedAt: Date.now(),
        Category: 'charts',
      });

      // Member should receive notification
      const memberNotifRef = adminDb.ref(`userNotifications/${memberUid}/notif_file_${bandId}_${fileId}_${memberUid}`);
      let notifiedMember = false;
      for (let i = 0; i < 50; i++) {
        const snap = await memberNotifRef.get();
        if (snap.exists() && snap.val()) {
          notifiedMember = true;
          assert.strictEqual(snap.val().type, 'band_file_uploaded');
          assert.strictEqual(snap.val().featureId, 'band_room');
          assert.strictEqual(snap.val().data.bandId, bandId);
          assert.strictEqual(snap.val().data.fileId, fileId);
          break;
        }
        await new Promise(r => setTimeout(r, 200));
      }
      assert.strictEqual(notifiedMember, true, 'Band member must receive file upload notification');

      // Uploader must NOT receive notification
      const uploaderNotifRef = adminDb.ref(`userNotifications/${uploaderUid}/notif_file_${bandId}_${fileId}_${uploaderUid}`);
      const uploaderSnap = await uploaderNotifRef.get();
      assert.strictEqual(uploaderSnap.exists(), false, 'Uploader must not receive own file notification');
    });

    describe('MAP-VIEW-FEEDBACK-03: Server-owned createMapPin Callable Tests', () => {
      it('30. Unauthenticated invocation of createMapPin is rejected', async () => {
        const callable = httpsCallable(functionsUnauth, 'createMapPin');
        await assert.rejects(
          callable({
            eventType: 'gigConcert',
            latitude: 59.3293,
            longitude: 18.0686,
          }),
          (err) => isAuthError(err)
        );
      });

      it('31. Authenticated valid creation succeeds and returns server-generated ID and normalized payload', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');
        const result = await callable({
          eventType: 'gigConcert',
          latitude: 59.3293,
          longitude: 18.0686,
          description: 'Stockholm Jazz Fest',
          venue: 'Fasching',
          bandName: 'Stora Stygga',
          genre: 'Big Band',
          date: '2026-11-01',
          startTime: '19:00:00',
          endTime: '22:00:00',
        });

        assert.strictEqual(result.data.success, true);
        assert(result.data.id && typeof result.data.id === 'string');
        const pin = result.data.pin;
        assert.strictEqual(pin.SubRequestId, result.data.id);
        assert.strictEqual(pin.CreatorUserId, 'user_a');
        assert.strictEqual(pin.UserId, 'user_a');
        assert.strictEqual(pin.Status, 'published');
        assert.strictEqual(pin.NotificationMode, 'map_pin');
        assert.strictEqual(pin.eventType, 'gigConcert');
        assert.strictEqual(pin.Latitude, 59.3293);
        assert.strictEqual(pin.Longitude, 18.0686);
      });

      it('32. Client-supplied record ID is ignored and server-generated key is used', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');
        const result = await callable({
          id: 'forged_client_id_999',
          subRequestId: 'forged_client_id_999',
          eventType: 'rehearsal',
          latitude: 59.33,
          longitude: 18.07,
        });

        assert.notStrictEqual(result.data.id, 'forged_client_id_999');
        const forgedSnap = await adminDb.ref('SubRequests/forged_client_id_999').get();
        assert.strictEqual(forgedSnap.exists(), false, 'Client-supplied ID must never be written to RTDB');

        const realSnap = await adminDb.ref(`SubRequests/${result.data.id}`).get();
        assert.strictEqual(realSnap.exists(), true, 'Server-generated key must be used in RTDB');
      });

      it('33. Server assigns caller UID as creator/user ID even if client supplies different UID', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');
        const result = await callable({
          CreatorUserId: 'user_b',
          UserId: 'user_c',
          creatorUserId: 'user_b',
          userId: 'user_c',
          eventType: 'jamSession',
          latitude: 59.34,
          longitude: 18.08,
        });

        const pinSnap = await adminDb.ref(`SubRequests/${result.data.id}`).get();
        const pin = pinSnap.val();
        assert.strictEqual(pin.CreatorUserId, 'user_a');
        assert.strictEqual(pin.UserId, 'user_a');
      });

      it('34. Server writes exactly once to SubRequests/{id} and never to staffing feeds', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');
        const result = await callable({
          eventType: 'recordedMusic',
          latitude: 59.35,
          longitude: 18.09,
        });

        const pinId = result.data.id;
        const subReqSnap = await adminDb.ref(`SubRequests/${pinId}`).get();
        assert.strictEqual(subReqSnap.exists(), true);

        const pubSnap = await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId}`).get();
        assert.strictEqual(pubSnap.exists(), false, 'Must not write to BandEvents/PublishedSubRequests');

        const feedSnap = await adminDb.ref(`userSubRequestFeed/user_b/${pinId}`).get();
        assert.strictEqual(feedSnap.exists(), false, 'Must not write to userSubRequestFeed');

        const audSnap = await adminDb.ref(`subRequestAudience/${pinId}`).get();
        assert.strictEqual(audSnap.exists(), false, 'Must not write to subRequestAudience');
      });

      it('35. Ordinary map_pin triggers zero notifications / push events for users', async () => {
        await adminDb.ref('users/user_b/info').set({
          UserType: 'Electric Guitar',
          Instruments: ['Electric Guitar'],
          PushToken: 'token_b',
        });

        const callable = httpsCallable(functionsUserA, 'createMapPin');
        await callable({
          eventType: 'gigConcert',
          latitude: 59.3293,
          longitude: 18.0686,
        });

        await new Promise(r => setTimeout(r, 1000));

        const notifSnapB = await adminDb.ref('userNotifications/user_b').get();
        assert.strictEqual(notifSnapB.exists(), false, 'Candidates must receive zero notifications for ordinary map_pin');
      });

      it('36. Invalid coordinates (< -90, > 90, non-numeric, NaN) rejected', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');

        await assert.rejects(
          callable({ eventType: 'gigConcert', latitude: 95, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'gigConcert', latitude: -91, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'gigConcert', latitude: 59.0, longitude: 185 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'gigConcert', latitude: 'invalid_lat', longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );
      });

      it('37. Invalid event types (subs, newMember, paid, unknown) rejected', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');

        await assert.rejects(
          callable({ eventType: 'subs', latitude: 59.0, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'newMember', latitude: 59.0, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'paid', latitude: 59.0, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        await assert.rejects(
          callable({ eventType: 'arbitraryType', latitude: 59.0, longitude: 18.0 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );
      });

      it('38. Staffing and server-controlled fields supplied by client are stripped', async () => {
        const callable = httpsCallable(functionsUserA, 'createMapPin');
        const result = await callable({
          eventType: 'gigConcert',
          latitude: 59.3293,
          longitude: 18.0686,
          Responses: { user_b: true },
          PublicationId: 'forged_pub_123',
          Status: 'cancelled',
          NotificationMode: 'forged_mode',
          AssignedUserId: 'user_b',
          TargetUserIds: ['user_b', 'user_c'],
        });

        const pinSnap = await adminDb.ref(`SubRequests/${result.data.id}`).get();
        const pin = pinSnap.val();
        assert.strictEqual(pin.Status, 'published', 'Server must enforce Status: published');
        assert.strictEqual(pin.NotificationMode, 'map_pin', 'Server must enforce NotificationMode: map_pin');
        assert.strictEqual(pin.Responses, undefined, 'Responses must be stripped');
        assert.strictEqual(pin.PublicationId, undefined, 'PublicationId must be stripped');
        assert.strictEqual(pin.AssignedUserId, undefined, 'AssignedUserId must be stripped');
        assert.strictEqual(pin.TargetUserIds, undefined, 'TargetUserIds must be stripped');
      });

      it('39. Band membership verification allows band member and rejects non-member', async () => {
        const bandId = 'band_membership_pin_test';
        await adminDb.ref(`Bands/${bandId}`).set({
          Name: 'Pin Test Band',
          Members_band: {
            user_a: { Role: 'Member' },
          },
        });

        // user_a is a member -> succeeds
        const callableA = httpsCallable(functionsUserA, 'createMapPin');
        const resultA = await callableA({
          eventType: 'gigConcert',
          bandId: bandId,
          latitude: 59.3293,
          longitude: 18.0686,
        });
        assert.strictEqual(resultA.data.success, true);

        // user_b is not a member -> rejected with permission-denied
        const callableB = httpsCallable(functionsUserB, 'createMapPin');
        await assert.rejects(
          callableB({
            eventType: 'gigConcert',
            bandId: bandId,
            latitude: 59.3293,
            longitude: 18.0686,
          }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );
      });

      it('40. Genuine staffing request creates expected published record and notification', async () => {
        await adminDb.ref('users/user_b/info').set({
          UserType: 'Electric Guitar',
          Instruments: ['Electric Guitar'],
          PushToken: 'token_b',
        });
        await adminDb.ref('Bands/band_staffing_1').set({
          Name: 'Staffing Band',
          Members_band: {
            user_a: { Role: 'Leader' },
          },
        });

        await adminDb.ref('SubRequests/staffing_req_1').set({
          SubRequestId: 'staffing_req_1',
          CreatorUserId: 'user_a',
          bandId: 'band_staffing_1',
          VoicePart: 'Electric Guitar',
          Status: 'published',
          Location: 'Stockholm, Sweden',
          CreatedAt: Date.now(),
        });

        let receivedNotif = false;
        for (let i = 0; i < 50; i++) {
          const notifSnapB = await adminDb.ref('userNotifications/user_b').get();
          if (notifSnapB.exists() && notifSnapB.val()) {
            receivedNotif = true;
            break;
          }
          await new Promise(r => setTimeout(r, 200));
        }
        assert.strictEqual(receivedNotif, true, 'Genuine staffing request MUST notify eligible candidates');
      });

      it('41. updateMapPin updates canonical /SubRequests/{id} and leaves mirrors byte-for-byte unchanged', async () => {
        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const createResult = await createCallable({
          eventType: 'gigConcert',
          latitude: 59.3293,
          longitude: 18.0686,
          title: 'Original Title',
          description: 'Original Desc',
        });
        const pinId = createResult.data.id;

        // 1. Populate legacy locations to prove they remain byte-for-byte unchanged
        const legacyPubData = { SubRequestId: pinId, Title: 'Legacy Mirror Title', oldFlag: true, untouchedValue: 42 };
        const legacyUserData = { SubRequestId: pinId, Title: 'User Mirror Title', note: 'Legacy Note', count: 99 };
        await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId}`).set(legacyPubData);
        await adminDb.ref(`users/user_a/SubRequests/${pinId}`).set(legacyUserData);

        const updateCallable = httpsCallable(functionsUserA, 'updateMapPin');
        const updateResult = await updateCallable({
          pinId: pinId,
          title: 'Updated Title',
          description: 'Updated Desc',
          latitude: 59.3400,
          longitude: 18.0700,
        });

        assert.strictEqual(updateResult.data.success, true);
        assert.strictEqual(updateResult.data.pin.Title, 'Updated Title');
        assert.strictEqual(updateResult.data.pin.Latitude, 59.3400);

        // Check canonical record
        const canonSnap = await adminDb.ref(`SubRequests/${pinId}`).get();
        assert.strictEqual(canonSnap.val().Title, 'Updated Title');
        assert.strictEqual(canonSnap.val().Latitude, 59.3400);

        // Assert existing legacy mirrors remain byte-for-byte unchanged
        const pubSnap = await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId}`).get();
        assert.deepStrictEqual(pubSnap.val(), legacyPubData);

        const userSnap = await adminDb.ref(`users/user_a/SubRequests/${pinId}`).get();
        assert.deepStrictEqual(userSnap.val(), legacyUserData);

        // 2. Missing mirrors are not created
        const create2 = await createCallable({
          eventType: 'gigConcert',
          latitude: 59.31,
          longitude: 18.05,
          title: 'Pin Without Mirrors',
        });
        const pinId2 = create2.data.id;
        await updateCallable({
          pinId: pinId2,
          title: 'Updated Pin Without Mirrors',
        });
        const pubSnap2 = await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId2}`).get();
        assert.strictEqual(pubSnap2.exists(), false, 'Missing PublishedSubRequests mirror must not be created');
        const userSnap2 = await adminDb.ref(`users/user_a/SubRequests/${pinId2}`).get();
        assert.strictEqual(userSnap2.exists(), false, 'Missing user SubRequests mirror must not be created');
      });

      it('42. updateMapPin authorization: Leader and Admin succeed, ordinary member, unrelated user, and missing bandId denied, creator authorized', async () => {
        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const updateCallableA = httpsCallable(functionsUserA, 'updateMapPin');
        const updateCallableB = httpsCallable(functionsUserB, 'updateMapPin');
        const updateCallableC = httpsCallable(functionsUserC, 'updateMapPin');

        // Case 1: Creator remains authorized independently of band role
        const noBandPin = await createCallable({
          eventType: 'jamSession',
          latitude: 59.32,
          longitude: 18.06,
          title: 'Creator Independent Pin',
        });
        const noBandPinId = noBandPin.data.id;
        const creatorUpdate = await updateCallableA({ pinId: noBandPinId, title: 'Creator Self Update' });
        assert.strictEqual(creatorUpdate.data.success, true);
        assert.strictEqual(creatorUpdate.data.pin.Title, 'Creator Self Update');

        // Case 2: Missing bandId does not grant band authorization to others
        await assert.rejects(
          updateCallableB({ pinId: noBandPinId, title: 'Hacker Update' }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );

        // Setup band with Members_band
        const bandId = 'band_auth_matrix_test';
        await adminDb.ref(`Bands/${bandId}`).set({
          Name: 'Matrix Band',
          Members_band: {
            user_a: { Role: 'Member' },  // Creator is only Member in band
            user_b: { Role: 'Leader' },  // user_b is Leader
            user_c: { Role: 'Member' },  // user_c is ordinary Member
          },
        });

        const bandPin = await createCallable({
          eventType: 'gigConcert',
          bandId: bandId,
          latitude: 59.32,
          longitude: 18.06,
          title: 'Band Pin Title',
        });
        const bandPinId = bandPin.data.id;

        // Case 3: Leader succeeds
        const leaderUpdate = await updateCallableB({ pinId: bandPinId, title: 'Leader Title' });
        assert.strictEqual(leaderUpdate.data.success, true);
        assert.strictEqual(leaderUpdate.data.pin.Title, 'Leader Title');

        // Case 4: Admin succeeds
        await adminDb.ref(`Bands/${bandId}/Members_band/user_b/Role`).set('Admin');
        const adminUpdate = await updateCallableB({ pinId: bandPinId, title: 'Admin Title' });
        assert.strictEqual(adminUpdate.data.success, true);
        assert.strictEqual(adminUpdate.data.pin.Title, 'Admin Title');

        // Case 5: Ordinary member is denied
        await assert.rejects(
          updateCallableC({ pinId: bandPinId, title: 'Member Title' }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );

        // Case 6: Unrelated user is denied
        await adminDb.ref(`Bands/${bandId}/Members_band/user_b/Role`).remove(); // user_b removed from band
        await assert.rejects(
          updateCallableB({ pinId: bandPinId, title: 'Unrelated Title' }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );
      });

      it('43. updateMapPin validates coordinates, field lengths, non-empty pinId, and non-map-pin records', async () => {
        const updateCallableA = httpsCallable(functionsUserA, 'updateMapPin');

        // Missing pinId
        await assert.rejects(
          updateCallableA({ title: 'New' }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        const realCreateCallable = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await realCreateCallable({
          eventType: 'rehearsal',
          latitude: 59.32,
          longitude: 18.06,
        });
        const pinId = pin.data.id;

        // Invalid coords (> 90 lat)
        await assert.rejects(
          updateCallableA({ pinId: pinId, latitude: 120, longitude: 18.06 }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        // Field length validation (title > 120 chars)
        await assert.rejects(
          updateCallableA({ pinId: pinId, title: 'a'.repeat(125) }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );

        // Non-map-pin record rejected
        await adminDb.ref('SubRequests/regular_staffing_item').set({
          SubRequestId: 'regular_staffing_item',
          CreatorUserId: 'user_a',
          NotificationMode: 'staffing',
          eventType: 'subs',
        });
        await assert.rejects(
          updateCallableA({ pinId: 'regular_staffing_item', title: 'New' }),
          (err) => err.code === 'functions/failed-precondition' || err.code === 'failed-precondition'
        );
      });

      it('44. deleteMapPin rejects unauthenticated callers and invalid pinId', async () => {
        const unauthCallable = httpsCallable(functionsUnauth, 'deleteMapPin');
        await assert.rejects(
          unauthCallable({ pinId: 'pin_1' }),
          (err) => isAuthError(err)
        );

        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        await assert.rejects(
          callableA({ pinId: '' }),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );
        await assert.rejects(
          callableA({}),
          (err) => err.code === 'functions/invalid-argument' || err.code === 'invalid-argument'
        );
      });

      it('45. deleteMapPin on non-existent pin returns idempotent success', async () => {
        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        const res = await callableA({ pinId: 'does_not_exist_99999' });
        assert.strictEqual(res.data.success, true);
        assert.strictEqual(res.data.alreadyDeleted, true);
      });

      it('46. deleteMapPin rejects non-map-pin records with failed-precondition', async () => {
        await adminDb.ref('SubRequests/not_a_map_pin').set({
          SubRequestId: 'not_a_map_pin',
          CreatorUserId: 'user_a',
          NotificationMode: 'standard',
        });
        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        await assert.rejects(
          callableA({ pinId: 'not_a_map_pin' }),
          (err) => err.code === 'functions/failed-precondition' || err.code === 'failed-precondition'
        );
      });

      it('47. deleteMapPin rejects unauthorized caller with permission-denied', async () => {
        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await createCallable({
          eventType: 'jamSession',
          latitude: 59.32,
          longitude: 18.06,
        });
        const pinId = pin.data.id;

        const callableB = httpsCallable(functionsUserB, 'deleteMapPin');
        await assert.rejects(
          callableB({ pinId: pinId }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );
      });

      it('48. deleteMapPin by creator succeeds, cleans canonical & legacy mirrors, and is idempotent', async () => {
        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await createCallable({
          eventType: 'jamSession',
          latitude: 59.32,
          longitude: 18.06,
        });
        const pinId = pin.data.id;

        // Plant legacy mirrors
        await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId}`).set({ legacy: true });
        await adminDb.ref(`users/user_a/SubRequests/${pinId}`).set({ legacy: true });

        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        const delResult = await callableA({ pinId: pinId });
        assert.strictEqual(delResult.data.success, true);

        // Check canonical deleted
        const canonSnap = await adminDb.ref(`SubRequests/${pinId}`).get();
        assert.strictEqual(canonSnap.exists(), false);

        // Check legacy copies removed
        const pubSnap = await adminDb.ref(`BandEvents/PublishedSubRequests/${pinId}`).get();
        assert.strictEqual(pubSnap.exists(), false);

        const userSnap = await adminDb.ref(`users/user_a/SubRequests/${pinId}`).get();
        assert.strictEqual(userSnap.exists(), false);

        // Calling a second time on the already deleted pin succeeds idempotently
        const secondDel = await callableA({ pinId: pinId });
        assert.strictEqual(secondDel.data.success, true);
        assert.strictEqual(secondDel.data.alreadyDeleted, true);
      });

      it('49. deleteMapPin by band leader/admin succeeds', async () => {
        const bandId = 'band_del_test_1';
        await adminDb.ref(`Bands/${bandId}`).set({
          Name: 'Band Del Test',
          Members_band: {
            user_b: { Role: 'Leader' },
            user_a: { Role: 'Member' },
          },
        });

        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await createCallable({
          eventType: 'gigConcert',
          bandId: bandId,
          latitude: 59.32,
          longitude: 18.06,
        });
        const pinId = pin.data.id;

        // user_b is Leader -> can delete
        const callableB = httpsCallable(functionsUserB, 'deleteMapPin');
        const delResult = await callableB({ pinId: pinId });
        assert.strictEqual(delResult.data.success, true);

        const canonSnap = await adminDb.ref(`SubRequests/${pinId}`).get();
        assert.strictEqual(canonSnap.exists(), false);
      });

      it('50. deleteMapPin: canonical and mirrors all absent -> idempotent success', async () => {
        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        const res = await callableA({ pinId: 'non_existent_pin_completely_absent' });
        assert.strictEqual(res.data.success, true);
        assert.strictEqual(res.data.id, 'non_existent_pin_completely_absent');
        assert.strictEqual(res.data.alreadyDeleted, true);
      });

      it('51. deleteMapPin: canonical missing but authorized creator-owned legacy map-pin mirror exists -> cleaned successfully', async () => {
        const pinId = 'orphan_legacy_pin_1';
        // Plant legacy mirror only (canonical SubRequests/{pinId} does not exist)
        await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).set({
          SubRequestId: pinId,
          CreatorUserId: 'user_a',
          NotificationMode: 'map_pin',
          title: 'Legacy Orphan Pin',
        });
        await adminDb.ref('users/user_a/SubRequests/' + pinId).set({
          SubRequestId: pinId,
          CreatorUserId: 'user_a',
          NotificationMode: 'map_pin',
        });

        // Verify canonical does not exist
        const canonBefore = await adminDb.ref('SubRequests/' + pinId).get();
        assert.strictEqual(canonBefore.exists(), false);

        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        const res = await callableA({ pinId: pinId });
        assert.strictEqual(res.data.success, true);
        assert.strictEqual(res.data.id, pinId);

        // Verify legacy mirrors are cleaned
        const pubAfter = await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).get();
        assert.strictEqual(pubAfter.exists(), false);
        const userAfter = await adminDb.ref('users/user_a/SubRequests/' + pinId).get();
        assert.strictEqual(userAfter.exists(), false);
      });

      it('52. deleteMapPin: canonical missing but unauthorized caller targets legacy mirror -> permission-denied', async () => {
        const pinId = 'orphan_legacy_pin_stranger';
        await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).set({
          SubRequestId: pinId,
          CreatorUserId: 'user_a',
          NotificationMode: 'map_pin',
        });

        // user_b is not creator and no band leader role
        const callableB = httpsCallable(functionsUserB, 'deleteMapPin');
        await assert.rejects(
          callableB({ pinId: pinId }),
          (err) => err.code === 'functions/permission-denied' || err.code === 'permission-denied'
        );

        // Record must still exist
        const pubSnap = await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).get();
        assert.strictEqual(pubSnap.exists(), true);
      });

      it('53. deleteMapPin: canonical missing but legacy record is a staffing request -> failed-precondition', async () => {
        const pinId = 'orphan_legacy_staffing_req';
        // Plant legacy staffing record without map_pin notification mode
        await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).set({
          SubRequestId: pinId,
          CreatorUserId: 'user_a',
          NotificationMode: 'staffing_request',
        });

        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        await assert.rejects(
          callableA({ pinId: pinId }),
          (err) => err.code === 'functions/failed-precondition' || err.code === 'failed-precondition'
        );

        // Record must not be deleted
        const pubSnap = await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).get();
        assert.strictEqual(pubSnap.exists(), true);
      });

      it('54. deleteMapPin: successful deletion leaves none of the relevant paths behind and creates no tombstone', async () => {
        const createCallable = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await createCallable({
          eventType: 'jamSession',
          latitude: 59.33,
          longitude: 18.07,
          title: 'Clean Sweep Pin',
        });
        const pinId = pin.data.id;

        // Plant all potential paths
        await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).set({ legacy: true });
        await adminDb.ref('users/user_a/SubRequests/' + pinId).set({ legacy: true });

        const callableA = httpsCallable(functionsUserA, 'deleteMapPin');
        const res = await callableA({ pinId: pinId });
        assert.strictEqual(res.data.success, true);

        // Verify none of the paths exist
        const canonSnap = await adminDb.ref('SubRequests/' + pinId).get();
        assert.strictEqual(canonSnap.exists(), false);
        const pubSnap = await adminDb.ref('BandEvents/PublishedSubRequests/' + pinId).get();
        assert.strictEqual(pubSnap.exists(), false);
        const userSnap = await adminDb.ref('users/user_a/SubRequests/' + pinId).get();
        assert.strictEqual(userSnap.exists(), false);

        // Verify no tombstone write under CancelledSubRequests
        const cancelSnap = await adminDb.ref('BandEvents/CancelledSubRequests/' + pinId).get();
        assert.strictEqual(cancelSnap.exists(), false);
      });
    });

    describe('SUBREQUEST-SECURITY-MIGRATION-01: Integration Tests for SubRequest Lifecycle and Feeds', () => {
      it('55. publishSubRequestGroup: public staffing request writes to canonical, publicSubRequests, creator feed, and zero legacy mirror writes', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        const res = await publish({
          requestGroupId: 'grp_pub_test',
          slots: [{
            slotId: 'slot_pub_test_1',
            voicePart: 'Drums',
            date: '2026-12-01',
            searchSource: 'search_all',
          }],
        });
        assert.strictEqual(res.data.success, true);

        const canon = await adminDb.ref('SubRequests/slot_pub_test_1').get();
        assert.strictEqual(canon.exists(), true);
        assert.strictEqual(canon.val().CreatorUserId, 'user_a');

        const pub = await adminDb.ref('publicSubRequests/slot_pub_test_1').get();
        assert.strictEqual(pub.exists(), true);
        assert.strictEqual(pub.val().voicePart, 'Drums');

        const creator = await adminDb.ref('creatorSubRequestFeed/user_a/slot_pub_test_1').get();
        assert.strictEqual(creator.exists(), true);

        const userBFeed = await adminDb.ref('userSubRequestFeed/user_b/slot_pub_test_1').get();
        assert.strictEqual(userBFeed.exists(), false);

        const legacy = await adminDb.ref('BandEvents/PublishedSubRequests/slot_pub_test_1').get();
        assert.strictEqual(legacy.exists(), false);
      });

      it('56. publishSubRequestGroup: Direct Invitation writes to userSubRequestFeed and subRequestAudience, NEVER to publicSubRequests', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        const res = await publish({
          requestGroupId: 'grp_direct_test',
          slots: [{
            slotId: 'slot_direct_test_1',
            voicePart: 'Bass',
            date: '2026-12-02',
            type: 'direct_invitation',
            targetUserIds: ['user_b'],
          }],
        });
        assert.strictEqual(res.data.success, true);

        const canon = await adminDb.ref('SubRequests/slot_direct_test_1').get();
        assert.strictEqual(canon.exists(), true);

        const pub = await adminDb.ref('publicSubRequests/slot_direct_test_1').get();
        assert.strictEqual(pub.exists(), false);

        const userBFeed = await adminDb.ref('userSubRequestFeed/user_b/slot_direct_test_1').get();
        assert.strictEqual(userBFeed.exists(), true);

        const userCFeed = await adminDb.ref('userSubRequestFeed/user_c/slot_direct_test_1').get();
        assert.strictEqual(userCFeed.exists(), false);

        const audience = await adminDb.ref('subRequestAudience/slot_direct_test_1/user_b').get();
        assert.strictEqual(audience.val(), true);
      });

      it('57. publishSubRequestGroup: Favorites-only without targetUserIds restricts to favorites, NEVER leaks to public', async () => {
        await adminDb.ref('users/user_a/Favorites/user_b').set(true);

        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        const res = await publish({
          requestGroupId: 'grp_fav_test',
          slots: [{
            slotId: 'slot_fav_test_1',
            voicePart: 'Guitar',
            date: '2026-12-03',
            searchSource: 'favorites',
            targetUserIds: [],
          }],
        });
        assert.strictEqual(res.data.success, true);

        const canon = await adminDb.ref('SubRequests/slot_fav_test_1').get();
        assert.strictEqual(canon.exists(), true);

        const pub = await adminDb.ref('publicSubRequests/slot_fav_test_1').get();
        assert.strictEqual(pub.exists(), false);

        const userBFeed = await adminDb.ref('userSubRequestFeed/user_b/slot_fav_test_1').get();
        assert.strictEqual(userBFeed.exists(), true);

        const userCFeed = await adminDb.ref('userSubRequestFeed/user_c/slot_fav_test_1').get();
        assert.strictEqual(userCFeed.exists(), false);
      });

      it('58. createMapPin: music promo pin never enters publicSubRequests or user feeds', async () => {
        const createPin = httpsCallable(functionsUserA, 'createMapPin');
        const pin = await createPin({
          eventType: 'jamSession',
          latitude: 59.33,
          longitude: 18.06,
          title: 'Acoustic Jam',
        });
        const pinId = pin.data.id;

        const canon = await adminDb.ref('SubRequests/' + pinId).get();
        assert.strictEqual(canon.exists(), true);
        assert.strictEqual(canon.val().NotificationMode, 'map_pin');

        const pub = await adminDb.ref('publicSubRequests/' + pinId).get();
        assert.strictEqual(pub.exists(), false);

        const userBFeed = await adminDb.ref('userSubRequestFeed/user_b/' + pinId).get();
        assert.strictEqual(userBFeed.exists(), false);
      });

      it('59. deleteSubRequest: completely removes canonical, public, user feed, creator feed, audience and legacy mirrors', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        await publish({
          requestGroupId: 'grp_del_test',
          slots: [{
            slotId: 'slot_del_test_1',
            voicePart: 'Keys',
            type: 'direct_invitation',
            targetUserIds: ['user_b'],
          }],
        });

        await adminDb.ref('BandEvents/PublishedSubRequests/slot_del_test_1').set({ legacy: true });

        const del = httpsCallable(functionsUserA, 'deleteSubRequest');
        const res = await del({ subRequestId: 'slot_del_test_1' });
        assert.strictEqual(res.data.success, true);

        const canon = await adminDb.ref('SubRequests/slot_del_test_1').get();
        assert.strictEqual(canon.exists(), false);

        const pub = await adminDb.ref('publicSubRequests/slot_del_test_1').get();
        assert.strictEqual(pub.exists(), false);

        const userFeed = await adminDb.ref('userSubRequestFeed/user_b/slot_del_test_1').get();
        assert.strictEqual(userFeed.exists(), false);

        const creatorFeed = await adminDb.ref('creatorSubRequestFeed/user_a/slot_del_test_1').get();
        assert.strictEqual(creatorFeed.exists(), false);

        const aud = await adminDb.ref('subRequestAudience/slot_del_test_1').get();
        assert.strictEqual(aud.exists(), false);

        const legacy = await adminDb.ref('BandEvents/PublishedSubRequests/slot_del_test_1').get();
        assert.strictEqual(legacy.exists(), false);
      });

      it('60. assignSubstitute: removes slot from public and user feeds and updates creator feed to assigned', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        await publish({
          requestGroupId: 'grp_assign_test',
          slots: [{
            slotId: 'slot_assign_test_1',
            voicePart: 'Vocals',
            searchSource: 'search_all',
          }],
        });

        const assign = httpsCallable(functionsUserA, 'assignSubstitute');
        const res = await assign({
          subRequestId: 'slot_assign_test_1',
          candidateUserId: 'user_b',
          candidateName: 'Bob Singer',
        });
        assert.strictEqual(res.data.success, true);

        const pub = await adminDb.ref('publicSubRequests/slot_assign_test_1').get();
        assert.strictEqual(pub.exists(), false);

        const canon = await adminDb.ref('SubRequests/slot_assign_test_1').get();
        assert.strictEqual(canon.val().Status, 'assigned');
        assert.strictEqual(canon.val().IsSelected, true);

        const creator = await adminDb.ref('creatorSubRequestFeed/user_a/slot_assign_test_1').get();
        assert.strictEqual(creator.val().status, 'assigned');
        assert.strictEqual(creator.val().isSelected, true);
        assert.strictEqual(creator.val().assignedUserId, 'user_b');
      });

      it('61. revokeSubstituteAssignment: restores slot to published status and re-populates exact feed', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        await publish({
          requestGroupId: 'grp_revoke_test',
          slots: [{
            slotId: 'slot_revoke_test_1',
            voicePart: 'Vocals',
            searchSource: 'search_all',
          }],
        });

        const assign = httpsCallable(functionsUserA, 'assignSubstitute');
        await assign({
          subRequestId: 'slot_revoke_test_1',
          candidateUserId: 'user_b',
          candidateName: 'Bob Singer',
        });

        const revoke = httpsCallable(functionsUserA, 'revokeSubstituteAssignment');
        const res = await revoke({
          subRequestId: 'slot_revoke_test_1',
          candidateUserId: 'user_b',
        });
        assert.strictEqual(res.data.success, true);

        const canon = await adminDb.ref('SubRequests/slot_revoke_test_1').get();
        assert.strictEqual(canon.val().Status, 'published');
        assert.strictEqual(canon.val().IsSelected, false);

        const creator = await adminDb.ref('creatorSubRequestFeed/user_a/slot_revoke_test_1').get();
        assert.strictEqual(creator.val().status, 'published');
        assert.strictEqual(creator.val().isSelected, false);

        const pub = await adminDb.ref('publicSubRequests/slot_revoke_test_1').get();
        assert.strictEqual(pub.exists(), true);
      });

      it('62. public to favorites transition removes the publicSubRequests entry', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        await publish({
          requestGroupId: 'grp_switch_test',
          slots: [{
            slotId: 'slot_switch_test_1',
            voicePart: 'Saxophone',
            searchSource: 'search_all',
          }],
        });
        let pubSnap = await adminDb.ref('publicSubRequests/slot_switch_test_1').get();
        assert.strictEqual(pubSnap.exists(), true);

        await adminDb.ref('users/user_a/Favorites/user_b').set(true);

        await publish({
          requestGroupId: 'grp_switch_test',
          slots: [{
            slotId: 'slot_switch_test_1',
            voicePart: 'Saxophone',
            searchSource: 'favorites',
            targetUserIds: ['user_b'],
          }],
        });

        pubSnap = await adminDb.ref('publicSubRequests/slot_switch_test_1').get();
        assert.strictEqual(pubSnap.exists(), false);

        const userFeed = await adminDb.ref('userSubRequestFeed/user_b/slot_switch_test_1').get();
        assert.strictEqual(userFeed.exists(), true);
      });

      it('63. changing audience removes the subrequest from previous recipients feeds', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        await publish({
          requestGroupId: 'grp_aud_test',
          slots: [{
            slotId: 'slot_aud_test_1',
            voicePart: 'Trumpet',
            type: 'direct_invitation',
            targetUserIds: ['user_b'],
          }],
        });
        let feedB = await adminDb.ref('userSubRequestFeed/user_b/slot_aud_test_1').get();
        assert.strictEqual(feedB.exists(), true);

        await publish({
          requestGroupId: 'grp_aud_test',
          slots: [{
            slotId: 'slot_aud_test_1',
            voicePart: 'Trumpet',
            type: 'direct_invitation',
            targetUserIds: ['user_c'],
          }],
        });

        feedB = await adminDb.ref('userSubRequestFeed/user_b/slot_aud_test_1').get();
        assert.strictEqual(feedB.exists(), false);

        const feedC = await adminDb.ref('userSubRequestFeed/user_c/slot_aud_test_1').get();
        assert.strictEqual(feedC.exists(), true);

        const audB = await adminDb.ref('subRequestAudience/slot_aud_test_1/user_b').get();
        assert.strictEqual(audB.exists(), false);
        const audC = await adminDb.ref('subRequestAudience/slot_aud_test_1/user_c').get();
        assert.strictEqual(audC.val(), true);
      });

      it('64. retry/re-publishing creates no duplicates and maintains idempotent state', async () => {
        const publish = httpsCallable(functionsUserA, 'publishSubRequestGroup');
        const payload = {
          requestGroupId: 'grp_retry_test',
          slots: [{
            slotId: 'slot_retry_test_1',
            voicePart: 'Cello',
            searchSource: 'search_all',
          }],
        };

        const res1 = await publish(payload);
        assert.strictEqual(res1.data.success, true);

        const res2 = await publish(payload);
        assert.strictEqual(res2.data.success, true);
        assert.strictEqual(res1.data.publicationId, res2.data.publicationId);

        const canon = await adminDb.ref('SubRequests/slot_retry_test_1').get();
        assert.strictEqual(canon.exists(), true);

        const pub = await adminDb.ref('publicSubRequests/slot_retry_test_1').get();
        assert.strictEqual(pub.exists(), true);
      });
    });
  });
});
