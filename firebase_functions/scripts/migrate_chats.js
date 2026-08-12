/**
 * Firebase Admin Migration Script for Direct Chats & User Conversation Indexes
 *
 * Usage:
 *   Dry-Run (Default):
 *     node scripts/migrate_chats.js
 *
 *   Write Mode (Requires Explicit Environment Flag):
 *     CONFIRM_PRODUCTION_MIGRATION=true node scripts/migrate_chats.js --write
 */

const admin = require('firebase-admin');

const EXPECTED_PROJECT_ID = process.env.EXPECTED_PROJECT_ID || "musiciansapp-35f70";
const DATABASE_URL = process.env.FIREBASE_DATABASE_URL || "https://musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app";

if (!DATABASE_URL.includes("musiciansapp-35f70")) {
  console.error(`SAFETY GUARD: Database URL (${DATABASE_URL}) does not match expected target project (musiciansapp-35f70).`);
  process.exit(1);
}

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    databaseURL: DATABASE_URL,
  });
}

async function migrateChats() {
  const args = process.argv.slice(2);
  const isWriteMode = args.includes('--write');

  if (isWriteMode && process.env.CONFIRM_PRODUCTION_MIGRATION !== 'true') {
    console.error('ERROR: Write mode requested, but environment variable CONFIRM_PRODUCTION_MIGRATION=true is missing.');
    console.error('Migration aborted for safety.');
    process.exit(1);
  }

  console.log('====================================================');
  console.log(`Starting Chat Index Migration [Mode: ${isWriteMode ? 'WRITE' : 'DRY-RUN'}]`);
  console.log('====================================================');

  const db = admin.database();
  const convsSnap = await db.ref('/conversations').once('value');

  if (!convsSnap.exists() || !convsSnap.val()) {
    console.log('No conversations found in the database. Nothing to migrate.');
    return;
  }

  const conversations = convsSnap.val();
  const convIds = Object.keys(conversations);

  let totalInspected = 0;
  let totalUserIndexesCreated = 0;
  let totalAnomalies = 0;

  const pendingUpdates = {};

  for (const convId of convIds) {
    totalInspected++;
    const conv = conversations[convId];
    if (!conv || typeof conv !== 'object') {
      totalAnomalies++;
      console.warn(`[Anomaly] Conversation ${convId} is empty or not an object.`);
      continue;
    }

    // Extract participants
    const pMap = conv.participants || conv.Participants;
    let participants = [];
    if (Array.isArray(pMap)) {
      participants = pMap.map(String);
    } else if (pMap && typeof pMap === 'object') {
      participants = Object.keys(pMap);
    }

    if (participants.length === 0) {
      totalAnomalies++;
      console.warn(`[Anomaly] Conversation ${convId} has no participants defined.`);
      continue;
    }

    // Extract latest message & unread state
    const msgs = conv.messages || conv.Messages || {};
    let lastMsgText = '';
    let lastMsgTimestamp = conv.createdTimestamp || conv.CreatedTimestamp || new Date().toISOString();

    if (typeof msgs === 'object' && Object.keys(msgs).length > 0) {
      const msgKeys = Object.keys(msgs);
      let latestTime = 0;

      msgKeys.forEach((mId) => {
        const m = msgs[mId];
        if (m && typeof m === 'object') {
          const rawTime = m.timestamp || m.Timestamp;
          const parsedTime = rawTime ? new Date(rawTime).getTime() : 0;
          if (parsedTime >= latestTime) {
            latestTime = parsedTime;
            lastMsgText = (m.text || m.Text || '').substring(0, 100);
            lastMsgTimestamp = rawTime || lastMsgTimestamp;
          }
        }
      });
    }

    const unreadMap = conv.unread || conv.Unread || {};
    const isAgreement = !!(conv.agreement || conv.Agreement);

    // Build userConversations updates for each participant
    participants.forEach((uid) => {
      const otherUid = participants.find((id) => id !== uid) || '';
      const hasUnread = unreadMap[uid] === true;

      const indexPath = `userConversations/${uid}/${convId}`;
      pendingUpdates[`${indexPath}/otherUserId`] = otherUid;
      pendingUpdates[`${indexPath}/lastMessageText`] = lastMsgText;
      pendingUpdates[`${indexPath}/lastMessageTimestamp`] = lastMsgTimestamp;
      pendingUpdates[`${indexPath}/hasUnread`] = hasUnread;
      pendingUpdates[`${indexPath}/conversationType`] = isAgreement ? 'agreement' : 'direct';

      totalUserIndexesCreated++;
    });
  }

  console.log('----------------------------------------------------');
  console.log(`Inspection Complete:`);
  console.log(`- Conversations Inspected: ${totalInspected}`);
  console.log(`- User Index Records to Update: ${totalUserIndexesCreated}`);
  console.log(`- Anomalies Flagged: ${totalAnomalies}`);
  console.log('----------------------------------------------------');

  if (isWriteMode) {
    if (Object.keys(pendingUpdates).length > 0) {
      console.log('Applying atomic multi-location update to Firebase Realtime Database...');
      await db.ref().update(pendingUpdates);
      console.log('SUCCESS: Migration write complete!');
    } else {
      console.log('No index updates needed.');
    }
  } else {
    console.log('DRY-RUN COMPLETE: No changes were written to the database.');
    console.log('To perform real writes, run:');
    console.log('  CONFIRM_PRODUCTION_MIGRATION=true node scripts/migrate_chats.js --write');
  }
}

migrateChats().catch((err) => {
  console.error('Fatal error during migration:', err);
  process.exit(1);
});
