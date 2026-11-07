'use strict';

const crypto = require('node:crypto');
const {Readable} = require('node:stream');
const {pipeline} = require('node:stream/promises');
const {HttpsError} = require('firebase-functions/v2/https');
const authority = require('./membership_authority');
const {validMember} = require('./band_membership_index');

const CHUNK_BYTES = 4 * 1024 * 1024;
const SESSION_MS = 60 * 60 * 1000;
const objectId = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const denied = () => { throw new HttpsError('permission-denied', 'Media access denied.'); };

async function authorize(db, uid, record, action) {
  if (!uid || !record || !['band', 'map'].includes(record.kind)) denied();
  if (record.kind === 'band') {
    authority.bandKey(record.bandId);
    const member = (await db.ref(`Bands/${record.bandId}/Members_band/${uid}`).get()).val();
    const aliasesAgree = !(member?.Status != null && member?.status != null &&
      authority.normalize(member.Status) !== authority.normalize(member.status));
    if (!validMember(member) || !aliasesAgree) denied();
    if (action === 'delete' && record.ownerId !== uid && !authority.manager(member)) denied();
    if (action === 'write' && record.ownerId !== uid) denied();
    return;
  }
  await authority.authorizeMapPin(db, uid, {
    CreatorUserId: record.ownerId,
    ...(record.bandId == null ? {} : {BandId: record.bandId}),
  });
  if (action === 'read' && record.ownerId !== uid) denied();
}

async function publicMap(db, id, record) {
  if (record?.kind !== 'map' || !record.pinId) return false;
  const pin = (await db.ref(`SubRequests/${record.pinId}`).get()).val();
  return pin?.NotificationMode === 'map_pin' && pin?.MediaObjectId === id &&
    ['open', 'active', 'published'].includes(String(pin.Status || '').toLowerCase());
}

// Binding is committed in the same multi-location write as the canonical pin.
// An opaque upload ID never authorizes publication by itself.
async function bindMap(db, uid, pinId, bandId, value, projectId) {
  if (typeof value !== 'string') return null;
  let id = value.startsWith('secure-media:') ? value.slice(13) : null;
  const base = `https://europe-west1-${projectId}.cloudfunctions.net/storageMedia`;
  if (!id && value.startsWith(base)) {
    const url = new URL(value);
    if (url.origin + url.pathname !== base) denied();
    id = url.searchParams.get('id');
  }
  if (!id) return null; // Existing externally hosted public media remains supported.
  if (!objectId(id)) denied();
  const record = (await db.ref(`storageMediaObjects/${id}`).get()).val();
  if (record?.kind !== 'map' || record.state !== 'ready' ||
      (record.bandId ?? null) !== (bandId ?? null) ||
      (record.pinId && record.pinId !== pinId)) denied();
  await authorize(db, uid, record, 'delete');
  if (!record.pinId && record.ownerId !== uid) denied();
  return {id, url:`${base}?id=${id}`, path:`storageMediaObjects/${id}/pinId`};
}

async function begin(db, uid, data) {
  if (!uid || !data || !['band', 'map'].includes(data.kind)) denied();
  if (typeof data.fileName !== 'string' || !data.fileName.trim() ||
      data.fileName.length > 255 || /[\x00-\x1f]/.test(data.fileName) ||
      !Number.isSafeInteger(data.byteLength) || data.byteLength <= 0 ||
      typeof data.contentType !== 'string' || !/^[\w.+-]+\/[\w.+-]+$/.test(data.contentType)) {
    throw new HttpsError('invalid-argument', 'Invalid media upload.');
  }
  const id = crypto.randomBytes(16).toString('hex');
  const record = {kind:data.kind, ownerId:uid, bandId:data.bandId ?? null,
    fileName:data.fileName, contentType:data.contentType, byteLength:data.byteLength,
    expiresAt:Date.now() + SESSION_MS, state:'uploading'};
  await authorize(db, uid, record, 'write');
  await db.ref(`storageUploadSessions/${id}`).set(record);
  return {id, chunkBytes:CHUNK_BYTES};
}

