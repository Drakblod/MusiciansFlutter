const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const jwt = require('jsonwebtoken');

/**
 * Server-side LiveKit configuration.
 * Kept strictly on the backend via environment variables / Firebase params.
 * NEVER exposed to mobile clients.
 */
function getLiveKitConfig() {
  return {
    apiKey: process.env.LIVEKIT_API_KEY || 'APIQ97KxhUGgXdz',
    apiSecret: process.env.LIVEKIT_API_SECRET || 'CVV6TkKaA5iBIgMRdbkdaLmrnDl8s1KcIOBUg1D5nOA',
    serverUrl: process.env.LIVEKIT_URL || 'wss://musiciansapp-b9yg950s.livekit.cloud',
  };
}

/**
 * Generates an authoritative LiveKit access token with strict grants.
 *
 * - Publishers: microphone-only audio publishing, no video or screen-share allowed.
 * - Listeners: subscribe-only, publishing strictly disabled.
 */
function createAuthoritativeLiveKitToken({ identity, roomName, role, userName }) {
  const config = getLiveKitConfig();

  const isPublisher = role === 'publisher';

  const videoGrant = {
    room: roomName,
    roomJoin: true,
    canPublish: isPublisher,
    // Restrict publishing exclusively to microphone (audio-only)
    canPublishSources: isPublisher ? ['microphone'] : [],
    canPublishData: false,
    canSubscribe: true,
    roomRecord: false,
    roomAdmin: false,
  };

  const payload = {
    iss: config.apiKey,
    sub: identity,
    name: userName || identity,
    video: videoGrant,
  };

  // 6 hour expiration for live session tokens
  const token = jwt.sign(payload, config.apiSecret, {
    algorithm: 'HS256',
    expiresIn: '6h',
    notBefore: '-10s',
  });

  return {
    token,
    serverUrl: config.serverUrl,
  };
}

/**
 * Callable: startLiveBroadcast
 *
 * Verifies caller has an active Leader or Admin membership in the specified band,
 * creates an active broadcast record at /LiveBroadcasts/{broadcastId},
 * and returns a publisher token restricted to microphone audio.
 */
const startLiveBroadcast = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be signed in to start a live broadcast.');
  }

  const callerUid = request.auth.uid;
  const { bandId, title, latitude, longitude, description, genre } = request.data || {};

  if (!bandId || typeof bandId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid bandId is required.');
  }

  const db = admin.database();

  // 1. Check band existence
  const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');
  if (!bandSnap.exists()) {
    throw new HttpsError('not-found', `Band ${bandId} not found.`);
  }
  const bandData = bandSnap.val() || {};

  // 2. Authoritative band membership check
  const memberSnap = await db.ref(`/Bands/${bandId}/Members_band/${callerUid}`).once('value');
  if (!memberSnap.exists()) {
    throw new HttpsError('permission-denied', 'You are not a member of this band.');
  }

  const memberData = memberSnap.val() || {};
  const memberStatus = (memberData.Status || memberData.status || 'active').toLowerCase();
  if (memberStatus === 'on_hold' || memberStatus === 'temporarily_off' || memberStatus === 'inactive') {
    throw new HttpsError('permission-denied', 'Members on hold cannot start live broadcasts.');
  }

  const memberRole = (memberData.Role || memberData.role || '').toLowerCase();
  const isLeaderOrAdmin = memberRole === 'leader' || memberRole === 'admin';
  if (!isLeaderOrAdmin) {
    throw new HttpsError('permission-denied', 'Only band Leaders or Admins can start live broadcasts.');
  }

  // 3. Resolve caller display name
  let callerName = memberData.Nickname || memberData.nickname;
  if (!callerName) {
    const userSnap = await db.ref(`/users/${callerUid}`).once('value');
    if (userSnap.exists()) {
      const uVal = userSnap.val() || {};
      callerName = uVal.name || uVal.username || 'Musician';
    }
  }

  const now = Date.now();
  const broadcastId = `broadcast_${bandId}_${now}`;
  const roomName = `room_${broadcastId}`;

  // 4. Create broadcast metadata in RTDB
  const broadcastPayload = {
    bandId,
    bandName: bandData.Name || bandData.name || 'Live Band',
    creatorUserId: callerUid,
    title: (title || 'Live Rehearsal Broadcast').toString().trim(),
    description: description ? description.toString().trim() : null,
    genre: genre || (Array.isArray(bandData.Genres) && bandData.Genres.length > 0 ? bandData.Genres[0] : null),
    location: bandData.Location || bandData.location || null,
    latitude: Number(latitude) || 0.0,
    longitude: Number(longitude) || 0.0,
    status: 'active',
    startedAt: now,
    endedAt: null,
    livekitRoomName: roomName,
    listenerCount: 0,
    audioOnly: true,
    hasActiveAudioTrack: true,
  };

  await db.ref(`/LiveBroadcasts/${broadcastId}`).set(broadcastPayload);

  // 5. Generate publisher token
  const tokenResult = createAuthoritativeLiveKitToken({
    identity: callerUid,
    roomName,
    role: 'publisher',
    userName: callerName,
  });

  return {
    broadcastId,
    roomName,
    token: tokenResult.token,
    serverUrl: tokenResult.serverUrl,
    role: 'publisher',
  };
});

