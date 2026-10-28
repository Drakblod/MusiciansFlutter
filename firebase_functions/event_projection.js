/**
 * MAP-VIEW-FEED-02: Centralized Event-to-Map Projection Builder.
 * Shared by Cloud Function triggers, backfill scripts, and tests.
 */

/**
 * Validates coordinate pair.
 * Stockholm fallback, 0/0, null, or out-of-bounds coordinates return false.
 */
function isValidCoordinate(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) {
    return false;
  }
  const nLat = Number(lat);
  const nLng = Number(lng);
  if (isNaN(nLat) || isNaN(nLng)) return false;
  if (nLat < -90 || nLat > 90 || nLng < -180 || nLng > 180) return false;
  if (nLat === 0 && nLng === 0) return false;
  return true;
}

/**
 * Deterministic Map Item ID generator.
 */
function buildMapItemId(source, bandId, eventId, schedulePartId) {
  if (source === 'public_calendar') {
    return `event:public:${eventId}`;
  }
  if (schedulePartId) {
    return `event:private:${bandId}:${eventId}:${schedulePartId}`;
  }
  return `event:private:${bandId}:${eventId}`;
}

/**
 * Sanitizes description text: strips unsafe HTML tags, excessive whitespace,
 * and caps maximum length.
 */
function sanitizeDescription(raw) {
  if (!raw || typeof raw !== 'string') return '';
  return raw
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 1000);
}

/**
 * Parses end or start Date from ISO strings or date/time strings.
 */
function parseDateTimeComponents(dateStr, timeStr) {
  if (!dateStr) return null;
  const trimmedDate = String(dateStr).trim();
  if (trimmedDate.includes('T')) {
    const d = new Date(trimmedDate);
    if (!isNaN(d.getTime())) return d;
  }
  if (timeStr) {
    const trimmedTime = String(timeStr).trim();
    const d = new Date(`${trimmedDate}T${trimmedTime}`);
    if (!isNaN(d.getTime())) return d;
  }
  const d = new Date(trimmedDate);
  if (!isNaN(d.getTime())) return d;
  return null;
}

/**
 * Evaluates whether an event is in the past.
 * Strict rule:
 * - If endDateTime is available: past if endDateTime <= now.
 * - If only startDateTime is available: past if startDateTime < now.
 * - Does NOT invent an arbitrary event duration.
 */
function isEventPast(eventOrPart, now = new Date()) {
  const end = eventOrPart.endDateTime
    ? new Date(eventOrPart.endDateTime)
    : parseDateTimeComponents(eventOrPart.date, eventOrPart.endTime);

  if (end && !isNaN(end.getTime())) {
    return end.getTime() <= now.getTime();
  }

  const start = eventOrPart.startDateTime
    ? new Date(eventOrPart.startDateTime)
    : parseDateTimeComponents(eventOrPart.date, eventOrPart.startTime);

  if (start && !isNaN(start.getTime())) {
    return start.getTime() <= now.getTime();
  }

  return false;
}

/**
 * Extracts authorized user IDs for a Band Event.
 * Includes:
 * - Band members from Members_band (excluding excludedMemberIds)
 * - External invitees
 * - Confirmed substitute assignments
 * - Event creator
 */
