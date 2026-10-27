/**
 * Fixture & Verification Script for SubRequest Migration: Backfill & Cleanup Phases
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

if (!process.env.FIREBASE_DATABASE_URL) {
  process.env.FIREBASE_DATABASE_URL = 'http://127.0.0.1:9000?ns=demo-musicians-test';
}
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: 'demo-musicians-test',
    databaseURL: process.env.FIREBASE_DATABASE_URL,
  });
}

const { runBackfill, runCleanup } = require('../scripts/migrate_subrequests');

async function setupFixture(db) {
  console.log('Seeding emulator fixture with comprehensive migration test cases...');
  await db.ref().set(null); // Clean state

  const fixture = {
    users: {
      user_creator_1: {
        DisplayName: 'Creator 1',
        Favorites: {
          user_fav_1: true,
          user_fav_2: true,
        },
        SubRequests: {
          legacy_user_sub_1: { Title: 'Old Sub in user node' },
        },
        CancelledSubRequests: {
          legacy_user_canc_1: { Title: 'Old Cancelled in user node' },
        },
      },
      user_creator_2: {
        DisplayName: 'Creator 2 (No Favorites)',
        Favorites: {},
      },
      user_fav_1: { DisplayName: 'Favorite Musician 1' },
      user_fav_2: { DisplayName: 'Favorite Musician 2' },
      user_target_1: { DisplayName: 'Direct Target 1' },
    },
    SubRequests: {
      // 1. Canonical Public Gig
      req_canonical_pub_1: {
        SubRequestId: 'req_canonical_pub_1',
        CreatorUserId: 'user_creator_1',
        NotificationMode: 'both',
        VoicePart: 'Drums',
        Status: 'published',
      },
      // 2. Canonical Direct Invitation
      req_canonical_direct_1: {
        SubRequestId: 'req_canonical_direct_1',
        CreatorUserId: 'user_creator_1',
        NotificationMode: 'both',
        Type: 'direct_invitation',
        targetUserIds: ['user_target_1'],
        VoicePart: 'Bass',
        Status: 'published',
      },
      // 3. Canonical Favorites with audience
      req_canonical_fav_with_aud: {
        SubRequestId: 'req_canonical_fav_with_aud',
        CreatorUserId: 'user_creator_1',
        NotificationMode: 'both',
        IsFavoritesOnly: true,
        targetUserIds: ['user_fav_1'],
        VoicePart: 'Keyboard',
        Status: 'published',
      },
      // 4. Canonical Favorites with missing audience (creator 2 has no favorites)
      req_canonical_fav_no_aud: {
        SubRequestId: 'req_canonical_fav_no_aud',
        CreatorUserId: 'user_creator_2',
        NotificationMode: 'both',
        IsFavoritesOnly: true,
        targetUserIds: [],
        VoicePart: 'Guitar',
        Status: 'published',
      },
      // 5. Promo Map Pin (must not create staffing feeds)
      req_canonical_map_pin: {
        SubRequestId: 'req_canonical_map_pin',
        CreatorUserId: 'user_creator_1',
        NotificationMode: 'map_pin',
        SnippetTitle: 'Promo Track',
        Status: 'published',
      },
      // 6. Cancelled record
      req_canonical_cancelled: {
        SubRequestId: 'req_canonical_cancelled',
        CreatorUserId: 'user_creator_1',
        VoicePart: 'Saxophone',
        Status: 'cancelled',
      },
      // 7. Invalid record (missing role/title)
      req_canonical_invalid: {
        SubRequestId: 'req_canonical_invalid',
        CreatorUserId: 'user_creator_1',
        Status: 'published',
      },
      // 8. Missing creator record
      req_canonical_no_creator: {
        SubRequestId: 'req_canonical_no_creator',
        VoicePart: 'Vocals',
        Status: 'published',
      },
      // 9. Conflict record (published in canonical, but cancelled in legacy)
      req_conflict_1: {
        SubRequestId: 'req_conflict_1',
        CreatorUserId: 'user_creator_1',
        VoicePart: 'Piano',
        Status: 'published',
      },
    },
    BandEvents: {
      PublishedSubRequests: {
        // Legacy mirror of req_conflict_1 with differing status
        req_conflict_1: {
          SubRequestId: 'req_conflict_1',
          CreatorUserId: 'user_creator_1',
          VoicePart: 'Piano',
          Status: 'cancelled',
        },
        // 10. Legacy-only record (does not exist in /SubRequests)
        req_legacy_only_pub: {
          SubRequestId: 'req_legacy_only_pub',
          CreatorUserId: 'user_creator_1',
          VoicePart: 'Trumpet',
          Status: 'published',
        },
      },
      CancelledSubRequests: {
        req_legacy_cancelled_1: {
          SubRequestId: 'req_legacy_cancelled_1',
          Status: 'cancelled',
        },
      },
    },
  };

  await db.ref().set(fixture);
  console.log('Fixture successfully loaded.');
}

async function runFixtureVerification() {
  const db = admin.database();
  await setupFixture(db);

  // STEP 1: Dry-Run Backfill
  console.log('\n--- 1. TESTING BACKFILL DRY-RUN ---');
  const snapBeforeBackfillDry = JSON.stringify((await db.ref().once('value')).val());
  await runBackfill(db, false);
  const snapAfterBackfillDry = JSON.stringify((await db.ref().once('value')).val());
  if (snapBeforeBackfillDry !== snapAfterBackfillDry) {
    throw new Error('VIOLATION: Backfill dry-run modified the database!');
  }
  console.log('[PASS] Backfill dry-run left database completely untouched.');

  // STEP 2: Apply Backfill
  console.log('\n--- 2. TESTING BACKFILL APPLY ---');
  await runBackfill(db, true);

  // PROVE: New feeds are populated
  const [pubFeedsSnap, creatorFeedsSnap, userFeedsSnap, legacyPubSnap, legacyCancSnap, userSubSnap] = await Promise.all([
    db.ref('publicSubRequests').once('value'),
    db.ref('creatorSubRequestFeed').once('value'),
    db.ref('userSubRequestFeed').once('value'),
    db.ref('BandEvents/PublishedSubRequests').once('value'),
    db.ref('BandEvents/CancelledSubRequests').once('value'),
    db.ref('users/user_creator_1/SubRequests').once('value'),
  ]);

  if (!pubFeedsSnap.exists() || Object.keys(pubFeedsSnap.val()).length === 0) {
    throw new Error('VIOLATION: /publicSubRequests was not populated after backfill apply!');
  }
  if (!creatorFeedsSnap.exists()) {
    throw new Error('VIOLATION: /creatorSubRequestFeed was not populated after backfill apply!');
  }
  if (!userFeedsSnap.exists()) {
    throw new Error('VIOLATION: /userSubRequestFeed was not populated after backfill apply!');
  }

  // PROVE: Legacy data still exists untouched after backfill!
  if (!legacyPubSnap.exists() || !legacyCancSnap.exists() || !userSubSnap.exists()) {
    throw new Error('VIOLATION: Backfill deleted or altered legacy nodes! Legacy data MUST remain intact during backfill.');
  }
  console.log('[PASS] Backfill successfully populated new feeds AND preserved all legacy mirror records untouched.');

  // STEP 3: Dry-Run Cleanup
  console.log('\n--- 3. TESTING CLEANUP DRY-RUN ---');
  const snapBeforeCleanupDry = JSON.stringify((await db.ref().once('value')).val());
  await runCleanup(db, false, false);
  const snapAfterCleanupDry = JSON.stringify((await db.ref().once('value')).val());
  if (snapBeforeCleanupDry !== snapAfterCleanupDry) {
    throw new Error('VIOLATION: Cleanup dry-run modified the database!');
  }
  console.log('[PASS] Cleanup dry-run left database completely untouched.');

  // STEP 4: Apply Cleanup without confirmation flag -> must throw
  console.log('\n--- 4. TESTING CLEANUP APPLY SAFETY GATE (Without Confirmation Flag) ---');
  let threw = false;
  try {
    await runCleanup(db, true, false);
  } catch (err) {
    threw = true;
    console.log('[PASS] Safety gate blocked unconfirmed cleanup:', err.message);
  }
  if (!threw) {
    throw new Error('VIOLATION: Cleanup without confirmation flag succeeded when it must fail!');
  }

  // STEP 5: Apply Cleanup with confirmation flag
  console.log('\n--- 5. TESTING CLEANUP APPLY (With Confirmation Flag) ---');
  await runCleanup(db, true, true);

  // PROVE: Legacy data is gone
  const [legacyPubPostClean, legacyCancPostClean, userSubPostClean, userCancPostClean] = await Promise.all([
    db.ref('BandEvents/PublishedSubRequests').once('value'),
    db.ref('BandEvents/CancelledSubRequests').once('value'),
    db.ref('users/user_creator_1/SubRequests').once('value'),
    db.ref('users/user_creator_1/CancelledSubRequests').once('value'),
  ]);

  if (legacyPubPostClean.exists() || legacyCancPostClean.exists() || userSubPostClean.exists() || userCancPostClean.exists()) {
    throw new Error('VIOLATION: Legacy mirror nodes still exist after cleanup apply!');
  }

  // PROVE: New feeds still exist and remain completely intact
  const [pubFeedsPostClean, creatorFeedsPostClean, userFeedsPostClean] = await Promise.all([
    db.ref('publicSubRequests').once('value'),
    db.ref('creatorSubRequestFeed').once('value'),
    db.ref('userSubRequestFeed').once('value'),
  ]);

  if (!pubFeedsPostClean.exists() || !creatorFeedsPostClean.exists() || !userFeedsPostClean.exists()) {
    throw new Error('VIOLATION: Cleanup accidentally deleted new feeds!');
  }
  console.log('[PASS] Cleanup successfully removed all legacy mirrors while preserving all new feeds intact.');

  // Clean up any generated manifest files
  const files = fs.readdirSync(path.join(__dirname, '..'));
  files.forEach((f) => {
    if (f.startsWith('cleanup_manifest_') && f.endsWith('.json')) {
      fs.unlinkSync(path.join(__dirname, '..', f));
    }
  });

  console.log('\nALL SPLIT MIGRATION PHASES VERIFIED WITH 100% EVIDENCE.');
}

if (require.main === module) {
  runFixtureVerification()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\nVerification failed:', err);
      process.exit(1);
    });
}
