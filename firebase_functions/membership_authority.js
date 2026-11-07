'use strict';
const { HttpsError } = require('firebase-functions/v2/https');
const { validStatus, validMember, reconcileMembershipIndex } = require('./band_membership_index');
const normalize = value => typeof value === 'string' ? value.trim().toLowerCase() : '';
const role = member => normalize(member?.Role ?? member?.role);
const consistent = member => !(member?.Status != null && member?.status != null && normalize(member.Status) !== normalize(member.status)) && !(member?.Role != null && member?.role != null && normalize(member.Role) !== normalize(member.role));
const manager = member => consistent(member) && validMember(member) && ['leader', 'admin'].includes(role(member));
const leader = member => consistent(member) && validMember(member) && role(member) === 'leader';
function key(value, label = 'ID') {
  if (typeof value !== 'string' || !value.trim() || value.length > 128 || /[.#$\[\]\/]/.test(value) || value !== value.trim() || ['__proto__','prototype','constructor'].includes(value)) {
    throw new HttpsError('invalid-argument', `Invalid ${label}.`);
  }
  return value;
}
function bandKey(value) {
  const id = key(value, 'band ID');
  if (['all','null','undefined','none','freelance','standalone'].includes(normalize(id))) {
    throw new HttpsError('invalid-argument', 'A canonical band is required.');
  }
  return id;
}
function canonicalField(record, upper, lower) {
  const a = record?.[upper], b = record?.[lower];
  if (a != null && b != null && a !== b) throw new HttpsError('failed-precondition', `Conflicting ${lower}.`);
  return a ?? b;
}
async function requireManager(db, bandId, uid, onlyLeader = false) {
  const id = bandKey(bandId);
  key(uid,'caller ID');
  const member = (await db.ref(`Bands/${id}/Members_band/${uid}`).get()).val();
  if (!(onlyLeader ? leader(member) : manager(member))) {
    throw new HttpsError('permission-denied', 'An active band manager is required.');
  }
  return member;
}
async function authorizeRequest(db, uid, request, suppliedBand, suppliedEvent) {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  key(uid,'caller ID');
  const bandId = canonicalField(request, 'BandId', 'bandId');
  // Bandless creator workflows have explicit sentinel ownership, never another band's authority.
  const bandless = ['freelance','standalone'].includes(bandId);
  if (!bandless) bandKey(bandId);
  if (suppliedBand != null && suppliedBand !== bandId) {
    throw new HttpsError('permission-denied', 'The band does not match the canonical request.');
  }
  const eventId = canonicalField(request, 'EventId', 'eventId');
  if (suppliedEvent != null && suppliedEvent !== eventId) {
    throw new HttpsError('permission-denied', 'The event does not match the canonical request.');
  }
  if (eventId != null && eventId !== '') key(eventId,'event ID');
  const creatorId = canonicalField(request, 'CreatorUserId', 'creatorUserId') ||
    canonicalField(request, 'UserId', 'userId') || request.createdBy;
  if (!creatorId) throw new HttpsError('failed-precondition', 'Request creator is missing.');
  key(creatorId,'creator ID');
  if (bandless) {
    if (creatorId !== uid) throw new HttpsError('permission-denied', 'Only the request creator may manage this request.');
  } else {
    await requireManager(db, bandId, uid);
  }
  return { bandId:bandless ? null : bandId, eventId:bandless ? null : eventId, creatorId };
}
// Ordinary Map pins have their own ownership contract. Absence of a band is
// personal ownership, never authority over a band or a staffing request.
async function authorizeMapPin(db, uid, record) {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  key(uid, 'caller ID');
  const bandId = canonicalField(record, 'BandId', 'bandId');
  const creatorId = canonicalField(record, 'CreatorUserId', 'creatorUserId') ||
    canonicalField(record, 'UserId', 'userId');
  key(creatorId, 'creator ID');
  if (bandId == null || bandId === 'freelance' || bandId === 'standalone') {
    if (creatorId !== uid) throw new HttpsError('permission-denied', 'Only the pin owner may manage this pin.');
  } else {
    await requireManager(db, bandId, uid);
  }
}
const metadataFields = ['Name','EnsembleType','Genres','Qualification','Location','PublicLocation','Style_band','Style','Level',
  'RehearsalLocation','RehearsalDayOfWeek','RehearsalDate','RehearsalTime','RehearsalStartTime','RehearsalEndTime',
  'RehearsalDateTime','About','Description','Address','Contact','Members','History','ConcertsProjects'];
function metadata(value, allowVerifiedCity = false) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new HttpsError('invalid-argument','Band metadata is required.');
  const clean = {};
  for (const field of metadataFields) {
    const v = value[field];
    if (field === 'Location' && v == null) { clean.Location = null; continue; }
    if (field === 'PublicLocation') {
      if (v == null) { clean[field] = null; continue; }
      if (!allowVerifiedCity) throw new HttpsError('permission-denied','A city confirmation is required.');
      const location = require('./catalogue_projections').structuredLocation(v);
      if (!location) throw new HttpsError('invalid-argument','Invalid public city.');
      clean[field] = {version:1,precision:'city',confirmed:true,city:location.city,
        ...(location.region?{region:location.region}:{}),country:location.country,
        ...(location.countryCode?{countryCode:location.countryCode}:{})};
      continue;
    }
    if (v == null) continue;
    if (['Genres','Style_band'].includes(field)) {
      if (!Array.isArray(v) || v.length > 100 || v.some(x => typeof x !== 'string' || x.length > 200)) throw new HttpsError('invalid-argument','Invalid band tags.');
    } else if (typeof v !== 'string' || v.length > 10000) throw new HttpsError('invalid-argument','Invalid band metadata.');
    clean[field] = v;
  }
  if ('Name' in clean && !clean.Name.trim()) throw new HttpsError('invalid-argument','Band name is required.');
  return clean;
}
// Fixed 64-entry window per band, across all callers; no scheduled cleanup required.
// A receipt outside this window is a new request and must pass current authority.
const RETRY_LIMIT = 64;
function trimLedger(value) {
  const entries = Object.keys(value).sort((a,b) => (value[a]?.timestamp ?? value[a]) - (value[b]?.timestamp ?? value[b]) || a.localeCompare(b));
  for (const id of entries.slice(0, Math.max(0, entries.length - RETRY_LIMIT))) delete value[id];
}
async function reconcileBand(db, bandId, memberIds) {
  await Promise.all([...new Set(memberIds)].map(uid => reconcileMembershipIndex(db, bandId, uid)));
}
// Canonical validation and mutations run in a per-band transaction. Current-state
// projections are reconciled after commit and by the existing retried member trigger.
async function mutate(db, uid, data) {
  if (!uid) throw new HttpsError('unauthenticated','Sign in first.');
  key(uid,'caller ID');
  const bandId = bandKey(data?.bandId);
  const action = data.action;
  const target = data.userId == null ? uid : key(data.userId, 'member ID');
  const operationId = key(data.operationId, 'operation ID');
  const allowed = ['create','add','role','status','remove','leave','transfer','metadata','departAccount','delete'];
  if (!allowed.includes(action)) throw new HttpsError('invalid-argument','Unknown membership action.');
  // Validate creation before allocating private retry state for a new band ID.
  if (action === 'create' || action === 'metadata') {
    const fields = metadata(data.metadata,!!data.cityGrantNonce);
    if (action === 'create') {
      if (!fields.Name) throw new HttpsError('invalid-argument','Band name is required.');
      const initial = data.initialMembers ?? [];
      if (!Array.isArray(initial) || initial.length > 100) throw new HttpsError('invalid-argument','Invalid initial members.');
      const ids = new Set([uid]);
      for (const entry of initial) {
        const id = key(entry.userId,'member ID');
        if (ids.has(id) || !['member','admin'].includes(normalize(entry.role || 'Member'))) throw new HttpsError('invalid-argument','Invalid initial member.');
        ids.add(id);
      }
    }
  }
  // Targets must be real, enabled accounts, not invented roster identities.
  if (['create','add','transfer','role','status'].includes(action)) {
    if (action === 'create' && !Array.isArray(data.initialMembers ?? [])) throw new HttpsError('invalid-argument','Invalid initial members.');
    const ids = action === 'create' ? (data.initialMembers ?? []).map(m => key(m.userId,'member ID')) : [target];
    for (const id of ids) {
      let user;
      try { user = await require('firebase-admin').auth().getUser(id); }
      catch (_) { throw new HttpsError('not-found','Member account was not found.'); }
      if (user.disabled) throw new HttpsError('failed-precondition','Member account is disabled.');
    }
  }
  const fingerprint = require('crypto').createHash('sha256').update(JSON.stringify({ action, target, role: data.role ?? null, status: data.status ?? null,
    nickname: data.nickname ?? null, metadata: data.metadata ?? null,
    cityGrantNonce:data.cityGrantNonce??null,initialMembers: data.initialMembers ?? null })).digest('hex');
  let failure, affected = [], deleted = false;
  const ref = db.ref(`Bands/${bandId}`);
  const before = (await ref.get()).val();
  if (!before && ['delete','departAccount'].includes(action)) return { success:true, bandId };
  if (!before && action !== 'create') throw new HttpsError('not-found','Band not found.');
  if (['leave','departAccount'].includes(action) && !before?.Members_band?.[uid]) return { success:true, bandId };
  const receiptKey = require('crypto').createHash('sha256').update(`${uid}\0${operationId}`).digest('hex');
  const ledgerRef = db.ref(`membershipMutationOperations/${bandId}`);
  // Only a valid caller or the owner of a retained receipt may reserve retry state.
  if (!before?._membershipOperations?.[receiptKey]) {
    const caller = before?.Members_band?.[uid];
    if (action === 'create') {
      if (before) throw new HttpsError('already-exists','A band with that ID already exists.');
    } else if (action === 'leave' || action === 'departAccount') {
      if (target !== uid) throw new HttpsError('permission-denied','You may only leave as yourself.');
    } else if (before && !(action === 'delete' ? leader(caller) : manager(caller))) {
      throw new HttpsError('permission-denied','An active canonical manager is required.');
    }
  }
  let effectiveMetadata=data.metadata;
  // A canonical receipt plus the matching private ledger proves this exact
  // operation already succeeded, even after the short-lived grant expires.
  if(data.cityGrantNonce!=null && !before?._membershipOperations?.[receiptKey]) {
    if(!['create','metadata'].includes(action))throw new HttpsError('invalid-argument','City confirmation is only valid for band metadata.');
    const grant=await require('./city_verification').consumeGrant(db,uid,'band',bandId,
      data.cityGrantNonce,operationId,data.metadata?.PublicLocation);
    effectiveMetadata={...data.metadata,PublicLocation:grant.location,
      Location:`${grant.location.city}, ${grant.location.country}`};
  }
  let ledgerFailure;
  const now = Date.now();
  await ledgerRef.get();
  await ledgerRef.transaction(value => {
    ledgerFailure = null;
    value ||= {};
    if (before?._membershipOperations?.[receiptKey] && !value[receiptKey]) {
      ledgerFailure = new HttpsError('failed-precondition','Retry receipt expired; reload before starting a new operation.'); return value;
    }
    if (value[receiptKey] && value[receiptKey].fingerprint !== fingerprint) {
      ledgerFailure = new HttpsError('invalid-argument','Operation ID was reused.'); return;
    }
    value[receiptKey] ||= { fingerprint, timestamp:now };
    trimLedger(value);
    return value;
  }, undefined, false);
  if (ledgerFailure) throw ledgerFailure;
  const result = await ref.transaction(current => {
    failure = null; deleted = false; affected = [];
    try {
      if (current?._membershipOperations?.[receiptKey]) {
        affected = Object.keys(current.Members_band || {}).concat(target);
        return current;
      }
      if (action === 'create') {
        if (current) {
          if (current._createdBy === uid && current._createOperation === operationId) {
            affected = Object.keys(current.Members_band || {}); return current;
          }
          throw new HttpsError('already-exists','A band with that ID already exists.');
        }
        const fields = metadata(effectiveMetadata,!!data.cityGrantNonce);
        if (!fields.Name) throw new HttpsError('invalid-argument','Band name is required.');
        const members = { [uid]: { Role:'Leader', Status:'active', Nickname: String(data.nickname || 'Leader').slice(0,200) } };
        const initial = data.initialMembers ?? [];
        if (!Array.isArray(initial) || initial.length > 100) throw new HttpsError('invalid-argument','Invalid initial members.');
        for (const entry of initial) {
          const id = key(entry.userId, 'member ID');
          if (id === uid || members[id]) throw new HttpsError('invalid-argument','Duplicate initial member.');
          const r = normalize(entry.role || 'Member');
          if (!['member','admin'].includes(r)) throw new HttpsError('invalid-argument','Invalid initial role.');
          members[id] = { Role:r === 'admin' ? 'Admin' : 'Member', Status:'active', Nickname:String(entry.nickname || 'Member').slice(0,200) };
        }
        current = { ...fields, Members_band:members, _createdBy:uid, _createOperation:operationId };
      } else {
        if (!current?.Members_band) {
          if (!current) return current;
          throw new HttpsError('not-found','Band not found.');
        }
        const members = current.Members_band;
        const caller = members[uid], subject = members[target];
        const leaders = Object.keys(members).filter(id => role(members[id]) === 'leader');
        if (leaders.length !== 1) throw new HttpsError('failed-precondition','Band must have exactly one Leader before membership changes.');
        if (action === 'leave' || action === 'departAccount') {
          if (target !== uid) throw new HttpsError('permission-denied','You may only leave as yourself.');
          if (!caller) return current;
          if (role(caller) === 'leader') {
            if (action === 'leave') throw new HttpsError('failed-precondition','Transfer leadership or delete the band before leaving.');
            const others = Object.keys(members).filter(id => id !== uid && validMember(members[id]));
            const successor = others.find(id => role(members[id]) === 'admin') || others.sort()[0];
            if (!successor) {
              if (Object.keys(members).length !== 1) throw new HttpsError('failed-precondition','Choose an active successor before deleting the account.');
              affected = Object.keys(members); deleted = true; return null;
            }
            members[successor].Role = 'Leader'; delete members[successor].role;
          }
          delete members[uid];
        } else {
          if (!manager(caller)) throw new HttpsError('permission-denied','An active band manager is required.');
          if (action === 'delete') {
            if (!leader(caller)) throw new HttpsError('permission-denied','Only the active Leader may delete the band.');
            affected = Object.keys(members); deleted = true; return null;
          }
          if (action === 'metadata') Object.assign(current, metadata(effectiveMetadata,!!data.cityGrantNonce));
          else if (action === 'add') {
            const r = normalize(data.role || 'Member');
            if (!['member','admin'].includes(r) || (r === 'admin' && !leader(caller))) throw new HttpsError('permission-denied','Only the Leader may grant Admin.');
            if (subject) {
              if (normalize(subject.Role ?? subject.role) !== r) throw new HttpsError('already-exists','Member already exists; use the role/status operation.');
              subject.Status = 'active'; delete subject.status;
            } else members[target] = { Role:r === 'admin' ? 'Admin':'Member', Status:'active', Nickname:String(data.nickname || 'Member').slice(0,200) };
          } else {
            if (!subject) {
              if (action === 'remove') return current;
              throw new HttpsError('not-found','Member not found.');
            }
            if (action === 'transfer') {
              if (!leader(caller) || target === uid || !validMember(subject)) throw new HttpsError('permission-denied','Only the current Leader may transfer to an active member.');
              members[uid].Role = 'Admin'; delete members[uid].role;
              subject.Role = 'Leader'; delete subject.role;
            } else {
              if (role(subject) === 'leader') throw new HttpsError('permission-denied','Use Leader transfer; the Leader cannot be removed or demoted.');
              if (action === 'role') {
                const r = normalize(data.role);
                if (!leader(caller) || !['member','admin'].includes(r)) throw new HttpsError('permission-denied','Only the Leader may grant or revoke Admin.');
                subject.Role = r === 'admin' ? 'Admin' : 'Member'; delete subject.role;
              } else {
                if (role(subject) === 'admin' && !leader(caller) && target !== uid) throw new HttpsError('permission-denied','Only the Leader may manage another Admin.');
                if (action === 'remove') delete members[target];
                if (action === 'status') {
                  const status = normalize(data.status);
                  if (!['active','on_hold','temporarily_off','inactive'].includes(status)) throw new HttpsError('invalid-argument','Invalid membership status.');
                  subject.Status = status; delete subject.status;
                }
              }
            }
          }
        }
        affected = Object.keys(members).concat(uid,target);
      }
      current._membershipOperations ||= {};
      current._membershipOperations[receiptKey] = now;
      trimLedger(current._membershipOperations);
      affected = Object.keys(current.Members_band || {}).concat(uid,target);
      return current;
    } catch (error) { failure = error; return; }
  }, undefined, false);
  if (failure) throw failure;
  if (!result.committed) {
    if (['delete','departAccount'].includes(action) && !result.snapshot.exists()) return { success:true, bandId };
    throw new HttpsError('aborted','Membership changed; retry the operation.');
  }
  if (!result.snapshot.exists() && !['delete','departAccount'].includes(action)) throw new HttpsError('not-found','Band not found.');
  await reconcileBand(db,bandId,affected);
  if (deleted) await db.ref().update({ [`membershipMutationOperations/${bandId}`]:null, [`bandconversations/${bandId}`]:null, [`bandSectionConversations/${bandId}`]:null });
  return { success:true, bandId };
}
module.exports = { normalize, role, manager, leader, key, bandKey, canonicalField, requireManager, authorizeRequest, authorizeMapPin, mutate, metadataFields };
