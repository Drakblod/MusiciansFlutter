/**
 * Backfill & Cleanup Administration Script: SubRequest Security Migration
 *
 * SPLIT MODES:
 * 1. BACKFILL: `--phase=backfill`
 *    - Scans canonical /SubRequests and legacy /BandEvents/PublishedSubRequests.
 *    - Populates /publicSubRequests, /userSubRequestFeed, /creatorSubRequestFeed, /subRequestAudience.
 *    - NEVER alters or deletes legacy nodes (/BandEvents or /users/{uid}/SubRequests).
 *
 * 2. CLEANUP: `--phase=cleanup`
 *    - Requires `--apply` AND `--confirm-legacy-delete`.
 *    - Validates that new feeds exist before allowing cleanup.
 *    - Writes a local JSON backup/manifest of all legacy records prior to deletion.
 *    - Atomically removes:
 *        - /BandEvents/PublishedSubRequests
 *        - /BandEvents/CancelledSubRequests
 *        - /users/{uid}/SubRequests
 *        - /users/{uid}/CancelledSubRequests
 *    - NEVER alters or removes new feeds.
 *
 * SAFETY GUARANTEES:
 * - Default execution mode is DRY-RUN for both phases.
 * - Explicit flag `--apply` is required to perform writes.
 * - Non-emulator / production runs require `--allow-production`.
 * - Idempotent and reversible via manifest.
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

if (!process.env.FIREBASE_DATABASE_URL) {
  process.env.FIREBASE_DATABASE_URL = 'http://127.0.0.1:9000?ns=demo-musicians-test';
}
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || 'demo-musicians-test',
    databaseURL: process.env.FIREBASE_DATABASE_URL,
  });
}

const { classifySubRequest, buildSanitizedFeedItem, SUBREQUEST_KIND } = require('../index');

async function runMigration() {
  const args = process.argv.slice(2);
  const phaseArg = args.find((a) => a.startsWith('--phase='));
  const phase = phaseArg ? phaseArg.split('=')[1].toLowerCase() : 'backfill';
  const isApply = args.includes('--apply');
  const confirmLegacyDelete = args.includes('--confirm-legacy-delete');
  const allowProd = args.includes('--allow-production');

  const isEmulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST) ||
    (process.env.FIREBASE_DATABASE_URL && process.env.FIREBASE_DATABASE_URL.includes('127.0.0.1')) ||
    (process.env.FIREBASE_DATABASE_URL && process.env.FIREBASE_DATABASE_URL.includes('localhost'));
  const projectId = process.env.GCLOUD_PROJECT || (admin.app().options && admin.app().options.projectId);

  // Safety Gate: Prevent unintended production writes
  if (!isEmulator && projectId !== 'demo-musicians-test' && !allowProd) {
    throw new Error(
      'FATAL: Target database is NOT an emulator (Project: ' +
        projectId +
        '). Explicit flag `--allow-production` is required to proceed. Aborting immediately.'
    );
  }

  const db = admin.database();

  if (phase === 'backfill') {
    return await runBackfill(db, isApply);
  } else if (phase === 'cleanup') {
    return await runCleanup(db, isApply, confirmLegacyDelete);
  } else {
    throw new Error('Invalid phase: ' + phase + '. Expected --phase=backfill or --phase=cleanup.');
  }
}

async function runBackfill(db, isApply) {
  console.log('=== SUBREQUEST MIGRATION: BACKFILL PHASE (Mode: ' + (isApply ? 'APPLY' : 'DRY-RUN') + ') ===\n');

  console.log('1. Reading /SubRequests (canonical)...');
  const canonicalSnap = await db.ref('SubRequests').once('value');
  const canonicalData = canonicalSnap.val() || {};

  console.log('2. Reading /BandEvents/PublishedSubRequests (legacy mirror)...');
  const legacyPubSnap = await db.ref('BandEvents/PublishedSubRequests').once('value');
  const legacyPubData = legacyPubSnap.val() || {};

  console.log('3. Reading /users for audience verification...');
  const usersSnap = await db.ref('users').once('value');
  const usersData = usersSnap.val() || {};

  const metrics = {
    canonicalCount: 0,
    legacyOnlyCount: 0,
    publicCount: 0,
    directCount: 0,
    favoritesCount: 0,
    mapPinCount: 0,
    cancelledCount: 0,
    invalidCount: 0,
    missingCreatorCount: 0,
    missingAudienceCount: 0,
    conflictsCount: 0,
    plannedPublicWrites: 0,
    plannedUserFeedWrites: 0,
    plannedCreatorFeedWrites: 0,
    legacyRemovalsCount: 0, // In backfill, strictly 0
  };

  const updates = {};
  const allKeys = new Set([...Object.keys(canonicalData), ...Object.keys(legacyPubData)]);

  allKeys.forEach((key) => {
    const isCanonical = Boolean(canonicalData[key]);
    const isLegacyOnly = !isCanonical && Boolean(legacyPubData[key]);

    if (isCanonical) {
      metrics.canonicalCount++;
    }
    if (isLegacyOnly) {
      metrics.legacyOnlyCount++;
    }

    const rawCanonical = canonicalData[key];
    const rawLegacy = legacyPubData[key];
    const raw = rawCanonical || rawLegacy;

    // Check for conflict between canonical and legacy mirror
    if (rawCanonical && rawLegacy) {
      const statusCanon = (rawCanonical.Status || rawCanonical.status || '').toLowerCase();
      const statusLeg = (rawLegacy.Status || rawLegacy.status || '').toLowerCase();
      if (statusCanon !== statusLeg) {
        metrics.conflictsCount++;
      }
    }

    // Invalid record check
    if (!raw || typeof raw !== 'object' || (!raw.VoicePart && !raw.Role && !raw.Instrument && !raw.EventTitle && !raw.BandName && !raw.SnippetTitle)) {
      metrics.invalidCount++;
      return;
    }

    const creatorId = raw.CreatorUserId || raw.creatorUserId || raw.UserId || raw.userId;
    if (!creatorId) {
      metrics.missingCreatorCount++;
    }

    const status = (raw.Status || raw.status || 'published').toLowerCase();
    const isSelected = raw.IsSelected === true || raw.isSelected === true;

    const kind = classifySubRequest(raw);

    if (kind === SUBREQUEST_KIND.PROMO_MAP_PIN) {
      metrics.mapPinCount++;
      return; // Skip staffing feeds for map pins
    }

    if (status === 'cancelled' || status === 'deleted' || status === 'closed') {
      metrics.cancelledCount++;
      return;
    }

    const sanitized = buildSanitizedFeedItem({
      ...raw,
      subRequestId: key,
      creatorUserId: creatorId || '',
    });

    if (creatorId) {
      updates[`creatorSubRequestFeed/${creatorId}/${key}`] = sanitized;
      metrics.plannedCreatorFeedWrites++;
    }

    if (status === 'assigned' || isSelected) {
      // Assigned requests stay in creator feed, but not in public or recipient feeds
      return;
    }

    if (kind === SUBREQUEST_KIND.PUBLIC_GIG || kind === SUBREQUEST_KIND.EVENT_SUBSTITUTE_PUBLIC) {
      metrics.publicCount++;
      updates[`publicSubRequests/${key}`] = sanitized;
      metrics.plannedPublicWrites++;
    } else if (kind === SUBREQUEST_KIND.FAVORITES_ONLY) {
      metrics.favoritesCount++;
      const creatorFavorites = (creatorId && usersData[creatorId]?.Favorites) || {};
      const rawTargets = raw.targetUserIds || raw.TargetUserIds || [];
      let audienceCount = 0;

      Object.keys(usersData).forEach((uid) => {
        if (uid === creatorId) return;
        const isFav = creatorFavorites[uid] === true || creatorFavorites[uid] === 'true';
        const isEligible = isFav && (rawTargets.length === 0 || rawTargets.includes(uid));
        if (isEligible) {
          updates[`subRequestAudience/${key}/${uid}`] = true;
          updates[`userSubRequestFeed/${uid}/${key}`] = sanitized;
          metrics.plannedUserFeedWrites++;
          audienceCount++;
        }
      });

      if (audienceCount === 0) {
        metrics.missingAudienceCount++;
      }
    } else if (kind === SUBREQUEST_KIND.DIRECT_INVITATION) {
      metrics.directCount++;
      const rawTargets = raw.targetUserIds || raw.TargetUserIds || [];
      let audienceCount = 0;

      rawTargets.forEach((targetUid) => {
        if (targetUid && targetUid !== creatorId) {
          updates[`subRequestAudience/${key}/${targetUid}`] = true;
          updates[`userSubRequestFeed/${targetUid}/${key}`] = sanitized;
          metrics.plannedUserFeedWrites++;
          audienceCount++;
        }
      });

      if (audienceCount === 0) {
        metrics.missingAudienceCount++;
      }
    }
  });

  console.log('\n--- BACKFILL METRICS ---');
  console.table({
    'Canonical SubRequests': metrics.canonicalCount,
    'Legacy-Only Records': metrics.legacyOnlyCount,
    'Public Staffing Requests': metrics.publicCount,
    'Direct Invitations': metrics.directCount,
    'Favorites-Only Requests': metrics.favoritesCount,
    'Promo / Map Pins': metrics.mapPinCount,
    'Cancelled / Closed Records': metrics.cancelledCount,
    'Invalid / Malformed Records': metrics.invalidCount,
    'Missing Creator ID': metrics.missingCreatorCount,
    'Missing Audience (0 targets)': metrics.missingAudienceCount,
    'Canonical vs Legacy Conflicts': metrics.conflictsCount,
    'Planned Public Feed Writes': metrics.plannedPublicWrites,
    'Planned Recipient Feed Writes': metrics.plannedUserFeedWrites,
    'Planned Creator Feed Writes': metrics.plannedCreatorFeedWrites,
    'Planned Legacy Removals': metrics.legacyRemovalsCount,
  });

  const totalOps = Object.keys(updates).length;
  console.log(`Total new feed write operations planned: ${totalOps}`);

  if (isApply) {
    if (totalOps > 0) {
      console.log('Writing feeds to database...');
      await db.ref().update(updates);
      console.log('Backfill apply successfully completed!');
    } else {
      console.log('Zero updates needed.');
    }
  } else {
    console.log('\nDRY-RUN COMPLETE: No changes were written to the database.');
    console.log('To apply backfill, run with `--phase=backfill --apply`.');
  }

  return metrics;
}

async function runCleanup(db, isApply, confirmLegacyDelete) {
  console.log('=== SUBREQUEST MIGRATION: CLEANUP PHASE (Mode: ' + (isApply ? 'APPLY' : 'DRY-RUN') + ') ===\n');

  if (isApply && !confirmLegacyDelete) {
    throw new Error(
      'BLOCKED: Cleanup execution with --apply requires explicit confirmation flag `--confirm-legacy-delete`.'
    );
  }

  // Verification Gate: Verify that new feeds are populated before allowing cleanup
  console.log('Verifying new feeds integrity prior to cleanup...');
  const [publicFeedSnap, creatorFeedSnap, canonicalSnap] = await Promise.all([
    db.ref('publicSubRequests').once('value'),
    db.ref('creatorSubRequestFeed').once('value'),
    db.ref('SubRequests').once('value'),
  ]);

  const publicFeed = publicFeedSnap.val() || {};
  const creatorFeed = creatorFeedSnap.val() || {};
  const canonical = canonicalSnap.val() || {};

  const activeCanonicalCount = Object.values(canonical).filter((r) => {
    const st = (r.Status || r.status || '').toLowerCase();
    const mode = r.NotificationMode || r.notificationMode;
    return st === 'published' && mode !== 'map_pin';
  }).length;

  const totalNewFeedsCount = Object.keys(publicFeed).length + Object.keys(creatorFeed).length;

  if (activeCanonicalCount > 0 && totalNewFeedsCount === 0) {
    throw new Error(
      'ABORT: New feeds are empty while active canonical requests exist! You must run `--phase=backfill --apply` and verify client migration before executing cleanup.'
    );
  }
  console.log(`Verification passed: ${totalNewFeedsCount} new feed entries detected.`);

  console.log('Reading legacy mirror nodes for deletion...');
  const [legacyPubSnap, legacyCancSnap, usersSnap] = await Promise.all([
    db.ref('BandEvents/PublishedSubRequests').once('value'),
    db.ref('BandEvents/CancelledSubRequests').once('value'),
    db.ref('users').once('value'),
  ]);

  const legacyPubData = legacyPubSnap.val() || {};
  const legacyCancData = legacyCancSnap.val() || {};
  const usersData = usersSnap.val() || {};

  const manifest = {
    timestamp: new Date().toISOString(),
    records: {
      'BandEvents/PublishedSubRequests': legacyPubData,
      'BandEvents/CancelledSubRequests': legacyCancData,
      usersSubRequests: {},
      usersCancelledSubRequests: {},
    },
  };

  const updates = {};
  let legacyRemovalsCount = 0;

  Object.keys(legacyPubData).forEach((k) => {
    updates[`BandEvents/PublishedSubRequests/${k}`] = null;
    legacyRemovalsCount++;
  });
  Object.keys(legacyCancData).forEach((k) => {
    updates[`BandEvents/CancelledSubRequests/${k}`] = null;
    legacyRemovalsCount++;
  });

  Object.keys(usersData).forEach((uid) => {
    const userSubRequests = usersData[uid]?.SubRequests || {};
    if (Object.keys(userSubRequests).length > 0) {
      manifest.records.usersSubRequests[uid] = userSubRequests;
      Object.keys(userSubRequests).forEach((k) => {
        updates[`users/${uid}/SubRequests/${k}`] = null;
        legacyRemovalsCount++;
      });
    }

    const userCancelled = usersData[uid]?.CancelledSubRequests || {};
    if (Object.keys(userCancelled).length > 0) {
      manifest.records.usersCancelledSubRequests[uid] = userCancelled;
      Object.keys(userCancelled).forEach((k) => {
        updates[`users/${uid}/CancelledSubRequests/${k}`] = null;
        legacyRemovalsCount++;
      });
    }
  });

  console.log('\n--- CLEANUP METRICS ---');
  console.table({
    'Published SubRequests Mirrors': Object.keys(legacyPubData).length,
    'Cancelled SubRequests Mirrors': Object.keys(legacyCancData).length,
    'User Node SubRequests': Object.keys(manifest.records.usersSubRequests).length,
    'User Node Cancelled': Object.keys(manifest.records.usersCancelledSubRequests).length,
    'Total Legacy Removals (null operations)': legacyRemovalsCount,
  });

  if (isApply) {
    if (legacyRemovalsCount > 0) {
      // Save backup manifest file locally before deleting
      const manifestPath = path.join(__dirname, `../cleanup_manifest_${Date.now()}.json`);
      fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8');
      console.log(`Backup manifest successfully written to: ${manifestPath}`);

      console.log('Executing atomic deletion of legacy mirrors...');
      await db.ref().update(updates);
      console.log('Legacy cleanup successfully executed!');
    } else {
      console.log('Zero legacy records to clean up.');
    }
  } else {
    console.log('\nDRY-RUN COMPLETE: No legacy data was deleted.');
    console.log('To apply cleanup, run with `--phase=cleanup --apply --confirm-legacy-delete`.');
  }

  return { legacyRemovalsCount };
}

if (require.main === module) {
  runMigration()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\nScript failed:', err.message);
      process.exit(1);
    });
}

module.exports = { runMigration, runBackfill, runCleanup };