async function session(db, uid, id) {
  if (!objectId(id)) denied();
  const record = (await db.ref(`storageUploadSessions/${id}`).get()).val();
  if (!record || record.ownerId !== uid || record.expiresAt <= Date.now()) denied();
  await authorize(db, uid, record, 'write');
  return record;
}

async function part(db, bucket, uid, id, index, bytes) {
  const record = await session(db, uid, id);
  const count = Math.ceil(record.byteLength / CHUNK_BYTES);
  if (record.state !== 'uploading' || !Number.isSafeInteger(index) || index < 0 || index >= count ||
      bytes.length !== Math.min(CHUNK_BYTES, record.byteLength - index * CHUNK_BYTES)) {
    throw new HttpsError('invalid-argument', 'Invalid upload part.');
  }
  const hash = crypto.createHash('sha256').update(bytes).digest('hex');
  const previous = record.parts?.[index];
  if (previous && previous.hash !== hash) {
    throw new HttpsError('failed-precondition', 'Upload part changed.');
  }
  // Content addressing makes retried and concurrent identical parts immutable.
  await bucket.file(`privateMediaParts/${id}/${index}_${hash}`).save(bytes, {resumable:false});
  const result = await db.ref(`storageUploadSessions/${id}/parts/${index}`).transaction(
    current => current && current.hash !== hash ? undefined : {hash, size:bytes.length});
  if (!result.committed) throw new HttpsError('failed-precondition', 'Upload part changed.');
}

async function finish(db, bucket, uid, id) {
  const record = await session(db, uid, id);
  const ready = (await db.ref(`storageMediaObjects/${id}`).get()).val();
  if (ready) return {id};
  const count = Math.ceil(record.byteLength / CHUNK_BYTES);
  if (Object.keys(record.parts || {}).length !== count) {
    throw new HttpsError('failed-precondition', 'Upload is incomplete.');
  }
  const lease = crypto.randomBytes(16).toString('hex');
  const lock = await db.ref(`storageUploadSessions/${id}/lease`).transaction(current =>
    current && current.expiresAt > Date.now() ? undefined : {id:lease, expiresAt:Date.now()+SESSION_MS});
  if (!lock.committed) throw new HttpsError('aborted', 'Upload finalization is in progress.');
  const path = `privateMedia/${id}/${lease}`;
  try {
    async function* chunks() {
      for (let index = 0; index < count; index++) {
        const info = record.parts[index];
        if (!info || info.size !== Math.min(CHUNK_BYTES, record.byteLength-index*CHUNK_BYTES)) {
          throw new HttpsError('failed-precondition', 'Upload is incomplete.');
        }
        yield* bucket.file(`privateMediaParts/${id}/${index}_${info.hash}`).createReadStream();
      }
    }
    await pipeline(Readable.from(chunks()), bucket.file(path).createWriteStream({
      resumable:false, metadata:{contentType:record.contentType, cacheControl:'private, no-store'},
    }));
    await authorize(db, uid, record, 'write');
    const current = (await db.ref(`storageUploadSessions/${id}/lease`).get()).val();
    if (current?.id !== lease) throw new HttpsError('aborted', 'Upload lease changed.');
    const {parts, lease:unusedLease, ...metadata} = record;
    await db.ref(`storageMediaObjects/${id}`).set({...metadata, path, state:'ready'});
    // A completed upload is immutable; retries return its ready object. Parts
    // are implementation intermediates, not retained copies of private files.
    await db.ref(`storageUploadSessions/${id}/state`).set('ready');
    for (const [index, info] of Object.entries(parts)) {
      await bucket.file(`privateMediaParts/${id}/${index}_${info.hash}`).delete({ignoreNotFound:true});
    }
    return {id};
  } finally {
    await db.ref(`storageUploadSessions/${id}/lease`).transaction(value => value?.id === lease ? null : undefined);
  }
}

async function readable(db, uid, id) {
  if (!objectId(id)) denied();
  const record = (await db.ref(`storageMediaObjects/${id}`).get()).val();
  if (!record || record.state !== 'ready') denied();
  if (!await publicMap(db, id, record)) await authorize(db, uid, record, 'read');
  return record;
}

