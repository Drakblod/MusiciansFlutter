'use strict';

const { createHash, randomUUID, timingSafeEqual } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { HttpsError } = require('firebase-functions/v2/https');

const digest = value => createHash('sha256').update(value).digest('hex');
const registryPath = 'notificationTokenRegistry';
const feedPath = 'notificationFeedV2';
const routesPath = 'notificationRoutesV2';
const signalPath = 'notificationFeedSignals';
const nativeTitles = new Map([
  ['sub_request_invite', 'Substitute Request'],
  ['grouped_sub_request', 'Substitute Request'],
  ['sub_request_response', 'Substitute Request Response'],
  ['event_invite', 'Event Request'],
  ['event_reminder', 'Event Request'],
  ['event_ready_to_finalize', 'Event Ready to Finalize'],
  ['gig_finalized', 'Gig Confirmed'],
  ['session_application', 'Collab Application'],
  ['session_application_status', 'Collab Application Update'],
  ['band_section_chat', 'New Band Message'],
]);
const soundProfiles = new Set(['android-v2', 'ios-v2']);
const sounds = new Map([
  ['request', ['gig_rquest', 'gig_request_channel', 'notification_gig_request_v2']],
  ['response', ['gig_rquest_response', 'gig_response_channel', 'notification_gig_response_v2']],
  ['event', ['reminder_rsvp', 'rsvp_reminder_channel', 'notification_event_rsvp_v2']],
  ['confirmed', ['finalized_gig', 'finalized_gig_channel', 'notification_gig_confirmed_v2']],
]);
const notificationSounds = new Map([
  ['sub_request_invite', 'request'],
  ['grouped_sub_request', 'request'],
  ['sub_request_response', 'response'],
  ['session_application', 'response'],
  ['session_application_status', 'response'],
  ['event_invite', 'event'],
  ['event_reminder', 'event'],
  ['event_threshold', 'event'],
  ['event_ready_to_finalize', 'event'],
  ['gig_finalized', 'confirmed'],
  ['band_section_chat', 'system'],
]);
const testSounds = new Map([
  ['gig_rquest', 'request'],
  ['gig_rquest_response', 'response'],
  ['reminder_rsvp', 'event'],
  ['reminder_24h', 'event'],
  ['reminder_48h', 'event'],
  ['reminder_72h', 'event'],
  ['reminder_final', 'event'],
  ['reminder_last', 'event'],
  ['finalized_gig', 'confirmed'],
]);

function soundPlatform(profile, cue) {
  const selected = sounds.get(cue);
  if (!selected) {
    return {
      sound: 'default',
      // A legacy Android installation has no known system-sound channel.
      channelId: profile === 'android-v2' ? 'chat_notifications_v2' : undefined,
      apnsSound: 'default',
    };
  }
  const [legacySound, channelId, v2Sound] = selected;
  return {
    sound: profile === 'android-v2' ? v2Sound : legacySound,
    channelId: profile === 'android-v2' ? channelId + '_v2' : channelId,
    apnsSound: (profile === 'ios-v2' ? v2Sound : legacySound) + '.wav',
  };
}

function testSoundPlatform(soundType, profile) {
  return testSounds.has(soundType) ? soundPlatform(profile, testSounds.get(soundType)) : null;
}
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
  const ownerKey = digest(uid);
  const tokenHash = unregister ? null : digest(token);
  const soundProfile = soundProfiles.has(input?.soundProfile) ? input.soundProfile : null;
  const ref = db.ref(registryPath);
  // A cold transaction can first run with an empty local cache.
  await ref.child('installations').child(installation).get();
  const tx = await ref.transaction(current => {
    const state = current || {};
    if (state.revokedOwners?.[ownerKey]) return;
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
      : { uid, proofHash, sequence, token, tokenHash, ...(soundProfile ? { soundProfile } : {}) };
    if (tokenHash) {
      state.tokens[tokenHash] = installation;
      (state.owners[uid] ||= {})[installation] = true;
    }
    return state;
  });
  const state = tx.snapshot.val();
  if (state?.revokedOwners?.[ownerKey]) {
    if (unregister) return { success: false };
    throw new HttpsError('failed-precondition', 'Notification registration is unavailable.');
  }
  const binding = state?.installations?.[installation];
  // Identical retries succeed without replacing a newer binding.
  const replay = binding?.proofHash === proofHash && binding.sequence === sequence &&
    (unregister ? !binding.uid : binding.uid === uid && binding.tokenHash === tokenHash &&
      (binding.soundProfile || null) === soundProfile);
  if (!unregister && !tx.committed && !replay) {
    throw new HttpsError('failed-precondition', 'Notification registration is unavailable.');
  }
  return { success: tx.committed || replay };
}

function removeAssociation(state, installation, binding) {
  if (binding?.tokenHash && state.tokens?.[binding.tokenHash] === installation) {
    delete state.tokens[binding.tokenHash];
  }
  const owner = state.owners?.[binding?.uid];
  if (owner) delete owner[installation];
}