function getAuthorizedUserIdsForBandEvent(bandData, eventData) {
  const authorized = new Set();

  const excluded = new Set();
  const rawExcluded = eventData.excludedMemberIds || eventData.ExcludedMemberIds;
  if (Array.isArray(rawExcluded)) {
    rawExcluded.forEach((uid) => {
      if (uid) excluded.add(String(uid).trim());
    });
  } else if (rawExcluded && typeof rawExcluded === 'object') {
    Object.entries(rawExcluded).forEach(([k, v]) => {
      if (v === true || v === 1 || v === 'true') {
        excluded.add(String(k).trim());
      }
    });
  }

  // 1. Band members
  if (bandData && bandData.Members_band && typeof bandData.Members_band === 'object') {
    Object.keys(bandData.Members_band).forEach((memberUid) => {
      const trimmedUid = String(memberUid).trim();
      if (trimmedUid && !excluded.has(trimmedUid)) {
        authorized.add(trimmedUid);
      }
    });
  }

  // 2. Creator
  const creator = eventData.createdBy || eventData.CreatedBy;
  if (creator && typeof creator === 'string' && creator.trim().length > 0) {
    authorized.add(creator.trim());
  }

  // 3. External Invitees
  if (eventData.externalInvitees && typeof eventData.externalInvitees === 'object') {
    Object.entries(eventData.externalInvitees).forEach(([inviteeUid, inv]) => {
      const trimmedUid = String(inviteeUid).trim();
      const status = inv && typeof inv === 'object' ? String(inv.status || '').toLowerCase() : '';
      if (trimmedUid && status !== 'declined') {
        authorized.add(trimmedUid);
      }
    });
  }

  // 4. Confirmed substitute assignments
  if (eventData.substituteAssignments && typeof eventData.substituteAssignments === 'object') {
    Object.values(eventData.substituteAssignments).forEach((assign) => {
      if (!assign || typeof assign !== 'object') return;
      const uid = assign.assignedUserId ? String(assign.assignedUserId).trim() : '';
      const status = assign.status ? String(assign.status).trim().toLowerCase() : '';
      if (uid && (status === 'assigned' || status === 'filled')) {
        authorized.add(uid);
      }
    });
  }

  return Array.from(authorized);
}

/**
 * Normalizes schedule parts list from an event node.
 */
function extractScheduleParts(eventData) {
  const parts = [];
  const raw = eventData.rehearsals || eventData.Rehearsals;
  if (Array.isArray(raw)) {
    raw.forEach((p, index) => {
      if (p && typeof p === 'object') {
        parts.push({
          ...p,
          id: p.id ? String(p.id) : `part_${index}`,
        });
      }
    });
  } else if (raw && typeof raw === 'object') {
    Object.entries(raw).forEach(([k, v]) => {
      if (v && typeof v === 'object') {
        parts.push({
          ...v,
          id: v.id ? String(v.id) : String(k),
        });
      }
    });
  }
  return parts;
}

/**
 * Builds strict, sanitized projections for an Event.
 * Returns an array of projection objects (or empty array if event is ineligible/missing coords/past).
 *
 * @param {string} source - 'public_calendar' or 'private_band'
 * @param {object} eventData - canonical event node
 * @param {string} eventId - event ID
 * @param {string|null} bandId - band ID if private_band
 * @param {string|null} bandName - band or organizer name
 * @param {Date} [referenceNow] - optional reference date for tests
 */
