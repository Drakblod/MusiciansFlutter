/**
 * Admin Tool: Public Map Pin Feed Backfill & Projection Tool
 * MAP-VIEW-FEED-03B
 *
 * Scans canonical SubRequests records:
 * - /SubRequests/{subRequestId}
 *
 * Filters strictly to NotificationMode: 'map_pin'.
 * Never copies staffing records or private recipient data.
 * Produces sanitized server-owned projections for:
 * - /publicMapPinFeed/{pinId}
 *
 * SAFETY INVARIANTS:
 * - Default mode is strictly DRY-RUN (0 database writes).
 * - Writing requires explicit `--apply` flag.
 * - Refuses execution on production without `--allow-production` AND `--confirm-production`.
 * - Zero external geocoding calls.
 * - Never includes private target data, responses, assignment, email, phone or tokens.
 * - Repeated application is idempotent.
 * - Reports stale projections without silent corruption.
 */

const admin = require('firebase-admin');
const { sanitizeMapPinProjection } = require('../index');

const args = process.argv.slice(2);
const isApplyMode = args.includes('--apply');
const allowProduction = args.includes('--allow-production');
const confirmProduction = args.includes('--confirm-production');
const isVerbose = args.includes('--verbose');

const projectArg = args.find((a) => a.startsWith('--project='));
const urlArg = args.find((a) => a.startsWith('--database-url='));

const projectId = projectArg ? projectArg.split('=')[1] : (process.env.GCLOUD_PROJECT || 'demo-musicians-test');
const databaseUrl = urlArg ? urlArg.split('=')[1] : (process.env.FIREBASE_DATABASE_URL || `http://127.0.0.1:9000?ns=${projectId}`);

const isEmulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST) ||
  databaseUrl.includes('127.0.0.1') ||
  databaseUrl.includes('localhost') ||
  projectId === 'demo-musicians-test';

/**
 * Pure calculation function for Map Pin backfill projections.
 * Takes in-memory datasets and computes proposed writes and audit summary.
 */
function calculateMapPinBackfillPlan({
  subRequests = {},
  existingProjections = {},
}) {
  const summary = {
    canonicalScanned: 0,
    staffingSkipped: 0,
    mapPinsFound: 0,
    proposedCreations: 0,
    proposedUpdates: 0,
    proposedDeletions: 0,
    unchanged: 0,
    invalidCoordinatesSkipped: 0,
    cancelledOrDeletedSkipped: 0,
    databaseWritesExecuted: 0,
    reports: [],
  };

  const proposedWrites = {};
  const activePinIds = new Set();

  for (const [key, raw] of Object.entries(subRequests)) {
    if (!raw || typeof raw !== 'object') continue;
    summary.canonicalScanned++;

    const notifMode = raw.NotificationMode || raw.notificationMode ||
      (raw.extraFields && (raw.extraFields.NotificationMode || raw.extraFields.notificationMode));

    if (notifMode !== 'map_pin') {
      summary.staffingSkipped++;
      continue;
    }

    summary.mapPinsFound++;
    const pinId = key;

    const status = String(raw.Status || raw.status || '').toLowerCase().trim();
    if (status === 'cancelled' || status === 'deleted' || status === 'closed') {
      summary.cancelledOrDeletedSkipped++;
      summary.reports.push({
        pinId,
        status: 'SKIPPED_STATUS',
        reason: `Status is ${status}`,
      });
      continue;
    }

    const projection = sanitizeMapPinProjection({ ...raw, id: pinId, subRequestId: pinId });
    if (!projection) {
      summary.invalidCoordinatesSkipped++;
      summary.reports.push({
        pinId,
        status: 'SKIPPED_COORDINATES',
        reason: 'Missing or invalid coordinates',
      });
      continue;
    }

    activePinIds.add(pinId);
    const existing = existingProjections[pinId];

    if (!existing) {
      summary.proposedCreations++;
      proposedWrites[`publicMapPinFeed/${pinId}`] = projection;
      summary.reports.push({
        pinId,
        status: 'CREATE',
      });
    } else {
      const isDifferent = JSON.stringify(projection) !== JSON.stringify(existing);
      if (isDifferent) {
        summary.proposedUpdates++;
        proposedWrites[`publicMapPinFeed/${pinId}`] = projection;
        summary.reports.push({
          pinId,
          status: 'UPDATE',
        });
      } else {
        summary.unchanged++;
      }
    }
  }

  // Check for stale projections that should be removed
  for (const [projId, projData] of Object.entries(existingProjections)) {
    if (!projData) continue;
    if (!activePinIds.has(projId)) {
      summary.proposedDeletions++;
      proposedWrites[`publicMapPinFeed/${projId}`] = null;
      summary.reports.push({
        pinId: projId,
        status: 'STALE_DELETE',
      });
    }
  }

  return { summary, proposedWrites };
}

