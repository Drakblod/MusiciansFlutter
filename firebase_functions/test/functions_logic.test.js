const assert = require('assert');
const crypto = require('crypto');

// Mock Database & FCM implementation for Cloud Functions logic tests
class MockSnapshot {
  constructor(val) {
    this._val = val;
  }
  val() {
    return this._val;
  }
  exists() {
    return this._val !== null && this._val !== undefined;
  }
}

class MockRef {
  constructor(path, db) {
    this.path = path;
    this.db = db;
  }

  async get() {
    if (this.db.data[this.path] !== undefined) {
      return new MockSnapshot(this.db.data[this.path]);
    }
    for (const dbKey of Object.keys(this.db.data)) {
      if (this.path.startsWith(dbKey + '/')) {
        const subPath = this.path.substring(dbKey.length + 1).split('/');
        let curr = this.db.data[dbKey];
        for (const part of subPath) {
          if (curr && typeof curr === 'object') {
            curr = curr[part];
          } else {
            curr = undefined;
            break;
          }
        }
        if (curr !== undefined) {
          return new MockSnapshot(curr);
        }
      }
    }
    return new MockSnapshot(null);
  }

  async set(val) {
    this.db.data[this.path] = JSON.parse(JSON.stringify(val));
  }

  async update(val) {
    if (!val || typeof val !== 'object') return;
    const targetPath = this.path ? (this.path.startsWith('/') ? this.path.substring(1) : this.path) : '';
    if (targetPath) {
      if (!this.db.data[targetPath] || typeof this.db.data[targetPath] !== 'object') {
        this.db.data[targetPath] = {};
      }
      Object.assign(this.db.data[targetPath], JSON.parse(JSON.stringify(val)));
    }

    Object.keys(val).forEach((k) => {
      const relPath = k.startsWith('/') ? k.substring(1) : k;
      const fullPath = targetPath ? `${targetPath}/${relPath}` : relPath;
      this.db.data[fullPath] = val[k];

      const parts = fullPath.split('/');
      if (parts.length > 1) {
        const parentPath = parts.slice(0, -1).join('/');
        const leafKey = parts[parts.length - 1];
        if (!this.db.data[parentPath] || typeof this.db.data[parentPath] !== 'object') {
          this.db.data[parentPath] = {};
        }
        this.db.data[parentPath][leafKey] = val[k];
      }

      Object.keys(this.db.data).forEach((dbKey) => {
        if (fullPath.startsWith(dbKey + '/')) {
          const subPath = fullPath.substring(dbKey.length + 1).split('/');
          let curr = this.db.data[dbKey];
          for (let i = 0; i < subPath.length - 1; i++) {
            if (curr && typeof curr === 'object') {
              curr = curr[subPath[i]];
            } else {
              curr = null;
              break;
            }
          }
          if (curr && typeof curr === 'object') {
            curr[subPath[subPath.length - 1]] = val[k];
          }
        }
      });
    });
  }

  push() {
    const autoId = 'auto_' + Math.random().toString(36).substring(2, 9);
    const childPath = `${this.path}/${autoId}`;
    return {
      key: autoId,
      set: async (val) => {
        this.db.data[childPath] = JSON.parse(JSON.stringify(val));
      }
    };
  }

  async transaction(updateFn) {
    const currentVal = this.db.data[this.path] || null;
    const newVal = updateFn(currentVal);
    if (newVal === undefined) {
      return { committed: false, snapshot: new MockSnapshot(currentVal) };
    }
    this.db.data[this.path] = JSON.parse(JSON.stringify(newVal));
    return { committed: true, snapshot: new MockSnapshot(newVal) };
  }
}

class MockDatabase {
  constructor() {
    this.data = {};
  }
  ref(path) {
    return new MockRef(path, this);
  }
}

// Logic implementations mirroring index.js for test verification
function computePairHash(uid1, uid2) {
  const sorted = [uid1, uid2].sort();
  return crypto.createHash('sha256').update(`${sorted[0]}_${sorted[1]}`).digest('hex');
}

