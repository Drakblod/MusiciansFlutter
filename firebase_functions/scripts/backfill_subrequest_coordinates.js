/**
 * Admin Tool: SubRequest Coordinate Backfill & Resolution Audit
 *
 * Scans canonical /SubRequests for missing or invalid coordinates and proposes
 * canonical location coordinates derived from connected Events or venue/city geocoding.
 *
 * SAFETY INVARIANTS:
 * - Default mode is strictly DRY-RUN (0 database writes).
 * - Writing requires explicit `--apply` flag.
 * - Production execution requires `--allow-production` AND `--confirm-production`.
 * - Ambiguous addresses remain UNRESOLVED for manual human review (never invents coords).
 * - Never prints sensitive candidate lists, tokens, phone numbers, or PII.
 */

const admin = require('firebase-admin');
const { isNewMemberRequest, extractCityLabel } = require('../index');

// Curated lookup table of canonical Swedish music venues and cities for deterministic offline resolution
const CANONICAL_KNOWN_LOCATIONS = {
  'fasching': { lat: 59.3340, lng: 18.0560, precision: 'exact', label: 'Fasching, Kungsgatan 63, Stockholm' },
  'stampen': { lat: 59.3242, lng: 18.0688, precision: 'exact', label: 'Stampen, Stora Nygatan 5, Stockholm' },
  'nefertiti': { lat: 57.6970, lng: 11.9510, precision: 'exact', label: 'Nefertiti, Gothenburg' },
  'mejeriet': { lat: 55.6983, lng: 13.1932, precision: 'exact', label: 'Kulturmejeriet, Lund' },
  'kb': { lat: 55.6012, lng: 13.0010, precision: 'exact', label: 'Kulturbolaget, Malmö' },
  'stockholm': { lat: 59.3293, lng: 18.0686, precision: 'city', label: 'Stockholm, Sweden' },
  'gothenburg': { lat: 57.7089, lng: 11.9746, precision: 'city', label: 'Gothenburg, Sweden' },
  'göteborg': { lat: 57.7089, lng: 11.9746, precision: 'city', label: 'Göteborg, Sweden' },
  'malmö': { lat: 55.6050, lng: 13.0038, precision: 'city', label: 'Malmö, Sweden' },
  'uppsala': { lat: 59.8586, lng: 17.6389, precision: 'city', label: 'Uppsala, Sweden' },
  'umeå': { lat: 63.8258, lng: 20.2630, precision: 'city', label: 'Umeå, Sweden' },
  'lund': { lat: 55.7047, lng: 13.1910, precision: 'city', label: 'Lund, Sweden' },
};

function isValidCoordinate(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) return false;
  const nLat = Number(lat);
  const nLng = Number(lng);
  if (!Number.isFinite(nLat) || !Number.isFinite(nLng)) return false;
  if (nLat < -90 || nLat > 90 || nLng < -180 || nLng > 180) return false;
  if (nLat === 0 && nLng === 0) return false; // reject Null Island
  return true;
}

function resolveLocationText(text, requestType) {
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    return { resolved: false, reason: 'MISSING_LOCATION_TEXT' };
  }

  const clean = text.trim().toLowerCase();
  const isNewMember = (requestType || '').toLowerCase().includes('new member');

  for (const [key, data] of Object.entries(CANONICAL_KNOWN_LOCATIONS)) {
    if (clean.includes(key)) {
      // New member requests always enforce city precision
      const precision = isNewMember ? 'city' : data.precision;
      return {
        resolved: true,
        lat: data.lat,
        lng: data.lng,
        precision: precision,
        matchedLabel: data.label,
      };
    }
  }

  return { resolved: false, reason: 'AMBIGUOUS_OR_UNKNOWN_ADDRESS' };
}