function buildEventProjections(source, eventData, eventId, bandId = null, bandName = '', referenceNow = new Date()) {
  if (!eventData || !eventId) return [];

  // Check cancellation/draft status
  if (source === 'public_calendar') {
    const status = String(eventData.status || '').toLowerCase().trim();
    if (status !== 'published') {
      return [];
    }
  }

  const scheduleParts = extractScheduleParts(eventData);
  const now = referenceNow;

  // Multi-part Event handling
  if (scheduleParts.length > 0) {
    const projections = [];

    // Parent coordinates available for inheritance
    const parentLat = eventData.latitude ?? eventData.Latitude ?? null;
    const parentLng = eventData.longitude ?? eventData.Longitude ?? null;
    const parentHasCoords = isValidCoordinate(parentLat, parentLng);

    scheduleParts.forEach((part) => {
      // Check part past status
      if (isEventPast(part, now)) {
        return;
      }

      // Coordinate resolution:
      // 1. Part's own confirmed coordinates
      let partLat = part.latitude ?? part.Latitude ?? null;
      let partLng = part.longitude ?? part.Longitude ?? null;
      let precision = part.locationPrecision || 'exact';

      if (!isValidCoordinate(partLat, partLng)) {
        // 2. Inherit from parent event confirmed coordinates
        if (parentHasCoords) {
          partLat = parentLat;
          partLng = parentLng;
          precision = eventData.locationPrecision || eventData.LocationPrecision || 'exact';
        } else {
          // No coordinates -> omit (never Stockholm fallback)
          return;
        }
      }

      const mapItemId = buildMapItemId(source, bandId, eventId, part.id);
      const displayLocation = (part.location || eventData.location || '').toString().trim();
      const displayCity = (part.city || eventData.city || '').toString().trim();

      projections.push({
        mapItemId,
        eventId: String(eventId),
        schedulePartId: String(part.id),
        source,
        bandId: bandId ? String(bandId) : null,
        bandName: bandName || (source === 'public_calendar' ? (eventData.organizerName || '') : 'Band'),
        title: String(eventData.title || ''),
        schedulePartTitle: part.title ? String(part.title) : String(part.type || 'Schedule Part'),
        description: sanitizeDescription(part.description || eventData.description),
        eventType: String(part.type || eventData.eventType || 'Rehearsal'),
        date: String(part.date || eventData.startDateTime || ''),
        startTime: String(part.startTime || ''),
        endTime: String(part.endTime || ''),
        startDateTime: part.date && part.startTime ? `${part.date}T${part.startTime}` : (eventData.startDateTime || ''),
        endDateTime: part.date && part.endTime ? `${part.date}T${part.endTime}` : (eventData.endDateTime || ''),
        location: displayLocation,
        city: displayCity,
        latitude: Number(partLat),
        longitude: Number(partLng),
        locationPrecision: precision,
        visibility: source === 'public_calendar' ? 'public' : 'private',
        status: String(eventData.status || (eventData.isLocked ? 'locked' : 'scheduled')),
        creatorUserId: eventData.createdBy ? String(eventData.createdBy) : '',
        createdAt: Number(eventData.createdAt || (referenceNow ? referenceNow.getTime() : Date.now())),
        updatedAt: Number(eventData.updatedAt || (referenceNow ? referenceNow.getTime() : Date.now())),
      });
    });

    return projections;
  }

  // Single Event handling (no schedule parts)
  if (isEventPast(eventData, now)) {
    return [];
  }

  const lat = eventData.latitude ?? eventData.Latitude ?? null;
  const lng = eventData.longitude ?? eventData.Longitude ?? null;

  if (!isValidCoordinate(lat, lng)) {
    return [];
  }

  const mapItemId = buildMapItemId(source, bandId, eventId, null);
  const displayLocation = (eventData.location || eventData.venueName || eventData.address || '').toString().trim();
  const displayCity = (eventData.city || '').toString().trim();

  return [
    {
      mapItemId,
      eventId: String(eventId),
      schedulePartId: null,
      source,
      bandId: bandId ? String(bandId) : null,
      bandName: bandName || (source === 'public_calendar' ? (eventData.organizerName || '') : 'Band'),
      title: String(eventData.title || ''),
      schedulePartTitle: null,
      description: sanitizeDescription(eventData.description || eventData.shortDescription),
      eventType: String(eventData.eventType || 'Event'),
      date: String(eventData.startDateTime ? eventData.startDateTime.split('T')[0] : (eventData.date || '')),
      startTime: eventData.startTime ? String(eventData.startTime) : '',
      endTime: eventData.endTime ? String(eventData.endTime) : '',
      startDateTime: String(eventData.startDateTime || ''),
      endDateTime: String(eventData.endDateTime || ''),
      location: displayLocation,
      city: displayCity,
      latitude: Number(lat),
      longitude: Number(lng),
      locationPrecision: eventData.locationPrecision || eventData.LocationPrecision || 'exact',
      visibility: source === 'public_calendar' ? 'public' : 'private',
      status: String(eventData.status || (eventData.isLocked ? 'locked' : 'scheduled')),
      creatorUserId: eventData.createdBy ? String(eventData.createdBy) : '',
      createdAt: Number(eventData.createdAt || (referenceNow ? referenceNow.getTime() : Date.now())),
      updatedAt: Number(eventData.updatedAt || (referenceNow ? referenceNow.getTime() : Date.now())),
    },
  ];
}

/**
 * Deterministic Projection Index Key generator.
 */
function buildProjectionIndexKey(source, bandId, eventId) {
  if (source === 'public_calendar') {
    return `public:${eventId}`;
  }
  return `band:${bandId}:${eventId}`;
}

/**
 * Calculates atomic reconciliation updates between desired event projections
 * and previous projection index state.
 */