async function handleGetOrCreateDirectConversation(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { otherUserId } = request.data || {};
  if (!otherUserId || typeof otherUserId !== 'string' || otherUserId === uid) {
    throw new Error('invalid-argument');
  }

  const pairHash = computePairHash(uid, otherUserId);
  const keyRef = db.ref(`directConversationKeys/${pairHash}`);
  let conversationId = null;

  const txResult = await keyRef.transaction((currentData) => {
    if (currentData === null) {
      const newConvRef = db.ref('conversations').push();
      return {
        conversationId: newConvRef.key,
        createdTimestamp: new Date().toISOString()
      };
    }
    return currentData;
  });

  conversationId = txResult.snapshot.val().conversationId;
  const convRef = db.ref(`conversations/${conversationId}`);
  const convSnap = await convRef.get();

  if (!convSnap.exists()) {
    await convRef.set({
      participants: { [uid]: true, [otherUserId]: true },
      createdTimestamp: new Date().toISOString()
    });
  } else {
    // Participant pair verification during recovery
    const convData = convSnap.val() || {};
    const parts = convData.participants || {};
    if (!parts[uid] || !parts[otherUserId] || Object.keys(parts).length !== 2) {
      throw new Error('corrupted-pair-key');
    }
  }

  // Idempotent repair of userConversations entries
  const user1Ref = db.ref(`userConversations/${uid}/${conversationId}`);
  const user2Ref = db.ref(`userConversations/${otherUserId}/${conversationId}`);

  const snap1 = await user1Ref.get();
  if (!snap1.exists()) {
    await user1Ref.set({
      otherUserId: otherUserId,
      lastMessageText: 'Conversation started',
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: false,
      conversationType: 'direct'
    });
  }

  const snap2 = await user2Ref.get();
  if (!snap2.exists()) {
    await user2Ref.set({
      otherUserId: uid,
      lastMessageText: 'Conversation started',
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: false,
      conversationType: 'direct'
    });
  }

  return { conversationId };
}

async function handleCreateAgreementConversation(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { subRequestId, applicantId } = request.data || {};
  if (!subRequestId || !applicantId) throw new Error('invalid-argument');

  const subSnap = await db.ref(`SubRequests/${subRequestId}`).get();
  if (!subSnap.exists()) throw new Error('not-found');
  const subData = subSnap.val();

  let receiverUserId = null;
  if (subData.createdBy === uid) {
    receiverUserId = applicantId;
  } else if (applicantId === uid) {
    receiverUserId = subData.createdBy;
  } else {
    throw new Error('permission-denied');
  }

  const conversationId = `agreement_${subRequestId}_${applicantId}`;
  await db.ref(`conversations/${conversationId}`).set({
    participants: { [uid]: true, [receiverUserId]: true },
    agreement: { subRequestId, applicantId, creatorId: subData.createdBy }
  });

  await db.ref(`userConversations/${uid}/${conversationId}`).set({
    otherUserId: receiverUserId,
    lastMessageText: 'Agreement created',
    lastMessageTimestamp: new Date().toISOString(),
    hasUnread: false,
    conversationType: 'agreement'
  });

  return { conversationId };
}

async function handleSendDirectMessage(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { conversationId, text, receiverUserId } = request.data || {};
  if (!conversationId || !text || !receiverUserId) throw new Error('invalid-argument');

  const convSnap = await db.ref(`conversations/${conversationId}`).get();
  if (!convSnap.exists()) throw new Error('not-found');
  const convData = convSnap.val();
  const parts = convData.participants || {};
  if (!parts[uid] || !parts[receiverUserId]) throw new Error('permission-denied');

  const msgRef = db.ref(`conversations/${conversationId}/messages`).push();
  const timestamp = new Date().toISOString();
  await msgRef.set({
    senderId: uid,
    receiverId: receiverUserId,
    text,
    timestamp,
    isRead: false
  });

  await db.ref(`userConversations/${uid}/${conversationId}`).update({
    lastMessageText: text,
    lastMessageTimestamp: timestamp,
    hasUnread: false
  });

  await db.ref(`userConversations/${receiverUserId}/${conversationId}`).update({
    lastMessageText: text,
    lastMessageTimestamp: timestamp,
    hasUnread: true
  });

  return { success: true };
}

function isParticipantMember(pMap, targetUid) {
  if (!pMap || !targetUid || typeof targetUid !== 'string') return false;

  if (Array.isArray(pMap)) {
    return pMap.some(item => item === targetUid);
  }

  if (typeof pMap === 'object' && pMap !== null) {
    if (!Object.prototype.hasOwnProperty.call(pMap, targetUid)) {
      return false;
    }
    const val = pMap[targetUid];
    if (val === false || val === 0 || val === 'false' || val === '' || val === null || val === undefined) {
      return false;
    }
    return true;
  }

  return false;
}

