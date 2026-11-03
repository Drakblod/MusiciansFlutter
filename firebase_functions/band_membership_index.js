'use strict';

const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const validStatus = value => value == null || (typeof value === 'string' &&
  ['active', 'on_hold', 'temporarily_off'].includes(value.trim().toLowerCase()));
const validMember = member => record(member) && validStatus(member.Status ?? member.status);
const indexPath = (uid, bandId) => `userBandMembershipIndex/${uid}/${bandId}`;

// Always read current canonical state rather than trusting an old trigger snapshot.
// Canonical deletion events also clean entries after whole-band deletion.
async function reconcileMembershipIndex(db, bandId, uid) {
  const ref = db.ref(`Bands/${bandId}/Members_band/${uid}`);
  for (let attempt = 0; attempt < 10; attempt++) {
    const active = validMember((await ref.get()).val());
    await db.ref().update({ [indexPath(uid, bandId)]: active ? true : null });
    // An overlapping invocation can finish before this older write. Verify after
    // writing, so that older work cannot leave a restored member undiscoverable.
    if (validMember((await ref.get()).val()) === active) return;
  }
  throw new Error('Canonical membership kept changing; retry reconciliation');
}

function calculatePlan(bands = {}, existing = {}, cleanup = false) {
  const desired = {};
  const malformed = [];
  for (const bandId of Object.keys(bands).sort()) {
    const band = bands[bandId];
    if (!record(band) || !record(band.Members_band)) {
      malformed.push(`Bands/${bandId}/Members_band`);
      continue;
    }
    for (const uid of Object.keys(band.Members_band).sort()) {
      const member = band.Members_band[uid];
      if (!record(member) || !validStatus(member.Status ?? member.status)) {
        // Known non-member statuses are expected; unknown shapes/statuses need auditing.
        const status = member?.Status ?? member?.status;
        if (!['inactive', 'invited', 'removed', 'blocked', 'suspended'].includes(String(status).trim().toLowerCase())) {
          malformed.push(`Bands/${bandId}/Members_band/${uid}`);
        }
        continue;
      }
      desired[indexPath(uid, bandId)] = true;
    }
  }
  const updates = {};
  for (const path of Object.keys(desired).sort()) {
    const [, uid, bandId] = path.split('/');
    if (existing[uid]?.[bandId] !== true) updates[path] = true;
  }
  const stale = [];
  const missingBands = [];
  for (const uid of Object.keys(existing).sort()) {
    if (!record(existing[uid])) { malformed.push(`userBandMembershipIndex/${uid}`); continue; }
    for (const bandId of Object.keys(existing[uid]).sort()) {
      const path = indexPath(uid, bandId);
      if (!desired[path]) {
        stale.push(path);
        if (!Object.prototype.hasOwnProperty.call(bands, bandId)) missingBands.push(path);
        if (cleanup) updates[path] = null;
      }
    }
  }
  return { updates, desiredCount: Object.keys(desired).length, stale, missingBands, malformed: malformed.sort() };
}

module.exports = { validMember, validStatus, reconcileMembershipIndex, calculatePlan };
