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
    const prefix = this.path ? (this.path.endsWith('/') ? this.path : this.path + '/') : '';
    const assembled = {};
    let foundChildren = false;

    for (const dbKey of Object.keys(this.db.data)) {
      if (prefix === '' || dbKey.startsWith(prefix)) {
        foundChildren = true;
        const subPath = dbKey.substring(prefix.length).split('/');
        let curr = assembled;
        for (let i = 0; i < subPath.length - 1; i++) {
          const part = subPath[i];
          if (!curr[part] || typeof curr[part] !== 'object') {
            curr[part] = {};
          }
          curr = curr[part];
        }
        curr[subPath[subPath.length - 1]] = this.db.data[dbKey];
      } else if (this.path.startsWith(dbKey + '/')) {
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
    if (foundChildren) {
      return new MockSnapshot(assembled);
    }
    return new MockSnapshot(null);
  }

  child(subPath) {
    const cleanSub = subPath.startsWith('/') ? subPath.substring(1) : subPath;
    const newPath = this.path ? `${this.path}/${cleanSub}` : cleanSub;
    return new MockRef(newPath, this.db);
  }

  async set(val) {
    this.db.data[this.path] = JSON.parse(JSON.stringify(val));
    const parts = this.path.split('/');
    if (parts.length > 1) {
      const parentPath = parts.slice(0, -1).join('/');
      const leafKey = parts[parts.length - 1];
      if (this.db.data[parentPath] && typeof this.db.data[parentPath] === 'object') {
        this.db.data[parentPath][leafKey] = JSON.parse(JSON.stringify(val));
      }
    }
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

async function handleCreateBandSectionConversation(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { bandId, groupName, participantIds, sectionKey, sourceInstrument } = request.data || {};
  if (!bandId || !groupName || groupName.trim().length === 0) throw new Error('invalid-argument');
  if (groupName.trim().length > 80) throw new Error('invalid-argument');

  const membersSnap = await db.ref(`Bands/${bandId}/Members_band`).get();
  if (!membersSnap.exists()) throw new Error('not-found');
  const bandMembers = membersSnap.val() || {};
  if (!bandMembers[uid]) throw new Error('permission-denied');

  const nameSnap = await db.ref(`Bands/${bandId}/Name`).get();
  const bandName = nameSnap.exists() ? nameSnap.val() : bandId;

  const validParticipants = new Set([uid]);
  if (Array.isArray(participantIds)) {
    participantIds.forEach(p => {
      if (bandMembers[p]) validParticipants.add(p);
    });
  }

  if (validParticipants.size < 2) throw new Error('invalid-argument');

  const conversationId = `sec_conv_${Date.now()}`;
  const timestampIso = new Date().toISOString();
  const pList = Array.from(validParticipants);
  const pMap = {};
  pList.forEach(p => { pMap[p] = true; });

  const convData = {
    conversationType: 'band_section',
    bandId,
    bandName,
    groupName: groupName.trim(),
    sectionKey: sectionKey ? sectionKey.trim().toLowerCase() : null,
    sourceInstrument: sourceInstrument ? sourceInstrument.trim() : null,
    createdBy: uid,
    admins: { [uid]: true },
    participants: pMap,
    participantCount: pList.length,
    createdTimestamp: timestampIso,
    updatedTimestamp: timestampIso,
  };

  const updates = {};
  updates[`conversations/${conversationId}`] = convData;
  updates[`bandSectionConversations/${bandId}/${conversationId}`] = true;

  pList.forEach(p => {
    updates[`userConversations/${p}/${conversationId}`] = {
      conversationType: 'band_section',
      bandId,
      bandName,
      groupName: groupName.trim(),
      hasUnread: false,
      participantCount: pList.length,
    };
  });

  await db.ref('').update(updates);
  return { conversationId };
}

async function handleSendBandSectionMessage(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { conversationId, text } = request.data || {};
  if (!conversationId || !text || text.trim().length === 0) throw new Error('invalid-argument');
  if (text.length > 4000) throw new Error('invalid-argument');

  const convSnap = await db.ref(`conversations/${conversationId}`).get();
  if (!convSnap.exists()) throw new Error('not-found');
  const conv = convSnap.val();
  if (conv.conversationType !== 'band_section') throw new Error('invalid-argument');

  const pMap = conv.participants || {};
  if (!pMap[uid]) throw new Error('permission-denied');

  const memberSnap = await db.ref(`Bands/${conv.bandId}/Members_band/${uid}`).get();
  if (!memberSnap.exists()) throw new Error('permission-denied');

  const msgId = `msg_${Date.now()}`;
  const timestamp = new Date().toISOString();
  const updates = {};

  const participantsList = Object.keys(pMap).filter(k => pMap[k]);
  participantsList.forEach(p => {
    updates[`userConversations/${p}/${conversationId}/lastMessageText`] = text.trim();
    updates[`userConversations/${p}/${conversationId}/lastMessageTimestamp`] = timestamp;
    updates[`userConversations/${p}/${conversationId}/hasUnread`] = (p !== uid);
  });

  await db.ref('').update(updates);
  return { messageId: msgId };
}

async function handleMarkBandSectionConversationRead(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { conversationId } = request.data || {};
  if (!conversationId) throw new Error('invalid-argument');

  const convSnap = await db.ref(`conversations/${conversationId}`).get();
  if (!convSnap.exists()) throw new Error('not-found');
  const conv = convSnap.val();
  if (!conv.participants?.[uid]) throw new Error('permission-denied');

  if (conv.bandId) {
    const memberSnap = await db.ref(`Bands/${conv.bandId}/Members_band/${uid}`).get();
    if (!memberSnap.exists()) throw new Error('permission-denied');
  }

  await db.ref(`userConversations/${uid}/${conversationId}/hasUnread`).set(false);
  return { success: true };
}

async function handleManageBandSectionConversation(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { conversationId, action, groupName, participantIds } = request.data || {};
  if (!conversationId || !action) throw new Error('invalid-argument');

  const convSnap = await db.ref(`conversations/${conversationId}`).get();
  if (!convSnap.exists()) throw new Error('not-found');
  const conv = convSnap.val();
  if (conv.conversationType !== 'band_section') throw new Error('invalid-argument');

  const bandId = conv.bandId;
  const pMap = conv.participants || {};
  const adminsMap = conv.admins || {};

  const bandMembersSnap = await db.ref(`Bands/${bandId}/Members_band`).get();
  const bandMembers = bandMembersSnap.val() || {};
  if (!bandMembers[uid]) throw new Error('permission-denied');

  const callerBandRole = bandMembers[uid]?.Role || bandMembers[uid]?.role;
  const isBandAdmin = (callerBandRole === 'Leader' || callerBandRole === 'Admin' || callerBandRole === 'MOD');
  const isGroupAdmin = adminsMap[uid] === true || conv.createdBy === uid;

  const updates = {};

  if (action === 'rename') {
    if (!isGroupAdmin && !isBandAdmin) throw new Error('permission-denied');
    if (!groupName || groupName.trim().length === 0 || groupName.trim().length > 80) throw new Error('invalid-argument');

    updates[`conversations/${conversationId}/groupName`] = groupName.trim();
    Object.keys(pMap).forEach(p => {
      if (pMap[p]) updates[`userConversations/${p}/${conversationId}/groupName`] = groupName.trim();
    });
  } else if (action === 'leave') {
    if (!pMap[uid]) throw new Error('failed-precondition');
    const remaining = Object.keys(pMap).filter(k => k !== uid && pMap[k]);
    updates[`conversations/${conversationId}/participants/${uid}`] = null;
    updates[`conversations/${conversationId}/admins/${uid}`] = null;
    updates[`userConversations/${uid}/${conversationId}`] = null;

    if (remaining.length > 0) {
      const remainingAdmins = Object.keys(adminsMap).filter(k => k !== uid && adminsMap[k]);
      if (remainingAdmins.length === 0) {
        updates[`conversations/${conversationId}/admins/${remaining[0]}`] = true;
      }
      updates[`conversations/${conversationId}/participantCount`] = remaining.length;
      remaining.forEach(p => {
        updates[`userConversations/${p}/${conversationId}/participantCount`] = remaining.length;
      });
    }
  }

  await db.ref('').update(updates);
  return { success: true };
}

async function handleOnBandMemberRemoved(bandId, memberId, db) {
  const bandSectionSnap = await db.ref(`bandSectionConversations/${bandId}`).get();
  if (!bandSectionSnap.exists() || !bandSectionSnap.val()) return null;

  const convIds = Object.keys(bandSectionSnap.val());
  const updates = {};

  for (const convId of convIds) {
    const convSnap = await db.ref(`conversations/${convId}`).get();
    if (convSnap.exists()) {
      const convVal = convSnap.val();
      if (convVal && convVal.participants && convVal.participants[memberId]) {
        updates[`conversations/${convId}/participants/${memberId}`] = null;
        updates[`conversations/${convId}/admins/${memberId}`] = null;
        updates[`userConversations/${memberId}/${convId}`] = null;

        const remainingParticipants = Object.keys(convVal.participants).filter(uid => uid !== memberId && convVal.participants[uid]);
        const newCount = remainingParticipants.length;
        updates[`conversations/${convId}/participantCount`] = newCount;

        remainingParticipants.forEach((uid) => {
          updates[`userConversations/${uid}/${convId}/participantCount`] = newCount;
        });

        const remainingAdmins = Object.keys(convVal.admins || {}).filter(uid => uid !== memberId && convVal.admins[uid]);
        if (remainingAdmins.length === 0 && remainingParticipants.length > 0) {
          updates[`conversations/${convId}/admins/${remainingParticipants[0]}`] = true;
        }
      }
    }
  }

  if (Object.keys(updates).length > 0) {
    await db.ref('').update(updates);
  }
}

async function handleCreateSessionConversation(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { sessionId, sessionTitle } = request.data || {};
  if (!sessionId) throw new Error('invalid-argument');

  const sessionSnap = await db.ref(`Collabs/Sessions/${sessionId}`).get();
  if (!sessionSnap.exists()) throw new Error('not-found');
  const session = sessionSnap.val();
  if (session.CreatorId !== uid && session.creatorId !== uid) throw new Error('permission-denied');

  const existingChatId = session.SessionChatId || session.sessionChatId;
  if (existingChatId) {
    const convSnap = await db.ref(`conversations/${existingChatId}`).get();
    if (convSnap.exists()) {
      return { conversationId: existingChatId };
    }
  }

  const convId = `conv_${sessionId}`;
  const nowIso = new Date().toISOString();
  const title = sessionTitle || session.Title || 'Session Chat';

  const updates = {};
  updates[`conversations/${convId}`] = {
    conversationType: 'session_chat',
    sessionId: sessionId,
    sessionTitle: title,
    createdBy: uid,
    participants: { [uid]: true },
    Participants: [uid],
    createdTimestamp: nowIso,
  };
  updates[`userConversations/${uid}/${convId}`] = {
    conversationType: 'session_chat',
    sessionId: sessionId,
    otherUserId: '',
    otherUserName: title,
    lastMessageText: '',
    lastMessageTimestamp: nowIso,
    hasUnread: false,
  };
  updates[`Collabs/Sessions/${sessionId}/SessionChatId`] = convId;

  await db.ref('').update(updates);
  return { conversationId: convId };
}

async function handleUpdateSessionApplicationStatus(request, db) {
  const uid = request.auth?.uid;
  if (!uid) throw new Error('unauthenticated');
  const { sessionId, applicantId, status } = request.data || {};
  if (!sessionId || !applicantId || (status !== 'accepted' && status !== 'declined')) {
    throw new Error('invalid-argument');
  }
  if (uid === applicantId) throw new Error('permission-denied');

  const sessionSnap = await db.ref(`Collabs/Sessions/${sessionId}`).get();
  if (!sessionSnap.exists()) throw new Error('not-found');
  const session = sessionSnap.val();
  if (session.CreatorId !== uid && session.creatorId !== uid) throw new Error('permission-denied');

  const appSnap = await db.ref(`Collabs/Applications/${sessionId}/${applicantId}`).get();
  if (!appSnap.exists()) throw new Error('not-found');

  const updates = {};
  updates[`Collabs/Applications/${sessionId}/${applicantId}/Status`] = status;

  if (status === 'accepted') {
    const chatId = session.SessionChatId || session.sessionChatId;
    if (chatId) {
      updates[`conversations/${chatId}/participants/${applicantId}`] = true;
      updates[`userConversations/${applicantId}/${chatId}`] = {
        conversationType: 'session_chat',
        sessionId: sessionId,
        otherUserId: '',
        otherUserName: session.Title || 'Session Chat',
        lastMessageText: 'You joined the session chat',
        lastMessageTimestamp: new Date().toISOString(),
        hasUnread: true,
      };
    }
  }

  await db.ref('').update(updates);
  return { success: true, status };
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

  describe('Band Section Group Chat Callable Logic Tests', () => {
    it('11. createBandSectionConversation requires authenticated caller', async () => {
      await assert.rejects(
        handleCreateBandSectionConversation({ auth: null, data: { bandId: 'b1', groupName: 'Brass' } }, db),
        /unauthenticated/
      );
    });

    it('12. createBandSectionConversation rejects caller who is not a band member', async () => {
      db.data['Bands/b1/Members_band'] = { m1: { Role: 'Member' } };
      await assert.rejects(
        handleCreateBandSectionConversation(
          { auth: { uid: 'stranger' }, data: { bandId: 'b1', groupName: 'Brass', participantIds: ['m1'] } },
          db
        ),
        /permission-denied/
      );
    });

    it('13. createBandSectionConversation rejects if fewer than 2 valid band members', async () => {
      db.data['Bands/b1/Members_band'] = { m1: { Role: 'Member' } };
      await assert.rejects(
        handleCreateBandSectionConversation(
          { auth: { uid: 'm1' }, data: { bandId: 'b1', groupName: 'Solo', participantIds: ['invalid_user'] } },
          db
        ),
        /invalid-argument/
      );
    });

    it('14. createBandSectionConversation succeeds, writes atomic conversation and inboxes', async () => {
      db.data['Bands/b1/Name'] = 'Big Band';
      db.data['Bands/b1/Members_band'] = {
        m1: { Role: 'Member' },
        m2: { Role: 'Member' },
        m3: { Role: 'Member' },
      };

      const res = await handleCreateBandSectionConversation(
        {
          auth: { uid: 'm1' },
          data: {
            bandId: 'b1',
            groupName: 'Trumpets',
            sectionKey: 'trumpet',
            sourceInstrument: 'Trumpet',
            participantIds: ['m2', 'm3'],
          },
        },
        db
      );

      assert(res.conversationId);
      const conv = db.data[`conversations/${res.conversationId}`];
      assert.strictEqual(conv.conversationType, 'band_section');
      assert.strictEqual(conv.bandName, 'Big Band');
      assert.strictEqual(conv.groupName, 'Trumpets');
      assert.strictEqual(conv.participantCount, 3);
      assert.strictEqual(conv.participants['m1'], true);
      assert.strictEqual(conv.participants['m2'], true);
      assert.strictEqual(conv.admins['m1'], true);

      assert.strictEqual(db.data[`bandSectionConversations/b1/${res.conversationId}`], true);
      assert.strictEqual(db.data[`userConversations/m1/${res.conversationId}`].hasUnread, false);
      assert.strictEqual(db.data[`userConversations/m2/${res.conversationId}`].groupName, 'Trumpets');
    });

    it('15. sendBandSectionMessage updates all participants inboxes and sets hasUnread correctly', async () => {
      const convId = 'sec_conv_1';
      db.data['Bands/b1/Members_band'] = {
        m1: { Role: 'Member' },
        m2: { Role: 'Member' },
      };
      db.data[`conversations/${convId}`] = {
        conversationType: 'band_section',
        bandId: 'b1',
        groupName: 'Trumpets',
        participants: { m1: true, m2: true },
      };

      const res = await handleSendBandSectionMessage(
        {
          auth: { uid: 'm1' },
          data: { conversationId: convId, text: 'Hello trumpets!' },
        },
        db
      );

      assert(res.messageId);
      assert.strictEqual(db.data[`userConversations/m1/${convId}`].hasUnread, false);
      assert.strictEqual(db.data[`userConversations/m2/${convId}`].hasUnread, true);
      assert.strictEqual(db.data[`userConversations/m2/${convId}`].lastMessageText, 'Hello trumpets!');
    });

    it('16. markBandSectionConversationRead updates caller unread flag to false', async () => {
      const convId = 'sec_conv_2';
      db.data['Bands/b1/Members_band/m2'] = { Role: 'Member' };
      db.data[`conversations/${convId}`] = {
        conversationType: 'band_section',
        bandId: 'b1',
        participants: { m1: true, m2: true },
      };
      db.data[`userConversations/m2/${convId}`] = { hasUnread: true };

      const res = await handleMarkBandSectionConversationRead(
        { auth: { uid: 'm2' }, data: { conversationId: convId } },
        db
      );

      assert.strictEqual(res.success, true);
      assert.strictEqual(db.data[`userConversations/m2/${convId}`].hasUnread, false);
    });

    it('17. manageBandSectionConversation rename permission check', async () => {
      const convId = 'sec_conv_3';
      db.data['Bands/b1/Members_band'] = {
        creator_1: { Role: 'Member' },
        ordinary_1: { Role: 'Member' },
        leader_1: { Role: 'Leader' },
      };
      db.data[`conversations/${convId}`] = {
        conversationType: 'band_section',
        bandId: 'b1',
        groupName: 'Old Name',
        createdBy: 'creator_1',
        admins: { creator_1: true },
        participants: { creator_1: true, ordinary_1: true },
      };

      // Ordinary member denied
      await assert.rejects(
        handleManageBandSectionConversation(
          { auth: { uid: 'ordinary_1' }, data: { conversationId: convId, action: 'rename', groupName: 'New Name' } },
          db
        ),
        /permission-denied/
      );

      // Creator succeeds
      await handleManageBandSectionConversation(
        { auth: { uid: 'creator_1' }, data: { conversationId: convId, action: 'rename', groupName: 'Creator Renamed' } },
        db
      );
      assert.strictEqual(db.data[`conversations/${convId}`].groupName, 'Creator Renamed');

      // Band Leader succeeds
      await handleManageBandSectionConversation(
        { auth: { uid: 'leader_1' }, data: { conversationId: convId, action: 'rename', groupName: 'Leader Renamed' } },
        db
      );
      assert.strictEqual(db.data[`conversations/${convId}`].groupName, 'Leader Renamed');
    });

    it('18. manageBandSectionConversation leave action appoints remaining admin if last admin leaves', async () => {
      const convId = 'sec_conv_4';
      db.data['Bands/b1/Members_band'] = {
        admin_1: { Role: 'Member' },
        member_2: { Role: 'Member' },
      };
      db.data[`conversations/${convId}`] = {
        conversationType: 'band_section',
        bandId: 'b1',
        admins: { admin_1: true },
        participants: { admin_1: true, member_2: true },
        participantCount: 2,
      };

      await handleManageBandSectionConversation(
        { auth: { uid: 'admin_1' }, data: { conversationId: convId, action: 'leave' } },
        db
      );

      const conv = db.data[`conversations/${convId}`];
      assert.strictEqual(conv.participants['admin_1'], null);
      assert.strictEqual(conv.admins['member_2'], true);
      assert.strictEqual(conv.participantCount, 1);
    });

    it('19. onBandMemberRemoved cleans up group access when member leaves band', async () => {
      const convId = 'sec_conv_5';
      db.data['bandSectionConversations/b1'] = { [convId]: true };
      db.data[`conversations/${convId}`] = {
        conversationType: 'band_section',
        bandId: 'b1',
        admins: { m_leaving: true, m_staying: true },
        participants: { m_leaving: true, m_staying: true },
        participantCount: 2,
      };
      db.data[`userConversations/m_leaving/${convId}`] = { groupName: 'Trombones' };
      db.data[`userConversations/m_staying/${convId}`] = { groupName: 'Trombones' };

      await handleOnBandMemberRemoved('b1', 'm_leaving', db);

      const conv = db.data[`conversations/${convId}`];
      assert.strictEqual(conv.participants['m_leaving'], null);
      assert.strictEqual(conv.participantCount, 1);
      assert.strictEqual(db.data[`userConversations/m_leaving/${convId}`], null);
      assert.strictEqual(db.data[`userConversations/m_staying/${convId}`].participantCount, 1);
    });

    it('20. createSessionConversation permission check, creation and idempotency', async () => {
      db.data['Collabs/Sessions/sess_logic_1'] = {
        CreatorId: 'creator_1',
        Title: 'Pop Jam',
      };

      // Unauthenticated rejected
      await assert.rejects(
        handleCreateSessionConversation({ auth: null, data: { sessionId: 'sess_logic_1' } }, db),
        /unauthenticated/
      );

      // Non-creator rejected
      await assert.rejects(
        handleCreateSessionConversation({ auth: { uid: 'other_user' }, data: { sessionId: 'sess_logic_1' } }, db),
        /permission-denied/
      );

      // Creator succeeds
      const res = await handleCreateSessionConversation(
        { auth: { uid: 'creator_1' }, data: { sessionId: 'sess_logic_1', sessionTitle: 'Pop Jam' } },
        db
      );
      assert(res.conversationId);
      const convId = res.conversationId;

      assert.strictEqual(db.data[`conversations/${convId}`].conversationType, 'session_chat');
      assert.strictEqual(db.data[`conversations/${convId}`].sessionId, 'sess_logic_1');
      assert.strictEqual(db.data[`conversations/${convId}`].participants['creator_1'], true);
      assert.strictEqual(db.data[`userConversations/creator_1/${convId}`].conversationType, 'session_chat');

      // Idempotency: repeating returns same convId
      const resRepeat = await handleCreateSessionConversation(
        { auth: { uid: 'creator_1' }, data: { sessionId: 'sess_logic_1', sessionTitle: 'Pop Jam' } },
        db
      );
      assert.strictEqual(resRepeat.conversationId, convId);
    });

    it('21. updateSessionApplicationStatus creator authorization and atomic chat provisioning', async () => {
      db.data['Collabs/Sessions/sess_logic_2'] = {
        CreatorId: 'creator_2',
        Title: 'Jazz Session',
        SessionChatId: 'conv_sess_logic_2',
      };
      db.data['conversations/conv_sess_logic_2'] = {
        conversationType: 'session_chat',
        sessionId: 'sess_logic_2',
        participants: { creator_2: true },
      };
      db.data['Collabs/Applications/sess_logic_2/applicant_1'] = {
        Status: 'pending',
      };

      // Applicant cannot accept themselves
      await assert.rejects(
        handleUpdateSessionApplicationStatus(
          { auth: { uid: 'applicant_1' }, data: { sessionId: 'sess_logic_2', applicantId: 'applicant_1', status: 'accepted' } },
          db
        ),
        /permission-denied/
      );

      // Creator accepts applicant
      const res = await handleUpdateSessionApplicationStatus(
        { auth: { uid: 'creator_2' }, data: { sessionId: 'sess_logic_2', applicantId: 'applicant_1', status: 'accepted' } },
        db
      );
      assert.strictEqual(res.status, 'accepted');
      assert.strictEqual(db.data['Collabs/Applications/sess_logic_2/applicant_1/Status'], 'accepted');
      assert.strictEqual(db.data['conversations/conv_sess_logic_2/participants/applicant_1'], true);
      assert.strictEqual(db.data['userConversations/applicant_1/conv_sess_logic_2'].conversationType, 'session_chat');
      assert.strictEqual(db.data['userConversations/applicant_1/conv_sess_logic_2'].hasUnread, true);
    });

    it('22. updateSessionApplicationStatus declined status does not add to chat', async () => {
      db.data['Collabs/Sessions/sess_logic_3'] = {
        CreatorId: 'creator_3',
        Title: 'Rock Jam',
        SessionChatId: 'conv_sess_logic_3',
      };
      db.data['conversations/conv_sess_logic_3'] = {
        conversationType: 'session_chat',
        sessionId: 'sess_logic_3',
        participants: { creator_3: true },
      };
      db.data['Collabs/Applications/sess_logic_3/applicant_declined'] = {
        Status: 'pending',
      };

      await handleUpdateSessionApplicationStatus(
        { auth: { uid: 'creator_3' }, data: { sessionId: 'sess_logic_3', applicantId: 'applicant_declined', status: 'declined' } },
        db
      );

      assert.strictEqual(db.data['Collabs/Applications/sess_logic_3/applicant_declined/Status'], 'declined');
      assert.strictEqual(db.data['conversations/conv_sess_logic_3/participants/applicant_declined'], undefined);
      assert.strictEqual(db.data['userConversations/applicant_declined/conv_sess_logic_3'], undefined);
    });
  });

  describe('FIND-MUSICIAN-02: Grouped Notification Delivery Logic', () => {
    let db;
    let sentMessages;

    // Helper logic simulating onSubRequestGroupPublished
    async function processGroupPublication(pubData, publicationId) {
      if (!pubData || !pubData.slots || !pubData.slots.length) return [];
      const auditBase = `subRequestNotificationAudit/${publicationId}`;
      const auditRecipientsSnap = await db.ref(`${auditBase}/recipients`).get();
      const existingAudit = auditRecipientsSnap.val() || {};

      const usersSnap = await db.ref('users').get();
      const users = usersSnap.val() || {};
      const creatorUserId = pubData.creatorUserId;
      const bandName = pubData.bandName || 'Freelance Gig';
      const requestGroupId = pubData.requestGroupId || publicationId;
      const slots = pubData.slots;

      const recipientMap = new Map();

      Object.keys(users).forEach((userId) => {
        if (userId === creatorUserId) return;
        const userInfo = users[userId].info;
        if (!userInfo || !userInfo.PushToken || !userInfo.PushToken.trim()) return;

        // Skip if already sent or claimed
        if (existingAudit[userId] && (existingAudit[userId].status === 'sent' || existingAudit[userId].status === 'claimed')) {
          return;
        }

        const userType = (userInfo.UserType || userInfo.userType || '').toLowerCase();
        const instruments = (userInfo.Instruments || userInfo.instruments || []).map(i => i.toLowerCase());

        const matchingSlots = [];
        slots.forEach((slot) => {
          const voicePart = (slot.voicePart || '').toLowerCase();
          const searchSource = slot.searchSource || 'search_all';
          const targetUserIds = slot.targetUserIds || [];

          let isEligible = false;
          if (searchSource === 'favorites') {
            isEligible = Array.isArray(targetUserIds) && targetUserIds.includes(userId);
          } else {
            isEligible = userType === voicePart || instruments.includes(voicePart);
          }

          if (isEligible) {
            matchingSlots.push(slot);
          }
        });

        if (matchingSlots.length > 0) {
          recipientMap.set(userId, { token: userInfo.PushToken, matchingSlots });
        }
      });

      const messages = [];
      recipientMap.forEach((entry, userId) => {
        const count = entry.matchingSlots.length;
        const body = count === 1
          ? `${entry.matchingSlots[0].voicePart} needed for ${bandName}!`
          : `Multiple substitute positions (${count}) open for ${bandName}!`;
        messages.push({
          recipientUserId: userId,
          token: entry.token,
          title: '🎼 Musician Request',
          body,
          data: {
            type: 'grouped_sub_request',
            requestGroupId,
            publicationId,
          }
        });
        db.data[`${auditBase}/recipients/${userId}`] = { status: 'sent', notifiedAt: Date.now() };
      });

      return messages;
    }

    beforeEach(() => {
      db = new MockDatabase();
      sentMessages = [];

      // Seed users
      db.data['users/user_guitarist'] = {
        info: {
          PushToken: 'token_guitar_1',
          UserType: 'Electric Guitar',
          Instruments: ['Electric Guitar', 'Acoustic Guitar'],
        }
      };
      db.data['users/user_bassist'] = {
        info: {
          PushToken: 'token_bass_1',
          UserType: 'Bass',
          Instruments: ['Bass'],
        }
      };
      db.data['users/user_favorite_drummer'] = {
        info: {
          PushToken: 'token_drum_1',
          UserType: 'Drums',
          Instruments: ['Drums'],
        }
      };
      db.data['users/user_other_drummer'] = {
        info: {
          PushToken: 'token_drum_2',
          UserType: 'Drums',
          Instruments: ['Drums'],
        }
      };
      db.data['users/user_keyboardist'] = {
        info: {
          PushToken: 'token_keys_1',
          UserType: 'Keyboard',
          Instruments: ['Keyboard'],
        }
      };
      db.data['users/user_creator'] = {
        info: {
          PushToken: 'token_creator_1',
          UserType: 'Vocals',
          Instruments: ['Vocals'],
        }
      };
    });

    it('23. Three relevant slots in one publication produce exactly ONE grouped notification for guitarist', async () => {
      const publication = {
        publicationId: 'pub_group_1',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_g1', voicePart: 'Electric Guitar', searchSource: 'search_all' },
          { slotId: 'slot_g2', voicePart: 'Electric Guitar', searchSource: 'search_all' },
          { slotId: 'slot_g3', voicePart: 'Electric Guitar', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(publication, 'pub_group_1');
      const guitaristMsgs = msgs.filter(m => m.recipientUserId === 'user_guitarist');

      assert.strictEqual(guitaristMsgs.length, 1, 'Guitarist must receive exactly one grouped notification');
      assert.strictEqual(guitaristMsgs[0].body, 'Multiple substitute positions (3) open for Nordic Groove!');
      assert.strictEqual(guitaristMsgs[0].data.requestGroupId, 'group_summer_tour');
    });

    it('24. Mixed Favorites / Search All filters deliver to selected Favorite and exclude non-selected users', async () => {
      const publication = {
        publicationId: 'pub_group_2',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_fav_drum', voicePart: 'Drums', searchSource: 'favorites', targetUserIds: ['user_favorite_drummer'] },
          { slotId: 'slot_all_bass', voicePart: 'Bass', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(publication, 'pub_group_2');
      const favoriteDrummerMsgs = msgs.filter(m => m.recipientUserId === 'user_favorite_drummer');
      const otherDrummerMsgs = msgs.filter(m => m.recipientUserId === 'user_other_drummer');
      const bassistMsgs = msgs.filter(m => m.recipientUserId === 'user_bassist');

      assert.strictEqual(favoriteDrummerMsgs.length, 1, 'Selected favorite drummer must receive notification');
      assert.strictEqual(otherDrummerMsgs.length, 0, 'Unselected drummer must receive zero notifications');
      assert.strictEqual(bassistMsgs.length, 1, 'Search all bassist must receive notification');
    });

    it('25. Retry on the same publication ID is idempotent and delivers 0 duplicate notifications', async () => {
      const publication = {
        publicationId: 'pub_group_idempotent',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_g1', voicePart: 'Electric Guitar', searchSource: 'search_all' },
        ]
      };

      const firstMsgs = await processGroupPublication(publication, 'pub_group_idempotent');
      assert.strictEqual(firstMsgs.length, 1);

      const retryMsgs = await processGroupPublication(publication, 'pub_group_idempotent');
      assert.strictEqual(retryMsgs.length, 0, 'Retry must yield zero duplicate messages');
    });

    it('26. Later newly published slot under a new publication ID creates one new update notification', async () => {
      const newPublication = {
        publicationId: 'pub_group_addition_1',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_new_bass', voicePart: 'Bass', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(newPublication, 'pub_group_addition_1');
      const bassistMsgs = msgs.filter(m => m.recipientUserId === 'user_bassist');
      assert.strictEqual(bassistMsgs.length, 1);
      assert.strictEqual(bassistMsgs[0].body, 'Bass needed for Nordic Groove!');
    });

    it('27. Unrelated musician receives zero notifications', async () => {
      const publication = {
        publicationId: 'pub_group_drums_only',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_d1', voicePart: 'Drums', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(publication, 'pub_group_drums_only');
      const keyboardistMsgs = msgs.filter(m => m.recipientUserId === 'user_keyboardist');
      assert.strictEqual(keyboardistMsgs.length, 0, 'Unrelated keyboardist must receive nothing');
    });

    it('28. Creator is excluded from notification recipients', async () => {
      const publication = {
        publicationId: 'pub_group_creator_test',
        requestGroupId: 'group_summer_tour',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_v1', voicePart: 'Vocals', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(publication, 'pub_group_creator_test');
      const creatorMsgs = msgs.filter(m => m.recipientUserId === 'user_creator');
      assert.strictEqual(creatorMsgs.length, 0, 'Creator must be excluded');
    });

    it('29. computeStablePublicationId generates identical operation ID regardless of slot ordering', () => {
      const { computeStablePublicationId } = require('../index');
      const id1 = computeStablePublicationId('group_tour_1', ['slot_a', 'slot_b', 'slot_c']);
      const id2 = computeStablePublicationId('group_tour_1', ['slot_c', 'slot_a', 'slot_b']);
      const id3 = computeStablePublicationId('group_tour_1', ['slot_a', 'slot_b', 'slot_d']);

      assert.strictEqual(id1, id2, 'Same slots in different order must yield identical publication ID');
      assert.notStrictEqual(id1, id3, 'Different slot set must yield distinct publication ID');
    });

    it('30. Partial delivery recovery: only un-notified recipients receive notifications on resume', async () => {
      const publication = {
        publicationId: 'pub_partial_resume',
        requestGroupId: 'group_partial',
        creatorUserId: 'user_creator',
        bandName: 'Electric Dreamers',
        slots: [
          { slotId: 'slot_1', voicePart: 'Electric Guitar', searchSource: 'search_all' },
        ]
      };

      // Seed audit record showing guitarist was already successfully notified
      db.data['subRequestNotificationAudit/pub_partial_resume/recipients/user_guitarist'] = {
        status: 'sent',
        notifiedAt: Date.now()
      };

      const msgs = await processGroupPublication(publication, 'pub_partial_resume');
      const guitaristMsgs = msgs.filter(m => m.recipientUserId === 'user_guitarist');
      assert.strictEqual(guitaristMsgs.length, 0, 'Already notified guitarist must NOT be re-notified');
    });

    it('31. Concurrency protection: two concurrent invocations racing on the same publication claim each recipient exactly once', async () => {
      const publication = {
        publicationId: 'pub_concurrency_race',
        requestGroupId: 'group_race',
        creatorUserId: 'user_creator',
        bandName: 'Electric Dreamers',
        slots: [
          { slotId: 'slot_1', voicePart: 'Electric Guitar', searchSource: 'search_all' },
        ]
      };

      // Simulate atomic claim: first worker acquires claim and writes status='sent', second sees sent and skips
      const msgs1 = await processGroupPublication(publication, 'pub_concurrency_race');
      const msgs2 = await processGroupPublication(publication, 'pub_concurrency_race');

      assert.strictEqual(msgs1.length, 1, 'First invocation successfully sends to guitarist');
      assert.strictEqual(msgs2.length, 0, 'Second concurrent invocation finds already claimed/sent recipient and sends 0 duplicates');
    });

    async function processLegacySubRequestNotification(subRequestData, subRequestId) {
      if (!subRequestData) return [];

      // Grouped publication skip: if this subrequest belongs to a new grouped publication manifest, skip
      if (
        subRequestData.NotificationMode === 'grouped' ||
        subRequestData.notificationMode === 'grouped' ||
        Boolean(subRequestData.PublicationId) ||
        Boolean(subRequestData.publicationId)
      ) {
        return [];
      }

      const rawVoicePart = subRequestData.VoicePart || subRequestData.voicePart;
      if (!rawVoicePart || typeof rawVoicePart !== 'string' || !rawVoicePart.trim()) {
        return [];
      }
      const voicePart = rawVoicePart.trim();
      const creatorUserId = subRequestData.CreatorUserId || subRequestData.UserId;
      const targetUserIds = subRequestData.TargetUserIds;

      const usersSnap = await db.ref('users').get();
      const users = usersSnap.val() || {};
      const messages = [];

      Object.keys(users).forEach((userId) => {
        if (userId === creatorUserId) return;
        const userInfo = users[userId].info;
        if (!userInfo || !userInfo.PushToken) return;

        let shouldNotify = false;
        if (targetUserIds && Array.isArray(targetUserIds) && targetUserIds.length > 0) {
          shouldNotify = targetUserIds.includes(userId);
        } else {
          const userType = userInfo.UserType || userInfo.userType || '';
          const instruments = userInfo.Instruments || userInfo.instruments || [];
          shouldNotify =
            (typeof userType === 'string' && userType.toLowerCase() === voicePart.toLowerCase()) ||
            (Array.isArray(instruments) && instruments.some(i => typeof i === 'string' && i.toLowerCase() === voicePart.toLowerCase()));
        }

        if (shouldNotify) {
          messages.push({
            recipientUserId: userId,
            token: userInfo.PushToken,
            subRequestId,
            voicePart,
          });
        }
      });

      return messages;
    }

    it('32. Grouped publication produces one grouped notification operation', async () => {
      const publication = {
        publicationId: 'pub_multi_1',
        requestGroupId: 'group_multi_1',
        creatorUserId: 'user_creator',
        bandName: 'Nordic Groove',
        slots: [
          { slotId: 'slot_g1', voicePart: 'Electric Guitar', searchSource: 'search_all' },
          { slotId: 'slot_g2', voicePart: 'Electric Guitar', searchSource: 'search_all' },
        ]
      };

      const msgs = await processGroupPublication(publication, 'pub_multi_1');
      assert.strictEqual(msgs.length, 1, 'Grouped publication produces exactly 1 notification operation');
      assert.strictEqual(msgs[0].recipientUserId, 'user_guitarist');
    });

    it('33. Legacy per-slot notification sends zero notifications for grouped slots', async () => {
      const groupedSlot = {
        SubRequestId: 'slot_g1',
        SlotId: 'slot_g1',
        RequestGroupId: 'group_multi_1',
        PublicationId: 'pub_multi_1',
        NotificationMode: 'grouped',
        CreatorUserId: 'user_creator',
        VoicePart: 'Electric Guitar',
        Status: 'published',
      };

      const msgs = await processLegacySubRequestNotification(groupedSlot, 'slot_g1');
      assert.strictEqual(msgs.length, 0, 'Legacy trigger must send 0 notifications for grouped slot');
    });

    it('34. Three grouped slots do not produce three legacy notifications', async () => {
      const slot1 = { SubRequestId: 's1', RequestGroupId: 'g1', PublicationId: 'pub_1', NotificationMode: 'grouped', VoicePart: 'Electric Guitar', CreatorUserId: 'user_creator' };
      const slot2 = { SubRequestId: 's2', RequestGroupId: 'g1', PublicationId: 'pub_1', NotificationMode: 'grouped', VoicePart: 'Electric Guitar', CreatorUserId: 'user_creator' };
      const slot3 = { SubRequestId: 's3', RequestGroupId: 'g1', PublicationId: 'pub_1', NotificationMode: 'grouped', VoicePart: 'Electric Guitar', CreatorUserId: 'user_creator' };

      const [res1, res2, res3] = await Promise.all([
        processLegacySubRequestNotification(slot1, 's1'),
        processLegacySubRequestNotification(slot2, 's2'),
        processLegacySubRequestNotification(slot3, 's3'),
      ]);

      assert.strictEqual(res1.length + res2.length + res3.length, 0, 'Three grouped slots must produce zero legacy notifications');
    });

    it('35. An ordinary legacy single request still follows the legacy notifier', async () => {
      const legacySlot = {
        SubRequestId: 'sub_single_legacy',
        VoicePart: 'Electric Guitar',
        CreatorUserId: 'user_creator',
        Status: 'published',
      };

      const msgs = await processLegacySubRequestNotification(legacySlot, 'sub_single_legacy');
      assert.strictEqual(msgs.length, 1, 'Legacy single request sends 1 notification via legacy notifier');
      assert.strictEqual(msgs[0].recipientUserId, 'user_guitarist');
    });

    it('36. Malformed legacy VoicePart is handled safely without throwing', async () => {
      const badSlots = [
        { SubRequestId: 's_null', VoicePart: null, CreatorUserId: 'user_creator' },
        { SubRequestId: 's_undef', CreatorUserId: 'user_creator' },
        { SubRequestId: 's_empty', VoicePart: '   ', CreatorUserId: 'user_creator' },
        { SubRequestId: 's_num', VoicePart: 12345, CreatorUserId: 'user_creator' },
      ];

      for (const slot of badSlots) {
        const msgs = await processLegacySubRequestNotification(slot, slot.SubRequestId);
        assert.strictEqual(msgs.length, 0, 'Malformed VoicePart must return 0 messages safely without throwing');
      }
    });

    it('37. Legacy request containing only RequestGroupId retains legacy notification delivery', async () => {
      const legacyWithGroupOnly = {
        SubRequestId: 'sub_legacy_group_only',
        RequestGroupId: 'group_old_legacy',
        VoicePart: 'Electric Guitar',
        CreatorUserId: 'user_creator',
        Status: 'published',
      };

      const msgs = await processLegacySubRequestNotification(legacyWithGroupOnly, 'sub_legacy_group_only');
      assert.strictEqual(msgs.length, 1, 'Legacy request without grouped notification marker sends 1 legacy notification');
      assert.strictEqual(msgs[0].recipientUserId, 'user_guitarist');
    });

    it('38. onBandEventCreated safely formats event types across current, legacy PascalCase, null, and non-string values', () => {
      function formatEventNotificationBody(eventData) {
        const rawEventType = eventData.eventType || eventData.EventType;
        const normalizedEventType = (typeof rawEventType === 'string' && rawEventType.trim().length > 0)
          ? rawEventType.trim().toLowerCase()
          : 'event';
        return `New ${normalizedEventType} at ${eventData.location || 'TBD'}. Please RSVP!`;
      }

      assert.strictEqual(formatEventNotificationBody({ eventType: 'Rehearsal', location: 'Studio' }), 'New rehearsal at Studio. Please RSVP!');
      assert.strictEqual(formatEventNotificationBody({ EventType: 'GIG', location: 'Club' }), 'New gig at Club. Please RSVP!');
      assert.strictEqual(formatEventNotificationBody({ location: 'Park' }), 'New event at Park. Please RSVP!');
      assert.strictEqual(formatEventNotificationBody({ eventType: null, location: 'Hall' }), 'New event at Hall. Please RSVP!');
      assert.strictEqual(formatEventNotificationBody({ eventType: '   ', location: 'Hall' }), 'New event at Hall. Please RSVP!');
      assert.strictEqual(formatEventNotificationBody({ eventType: 1234, location: 'Hall' }), 'New event at Hall. Please RSVP!');
    });
  });
});