/**
 * Callable: joinLiveBroadcast
 *
 * Verifies broadcast is active, increments listener count, and returns
 * a subscriber-only listener token.
 */
const joinLiveBroadcast = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be signed in to listen to a live broadcast.');
  }

  const callerUid = request.auth.uid;
  const { broadcastId } = request.data || {};

  if (!broadcastId || typeof broadcastId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid broadcastId is required.');
  }

  const db = admin.database();
  const bSnap = await db.ref(`/LiveBroadcasts/${broadcastId}`).once('value');
  if (!bSnap.exists()) {
    throw new HttpsError('not-found', 'Live broadcast not found.');
  }

  const bVal = bSnap.val() || {};
  if (bVal.status !== 'active') {
    throw new HttpsError('failed-precondition', 'This live broadcast is no longer active.');
  }

  // Increment listener count
  await db.ref(`/LiveBroadcasts/${broadcastId}/listenerCount`).transaction((count) => {
    return (count || 0) + 1;
  });

  // Resolve listener user name
  let userName = 'Listener';
  const userSnap = await db.ref(`/users/${callerUid}`).once('value');
  if (userSnap.exists()) {
    const uVal = userSnap.val() || {};
    userName = uVal.name || uVal.username || 'Listener';
  }

  const roomName = bVal.livekitRoomName || `room_${broadcastId}`;
  const tokenResult = createAuthoritativeLiveKitToken({
    identity: callerUid,
    roomName,
    role: 'listener',
    userName,
  });

  return {
    broadcastId,
    roomName,
    token: tokenResult.token,
    serverUrl: tokenResult.serverUrl,
    role: 'listener',
  };
});

/**
 * Callable: stopLiveBroadcast
 *
 * Verifies caller is the original broadcaster or a band Leader/Admin,
 * and sets broadcast status to 'ended'.
 */
const stopLiveBroadcast = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be signed in to stop a live broadcast.');
  }

  const callerUid = request.auth.uid;
  const { broadcastId } = request.data || {};

  if (!broadcastId || typeof broadcastId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid broadcastId is required.');
  }

  const db = admin.database();
  const bSnap = await db.ref(`/LiveBroadcasts/${broadcastId}`).once('value');
  if (!bSnap.exists()) {
    throw new HttpsError('not-found', 'Live broadcast not found.');
  }

  const bVal = bSnap.val() || {};
  if (bVal.status === 'ended') {
    return { success: true, broadcastId, alreadyEnded: true };
  }

  // Check authorization: creator or Leader/Admin
  const isCreator = bVal.creatorUserId === callerUid;
  let isAuthorized = isCreator;

  if (!isAuthorized && bVal.bandId) {
    const memberSnap = await db.ref(`/Bands/${bVal.bandId}/Members_band/${callerUid}`).once('value');
    if (memberSnap.exists()) {
      const mVal = memberSnap.val() || {};
      const role = (mVal.Role || mVal.role || '').toLowerCase();
      if (role === 'leader' || role === 'admin') {
        isAuthorized = true;
      }
    }
  }

  if (!isAuthorized) {
    throw new HttpsError('permission-denied', 'Only the broadcaster or band leader can stop this live broadcast.');
  }

  const now = Date.now();
  await db.ref(`/LiveBroadcasts/${broadcastId}`).update({
    status: 'ended',
    endedAt: now,
  });

  return {
    success: true,
    broadcastId,
    status: 'ended',
    endedAt: now,
  };
});

module.exports = {
  startLiveBroadcast,
  joinLiveBroadcast,
  stopLiveBroadcast,
  createAuthoritativeLiveKitToken,
};
