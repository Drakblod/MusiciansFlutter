'use strict';

const { createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const { validMember } = require('./band_membership_index');
const { bandKey, manager, normalize } = require('./membership_authority');
const { excludedIds, key } = require('./event_read_models');

const type = 'event_ready_to_finalize';
const responses = new Set(['yes', 'no', 'maybe', 'uncertain', 'attending', 'declined']);
const inactive = new Set(['cancelled', 'canceled', 'deleted', 'inactive', 'archived',
  'finalized', 'completed', 'complete', 'closed', 'removed', 'revoked', 'withdrawn']);
// A hold pauses RSVP obligations while preserving canonical band access.
const eligibleMember = member => validMember(member) &&
  [member.Status, member.status].every(status => status == null || normalize(status) === 'active');

function eventIsOpen(event, now) {
  if (!event || event.requireResponse === false || event.isLocked === true ||
      event.isActive === false || event.IsActive === false ||
      event.isFinalized === true || event.IsFinalized === true ||
      event.isCancelled === true || event.isCanceled === true || event.isDeleted === true ||
      [event.Status, event.status].some(status => inactive.has(normalize(status)))) return false;
  const end = event.endDateTime || event.startDateTime;
  if (typeof end !== 'string' || !/^\d{4}-\d\d-\d\dT/.test(end)) return false;
  // Legacy wall-clock values have no authoritative time zone. Once an event
  // could have ended anywhere, do not advertise it as ready to finalize.
  const zoned = /(?:Z|[+-]\d\d:?\d\d)$/i.test(end);
  const boundary = Date.parse(zoned ? end : `${end}Z`) - (zoned ? 0 : 14 * 3_600_000);
  return boundary > now;
}

function eligibleGuest(invite) {
  return ['manual', 'direct'].includes(normalize(invite?.source)) &&
    invite.isActive !== false && !inactive.has(normalize(invite.status));
}

function readiness(event, members, now = Date.now()) {
  if (!eventIsOpen(event, now)) return null;
  const excluded = new Set(excludedIds(event));
  const eligible = new Map();
  const persistedResponses = event.Responses ?? event.responses;
  const hasResponded = uid => responses.has(normalize(persistedResponses?.[uid]?.status));
  for (const [uid, member] of Object.entries(members || {})) {
    if (key(uid) && !excluded.has(uid) && eligibleMember(member)) {
      eligible.set(uid, hasResponded(uid));
    }
  }
  for (const [uid, invite] of Object.entries(event.externalInvitees || {})) {
    if (key(uid) && !excluded.has(uid) && eligibleGuest(invite)) {
      eligible.set(uid, hasResponded(uid) || responses.has(normalize(invite.status)));
    }
  }
  if (!eligible.size || [...eligible.values()].some(answered => !answered)) return null;
  const createdAt = Number.isSafeInteger(event.createdAt) ? event.createdAt : null;
  return createHash('sha256').update(JSON.stringify([createdAt, [...eligible.keys()].sort()])).digest('hex');
}

function eventAudienceChanged(before, after) {
  if (!after) return false;
  return ['externalInvitees', 'excludedMemberIds', 'ExcludedMemberIds', 'requireResponse', 'responses', 'createdAt',
    'status', 'Status', 'isActive', 'IsActive', 'isLocked', 'IsFinalized', 'isFinalized', 'isCancelled', 'isCanceled',
    'isDeleted', 'startDateTime', 'endDateTime']
    .some(field => !isDeepStrictEqual(before?.[field], after[field]));
}

function memberEligibilityChanged(before, after) {
  return eligibleMember(before) !== eligibleMember(after);
}

function validBandId(bandId) {
  if (!key(bandId)) return false;
  try {
    return bandKey(bandId) === bandId;
  } catch (_) {
    return false;
  }
}

async function read(db, bandId, eventId) {
  if (!validBandId(bandId) || !key(eventId)) return null;
  const band = db.ref(`Bands/${bandId}`);
  const [eventSnap, membersSnap, nameSnap] = await Promise.all([
    band.child(`Events/${eventId}`).get(), band.child('Members_band').get(), band.child('Name').get(),
  ]);
  const event = eventSnap.val();
  const members = membersSnap.val();
  const generation = readiness(event, members);
  return generation ? { event, members, generation, bandName: nameSnap.val() } : null;
}

async function canFinalizeReadyEvent(db, uid, bandId, eventId, generation) {
  if (!key(uid) || uid.trim() !== uid) return null;
  const ready = await read(db, bandId, eventId);
  // The lock action calls requireManager, which uses this same predicate.
  return ready?.generation === generation && manager(ready?.members?.[uid]) ? ready : null;
}

async function notify(db, bandId, eventId, publish, entersReadiness) {
  const ready = await read(db, bandId, eventId);
  if (!ready || !entersReadiness(ready)) return;
  const { generation, members } = ready;
  const recipients = Object.keys(members || {}).filter(uid => key(uid) && manager(members[uid]));
  await Promise.all(recipients.map(uid => publish(uid, type, [bandId, eventId, generation],
    { bandId, eventId, generation },
    { canPublish: () => canFinalizeReadyEvent(db, uid, bandId, eventId, generation) })));
}

function changedGeneration(generation, before, after) {
  return after === generation && before !== generation;
}

function notifyEventChange(db, bandId, eventId, before, after, publish) {
  return notify(db, bandId, eventId, publish, ({ members, generation }) =>
    changedGeneration(generation, readiness(before, members), readiness(after, members)));
}

function notifyResponseChange(db, bandId, eventId, uid, before, after, publish) {
  if (!key(uid)) return;
  return notify(db, bandId, eventId, publish, ({ event, members, generation }) => {
    const withResponse = response => ({
      ...event, Responses: { ...event.Responses, [uid]: response },
    });
    return changedGeneration(generation, readiness(withResponse(before), members),
      readiness(withResponse(after), members));
  });
}

async function notifyBand(db, bandId, uid, before, after, publish) {
  if (!validBandId(bandId)) return;
  const band = db.ref(`Bands/${bandId}`);
  const [events, members] = await Promise.all([band.child('Events').get(), band.child('Members_band').get()]);
  const roster = members.val();
  const priorRoster = { ...roster, [uid]: before };
  const changedRoster = { ...roster, [uid]: after };
  for (const [eventId, event] of Object.entries(events.val() || {})) {
    const current = readiness(event, roster);
    if (current && changedGeneration(current, readiness(event, priorRoster), readiness(event, changedRoster))) {
      await notify(db, bandId, eventId, publish, ({ generation }) => generation === current);
    }
  }
}

module.exports = {
  readiness, eventAudienceChanged, memberEligibilityChanged, canFinalizeReadyEvent,
  notifyEventChange, notifyResponseChange, notifyBand,
};