async function handleMarkDirectConversationRead(request, db) {
  const selfUid = request.auth?.uid;
  if (!selfUid) throw new Error('unauthenticated');
  const { conversationId } = request.data || {};
  if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
    throw new Error('invalid-argument');
  }

  const trimmedConvId = conversationId.trim();
  const convSnap = await db.ref(`conversations/${trimmedConvId}`).get();
  if (!convSnap.exists()) throw new Error('not-found');

  const convVal = convSnap.val() || {};
  const pMap = convVal.participants || convVal.Participants;
  const isParticipant = isParticipantMember(pMap, selfUid);
  if (!isParticipant) throw new Error('permission-denied');

  const updates = {};
  updates[`userConversations/${selfUid}/${trimmedConvId}/hasUnread`] = false;

  const msgsSnap = await db.ref(`conversations/${trimmedConvId}/messages`).get();
  if (msgsSnap.exists() && msgsSnap.val()) {
    const msgs = msgsSnap.val();
    if (typeof msgs === 'object' && msgs !== null) {
      Object.keys(msgs).forEach((msgId) => {
        const msg = msgs[msgId];
        if (msg && typeof msg === 'object') {
          const sender = (msg.senderId || msg.SenderId || '').toString();
          const receiver = (msg.receiverId || msg.ReceiverId || '').toString();

          let isForSelf = false;
          if (receiver) {
            isForSelf = (receiver === selfUid);
          } else if (sender) {
            isForSelf = (sender !== selfUid);
          }

          if (isForSelf) {
            updates[`conversations/${trimmedConvId}/messages/${msgId}/isRead`] = true;
            updates[`conversations/${trimmedConvId}/messages/${msgId}/IsRead`] = true;
          }
        }
      });
    }
  }

  if (Object.keys(updates).length > 0) {
    await db.ref('').update(updates);
  }

  return { success: true };
}

async function handleTriggerEventReminder(request, db, mockMessaging = { sent: [] }) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { bandId, eventId, reminderType } = request.data || {};

  const roleSnap = await db.ref(`Bands/${bandId}/Members_band/${uid}/Role`).get();
  const role = roleSnap.exists() ? roleSnap.val() : null;
  if (role !== 'Leader' && role !== 'Admin') throw new Error('permission-denied');

  const auditRef = db.ref(`eventReminderAudit/${bandId}/${eventId}/${reminderType}`);
  const auditSnap = await auditRef.get();
  if (auditSnap.exists()) {
    const audit = auditSnap.val();
    if (audit.status === 'completed') {
      return { status: 'already_sent', successCount: 0 };
    }
  }

  // Record active claim
  await auditRef.set({
    status: 'sending',
    requestedBy: uid,
    requestedAt: new Date().toISOString()
  });

  // Mock members and dispatch
  const membersSnap = await db.ref(`Bands/${bandId}/Members_band`).get();
  const members = membersSnap.exists() ? membersSnap.val() : {};
  let successCount = 0;
  let failureCount = 0;

  for (const mId of Object.keys(members)) {
    if (mId === uid) continue;
    if (mockMessaging.failFor && mockMessaging.failFor.includes(mId)) {
      failureCount++;
    } else {
      successCount++;
      mockMessaging.sent.push(mId);
    }
  }

  const finalStatus = failureCount > 0 ? 'partial_success' : 'completed';
  await auditRef.set({
    status: finalStatus,
    requestedBy: uid,
    successCount,
    failureCount
  });

  return { status: finalStatus, successCount, failureCount };
}

