'use strict';

const { HttpsError } = require('firebase-functions/v2/https');
const { randomUUID } = require('node:crypto');
const { validMember } = require('./band_membership_index');
const { authorizeRequest, normalize } = require('./membership_authority');
const { safeKey, feedPath, routesPath, signalPath } = require('./notification_delivery');

const unavailable = () => new HttpsError('not-found', 'This notification is unavailable.');
const at = async (db, path) => (await db.ref(path).get()).val();
const eventTypes = new Set(['event_invite', 'event_reminder', 'event_threshold', 'event_milestone']);
const requestTypes = new Set(['sub_request_invite', 'sub_request', 'grouped_sub_request']);
const responseTypes = new Set(['sub_request_response', 'sub_response']);
const genericTitles = {
  band_file_uploaded: 'Band file uploaded',
  direct_message: 'New message',
  band_section_chat: 'New section message',
  band_room_message: 'New Band Room activity',
  session_message: 'New session message',
  session_application: 'New session application',
  session_application_status: 'Session application update',
  gig_finalized: 'Gig confirmed',
};
const field = (data, name) => data?.[name] ?? data?.[name[0].toLowerCase() + name.slice(1)];
const currentMember = member => validMember(member) &&
  (member.Status == null || member.status == null || normalize(member.Status) === normalize(member.status));

function activeRequest(request, now = Date.now()) {
  if (!request || normalize(field(request, 'NotificationMode')) === 'map_pin') return false;
  const status = normalize(field(request, 'Status') ?? 'published');
  if (!['published', 'open', 'active'].includes(status) ||
      field(request, 'IsSelected') === true || field(request, 'AssignedUserId')) return false;
  const explicitEnd = field(request, 'ExpiresAt') ?? field(request, 'EndDateTime');
  const end = typeof explicitEnd === 'number' ? explicitEnd :
    /(?:Z|[+-]\d\d:?\d\d)$/i.test(explicitEnd || '') ? Date.parse(explicitEnd) : NaN;
  if (Number.isFinite(end)) return now < end;
  const day = String(field(request, 'Date') || '').match(/^(\d{4})[-/](\d\d?)[-/](\d\d?)(?:$|T)/);
  if (!day) return true;
  const start = timeOfDay(field(request, 'StartTime'));
  const finish = timeOfDay(field(request, 'EndTime'));
  const crossesMidnight = finish != null && start != null && finish <= start;
  const boundary = Date.UTC(+day[1], +day[2] - 1, +day[3] + Number(crossesMidnight)) +
    (finish ?? 1440) * 60_000;
  // A legacy wall-clock date has no authoritative time zone. At the
  // ambiguous boundary, deny access once it could have expired.
  return now < boundary - 14 * 3_600_000;
}

function timeOfDay(value) {
  const match = String(value || '').trim().match(/^(\d{1,2})[:.](\d{2})(?::\d{2})?$/);
  if (!match) return null;
  const [, hour, minute] = match.map(Number);
  return (hour < 24 && minute < 60) || (hour === 24 && minute === 0)
    ? hour * 60 + minute : null;
}

async function requestFor(db, uid, id, isPrivate) {
  if (!safeKey(id)) throw unavailable();
  const request = await at(db, `SubRequests/${id}`);
  if (!activeRequest(request)) throw unavailable();
  const targets = field(request, 'TargetUserIds');
  const explicitlyTargeted = Array.isArray(targets) && targets.includes(uid);
  if (Array.isArray(targets) && targets.length > 0 && !explicitlyTargeted) throw unavailable();
  const [audience, publicRow] = await Promise.all([
    at(db, `subRequestAudience/${id}/${uid}`),
    at(db, `publicSubRequests/${id}`),
  ]);
  if (!explicitlyTargeted && audience !== true && (isPrivate(request) || !publicRow)) {
    throw unavailable();
  }
  return request;
}

async function authorizedEvent(db, uid, bandId, eventId) {
  if (!safeKey(bandId) || !safeKey(eventId)) throw unavailable();
  const [event, member, bandName] = await Promise.all([
    at(db, `Bands/${bandId}/Events/${eventId}`),
    at(db, `Bands/${bandId}/Members_band/${uid}`),
    at(db, `Bands/${bandId}/Name`),
  ]);
  const invite = event?.externalInvitees?.[uid];
  const directlyInvited = ['manual', 'direct'].includes(invite?.source) &&
    ['pending', 'attending', 'maybe', 'declined'].includes(normalize(invite?.status));
  const memberAccess = currentMember(member);
  if (!event || ['deleted', 'cancelled', 'canceled', 'inactive', 'archived'].includes(normalize(field(event, 'Status'))) ||
      (!memberAccess && !directlyInvited)) throw unavailable();
  return { event, bandName, memberAccess };
}

