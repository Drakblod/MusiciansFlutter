/**
 * Strict Verification Tool: SubRequest Security Migration
 *
 * Performs a comprehensive read-only audit of server-owned feeds against canonical records.
 *
 * RULES VERIFIED (Exact parity with migration logic):
 * 1. Every applicable canonical SubRequest has the correct creator feed entry.
 * 2. Every public staffing request has the correct publicSubRequests entry.
 * 3. Direct Invitations and Favorites-only requests NEVER appear in publicSubRequests.
 * 4. Promo map_pins NEVER appear in publicSubRequests, userSubRequestFeed, or creator staffing feeds.
 * 5. Private requests are distributed ONLY to intended recipient feeds.
 * 6. Feed entries are sanitized and do not leak target lists, tokens, emails, phone numbers.
 * 7. No orphan feed entries (every feed entry refers to an existing canonical record).
 * 8. IDs and canonical references match.
 *
 * EXIT CODES:
 * - Code 0: Every check passes with zero violations.
 * - Code 1: One or more violations, leaks, orphans, or invalid records found.
 *
 * SAFETY GUARANTEES:
 * - Strictly read-only (0 database writes).
 * - Production runs require explicit target flags (`--allow-production` and `--confirm-production`).
 * - Never prints sensitive payloads; outputs IDs and summary categories only.
 */

const admin = require('firebase-admin');
const { classifySubRequest, SUBREQUEST_KIND } = require('../index');

// Forbidden fields that should NEVER exist in sanitized feed items
const FORBIDDEN_FIELDS = [
  'targetUserIds',
  'TargetUserIds',
  'targetUserNames',
  'TargetUserNames',
  'pushTokens',
  'fcmToken',
  'deviceTokens',
  'email',
  'Email',
  'phone',
  'Phone',
  'password',
  'userToken',
];

