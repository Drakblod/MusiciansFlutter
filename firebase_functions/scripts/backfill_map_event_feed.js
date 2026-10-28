/**
 * Admin Tool: Event Map Feed Backfill & Projection Tool
 * MAP-VIEW-FEED-02
 *
 * Scans canonical Event sources:
 * - /Bands/{bandId}/Events/{eventId}
 * - /PublicEvents/{eventId}
 *
 * Produces sanitized server-owned projections for:
 * - /publicMapEventFeed/{mapItemId}
 * - /userMapEventFeed/{userId}/{mapItemId}
 * - /mapEventProjectionIndex/{sourceKey}
 *
 * SAFETY INVARIANTS:
 * - Default mode is strictly DRY-RUN (0 database writes).
 * - Writing requires explicit `--apply` flag.
 * - Refuses execution on production without `--allow-production` AND `--confirm-production`.
 * - Zero external geocoding calls (free-text only remains unresolved).
 * - Never prints sensitive member lists, RSVP data, tokens, phone, email, or raw payloads.
 * - Apply mode is idempotent.
 * - Reports stale projections without silent deletion.
 */

const admin = require('firebase-admin');
const {
  isValidCoordinate,
  buildEventProjections,
  getAuthorizedUserIdsForBandEvent,
  buildProjectionIndexKey,
} = require('../event_projection');

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
 * Pure calculation function for backfill projections.
 * Takes in-memory datasets and computes proposed writes and audit summary.
 */
function calculateBackfillPlan({
  publicEvents = {},
  bands = {},
  existingPublicProjections = {},
  now = new Date(),
}) {
  const summary = {
    canonicalEventsScanned: 0,
    publicEventsScanned: 0,
    bandEventsScanned: 0,
    proposedProjections: 0,
    resolvedWithCoordinates: 0,
    unresolvedMissingCoordinates: 0,
    pastEventsSkipped: 0,
    cancelledOrDraftSkipped: 0,
    staleProjectionsReported: 0,
    databaseWritesExecuted: 0,
    reports: [],
  };

  const proposedWrites = {};

  // 1. Process Public Calendar Events
  for (const [eventId, eventData] of Object.entries(publicEvents)) {
    if (!eventData || typeof eventData !== 'object') continue;
    summary.publicEventsScanned++;
    summary.canonicalEventsScanned++;

    const sourcePath = `PublicEvents/${eventId}`;
    const status = String(eventData.status || '').toLowerCase().trim();

    if (status !== 'published') {
      summary.cancelledOrDraftSkipped++;
      summary.reports.push({
        sourcePath,
        eventId,
        schedulePartId: null,
        visibility: 'public',
        coordinateStatus: 'SKIPPED',
        targetCategory: 'publicMapEventFeed',
        unresolvedReason: `Non-published status (${status || 'draft'})`,
      });
      continue;
    }

    const projections = buildEventProjections(
      'public_calendar',
      eventData,
      eventId,
      null,
      eventData.organizerName || '',
      now
    );

    if (projections.length === 0) {
      const lat = eventData.latitude ?? eventData.Latitude;
      const lng = eventData.longitude ?? eventData.Longitude;
      const hasCoords = isValidCoordinate(lat, lng);
      const reason = !hasCoords ? 'MISSING_COORDINATES' : 'PAST_EVENT';

      if (!hasCoords) summary.unresolvedMissingCoordinates++;
      else summary.pastEventsSkipped++;

      summary.reports.push({
        sourcePath,
        eventId,
        schedulePartId: null,
        visibility: 'public',
        coordinateStatus: hasCoords ? 'EXACT' : 'NONE',
        targetCategory: 'publicMapEventFeed',
        unresolvedReason: reason,
      });
      continue;
    }

    const mapItemIdsObj = {};
    projections.forEach((p) => {
      summary.proposedProjections++;
      summary.resolvedWithCoordinates++;
      summary.reports.push({
        sourcePath,
        eventId,
        schedulePartId: p.schedulePartId,
        visibility: 'public',
        coordinateStatus: 'VALID_CONFIRMED',
        targetCategory: 'publicMapEventFeed',
        unresolvedReason: null,
      });
      proposedWrites[`publicMapEventFeed/${p.mapItemId}`] = p;
      mapItemIdsObj[p.mapItemId] = true;
    });

    // Also populate server-only projection index
    const sourceKey = buildProjectionIndexKey('public_calendar', null, eventId);
    proposedWrites[`mapEventProjectionIndex/${sourceKey}`] = {
      sourceType: 'public_calendar',
      bandId: null,
      eventId: String(eventId),
      mapItemIds: mapItemIdsObj,
      authorizedUids: { public: true },
      updatedAt: now.getTime(),
    };
  }

  // 2. Process Private Band Events
  for (const [bandId, bandNode] of Object.entries(bands)) {
    if (!bandNode || typeof bandNode !== 'object') continue;
    const bandName = String(bandNode.Name || bandNode.name || 'Band').trim();
    const eventsNode = bandNode.Events || bandNode.events;
    if (!eventsNode || typeof eventsNode !== 'object') continue;

    const bandData = { Members_band: bandNode.Members_band || {} };

    for (const [eventId, eventData] of Object.entries(eventsNode)) {
      if (!eventData || typeof eventData !== 'object') continue;
      summary.bandEventsScanned++;
      summary.canonicalEventsScanned++;

      const sourcePath = `Bands/${bandId}/Events/${eventId}`;
      const authorizedUids = getAuthorizedUserIdsForBandEvent(bandData, eventData);

      const projections = buildEventProjections(
        'private_band',
        eventData,
        eventId,
        bandId,
        bandName,
        now
      );

      if (projections.length === 0) {
        const lat = eventData.latitude ?? eventData.Latitude;
        const lng = eventData.longitude ?? eventData.Longitude;
        const hasCoords = isValidCoordinate(lat, lng);
        const reason = !hasCoords ? 'MISSING_COORDINATES' : 'PAST_EVENT';

        if (!hasCoords) summary.unresolvedMissingCoordinates++;
        else summary.pastEventsSkipped++;

        summary.reports.push({
          sourcePath,
          eventId,
          schedulePartId: null,
          visibility: 'private',
          coordinateStatus: hasCoords ? 'EXACT' : 'NONE',
          targetCategory: 'userMapEventFeed',
          unresolvedReason: reason,
        });
        continue;
      }

      const mapItemIdsObj = {};
      const authUidsObj = {};
      authorizedUids.forEach((uid) => {
        authUidsObj[uid] = true;
      });

      projections.forEach((p) => {
        summary.proposedProjections++;
        summary.resolvedWithCoordinates++;
        summary.reports.push({
          sourcePath,
          eventId,
          schedulePartId: p.schedulePartId,
          visibility: 'private',
          coordinateStatus: 'VALID_CONFIRMED',
          targetCategory: 'userMapEventFeed',
          unresolvedReason: null,
        });

        mapItemIdsObj[p.mapItemId] = true;

        // Write to each authorized user's feed
        authorizedUids.forEach((uid) => {
          proposedWrites[`userMapEventFeed/${uid}/${p.mapItemId}`] = p;
        });
      });

      // Populate server-only projection index
      const sourceKey = buildProjectionIndexKey('private_band', bandId, eventId);
      proposedWrites[`mapEventProjectionIndex/${sourceKey}`] = {
        sourceType: 'private_band',
        bandId: String(bandId),
        eventId: String(eventId),
        mapItemIds: mapItemIdsObj,
        authorizedUids: authUidsObj,
        updatedAt: now.getTime(),
      };
    }
  }

  // 3. Stale projections audit
  for (const mapItemId of Object.keys(existingPublicProjections)) {
    if (!proposedWrites[`publicMapEventFeed/${mapItemId}`]) {
      summary.staleProjectionsReported++;
    }
  }

  return { summary, proposedWrites };
}

