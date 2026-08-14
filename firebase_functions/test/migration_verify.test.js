const assert = require('assert');
const {
  extractParticipants,
  extractMetadata,
  analyzeConversations,
  verifyIndexes,
} = require('../scripts/migrate_chats');

describe('Migration & Verification Logic Unit Tests', () => {
  it('1. Correctly calculates raw assignments vs expected unique paths for normal conversations', () => {
    const convs = {
      conv_100: {
        participants: { user_a: true, user_b: true },
        messages: { m1: { text: 'Hello', timestamp: '2026-08-14T10:00:00Z' } },
      },
      conv_101: {
        participants: ['user_b', 'user_c'],
        messages: { m2: { text: 'Hey!', timestamp: '2026-08-14T10:05:00Z' } },
      },
    };

    const analysis = analyzeConversations(convs);

    assert.strictEqual(analysis.totalInspected, 2);
    assert.strictEqual(analysis.rawIndexAssignments, 4);
    assert.strictEqual(Object.keys(analysis.expectedUniqueIndexMap).length, 4);
    assert.strictEqual(analysis.duplicateCollidingPaths.length, 0);
    assert.strictEqual(analysis.duplicateParticipantConvs.length, 0);

    // Verify expected entry structure
    const entryA = analysis.expectedUniqueIndexMap['userConversations/user_a/conv_100'];
    assert.strictEqual(entryA.otherUserId, 'user_b');
    assert.strictEqual(entryA.lastMessageText, 'Hello');
    assert.strictEqual(entryA.conversationType, 'direct');
  });

  it('2. Detects colliding duplicate paths and self-conversations', () => {
    const convs = {
      conv_duplicate: {
        participants: ['user_a', 'user_a'], // Duplicate UIDs in list
        messages: { m1: { text: 'Self note' } },
      },
      conv_single: {
        participants: { user_b: true }, // Single participant self-chat
      },
    };

    const analysis = analyzeConversations(convs);

    assert.strictEqual(analysis.totalInspected, 2);
    assert.strictEqual(analysis.rawIndexAssignments, 3); // 2 from conv_duplicate + 1 from conv_single
    assert.strictEqual(Object.keys(analysis.expectedUniqueIndexMap).length, 2); // user_a and user_b paths
    assert.strictEqual(analysis.duplicateCollidingPaths.length, 1); // userConversations/user_a/conv_duplicate
    assert.strictEqual(analysis.duplicateParticipantConvs.length, 2);
  });

  it('3. Detects missing expected paths in verifyIndexes', () => {
    const conversations = {
      conv_1: { participants: { user_a: true, user_b: true } },
    };

    // Actual userConversations has only user_a's index, missing user_b's
    const actualUserConversations = {
      user_a: {
        conv_1: {
          otherUserId: 'user_b',
          lastMessageText: '',
          lastMessageTimestamp: '2026-08-14T10:00:00Z',
          hasUnread: false,
          conversationType: 'direct',
        },
      },
    };

    const result = verifyIndexes(conversations, actualUserConversations);

    assert.strictEqual(result.expectedUniquePathsCount, 2);
    assert.strictEqual(result.actualPersistedPathsCount, 1);
    assert.strictEqual(result.missingExpectedPaths.length, 1);
    assert.strictEqual(result.missingExpectedPaths[0], 'userConversations/user_b/conv_1');
    assert.strictEqual(result.unexpectedExtraPaths.length, 0);
  });

  it('4. Detects unexpected extra paths in verifyIndexes', () => {
    const conversations = {
      conv_1: { participants: { user_a: true, user_b: true } },
    };

    // Actual userConversations contains an extra orphaned conversation conv_orphaned for user_a
    const actualUserConversations = {
      user_a: {
        conv_1: { otherUserId: 'user_b', lastMessageText: '', lastMessageTimestamp: '2026-08-14T10:00:00Z', hasUnread: false, conversationType: 'direct' },
        conv_orphaned: { otherUserId: 'user_z', lastMessageText: 'ghost', lastMessageTimestamp: '2026-08-14T10:00:00Z', hasUnread: false, conversationType: 'direct' },
      },
      user_b: {
        conv_1: { otherUserId: 'user_a', lastMessageText: '', lastMessageTimestamp: '2026-08-14T10:00:00Z', hasUnread: false, conversationType: 'direct' },
      },
    };

    const result = verifyIndexes(conversations, actualUserConversations);

    assert.strictEqual(result.unexpectedExtraPaths.length, 1);
    assert.strictEqual(result.unexpectedExtraPaths[0], 'userConversations/user_a/conv_orphaned');
  });

  it('5. Detects metadata mismatches between expected and actual persisted entries', () => {
    const conversations = {
      conv_1: {
        participants: { user_a: true, user_b: true },
        messages: { m1: { text: 'Canonical message', timestamp: '2026-08-14T12:00:00Z' } },
        unread: { user_b: true },
      },
    };

    // Actual has stale lastMessageText and incorrect hasUnread flag for user_b
    const actualUserConversations = {
      user_a: {
        conv_1: { otherUserId: 'user_b', lastMessageText: 'Canonical message', lastMessageTimestamp: '2026-08-14T12:00:00Z', hasUnread: false, conversationType: 'direct' },
      },
      user_b: {
        conv_1: { otherUserId: 'user_a', lastMessageText: 'Old message', lastMessageTimestamp: '2026-08-14T12:00:00Z', hasUnread: false, conversationType: 'direct' },
      },
    };

    const result = verifyIndexes(conversations, actualUserConversations);

    assert(result.metadataMismatches.length >= 2);
    const mismatchedFields = result.metadataMismatches.map((m) => m.field);
    assert(mismatchedFields.includes('lastMessageText'));
    assert(mismatchedFields.includes('hasUnread'));
  });
});
