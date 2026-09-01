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
});