async function runBackfillCoordinates(options = {}) {
  const args = process.argv.slice(2);
  const isApply = (options.apply !== undefined ? options.apply : (options.isApply !== undefined ? options.isApply : args.includes('--apply')));
  const allowProd = options.allowProduction !== undefined ? options.allowProduction : args.includes('--allow-production');
  const confirmProd = options.confirmProduction !== undefined ? options.confirmProduction : args.includes('--confirm-production');

  const projectArg = args.find((a) => a.startsWith('--project='));
  const urlArg = args.find((a) => a.startsWith('--database-url='));

  let projectId = options.projectId || (projectArg ? projectArg.split('=')[1] : (process.env.GCLOUD_PROJECT || 'demo-musicians-test'));
  let databaseUrl = options.databaseUrl || (urlArg ? urlArg.split('=')[1] : (process.env.FIREBASE_DATABASE_URL || 'http://127.0.0.1:9000?ns=' + projectId));

  const isEmulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST) ||
    databaseUrl.includes('127.0.0.1') ||
    databaseUrl.includes('localhost') ||
    projectId === 'demo-musicians-test';

  console.log('=== SUBREQUEST COORDINATE BACKFILL AUDIT ===');
  console.log('Target Project: ', projectId);
  console.log('Target DB URL:  ', databaseUrl);
  console.log('Execution Mode: ', isEmulator ? 'EMULATOR / TEST' : 'PRODUCTION');
  console.log('Mode:           ', isApply ? 'APPLY (Database Writes Enabled)' : 'DRY-RUN (Zero Writes Guarantee)\n');

  if (!isEmulator) {
    if (!allowProd) {
      throw new Error('Running against production requires `--allow-production`.');
    }
    if (isApply && !confirmProd) {
      throw new Error('Applying writes to production requires `--confirm-production`.');
    }
  }

  let db = options.db;
  if (!db) {
    if (!admin.apps.length) {
      admin.initializeApp({
        projectId: projectId,
        databaseURL: databaseUrl,
      });
    }
    db = admin.database();
  }

  console.log('Reading /SubRequests, /Bands, and legacy /BandEvents snapshots...');
  const [subSnap, bandsSnap, legacyEventsSnap] = await Promise.all([
    db.ref('SubRequests').once('value'),
    db.ref('Bands').once('value'),
    db.ref('BandEvents').once('value'),
  ]);

  const subRequests = subSnap.val() || {};
  const bands = bandsSnap.val() || {};
  const legacyBandEvents = legacyEventsSnap.val() || {};

  const auditReport = [];
  const updatesToApply = {};

  let totalScanned = 0;
  let alreadyValidCount = 0;
  let resolvedViaEventCount = 0;
  let resolvedViaGeocodeCount = 0;
  let unresolvedCount = 0;

  for (const [id, req] of Object.entries(subRequests)) {
    totalScanned++;
    const lat = req.Latitude ?? req.latitude ?? req.lat;
    const lng = req.Longitude ?? req.longitude ?? req.lng;
    const reqType = req.RequestType || req.requestType || req.Role || req.role || 'Substitute';
    const locText = (req.Location || req.location || req.Venue || req.venue || '').toString().trim();

    if (isValidCoordinate(lat, lng)) {
      alreadyValidCount++;
      continue;
    }

    const isNewMember = isNewMemberRequest(req);
    let eventCoordsAvailable = false;
    let proposedLat = null;
    let proposedLng = null;
    let proposedPrecision = isNewMember ? 'city' : 'exact';
    let resolutionReason = 'RESOLVED';
    let isResolved = false;

    // 1. Check if connected to an Event with existing coordinates
    const bandId = req.BandId || req.bandId;
    const eventId = req.EventId || req.eventId;

    let eventData = null;
    // Canonical RTDB path: /Bands/{bandId}/Events/{eventId}
    if (bandId && eventId && bands[bandId] && bands[bandId].Events && bands[bandId].Events[eventId]) {
      eventData = bands[bandId].Events[eventId];
    } else if (bandId && eventId && legacyBandEvents[bandId] && legacyBandEvents[bandId][eventId]) {
      // Verified legacy path: /BandEvents/{bandId}/{eventId}
      eventData = legacyBandEvents[bandId][eventId];
    }

    if (eventData) {
      const evLat = eventData.Latitude ?? eventData.latitude;
      const evLng = eventData.Longitude ?? eventData.longitude;
      if (isValidCoordinate(evLat, evLng)) {
        eventCoordsAvailable = true;
        isResolved = true;
        proposedLat = Number(evLat);
        proposedLng = Number(evLng);
        if (isNewMember) {
          // Coarsen coordinates to 1 decimal place (~11 km lat uncertainty) for residential privacy
          proposedLat = Number(proposedLat.toFixed(1));
          proposedLng = Number(proposedLng.toFixed(1));
        }
        resolutionReason = 'EVENT_COORDINATES_INHERITED';
        resolvedViaEventCount++;
      }
    }

    // 2. Free-text records without canonical event coordinates must remain unresolved for manual review
    if (!isResolved) {
      resolutionReason = 'UNRESOLVED_REQUIRES_MANUAL_REVIEW';
      unresolvedCount++;
    }

    auditReport.push({
      requestId: id,
      locationLabel: locText.length > 0 ? locText.substring(0, 30) : '<EMPTY>',
      requestType: reqType,
      eventCoordsAvailable: eventCoordsAvailable ? 'YES' : 'NO',
      resolved: isResolved ? 'YES' : 'NO',
      reason: resolutionReason,
      proposedLat: proposedLat !== null ? proposedLat.toFixed(4) : '-',
      proposedLng: proposedLng !== null ? proposedLng.toFixed(4) : '-',
      precision: isResolved ? proposedPrecision : '-',
    });

    if (isResolved && isApply) {
      updatesToApply[`SubRequests/${id}/Latitude`] = proposedLat;
      updatesToApply[`SubRequests/${id}/Longitude`] = proposedLng;
      updatesToApply[`SubRequests/${id}/LocationPrecision`] = proposedPrecision;
      updatesToApply[`SubRequests/${id}/LocationStatus`] = 'resolved';

      // Propagate to public feed if present
      updatesToApply[`publicSubRequests/${id}/latitude`] = proposedLat;
      updatesToApply[`publicSubRequests/${id}/longitude`] = proposedLng;
    }
  }

  console.log('\n--- COORDINATE BACKFILL AUDIT SUMMARY ---');
  console.table({
    'Total Scanned SubRequests': totalScanned,
    'Already Has Valid Coordinates': alreadyValidCount,
    'Resolved via Event Coordinates': resolvedViaEventCount,
    'Resolved via Venue/City Matching': resolvedViaGeocodeCount,
    'Unresolved (Retained without coords)': unresolvedCount,
  });

  if (auditReport.length > 0) {
    console.log('\nAudit Sample (up to 20 items):');
    console.table(auditReport.slice(0, 20));
  }

  if (isApply) {
    const updateKeys = Object.keys(updatesToApply);
    if (updateKeys.length > 0) {
      console.log(`\n[APPLY] Applying ${updateKeys.length} field updates to canonical records...`);
      await db.ref().update(updatesToApply);
      console.log('[SUCCESS] Coordinates backfilled successfully.');
    } else {
      console.log('\n[APPLY] Zero records required coordinate updates.');
    }
  } else {
    console.log('\n[DRY-RUN] Completed. Zero database writes were executed.');
  }

  return {
    totalScanned,
    alreadyValidCount,
    resolvedViaEventCount,
    resolvedViaGeocodeCount,
    unresolvedCount,
    auditReport,
    writesPerformed: isApply ? Object.keys(updatesToApply).length : 0,
  };
}

if (require.main === module) {
  runBackfillCoordinates()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('\nFATAL ERROR:', err.message);
      process.exit(1);
    });
}

module.exports = { runBackfillCoordinates, isValidCoordinate, resolveLocationText };