describe('v2 Callable Cloud Functions Logic Tests', () => {
  let db;

  beforeEach(() => {
    db = new MockDatabase();
  });

  it('1. Unauthenticated callable rejection', async () => {
    await assert.rejects(
      handleGetOrCreateDirectConversation({ auth: null, data: { otherUserId: 'user_b' } }, db),
      /unauthenticated/
    );
  });

  it('2. Chat participant authorization and creation', async () => {
    const res = await handleGetOrCreateDirectConversation(
      { auth: { uid: 'user_a' }, data: { otherUserId: 'user_b' } },
      db
    );
    assert(res.conversationId);
    assert.strictEqual(db.data[`userConversations/user_a/${res.conversationId}`].otherUserId, 'user_b');
    assert.strictEqual(db.data[`userConversations/user_b/${res.conversationId}`].otherUserId, 'user_a');
  });

  it('3. Race-safe direct-conversation creation & recovery', async () => {
    // First call creates key
    const res1 = await handleGetOrCreateDirectConversation(
      { auth: { uid: 'user_a' }, data: { otherUserId: 'user_b' } },
      db
    );
    // Second call recovers existing key deterministically
    const res2 = await handleGetOrCreateDirectConversation(
      { auth: { uid: 'user_b' }, data: { otherUserId: 'user_a' } },
      db
    );
    assert.strictEqual(res1.conversationId, res2.conversationId);
  });

  it('4. Recovery from corrupted pair-key claim checks participant pair', async () => {
    const pairHash = computePairHash('user_a', 'user_b');
    db.data[`directConversationKeys/${pairHash}`] = { conversationId: 'bad_conv' };
    db.data['conversations/bad_conv'] = { participants: { user_a: true, user_c: true } }; // Wrong pair!

    await assert.rejects(
      handleGetOrCreateDirectConversation(
        { auth: { uid: 'user_a' }, data: { otherUserId: 'user_b' } },
        db
      ),
      /corrupted-pair-key/
    );
  });

  it('5. Agreement-chat authorization verifies sub-request creator or applicant', async () => {
    db.data['SubRequests/sub_1'] = { createdBy: 'leader_1' };

    // Authorized applicant
    const res = await handleCreateAgreementConversation(
      { auth: { uid: 'applicant_1' }, data: { subRequestId: 'sub_1', applicantId: 'applicant_1' } },
      db
    );
    assert.strictEqual(res.conversationId, 'agreement_sub_1_applicant_1');

    // Unauthorized outsider
    await assert.rejects(
      handleCreateAgreementConversation(
        { auth: { uid: 'outsider' }, data: { subRequestId: 'sub_1', applicantId: 'applicant_1' } },
        db
      ),
      /permission-denied/
    );
  });

  it('6. Message validation and participant derivation', async () => {
    db.data['conversations/conv_1'] = { participants: { user_a: true, user_b: true } };

    await handleSendDirectMessage(
      { auth: { uid: 'user_a' }, data: { conversationId: 'conv_1', text: 'Hello!', receiverUserId: 'user_b' } },
      db
    );

    assert.strictEqual(db.data['userConversations/user_a/conv_1'].lastMessageText, 'Hello!');
    assert.strictEqual(db.data['userConversations/user_b/conv_1'].hasUnread, true);
  });

  it('7. Mark-as-read authorization verifies participant membership', async () => {
    db.data['conversations/conv_1'] = { participants: { user_a: true, user_b: true } };
    db.data['userConversations/user_a/conv_1'] = { hasUnread: true };

    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_a' }, data: { conversationId: 'conv_1' } },
      db
    );
    assert.strictEqual(db.data['userConversations/user_a/conv_1'].hasUnread, false);

    // Outsider cannot mark as read
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'outsider' }, data: { conversationId: 'conv_1' } },
        db
      ),
      /permission-denied/
    );
  });

  it('7b. Mark-as-read handles legacy Participants array, non-boolean maps, missing receiverId, and sparse message arrays', async () => {
    // Legacy conversation with Participants array and messages without receiverId
    db.data['conversations/legacy_conv'] = {
      Participants: ['user_x', 'user_y'],
      messages: {
        msg_1: { SenderId: 'user_y', Text: 'Legacy message', IsRead: false },
        msg_2: { SenderId: 'user_x', Text: 'My reply', IsRead: false }
      }
    };
    db.data['userConversations/user_x/legacy_conv'] = { hasUnread: true };

    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_x' }, data: { conversationId: 'legacy_conv' } },
      db
    );

    assert.strictEqual(db.data['userConversations/user_x/legacy_conv'].hasUnread, false);
    // msg_1 from user_y to user_x marked as read
    assert.strictEqual(db.data['conversations/legacy_conv'].messages.msg_1.isRead, true);
    assert.strictEqual(db.data['conversations/legacy_conv'].messages.msg_1.IsRead, true);
    // msg_2 from user_x not marked as read for user_x
    assert.strictEqual(db.data['conversations/legacy_conv'].messages.msg_2.isRead, undefined);

    // Legacy conversation with non-boolean participant map
    db.data['conversations/legacy_map_conv'] = {
      participants: { user_x: 'owner', user_y: 'member' }
    };
    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_x' }, data: { conversationId: 'legacy_map_conv' } },
      db
    );
    assert.strictEqual(db.data['userConversations/user_x/legacy_map_conv'].hasUnread, false);
  });

  it('7c. Exact case-sensitive UID authorization security tests', async () => {
    // Setup conversation with exact case UID "User_ExactCase"
    db.data['conversations/conv_security'] = {
      participants: {
        'User_ExactCase': true,
        'user_role_owner': 'owner',
        'user_role_member': 'member',
        'user_num_1': 1,
        'user_str_true': 'true',
        'user_false_bool': false,
        'user_false_str': 'false',
        'user_zero': 0,
        'user_empty': '',
        'user_null': null,
      }
    };

    // 1. Exact UID is accepted
    const okRes = await handleMarkDirectConversationRead(
      { auth: { uid: 'User_ExactCase' }, data: { conversationId: 'conv_security' } },
      db
    );
    assert.strictEqual(okRes.success, true);

    // 2. Differently cased UID is rejected with permission-denied
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_exactcase' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );

    // 3. Valid legacy role-map entries accepted
    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_role_owner' }, data: { conversationId: 'conv_security' } },
      db
    );
    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_role_member' }, data: { conversationId: 'conv_security' } },
      db
    );
    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_num_1' }, data: { conversationId: 'conv_security' } },
      db
    );
    await handleMarkDirectConversationRead(
      { auth: { uid: 'user_str_true' }, data: { conversationId: 'conv_security' } },
      db
    );

    // 4. False/null/zero/empty membership values rejected with permission-denied
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_false_bool' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_false_str' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_zero' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_empty' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );
    await assert.rejects(
      handleMarkDirectConversationRead(
        { auth: { uid: 'user_null' }, data: { conversationId: 'conv_security' } },
        db
      ),
      /permission-denied/
    );
  });

  it('8. Leader/Admin reminder authorization & member rejection', async () => {
    db.data['Bands/band_1/Members_band/leader_1/Role'] = 'Leader';
    db.data['Bands/band_1/Members_band/member_1/Role'] = 'Member';

    // Leader succeeds
    const res = await handleTriggerEventReminder(
      { auth: { uid: 'leader_1' }, data: { bandId: 'band_1', eventId: 'evt_1', reminderType: '24h' } },
      db
    );
    assert.strictEqual(res.status, 'completed');

    // Normal member rejected
    await assert.rejects(
      handleTriggerEventReminder(
        { auth: { uid: 'member_1' }, data: { bandId: 'band_1', eventId: 'evt_2', reminderType: '24h' } },
        db
      ),
      /permission-denied/
    );
  });

  it('9. Duplicate reminder claims rejected with already_sent', async () => {
    db.data['Bands/band_1/Members_band/leader_1/Role'] = 'Leader';
    db.data['eventReminderAudit/band_1/evt_1/24h'] = { status: 'completed' };

    const res = await handleTriggerEventReminder(
      { auth: { uid: 'leader_1' }, data: { bandId: 'band_1', eventId: 'evt_1', reminderType: '24h' } },
      db
    );
    assert.strictEqual(res.status, 'already_sent');
  });

  it('10. Partial FCM failure and retry status tracking', async () => {
    db.data['Bands/band_1/Members_band/leader_1/Role'] = 'Leader';
    db.data['Bands/band_1/Members_band'] = {
      leader_1: { Role: 'Leader' },
      m1: { Role: 'Member' },
      m2: { Role: 'Member' }
    };

    const mockMessaging = { sent: [], failFor: ['m2'] };
    const res = await handleTriggerEventReminder(
      { auth: { uid: 'leader_1' }, data: { bandId: 'band_1', eventId: 'evt_99', reminderType: '48h' } },
      db,
      mockMessaging
    );

    assert.strictEqual(res.status, 'partial_success');
    assert.strictEqual(res.successCount, 1);
    assert.strictEqual(res.failureCount, 1);
  });
});