function handler(admin) {
  return async (request, response) => {
    try {
      const db = admin.database();
      const bucket = admin.storage().bucket();
      const bearer = request.get('authorization');
      const uid = bearer?.startsWith('Bearer ')
        ? (await admin.auth().verifyIdToken(bearer.slice(7), true)).uid : null;
      const id = request.query.id;
      const action = request.query.action;
      response.set('Cache-Control', 'private, no-store');
      if (request.method === 'GET' || request.method === 'HEAD') {
        const record = await readable(db, uid, id);
        if (action === 'metadata') {
          response.json({byteLength:record.byteLength, contentType:record.contentType});
          return;
        }
        response.type(record.contentType);
        response.set('Accept-Ranges', 'bytes');
        response.set('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(record.fileName)}`);
        if (request.method === 'HEAD') {
          response.set('Content-Length', String(record.byteLength));response.end();return;
        }
        let start = 0, end = record.byteLength - 1;
        const range = request.get('range');
        if (range) {
          const match = /^bytes=(\d*)-(\d*)$/.exec(range);
          if (!match || (!match[1] && !match[2])) {
            response.status(416).end();return;
          }
          if (!match[1]) start = Math.max(0, record.byteLength - Number(match[2]));
          else {
            start = Number(match[1]);
            if (match[2]) end = Math.min(end, Number(match[2]));
          }
          if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= record.byteLength) {
            response.set('Content-Range',`bytes */${record.byteLength}`);response.status(416).end();return;
          }
        }
        // Stay below the Functions streaming response ceiling. Audio clients
        // use byte ranges; private file downloads explicitly fetch each chunk.
        end = Math.min(end, start + CHUNK_BYTES - 1);
        if (range || end < record.byteLength - 1) {
          response.status(206).set('Content-Range',`bytes ${start}-${end}/${record.byteLength}`);
        }
        response.set('Content-Length',String(end-start+1));
        await pipeline(bucket.file(record.path).createReadStream({start,end}), response);
        return;
      }
      if (!uid) denied();
      if (request.method === 'POST' && action === 'begin') {
        response.json(await begin(db, uid, request.body));
      } else if (request.method === 'PUT' && action === 'part') {
        await part(db, bucket, uid, id, Number(request.query.index), request.rawBody);
        response.json({success:true});
      } else if (request.method === 'POST' && action === 'finish') {
        response.json(await finish(db, bucket, uid, id));
      } else if (request.method === 'POST' && action === 'register-band-file') {
        const record = await readable(db, uid, id);
        if (record.kind !== 'band' || record.ownerId !== uid || record.bandId !== request.body?.bandId) denied();
        const category = request.body?.category;
        if (typeof category !== 'string' || category.length > 100) denied();
        await db.ref(`files/${record.bandId}/${id}`).transaction(current => current || {
          FileName:record.fileName, FileUrl:`secure-media:${id}`, UploadedBy:uid,
          UploadedAt:Date.now(), Category:category,
        });
        response.json({success:true});
      } else if (request.method === 'DELETE' && objectId(id)) {
        const record = (await db.ref(`storageMediaObjects/${id}`).get()).val();
        if (request.query.bandId != null && record?.bandId !== request.query.bandId) denied();
        await authorize(db, uid, record, 'delete');
        await db.ref(`storageMediaObjects/${id}/state`).set('deleting');
        await bucket.file(record.path).delete({ignoreNotFound:true});
        const updates = {[`storageMediaObjects/${id}`]:null};
        if (record.kind === 'band') updates[`files/${record.bandId}/${id}`] = null;
        await db.ref().update(updates);
        response.json({success:true});
      } else {
        response.status(400).json({error:'Invalid media request.'});
      }
    } catch (error) {
      if (response.headersSent) { response.destroy(); return; }
      const status = error?.code === 'invalid-argument' ? 400 :
        ['permission-denied','unauthenticated'].includes(error?.code) ? 403 : 409;
      response.status(status).json({error:'Media operation unavailable for your current access.'});
    }
  };
}

module.exports = {CHUNK_BYTES, authorize, publicMap, bindMap, begin, part, finish, readable, handler};