function calculateReconciliationDiff({
  source,
  eventId,
  bandId,
  bandName,
  bandData,
  eventData,
  prevIndex,
  now,
}) {
  const sourceKey = buildProjectionIndexKey(source, bandId, eventId);
  const prevMapItemIds = prevIndex && prevIndex.mapItemIds ? Object.keys(prevIndex.mapItemIds) : [];
  const prevAuthorizedUids = prevIndex && prevIndex.authorizedUids ? Object.keys(prevIndex.authorizedUids) : [];

  const isCancelled = eventData && (
    eventData.status === 'cancelled' ||
    eventData.status === 'canceled' ||
    eventData.status === 'deleted'
  );
  const isDraft = eventData && (
    eventData.isDraft === true ||
    eventData.status === 'draft' ||
    eventData.isPublished === false
  );

  let desiredProjections = [];
  let desiredMapItemIds = [];
  let desiredAuthorizedUids = [];

  if (eventData && !isCancelled && !isDraft) {
    desiredProjections = buildEventProjections(source, eventData, eventId, bandId, bandName, now);
    desiredMapItemIds = desiredProjections.map((p) => p.mapItemId);
    if (desiredProjections.length > 0) {
      if (source === 'public_calendar') {
        desiredAuthorizedUids = ['public'];
      } else {
        desiredAuthorizedUids = getAuthorizedUserIdsForBandEvent(bandData || {}, eventData);
      }
    }
  }

  const updates = {};

  if (source === 'public_calendar') {
    const desiredIdSet = new Set(desiredMapItemIds);
    prevMapItemIds.forEach((mId) => {
      if (!desiredIdSet.has(mId)) {
        updates[`/publicMapEventFeed/${mId}`] = null;
      }
    });
    desiredProjections.forEach((p) => {
      updates[`/publicMapEventFeed/${p.mapItemId}`] = p;
    });
  } else {
    // Private Band Event
    // Ensure public feed cannot leak this private event
    updates[`/publicMapEventFeed/event:public:${eventId}`] = null;

    const desiredAuthSet = new Set(desiredAuthorizedUids);
    const desiredIdSet = new Set(desiredMapItemIds);

    // Users who lost authorization
    prevAuthorizedUids.forEach((uid) => {
      if (!desiredAuthSet.has(uid)) {
        prevMapItemIds.forEach((mId) => {
          updates[`/userMapEventFeed/${uid}/${mId}`] = null;
        });
      }
    });

    // Users who retained authorization
    prevAuthorizedUids.forEach((uid) => {
      if (desiredAuthSet.has(uid)) {
        // Stale map items (e.g. removed schedule parts)
        prevMapItemIds.forEach((mId) => {
          if (!desiredIdSet.has(mId)) {
            updates[`/userMapEventFeed/${uid}/${mId}`] = null;
          }
        });
        // Write/update desired projections
        desiredProjections.forEach((p) => {
          updates[`/userMapEventFeed/${uid}/${p.mapItemId}`] = p;
        });
      }
    });

    // Newly authorized users
    desiredAuthorizedUids.forEach((uid) => {
      if (!prevAuthorizedUids.includes(uid)) {
        desiredProjections.forEach((p) => {
          updates[`/userMapEventFeed/${uid}/${p.mapItemId}`] = p;
        });
      }
    });
  }

  // Index maintenance
  if (desiredMapItemIds.length === 0) {
    updates[`/mapEventProjectionIndex/${sourceKey}`] = null;
  } else {
    const mapItemIdsObj = {};
    desiredMapItemIds.forEach((id) => {
      mapItemIdsObj[id] = true;
    });
    const authUidsObj = {};
    desiredAuthorizedUids.forEach((uid) => {
      authUidsObj[uid] = true;
    });
    updates[`/mapEventProjectionIndex/${sourceKey}`] = {
      sourceType: source,
      bandId: bandId || null,
      eventId: String(eventId),
      mapItemIds: mapItemIdsObj,
      authorizedUids: authUidsObj,
      updatedAt: Date.now(),
    };
  }

  return {
    sourceKey,
    updates,
    desiredProjections,
    desiredMapItemIds,
    desiredAuthorizedUids,
  };
}

module.exports = {
  isValidCoordinate,
  buildMapItemId,
  buildProjectionIndexKey,
  sanitizeDescription,
  isEventPast,
  getAuthorizedUserIdsForBandEvent,
  extractScheduleParts,
  buildEventProjections,
  calculateReconciliationDiff,
};