async function runCli() {
  console.log('=== MAP PIN BACKFILL & PROJECTION TOOL ===');
  console.log(`Target Project: ${projectId}`);
  console.log(`Database URL: ${databaseUrl}`);
  console.log(`Mode: ${isApplyMode ? 'APPLY (LIVE WRITES)' : 'DRY-RUN (NO WRITES)'}`);
  console.log(`Environment: ${isEmulator ? 'EMULATOR' : 'PRODUCTION'}`);

  if (!isEmulator) {
    if (!allowProduction || !confirmProduction) {
      console.error('\n[FATAL SAFETY BLOCK] Execution against production refused without --allow-production AND --confirm-production.');
      process.exit(1);
    }
    if (isApplyMode && (!confirmProduction || !allowProduction)) {
      console.error('\n[FATAL SAFETY BLOCK] Applying writes to production requires explicit --allow-production AND --confirm-production.');
      process.exit(1);
    }
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      projectId,
      databaseURL: databaseUrl,
    });
  }

  const db = admin.database();

  console.log('\n[1/3] Reading canonical SubRequests...');
  const subSnap = await db.ref('SubRequests').once('value');
  const subRequests = subSnap.val() || {};

  console.log('[2/3] Reading existing publicMapPinFeed projections...');
  const projSnap = await db.ref('publicMapPinFeed').once('value');
  const existingProjections = projSnap.val() || {};

  console.log('[3/3] Calculating backfill plan...');
  const { summary, proposedWrites } = calculateMapPinBackfillPlan({
    subRequests,
    existingProjections,
  });

  console.log('\n=== AUDIT SUMMARY ===');
  console.log(`Canonical records scanned:          ${summary.canonicalScanned}`);
  console.log(`Staffing records ignored:           ${summary.staffingSkipped}`);
  console.log(`Music promotion pins found:         ${summary.mapPinsFound}`);
  console.log(`Proposed new projections:           ${summary.proposedCreations}`);
  console.log(`Proposed updated projections:       ${summary.proposedUpdates}`);
  console.log(`Proposed stale deletions:           ${summary.proposedDeletions}`);
  console.log(`Unchanged projections:              ${summary.unchanged}`);
  console.log(`Skipped (cancelled/deleted):        ${summary.cancelledOrDeletedSkipped}`);
  console.log(`Skipped (invalid coordinates):      ${summary.invalidCoordinatesSkipped}`);

  if (isVerbose && summary.reports.length > 0) {
    console.log('\n=== ITEM DETAILS ===');
    for (const r of summary.reports) {
      console.log(`- Pin ${r.pinId}: ${r.status}${r.reason ? ` (${r.reason})` : ''}`);
    }
  }

  const writeKeys = Object.keys(proposedWrites);
  if (writeKeys.length === 0) {
    console.log('\nNo changes needed. Projections are fully synchronized.');
    process.exit(0);
  }

  if (!isApplyMode) {
    console.log(`\nDRY-RUN COMPLETE: ${writeKeys.length} proposed writes calculated. ZERO writes executed.`);
    console.log('To apply changes, rerun with --apply.');
    process.exit(0);
  }

  console.log(`\nExecuting ${writeKeys.length} database updates...`);
  await db.ref().update(proposedWrites);
  summary.databaseWritesExecuted = writeKeys.length;
  console.log(`APPLY COMPLETE: ${summary.databaseWritesExecuted} database writes executed successfully.`);
  process.exit(0);
}

if (require.main === module) {
  runCli().catch((err) => {
    console.error('Fatal execution error:', err);
    process.exit(1);
  });
}

module.exports = {
  calculateMapPinBackfillPlan,
};
