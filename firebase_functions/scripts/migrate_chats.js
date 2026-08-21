/**
 * Firebase Admin Migration & Verification Script for Direct Chats & User Conversation Indexes
 *
 * Usage:
 *   Dry-Run (Default):
 *     node scripts/migrate_chats.js
 *
 *   Read-Only Verification Mode:
 *     node scripts/migrate_chats.js --verify
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

function initAdminApp() {
  if (!admin.apps.length) {
    admin.initializeApp({
      databaseURL: DATABASE_URL,
    });
  }
  return admin.database();
}

async function cleanupAdmin() {
  if (admin.apps.length > 0) {
    await Promise.all(admin.apps.map((app) => app.delete()));
  }
}

// Helper function to extract participants from conversation object
function extractParticipants(conv) {
  if (!conv || typeof conv !== 'object') return [];
  const pMap = conv.participants || conv.Participants;
  if (Array.isArray(pMap)) {
    return pMap.map(String);
  } else if (pMap && typeof pMap === 'object') {
    return Object.keys(pMap);
  }
  return [];
}

// Helper to extract latest message & unread state metadata
function extractMetadata(conv) {
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

  return { lastMsgText, lastMsgTimestamp, unreadMap, isAgreement };
}

// Analyze conversations and generate expected index mappings and anomalies
function analyzeConversations(conversations) {
  const convIds = Object.keys(conversations || {});
  let totalInspected = 0;
  let rawIndexAssignments = 0;
  let totalAnomalies = 0;

  const pendingUpdates = {};
  const expectedUniqueIndexMap = {};
  const duplicateCollidingPaths = [];
  const duplicateParticipantConvs = [];

  for (const convId of convIds) {
    totalInspected++;
    const conv = conversations[convId];
    if (!conv || typeof conv !== 'object') {
      totalAnomalies++;
      continue;
    }

    const participants = extractParticipants(conv);
    if (participants.length === 0) {
      totalAnomalies++;
      continue;
    }

    const uniqueUids = Array.from(new Set(participants));
    if (uniqueUids.length < participants.length || uniqueUids.length === 1) {
      duplicateParticipantConvs.push({ convId, uids: participants });
    }

    const { lastMsgText, lastMsgTimestamp, unreadMap, isAgreement } = extractMetadata(conv);
    const pathsSeenInThisConv = new Set();

    participants.forEach((uid) => {
      const otherUid = participants.find((id) => id !== uid) || '';
      const hasUnread = unreadMap[uid] === true;
      const indexPath = `userConversations/${uid}/${convId}`;

      rawIndexAssignments++;

      if (pathsSeenInThisConv.has(indexPath)) {
        duplicateCollidingPaths.push({ convId, path: indexPath, uid });
      } else {
        pathsSeenInThisConv.add(indexPath);
      }

      const entryObj = {
        otherUserId: otherUid,
        lastMessageText: lastMsgText,
        lastMessageTimestamp: lastMsgTimestamp,
        hasUnread: hasUnread,
        conversationType: isAgreement ? 'agreement' : 'direct',
      };

      expectedUniqueIndexMap[indexPath] = entryObj;

      pendingUpdates[`${indexPath}/otherUserId`] = otherUid;
      pendingUpdates[`${indexPath}/lastMessageText`] = lastMsgText;
      pendingUpdates[`${indexPath}/lastMessageTimestamp`] = lastMsgTimestamp;
      pendingUpdates[`${indexPath}/hasUnread`] = hasUnread;
      pendingUpdates[`${indexPath}/conversationType`] = isAgreement ? 'agreement' : 'direct';
    });
  }

  return {
    totalInspected,
    rawIndexAssignments,
    totalAnomalies,
    pendingUpdates,
    expectedUniqueIndexMap,
    duplicateCollidingPaths,
    duplicateParticipantConvs,
  };
}

// Compare expected unique index mappings against actual persisted userConversations
function verifyIndexes(conversations, actualUserConversations) {
  const analysis = analyzeConversations(conversations);
  const expectedMap = analysis.expectedUniqueIndexMap;

  const actualMap = {};
  if (actualUserConversations && typeof actualUserConversations === 'object') {
    Object.keys(actualUserConversations).forEach((uid) => {
      const uConvs = actualUserConversations[uid];
      if (uConvs && typeof uConvs === 'object') {
        Object.keys(uConvs).forEach((convId) => {
          const path = `userConversations/${uid}/${convId}`;
          actualMap[path] = uConvs[convId];
        });
      }
    });
  }

  const expectedPaths = Object.keys(expectedMap);
  const actualPaths = Object.keys(actualMap);

  const missingExpectedPaths = expectedPaths.filter((p) => !actualMap[p]);
  const unexpectedExtraPaths = actualPaths.filter((p) => !expectedMap[p]);
  const metadataMismatches = [];

  expectedPaths.forEach((path) => {
    if (actualMap[path]) {
      const exp = expectedMap[path];
      const act = actualMap[path];
      const fields = ['otherUserId', 'lastMessageText', 'lastMessageTimestamp', 'hasUnread', 'conversationType'];
      fields.forEach((field) => {
        if (exp[field] !== act[field]) {
          const parts = path.split('/');
          const uid = parts[1];
          const convId = parts[2];
          metadataMismatches.push({ convId, uid, field });
        }
      });
    }
  });

  return {
    ...analysis,
    expectedUniquePathsCount: expectedPaths.length,
    actualPersistedPathsCount: actualPaths.length,
    missingExpectedPaths,
    unexpectedExtraPaths,
    metadataMismatches,
  };
}

async function migrateChats() {
  const args = process.argv.slice(2);
  const isWriteMode = args.includes('--write');
  const isVerifyMode = args.includes('--verify');

  if (isVerifyMode && isWriteMode) {
    console.error('ERROR: Cannot combine --verify and --write flags.');
    process.exit(1);
  }

  if (isWriteMode && process.env.CONFIRM_PRODUCTION_MIGRATION !== 'true') {
    console.error('ERROR: Write mode requested, but environment variable CONFIRM_PRODUCTION_MIGRATION=true is missing.');
    console.error('Migration aborted for safety.');
    process.exit(1);
  }

  const db = initAdminApp();

  console.log('====================================================');
  console.log(`Starting Chat Index Migration [Mode: ${isVerifyMode ? 'VERIFY (READ-ONLY)' : isWriteMode ? 'WRITE' : 'DRY-RUN'}]`);
  console.log('====================================================');

  const convsSnap = await db.ref('/conversations').once('value');
  const conversations = convsSnap.exists() ? convsSnap.val() : {};

  if (isVerifyMode) {
    const userConvsSnap = await db.ref('/userConversations').once('value');
    const actualUserConvs = userConvsSnap.exists() ? userConvsSnap.val() : {};

    const verification = verifyIndexes(conversations, actualUserConvs);

    console.log('----------------------------------------------------');
    console.log(`READ-ONLY VERIFICATION REPORT:`);
    console.log(`- Conversations Inspected: ${verification.totalInspected}`);
    console.log(`- Raw Index Assignments Generated: ${verification.rawIndexAssignments}`);
    console.log(`- Expected Unique Index Paths: ${verification.expectedUniquePathsCount}`);
    console.log(`- Actual Persisted Index Paths: ${verification.actualPersistedPathsCount}`);
    console.log(`- Missing Expected Paths: ${verification.missingExpectedPaths.length}`);
    console.log(`- Unexpected Extra Paths: ${verification.unexpectedExtraPaths.length}`);
    console.log(`- Entries with Mismatched Metadata: ${verification.metadataMismatches.length}`);
    console.log(`- Duplicate or Colliding Generated Paths: ${verification.duplicateCollidingPaths.length}`);
    console.log(`- Conversations with Duplicate/Self Participants: ${verification.duplicateParticipantConvs.length}`);
    console.log('----------------------------------------------------');

    if (verification.missingExpectedPaths.length > 0) {
      console.log('[Discrepancy: Missing Expected Paths]');
      verification.missingExpectedPaths.forEach((path) => {
        const parts = path.split('/');
        console.log(`  convId: ${parts[2]}, uid: ${parts[1]}`);
      });
    }

    if (verification.unexpectedExtraPaths.length > 0) {
      console.log('[Discrepancy: Unexpected Extra Paths]');
      verification.unexpectedExtraPaths.forEach((path) => {
        const parts = path.split('/');
        console.log(`  convId: ${parts[2]}, uid: ${parts[1]}`);
      });
    }

    if (verification.metadataMismatches.length > 0) {
      console.log('[Discrepancy: Metadata Mismatch]');
      verification.metadataMismatches.forEach((m) => {
        console.log(`  convId: ${m.convId}, uid: ${m.uid}, field: ${m.field}`);
      });
    }

    if (verification.duplicateCollidingPaths.length > 0) {
      console.log('[Discrepancy: Duplicate Colliding Generated Paths]');
      verification.duplicateCollidingPaths.forEach((c) => {
        console.log(`  convId: ${c.convId}, uid: ${c.uid}`);
      });
    }

    if (verification.duplicateParticipantConvs.length > 0) {
      console.log('[Discrepancy: Duplicate/Self Participants]');
      verification.duplicateParticipantConvs.forEach((c) => {
        console.log(`  convId: ${c.convId}, participantUids: [${c.uids.join(', ')}]`);
      });
    }

    console.log('----------------------------------------------------');
    console.log('VERIFICATION COMPLETE: Zero writes executed.');
    return;
  }

  const analysis = analyzeConversations(conversations);

  console.log('----------------------------------------------------');
  console.log(`Inspection Complete:`);
  console.log(`- Conversations Inspected: ${analysis.totalInspected}`);
  console.log(`- Raw Index Assignments Generated: ${analysis.rawIndexAssignments}`);
  console.log(`- Expected Unique Index Paths: ${Object.keys(analysis.expectedUniqueIndexMap).length}`);
  console.log(`- Anomalies Flagged: ${analysis.totalAnomalies}`);
  console.log(`- Colliding Paths Collapsed: ${analysis.duplicateCollidingPaths.length}`);
  console.log('----------------------------------------------------');

  if (isWriteMode) {
    if (Object.keys(analysis.pendingUpdates).length > 0) {
      console.log('Applying atomic multi-location update to Firebase Realtime Database...');
      await db.ref().update(analysis.pendingUpdates);
      console.log('SUCCESS: Migration write complete!');
    } else {
      console.log('No index updates needed.');
    }
  } else {
    console.log('DRY-RUN COMPLETE: No changes were written to the database.');
    console.log('To perform read-only verification, run:');
    console.log('  node scripts/migrate_chats.js --verify');
    console.log('To perform real writes, run:');
    console.log('  CONFIRM_PRODUCTION_MIGRATION=true node scripts/migrate_chats.js --write');
  }
}

// Module export for unit tests
module.exports = {
  extractParticipants,
  extractMetadata,
  analyzeConversations,
  verifyIndexes,
  migrateChats,
  cleanupAdmin,
};

// CLI entry point
if (require.main === module) {
  migrateChats()
    .catch((err) => {
      console.error('Fatal error during migration execution:', err);
      process.exitCode = 1;
    })
    .finally(async () => {
      await cleanupAdmin();
    });
}