async function revokeAccount(db, uid) {
  const registry = db.ref(registryPath);
  const ownerKey = digest(uid);
  await registry.transaction(current => {
    const state = current || {};
    (state.revokedOwners ||= {})[ownerKey] = true;
    for (const [installation, binding] of Object.entries(state.installations || {})) {
      if (binding.uid !== uid) continue;
      removeAssociation(state, installation, binding);
      // Retain the proof and last generation so the next owner can reuse
      // this installation without accepting stale requests.
      state.installations[installation] = {
        proofHash: binding.proofHash, sequence: binding.sequence,
      };
    }
    if (state.owners) delete state.owners[uid];
    return state;
  });
}

async function isAccountRevoked(db, uid) {
  return (await db.ref(`${registryPath}/revokedOwners/${digest(uid)}`).get()).exists();
}

// Use the same service identity with a restricted Database auth override.
// RTDB checks revocation at commit, including writes from an interrupted sender.
async function withNotificationWriter(db, uid, write) {
  if (await isAccountRevoked(db, uid)) return undefined;
  const app = initializeApp({
    ...db.app.options,
    databaseAuthVariableOverride: {
      uid, token: { notificationV2Writer: true, ownerKey: digest(uid) },
    },
  }, 'notification-writer-' + randomUUID());
  try {
    return await write(getDatabase(app));
  } catch (error) {
    if (/^permission[_ -]denied$/i.test(error.code || error.message || '') &&
        await isAccountRevoked(db, uid)) return undefined;
    throw error;
  } finally {
    await deleteApp(app);
  }
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
  return {
    installation, userId: row.uid, sequence: row.sequence, token: row.token,
    soundProfile: row.soundProfile,
  };
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

function messageFor(recipient, id, type, soundTest) {
  const cue = type === 'sound_test' ? testSounds.get(soundTest) : notificationSounds.get(type);
  const { sound, channelId, apnsSound } = soundPlatform(recipient.soundProfile, cue);
  return {
    token: recipient.token,
    notification: {
      title: nativeTitles.get(type) ?? 'New activity in Musicians',
      body: 'Open the app to view details.',
    },
    data: { schemaVersion: '2', notificationId: id, type },
    android: { notification: {
      sound,
      ...(channelId ? { channelId } : {}),
    } },
    apns: { payload: { aps: { sound: apnsSound } } },
  };
}

async function deliver(db, messaging, recipient, id, type, soundTest, canPublish) {
  if (canPublish && !await canPublish()) return { success: false, superseded: true };
  if (!(await stillCurrent(db, recipient))) return { success: false, superseded: true };
  // A missing channel on an older Android client falls back to the guitar.
  // Bindings that predate sound profiles cannot distinguish Android from iOS.
  if (type === 'band_section_chat' && !soundProfiles.has(recipient.soundProfile)) {
    return { success: false, noCompatibleSound: true };
  }
  try {
    const messageId = await messaging.send(messageFor(recipient, id, type, soundTest));
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
    if (!(await stillCurrent(db, recipient))) return { success: false, superseded: true };
    const written = await withNotificationWriter(db, recipient.userId, async writer => {
      await writer.ref(`${routesPath}/${recipient.userId}/${id}`).set({ type, ...route });
      return true;
    });
    if (!written) return { success: false, superseded: true };
  }
  return deliver(db, messaging, recipient, id, type, message.data?.soundType);
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
async function publish(db, messaging, uid, type, key, route, {
  suppressPush = false, writeAsRecipient = withNotificationWriter, canPublish,
} = {}) {
  const id = notificationId(uid, type, key);
  const result = await writeAsRecipient(db, uid, async writer => {
    if (canPublish && !await canPublish()) return null;
    const claimRef = writer.ref(`${routesPath}/${uid}/${id}`);
    const claim = await claimRef.transaction(current =>
      current ? undefined : { type, ...route, createdAt: Date.now(), dispatchState: 'claimed' });
    const createdAt = claim.snapshot.val()?.createdAt;
    if (!createdAt) return null;
    const feed = await writer.ref(`${feedPath}/${uid}/${id}`).transaction(current =>
      current ? undefined : { type, createdAt, isRead: false });
    if (feed.committed || claim.committed) await writer.ref(`${signalPath}/${uid}`).set(id);
    if (!claim.committed) return { id, duplicate: true };
    if (suppressPush) {
      await claimRef.child('dispatchState').set('legacy-delivery');
      return { id, results: [] };
    }
    if (!notificationSounds.has(type)) {
      await claimRef.child('dispatchState').set('feed-only');
      return { id, results: [] };
    }
    const destinations = await recipients(db, [uid]);
    const results = await Promise.all(destinations.map(recipient =>
      deliver(db, messaging, recipient, id, type, undefined, canPublish)));
    const dispatchState = results.some(result => result.success) ? 'sent' :
      results.some(result => result.error) ? 'undelivered-or-unknown' :
      results.some(result => result.noCompatibleSound) ? 'no-compatible-sound' : 'no-current-installation';
    await claimRef.child('dispatchState').set(dispatchState);
    return { id, results };
  });
  return result ?? null;
}

module.exports = {
  changeBinding, recipients, stillCurrent, removeInvalid, messageFor, deliver, publish,
  dispatchRegistered, routingData, revokeAccount, isAccountRevoked, withNotificationWriter,
  testSoundPlatform,
  safeKey, feedPath, routesPath, signalPath,
};