function summaryParts(source, bandName, format, isEvent = false) {
  return [
    bandName || field(source, 'BandName') || (isEvent ? 'Band' : 'Freelance Gig'),
    field(source, 'EventType') || (isEvent ? 'Event' : 'Gig'),
    format(source.startDateTime || field(source, 'Date'), field(source, 'StartTime'), field(source, 'EndTime')),
  ];
}

function summary(source, bandName, format, isEvent = false) {
  return summaryParts(source, bandName, format, isEvent).join(' • ');
}

function requestItem(id, request, options) {
  const item = options.buildRequest({ ...request, SubRequestId: id });
  item.id = id;
  item.subRequestId = id;
  return item;
}

async function resolveRoute(db, uid, route, options, { preview = false, slotId } = {}) {
  const { type, subRequestId, responderId, bandId, eventId, publicationId, conversationId,
    sessionId, fileId, messageId, assignedAt, applicantId, decision } = route;
  if (eventTypes.has(type)) {
    const { event, bandName, memberAccess } = await authorizedEvent(db, uid, bandId, eventId);
    const title = type === 'event_invite' ? 'Event Request' :
      type === 'event_reminder' ? 'Event RSVP Reminder' : 'Event RSVP Milestone';
    return { kind: 'event', title, body: summary(event, bandName, options.format, true), bandId, eventId, memberAccess };
  }
  if (responseTypes.has(type)) {
    if (!safeKey(subRequestId) || !safeKey(responderId)) throw unavailable();
    const request = await at(db, `SubRequests/${subRequestId}`);
    if (!activeRequest(request) || !(request.Responses ?? request.responses)?.[responderId]) throw unavailable();
    await authorizeRequest(db, uid, request);
    return {
      kind: 'response', title: 'Gig Request Response', body: summary(request, null, options.format),
      ...(preview ? {} : { request: requestItem(subRequestId, request, options), responderId }),
    };
  }
  if (requestTypes.has(type)) {
    if (type !== 'grouped_sub_request') {
      if (slotId) throw unavailable();
      const request = await requestFor(db, uid, subRequestId, options.isPrivate);
      return {
        kind: 'request', title: 'Gig Request', body: summary(request, null, options.format),
        ...(preview ? {} : { request: requestItem(subRequestId, request, options) }),
      };
    }
    if (!safeKey(publicationId)) throw unavailable();
    const publication = await at(db, `subRequestPublications/${publicationId}`);
    const ids = [...new Set(Object.values(publication?.slots || {})
      .map(slot => slot.subRequestId || slot.slotId).filter(safeKey))];
    if (slotId && !ids.includes(slotId)) throw unavailable();
    const matching = await Promise.all((slotId ? [slotId] : ids).map(async id => {
      if (await at(db, `subRequestAudience/${id}/${uid}`) !== true) return null;
      const request = await at(db, `SubRequests/${id}`);
      const targets = field(request, 'TargetUserIds');
      const targetMatches = !Array.isArray(targets) || targets.length === 0 || targets.includes(uid);
      return activeRequest(request) && targetMatches && field(request, 'PublicationId') === publicationId
        ? { id, request } : null;
    }));
    const eligible = matching.filter(Boolean);
    if (eligible.length === 0) throw unavailable();
    const title = 'Gig Request';
    if (eligible.length === 1) {
      const [{ id, request }] = eligible;
      return {
        kind: 'request', title, body: summary(request, null, options.format),
        ...(preview ? {} : { request: requestItem(id, request, options) }),
      };
    }
    const matches = eligible.map(({ id, request }) => ({
      id,
      label: [field(request, 'VoicePart'), summary(request, null, options.format)].filter(Boolean).join(' • '),
    }));
    const summaries = eligible.map(({ request }) => summaryParts(request, null, options.format));
    const common = summaries[0].filter((part, index) => summaries.every(parts => parts[index] === part));
    return {
      kind: 'group', title, body: common.join(' • '),
      ...(preview ? {} : { matches }),
    };
  }
  if (!Object.hasOwn(genericTitles, type)) throw unavailable();
  const result = { kind: 'other', title: genericTitles[type], body: '' };
  if (['direct_message', 'band_section_chat', 'session_message'].includes(type)) {
    if (!safeKey(conversationId)) throw unavailable();
    const [index, participant] = await Promise.all([
      at(db, `userConversations/${uid}/${conversationId}`),
      at(db, `conversations/${conversationId}/participants/${uid}`),
    ]);
    if (!index || participant !== true) throw unavailable();
    if (type === 'band_section_chat') {
      if (!safeKey(bandId) || await at(db, `conversations/${conversationId}/bandId`) !== bandId ||
          !currentMember(await at(db, `Bands/${bandId}/Members_band/${uid}`))) throw unavailable();
    }
    return { ...result, conversationId, ...(bandId ? { bandId } : {}), otherUserId: index.otherUserId || '' };
  }
  if (['band_file_uploaded', 'band_room_message'].includes(type)) {
    if (!safeKey(bandId) || !currentMember(await at(db, `Bands/${bandId}/Members_band/${uid}`))) throw unavailable();
    if (type === 'band_file_uploaded' && (!safeKey(fileId) || !(await at(db, `files/${bandId}/${fileId}`)))) {
      throw unavailable();
    }
    if (type === 'band_room_message') {
      if (!safeKey(messageId) || !(await at(db, `bandconversations/${bandId}/messages/${messageId}`))) {
        throw unavailable();
      }
    }
    return { ...result, bandId };
  }
  if (type === 'gig_finalized') {
    if (!safeKey(subRequestId)) throw unavailable();
    const request = await at(db, `SubRequests/${subRequestId}`);
    if (field(request, 'AssignedUserId') !== uid || field(request, 'AssignedAt') !== assignedAt ||
        !['assigned', 'filled'].includes(normalize(field(request, 'Status')))) throw unavailable();
    result.body = summary(request, null, options.format);
    if (safeKey(bandId) && safeKey(eventId)) {
      const { memberAccess } = await authorizedEvent(db, uid, bandId, eventId);
      return { ...result, kind: 'event', bandId, eventId, memberAccess };
    }
    return { ...result, kind: 'request', ...(preview ? {} : { request: requestItem(subRequestId, request, options) }) };
  }
  if (!safeKey(sessionId)) throw unavailable();
  const session = await at(db, `Collabs/Sessions/${sessionId}`);
  if (!session) throw unavailable();
  if (type === 'session_application') {
    if (field(session, 'CreatorId') !== uid || !safeKey(applicantId) ||
        !(await at(db, `Collabs/Applications/${sessionId}/${applicantId}`))) throw unavailable();
  } else {
    const application = await at(db, `Collabs/Applications/${sessionId}/${uid}`);
    if (!['accepted', 'declined'].includes(decision) ||
        normalize(field(application, 'Status')) !== decision) throw unavailable();
    result.title = decision === 'accepted' ? 'Session application accepted' : 'Session application declined';
  }
  return { ...result, sessionId };
}