async function verifyMigration() {
  const args = process.argv.slice(2);
  const allowProd = args.includes('--allow-production');
  const confirmProd = args.includes('--confirm-production');

  const projectArg = args.find((a) => a.startsWith('--project='));
  const urlArg = args.find((a) => a.startsWith('--database-url='));

  let projectId = projectArg ? projectArg.split('=')[1] : (process.env.GCLOUD_PROJECT || 'demo-musicians-test');
  let databaseUrl = urlArg ? urlArg.split('=')[1] : (process.env.FIREBASE_DATABASE_URL || 'http://127.0.0.1:9000?ns=' + projectId);

  const isEmulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST) ||
    databaseUrl.includes('127.0.0.1') ||
    databaseUrl.includes('localhost') ||
    projectId === 'demo-musicians-test';

  console.log('=== SUBREQUEST MIGRATION VERIFIER ===');
  console.log('Target Project ID:  ', projectId);
  console.log('Target Database URL:', databaseUrl);
  console.log('Execution Mode:     ', isEmulator ? 'EMULATOR / TEST' : 'PRODUCTION');
  console.log('Read-Only:           YES (Zero writes performed)\n');

  if (!isEmulator) {
    if (!allowProd) {
      throw new Error(
        'FATAL: Target is PRODUCTION (Project: ' +
          projectId +
          '). Running against production requires explicit `--allow-production`.'
      );
    }
    if (!confirmProd) {
      throw new Error(
        'FATAL: Reading production data requires explicit confirmation flag `--confirm-production`.'
      );
    }
  }

  if (admin.apps.length && !admin.app().options.databaseURL) {
    await admin.app().delete();
  }
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: projectId,
      databaseURL: databaseUrl,
    });
  }

  const db = admin.database();

  console.log('Reading database snapshots...');
  const [subSnap, pubSnap, creatorSnap, userSnap, usersProfileSnap] = await Promise.all([
    db.ref('SubRequests').once('value'),
    db.ref('publicSubRequests').once('value'),
    db.ref('creatorSubRequestFeed').once('value'),
    db.ref('userSubRequestFeed').once('value'),
    db.ref('users').once('value'),
  ]);

  const canonical = subSnap.val() || {};
  const publicFeeds = pubSnap.val() || {};
  const creatorFeeds = creatorSnap.val() || {};
  const userFeeds = userSnap.val() || {};
  const usersProfiles = usersProfileSnap.val() || {};

  const metrics = {
    canonicalTotal: Object.keys(canonical).length,
    publicFeedsTotal: Object.keys(publicFeeds).length,
    creatorFeedsEntries: 0,
    userFeedsEntries: 0,
    activeStaffing: 0,
    promoPins: 0,
    cancelled: 0,
  };

  Object.values(creatorFeeds).forEach((m) => {
    metrics.creatorFeedsEntries += Object.keys(m).length;
  });
  Object.values(userFeeds).forEach((m) => {
    metrics.userFeedsEntries += Object.keys(m).length;
  });

  const violations = [];

  function recordViolation(category, id, detail) {
    violations.push({ category, id, detail });
  }

  function checkForbiddenFields(item, feedName, id) {
    if (!item || typeof item !== 'object') return;
    FORBIDDEN_FIELDS.forEach((field) => {
      if (item[field] !== undefined) {
        recordViolation('SENSITIVE_FIELD_LEAK', id, `Field "${field}" found in ${feedName}`);
      }
    });
  }

  // 1. AUDIT CANONICAL RECORDS AND EXPECTED FEED TARGETS
  for (const [key, raw] of Object.entries(canonical)) {
    if (!raw || typeof raw !== 'object') {
      recordViolation('INVALID_CANONICAL_PAYLOAD', key, 'Record is not an object');
      continue;
    }

    const creatorId = raw.CreatorUserId || raw.creatorUserId || raw.UserId || raw.userId;
    const status = (raw.Status || raw.status || 'published').toLowerCase();
    const isSelected = raw.IsSelected === true || raw.isSelected === true;
    const isAssigned = status === 'assigned' || isSelected;
    const isClosed = status === 'cancelled' || status === 'deleted' || status === 'closed';

    const kind = classifySubRequest(raw);

    // Check Map Pins
    if (kind === SUBREQUEST_KIND.PROMO_MAP_PIN) {
      metrics.promoPins++;
      if (publicFeeds[key]) {
        recordViolation('MAP_PIN_IN_PUBLIC_FEED', key, 'map_pin promo request found in publicSubRequests');
      }
      Object.entries(userFeeds).forEach(([uid, feed]) => {
        if (feed[key]) {
          recordViolation('MAP_PIN_IN_USER_FEED', key, `map_pin promo request found in userSubRequestFeed/${uid}`);
        }
      });
      Object.entries(creatorFeeds).forEach(([uid, feed]) => {
        if (feed[key]) {
          recordViolation('MAP_PIN_IN_CREATOR_FEED', key, `map_pin promo request found in creatorSubRequestFeed/${uid}`);
        }
      });
      continue;
    }

    if (isClosed) {
      metrics.cancelled++;
      if (publicFeeds[key]) {
        recordViolation('CLOSED_IN_PUBLIC_FEED', key, `Closed/cancelled request (${status}) exists in publicSubRequests`);
      }
      Object.entries(userFeeds).forEach(([uid, feed]) => {
        if (feed[key]) {
          recordViolation('CLOSED_IN_USER_FEED', key, `Closed/cancelled request exists in userSubRequestFeed/${uid}`);
        }
      });
      continue;
    }

    metrics.activeStaffing++;

    // Creator Feed Verification
    if (creatorId) {
      const creatorItem = creatorFeeds[creatorId] && creatorFeeds[creatorId][key];
      if (!creatorItem) {
        recordViolation('MISSING_CREATOR_FEED_ENTRY', key, `Expected entry in creatorSubRequestFeed/${creatorId}/${key}`);
      } else {
        checkForbiddenFields(creatorItem, `creatorSubRequestFeed/${creatorId}`, key);
      }
    } else {
      recordViolation('CANONICAL_MISSING_CREATOR_ID', key, 'Active canonical staffing request has no CreatorUserId');
    }

    // Public vs Private Isolation Verification
    if (kind === SUBREQUEST_KIND.PUBLIC_GIG || kind === SUBREQUEST_KIND.EVENT_SUBSTITUTE_PUBLIC) {
      if (!isAssigned) {
        const pubItem = publicFeeds[key];
        if (!pubItem) {
          recordViolation('MISSING_PUBLIC_FEED_ENTRY', key, 'Public staffing request missing from publicSubRequests');
        } else {
          checkForbiddenFields(pubItem, 'publicSubRequests', key);
        }
      } else {
        if (publicFeeds[key]) {
          recordViolation('ASSIGNED_IN_PUBLIC_FEED', key, 'Assigned slot not removed from publicSubRequests');
        }
      }
    } else if (kind === SUBREQUEST_KIND.DIRECT_INVITATION) {
      // Must NEVER exist in public feed
      if (publicFeeds[key]) {
        recordViolation('DIRECT_INVITATION_LEAK_IN_PUBLIC', key, 'Direct invitation leaked into publicSubRequests');
      }

      const rawTargets = raw.targetUserIds || raw.TargetUserIds || [];
      const expectedTargets = new Set(rawTargets.filter((t) => t && t !== creatorId));

      expectedTargets.forEach((targetUid) => {
        if (!isAssigned) {
          const recipientItem = userFeeds[targetUid] && userFeeds[targetUid][key];
          if (!recipientItem) {
            recordViolation('MISSING_DIRECT_RECIPIENT_ENTRY', key, `Expected entry in userSubRequestFeed/${targetUid}`);
          } else {
            checkForbiddenFields(recipientItem, `userSubRequestFeed/${targetUid}`, key);
          }
        }
      });

      // Verify no UNINTENDED users have this direct invitation
      Object.entries(userFeeds).forEach(([uid, feed]) => {
        if (feed[key] && !expectedTargets.has(uid)) {
          recordViolation('UNAUTHORIZED_DIRECT_RECIPIENT', key, `Unauthorized user ${uid} has request in feed`);
        }
      });
    } else if (kind === SUBREQUEST_KIND.FAVORITES_ONLY) {
      // Must NEVER exist in public feed
      if (publicFeeds[key]) {
        recordViolation('FAVORITES_ONLY_LEAK_IN_PUBLIC', key, 'Favorites-only request leaked into publicSubRequests');
      }

      const creatorFavs = (creatorId && usersProfiles[creatorId]?.Favorites) || {};
      const rawTargets = raw.targetUserIds || raw.TargetUserIds || [];
      const eligibleFavs = new Set();

      Object.keys(usersProfiles).forEach((uid) => {
        if (uid === creatorId) return;
        const isFav = creatorFavs[uid] === true || creatorFavs[uid] === 'true';
        if (isFav && (rawTargets.length === 0 || rawTargets.includes(uid))) {
          eligibleFavs.add(uid);
        }
      });

      eligibleFavs.forEach((targetUid) => {
        if (!isAssigned) {
          const recipientItem = userFeeds[targetUid] && userFeeds[targetUid][key];
          if (!recipientItem) {
            recordViolation('MISSING_FAVORITE_RECIPIENT_ENTRY', key, `Expected entry in userSubRequestFeed/${targetUid}`);
          } else {
            checkForbiddenFields(recipientItem, `userSubRequestFeed/${targetUid}`, key);
          }
        }
      });

      // Verify no UNINTENDED users have this favorites-only request
      Object.entries(userFeeds).forEach(([uid, feed]) => {
        if (feed[key] && !eligibleFavs.has(uid)) {
          recordViolation('UNAUTHORIZED_FAVORITE_RECIPIENT', key, `Unauthorized user ${uid} has request in feed`);
        }
      });
    }
  }

  // 2. ORPHAN FEED ENTRY CHECKS
  // Check publicSubRequests for orphans
  for (const key of Object.keys(publicFeeds)) {
    if (!canonical[key]) {
      recordViolation('ORPHAN_PUBLIC_FEED_ENTRY', key, 'publicSubRequests entry has no canonical record');
    }
  }

  // Check creatorSubRequestFeed for orphans
  for (const [creatorId, feed] of Object.entries(creatorFeeds)) {
    for (const key of Object.keys(feed)) {
      if (!canonical[key]) {
        recordViolation('ORPHAN_CREATOR_FEED_ENTRY', key, `creatorSubRequestFeed/${creatorId} entry has no canonical record`);
      }
    }
  }

  // Check userSubRequestFeed for orphans
  for (const [userId, feed] of Object.entries(userFeeds)) {
    for (const key of Object.keys(feed)) {
      if (!canonical[key]) {
        recordViolation('ORPHAN_USER_FEED_ENTRY', key, `userSubRequestFeed/${userId} entry has no canonical record`);
      }
    }
  }

  // 3. REPORTING RESULTS
  console.log('--- VERIFICATION METRICS ---');
  console.table({
    'Canonical Records': metrics.canonicalTotal,
    'Active Staffing Requests': metrics.activeStaffing,
    'Promo / Map Pins': metrics.promoPins,
    'Cancelled / Closed Records': metrics.cancelled,
    'Entries in publicSubRequests': metrics.publicFeedsTotal,
    'Entries in creatorSubRequestFeed': metrics.creatorFeedsEntries,
    'Entries in userSubRequestFeed': metrics.userFeedsEntries,
    'Violations / Leaks Detected': violations.length,
  });

  if (violations.length > 0) {
    console.error('\n[FAILURE] ' + violations.length + ' INTEGRITY VIOLATION(S) DETECTED:');
    const summary = {};
    violations.forEach((v) => {
      summary[v.category] = (summary[v.category] || 0) + 1;
      console.error(` - [${v.category}] ID: ${v.id} -> ${v.detail}`);
    });
    console.error('\nSummary of Violations:');
    console.table(summary);
    return { success: false, violations };
  }

  console.log('\n[SUCCESS] ALL SUBREQUEST MIGRATION VERIFICATIONS PASSED (0 VIOLATIONS).');
  return { success: true, violations: [] };
}

if (require.main === module) {
  verifyMigration()
    .then((result) => {
      if (!result.success) {
        process.exit(1);
      }
      process.exit(0);
    })
    .catch((err) => {
      console.error('\nFATAL ERROR DURING VERIFICATION:', err.message);
      process.exit(1);
    });
}

module.exports = { verifyMigration };