async function runBackfill() {
  if (!isEmulator) {
    if (!allowProduction) {
      console.error('FATAL SAFETY BLOCK: Running against production requires --allow-production.');
      process.exit(1);
    }
    if (isApplyMode && !confirmProduction) {
      console.error('FATAL SAFETY BLOCK: Applying writes to production requires --confirm-production.');
      process.exit(1);
    }
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: projectId,
      databaseURL: databaseUrl,
    });
  }

  const db = admin.database();

  console.log('='.repeat(70));
  console.log(`EVENT MAP FEED BACKFILL [${isApplyMode ? 'APPLY MODE' : 'DRY-RUN'}]`);
  console.log('='.repeat(70));

  let publicEvents = {};
  let bands = {};
  let existingPublicProjections = {};

  try {
    const pubSnap = await db.ref('PublicEvents').once('value');
    if (pubSnap.exists()) publicEvents = pubSnap.val() || {};
  } catch (e) {
    console.error(`Error reading PublicEvents: ${e.message}`);
  }

  try {
    const bandsSnap = await db.ref('Bands').once('value');
    if (bandsSnap.exists()) bands = bandsSnap.val() || {};
  } catch (e) {
    console.error(`Error reading Bands: ${e.message}`);
  }

  try {
    const feedSnap = await db.ref('publicMapEventFeed').once('value');
    if (feedSnap.exists()) existingPublicProjections = feedSnap.val() || {};
  } catch (e) {
    console.error(`Notice reading publicMapEventFeed: ${e.message}`);
  }

  const { summary, proposedWrites } = calculateBackfillPlan({
    publicEvents,
    bands,
    existingPublicProjections,
  });

  // Print Summary Report (NEVER logs sensitive fields)
  console.log('\n' + '='.repeat(70));
  console.log('BACKFILL AUDIT SUMMARY REPORT');
  console.log('='.repeat(70));
  console.log(`Canonical Events Scanned:          ${summary.canonicalEventsScanned}`);
  console.log(`  - Public Events:                 ${summary.publicEventsScanned}`);
  console.log(`  - Band Events:                   ${summary.bandEventsScanned}`);
  console.log(`Proposed Map Projections:         ${summary.proposedProjections}`);
  console.log(`Resolved With Coordinates:         ${summary.resolvedWithCoordinates}`);
  console.log(`Unresolved (Missing Coords):       ${summary.unresolvedMissingCoordinates}`);
  console.log(`Skipped (Past Events):             ${summary.pastEventsSkipped}`);
  console.log(`Skipped (Draft/Cancelled):         ${summary.cancelledOrDraftSkipped}`);
  console.log(`Stale Projections Reported:        ${summary.staleProjectionsReported}`);
  console.log(`Planned Database Write Paths:      ${Object.keys(proposedWrites).length}`);
  console.log('='.repeat(70));

  if (!isApplyMode) {
    console.log('\n[DRY-RUN] Finished safely with 0 database writes.');
    console.log('To apply the backfill writes to the database, run with --apply.');
    return summary;
  }

  console.log('\n[APPLY MODE] Applying updates idempotently...');
  if (Object.keys(proposedWrites).length > 0) {
    await db.ref().update(proposedWrites);
    summary.databaseWritesExecuted = Object.keys(proposedWrites).length;
    console.log(`Successfully applied ${summary.databaseWritesExecuted} database writes.`);
  } else {
    console.log('No writes required.');
  }

  return summary;
}

if (require.main === module) {
  runBackfill()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Fatal backfill error:', err);
      process.exit(1);
    });
}

module.exports = {
  calculateBackfillPlan,
  runBackfill,
};