async function list(db, uid, options) {
  const rows = await at(db, `${feedPath}/${uid}`) || {};
  const views = await Promise.all(Object.entries(rows).map(async ([id, row]) => {
    try {
      const route = await at(db, `${routesPath}/${uid}/${id}`);
      if (!route) return null;
      const { title, body } = await resolveRoute(db, uid, route, options, { preview: true });
      return {
        id, type: route.type, title, body, createdAt: row.createdAt, isRead: row.isRead === true,
        ...(responseTypes.has(route.type) ? { data: { subRequestId: route.subRequestId } } : {}),
      };
    } catch (error) {
      if (['not-found', 'permission-denied', 'failed-precondition', 'invalid-argument'].includes(error.code)) return null;
      throw error;
    }
  }));
  return views.filter(Boolean).sort((a, b) => b.createdAt - a.createdAt);
}

async function resolve(db, uid, id, slotId, options, preview = false) {
  if (!safeKey(id) || (slotId != null && !safeKey(slotId))) throw unavailable();
  const route = await at(db, `${routesPath}/${uid}/${id}`);
  if (!route) throw unavailable();
  try {
    return { type: route.type, ...(await resolveRoute(db, uid, route, options, { slotId, preview })) };
  } catch (error) {
    if (['permission-denied', 'failed-precondition', 'invalid-argument'].includes(error.code)) throw unavailable();
    throw error;
  }
}

async function markRead(db, uid, accepts, id) {
  const feed = db.ref(`${feedPath}/${uid}`);
  const rows = id ? { [id]: (await feed.child(id).get()).val() } : (await feed.get()).val() || {};
  if (id && !rows[id]) throw unavailable();
  const now = Date.now();
  const results = await Promise.all(Object.entries(rows)
    .filter(([, row]) => row && !row.isRead && accepts(row))
    .map(([key]) => feed.child(key).transaction(row => {
      // Returning null on a cold local cache lets RTDB retry with server data.
      // An actual deletion stays deleted and does not count as an update.
      if (!row) return null;
      if (row.isRead || !accepts(row)) return;
      return { ...row, isRead: true, readAt: now };
    })));
  const updatedCount = results.filter(result => result.committed && result.snapshot.val()?.isRead).length;
  if (updatedCount) await db.ref(`${signalPath}/${uid}`).set(randomUUID());
  return { success: true, updatedCount };
}

module.exports = { activeRequest, list, resolve, markRead, authorizedEvent, currentMember };
