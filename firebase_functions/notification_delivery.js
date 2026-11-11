'use strict';

const { createHash, timingSafeEqual } = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');

const digest = value => createHash('sha256').update(value).digest('hex');
const registryPath = 'notificationTokenRegistry';
const feedPath = 'notificationFeedV2';
const routesPath = 'notificationRoutesV2';
const signalPath = 'notificationFeedSignals';
const neutralAlert = Object.freeze({
  title: 'New activity in Musicians',
  body: 'Open the app to view details.',
});
const safeKey = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 240 && !/[.#$\[\]/\u0000-\u001f\u007f]/.test(value) &&
  !['__proto__', 'constructor', 'prototype'].includes(value);
const isTokenError = code => [
  'messaging/invalid-registration-token', 'messaging/registration-token-not-registered',
].includes(code);

async function changeBinding(db, uid, input, unregister = false) {
  const { accountUid, installation, proof, sequence, token } = input || {};
  if (accountUid !== uid) {
    throw new HttpsError('permission-denied', 'Notification account changed.');
  }
  if (typeof installation !== 'string' || !/^[a-f0-9]{32}$/.test(installation) ||
      typeof proof !== 'string' || !/^[a-f0-9]{64}$/.test(proof) ||
      !Number.isSafeInteger(sequence) || sequence < 1 ||
      (!unregister && (typeof token !== 'string' || !/^\S{16,4096}$/.test(token)))) {
    throw new HttpsError('invalid-argument', 'Invalid notification registration.');
  }
  const proofHash = digest(proof);
  const tokenHash = unregister ? null : digest(token);
  const ref = db.ref(registryPath);
  // A cold transaction can first run with an empty local cache.
  await ref.child('installations').child(installation).get();
  const tx = await ref.transaction(current => {
    const state = current || {};
    state.installations ||= {};
    state.tokens ||= {};
    state.owners ||= {};
    const previous = state.installations[installation];
    if (previous && (!/^[a-f0-9]{64}$/.test(previous.proofHash) ||
        !timingSafeEqual(Buffer.from(proofHash), Buffer.from(previous.proofHash)))) return;
    if (unregister && !previous) return state;
    if (unregister && previous.uid !== uid) return;
    if (previous && sequence <= previous.sequence) return;
    if (tokenHash && state.tokens[tokenHash] && state.tokens[tokenHash] !== installation) return;
    removeAssociation(state, installation, previous);
    state.installations[installation] = unregister
      ? { proofHash, sequence }
      : { uid, proofHash, sequence, token, tokenHash };
    if (tokenHash) {
      state.tokens[tokenHash] = installation;
      (state.owners[uid] ||= {})[installation] = true;
    }
    return state;
  });
  const binding = tx.snapshot.val()?.installations?.[installation];
  // Identical retries succeed without replacing a newer binding.
  const replay = binding?.proofHash === proofHash && binding.sequence === sequence &&
    (unregister ? !binding.uid : binding.uid === uid && binding.tokenHash === tokenHash);
  if (!unregister && !tx.committed && !replay) {
    throw new HttpsError('failed-precondition', 'Notification registration is unavailable.');
  }
  return { success: tx.committed || replay };
}

function removeAssociation(state, installation, binding) {
  if (binding?.tokenHash) delete state.tokens[binding.tokenHash];
  const owner = state.owners?.[binding?.uid];
  if (owner) delete owner[installation];
}

async function recipients(db, uids) {
  const registry = db.ref(registryPath);
  const installations = registry.child('installations');
  if (!uids) {
    const all = (await installations.get()).val() || {};
    return Object.entries(all).filter(([, row]) => row.uid && row.token)
      .map(([installation, row]) => destination(installation, row));
  }
  const groups = await Promise.all([...new Set(uids)].map(async uid => {
    const index = (await registry.child('owners').child(uid).get()).val() || {};
    return Promise.all(Object.keys(index).map(async installation => {
      const row = (await installations.child(installation).get()).val();
      return row?.uid === uid && row.token ? destination(installation, row) : null;
    }));
  }));
  return groups.flat().filter(Boolean);
}

function destination(installation, row) {
  return { installation, userId: row.uid, sequence: row.sequence, token: row.token };
}

async function stillCurrent(db, recipient) {
  const binding = (await db.ref(`${registryPath}/installations/${recipient.installation}`).get()).val();
  return binding?.uid === recipient.userId && binding.sequence === recipient.sequence &&
    binding.token === recipient.token;
}

async function removeInvalid(db, recipient, error) {
  if (!isTokenError(error?.code)) return;
  await db.ref(registryPath).transaction(state => {
    const binding = state?.installations?.[recipient.installation];
    if (binding?.uid !== recipient.userId || binding.sequence !== recipient.sequence ||
        binding.token !== recipient.token) return;
    removeAssociation(state, recipient.installation, binding);
    state.installations[recipient.installation] = {
      proofHash: binding.proofHash, sequence: binding.sequence,
    };
    return state;
  });
}

function messageFor(message, id, type) {
  const androidSound = message.android?.notification?.sound;
  const channelId = message.android?.notification?.channelId;
  const apnsSound = message.apns?.payload?.aps?.sound;
  return {
    token: message.token,
    notification: neutralAlert,
    data: { schemaVersion: '2', notificationId: id, type },
    ...(androidSound || channelId ? { android: { notification: {
      ...(androidSound ? { sound: androidSound } : {}),
      ...(channelId ? { channelId } : {}),
    } } } : {}),
    ...(apnsSound ? { apns: { payload: { aps: { sound: apnsSound } } } } : {}),
  };
}

async function deliver(db, messaging, recipient, message, id, type) {
  if (!(await stillCurrent(db, recipient))) return { success: false, superseded: true };
  try {
    const messageId = await messaging.send(messageFor({ ...message, token: recipient.token }, id, type));
    return { success: true, messageId };
  } catch (error) {
    await removeInvalid(db, recipient, error);
    return { success: false, error: { code: error?.code || 'messaging/unknown' } };
  }
}

const notificationId = (uid, type, key) => digest(JSON.stringify([uid, type, key]));

async function dispatchRegistered(db, messaging, recipient, message) {
  const { type, ...route } = routingData(message.data);
  const id = notificationId(recipient.userId, type, route);
  if (Object.keys(route).length) {
    await db.ref(`${routesPath}/${recipient.userId}/${id}`).set({ type, ...route });
  }
  return deliver(db, messaging, recipient, message, id, type);
}

function routingData(data) {
  const safe = {};
  for (const key of ['type', 'bandId', 'eventId', 'subRequestId', 'conversationId', 'sessionId', 'fileId']) {
    if (safeKey(data?.[key])) safe[key] = data[key];
  }
  safe.type ||= 'system';
  return safe;
}

// The private route doubles as the permanent delivery claim. No retry can
// redispatch after an ambiguous provider result or an interrupted invocation.
async function publish(db, messaging, uid, type, key, route, platform, { suppressPush = false } = {}) {
  const id = notificationId(uid, type, key);
  const claimRef = db.ref(`${routesPath}/${uid}/${id}`);
  const claim = await claimRef.transaction(current =>
    current ? undefined : { type, ...route, createdAt: Date.now(), dispatchState: 'claimed' });
  const createdAt = claim.snapshot.val()?.createdAt;
  if (!createdAt) return null;
  const feed = await db.ref(`${feedPath}/${uid}/${id}`).transaction(current =>
    current ? undefined : { type, createdAt, isRead: false });
  if (feed.committed || claim.committed) await db.ref(`${signalPath}/${uid}`).set(id);
  if (!claim.committed) return { id, duplicate: true };
  if (suppressPush) {
    await claimRef.child('dispatchState').set('legacy-delivery');
    return { id, results: [] };
  }
  if (!platform) {
    await claimRef.child('dispatchState').set('feed-only');
    return { id, results: [] };
  }
  const destinations = await recipients(db, [uid]);
  const results = await Promise.all(destinations.map(recipient =>
    deliver(db, messaging, recipient, platform, id, type)));
  const dispatchState = results.some(result => result.success) ? 'sent' :
    results.some(result => result.error) ? 'undelivered-or-unknown' : 'no-current-installation';
  await claimRef.child('dispatchState').set(dispatchState);
  return { id, results };
}

module.exports = {
  changeBinding, recipients, stillCurrent, removeInvalid, messageFor, deliver, publish,
  dispatchRegistered, routingData,
  safeKey, feedPath, routesPath, signalPath,
};
