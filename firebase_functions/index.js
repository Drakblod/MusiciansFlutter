const notificationDelivery = require('./notification_delivery');
const notificationAccess = require('./notification_access');
const { currentMember: notificationMember } = notificationAccess;
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { onValueCreated, onValueWritten } = require('firebase-functions/v2/database');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const crypto = require('crypto');
const membershipAuthority = require('./membership_authority');
const cityPlaces = require('./google_places_cities');
const cityGate = require('./city_verification');
const eventReadModels = require('./event_read_models');
const eventMutations = require('./event_mutations');
exports.storageMedia = onRequest({region:'europe-west1', cors:true, timeoutSeconds:540},
  require('./storage_media').handler(admin));
exports.mutateBandEvent = onCall({region:'europe-west1'},async request=>{
  if(!request.auth)throw new HttpsError('unauthenticated','Sign in first.');
  return eventMutations.mutate(admin.database(),request.auth.uid,request.data);
});
const cityPlacesKey = defineSecret('GOOGLE_PLACES_API_KEY');
const cityBody = (data,keys) => data && typeof data === 'object' && !Array.isArray(data) &&
  JSON.stringify(data).length <= 512 && Object.keys(data).every(key => keys.includes(key)) &&
  keys.every(key => Object.hasOwn(data,key));
exports.startCatalogueCitySession = onCall({region:'europe-west1',secrets:[cityPlacesKey]},request=>{
  if(!request.auth)throw new HttpsError('unauthenticated','Sign in first.');
  if(!cityBody(request.data||{},[]))throw new HttpsError('invalid-argument','Invalid city session.');
  return {sessionToken:cityGate.createToken(request.auth.uid,cityPlacesKey.value())};
});
exports.searchCatalogueCities = onCall({region:'europe-west1',secrets:[cityPlacesKey]}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated','Sign in first.');
  if(!cityBody(request.data,['query','sessionToken']))throw new HttpsError('invalid-argument','Invalid city search.');
  const {query,sessionToken} = request.data;
  if (typeof query !== 'string' || query.trim().length < 2 || query.trim().length > 100 ||
      !cityPlaces.token(sessionToken)) throw new HttpsError('invalid-argument','Invalid city search.');
  const db=admin.database(),uid=request.auth.uid;
  cityGate.validateToken(sessionToken,uid,cityPlacesKey.value());
  const lease=await cityGate.reserveRate(db,uid);
  try {
    const hash=await cityGate.searchSession(db,uid,sessionToken);
    const candidates=await cityPlaces.search(query,sessionToken,cityPlacesKey.value());
    await cityGate.rememberPredictions(db,uid,hash,candidates.map(x=>x.placeId));
    return {candidates};
  } catch(error) {
    if(error instanceof HttpsError)throw error;
    throw new HttpsError(error?.code==='quota'?'resource-exhausted':'unavailable',
      'City search is temporarily unavailable.');
  } finally {await cityGate.releaseRate(db,lease);}
});
exports.resolveCatalogueCity = onCall({region:'europe-west1',secrets:[cityPlacesKey]}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated','Sign in first.');
  if(!cityBody(request.data,['placeId','sessionToken','purpose','targetId','city','country']))
    throw new HttpsError('invalid-argument','Invalid city selection.');
  const {placeId,sessionToken,purpose,targetId,city,country} = request.data;
  if (!cityPlaces.token(sessionToken) || typeof placeId !== 'string' || placeId.length > 200)
    throw new HttpsError('invalid-argument','Invalid city selection.');
  cityGate.scope(purpose,targetId,request.auth.uid);
  const names=cityGate.authored(city,country);
  const db=admin.database(),uid=request.auth.uid;
  cityGate.validateToken(sessionToken,uid,cityPlacesKey.value());
  if(purpose==='band') {
    const exists=(await db.ref(`Bands/${targetId}`).get()).exists();
    if(exists)await membershipAuthority.requireManager(db,targetId,uid);
  }
  const lease=await cityGate.reserveRate(db,uid);
  try {
    await cityGate.closeSessionForDetails(db,uid,sessionToken,placeId);
    const provider=await cityPlaces.resolve(placeId,sessionToken,cityPlacesKey.value());
    if(!provider||!cityGate.same(provider.city,names.city)||!cityGate.same(provider.country,names.country)) {
      logger.warn('City confirmation rejected', {
        category:provider?'city-country-mismatch':'unverifiable-place-details',
      });
      throw new HttpsError('failed-precondition','City and country must match the selected place.');
    }
    const grant=await cityGate.issueGrant(db,uid,purpose,targetId,placeId,names.city,names.country);
    return {...grant,attributions:provider.attributions||[]};
  } catch(error) {
    if(error instanceof HttpsError)throw error;
    throw new HttpsError(error?.code==='quota'?'resource-exhausted':'unavailable',
      'City selection is temporarily unavailable.');
  } finally {await cityGate.releaseRate(db,lease);}
});
const profileTextFields = new Set(['DisplayName','Level','About','Contact','History','Projects',
  'ProfilePictureUrl','SpotifyUrl','YoutubeUrl','AudioSnippetUrl','CollabBio','MainInstrument',
  'UserType','Nickname']);
const profileListFields = new Set(['Instruments','Styles','Genres','CollabRoles']);
const profileMirrors = new Set(['DisplayName','UserType','Nickname']);
function profileEdits(profile) {
  if (profile === undefined) return [];
  if (!profile || typeof profile !== 'object' || Array.isArray(profile) ||
      JSON.stringify(profile).length > 65536) {
    throw new HttpsError('invalid-argument','Invalid profile fields.');
  }
  const entries = Object.entries(profile);
  const valid = (key, value) => {
    if (profileTextFields.has(key)) return value === null || typeof value === 'string';
    if (profileListFields.has(key)) return value === null ||
      (Array.isArray(value) && value.every(item => typeof item === 'string'));
    return key === 'CollabRemote' && (value === null || typeof value === 'boolean');
  };
  if (!entries.every(([key,value]) => valid(key,value))) {
    throw new HttpsError('invalid-argument','Invalid profile fields.');
  }
  return entries;
}
exports.commitUserCity = onCall({region:'europe-west1'},async request=>{
  if(!request.auth)throw new HttpsError('unauthenticated','Sign in first.');
  const {profile,targetId,...data}=request.data||{},uid=request.auth.uid,db=admin.database();
  if((profile!==undefined||targetId!==undefined)&&targetId!==uid) {
    throw new HttpsError('permission-denied','You can only save your own profile.');
  }
  const clear=data.clear===true&&cityBody(data,['clear']);
  if(!clear&&(!cityBody(data,['nonce','operationId','location'])||typeof data.location!=='object')) {
    throw new HttpsError('invalid-argument','Invalid city confirmation.');
  }
  const edits=profileEdits(profile);
  const receipt=clear?null:await cityGate.consumeGrant(db,uid,'profile',uid,
    data.nonce,data.operationId,data.location);
  const operationId=clear?`clear_${crypto.randomBytes(12).toString('hex')}`:data.operationId;
  const startedAt=receipt?.consumedAt??Date.now();
  // Keep profile fields, compatibility mirrors and the verified city in one write.
  const committed=await db.ref(`users/${uid}`).transaction(current=>{
    if(current!=null&&(typeof current!=='object'||Array.isArray(current)))return;
    current ||= {};
    if(current.info!=null&&(typeof current.info!=='object'||Array.isArray(current.info)))return;
    const info=current.info ||= {};
    if(info.CityOperationId===operationId)return current;
    if((info.CityUpdatedAt||0)>startedAt)return;
    for(const [key,value] of edits) {
      info[key]=value;
      if(profileMirrors.has(key))current[key]=value;
    }
    Object.assign(info,{
      Location:clear?null:`${receipt.location.city}, ${receipt.location.country}`,
      PublicLocation:receipt?.location??null,
      LocationCleared:clear,CityOperationId:operationId,CityUpdatedAt:Date.now(),
    });
    return current;
  },undefined,false);
  if(!committed.committed)
    throw new HttpsError('failed-precondition','Profile could not be saved.');
  return {success:true};
});
exports.cleanupCityVerificationState = onSchedule({schedule:'every 30 minutes',
  region:'europe-west1'},()=>cityGate.cleanup(admin.database()));
exports.mutateBandMembership = onCall({ region:'europe-west1' }, request => {
  if (!['create','add','role','status','remove','leave','transfer','metadata'].includes(request.data?.action)) {
    throw new HttpsError('invalid-argument','Unsupported membership action.');
  }
  return membershipAuthority.mutate(admin.database(), request.auth?.uid, request.data);
});
const {
  buildEventProjections,
  getAuthorizedUserIdsForBandEvent,
  calculateReconciliationDiff,
  buildProjectionIndexKey,
} = require('./event_projection');
if (!admin.apps.length) {
  admin.initializeApp();
}

// In production, RTDB is located in europe-west1 (musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app).
// During local emulator execution, RTDB emulator operates under default us-central1 routing.
const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true' ||
  process.env.FIREBASE_DATABASE_EMULATOR_HOST !== undefined ||
  process.env.FIREBASE_EMULATOR_HUB !== undefined;
// The deployed manifest must not change region merely because a developer's
// shell has FIREBASE_DATABASE_EMULATOR_HOST or FIREBASE_EMULATOR_HUB set.
const databaseTriggerRegion = require('./deployment_region').databaseRegion();

// In emulator environment, stub outbound FCM messaging to avoid external network timeouts on fake tokens
if (isEmulator) {
  // Admin exposes messaging through an inherited getter; assignment is ignored.
  Object.defineProperty(admin, 'messaging', { configurable:true, value:function() {
    return {
      send: async () => 'mock-fcm-message-id',
      sendEach: async (messages) => ({
        responses: (messages || []).map(() => ({ success: true, messageId: 'mock-fcm-id' })),
        successCount: (messages || []).length,
        failureCount: 0,
      }),
    };
  } });
}

// Server-owned authenticated discovery projections; never use event snapshots as authority.
exports.onCatalogueUserWritten = onValueWritten({ref:'/users/{userId}',region:databaseTriggerRegion,retry:true},
  event => require('./catalogue_projections').reconcile(admin.database(),'user',event.params.userId));
exports.onCatalogueBandWritten = onValueWritten({ref:'/Bands/{bandId}',region:databaseTriggerRegion,retry:true},
  async event => {
    await require('./catalogue_projections').reconcile(admin.database(),'band',event.params.bandId);
    const beforeName=event.data.before.val()?.Name;
    const afterName=event.data.after.val()?.Name;
    if(!event.data.after.exists())await eventReadModels.reconcileBand(admin.database(),event.params.bandId);
    else if(beforeName!==afterName &&
      (await admin.database().ref(`bandMemberEvents/${event.params.bandId}`).get()).exists())
      await eventReadModels.reconcileBand(admin.database(),event.params.bandId);
  });
exports.onBandEventReadModelWritten = onValueWritten({
  ref:'/Bands/{bandId}/Events/{eventId}',region:databaseTriggerRegion,retry:true,
},event=>eventReadModels.reconcile(admin.database(),event.params.bandId,event.params.eventId));
exports.onLegacyBandCalendarEventWritten = onValueWritten({
  ref:'/Bands/{bandId}/Calendar/{eventId}',region:databaseTriggerRegion,retry:true,
},event=>{
  return eventReadModels.reconcileLegacyCalendar(admin.database(),
    event.params.bandId,event.params.eventId);
});

const KNOWN_FEATURE_IDS = ['find_gigs', 'find_musicians', 'collabs', 'band_room', 'messages'];

/**
 * Resolves the destination feature ID for a notification, preserving explicit featureId
 * or falling back to centralized type-to-feature mapping.
 */
function resolveNotificationFeatureId(notif) {
  if (!notif) return null;
  const explicit = notif.featureId || notif.data?.featureId;
  if (explicit && KNOWN_FEATURE_IDS.includes(explicit)) {
    return explicit;
  }
  const type = notif.type;
  switch (type) {
    case 'sub_request_invite':
    case 'sub_request':
    case 'grouped_sub_request':
    case 'gig_finalized':
      return 'find_gigs';
    case 'sub_request_response':
    case 'sub_response':
      return 'find_musicians';
    case 'session_application':
    case 'session_application_status':
    case 'session_message':
      return 'collabs';
    case 'band_room_message':
    case 'band_section_chat':
    case 'event_invite':
    case 'event_reminder':
    case 'event_threshold':
    case 'event_milestone':
    case 'band_file_uploaded':
      return 'band_room';
    case 'direct_message':
      return 'messages';
    default:
      return null;
  }
}

function notificationUid(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to view notifications.');
  return request.auth.uid;
}

exports.registerNotificationInstallation = onCall({ region: 'europe-west1' }, request =>
  notificationDelivery.changeBinding(admin.database(), notificationUid(request), request.data));
exports.unregisterNotificationInstallation = onCall({ region: 'europe-west1' }, request =>
  notificationDelivery.changeBinding(admin.database(), notificationUid(request), request.data, true));

const notificationOptions = {
  buildRequest: buildSanitizedFeedItem,
  format: formatDateTimeLabel,
  isPrivate: request => ['direct_invitation', 'favorites_only'].includes(classifySubRequest(request)),
};

exports.listNotificationFeed = onCall({ region: 'europe-west1' }, request =>
  notificationAccess.list(admin.database(), notificationUid(request), notificationOptions));
exports.resolveNotification = onCall({ region: 'europe-west1' }, request =>
  notificationAccess.resolve(admin.database(), notificationUid(request), request.data?.notificationId,
    request.data?.slotId, notificationOptions, request.data?.preview === true));

function publishNotification(uid, type, key, route, deliveryOptions) {
  return notificationDelivery.publish(admin.database(), admin.messaging(), uid, type, key, route,
    deliveryOptions);
}

async function notifyRequestResponse(subRequestId, responderId) {
  const db = admin.database();
  const request = (await db.ref('SubRequests/' + subRequestId).get()).val();
  if (!notificationAccess.activeRequest(request) || !(request.Responses ?? request.responses)?.[responderId]) return;
  const uid = request.CreatorUserId || request.creatorUserId || request.UserId || request.userId;
  if (!notificationDelivery.safeKey(uid) || uid === responderId) return;
  try {
    await membershipAuthority.authorizeRequest(db, uid, request);
  } catch (error) {
    if (error.code === 'permission-denied' || error.code === 'failed-precondition') return;
    throw error;
  }
  // A retry of a pre-cutover application may have a historical delivery.
  // Keep that record private and avoid sending another alert for it.
  const legacyId = 'notif_sub_resp_' + subRequestId + '_' + responderId;
  const legacy = await db.ref('userNotifications/' + uid + '/' + legacyId).get();
  return publishNotification(uid, 'sub_request_response', [subRequestId, responderId],
    { subRequestId, responderId }, { suppressPush: legacy.exists() });
}

function registeredRecipients(uids) {
  return notificationDelivery.recipients(admin.database(), uids);
}

function dispatchRegistered(recipient, message) {
  return notificationDelivery.dispatchRegistered(admin.database(), admin.messaging(), recipient, message);
}

async function dispatchRegisteredBatch(recipients, messages) {
  const responses = await Promise.all(recipients.map((recipient, index) =>
    dispatchRegistered(recipient, messages[index])));
  const successCount = responses.filter(response => response.success).length;
  return { responses, successCount, failureCount: responses.length - successCount };
}

/**
 * Helper to format date and time string cleanly for notifications.
 */
function formatDateTimeLabel(dateVal, startTimeVal, endTimeVal) {
  let datePart = '';
  let timePart = '';

  if (dateVal) {
    if (typeof dateVal === 'string' && dateVal.includes('T')) {
      const d = new Date(dateVal);
      if (!isNaN(d.getTime())) {
        const yyyy = d.getFullYear();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        datePart = `${yyyy}-${mm}-${dd}`;
        const hh = String(d.getHours()).padStart(2, '0');
        const min = String(d.getMinutes()).padStart(2, '0');
        if (hh !== '00' || min !== '00') {
          timePart = `${hh}:${min}`;
        }
      }
    } else {
      datePart = String(dateVal).trim();
    }
  }

  if (startTimeVal) {
    const s = String(startTimeVal).trim();
    if (s && s !== 'TBD') {
      timePart = endTimeVal && String(endTimeVal).trim() && String(endTimeVal).trim() !== 'TBD'
        ? `${s} - ${String(endTimeVal).trim()}`
        : s;
    }
  }

  if (datePart && timePart) {
    return `${datePart} ${timePart}`;
  } else if (datePart) {
    return datePart;
  } else if (timePart) {
    return timePart;
  }
  return 'Date & Time TBD';
}

/**
 * Triggered when a new event is created under /Bands/{bandId}/Events/{eventId}.
 * Sends a push notification to all band members except the event creator.
 */
exports.onBandEventCreated = functions.region(databaseTriggerRegion).database
  .ref('/Bands/{bandId}/Events/{eventId}')
  .onCreate(async (snapshot, context) => {
    const eventData = snapshot.val();
    if (!eventData) return null;

    const bandId = context.params.bandId;
    const eventId = context.params.eventId;
    const creatorId = eventData.createdBy;

    try {
      // 1. Fetch the band members
      const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);
      const membersSnapshot = await membersRef.once('value');
      const members = membersSnapshot.val();
      if (!members) {
        console.log(`No members found for band ${bandId}`);
        return null;
      }

      const recipients = Object.keys(members).filter(uid =>
        uid !== creatorId && notificationMember(members[uid]));
      await Promise.all(recipients.map(uid => publishNotification(uid, 'event_invite',
        [bandId, eventId], { bandId, eventId })));
      return null;
    } catch (error) {
      console.error('Error sending event push notification:', error);
      return null;
    }
  });

/**
 * MAP-VIEW-FEED-02:
 * Synchronizes private band event projections with atomic index-driven reconciliation.
 */
exports.onBandEventWritten = functions.region(databaseTriggerRegion).database
  .ref('/Bands/{bandId}/Events/{eventId}')
  .onWrite(async (change, context) => {
    const bandId = context.params.bandId;
    const eventId = context.params.eventId;
    const db = admin.database();
    const sourceKey = `band:${bandId}:${eventId}`;

    try {
      const prevIndexSnap = await db.ref(`/mapEventProjectionIndex/${sourceKey}`).once('value');
      const prevIndex = prevIndexSnap.val() || null;

      let bandName = 'Band';
      let bandData = { Members_band: {} };
      try {
        const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');
        if (bandSnap.exists() && bandSnap.val()) {
          const bVal = bandSnap.val();
          bandName = String(bVal.Name || bVal.name || 'Band').trim();
          bandData = bVal;
        }
      } catch (_) {}

      const eventData = change.after.exists() ? change.after.val() : null;

      const { updates } = calculateReconciliationDiff({
        source: 'private_band',
        eventId,
        bandId,
        bandName,
        bandData,
        eventData,
        prevIndex,
      });

      if (Object.keys(updates).length > 0) {
        await db.ref().update(updates);
      }
    } catch (err) {
      console.error(`[onBandEventWritten] Error reconciling event projections for ${sourceKey}: ${err.message}`);
    }
    return null;
  });

/**
 * MAP-VIEW-FEED-02:
 * Synchronizes public calendar event projections with atomic index-driven reconciliation.
 */
exports.onPublicEventWritten = functions.region(databaseTriggerRegion).database
  .ref('/PublicEvents/{eventId}')
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;
    const db = admin.database();
    const sourceKey = `public:${eventId}`;

    try {
      const prevIndexSnap = await db.ref(`/mapEventProjectionIndex/${sourceKey}`).once('value');
      const prevIndex = prevIndexSnap.val() || null;

      const eventData = change.after.exists() ? change.after.val() : null;
      const organizerName = eventData ? (eventData.organizerName || '') : '';

      const { updates } = calculateReconciliationDiff({
        source: 'public_calendar',
        eventId,
        bandId: null,
        bandName: organizerName,
        bandData: null,
        eventData,
        prevIndex,
      });

      if (Object.keys(updates).length > 0) {
        await db.ref().update(updates);
      }
    } catch (err) {
      console.error(`[onPublicEventWritten] Error reconciling public event projections for ${sourceKey}: ${err.message}`);
    }
    return null;
  });


/**
 * Triggered when a new substitute request is created under /SubRequests/{subRequestId}.
 * Sends a push notification to either targeted favorites or matching instrument users.
 */
exports.sendSubRequestNotification = onValueCreated({
  ref: '/SubRequests/{subRequestId}',
  region: databaseTriggerRegion
}, async (event) => {
  const subRequestData = event.data.val();
  if (!subRequestData) return null;

  const subRequestId = event.params.subRequestId;

  // 1. Grouped publication skip: if this subrequest belongs to a new grouped publication manifest,
  // the onSubRequestGroupPublished handler provides the single combined notification.
  if (
    subRequestData.NotificationMode === 'grouped' ||
    subRequestData.notificationMode === 'grouped' ||
    Boolean(subRequestData.PublicationId) ||
    Boolean(subRequestData.publicationId)
  ) {
    console.log(`Skipping legacy per-slot notification for grouped subrequest ${subRequestId}`);
    return null;
  }

  // 1b. Map pin publication skip: ordinary map view pins must produce no notifications
  if (
    subRequestData.NotificationMode === 'map_pin' ||
    subRequestData.notificationMode === 'map_pin'
  ) {
    console.log(`Skipping notification for map-only pin ${subRequestId}`);
    return null;
  }

  const rawVoicePart = subRequestData.VoicePart || subRequestData.voicePart;
  if (!rawVoicePart || typeof rawVoicePart !== 'string' || !rawVoicePart.trim()) {
    console.log(`Skipping legacy notification for subrequest ${subRequestId} due to missing or invalid VoicePart.`);
    return null;
  }
  const voicePart = rawVoicePart.trim();
  const creatorUserId = subRequestData.CreatorUserId || subRequestData.creatorUserId ||
    subRequestData.UserId || subRequestData.userId;
  const targetUserIds = subRequestData.TargetUserIds || subRequestData.targetUserIds;

  try {
    // Resolve eligible profiles. Tokens are read only during delivery.
    const usersRef = admin.database().ref('/users');
    const usersSnapshot = await usersRef.once('value');
    const users = usersSnapshot.val();
    if (!users) {
      console.log('No users found in the system.');
      return null;
    }

    const matchingUserIds = [];

    const privateRequest = notificationOptions.isPrivate(subRequestData);
    const previousAudience = privateRequest
      ? (await admin.database().ref('subRequestAudience/' + subRequestId).get()).val() || {}
      : {};
    Object.keys(users).forEach((userId) => {
      // Exclude creator
      if (userId === creatorUserId) return;

      const userInfo = users[userId].info;
      if (!userInfo) return;

      let shouldNotify = false;
      if (targetUserIds && Array.isArray(targetUserIds) && targetUserIds.length > 0) {
        // Targeted mode: only selected user IDs
        shouldNotify = targetUserIds.includes(userId);
      } else if (privateRequest) {
        shouldNotify = previousAudience[userId] === true;
      } else {
        // Default mode: matches the requested instrument/voice part
        const userType = userInfo.UserType || userInfo.userType || '';
        const instruments = userInfo.Instruments || userInfo.instruments || [];
        
        const hasMatchingInstrument = 
          (typeof userType === 'string' && userType.toLowerCase() === voicePart.toLowerCase()) ||
          (Array.isArray(instruments) && instruments.some(i => typeof i === 'string' && i.toLowerCase() === voicePart.toLowerCase()));
          
        shouldNotify = hasMatchingInstrument;
      }

      if (shouldNotify) matchingUserIds.push(userId);
    });
    if (matchingUserIds.length) {
      const audience = Object.fromEntries(matchingUserIds.map(uid =>
        ['subRequestAudience/' + subRequestId + '/' + uid, true]));
      await admin.database().ref().update(audience);
    }
    await Promise.all(matchingUserIds.map(uid => publishNotification(uid, 'sub_request_invite',
      subRequestId, { subRequestId })));

    return null;
  } catch (error) {
    console.error('Error sending sub request notifications:', error);
    return null;
  }
});

/**
 * Compute stable publication operation ID from group ID and sorted slot IDs.
 */
function computeStablePublicationId(groupId, slotIds) {
  const sorted = [...slotIds].sort();
  const hash = crypto.createHash('sha256').update(groupId + ':' + sorted.join(',')).digest('hex').substring(0, 16);
  return `pub_${groupId}_${hash}`;
}
exports.computeStablePublicationId = computeStablePublicationId;

/**
 * The publisher commits the manifest and exact audience together. This trigger
 * consumes that audience without replacing the request or its feed entries.
 */
exports.onSubRequestGroupPublished = onValueCreated({
  ref: '/subRequestPublications/{publicationId}',
  region: databaseTriggerRegion,
}, async event => {
  const publication = event.data.val();
  if (!publication) return null;
  const publicationId = event.params.publicationId;
  const slotIds = [...new Set(Object.values(publication.slots || {})
    .map(slot => slot.subRequestId || slot.slotId).filter(notificationDelivery.safeKey))];
  const db = admin.database();
  try {
    const audiences = await Promise.all(slotIds.map(id =>
      db.ref('subRequestAudience/' + id).get()));
    const recipients = new Set(audiences.flatMap(snapshot => Object.entries(snapshot.val() || {})
      .filter(([uid, matched]) => matched === true && uid !== publication.creatorUserId)
      .map(([uid]) => uid)));
    const results = await Promise.all([...recipients].map(async uid => {
      const result = await publishNotification(uid, 'grouped_sub_request', publicationId, { publicationId });
      return [uid, result];
    }));
    const sent = results.filter(([, result]) => result?.results?.some(response => response.success));
    const auditRef = db.ref('subRequestNotificationAudit/' + publicationId);
    const audit = Object.fromEntries(sent.map(([uid]) =>
      ['recipients/' + uid, { notifiedAt: Date.now(), status: 'sent' }]));
    const previous = (await auditRef.child('recipients').get()).val() || {};
    await auditRef.update({
      ...audit,
      processedAt: Date.now(),
      requestGroupId: publication.requestGroupId || publicationId,
      notifiedCount: new Set([...Object.keys(previous), ...sent.map(([uid]) => uid)]).size,
    });
  } catch (error) {
    console.error('Grouped notification unavailable:', error?.code || 'unknown');
  }
  return null;
});

/**
 * Taxonomy of SubRequest categories for least-privilege feed distribution.
 */
const SUBREQUEST_KIND = {
  DIRECT_INVITATION: 'direct_invitation',
  FAVORITES_ONLY: 'favorites_only',
  PUBLIC_GIG: 'public_gig',
  EVENT_SUBSTITUTE_PUBLIC: 'event_substitute_public',
  PROMO_MAP_PIN: 'promo_map_pin',
};

/**
 * Classifies a subrequest item into its security kind.
 */
function classifySubRequest(data) {
  if (!data) return SUBREQUEST_KIND.PUBLIC_GIG;

  const mode = data.NotificationMode || data.notificationMode;
  if (mode === 'map_pin') {
    return SUBREQUEST_KIND.PROMO_MAP_PIN;
  }

  const rawType = (data.Type || data.type || '').toString().toLowerCase();
  const searchSource = (data.SearchSource || data.searchSource || '').toString().toLowerCase();
  const isFavoritesOnly = data.IsFavoritesOnly === true || data.isFavoritesOnly === true || searchSource === 'favorites';

  const isDirect = data.IsDirectInvitation === true || data.isDirectInvitation === true ||
    rawType === 'direct_invitation' || rawType === 'direct' ||
    searchSource === 'direct';

  if (isDirect) {
    return SUBREQUEST_KIND.DIRECT_INVITATION;
  }

  if (isFavoritesOnly) {
    return SUBREQUEST_KIND.FAVORITES_ONLY;
  }

  const targetUserIds = data.TargetUserIds || data.targetUserIds;
  if (Array.isArray(targetUserIds) && targetUserIds.length > 0 && targetUserIds[0]) {
    return SUBREQUEST_KIND.DIRECT_INVITATION;
  }

  const bandId = data.BandId || data.bandId;
  const eventId = data.EventId || data.eventId;
  if (bandId && eventId && bandId !== 'freelance' && bandId !== 'standalone') {
    return SUBREQUEST_KIND.EVENT_SUBSTITUTE_PUBLIC;
  }

  return SUBREQUEST_KIND.PUBLIC_GIG;
}

/**
 * Normalized classifier recognizing all New Member representation variants
 * without misclassifying Substitute, Other, direct invitations, or map pins.
 */
function isNewMemberRequest(data) {
  if (!data || typeof data !== 'object') return false;

  const mode = (data.NotificationMode || data.notificationMode || '').toString().trim().toLowerCase();
  if (mode === 'map_pin') return false;

  const rawReqType = (data.RequestType || data.requestType || '').toString().trim();
  if (rawReqType) {
    const cleanReqType = rawReqType.toLowerCase().replace(/[\s_-]+/g, '');
    if (cleanReqType === 'newmember' || cleanReqType === 'newbandmember') return true;
    if (cleanReqType === 'substitute' || cleanReqType === 'sub' || cleanReqType === 'other') return false;
  }

  const rawRole = (data.Role || data.role || '').toString().trim();
  if (rawRole) {
    const cleanRole = rawRole.toLowerCase().replace(/[\s_-]+/g, '');
    if (cleanRole === 'newmember' || cleanRole === 'newbandmember') return true;
  }

  const extra = data.extraFields && typeof data.extraFields === 'object' ? data.extraFields : {};
  const rawEventType = (data.EventType || data.eventType || extra.EventType || extra.eventType || '').toString().trim();
  if (rawEventType) {
    const cleanEventType = rawEventType.toLowerCase().replace(/[\s_-]+/g, '');
    if (cleanEventType === 'newmember' || cleanEventType === 'newbandmember') return true;
  }

  return false;
}

/**
 * Extracts a city label from a full address string by stripping street numbers and street names.
 */
function extractCityLabel(locationStr) {
  if (!locationStr) return '';
  const str = locationStr.toString().trim();
  if (!str) return '';

  if (str.includes(',')) {
    const parts = str.split(',').map((p) => p.trim()).filter(Boolean);
    for (let i = parts.length - 1; i >= 0; i--) {
      const part = parts[i];
      if ((part.toLowerCase() === 'sweden' || part.toLowerCase() === 'sverige') && i > 0) {
        continue;
      }
      const cleaned = part.replace(/^\d{3}\s?\d{2}\s+/, '').trim();
      if (cleaned && !/^\d+$/.test(cleaned)) {
        return cleaned;
      }
    }
    return parts[parts.length - 1];
  }

  const noHouseNum = str.replace(/^[A-Za-zåäöÅÄÖ\s\.\-]+\s+\d+[A-Za-z]?\s+/, '').trim();
  if (noHouseNum && !/^\d+$/.test(noHouseNum)) return noHouseNum;

  return str;
}

const KNOWN_SWEDISH_CITIES = {
  'stockholm': { lat: 59.3293, lng: 18.0686, name: 'Stockholm' },
  'göteborg': { lat: 57.7089, lng: 11.9746, name: 'Göteborg' },
  'gothenburg': { lat: 57.7089, lng: 11.9746, name: 'Göteborg' },
  'malmö': { lat: 55.6050, lng: 13.0038, name: 'Malmö' },
  'uppsala': { lat: 59.8586, lng: 17.6389, name: 'Uppsala' },
  'linköping': { lat: 58.4108, lng: 15.6214, name: 'Linköping' },
  'örebro': { lat: 59.2753, lng: 15.2134, name: 'Örebro' },
  'västerås': { lat: 59.6099, lng: 16.5448, name: 'Västerås' },
  'helsingborg': { lat: 56.0465, lng: 12.6945, name: 'Helsingborg' },
  'jönköping': { lat: 57.7826, lng: 14.1618, name: 'Jönköping' },
  'norrköping': { lat: 58.5877, lng: 16.1924, name: 'Norrköping' },
  'lund': { lat: 55.7047, lng: 13.1910, name: 'Lund' },
  'umeå': { lat: 63.8258, lng: 20.2630, name: 'Umeå' },
  'gävle': { lat: 60.6749, lng: 17.1417, name: 'Gävle' },
  'borås': { lat: 57.7210, lng: 12.9401, name: 'Borås' },
  'halmstad': { lat: 56.6745, lng: 12.8578, name: 'Halmstad' },
  'karlstad': { lat: 59.3793, lng: 13.5036, name: 'Karlstad' },
  'sundsvall': { lat: 62.3908, lng: 17.3069, name: 'Sundsvall' },
  'ljusdal': { lat: 61.8286, lng: 16.0958, name: 'Ljusdal' },
};

function resolveKnownCityCentroid(label) {
  if (!label) return null;
  const clean = label.toString().trim().toLowerCase();
  if (!clean) return null;
  for (const [key, city] of Object.entries(KNOWN_SWEDISH_CITIES)) {
    if (clean.includes(key)) {
      return city;
    }
  }
  return null;
}

/**
 * Builds a sanitized, leak-free feed item containing only displayable fields.
 */
function buildSanitizedFeedItem(subRequest) {
  if (!subRequest) return null;

  const isNewMember = isNewMemberRequest(subRequest);
  const isCityPrecision = (subRequest.LocationPrecision || subRequest.locationPrecision) === 'city' || isNewMember;

  let lat = subRequest.Latitude ?? subRequest.latitude ?? null;
  let lng = subRequest.Longitude ?? subRequest.longitude ?? null;
  let locationLabel = (subRequest.Location || subRequest.location || '').toString().trim();

  let cityLabel = (subRequest.City || subRequest.city || '').toString().trim();
  if (!cityLabel && locationLabel) {
    cityLabel = extractCityLabel(locationLabel);
  }

  if (isNewMember) {
    // Coarsen coordinates to 1 decimal place (~11 km lat, ~6 km lng uncertainty)
    // to strictly protect residential privacy, or fallback to known city centroid
    if (lat !== null && lng !== null) {
      lat = Number(Number(lat).toFixed(1));
      lng = Number(Number(lng).toFixed(1));
    } else {
      const knownCentroid = resolveKnownCityCentroid(cityLabel || locationLabel);
      if (knownCentroid) {
        lat = knownCentroid.lat;
        lng = knownCentroid.lng;
      }
    }
    // Location label is strictly coarsened to city label only; never expose street addresses or house numbers
    locationLabel = cityLabel || 'Stockholm';
  } else if (isCityPrecision) {
    if (lat !== null && lng !== null) {
      lat = Number(Number(lat).toFixed(1));
      lng = Number(Number(lng).toFixed(1));
    } else {
      const knownCentroid = resolveKnownCityCentroid(cityLabel || locationLabel);
      if (knownCentroid) {
        lat = knownCentroid.lat;
        lng = knownCentroid.lng;
      }
    }
    if (cityLabel) {
      locationLabel = cityLabel;
    }
  }

  const rawReqType = subRequest.RequestType || subRequest.requestType || '';
  const requestType = isNewMember
    ? 'New Band Member'
    : (rawReqType || 'Substitute');

  const rawEventType = subRequest.EventType || subRequest.eventType ||
    (subRequest.extraFields && (subRequest.extraFields.EventType || subRequest.extraFields.eventType)) || null;
  const eventType = isNewMember ? null : (rawEventType ? rawEventType.toString().trim() : null);

  const startTime = isNewMember ? null : (subRequest.StartTime || subRequest.startTime || null);
  const endTime = isNewMember ? null : (subRequest.EndTime || subRequest.endTime || null);

  const description = (subRequest.Description || subRequest.description || subRequest.Notes || subRequest.notes || '').toString().trim();
  const payDetails = (subRequest.PayDetails || subRequest.payDetails || '').toString().trim() || null;

  return {
    id: subRequest.SubRequestId || subRequest.subRequestId || subRequest.id || subRequest.slotId || '',
    subRequestId: subRequest.SubRequestId || subRequest.subRequestId || subRequest.id || subRequest.slotId || '',
    slotId: subRequest.SlotId || subRequest.slotId || subRequest.SubRequestId || subRequest.subRequestId || subRequest.id || '',
    requestGroupId: subRequest.RequestGroupId || subRequest.requestGroupId || '',
    publicationId: subRequest.PublicationId || subRequest.publicationId || '',
    bandId: subRequest.BandId || subRequest.bandId || '',
    bandName: subRequest.BandName || subRequest.bandName || 'Freelance Gig',
    eventId: isNewMember ? '' : (subRequest.EventId || subRequest.eventId || ''),
    eventTitle: isNewMember ? '' : (subRequest.EventTitle || subRequest.eventTitle || ''),
    voicePart: subRequest.VoicePart || subRequest.voicePart || subRequest.role || subRequest.Role || '',
    date: isNewMember ? '' : (subRequest.Date || subRequest.date || ''),
    time: isNewMember ? '' : (subRequest.Time || subRequest.time || ''),
    requestType: requestType,
    eventType: eventType,
    startTime: startTime,
    endTime: endTime,
    location: locationLabel,
    city: cityLabel || (isNewMember ? locationLabel : ''),
    latitude: lat,
    longitude: lng,
    locationPrecision: isCityPrecision ? 'city' : (subRequest.LocationPrecision || subRequest.locationPrecision || 'exact'),
    payAmount: subRequest.PayAmount ?? subRequest.payAmount ?? null,
    payAmountMinor: subRequest.PayAmountMinor ?? subRequest.payAmountMinor ?? null,
    currency: subRequest.Currency || subRequest.currency || 'SEK',
    isPaid: subRequest.IsPaid ?? subRequest.isPaid ?? false,
    payDetails: payDetails,
    description: description,
    genre: subRequest.Genre || subRequest.genre || '',
    status: subRequest.Status || subRequest.status || 'published',
    createdAt: subRequest.CreatedAt || subRequest.createdAt || Date.now(),
    updatedAt: subRequest.UpdatedAt || subRequest.updatedAt || Date.now(),
    creatorUserId: subRequest.CreatorUserId || subRequest.creatorUserId || subRequest.UserId || subRequest.userId || '',
    creatorName: subRequest.CreatorName || subRequest.creatorName || '',
    searchSource: subRequest.SearchSource || subRequest.searchSource || 'search_all',
    type: subRequest.Type || subRequest.type || 'sub_request',
    isFavoritesOnly: subRequest.IsFavoritesOnly === true || subRequest.isFavoritesOnly === true || (subRequest.SearchSource || subRequest.searchSource) === 'favorites',
  };
}

function isValidSubRequestCoord(lat, lng) {
  if (lat === null || lat === undefined || lng === null || lng === undefined) return false;
  const nLat = Number(lat);
  const nLng = Number(lng);
  if (!Number.isFinite(nLat) || !Number.isFinite(nLng)) return false;
  if (nLat < -90 || nLat > 90 || nLng < -180 || nLng > 180) return false;
  if (nLat === 0 && nLng === 0) return false;
  return true;
}

/**
 * Centralized location precedence for SubRequest:
 * 1. If the SubRequest has its own explicitly confirmed valid coordinates,
 *    those coordinates and its confirmed location label MUST be used.
 * 2. Linked Event coordinates may be inherited ONLY when the SubRequest has
 *    no valid confirmed coordinates of its own.
 * 3. Band city, creator profile city, Ljusdal, Stockholm, or any other default
 *    must NEVER replace valid request coordinates.
 * 4. If neither the request nor its linked Event has valid coordinates, the
 *    request remains unresolved (latitude: null, longitude: null).
 */
function resolveSubRequestLocation(slot, linkedEvent = null) {
  if (!slot) return slot;
  const slotLat = slot.Latitude ?? slot.latitude ?? null;
  const slotLng = slot.Longitude ?? slot.longitude ?? null;
  const rawLoc = (slot.Location || slot.location || '').toString().trim();

  if (isValidSubRequestCoord(slotLat, slotLng)) {
    const numLat = Number(slotLat);
    const numLng = Number(slotLng);
    const city = (slot.City || slot.city || extractCityLabel(rawLoc) || '').toString().trim();
    return {
      ...slot,
      Location: rawLoc,
      location: rawLoc,
      City: city,
      city: city,
      Latitude: numLat,
      latitude: numLat,
      Longitude: numLng,
      longitude: numLng,
      LocationPrecision: slot.LocationPrecision || slot.locationPrecision || 'exact',
      locationPrecision: slot.LocationPrecision || slot.locationPrecision || 'exact',
      LocationStatus: 'resolved',
      locationStatus: 'resolved',
    };
  }

  if (linkedEvent) {
    const evLat = linkedEvent.Latitude ?? linkedEvent.latitude ?? null;
    const evLng = linkedEvent.Longitude ?? linkedEvent.longitude ?? null;
    const evLoc = (linkedEvent.Location || linkedEvent.location || '').toString().trim();
    if (isValidSubRequestCoord(evLat, evLng)) {
      const numLat = Number(evLat);
      const numLng = Number(evLng);
      const finalLoc = rawLoc || evLoc;
      const city = extractCityLabel(finalLoc);
      return {
        ...slot,
        Location: finalLoc,
        location: finalLoc,
        City: city,
        city: city,
        Latitude: numLat,
        latitude: numLat,
        Longitude: numLng,
        longitude: numLng,
        LocationPrecision: slot.LocationPrecision || slot.locationPrecision || 'exact',
        locationPrecision: slot.LocationPrecision || slot.locationPrecision || 'exact',
        LocationStatus: 'resolved',
        locationStatus: 'resolved',
      };
    }
  }

  return {
    ...slot,
    Location: rawLoc,
    location: rawLoc,
    Latitude: null,
    latitude: null,
    Longitude: null,
    longitude: null,
    LocationStatus: 'unresolved',
    locationStatus: 'unresolved',
  };
}

exports.SUBREQUEST_KIND = SUBREQUEST_KIND;
exports.classifySubRequest = classifySubRequest;
exports.buildSanitizedFeedItem = buildSanitizedFeedItem;
exports.isNewMemberRequest = isNewMemberRequest;
exports.extractCityLabel = extractCityLabel;
exports.resolveSubRequestLocation = resolveSubRequestLocation;

/**
 * Production callable entrypoint to publish a grouped substitute request.
 * Authorized for Band Leader/Admin or event creator.
 * Atomically writes SubRequests, publication manifest, audience index, and user feeds.
 */
exports.publishSubRequestGroup = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerId = request.auth.uid;
  const data = request.data || {};
  const { bandId: requestedBandId, requestGroupId, eventId, slots, bandName } = data;
  // Explicit canonical sentinel for a genuinely bandless new publication.
  const bandId = requestedBandId ?? 'freelance';

  if (!requestGroupId || !slots || !Array.isArray(slots) || slots.length === 0) {
    throw new HttpsError('invalid-argument', 'Invalid request payload.');
  }

  const db = admin.database();

  // New publications have no canonical request yet: bind every slot and existing
  // exact slot record to this validated owning band before publishing anything.
  if (!bandId || typeof bandId !== 'string') throw new HttpsError('invalid-argument','An explicit owning band is required.');
  const bandless = ['freelance','standalone'].includes(bandId);
  if (!bandless) await membershipAuthority.requireManager(db,bandId,callerId);
  for (const slot of slots) {
    if (slot.bandId != null && slot.bandId !== bandId) throw new HttpsError('invalid-argument','Mixed owning bands are not permitted.');
    if (slot.BandId != null && slot.BandId !== bandId) throw new HttpsError('invalid-argument','Mixed owning bands are not permitted.');
    slot.bandId = bandId;
    slot.BandId = bandId;
    const id = slot.subRequestId || slot.SubRequestId || slot.slotId;
    if (id) {
      membershipAuthority.key(id,'request ID');
      const existing = (await db.ref(`SubRequests/${id}`).get()).val();
      if (existing) await membershipAuthority.authorizeRequest(db,callerId,existing,bandId);
    }
    const linkedEvent = membershipAuthority.canonicalField(slot,'EventId','eventId') || eventId;
    if (linkedEvent) { slot.EventId = linkedEvent; slot.eventId = linkedEvent; }
    if (!bandless && linkedEvent && linkedEvent !== 'standalone' && !linkedEvent.startsWith('freelance')) {
      membershipAuthority.key(linkedEvent,'event ID');
      if (!(await db.ref(`Bands/${bandId}/Events/${linkedEvent}`).get()).exists()) throw new HttpsError('permission-denied','Owning band event was not found.');
    }
  }

  // Fetch linked events if needed for fallback coordinate inheritance ONLY when slot lacks own coordinates
  const linkedEventsMap = {};
  if (bandId && bandId !== 'freelance' && bandId !== 'standalone') {
    for (const slot of slots) {
      const slotEventId = slot.eventId || slot.EventId || eventId;
      if (slotEventId && slotEventId !== 'standalone' && !slotEventId.startsWith('freelance') && !linkedEventsMap[slotEventId]) {
        const evSnap = await db.ref(`/Bands/${bandId}/Events/${slotEventId}`).once('value');
        if (evSnap.exists()) {
          linkedEventsMap[slotEventId] = evSnap.val();
        }
      }
    }
  }

  // 2. Fetch creator favorites to strictly validate targeted favorites
  const callerFavSnap = await db.ref(`/users/${callerId}/Favorites`).once('value');
  const callerFavorites = callerFavSnap.val() || {};

  const resolvedSlots = slots.map((slot, index) => {
    const rawKey =
      slot.subRequestId ||
      slot.SubRequestId ||
      slot.slotId ||
      slot.SlotId ||
      slot.id ||
      slot.Id ||
      slot.key;
    const slotKey =
      (rawKey && typeof rawKey === 'string' && rawKey.trim().length > 0 && !rawKey.startsWith('draft_'))
        ? rawKey.trim()
        : (db.ref('SubRequests').push().key || `sub_${Date.now()}_${index}`);

    const slotId = slot.slotId || slot.SlotId || slotKey;
    const slotEventId = slot.eventId || slot.EventId || eventId;
    const linkedEv = slotEventId ? linkedEventsMap[slotEventId] : null;
    const locationResolvedSlot = resolveSubRequestLocation(slot, linkedEv);

    return {
      ...locationResolvedSlot,
      subRequestId: slotKey,
      SubRequestId: slotKey,
      slotId: slotId,
      SlotId: slotId,
    };
  });

  const slotIds = resolvedSlots.map(s => s.subRequestId).filter(Boolean);
  const publicationId = computeStablePublicationId(requestGroupId, slotIds);

  const updates = {};
  const now = Date.now();

  // 3. Write each canonical SubRequest & Creator feed
  resolvedSlots.forEach((slot) => {
    const slotKey = slot.subRequestId;
    const isNewMember = isNewMemberRequest(slot);
    const resolvedRequestType = isNewMember ? 'New Band Member' : (slot.RequestType || slot.requestType || 'Substitute');
    const resolvedEventType = isNewMember ? null : (slot.EventType || slot.eventType || (slot.extraFields && (slot.extraFields.EventType || slot.extraFields.eventType)) || null);
    const resolvedStartTime = isNewMember ? null : (slot.StartTime || slot.startTime || null);
    const resolvedEndTime = isNewMember ? null : (slot.EndTime || slot.endTime || null);
    const resolvedDesc = (slot.Description || slot.description || slot.Notes || slot.notes || '').toString().trim();
    const resolvedPayDetails = (slot.PayDetails || slot.payDetails || '').toString().trim() || null;

    const canonicalItem = {
      ...slot,
      SubRequestId: slotKey,
      SlotId: slot.slotId || slotKey,
      RequestGroupId: requestGroupId,
      PublicationId: publicationId,
      NotificationMode: slot.NotificationMode || slot.notificationMode || 'grouped',
      CreatorUserId: callerId,
      Status: 'published',
      CreatedAt: slot.createdAt || slot.CreatedAt || now,
      UpdatedAt: now,
      RequestType: resolvedRequestType,
      EventType: resolvedEventType,
      StartTime: resolvedStartTime,
      EndTime: resolvedEndTime,
      Description: resolvedDesc,
      PayDetails: resolvedPayDetails,
    };
    if (isNewMember) {
      delete canonicalItem.Date;
      delete canonicalItem.date;
      delete canonicalItem.Time;
      delete canonicalItem.time;
      delete canonicalItem.EventType;
      delete canonicalItem.eventType;
      delete canonicalItem.StartTime;
      delete canonicalItem.startTime;
      delete canonicalItem.EndTime;
      delete canonicalItem.endTime;
      delete canonicalItem.EventId;
      delete canonicalItem.eventId;
      delete canonicalItem.EventTitle;
      delete canonicalItem.eventTitle;
      delete canonicalItem.PlaceId;
      delete canonicalItem.placeId;

      const rawLoc = canonicalItem.City || canonicalItem.city || canonicalItem.Location || canonicalItem.location || '';
      const knownCentroid = resolveKnownCityCentroid(rawLoc);
      const cleanCity = knownCentroid ? knownCentroid.name : (extractCityLabel(rawLoc) || 'Stockholm');
      canonicalItem.Location = cleanCity;
      canonicalItem.location = cleanCity;
      canonicalItem.City = cleanCity;
      canonicalItem.city = cleanCity;
      canonicalItem.LocationPrecision = 'city';
      canonicalItem.locationPrecision = 'city';
      if (canonicalItem.Latitude !== undefined && canonicalItem.Latitude !== null) {
        const coarsenLat = Number(Number(canonicalItem.Latitude).toFixed(1));
        const coarsenLng = Number(Number(canonicalItem.Longitude).toFixed(1));
        canonicalItem.Latitude = coarsenLat;
        canonicalItem.latitude = coarsenLat;
        canonicalItem.Longitude = coarsenLng;
        canonicalItem.longitude = coarsenLng;
      } else if (knownCentroid) {
        canonicalItem.Latitude = knownCentroid.lat;
        canonicalItem.latitude = knownCentroid.lat;
        canonicalItem.Longitude = knownCentroid.lng;
        canonicalItem.longitude = knownCentroid.lng;
      }
    }
    updates[`/SubRequests/${slotKey}`] = canonicalItem;
    updates[`/creatorSubRequestFeed/${callerId}/${slotKey}`] = buildSanitizedFeedItem(canonicalItem);

  });

  // 4. Write publication manifest
  updates[`/subRequestPublications/${publicationId}`] = {
    publicationId,
    requestGroupId,
    creatorUserId: callerId,
    bandId: bandId || null,
    bandName: bandName || 'Freelance Gig',
    publishedAt: now,
    slots: resolvedSlots.map(s => ({
      slotId: s.slotId || s.subRequestId,
      subRequestId: s.subRequestId || s.slotId,
      voicePart: s.voicePart || s.VoicePart || '',
      searchSource: s.searchSource || s.SearchSource || 'search_all',
      targetUserIds: s.targetUserIds || s.TargetUserIds || [],
      eventTitle: s.eventTitle || s.EventTitle || '',
      eventSequence: s.eventSequence || s.EventSequence || 1,
      date: s.date || s.Date || '',
      payAmountMinor: s.payAmountMinor || s.PayAmountMinor || null,
      currency: s.currency || s.Currency || 'SEK',
    })),
  };

  if (callerId) {
    updates[`/creatorSubRequestGroups/${callerId}/${requestGroupId}`] = true;
  }

  // 5. Populate feeds according to least-privilege security model
  function matchesInstrument(requested, userSkills) {
    if (!requested || !requested.trim()) return true;
    const nonGeneric = userSkills.filter(s => {
      if (!s) return false;
      const l = s.trim().toLowerCase();
      return l.length > 0 &&
        l !== 'musician' &&
        l !== 'browse musicians' &&
        l !== 'browse profiles' &&
        l !== 'browse_musicians' &&
        l !== 'artist' &&
        l !== 'band member';
    });
    if (nonGeneric.length === 0) return true;

    const reqClean = requested.trim().toLowerCase().replace(/[\s\-_]/g, '');
    const reqLower = requested.trim().toLowerCase();

    for (const skill of nonGeneric) {
      const skillLower = skill.trim().toLowerCase();
      const skillClean = skillLower.replace(/[\s\-_]/g, '');
      if (!skillLower) continue;

      if (skillLower === reqLower || skillClean === reqClean) return true;
      if (skillLower.includes(reqLower) || reqLower.includes(skillLower)) return true;
      if (skillClean.includes(reqClean) || reqClean.includes(skillClean)) return true;

      if ((reqLower.includes('guitar') || reqLower.includes('gitarr')) && (skillLower.includes('guitar') || skillLower.includes('gitarr'))) return true;
      if ((reqLower.includes('bass') || reqLower.includes('bas')) && (skillLower.includes('bass') || skillLower.includes('bas'))) return true;
      if ((reqLower.includes('drum') || reqLower.includes('slagverk') || reqLower.includes('percussion') || reqLower.includes('trumm')) && (skillLower.includes('drum') || skillLower.includes('slagverk') || skillLower.includes('percussion') || skillLower.includes('trumm'))) return true;
      if ((reqLower.includes('vocal') || reqLower.includes('sing') || reqLower.includes('sång') || reqLower.includes('sang') || reqLower.includes('voice') || reqLower.includes('kör')) && (skillLower.includes('vocal') || skillLower.includes('sing') || skillLower.includes('sång') || skillLower.includes('sang') || skillLower.includes('voice') || skillLower.includes('kör'))) return true;
      if ((reqLower.includes('key') || reqLower.includes('piano') || reqLower.includes('synth') || reqLower.includes('klaviatur') || reqLower.includes('orgel')) && (skillLower.includes('key') || skillLower.includes('piano') || skillLower.includes('synth') || skillLower.includes('klaviatur') || skillLower.includes('orgel'))) return true;
      if ((reqLower.includes('sax') || reqLower.includes('horn') || reqLower.includes('brass') || reqLower.includes('trumpet') || reqLower.includes('trombone') || reqLower.includes('blås')) && (skillLower.includes('sax') || skillLower.includes('horn') || skillLower.includes('brass') || skillLower.includes('trumpet') || skillLower.includes('trombone') || skillLower.includes('blås'))) return true;
    }
    return false;
  }

  const usersSnap = await db.ref('/users').once('value');
  const users = usersSnap.val() || {};

  for (const slot of resolvedSlots) {
    const slotKey = slot.subRequestId;
    const sanitizedItem = buildSanitizedFeedItem({
      ...slot,
      SubRequestId: slotKey,
      SlotId: slot.slotId || slotKey,
      RequestGroupId: requestGroupId,
      PublicationId: publicationId,
      CreatorUserId: callerId,
      Status: 'published',
      CreatedAt: slot.createdAt || slot.CreatedAt || now,
      UpdatedAt: now,
    });

    const kind = classifySubRequest(slot);

    if (kind === SUBREQUEST_KIND.PROMO_MAP_PIN) {
      // Ordinary music pins stay isolated and never appear in SubRequest feeds
      continue;
    }

    const rawTargetUserIds = Array.isArray(slot.targetUserIds || slot.TargetUserIds)
      ? (slot.targetUserIds || slot.TargetUserIds)
      : [];

    let eligibleRecipientUids = [];

    if (kind === SUBREQUEST_KIND.PUBLIC_GIG || kind === SUBREQUEST_KIND.EVENT_SUBSTITUTE_PUBLIC) {
      // Truly public: readable by all authenticated users
      updates[`/publicSubRequests/${slotKey}`] = sanitizedItem;

      // Audience indexing for public matching users
      const voicePart = slot.voicePart || slot.VoicePart || slot.role || slot.Role || '';
      Object.keys(users).forEach(uid => {
        if (uid === callerId) return;
        const userObj = users[uid] || {};
        const userInfo = userObj.info || {};
        const userSkills = [];
        const rawUserType = userInfo.UserType || userInfo.userType || userObj.UserType || userObj.userType || '';
        if (rawUserType) userSkills.push(rawUserType);
        const rawMain = userInfo.MainInstrument || userInfo.mainInstrument || userObj.MainInstrument || userObj.mainInstrument || '';
        if (rawMain) {
          rawMain.split(',').forEach(s => { if (s.trim()) userSkills.push(s.trim()); });
        }
        const rawInsts = userInfo.Instruments || userInfo.instruments || userObj.Instruments || userObj.instruments || userObj.Instruments_user || [];
        if (Array.isArray(rawInsts)) {
          rawInsts.forEach(i => { if (i && typeof i === 'string') userSkills.push(i.trim()); });
        } else if (typeof rawInsts === 'object') {
          Object.values(rawInsts).forEach(i => { if (i && typeof i === 'string') userSkills.push(i.trim()); });
        }
        if (matchesInstrument(voicePart, userSkills)) {
          eligibleRecipientUids.push(uid);
        }
      });
    } else if (kind === SUBREQUEST_KIND.FAVORITES_ONLY) {
      // Public feed entry must be removed if converted to private
      updates[`/publicSubRequests/${slotKey}`] = null;

      if (rawTargetUserIds.length > 0) {
        eligibleRecipientUids = rawTargetUserIds.filter(uid => callerFavorites[uid] === true || callerFavorites[uid] === 'true');
      } else {
        eligibleRecipientUids = Object.keys(callerFavorites).filter(uid => callerFavorites[uid] === true || callerFavorites[uid] === 'true');
      }
    } else {
      // Direct invitation
      updates[`/publicSubRequests/${slotKey}`] = null;
      eligibleRecipientUids = rawTargetUserIds;
    }

    // Clean up previous audience members who are no longer eligible
    const existingAudienceSnap = await db.ref(`/subRequestAudience/${slotKey}`).once('value');
    const existingAudience = existingAudienceSnap.val() || {};
    for (const oldUid of Object.keys(existingAudience)) {
      if (!eligibleRecipientUids.includes(oldUid)) {
        updates[`/userSubRequestFeed/${oldUid}/${slotKey}`] = null;
        updates[`/subRequestAudience/${slotKey}/${oldUid}`] = null;
      }
    }

    for (const targetUid of eligibleRecipientUids) {
      if (targetUid && targetUid !== callerId) {
        updates[`/userSubRequestFeed/${targetUid}/${slotKey}`] = sanitizedItem;
        updates[`/subRequestAudience/${slotKey}/${targetUid}`] = true;
      }
    }
  }

  // Single atomic root multi-location update containing all feeds and manifest
  await db.ref().update(updates);

  return {
    success: true,
    publicationId,
    requestGroupId,
    slotCount: slots.length,
  };
});

exports.respondToSubRequest = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  const userId = request.auth.uid;
  const rawSubRequestId = request.data?.subRequestId;
  if (!rawSubRequestId || typeof rawSubRequestId !== 'string' || !rawSubRequestId.trim()) {
    throw new HttpsError('invalid-argument', 'subRequestId is required.');
  }
  const subRequestId = rawSubRequestId.trim();

  const db = admin.database();
  const subSnap = await db.ref(`SubRequests/${subRequestId}`).get();
  if (!subSnap.exists()) {
    throw new HttpsError('not-found', 'SubRequest not found.');
  }

  const val = subSnap.val() || {};

  // 1. Reject promotional map-only pins
  const mode = (val.NotificationMode || val.notificationMode || '').toString().trim().toLowerCase();
  if (mode === 'map_pin') {
    throw new HttpsError('failed-precondition', 'Cannot apply to a promotional map pin.');
  }

  // 2. Reject self-application by creator
  const creatorId = val.CreatorUserId || val.creatorUserId || val.UserId || val.userId;
  if (creatorId && creatorId === userId) {
    throw new HttpsError('permission-denied', 'You cannot respond to your own substitute request.');
  }

  // 3. Reject Band Leader or Admin of the band that owns the request
  const bandId = (val.BandId || val.bandId || '').toString().trim();
  if (bandId && bandId !== 'freelance' && bandId !== 'standalone') {
    const roleSnap = await db.ref(`Bands/${bandId}/Members_band/${userId}/Role`).get();
    const roleVal = roleSnap.exists() ? String(roleSnap.val() || '').trim() : '';
    if (roleVal === 'Leader' || roleVal === 'Admin') {
      throw new HttpsError('permission-denied', 'Band administrators should manage rather than apply to their band requests.');
    }
  }

  // 4. Reject non-open status or already-assigned requests
  const rawStatus = (val.Status || val.status || 'published').toString().trim().toLowerCase();
  const assignedUserId = (val.AssignedUserId || val.assignedUserId || '').toString().trim();
  const isSelected = val.IsSelected === true || val.isSelected === true;
  if (
    rawStatus === 'assigned' ||
    rawStatus === 'cancelled' ||
    rawStatus === 'deleted' ||
    rawStatus === 'closed' ||
    rawStatus === 'archived' ||
    (rawStatus !== 'published' && rawStatus !== 'open' && rawStatus !== 'active') ||
    assignedUserId.length > 0 ||
    isSelected
  ) {
    throw new HttpsError('failed-precondition', 'This request is no longer open for applications.');
  }

  // 5. Enforce audience authorization for private / targeted requests
  const kind = classifySubRequest(val);
  if (kind === SUBREQUEST_KIND.DIRECT_INVITATION || kind === SUBREQUEST_KIND.FAVORITES_ONLY) {
    const rawTargets = val.TargetUserIds || val.targetUserIds;
    const inTargetList = Array.isArray(rawTargets) && rawTargets.includes(userId);
    let inAudienceIndex = false;
    if (!inTargetList) {
      const audSnap = await db.ref(`subRequestAudience/${subRequestId}/${userId}`).get();
      inAudienceIndex = audSnap.exists() && audSnap.val() === true;
    }
    if (!inTargetList && !inAudienceIndex) {
      throw new HttpsError('permission-denied', 'You are not authorized to apply to this private request.');
    }
  }

  // 6. Idempotency check: if user already applied to this exact subRequestId, ensure user AppliedSubRequests is synced and return without duplicate notifications
  const existingResponses = val.Responses || val.responses || {};
  const alreadyApplied =
    existingResponses[userId] === true ||
    existingResponses[userId] === 'true' ||
    (typeof existingResponses[userId] === 'object' && existingResponses[userId] !== null);

  if (alreadyApplied) {
    const idempotentUpdates = {};
    idempotentUpdates[`users/${userId}/AppliedSubRequests/${subRequestId}`] = true;
    idempotentUpdates[`subRequestAudience/${subRequestId}/${userId}`] = true;
    await db.ref().update(idempotentUpdates);
    await notifyRequestResponse(subRequestId, userId).catch(error =>
      console.warn('Request response notification unavailable:', error?.code || 'unknown'));
    return { success: true, alreadyApplied: true, subRequestId };
  }

  const updates = {};
  updates[`SubRequests/${subRequestId}/Responses/${userId}`] = true;
  updates[`subRequestAudience/${subRequestId}/${userId}`] = true;
  updates[`users/${userId}/AppliedSubRequests/${subRequestId}`] = true;
  await db.ref().update(updates);
  await notifyRequestResponse(subRequestId, userId).catch(error =>
    console.warn('Request response notification unavailable:', error?.code || 'unknown'));
  return { success: true, alreadyApplied: false, subRequestId };
});

/**
 * Server-owned Cloud Function callable to securely delete or cancel a SubRequest.
 */
exports.deleteSubRequest = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  const callerId = request.auth.uid;
  const subRequestId = request.data?.subRequestId;
  if (!subRequestId) {
    throw new HttpsError('invalid-argument', 'subRequestId is required.');
  }

  membershipAuthority.key(subRequestId,'request ID');

  const db = admin.database();
  const subSnap = await db.ref(`SubRequests/${subRequestId}`).get();
  if (!subSnap.exists()) {
    return { success: true };
  }

  const val = subSnap.val() || {};
  const creatorId = val.CreatorUserId || val.creatorUserId || val.UserId || val.userId;
  const ownership = await membershipAuthority.authorizeRequest(db,callerId,val,request.data?.bandId,request.data?.eventId);
  const bandId = ownership.bandId;

  // Fetch all audience recipients for atomic removal
  const audienceSnap = await db.ref(`subRequestAudience/${subRequestId}`).once('value');
  const audience = audienceSnap.val() || {};
  const recipientUids = Object.keys(audience);
  const extraTargets = Array.isArray(val.TargetUserIds) ? val.TargetUserIds : (Array.isArray(val.targetUserIds) ? val.targetUserIds : []);
  for (const tUid of extraTargets) {
    if (tUid && !recipientUids.includes(tUid)) {
      recipientUids.push(tUid);
    }
  }

  const updates = {};
  updates[`SubRequests/${subRequestId}`] = null;
  updates[`publicSubRequests/${subRequestId}`] = null;
  updates[`publicMapPinFeed/${subRequestId}`] = null;
  if (creatorId) {
    updates[`creatorSubRequestFeed/${creatorId}/${subRequestId}`] = null;

  }
  for (const rUid of recipientUids) {
    updates[`userSubRequestFeed/${rUid}/${subRequestId}`] = null;
  }
  updates[`subRequestAudience/${subRequestId}`] = null;



  await db.ref().update(updates);

  return { success: true };
});

exports.assignSubstitute = onCall({ region: 'europe-west1' }, async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const {
    subRequestId,
    candidateUserId,
    candidateName,
    bandId,
    eventId,
    roleOrInstrument,
    slotId,
    replacedMemberId,
    replacedMemberName,
  } = request.data || {};

  if (!subRequestId || !candidateUserId) {
    throw new HttpsError('invalid-argument', 'subRequestId and candidateUserId are required.');
  }

  membershipAuthority.key(subRequestId,'request ID');
  membershipAuthority.key(candidateUserId,'candidate ID');

  const db = admin.database();
  const subReqRef = db.ref(`/SubRequests/${subRequestId}`);
  const subReqSnap = await subReqRef.once('value');
  if (!subReqSnap.exists()) {
    throw new HttpsError('not-found', `SubRequest ${subRequestId} does not exist.`);
  }

  const subReqData = subReqSnap.val();
  const ownership = await membershipAuthority.authorizeRequest(db,callerId,subReqData,bandId,eventId);
  const targetBandId = ownership.bandId;
  const targetEventId = ownership.eventId;
  const creatorUserId = ownership.creatorId;
  if (candidateUserId === creatorUserId) throw new HttpsError('invalid-argument','Creator cannot assign themselves as substitute.');

  const callerMember = !targetBandId ? null :
    (await db.ref(`Bands/${targetBandId}/Members_band/${callerId}`).get()).val();
  const addsMember = isNewMemberRequest(subReqData) || (!!targetEventId && membershipAuthority.manager(callerMember));
  if (addsMember) await membershipAuthority.requireManager(db,targetBandId,callerId);
  // Candidate eligibility check: candidate must have applied/responded, be targeted, or invited
  const currentAssignedIdCheck = subReqData.AssignedUserId || subReqData.assignedUserId;
  const responsesSnap = await db.ref(`/SubRequests/${subRequestId}/Responses/${candidateUserId}`).once('value');
  const audienceSnapCheck = await db.ref(`/subRequestAudience/${subRequestId}/${candidateUserId}`).once('value');
  const extraTargetsCheck = Array.isArray(subReqData.TargetUserIds) ? subReqData.TargetUserIds : (Array.isArray(subReqData.targetUserIds) ? subReqData.targetUserIds : []);
  const isCandidateEligible = responsesSnap.exists() ||
    audienceSnapCheck.exists() ||
    extraTargetsCheck.includes(candidateUserId) ||
    currentAssignedIdCheck === candidateUserId;

  if (!isCandidateEligible) {
    throw new HttpsError('failed-precondition', 'Candidate has not applied or been invited for this request.');
  }

  // Validate the real candidate before the canonical claim can commit.
  try {
    const candidate = await admin.auth().getUser(candidateUserId);
    if (candidate.disabled) throw new Error('disabled');
  } catch (_) { throw new HttpsError('failed-precondition','Candidate account is unavailable.'); }

  const now = Date.now();
  const actualSlotId = slotId || subReqData.SlotId || subReqData.slotId || subRequestId;

  // Real server-side RTDB atomic transaction on canonical SubRequest
  let committed = false;
  let txError = null;
  let alreadyAssignedToSame = false;

  await new Promise((resolve) => {
    subReqRef.transaction((current) => {
      if (current === null) return current;
      const currentAssignedId = current.AssignedUserId || current.assignedUserId;
      const isSelected = current.IsSelected === true || current.Status === 'assigned' || current.Status === 'filled';

      if (isSelected && currentAssignedId === candidateUserId) {
        alreadyAssignedToSame = true;
        return current; // Idempotent success
      }

      if (isSelected && currentAssignedId && currentAssignedId !== candidateUserId) {
        return; // Abort transaction on conflict
      }

      if (current.Status === 'cancelled' || current.Status === 'closed') {
        return; // Abort on closed/cancelled
      }

      current.IsSelected = true;
      current.Status = 'assigned';
      current.AssignedUserId = candidateUserId;
      if (candidateName) {
        current.AssignedUserName = candidateName;
      }
      current.AssignedAt = now;
      current.AssignedBy = callerId;
      return current;
    }, (error, wasCommitted) => {
      txError = error;
      committed = wasCommitted;
      resolve();
    });
  });

  if (txError) {
    throw new HttpsError('internal', txError.message);
  }

  if (!committed && !alreadyAssignedToSame) {
    throw new HttpsError('already-exists', `Slot ${subRequestId} has already been assigned to another candidate.`);
  }

  if (addsMember) {
    const existing = (await db.ref(`Bands/${targetBandId}/Members_band/${candidateUserId}`).get()).val();
    if (!existing) await membershipAuthority.mutate(db,callerId,{
      action:'add',bandId:targetBandId,userId:candidateUserId,role:'Member',
      nickname:candidateName || 'Member',operationId:`assignment_${crypto.createHash('sha256').update(`${subRequestId}/${candidateUserId}`).digest('hex')}`,
    });
  }

  // Multi-location idempotent derived updates (band event substitute assignments, externalInvitees, creator index)
  const updates = {};
  if (targetBandId && targetEventId) {
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/substituteAssignments/${actualSlotId}`] = {
      slotId: actualSlotId,
      subRequestId: subRequestId,
      assignedUserId: candidateUserId,
      assignedUserName: candidateName || `Candidate ${candidateUserId}`,
      instrument: roleOrInstrument || subReqData.VoicePart || '',
      replacedMemberId: replacedMemberId || null,
      replacedMemberName: replacedMemberName || null,
      status: 'assigned',
      assignedAt: now,
      assignedBy: callerId,
    };

    updates[`/Bands/${targetBandId}/Events/${targetEventId}/Responses/${candidateUserId}`] = {
      status: 'YES',
      timestamp: new Date(now).toISOString(),
    };

    updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/userId`] = candidateUserId;
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/status`] = 'attending';
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/instrument`] = roleOrInstrument || subReqData.VoicePart || '';
    if (candidateName) {
      updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/displayName`] = candidateName;
    }
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/source`] = 'subRequest';
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/subRequestId`] = subRequestId;
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/updatedAt`] = now;


  }


  // Remove the public feed entry so the slot is no longer open
  updates[`/publicSubRequests/${subRequestId}`] = null;

  // Remove from userSubRequestFeed for all audience recipients
  const audienceSnap = await db.ref(`/subRequestAudience/${subRequestId}`).once('value');
  const audience = audienceSnap.val() || {};
  const recipientUids = Object.keys(audience);
  const extraTargets = Array.isArray(subReqData.TargetUserIds) ? subReqData.TargetUserIds : (Array.isArray(subReqData.targetUserIds) ? subReqData.targetUserIds : []);
  for (const tUid of extraTargets) {
    if (tUid && !recipientUids.includes(tUid)) {
      recipientUids.push(tUid);
    }
  }
  for (const rUid of recipientUids) {
    updates[`/userSubRequestFeed/${rUid}/${subRequestId}`] = null;
  }

  // Update creatorSubRequestFeed with assignment status
  const actualCreatorId = creatorUserId || callerId;
  if (actualCreatorId) {
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/isSelected`] = true;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/status`] = 'assigned';
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedUserId`] = candidateUserId;
    if (candidateName) {
      updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedUserName`] = candidateName;
    }
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedAt`] = now;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedBy`] = callerId;
  }

  // Deterministic, idempotent Agreement conversation ID reservation
  const agreementConvKeyRaw = `agreement_${subRequestId}_${candidateUserId}`;
  const agreementConvHash = crypto.createHash('sha256').update(agreementConvKeyRaw).digest('hex');
  const agreementKeyRef = db.ref(`/agreementConversationKeys/${agreementConvHash}`);

  let conversationId;
  const txResult = await agreementKeyRef.transaction((current) => {
    if (current && current.conversationId) {
      return current;
    }
    const newId = db.ref('/conversations').push().key;
    return {
      conversationId: newId,
      createdTimestamp: new Date().toISOString(),
    };
  });

  const keyVal = txResult.snapshot.val();
  conversationId = keyVal ? keyVal.conversationId : null;
  if (!conversationId) {
    throw new HttpsError('internal', 'Failed to resolve agreement conversation ID.');
  }

  // Resolve band authority strictly
  let resolvedBandName = null;
  if (targetBandId) {
    try {
      const bSnap = await db.ref(`/Bands/${targetBandId}`).once('value');
      if (bSnap.exists()) {
        const bData = bSnap.val() || {};
        const cand = bData.BandName || bData.bandName || bData.Name || bData.name;
        if (cand && typeof cand === 'string' && cand.trim().length > 0) {
          resolvedBandName = cand.trim();
        }
      }
    } catch (_) {}
  }
  if (!resolvedBandName) {
    const rawBName = subReqData.BandName || subReqData.bandName;
    if (rawBName && typeof rawBName === 'string') {
      const lower = rawBName.trim().toLowerCase();
      if (lower !== 'null' && lower !== 'n/a' && lower !== 'gig agreement' && lower !== 'band / project' && lower !== 'unknown band' && lower !== 'band') {
        resolvedBandName = rawBName.trim();
      }
    }
  }

  let creatorName = 'Organizer';
  try {
    const cSnap = await db.ref(`/users/${actualCreatorId}`).once('value');
    if (cSnap.exists()) {
      const cVal = cSnap.val() || {};
      const cInfo = cVal.info || {};
      creatorName = cVal.displayName || cVal.nickname || cVal.DisplayName || cInfo.displayName || cInfo.nickname || cInfo.DisplayName || cInfo.Name || 'Organizer';
    }
  } catch (_) {}

  let candidateDisplayName = candidateName || 'Musician';
  try {
    const uSnap = await db.ref(`/users/${candidateUserId}`).once('value');
    if (uSnap.exists()) {
      const uVal = uSnap.val() || {};
      const uInfo = uVal.info || {};
      candidateDisplayName = uVal.displayName || uVal.nickname || uVal.DisplayName || uInfo.displayName || uInfo.nickname || uInfo.DisplayName || uInfo.Name || candidateDisplayName;
    }
  } catch (_) {}

  const agreementRole = roleOrInstrument || subReqData.VoicePart || subReqData.voicePart || subReqData.Role || subReqData.role || 'Musician';
  const agreementDate = subReqData.Date || subReqData.date || subReqData.startDateTime || null;
  const agreementStartTime = subReqData.StartTime || subReqData.startTime || null;
  const agreementEndTime = subReqData.EndTime || subReqData.endTime || null;
  const agreementLocation = subReqData.Location || subReqData.location || null;
  const agreementDesc = subReqData.Description || subReqData.description || null;
  const agreementPayDetails = subReqData.PayDetails || subReqData.payDetails || null;
  const agreementTerms = subReqData.AdditionalTerms || subReqData.additionalTerms || 'Substitute staffing assignment.';
  const agreementPay = subReqData.PayAmount !== undefined ? subReqData.PayAmount : (subReqData.payAmount !== undefined ? subReqData.payAmount : null);
  const agreementCurrency = subReqData.Currency || subReqData.currency || null;
  const agreementReqType = subReqData.RequestType || subReqData.requestType || 'Substitute';
  const agreementEventType = subReqData.EventType || subReqData.eventType || null;
  const agreementReqGroupId = subReqData.RequestGroupId || subReqData.requestGroupId || null;

  const agreementPayload = {
    subRequestId: subRequestId,
    requestGroupId: agreementReqGroupId,
    eventId: targetEventId || null,
    bandId: targetBandId || null,
    bandName: resolvedBandName,
    requestType: agreementReqType,
    eventType: agreementEventType,
    role: agreementRole,
    voicePart: agreementRole,
    date: agreementDate,
    startTime: agreementStartTime,
    endTime: agreementEndTime,
    location: agreementLocation,
    description: agreementDesc,
    payDetails: agreementPayDetails,
    additionalTerms: agreementTerms,
    payAmount: agreementPay,
    currency: agreementCurrency,
    choirLeaderId: actualCreatorId,
    vocalistId: candidateUserId,
    choirLeaderName: creatorName,
    vocalistName: candidateDisplayName,
    status: 'confirmed',
    createdAt: now,

    // Legacy PascalCase aliases for backward compatibility
    ChoirLeaderId: actualCreatorId,
    VocalistId: candidateUserId,
    VoicePart: agreementRole,
    Date: agreementDate,
    StartTime: agreementStartTime,
    EndTime: agreementEndTime,
    Location: agreementLocation,
    AdditionalTerms: agreementTerms,
    BandName: resolvedBandName,
    SubRequestId: subRequestId,
    PayAmount: agreementPay,
    Currency: agreementCurrency,
    Description: agreementDesc,
    PayDetails: agreementPayDetails,
    RequestType: agreementReqType,
    EventType: agreementEventType,
    BandId: targetBandId || null,
    EventId: targetEventId || null,
  };

  // Atomic root multi-path conversation, inbox, and mirror updates
  updates[`/conversations/${conversationId}/agreement`] = agreementPayload;
  updates[`/conversations/${conversationId}/Agreement`] = agreementPayload;
  updates[`/conversations/${conversationId}/participants`] = { [actualCreatorId]: true, [candidateUserId]: true };
  updates[`/conversations/${conversationId}/Participants`] = [actualCreatorId, candidateUserId];
  updates[`/conversations/${conversationId}/createdTimestamp`] = new Date(now).toISOString();
  updates[`/conversations/${conversationId}/lastActivity`] = now;

  const summaryMsg = `Confirmed Agreement: ${agreementRole}`;
  updates[`/userConversations/${actualCreatorId}/${conversationId}`] = {
    conversationId: conversationId,
    conversationType: 'agreement',
    otherUserId: candidateUserId,
    otherUserName: candidateDisplayName,
    lastMessageText: summaryMsg,
    lastMessageTimestamp: new Date(now).toISOString(),
    hasUnread: false,
    agreement: agreementPayload,
    bandName: resolvedBandName,
    bandId: targetBandId || null,
  };
  updates[`/userConversations/${candidateUserId}/${conversationId}`] = {
    conversationId: conversationId,
    conversationType: 'agreement',
    otherUserId: actualCreatorId,
    otherUserName: creatorName,
    lastMessageText: summaryMsg,
    lastMessageTimestamp: new Date(now).toISOString(),
    hasUnread: true,
    agreement: agreementPayload,
    bandName: resolvedBandName,
    bandId: targetBandId || null,
  };




  if (Object.keys(updates).length > 0) {
    await db.ref().update(updates);
  }

  try {
    const assignment = (await subReqRef.get()).val();
    const assignedAt = assignment?.AssignedAt ?? assignment?.assignedAt;
    if ((assignment?.AssignedUserId ?? assignment?.assignedUserId) === candidateUserId &&
        Number.isSafeInteger(assignedAt)) {
      await publishNotification(candidateUserId, 'gig_finalized', [subRequestId, assignedAt], {
        subRequestId, assignedAt,
        ...(targetBandId ? { bandId: targetBandId } : {}),
        ...(targetEventId ? { eventId: targetEventId } : {}),
      });
    }
  } catch (error) {
    console.warn('Assignment notification unavailable:', error?.code || 'unknown');
  }

  return {
    success: true,
    subRequestId,
    assignedUserId: candidateUserId,
    status: 'assigned',
    conversationId,
    agreement: agreementPayload,
  };
});

/**
 * Secure server-owned Cloud Function callable to revoke a substitute assignment.
 */
exports.revokeSubstituteAssignment = onCall({ region: 'europe-west1' }, async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { subRequestId, candidateUserId, bandId, eventId, slotId } = request.data || {};
  if (!subRequestId) {
    throw new HttpsError('invalid-argument', 'subRequestId is required.');
  }

  membershipAuthority.key(subRequestId,'request ID');

  const db = admin.database();
  const subReqRef = db.ref(`/SubRequests/${subRequestId}`);
  const subReqSnap = await subReqRef.once('value');
  if (!subReqSnap.exists()) {
    throw new HttpsError('not-found', `SubRequest ${subRequestId} does not exist.`);
  }

  const subReqData = subReqSnap.val();
  const ownership = await membershipAuthority.authorizeRequest(db,callerId,subReqData,bandId,eventId);
  const targetBandId = ownership.bandId;
  const targetEventId = ownership.eventId;
  const creatorUserId = ownership.creatorId;

  const actualSlotId = slotId || subReqData.SlotId || subReqData.slotId || subRequestId;
  const updates = {};

  updates[`/SubRequests/${subRequestId}/IsSelected`] = false;
  updates[`/SubRequests/${subRequestId}/Status`] = 'published';
  updates[`/SubRequests/${subRequestId}/AssignedUserId`] = null;
  updates[`/SubRequests/${subRequestId}/AssignedUserName`] = null;
  updates[`/SubRequests/${subRequestId}/AssignedAt`] = null;
  updates[`/SubRequests/${subRequestId}/AssignedBy`] = null;

  if (targetBandId && targetEventId) {
    updates[`/Bands/${targetBandId}/Events/${targetEventId}/substituteAssignments/${actualSlotId}`] = null;
  }

  const actualCreatorId = creatorUserId || callerId;
  if (actualCreatorId) {






    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/isSelected`] = false;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/status`] = 'published';
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedUserId`] = null;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedUserName`] = null;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedAt`] = null;
    updates[`/creatorSubRequestFeed/${actualCreatorId}/${subRequestId}/assignedBy`] = null;
  }

  // Re-classify and restore to appropriate feed
  const restoredSubReq = {
    ...subReqData,
    IsSelected: false,
    Status: 'published',
    AssignedUserId: null,
    AssignedUserName: null,
    AssignedAt: null,
    AssignedBy: null,
    updatedAt: Date.now(),
  };

  const kind = classifySubRequest(restoredSubReq);
  const sanitizedItem = buildSanitizedFeedItem(restoredSubReq);

  if (kind === SUBREQUEST_KIND.PUBLIC_GIG || kind === SUBREQUEST_KIND.EVENT_SUBSTITUTE_PUBLIC) {
    updates[`/publicSubRequests/${subRequestId}`] = sanitizedItem;
  } else if (kind === SUBREQUEST_KIND.DIRECT_INVITATION || kind === SUBREQUEST_KIND.FAVORITES_ONLY) {
    const audienceSnap = await db.ref(`/subRequestAudience/${subRequestId}`).once('value');
    const audience = audienceSnap.val() || {};
    const recipientUids = Object.keys(audience);
    const extraTargets = Array.isArray(restoredSubReq.TargetUserIds) ? restoredSubReq.TargetUserIds : (Array.isArray(restoredSubReq.targetUserIds) ? restoredSubReq.targetUserIds : []);
    for (const tUid of extraTargets) {
      if (tUid && !recipientUids.includes(tUid)) {
        recipientUids.push(tUid);
      }
    }
    for (const rUid of recipientUids) {
      updates[`/userSubRequestFeed/${rUid}/${subRequestId}`] = sanitizedItem;
    }
  }
  await db.ref().update(updates);

  return { success: true, subRequestId };
});

/**
 * HTTPS Triggered function to compile app usage metrics for investors.
 */
exports.getAppMetrics = functions.region('europe-west1').https.onRequest(async (req, res) => {
  // CORS support
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'GET');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }

  try {
    const db = admin.database();

    // 1. Fetch Users
    const usersSnapshot = await db.ref('/users').once('value');
    const usersData = usersSnapshot.val() || {};
    const totalUsers = Object.keys(usersData).length;

    // 2. Fetch Bands
    const bandsSnapshot = await db.ref('/Bands').once('value');
    const bandsData = bandsSnapshot.val() || {};
    const totalBands = Object.keys(bandsData).length;

    // Calculate total events inside Bands
    let totalEvents = 0;
    Object.keys(bandsData).forEach(bandId => {
      const band = bandsData[bandId];
      if (band && band.Events) {
        totalEvents += Object.keys(band.Events).length;
      }
    });

    // 3. Fetch Sub Requests
    const subReqSnapshot = await db.ref('/SubRequests').once('value');
    const subReqData = subReqSnapshot.val() || {};
    const totalSubRequests = Object.keys(subReqData).length;

    // 4. Fetch Marketplace Listings
    const marketSnapshot = await db.ref('/marketplaceListings').once('value');
    const marketData = marketSnapshot.val() || {};
    const totalMarketplaceItems = Object.keys(marketData).length;

    // 5. Calculate Activity & Engagement
    let usersWithAudio = 0;
    let totalBandsJoined = 0;
    const globalButtonClicks = {
      find_musicians: 0,
      browse_musicians: 0,
      find_gigs: 0,
      band_room: 0,
      marketplace: 0
    };

    Object.keys(usersData).forEach(userId => {
      const u = usersData[userId];
      if (!u) return;

      const info = u.info || {};
      if (info.AudioSnippetUrl) {
        usersWithAudio++;
      }
      if (u.Bands) {
        totalBandsJoined += Object.keys(u.Bands).length;
      }

      // Sum button click metrics
      const metrics = u.metrics || {};
      const clicks = metrics.buttonClicks || {};
      Object.keys(clicks).forEach(buttonId => {
        if (globalButtonClicks[buttonId] !== undefined) {
          globalButtonClicks[buttonId] += clicks[buttonId];
        } else {
          globalButtonClicks[buttonId] = clicks[buttonId];
        }
      });
    });

    const metricsPayload = {
      timestamp: new Date().toISOString(),
      summary: {
        totalUsers,
        totalBands,
        totalEvents,
        totalSubRequests,
        totalMarketplaceItems
      },
      engagement: {
        usersWithAudio,
        averageBandsPerUser: totalUsers > 0 ? (totalBandsJoined / totalUsers).toFixed(2) : '0',
        audioSnippetAdoptionRate: totalUsers > 0 ? `${((usersWithAudio / totalUsers) * 100).toFixed(1)}%` : '0%'
      },
      featureUsage: {
        findMusicians: globalButtonClicks.find_musicians,
        browseMusicians: globalButtonClicks.browse_musicians,
        findGigs: globalButtonClicks.find_gigs,
        bandRoom: globalButtonClicks.band_room,
        marketplace: globalButtonClicks.marketplace
      },
      activityScore: totalEvents + totalSubRequests + totalMarketplaceItems
    };

    res.status(200).json(metricsPayload);
  } catch (error) {
    console.error('Error compiling metrics:', error);
    res.status(500).send('Internal Server Error compiling metrics: ' + error.message);
  }
});

/**
 * Triggered when a member responds to an event under /Bands/{bandId}/Events/{eventId}/Responses/{userId}.
 * Sends a push notification to the event creator when 70% or more of invited members have responded.
 */
exports.onEventResponseChanged = functions.region(databaseTriggerRegion).database
  .ref('/Bands/{bandId}/Events/{eventId}/Responses/{userId}')
  .onWrite(async (change, context) => {
    const bandId = context.params.bandId;
    const eventId = context.params.eventId;

    try {
      // 1. Fetch the event details
      const eventRef = admin.database().ref(`/Bands/${bandId}/Events/${eventId}`);
      const eventSnapshot = await eventRef.once('value');
      const eventData = eventSnapshot.val();

      if (!eventData) {
        console.log(`Event ${eventId} not found under band ${bandId}`);
        return null;
      }

      // Exit early if creatorThresholdNotified is already true or event is locked
      if (eventData.creatorThresholdNotified === true || eventData.isLocked === true) {
        console.log(`Event ${eventId} threshold already notified or event is locked.`);
        return null;
      }

      // 2. Fetch the band members
      const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);
      const membersSnapshot = await membersRef.once('value');
      const members = membersSnapshot.val();
      if (!members) {
        console.log(`No members found for band ${bandId}`);
        return null;
      }

      const totalMembersCount = Object.keys(members).length;
      if (totalMembersCount === 0) return null;

      // 3. Count responses
      const responses = eventData.Responses || {};
      const totalResponsesCount = Object.keys(responses).length;

      const responseRate = totalResponsesCount / totalMembersCount;
      console.log(`Event ${eventId} response count: ${totalResponsesCount}/${totalMembersCount} (${(responseRate * 100).toFixed(1)}%)`);

      // 4. If response rate is >= 70% (0.70)
      if (responseRate >= 0.70) {
        const creatorId = eventData.createdBy;
        if (!creatorId) {
          console.log(`No creatorId found on event ${eventId}`);
          return null;
        }

        try {
          await notificationAccess.authorizedEvent(admin.database(), creatorId, bandId, eventId);
          await publishNotification(creatorId, 'event_threshold', [bandId, eventId], { bandId, eventId });
        } catch (error) {
          if (error.code !== 'not-found') throw error;
        }

        // Update database to prevent repeated notifications
        await eventRef.child('creatorThresholdNotified').set(true);
      }

      return null;
    } catch (error) {
      console.error('Error in onEventResponseChanged trigger:', error);
      return null;
    }
  });

/**
 * Scheduled cron job running every hour to send automatic RSVP reminders
 * to members who have not responded after 48h, 72h, and 84h.
 */
exports.checkEventReminders = functions.region('europe-west1').pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      const now = Date.now();
      const bandsRef = admin.database().ref('/Bands');
      const bandsSnapshot = await bandsRef.once('value');
      const bands = bandsSnapshot.val();

      if (!bands) {
        console.log('No bands found for reminders check.');
        return null;
      }

      const bandIds = Object.keys(bands);

      for (const bandId of bandIds) {
        const eventsRef = admin.database().ref(`/Bands/${bandId}/Events`);
        const eventsSnapshot = await eventsRef.once('value');
        const events = eventsSnapshot.val();

        if (!events) continue;

        const eventIds = Object.keys(events);

        for (const eventId of eventIds) {
          const event = events[eventId];
          if (!event) continue;

          // Skip if locked
          if (event.isLocked === true) continue;

          // Skip if in the past
          if (event.startDateTime) {
            const startDate = new Date(event.startDateTime);
            if (startDate.getTime() <= now) {
              console.log(`Event ${eventId} has already started/passed. Skipping.`);
              continue;
            }
          }

          // Calculate hours elapsed since creation
          const createdAt = event.createdAt;
          if (!createdAt) continue;

          const hoursElapsed = (now - createdAt) / (1000 * 60 * 60);
          console.log(`Event ${eventId} created ${hoursElapsed.toFixed(1)} hours ago.`);

          let send48 = false;
          let send72 = false;
          let send84 = false;

          // Check flags using the exact model names
          if (hoursElapsed >= 48 && hoursElapsed < 72 && !event.sentReminder48h) {
            send48 = true;
          } else if (hoursElapsed >= 72 && hoursElapsed < 84 && !event.sentReminder72h) {
            send72 = true;
          } else if (hoursElapsed >= 84 && !event.sentReminder84h) {
            send84 = true;
          }

          if (send48 || send72 || send84) {
            console.log(`Triggering reminder for event ${eventId} (48h: ${send48}, 72h: ${send72}, 84h: ${send84})`);

            // Fetch band members
            const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);
            const membersSnapshot = await membersRef.once('value');
            const members = membersSnapshot.val() || {};
            const responses = event.Responses || {};
            const recipients = Object.keys(members).filter(uid => notificationMember(members[uid]) && !responses[uid]);
            const reminderHours = send84 ? '84h' : send72 ? '72h' : '48h';
            await Promise.all(recipients.map(uid => publishNotification(uid, 'event_reminder',
              [bandId, eventId, reminderHours], { bandId, eventId })));

            // Update database flags using the exact model names
            const updateObj = {};
            if (send48) updateObj['sentReminder48h'] = true;
            if (send72) updateObj['sentReminder72h'] = true;
            if (send84) updateObj['sentReminder84h'] = true;

            await admin.database().ref(`/Bands/${bandId}/Events/${eventId}`).update(updateObj);
          }
        }
      }
      return null;
    } catch (err) {
      console.error('Error in checkEventReminders scheduler:', err);
      return null;
    }
  });

exports.onCollabSessionApplicationChanged = onValueWritten({
  ref: '/Collabs/Applications/{sessionId}/{applicantId}',
  region: databaseTriggerRegion
}, async (event) => {
  try {
    const beforeData = event.data.before.val();
    const afterData = event.data.after.val();

    if (!afterData) {
      console.log('Application was deleted, no notification sent.');
      return null;
    }

    const sessionId = event.params.sessionId;
    const applicantId = event.params.applicantId;

    const db = admin.database();
    const session = (await db.ref('Collabs/Sessions/' + sessionId).get()).val();
    if (!session) return null;
    if (!beforeData) {
      const creatorId = session.CreatorId ?? session.creatorId;
      if (notificationDelivery.safeKey(creatorId)) {
        await publishNotification(creatorId, 'session_application', [sessionId, event.id], {
          sessionId, applicantId,
        });
      }
      return null;
    }

    const beforeStatus = beforeData.Status ?? beforeData.status;
    const decision = afterData.Status ?? afterData.status;
    if (beforeStatus !== decision && ['accepted', 'declined'].includes(decision)) {
      await publishNotification(applicantId, 'session_application_status', [sessionId, event.id], {
        sessionId, decision,
      });
    }
    return null;
  } catch (err) {
    console.error('Error in onCollabSessionApplicationChanged trigger:', err);
    return null;
  }
});

// ============================================================================
// BACKEND-OWNED CALLABLE CLOUD FUNCTIONS (v2 - europe-west1)
// ============================================================================

/**
 * 1. getOrCreateDirectConversation
 */
exports.getOrCreateDirectConversation = onCall({ region: 'europe-west1' }, async (request) => {
  const uid1 = request.auth?.uid;
  if (!uid1) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const uid2 = request.data?.otherUserId;
  if (!uid2 || typeof uid2 !== 'string' || uid2.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'otherUserId must be a valid non-empty string.');
  }
  if (uid1 === uid2) {
    throw new HttpsError('invalid-argument', 'Cannot create a direct conversation with yourself.');
  }

  // Deterministic SHA-256 pair key
  const sorted = [uid1, uid2].sort();
  const pairKeyRaw = `${sorted[0]}_${sorted[1]}`;
  const pairHash = crypto.createHash('sha256').update(pairKeyRaw).digest('hex');

  const pairRef = admin.database().ref(`/directConversationKeys/${pairHash}`);

  let conversationId;
  const txResult = await pairRef.transaction((current) => {
    if (current && current.conversationId) {
      return current;
    }
    const newId = admin.database().ref('/conversations').push().key;
    return {
      conversationId: newId,
      createdTimestamp: new Date().toISOString(),
    };
  });

  if (!txResult.committed && !txResult.snapshot.exists()) {
    throw new HttpsError('internal', 'Transaction failed to claim or retrieve conversation key.');
  }

  const val = txResult.snapshot.val();
  conversationId = val ? val.conversationId : null;
  if (!conversationId) {
    throw new HttpsError('internal', 'Failed to resolve conversation ID.');
  }

  // Check existing canonical conversation
  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');
  const convVal = convSnap.val();

  if (convSnap.exists() && convVal) {
    // Requirement 3: Verify that an existing canonical conversation contains EXACTLY the expected participant pair
    const pMap = convVal.participants || convVal.Participants;
    let existingUids = [];
    if (Array.isArray(pMap)) {
      existingUids = pMap.map(String);
    } else if (pMap && typeof pMap === 'object') {
      existingUids = Object.keys(pMap);
    }

    const isMatch = existingUids.length === 2 &&
      existingUids.includes(sorted[0]) &&
      existingUids.includes(sorted[1]);

    if (!isMatch) {
      console.error(`Corrupted pair key ${pairHash}: conversation ${conversationId} participants mismatch. Expected ${sorted}, found ${existingUids}`);
      throw new HttpsError('data-loss', 'Conversation participant mismatch for pair key.');
    }
  } else {
    // Initialize new canonical conversation
    await convRef.set({
      participants: { [uid1]: true, [uid2]: true },
      Participants: [uid1, uid2],
      createdTimestamp: new Date().toISOString(),
      agreement: null,
    });
  }

  // Idempotent repair phase: Requirement 4 - merge ONLY missing structural fields
  const user1ConvRef = admin.database().ref(`/userConversations/${uid1}/${conversationId}`);
  const user2ConvRef = admin.database().ref(`/userConversations/${uid2}/${conversationId}`);

  const [u1Snap, u2Snap] = await Promise.all([
    user1ConvRef.once('value'),
    user2ConvRef.once('value'),
  ]);

  if (!u1Snap.exists()) {
    await user1ConvRef.set({
      otherUserId: uid2,
      lastMessageText: '',
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: false,
      conversationType: 'direct',
    });
  }

  if (!u2Snap.exists()) {
    await user2ConvRef.set({
      otherUserId: uid1,
      lastMessageText: '',
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: false,
      conversationType: 'direct',
    });
  }

  return { conversationId };
});

/**
 * 2. createAgreementConversation
 */
exports.createAgreementConversation = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const subRequestId = request.data?.subRequestId;
  const applicantId = request.data?.applicantId;

  if (!subRequestId || typeof subRequestId !== 'string' || subRequestId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'subRequestId is required.');
  }
  if (!applicantId || typeof applicantId !== 'string' || applicantId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'applicantId is required.');
  }

  membershipAuthority.key(subRequestId,'request ID');
  membershipAuthority.key(applicantId,'applicant ID');

  // Database verification: Load SubRequest
  const subReqSnap = await admin.database().ref(`/SubRequests/${subRequestId}`).once('value');
  if (!subReqSnap.exists()) {
    throw new HttpsError('not-found', `SubRequest ${subRequestId} does not exist.`);
  }
  const subReqData = subReqSnap.val();
  const creatorUid = subReqData.CreatorUserId || subReqData.UserId || subReqData.createdBy || subReqData.userId || subReqData.creatorUserId;

  if (!creatorUid) {
    throw new HttpsError('failed-precondition', 'SubRequest has no valid creator.');
  }

  const ownership = await membershipAuthority.authorizeRequest(admin.database(),callerUid,subReqData,request.data?.bandId,request.data?.eventId);
  const targetBandId = ownership.bandId;

  // Precondition: SubRequest must already be assigned or filled to applicantId
  const currentAssignedId = subReqData.AssignedUserId || subReqData.assignedUserId;
  const currentStatus = subReqData.Status || subReqData.status;
  if (currentStatus !== 'assigned' && currentStatus !== 'filled') {
    throw new HttpsError('failed-precondition', `SubRequest ${subRequestId} is not assigned or filled.`);
  }
  if (currentAssignedId !== applicantId) {
    throw new HttpsError('failed-precondition', `Applicant ${applicantId} does not match assigned user.`);
  }

  const agreementConvKeyRaw = `agreement_${subRequestId}_${applicantId}`;
  const agreementConvHash = crypto.createHash('sha256').update(agreementConvKeyRaw).digest('hex');

  const agreementKeyRef = admin.database().ref(`/agreementConversationKeys/${agreementConvHash}`);

  let conversationId;
  const txResult = await agreementKeyRef.transaction((current) => {
    if (current && current.conversationId) {
      return current;
    }
    const newId = admin.database().ref('/conversations').push().key;
    return {
      conversationId: newId,
      createdTimestamp: new Date().toISOString(),
    };
  });

  const val = txResult.snapshot.val();
  conversationId = val ? val.conversationId : null;
  if (!conversationId) {
    throw new HttpsError('internal', 'Failed to resolve agreement conversation ID.');
  }

  let resolvedBandName = null;
  if (targetBandId) {
    try {
      const bSnap = await admin.database().ref(`/Bands/${targetBandId}`).once('value');
      if (bSnap.exists()) {
        const bData = bSnap.val() || {};
        const cand = bData.BandName || bData.bandName || bData.Name || bData.name;
        if (cand && typeof cand === 'string' && cand.trim().length > 0) {
          resolvedBandName = cand.trim();
        }
      }
    } catch (_) {}
  }
  if (!resolvedBandName) {
    const rawBName = subReqData.BandName || subReqData.bandName;
    if (rawBName && typeof rawBName === 'string') {
      const lower = rawBName.trim().toLowerCase();
      if (lower !== 'null' && lower !== 'n/a' && lower !== 'gig agreement' && lower !== 'band / project' && lower !== 'unknown band' && lower !== 'band') {
        resolvedBandName = rawBName.trim();
      }
    }
  }

  let creatorName = 'Organizer';
  try {
    const cSnap = await admin.database().ref(`/users/${creatorUid}`).once('value');
    if (cSnap.exists()) {
      const cVal = cSnap.val() || {};
      const cInfo = cVal.info || {};
      creatorName = cVal.displayName || cVal.nickname || cVal.DisplayName || cInfo.displayName || cInfo.nickname || cInfo.DisplayName || cInfo.Name || 'Organizer';
    }
  } catch (_) {}

  let applicantDisplayName = 'Musician';
  try {
    const uSnap = await admin.database().ref(`/users/${applicantId}`).once('value');
    if (uSnap.exists()) {
      const uVal = uSnap.val() || {};
      const uInfo = uVal.info || {};
      applicantDisplayName = uVal.displayName || uVal.nickname || uVal.DisplayName || uInfo.displayName || uInfo.nickname || uInfo.DisplayName || uInfo.Name || applicantDisplayName;
    }
  } catch (_) {}

  const now = Date.now();
  const agreementRole = subReqData.VoicePart || subReqData.voicePart || subReqData.Role || subReqData.role || 'Musician';
  const agreementDate = subReqData.Date || subReqData.date || subReqData.startDateTime || null;
  const agreementStartTime = subReqData.StartTime || subReqData.startTime || null;
  const agreementEndTime = subReqData.EndTime || subReqData.endTime || null;
  const agreementLocation = subReqData.Location || subReqData.location || null;
  const agreementDesc = subReqData.Description || subReqData.description || null;
  const agreementPayDetails = subReqData.PayDetails || subReqData.payDetails || null;
  const agreementTerms = subReqData.AdditionalTerms || subReqData.additionalTerms || 'Substitute staffing assignment.';
  const agreementPay = subReqData.PayAmount !== undefined ? subReqData.PayAmount : (subReqData.payAmount !== undefined ? subReqData.payAmount : null);
  const agreementCurrency = subReqData.Currency || subReqData.currency || null;
  const agreementReqType = subReqData.RequestType || subReqData.requestType || 'Substitute';
  const agreementEventType = subReqData.EventType || subReqData.eventType || null;
  const agreementReqGroupId = subReqData.RequestGroupId || subReqData.requestGroupId || null;
  const targetEventId = subReqData.EventId || subReqData.eventId || null;

  // CANONICAL SNAPSHOT: Caller-supplied fields NEVER override canonical fields
  const agreementPayload = {
    subRequestId: subRequestId,
    requestGroupId: agreementReqGroupId,
    eventId: targetEventId,
    bandId: targetBandId || null,
    bandName: resolvedBandName,
    requestType: agreementReqType,
    eventType: agreementEventType,
    role: agreementRole,
    voicePart: agreementRole,
    date: agreementDate,
    startTime: agreementStartTime,
    endTime: agreementEndTime,
    location: agreementLocation,
    description: agreementDesc,
    payDetails: agreementPayDetails,
    additionalTerms: agreementTerms,
    payAmount: agreementPay,
    currency: agreementCurrency,
    choirLeaderId: creatorUid,
    vocalistId: applicantId,
    choirLeaderName: creatorName,
    vocalistName: applicantDisplayName,
    status: 'confirmed',
    createdAt: now,

    ChoirLeaderId: creatorUid,
    VocalistId: applicantId,
    VoicePart: agreementRole,
    Date: agreementDate,
    StartTime: agreementStartTime,
    EndTime: agreementEndTime,
    Location: agreementLocation,
    AdditionalTerms: agreementTerms,
    BandName: resolvedBandName,
    SubRequestId: subRequestId,
    PayAmount: agreementPay,
    Currency: agreementCurrency,
    Description: agreementDesc,
    PayDetails: agreementPayDetails,
    RequestType: agreementReqType,
    EventType: agreementEventType,
    BandId: targetBandId || null,
    EventId: targetEventId || null,
  };

  const atomicUpdates = {};
  atomicUpdates[`/conversations/${conversationId}/agreement`] = agreementPayload;
  atomicUpdates[`/conversations/${conversationId}/Agreement`] = agreementPayload;
  atomicUpdates[`/conversations/${conversationId}/participants`] = { [creatorUid]: true, [applicantId]: true };
  atomicUpdates[`/conversations/${conversationId}/Participants`] = [creatorUid, applicantId];
  atomicUpdates[`/conversations/${conversationId}/createdTimestamp`] = new Date(now).toISOString();
  atomicUpdates[`/conversations/${conversationId}/lastActivity`] = now;

  const summaryMsg = `Confirmed Agreement: ${agreementRole}`;
  atomicUpdates[`/userConversations/${creatorUid}/${conversationId}`] = {
    conversationId: conversationId,
    conversationType: 'agreement',
    otherUserId: applicantId,
    otherUserName: applicantDisplayName,
    lastMessageText: summaryMsg,
    lastMessageTimestamp: new Date(now).toISOString(),
    hasUnread: false,
    agreement: agreementPayload,
    bandName: resolvedBandName,
    bandId: targetBandId || null,
  };
  atomicUpdates[`/userConversations/${applicantId}/${conversationId}`] = {
    conversationId: conversationId,
    conversationType: 'agreement',
    otherUserId: creatorUid,
    otherUserName: creatorName,
    lastMessageText: summaryMsg,
    lastMessageTimestamp: new Date(now).toISOString(),
    hasUnread: true,
    agreement: agreementPayload,
    bandName: resolvedBandName,
    bandId: targetBandId || null,
  };



  await admin.database().ref().update(atomicUpdates);

  return { conversationId, agreement: agreementPayload };
});

/**
 * 3. sendDirectMessage
 */
exports.sendDirectMessage = onCall({ region: 'europe-west1' }, async (request) => {
  const senderUid = request.auth?.uid;
  if (!senderUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const conversationId = request.data?.conversationId;
  const text = request.data?.text;

  if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'conversationId is required.');
  }
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Message text cannot be empty.');
  }
  if (text.length > 4000) {
    throw new HttpsError('invalid-argument', 'Message exceeds maximum length of 4000 characters.');
  }

  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');
  if (!convSnap.exists()) {
    throw new HttpsError('not-found', 'Conversation does not exist.');
  }
  const convVal = convSnap.val() || {};

  const pMap = convVal.participants || convVal.Participants;
  const isParticipant = isParticipantMember(pMap, senderUid);
  let receiverUid = null;

  if (Array.isArray(pMap)) {
    receiverUid = pMap.map(String).find(id => id !== senderUid);
  } else if (pMap && typeof pMap === 'object') {
    receiverUid = Object.keys(pMap).find(id => id !== senderUid && isParticipantMember(pMap, id));
  }

  if (!isParticipant) {
    throw new HttpsError('permission-denied', 'You are not a participant in this conversation.');
  }

  const isSessionChat = convVal.conversationType === 'session_chat';

  if (!isSessionChat && !receiverUid) {
    receiverUid = request.data?.receiverUserId;
  }
  if (!isSessionChat && !receiverUid) {
    throw new HttpsError('failed-precondition', 'Could not determine receiver for this message.');
  }

  const msgRef = admin.database().ref(`/conversations/${conversationId}/messages`).push();
  const msgId = msgRef.key;
  const timestampIso = new Date().toISOString();

  const messageData = {
    id: msgId,
    senderId: senderUid,
    SenderId: senderUid,
    receiverId: receiverUid || '',
    ReceiverId: receiverUid || '',
    text: text.trim(),
    Text: text.trim(),
    timestamp: timestampIso,
    Timestamp: timestampIso,
    isRead: false,
    IsRead: false,
  };

  await msgRef.set(messageData);

  const updates = {};
  if (isSessionChat) {
    const participantList = (pMap && typeof pMap === 'object')
      ? Object.keys(pMap).filter(id => isParticipantMember(pMap, id))
      : (Array.isArray(pMap) ? pMap.map(String) : [senderUid]);

    for (const pUid of participantList) {
      updates[`/userConversations/${pUid}/${conversationId}/lastMessageText`] = text.trim();
      updates[`/userConversations/${pUid}/${conversationId}/lastMessageTimestamp`] = timestampIso;
      updates[`/userConversations/${pUid}/${conversationId}/hasUnread`] = (pUid !== senderUid);
    }
  } else {
    updates[`/userConversations/${senderUid}/${conversationId}/lastMessageText`] = text.trim();
    updates[`/userConversations/${senderUid}/${conversationId}/lastMessageTimestamp`] = timestampIso;
    updates[`/userConversations/${senderUid}/${conversationId}/otherUserId`] = receiverUid;
    updates[`/userConversations/${senderUid}/${conversationId}/hasUnread`] = false;

    updates[`/userConversations/${receiverUid}/${conversationId}/lastMessageText`] = text.trim();
    updates[`/userConversations/${receiverUid}/${conversationId}/lastMessageTimestamp`] = timestampIso;
    updates[`/userConversations/${receiverUid}/${conversationId}/otherUserId`] = senderUid;
    updates[`/userConversations/${receiverUid}/${conversationId}/hasUnread`] = true;
  }

  await admin.database().ref().update(updates);

  try {
    if (isSessionChat) {
      const participants = Array.isArray(pMap) ? pMap : Object.keys(pMap || {});
      const otherParticipants = participants.filter(uid =>
        uid !== senderUid && isParticipantMember(pMap, uid));
      await Promise.all(otherParticipants.map(uid =>
        publishNotification(uid, 'session_message', [conversationId, msgId], { conversationId })));
    } else if (receiverUid) {
      await publishNotification(receiverUid, 'direct_message', [conversationId, msgId], { conversationId });
    }
  } catch (error) {
    console.warn('Message notification unavailable:', error?.code || 'unknown');
  }

  return { messageId: msgId };
});

function isParticipantMember(pMap, targetUid) {
  if (!pMap || !targetUid || typeof targetUid !== 'string') return false;

  if (Array.isArray(pMap)) {
    return pMap.some(item => item === targetUid);
  }

  if (typeof pMap === 'object' && pMap !== null) {
    if (!Object.prototype.hasOwnProperty.call(pMap, targetUid)) {
      return false;
    }
    const val = pMap[targetUid];
    if (val === false || val === 0 || val === 'false' || val === '' || val === null || val === undefined) {
      return false;
    }
    return true;
  }

  return false;
}

/**
 * 4. markDirectConversationRead
 */
exports.markDirectConversationRead = onCall({ region: 'europe-west1' }, async (request) => {
  const selfUid = request.auth?.uid;
  const conversationId = request.data?.conversationId;

  try {
    if (!selfUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'conversationId is required.');
    }

    const trimmedConvId = conversationId.trim();
    const convRef = admin.database().ref(`/conversations/${trimmedConvId}`);
    const convSnap = await convRef.once('value');
    if (!convSnap.exists()) {
      throw new HttpsError('not-found', 'Conversation does not exist.');
    }

    const convVal = convSnap.val() || {};
    const pMap = convVal.participants || convVal.Participants;
    const isParticipant = isParticipantMember(pMap, selfUid);

    if (!isParticipant) {
      throw new HttpsError('permission-denied', 'You are not a participant in this conversation.');
    }

    const updates = {};
    updates[`/userConversations/${selfUid}/${trimmedConvId}/hasUnread`] = false;

    const msgsSnap = await admin.database().ref(`/conversations/${trimmedConvId}/messages`).once('value');
    if (msgsSnap.exists() && msgsSnap.val()) {
      const msgs = msgsSnap.val();
      if (typeof msgs === 'object' && msgs !== null) {
        Object.keys(msgs).forEach((msgId) => {
          const msg = msgs[msgId];
          if (msg && typeof msg === 'object') {
            const sender = (msg.senderId || msg.SenderId || '').toString();
            const receiver = (msg.receiverId || msg.ReceiverId || '').toString();

            let isForSelf = false;
            if (receiver) {
              isForSelf = (receiver === selfUid);
            } else if (sender) {
              isForSelf = (sender !== selfUid);
            }

            if (isForSelf) {
              updates[`/conversations/${trimmedConvId}/messages/${msgId}/isRead`] = true;
              updates[`/conversations/${trimmedConvId}/messages/${msgId}/IsRead`] = true;
            }
          }
        });
      }
    }

    if (Object.keys(updates).length > 0) {
      await admin.database().ref().update(updates);
    }

    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) {
      throw err;
    }

    logger.error('markDirectConversationRead failed with unexpected error', {
      functionName: 'markDirectConversationRead',
      stage: 'execution',
      conversationId: conversationId || null,
      callerUid: selfUid || null,
      errorName: err.name || 'Error',
      errorMessage: err.message || String(err),
      errorCode: err.code || null,
      errorStack: err.stack || null,
    });

    throw new HttpsError('internal', `An internal error occurred: ${err.message || 'Unknown error'}`);
  }
});

/**
 * 5. triggerEventReminder
 */
exports.triggerEventReminder = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { bandId, eventId, reminderType } = request.data || {};
  if (!bandId || typeof bandId !== 'string' || bandId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'bandId is required.');
  }
  if (!eventId || typeof eventId !== 'string' || eventId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'eventId is required.');
  }

  const allowedTypes = ['24h', '48h', '72h', 'last'];
  if (!reminderType || !allowedTypes.includes(reminderType)) {
    throw new HttpsError('invalid-argument', `reminderType must be one of: ${allowedTypes.join(', ')}`);
  }

  const roleSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${callerUid}/Role`).once('value');
  const role = (roleSnap.val() || '').toString().toLowerCase();

  const eventSnap = await admin.database().ref(`/Bands/${bandId}/Events/${eventId}`).once('value');
  if (!eventSnap.exists()) {
    throw new HttpsError('not-found', `Event ${eventId} not found.`);
  }
  const eventData = eventSnap.val() || {};

  const isLeaderOrAdminOrMod = role.includes('leader') || role.includes('admin') || role.includes('mod');
  const isCreator = eventData.createdBy === callerUid;
  if (!isLeaderOrAdminOrMod && !isCreator) {
    throw new HttpsError('permission-denied', 'Only Leader, Admin, MOD, or event creator can trigger event reminders.');
  }

  // Check if reminder was already completed before resolving tokens
  const auditRef = admin.database().ref(`/eventReminderAudit/${bandId}/${eventId}/${reminderType}`);
  const auditSnap = await auditRef.once('value');
  const auditData = auditSnap.val();

  const legacyKeyMap = {
    '24h': 'sentReminder24h',
    '48h': 'sentReminder48h',
    '72h': 'sentReminder72h',
    'last': 'sentReminder84h',
  };
  const legacyKey = legacyKeyMap[reminderType];
  const isLegacyAlreadySent = legacyKey ? (eventData[legacyKey] === true) : false;

  if ((auditData && (auditData.status === 'completed' || auditData.status === 'already_sent')) || isLegacyAlreadySent) {
    return {
      status: 'already_sent',
      successCount: auditData?.successCount || 0,
      failureCount: auditData?.failureCount || 0,
      attemptedCount: auditData?.attemptedCount || 0,
      totalMembersCount: auditData?.totalMembersCount || 0,
      tokensFoundCount: auditData?.tokensFoundCount || 0,
      missingTokensCount: auditData?.missingTokensCount || 0,
    };
  }

  const membersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');
  const members = membersSnap.val() || {};
  const memberIdsSet = new Set(Object.keys(members));

  if (memberIdsSet.size === 0) {
    const altMembersSnap = await admin.database().ref(`/Bands/${bandId}/Members`).once('value');
    const altMembers = altMembersSnap.val() || {};
    Object.keys(altMembers).forEach(uid => memberIdsSet.add(uid));
  }

  if (callerUid) memberIdsSet.add(callerUid);
  if (eventData.createdBy) memberIdsSet.add(eventData.createdBy);

  if (eventData.responses && typeof eventData.responses === 'object') {
    Object.keys(eventData.responses).forEach(uid => memberIdsSet.add(uid));
  }
  if (eventData.externalInvitees && typeof eventData.externalInvitees === 'object') {
    Object.keys(eventData.externalInvitees).forEach(uid => memberIdsSet.add(uid));
  }
  if (eventData.members && typeof eventData.members === 'object') {
    Object.keys(eventData.members).forEach(uid => memberIdsSet.add(uid));
  }
  if (eventData.invitedMembers && typeof eventData.invitedMembers === 'object') {
    Object.keys(eventData.invitedMembers).forEach(uid => memberIdsSet.add(uid));
  }
  if (eventData.attendees && typeof eventData.attendees === 'object') {
    Object.keys(eventData.attendees).forEach(uid => memberIdsSet.add(uid));
  }

  const memberIds = Array.from(memberIdsSet).filter(uid => uid && typeof uid === 'string' && uid.trim().length > 0);

  if (memberIds.length === 0) {
    return {
      status: 'no_recipients',
      successCount: 0,
      attemptedCount: 0,
      failureCount: 0,
      totalMembersCount: 0,
      tokensFoundCount: 0,
      missingTokensCount: 0,
    };
  }

  const recipientsWithTokens = await registeredRecipients(memberIds);

  if (recipientsWithTokens.length === 0) {
    await auditRef.update({
      status: 'no_valid_tokens',
      completedAt: new Date().toISOString(),
      failureReason: 'no_valid_tokens',
      triggeredBy: callerUid,
      totalMembersCount: memberIds.length,
      tokensFoundCount: 0,
    });
    return {
      status: 'no_valid_tokens',
      successCount: 0,
      attemptedCount: 0,
      failureCount: 0,
      totalMembersCount: memberIds.length,
      tokensFoundCount: 0,
      missingTokensCount: memberIds.length,
    };
  }

  const messages = recipientsWithTokens.map(() => ({
    data: { bandId, eventId, type: 'event_reminder' },
  }));

  const fcmResponse = await dispatchRegisteredBatch(recipientsWithTokens, messages);
  const missingTokensCount = memberIds.length - new Set(recipientsWithTokens.map(row => row.userId)).size;

  let batchSuccess = 0;
  let batchFailure = 0;
  const recipientUpdates = {};

  fcmResponse.responses.forEach((res, index) => {
    const recipient = recipientsWithTokens[index];
    if (!recipient) return;

    if (res.success) {
      batchSuccess++;
      recipientUpdates[`recipients/${recipient.userId}`] = { status: 'sent', sentAt: new Date().toISOString() };
    } else {
      batchFailure++;
      const path = `recipients/${recipient.userId}`;
      if (recipientUpdates[path]?.status !== 'sent') {
        recipientUpdates[path] = { status: 'failed', error: res.error?.code || 'undelivered' };
      }
    }
  });

  const finalStatus = batchSuccess > 0 ? 'completed' : (batchFailure > 0 ? 'failed' : 'completed');

  const auditUpdates = {
    ...recipientUpdates,
    status: finalStatus,
    attemptedCount: recipientsWithTokens.length,
    successCount: batchSuccess,
    failureCount: batchFailure,
    totalMembersCount: memberIds.length,
    tokensFoundCount: recipientsWithTokens.length,
    missingTokensCount,
    completedAt: new Date().toISOString(),
    triggeredBy: callerUid,
  };

  await auditRef.update(auditUpdates);

  if (legacyKey) {
    await admin.database().ref(`/Bands/${bandId}/Events/${eventId}/${legacyKey}`).set(true);
  }

  return {
    status: finalStatus,
    successCount: batchSuccess,
    failureCount: batchFailure,
    attemptedCount: recipientsWithTokens.length,
    totalMembersCount: memberIds.length,
    tokensFoundCount: recipientsWithTokens.length,
    missingTokensCount,
  };
});

/**
 * 6. createBandSectionConversation
 */
exports.createBandSectionConversation = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { bandId, groupName, participantIds, sectionKey, sourceInstrument } = request.data || {};

  if (!bandId || typeof bandId !== 'string' || bandId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'bandId is required.');
  }
  if (!groupName || typeof groupName !== 'string' || groupName.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'groupName cannot be empty.');
  }
  const trimmedGroupName = groupName.trim();
  if (trimmedGroupName.length > 80) {
    throw new HttpsError('invalid-argument', 'groupName cannot exceed 80 characters.');
  }

  // Authoritative band membership check
  const membersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');
  if (!membersSnap.exists() || !membersSnap.val()) {
    throw new HttpsError('not-found', `Band ${bandId} does not exist or has no members.`);
  }
  const bandMembers = membersSnap.val();

  // Verify caller is a current band member (any valid role including Member)
  if (!bandMembers[callerUid]) {
    throw new HttpsError('permission-denied', 'You are not a member of this band.');
  }

  // Get authoritative band name snapshot
  let bandName = bandId;
  const bandNameSnap = await admin.database().ref(`/Bands/${bandId}/Name`).once('value');
  if (bandNameSnap.exists() && bandNameSnap.val()) {
    bandName = bandNameSnap.val().toString();
  }

  // Validate and deduplicate participants
  const rawParticipants = Array.isArray(participantIds) ? participantIds : [];
  const validParticipantSet = new Set();
  validParticipantSet.add(callerUid);

  for (const pid of rawParticipants) {
    if (pid && typeof pid === 'string' && pid.trim().length > 0) {
      const cleanPid = pid.trim();
      if (bandMembers[cleanPid]) {
        validParticipantSet.add(cleanPid);
      }
    }
  }

  if (validParticipantSet.size < 2) {
    throw new HttpsError('invalid-argument', 'A section group chat requires at least 2 current band members.');
  }

  const participantsMap = {};
  const participantsList = Array.from(validParticipantSet);
  participantsList.forEach((uid) => {
    participantsMap[uid] = true;
  });

  const conversationId = admin.database().ref('/conversations').push().key;
  const timestampIso = new Date().toISOString();

  const conversationData = {
    conversationType: 'band_section',
    bandId: bandId,
    bandName: bandName,
    groupName: trimmedGroupName,
    sectionKey: (sectionKey && typeof sectionKey === 'string') ? sectionKey.trim().toLowerCase() : null,
    sourceInstrument: (sourceInstrument && typeof sourceInstrument === 'string') ? sourceInstrument.trim() : null,
    createdBy: callerUid,
    createdTimestamp: timestampIso,
    updatedTimestamp: timestampIso,
    participants: participantsMap,
    admins: { [callerUid]: true },
    participantCount: participantsList.length,
  };

  const updates = {};
  updates[`/conversations/${conversationId}`] = conversationData;
  updates[`/bandSectionConversations/${bandId}/${conversationId}`] = true;

  // Multi-location atomic index updates for each participant
  participantsList.forEach((uid) => {
    updates[`/userConversations/${uid}/${conversationId}`] = {
      conversationType: 'band_section',
      bandId: bandId,
      bandName: bandName,
      groupName: trimmedGroupName,
      sectionKey: conversationData.sectionKey,
      sourceInstrument: conversationData.sourceInstrument,
      lastMessageText: '',
      lastMessageTimestamp: timestampIso,
      lastMessageSenderId: null,
      lastMessageSenderName: null,
      hasUnread: false,
      participantCount: participantsList.length,
    };
  });

  await admin.database().ref().update(updates);

  return { conversationId };
});

/**
 * 7. sendBandSectionMessage
 */
exports.sendBandSectionMessage = onCall({ region: 'europe-west1' }, async (request) => {
  const senderUid = request.auth?.uid;
  if (!senderUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { conversationId, text, replyToText, replyToSenderName } = request.data || {};

  if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'conversationId is required.');
  }
  if (!text || typeof text !== 'string' || text.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Message text cannot be empty.');
  }
  if (text.length > 4000) {
    throw new HttpsError('invalid-argument', 'Message exceeds maximum length of 4000 characters.');
  }

  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');
  if (!convSnap.exists()) {
    throw new HttpsError('not-found', 'Conversation does not exist.');
  }
  const convVal = convSnap.val() || {};

  if (convVal.conversationType !== 'band_section') {
    throw new HttpsError('invalid-argument', 'Conversation is not a band section group.');
  }

  const pMap = convVal.participants || {};
  if (!pMap[senderUid]) {
    throw new HttpsError('permission-denied', 'You are not a participant in this conversation.');
  }

  // Authoritative band membership check
  const bandId = convVal.bandId;
  const memberSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${senderUid}`).once('value');
  if (!memberSnap.exists()) {
    throw new HttpsError('permission-denied', 'You are no longer a member of this band.');
  }

  // Resolve sender name snapshot
  let senderName = 'Musician';
  const userProfileSnap = await admin.database().ref(`/users/${senderUid}/info`).once('value');
  if (userProfileSnap.exists()) {
    const info = userProfileSnap.val();
    senderName = info.DisplayName || info.displayName || info.Nickname || info.nickname || 'Musician';
  }

  const msgRef = admin.database().ref(`/conversations/${conversationId}/messages`).push();
  const msgId = msgRef.key;
  const timestampIso = new Date().toISOString();

  const messageData = {
    id: msgId,
    senderId: senderUid,
    SenderId: senderUid,
    senderName: senderName,
    SenderName: senderName,
    text: text.trim(),
    Text: text.trim(),
    timestamp: timestampIso,
    Timestamp: timestampIso,
    isRead: false,
    IsRead: false,
  };
  if (replyToText) messageData.replyToText = String(replyToText);
  if (replyToSenderName) messageData.replyToSenderName = String(replyToSenderName);

  await msgRef.set(messageData);

  const updates = {};
  updates[`/conversations/${conversationId}/updatedTimestamp`] = timestampIso;

  const participantsList = Object.keys(pMap).filter(uid => pMap[uid] === true);

  participantsList.forEach((uid) => {
    updates[`/userConversations/${uid}/${conversationId}/lastMessageText`] = text.trim();
    updates[`/userConversations/${uid}/${conversationId}/lastMessageTimestamp`] = timestampIso;
    updates[`/userConversations/${uid}/${conversationId}/lastMessageSenderId`] = senderUid;
    updates[`/userConversations/${uid}/${conversationId}/lastMessageSenderName`] = senderName;
    if (uid === senderUid) {
      updates[`/userConversations/${uid}/${conversationId}/hasUnread`] = false;
    } else {
      updates[`/userConversations/${uid}/${conversationId}/hasUnread`] = true;
    }
  });

  await admin.database().ref().update(updates);

  try {
    await Promise.all(participantsList.filter(uid => uid !== senderUid).map(async uid => {
      const member = (await admin.database().ref('Bands/' + bandId + '/Members_band/' + uid).get()).val();
      if (notificationMember(member)) {
        await publishNotification(uid, 'band_section_chat', [conversationId, msgId], { bandId, conversationId });
      }
    }));
  } catch (error) {
    console.warn('Section message notification unavailable:', error?.code || 'unknown');
  }

  return { messageId: msgId };
});

/**
 * 8. markBandSectionConversationRead
 */
exports.markBandSectionConversationRead = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const conversationId = request.data?.conversationId;
  if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'conversationId is required.');
  }

  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');
  if (!convSnap.exists()) {
    throw new HttpsError('not-found', 'Conversation does not exist.');
  }
  const convVal = convSnap.val() || {};

  const pMap = convVal.participants || {};
  if (!pMap[callerUid]) {
    throw new HttpsError('permission-denied', 'You are not a participant in this conversation.');
  }

  // Verify band membership
  const bandId = convVal.bandId;
  if (bandId) {
    const memberSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${callerUid}`).once('value');
    if (!memberSnap.exists()) {
      throw new HttpsError('permission-denied', 'You are no longer a member of this band.');
    }
  }

  // Update only caller's per-user read state under userConversations
  await admin.database().ref(`/userConversations/${callerUid}/${conversationId}/hasUnread`).set(false);

  return { success: true };
});

/**
 * 9. manageBandSectionConversation
 */
exports.manageBandSectionConversation = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { conversationId, action, groupName, participantIds } = request.data || {};
  if (!conversationId || typeof conversationId !== 'string' || conversationId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'conversationId is required.');
  }

  const allowedActions = ['rename', 'addParticipants', 'removeParticipants', 'leave'];
  if (!action || !allowedActions.includes(action)) {
    throw new HttpsError('invalid-argument', `action must be one of: ${allowedActions.join(', ')}`);
  }

  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');
  if (!convSnap.exists()) {
    throw new HttpsError('not-found', 'Conversation does not exist.');
  }
  const convVal = convSnap.val() || {};

  if (convVal.conversationType !== 'band_section') {
    throw new HttpsError('invalid-argument', 'Conversation is not a band section group.');
  }

  const bandId = convVal.bandId;
  const pMap = convVal.participants || {};
  const adminsMap = convVal.admins || {};

  // Check band membership and role
  const bandMembersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');
  const bandMembers = bandMembersSnap.val() || {};

  if (!bandMembers[callerUid]) {
    throw new HttpsError('permission-denied', 'You are not a member of this band.');
  }

  const callerBandRole = bandMembers[callerUid]?.Role || bandMembers[callerUid]?.role;
  const isBandAdminOrLeader = (callerBandRole === 'Leader' || callerBandRole === 'Admin' || callerBandRole === 'MOD');
  const isGroupAdmin = adminsMap[callerUid] === true || convVal.createdBy === callerUid;

  const updates = {};
  const timestampIso = new Date().toISOString();
  updates[`/conversations/${conversationId}/updatedTimestamp`] = timestampIso;

  if (action === 'rename') {
    if (!isGroupAdmin && !isBandAdminOrLeader) {
      throw new HttpsError('permission-denied', 'Only group admins or Band Leaders/Admins can rename the group.');
    }
    if (!groupName || typeof groupName !== 'string' || groupName.trim().length === 0) {
      throw new HttpsError('invalid-argument', 'groupName cannot be empty.');
    }
    const trimmed = groupName.trim();
    if (trimmed.length > 80) {
      throw new HttpsError('invalid-argument', 'groupName cannot exceed 80 characters.');
    }

    updates[`/conversations/${conversationId}/groupName`] = trimmed;
    Object.keys(pMap).forEach((uid) => {
      if (pMap[uid]) {
        updates[`/userConversations/${uid}/${conversationId}/groupName`] = trimmed;
      }
    });
  } else if (action === 'addParticipants') {
    if (!isGroupAdmin && !isBandAdminOrLeader) {
      throw new HttpsError('permission-denied', 'Only group admins or Band Leaders/Admins can add members.');
    }
    const toAdd = Array.isArray(participantIds) ? participantIds : [];
    if (toAdd.length === 0) {
      throw new HttpsError('invalid-argument', 'participantIds list is empty.');
    }

    const currentParticipants = Object.keys(pMap).filter(uid => pMap[uid]);
    const newParticipantSet = new Set(currentParticipants);

    toAdd.forEach((uid) => {
      if (uid && typeof uid === 'string' && bandMembers[uid]) {
        newParticipantSet.add(uid);
      }
    });

    const updatedList = Array.from(newParticipantSet);
    const newCount = updatedList.length;

    updatedList.forEach((uid) => {
      updates[`/conversations/${conversationId}/participants/${uid}`] = true;
      updates[`/userConversations/${uid}/${conversationId}/conversationType`] = 'band_section';
      updates[`/userConversations/${uid}/${conversationId}/bandId`] = bandId;
      updates[`/userConversations/${uid}/${conversationId}/bandName`] = convVal.bandName || bandId;
      updates[`/userConversations/${uid}/${conversationId}/groupName`] = convVal.groupName;
      updates[`/userConversations/${uid}/${conversationId}/participantCount`] = newCount;
    });

    updates[`/conversations/${conversationId}/participantCount`] = newCount;
  } else if (action === 'removeParticipants') {
    if (!isGroupAdmin && !isBandAdminOrLeader) {
      throw new HttpsError('permission-denied', 'Only group admins or Band Leaders/Admins can remove members.');
    }
    const toRemove = Array.isArray(participantIds) ? participantIds : [];
    if (toRemove.length === 0) {
      throw new HttpsError('invalid-argument', 'participantIds list is empty.');
    }

    const currentParticipants = Object.keys(pMap).filter(uid => pMap[uid]);
    const updatedParticipants = currentParticipants.filter(uid => !toRemove.includes(uid));

    if (updatedParticipants.length < 2) {
      throw new HttpsError('failed-precondition', 'Cannot reduce group to fewer than 2 participants.');
    }

    toRemove.forEach((uid) => {
      updates[`/conversations/${conversationId}/participants/${uid}`] = null;
      updates[`/conversations/${conversationId}/admins/${uid}`] = null;
      updates[`/userConversations/${uid}/${conversationId}`] = null;
    });

    // Ensure at least one admin remains
    const remainingAdmins = Object.keys(adminsMap).filter(uid => !toRemove.includes(uid) && adminsMap[uid]);
    if (remainingAdmins.length === 0 && updatedParticipants.length > 0) {
      updates[`/conversations/${conversationId}/admins/${updatedParticipants[0]}`] = true;
    }

    const newCount = updatedParticipants.length;
    updates[`/conversations/${conversationId}/participantCount`] = newCount;
    updatedParticipants.forEach((uid) => {
      updates[`/userConversations/${uid}/${conversationId}/participantCount`] = newCount;
    });
  } else if (action === 'leave') {
    if (!pMap[callerUid]) {
      throw new HttpsError('failed-precondition', 'You are not a participant in this conversation.');
    }

    const currentParticipants = Object.keys(pMap).filter(uid => pMap[uid]);
    const updatedParticipants = currentParticipants.filter(uid => uid !== callerUid);

    updates[`/conversations/${conversationId}/participants/${callerUid}`] = null;
    updates[`/conversations/${conversationId}/admins/${callerUid}`] = null;
    updates[`/userConversations/${callerUid}/${conversationId}`] = null;

    if (updatedParticipants.length > 0) {
      // If leaving user was the only admin, appoint first remaining participant
      const remainingAdmins = Object.keys(adminsMap).filter(uid => uid !== callerUid && adminsMap[uid]);
      if (remainingAdmins.length === 0) {
        updates[`/conversations/${conversationId}/admins/${updatedParticipants[0]}`] = true;
      }

      const newCount = updatedParticipants.length;
      updates[`/conversations/${conversationId}/participantCount`] = newCount;
      updatedParticipants.forEach((uid) => {
        updates[`/userConversations/${uid}/${conversationId}/participantCount`] = newCount;
      });
    }
  }

  await admin.database().ref().update(updates);
  return { success: true };
});

/**
 * Core handler for band membership changes (both /Bands/{bandId}/Members_band/{memberId}
 * and legacy /Members_band/{bandId}/{memberId}).
 * Idempotently reconciles private event projections and conversation membership.
 */
async function handleBandMemberChange(event) {
  const bandId = event.params.bandId;
  const memberId = event.params.memberId;
  const db = admin.database();
  const updates = {};

  try {
    const afterExists = event.data.after.exists();
    const memberData = afterExists ? event.data.after.val() : null;

    if (!afterExists || !require('./band_membership_index').validMember(memberData)) {
      // 1. Removed or inactive membership cannot retain private conversation indices.
      // Strictly scoped removal: use mapEventProjectionIndex to remove ONLY projections for this band's events
      try {
        const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');
        const bandVal = bandSnap.exists() ? bandSnap.val() : {};
        const eventsSnap = await db.ref(`/Bands/${bandId}/Events`).once('value');
        if (eventsSnap.exists() && eventsSnap.val()) {
          const eventsObj = eventsSnap.val();
          for (const [eventId, eventData] of Object.entries(eventsObj)) {
            if (!eventData || typeof eventData !== 'object') continue;

            // Check if user is still authorized via another role (creator, invitee, confirmed substitute)
            const stillAuthorized = getAuthorizedUserIdsForBandEvent(bandVal, eventData).includes(memberId);
            if (!stillAuthorized) {
              const indexSnap = await db.ref(`/mapEventProjectionIndex/band:${bandId}:${eventId}`).once('value');
              const indexVal = indexSnap.exists() ? indexSnap.val() : null;
              const mapItemIds = indexVal && indexVal.mapItemIds ? Object.keys(indexVal.mapItemIds) : [];
              mapItemIds.forEach((mapItemId) => {
                updates[`/userMapEventFeed/${memberId}/${mapItemId}`] = null;
              });
              updates[`/mapEventProjectionIndex/band:${bandId}:${eventId}/authorizedUids/${memberId}`] = null;
            }
          }
        }
      } catch (_) {}

      // Section conversations cleanup
      try {
        const bandSectionSnap = await db.ref(`/bandSectionConversations/${bandId}`).once('value');
        if (bandSectionSnap.exists() && bandSectionSnap.val()) {
          const convIds = Object.keys(bandSectionSnap.val());
          for (const convId of convIds) {
            const convSnap = await db.ref(`/conversations/${convId}`).once('value');
            if (convSnap.exists()) {
              const convVal = convSnap.val();
              if (convVal && convVal.participants && convVal.participants[memberId]) {
                updates[`/conversations/${convId}/participants/${memberId}`] = null;
                updates[`/conversations/${convId}/admins/${memberId}`] = null;
                updates[`/userConversations/${memberId}/${convId}`] = null;

                const remainingParticipants = Object.keys(convVal.participants).filter(uid => uid !== memberId && convVal.participants[uid]);
                const newCount = remainingParticipants.length;
                updates[`/conversations/${convId}/participantCount`] = newCount;

                remainingParticipants.forEach((uid) => {
                  updates[`/userConversations/${uid}/${convId}/participantCount`] = newCount;
                });

                const remainingAdmins = Object.keys(convVal.admins || {}).filter(uid => uid !== memberId && convVal.admins[uid]);
                if (remainingAdmins.length === 0 && remainingParticipants.length > 0) {
                  updates[`/conversations/${convId}/admins/${remainingParticipants[0]}`] = true;
                }
              }
            }
          }
        }
      } catch (_) {}
    } else {
      // 2. Member was added or role/status changed
      const memberStatus = memberData && typeof memberData === 'object'
        ? String(memberData.Status || memberData.status || 'active').toLowerCase()
        : 'active';
      const isActive = memberStatus !== 'inactive' && memberStatus !== 'suspended';

      let bandName = 'Band';
      let bandVal = { Members_band: {} };
      try {
        const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');
        if (bandSnap.exists() && bandSnap.val()) {
          bandVal = bandSnap.val();
          bandName = String(bandVal.Name || bandVal.name || 'Band').trim();
        }
      } catch (_) {}

      try {
        const eventsSnap = await db.ref(`/Bands/${bandId}/Events`).once('value');
        if (eventsSnap.exists() && eventsSnap.val()) {
          const eventsObj = eventsSnap.val();
          for (const [eventId, eventData] of Object.entries(eventsObj)) {
            if (!eventData || typeof eventData !== 'object') continue;

            const authorizedUids = getAuthorizedUserIdsForBandEvent(bandVal, eventData);
            const isAuth = isActive && authorizedUids.includes(memberId);
            const projections = buildEventProjections('private_band', eventData, eventId, bandId, bandName);

            if (isAuth && projections.length > 0) {
              projections.forEach((p) => {
                updates[`/userMapEventFeed/${memberId}/${p.mapItemId}`] = p;
              });
              updates[`/mapEventProjectionIndex/band:${bandId}:${eventId}/authorizedUids/${memberId}`] = true;
            } else {
              // Not authorized: ensure no stale projections remain
              const indexSnap = await db.ref(`/mapEventProjectionIndex/band:${bandId}:${eventId}`).once('value');
              const indexVal = indexSnap.exists() ? indexSnap.val() : null;
              const mapItemIds = indexVal && indexVal.mapItemIds ? Object.keys(indexVal.mapItemIds) : projections.map((p) => p.mapItemId);
              mapItemIds.forEach((mId) => {
                updates[`/userMapEventFeed/${memberId}/${mId}`] = null;
              });
              updates[`/mapEventProjectionIndex/band:${bandId}:${eventId}/authorizedUids/${memberId}`] = null;
            }
          }
        }
      } catch (_) {}
    }

    if (Object.keys(updates).length > 0) {
      await db.ref().update(updates);
    }
    return null;
  } catch (error) {
    console.error('Error in handleBandMemberChange trigger:', error);
    return null;
  }
}

/**
 * 10. onBandMemberWritten
 * Primary cleanup/reconciliation trigger when a member is added, updated, or removed
 * at canonical path /Bands/{bandId}/Members_band/{memberId}
 */
exports.onBandMemberWritten = onValueWritten({
  ref: '/Bands/{bandId}/Members_band/{memberId}',
  region: databaseTriggerRegion,
  retry: true,
}, async (event) => {
  // Re-read canonical state: delayed/retried events must not resurrect old membership.
  try {
    await require('./band_membership_index').reconcileMembershipIndex(
      admin.database(), event.params.bandId, event.params.memberId);
    await eventReadModels.reconcileBand(admin.database(),event.params.bandId,event.params.memberId);
  } finally {
    // Preserve audience reconciliation even if index maintenance needs a retry.
    await handleBandMemberChange(event);
  }
  return null;
});

/**
 * 10. createSessionConversation
 * Creates or retrieves a canonical conversation for a Session.
 * Only the authenticated creator of the Session may create its chat room.
 */
exports.createSessionConversation = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { sessionId, sessionTitle } = request.data || {};
  if (!sessionId || typeof sessionId !== 'string' || sessionId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'sessionId is required.');
  }

  const sessionSnap = await admin.database().ref(`/Collabs/Sessions/${sessionId}`).once('value');
  if (!sessionSnap.exists()) {
    throw new HttpsError('not-found', `Session ${sessionId} not found.`);
  }

  const sessionData = sessionSnap.val() || {};
  const creatorId = sessionData.CreatorId || sessionData.creatorId;

  if (creatorId !== callerUid) {
    throw new HttpsError('permission-denied', 'Only the session creator can initialize the session chat.');
  }

  const existingChatId = sessionData.SessionChatId || sessionData.sessionChatId;
  if (existingChatId) {
    // Idempotent: return existing conversation
    const convSnap = await admin.database().ref(`/conversations/${existingChatId}`).once('value');
    if (convSnap.exists()) {
      return { conversationId: existingChatId };
    }
  }

  const conversationId = admin.database().ref('/conversations').push().key;
  const nowIso = new Date().toISOString();
  const title = (sessionTitle && typeof sessionTitle === 'string' && sessionTitle.trim().length > 0)
    ? sessionTitle.trim()
    : (sessionData.Title || sessionData.title || 'Session Chat');

  const updates = {};
  updates[`/conversations/${conversationId}`] = {
    conversationType: 'session_chat',
    sessionId: sessionId,
    sessionTitle: title,
    createdBy: callerUid,
    participants: { [callerUid]: true },
    Participants: [callerUid],
    createdTimestamp: nowIso,
  };
  updates[`/userConversations/${callerUid}/${conversationId}`] = {
    conversationType: 'session_chat',
    sessionId: sessionId,
    otherUserId: '',
    otherUserName: title,
    lastMessageText: '',
    lastMessageTimestamp: nowIso,
    hasUnread: false,
  };
  updates[`/Collabs/Sessions/${sessionId}/SessionChatId`] = conversationId;

  await admin.database().ref().update(updates);
  return { conversationId };
});

/**
 * 11. updateSessionApplicationStatus
 * Allows session creator to accept or decline applications.
 * Automatically and securely adds accepted applicants to session chat.
 */
exports.updateSessionApplicationStatus = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { sessionId, applicantId, status } = request.data || {};
  if (!sessionId || typeof sessionId !== 'string' || sessionId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'sessionId is required.');
  }
  if (!applicantId || typeof applicantId !== 'string' || applicantId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'applicantId is required.');
  }
  if (status !== 'accepted' && status !== 'declined') {
    throw new HttpsError('invalid-argument', 'status must be either accepted or declined.');
  }
  if (callerUid === applicantId) {
    throw new HttpsError('permission-denied', 'An applicant cannot accept or decline their own application.');
  }

  const sessionSnap = await admin.database().ref(`/Collabs/Sessions/${sessionId}`).once('value');
  if (!sessionSnap.exists()) {
    throw new HttpsError('not-found', `Session ${sessionId} not found.`);
  }

  const sessionData = sessionSnap.val() || {};
  const creatorId = sessionData.CreatorId || sessionData.creatorId;

  if (creatorId !== callerUid) {
    throw new HttpsError('permission-denied', 'Only the session creator can update application status.');
  }

  const appSnap = await admin.database().ref(`/Collabs/Applications/${sessionId}/${applicantId}`).once('value');
  if (!appSnap.exists()) {
    throw new HttpsError('not-found', `Application for applicant ${applicantId} not found.`);
  }

  const updates = {};
  updates[`/Collabs/Applications/${sessionId}/${applicantId}/Status`] = status;

  if (status === 'accepted') {
    const chatId = sessionData.SessionChatId || sessionData.sessionChatId;
    if (chatId) {
      updates[`/conversations/${chatId}/participants/${applicantId}`] = true;
      updates[`/userConversations/${applicantId}/${chatId}`] = {
        conversationType: 'session_chat',
        sessionId: sessionId,
        otherUserId: '',
        otherUserName: sessionData.Title || sessionData.title || 'Session Chat',
        lastMessageText: 'You joined the session chat',
        lastMessageTimestamp: new Date().toISOString(),
        hasUnread: true,
      };
    }
  }

  await admin.database().ref().update(updates);
  return { success: true, status };
});

/**
 * Admin testing callable function to trigger any of the 4 push sounds to a device.
 */
exports.sendTestPushNotification = onCall({ region: 'europe-west1' }, async (request) => {
  const callerId = request.auth?.uid;
  notificationUid(request);
  const { soundType, customToken, broadcastToAll } = request.data || {};

  const config = notificationDelivery.testSoundPlatform(soundType);
  if (!config) throw new HttpsError('invalid-argument', 'Invalid soundType.');

  const message = { data: { type: 'sound_test', soundType } };
  // If broadcastToAll is requested, deliver to all registered push tokens in RTDB
  if (broadcastToAll === true) {
    if (request.auth.token?.admin !== true) throw new HttpsError('permission-denied', 'Administrator access is required.');
    const recipientTokens = await registeredRecipients();

    if (recipientTokens.length === 0) {
      return {
        success: false,
        error: 'No registered push tokens found in database across all users.',
      };
    }

    const messages = recipientTokens.map(() => message);

    try {
      const response = await dispatchRegisteredBatch(recipientTokens, messages);
      console.log(`Broadcasted test push ${soundType}: ${response.successCount} succeeded, ${response.failureCount} failed.`);
      return {
        success: true,
        broadcast: true,
        total: messages.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
        soundType,
        // A mixed broadcast can use different channels per installation.
        ...(recipientTokens.every(row => row.soundProfile !== 'android-v2')
          ? { channelId: config.channelId } : {}),
      };
    } catch (err) {
      console.error('Error broadcasting test push notification via FCM:', err);
      return {
        success: false,
        error: `Broadcast Error: ${err.message || err.code || err}`,
      };
    }
  }

  // Single device push
  const destinations = await registeredRecipients([callerId]);
  const recipient = customToken ? destinations.find(row => row.token === customToken) : destinations[0];
  if (!recipient) {
    return { success: false, error: 'No registered device for this account.' };
  }

  try {
    const delivery = await dispatchRegistered(recipient, message);
    return {
      success: delivery.success,
      broadcast: false,
      messageId: delivery.messageId || null,
      soundType,
      channelId: notificationDelivery.testSoundPlatform(soundType, recipient.soundProfile).channelId,
    };
  } catch (err) {
    console.error('Error sending test push notification via FCM:', err);
    return {
      success: false,
      error: `FCM Error: ${err.message || err.code || err}`,
    };
  }
});

/**
 * Triggered when a new band room message is created under /bandconversations/{bandId}/messages/{messageId}.
 * Records user notifications for all band members except the sender.
 */
exports.onBandRoomMessageCreated = functions.region(databaseTriggerRegion).database
  .ref('/bandconversations/{bandId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const msgData = snapshot.val();
    if (!msgData) return null;

    const bandId = context.params.bandId;
    const messageId = context.params.messageId;
    const senderId = msgData.senderId || msgData.SenderId;

    try {
      const db = admin.database();
      const bandMembers = await db.ref('Bands/' + bandId + '/Members_band').get();
      const recipients = Object.entries(bandMembers.val() || {})
        .filter(([uid, member]) => uid !== senderId && notificationMember(member))
        .map(([uid]) => uid);
      await Promise.all(recipients.map(uid => publishNotification(uid, 'band_room_message',
        [bandId, messageId], { bandId, messageId })));

      return null;
    } catch (err) {
      console.error('Error in onBandRoomMessageCreated trigger:', err);
      return null;
    }
  });

exports.markNotificationRead = onCall({ region: 'europe-west1' }, async request => {
  const uid = notificationUid(request);
  const id = request.data?.notificationId;
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id)) {
    throw new HttpsError('invalid-argument', 'Invalid notification ID.');
  }
  return notificationAccess.markRead(admin.database(), uid, () => true, id);
});

exports.markAllNotificationsRead = onCall({ region: 'europe-west1' }, request =>
  notificationAccess.markRead(admin.database(), notificationUid(request), () => true));

exports.markFeatureNotificationsRead = onCall({ region: 'europe-west1' }, request => {
  const uid = notificationUid(request);
  const rawFeature = request.data?.featureId;
  const feature = typeof rawFeature === 'string' ? rawFeature.trim() : null;
  if (!KNOWN_FEATURE_IDS.includes(feature)) throw new HttpsError('invalid-argument', 'A valid featureId is required.');
  return notificationAccess.markRead(admin.database(), uid, row =>
    resolveNotificationFeatureId(row) === feature);
});

/**
 * Database trigger when a response is created under /SubRequests/{subRequestId}/Responses/{applicantId}.
 * Records a notification for the creator of the SubRequest if not already created.
 */
exports.onSubRequestResponseCreated = functions.region(databaseTriggerRegion).database
  .ref('/SubRequests/{subRequestId}/Responses/{applicantId}')
  .onCreate(async (snapshot, context) => {
    const subRequestId = context.params.subRequestId;
    const applicantId = context.params.applicantId;
    if (!subRequestId || !applicantId) return null;

    await notifyRequestResponse(subRequestId, applicantId).catch(error =>
      console.warn('Request response notification unavailable:', error?.code || 'unknown'));
    return null;
  });

/**
 * Database trigger when a file is uploaded under /files/{bandId}/{fileId}.
 * Records a notification for all band members except the uploader.
 */
exports.onBandFileUploaded = functions.region(databaseTriggerRegion).database
  .ref('/files/{bandId}/{fileId}')
  .onCreate(async (snapshot, context) => {
    const fileData = snapshot.val();
    if (!fileData) return null;

    const bandId = context.params.bandId;
    const fileId = context.params.fileId;
    const uploaderId = fileData.UploadedBy || fileData.uploadedBy || fileData.uploaderId || fileData.userId || fileData.UserId;

    try {
      const members = (await admin.database().ref('Bands/' + bandId + '/Members_band').get()).val() || {};

      // File names are private band data too. Legacy mirrors and stale roles
      // must never expand the current canonical audience.
      const recipients = Object.keys(members).filter(uid =>
        uid !== uploaderId && notificationMember(members[uid]));
      await Promise.all(recipients.map(uid => publishNotification(uid, 'band_file_uploaded',
        [bandId, fileId], { bandId, fileId })));

      return null;
    } catch (err) {
      console.error('Error in onBandFileUploaded trigger:', err);
      return null;
    }
  });

/**
 * Permanently deletes the caller's user account and all associated data.
 * If the user is the leader of a band:
 *   - If other members exist, leadership is automatically transferred to an Admin or next member.
 *   - If no other members exist, the orphaned band is deleted.
 */
exports.deleteUserAccount = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  if ((request.data?.userId != null && request.data.userId !== callerUid) || (request.data?.uid != null && request.data.uid !== callerUid)) {
    throw new HttpsError('permission-denied','You may delete only your own account.');
  }
  const db = admin.database();

  try {
    // Discovery references are candidates only. Every departure checks the canonical band.
    const indexed = (await db.ref(`userBandMembershipIndex/${callerUid}`).get()).val() || {};
    for (const bandId of Object.keys(indexed)) {
      if (!(await db.ref(`Bands/${bandId}/Members_band/${callerUid}`).get()).exists()) {
        await require('./band_membership_index').reconcileMembershipIndex(db,bandId,callerUid);
        continue;
      }
      await membershipAuthority.mutate(db,callerUid,{action:'departAccount',bandId,operationId:'delete_account'});
    }

    // 2. Clean up user's sub-requests
    const subRequestsSnap = await db.ref('/SubRequests').once('value');
    if (subRequestsSnap.exists() && subRequestsSnap.val()) {
      const allSubRequests = subRequestsSnap.val();
      const subUpdates = {};
      for (const subId of Object.keys(allSubRequests)) {
        const item = allSubRequests[subId];
        if (item && (item.CreatorUserId === callerUid || item.UserId === callerUid || item.creatorUserId === callerUid || item.userId === callerUid)) {
          // A surviving band's request belongs to that band, even when its creator leaves.
          let owningBand;
          try { owningBand = membershipAuthority.canonicalField(item,'BandId','bandId'); }
          catch (_) { continue; }
          if (!['freelance','standalone'].includes(owningBand)) {
            try { membershipAuthority.bandKey(owningBand); } catch (_) { continue; }
            if ((await db.ref(`Bands/${owningBand}`).get()).exists()) continue;
          }
          subUpdates[`/SubRequests/${subId}`] = null;
          subUpdates[`/subRequestAudience/${subId}`] = null;
        }
      }
      if (Object.keys(subUpdates).length > 0) {
        await db.ref().update(subUpdates);
      }
    }

    // 3. Clean up user's collab sessions & studios
    const collabsSnap = await db.ref('/Collabs/Sessions').once('value');
    if (collabsSnap.exists() && collabsSnap.val()) {
      const sessions = collabsSnap.val();
      const collabUpdates = {};
      Object.keys(sessions).forEach((sId) => {
        const s = sessions[sId];
        if (s && (s.CreatorId === callerUid || s.creatorId === callerUid)) {
          collabUpdates[`/Collabs/Sessions/${sId}`] = null;
          collabUpdates[`/Collabs/SessionResponses/${sId}`] = null;
          collabUpdates[`/Collabs/Applications/${sId}`] = null;
        }
      });
      if (Object.keys(collabUpdates).length > 0) {
        await db.ref().update(collabUpdates);
      }
    }

    const studiosSnap = await db.ref('/Collabs/Studios').once('value');
    if (studiosSnap.exists() && studiosSnap.val()) {
      const studios = studiosSnap.val();
      const studioUpdates = {};
      Object.keys(studios).forEach((sId) => {
        const s = studios[sId];
        if (s && (s.CreatorId === callerUid || s.creatorId === callerUid)) {
          studioUpdates[`/Collabs/Studios/${sId}`] = null;
        }
      });
      if (Object.keys(studioUpdates).length > 0) {
        await db.ref().update(studioUpdates);
      }
    }

    // Revoke V2 token ownership before deleting the private notification data.
    await notificationDelivery.revokeAccount(db, callerUid);

    // 4. Clean up user-specific nodes
    const rootUpdates = {};
    rootUpdates[`/users/${callerUid}`] = null;
    rootUpdates[`/userBandMembershipIndex/${callerUid}`] = null;
    for (const path of [notificationDelivery.feedPath, notificationDelivery.routesPath, notificationDelivery.signalPath]) {
      rootUpdates['/' + path + '/' + callerUid] = null;
    }
    rootUpdates[`/userSubRequestFeed/${callerUid}`] = null;
    rootUpdates[`/creatorSubRequestGroups/${callerUid}`] = null;
    rootUpdates[`/userConversations/${callerUid}`] = null;
    await db.ref().update(rootUpdates);

    // 5. Delete Firebase Authentication user record
    try {
      await admin.auth().deleteUser(callerUid);
    } catch (authErr) {
      if (authErr.code !== 'auth/user-not-found') throw authErr;
    }

    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error(`Error deleting user account for ${callerUid}:`, err);
    throw new HttpsError('internal', `Failed to delete user account: ${err.message}`);
  }
});

/**
 * Permanently deletes a band. Only callable by a Leader of the band.
 * Removes band references from all members' /users/{memberId}/Bands and deletes the band.
 */
exports.deleteBand = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const bandId = request.data?.bandId;
  if (!bandId || typeof bandId !== 'string' || bandId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'bandId is required.');
  }

  const trimmedBandId = bandId.trim();
  const db = admin.database();

  try {
    const bandRef = db.ref(`/Bands/${trimmedBandId}`);
    const bandSnap = await bandRef.once('value');

    if (!bandSnap.exists()) {
      return { success:true };
    }

    const bandData = bandSnap.val() || {};
    const members = bandData.Members_band || {};
    const callerMember = members[callerUid];

    if (!callerMember) {
      throw new HttpsError('permission-denied', 'You are not a member of this band.');
    }

    await membershipAuthority.requireManager(db,trimmedBandId,callerUid,true);

    const memberIds = Object.keys(members);
    const updates = {};

    // 1. Remove band from each member's user profile
    for (const memberId of memberIds) {

    }

    // Clean up private event projections for all members of deleted band
    for (const memberId of memberIds) {
      try {
        const userFeedSnap = await db.ref(`userMapEventFeed/${memberId}`).once('value');
        if (userFeedSnap.exists() && userFeedSnap.val()) {
          Object.keys(userFeedSnap.val()).forEach((mapItemId) => {
            if (mapItemId.startsWith(`event:private:${trimmedBandId}:`)) {
              updates[`/userMapEventFeed/${memberId}/${mapItemId}`] = null;
            }
          });
        }
      } catch (_) {}
    }

    // 2. Remove band conversations & section conversations
    updates[`/bandconversations/${trimmedBandId}`] = null;
    updates[`/bandSectionConversations/${trimmedBandId}`] = null;

    // Atomically revalidate ownership and delete canonical band; no client fallback.
    await membershipAuthority.mutate(db,callerUid,{action:'delete',bandId:trimmedBandId,operationId:'delete_band'});

    await db.ref().update(updates);

    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error(`Error deleting band ${trimmedBandId} by ${callerUid}:`, err);
    throw new HttpsError('internal', `Failed to delete band: ${err.message}`);
  }
});

/**
 * MAP-VIEW-FEED-03B: Strict allowlist projection sanitizer for server-owned publicMapPinFeed.
 * Strips all recipient data, tokens, staffing metadata, email/phone, etc.
 */
function sanitizeMapPinProjection(raw) {
  if (!raw || typeof raw !== 'object') return null;

  const pinId = raw.id || raw.pinId || raw.SubRequestId || raw.subRequestId;
  if (!pinId) return null;

  const creatorUserId = raw.creatorUserId || raw.CreatorUserId || raw.userId || raw.UserId || '';
  const status = raw.status || raw.Status || 'published';
  const eventType = raw.eventType || raw.EventType || raw.promotionType || 'gigPromo';
  const rawLat = raw.latitude !== undefined ? raw.latitude : raw.Latitude;
  const rawLng = raw.longitude !== undefined ? raw.longitude : raw.Longitude;

  if (typeof rawLat !== 'number' || typeof rawLng !== 'number' || !Number.isFinite(rawLat) || !Number.isFinite(rawLng)) {
    return null;
  }

  const projection = {
    id: pinId,
    pinId: pinId,
    subRequestId: pinId,
    mapItemId: `map_pin:${pinId}`,
    creatorUserId: creatorUserId,
    status: status,
    NotificationMode: 'map_pin',
    notificationMode: 'map_pin',
    subCategory: 'Music',
    eventType: eventType,
    latitude: rawLat,
    longitude: rawLng,
    Latitude: rawLat,
    Longitude: rawLng,
    createdAt: raw.createdAt || raw.CreatedAt || Date.now(),
    updatedAt: raw.updatedAt || raw.UpdatedAt || Date.now(),
  };

  if (raw.title || raw.Title) {
    projection.title = raw.title || raw.Title;
    projection.Title = projection.title;
  }
  if (raw.bandName || raw.BandName) {
    projection.bandName = raw.bandName || raw.BandName;
    projection.BandName = projection.bandName;
  }
  if (raw.bandId || raw.BandId) {
    projection.bandId = raw.bandId || raw.BandId;
    projection.BandId = projection.bandId;
  }
  if (raw.description || raw.Description) {
    projection.description = raw.description || raw.Description;
    projection.Description = projection.description;
  }
  if (raw.location || raw.Location) {
    projection.location = raw.location || raw.Location;
    projection.Location = projection.location;
  }
  if (raw.venue || raw.venue) {
    projection.venue = raw.venue || raw.Venue;
  }
  if (raw.city || raw.City) {
    projection.city = raw.city || raw.City;
  }
  if (raw.genre || raw.Genre || raw.style || raw.Style) {
    const g = raw.genre || raw.Genre || raw.style || raw.Style;
    projection.genre = g;
    projection.style = g;
    projection.Style = g;
  }
  if (raw.date || raw.Date) {
    projection.date = raw.date || raw.Date;
    projection.Date = projection.date;
  }
  if (raw.startTime || raw.StartTime) {
    projection.startTime = raw.startTime || raw.StartTime;
    projection.StartTime = projection.startTime;
  }
  if (raw.endTime || raw.EndTime) {
    projection.endTime = raw.endTime || raw.EndTime;
    projection.EndTime = projection.endTime;
  }
  if (raw.audioSnippetUrl) {
    projection.audioSnippetUrl = raw.audioSnippetUrl;
  }
  if (raw.audioSnippetTitle) {
    projection.audioSnippetTitle = raw.audioSnippetTitle;
  }
  if (raw.infoAudioTrack) {
    projection.infoAudioTrack = raw.infoAudioTrack;
  }
  if (raw.locationPrecision !== undefined) {
    projection.locationPrecision = raw.locationPrecision;
  }

  return projection;
}

/**
 * MAP-VIEW-FEEDBACK-03 & MAP-VIEW-FEED-03B: Server-owned Ordinary Map Pin Creation.
 * Narrowly scoped authenticated callable to persist ordinary Music Map View pins.
 * Writes atomically to SubRequests/{generatedId} and publicMapPinFeed/{generatedId}.
 * Never writes to BandEvents/PublishedSubRequests or staffing notification feeds.
 */
exports.createMapPin = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to create a map pin.');
  }

  const data = request.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Request data must be an object.');
  }

  // Helper for scalar string validation
  function validateOptionalString(val, name, maxLength) {
    if (val === undefined || val === null) return undefined;
    if (typeof val !== 'string') {
      throw new HttpsError('invalid-argument', `${name} must be a string.`);
    }
    const trimmed = val.trim();
    if (trimmed.length > maxLength) {
      throw new HttpsError('invalid-argument', `${name} exceeds maximum allowed length.`);
    }
    return trimmed;
  }

  // 1. Validate eventType (must be ordinary Music Map View type)
  const rawEventType = data.eventType || data.EventType || data.extraFields?.eventType || data.extraFields?.EventType;
  if (!rawEventType || typeof rawEventType !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid eventType is required.');
  }
  const eventType = rawEventType.trim();
  const ALLOWED_MAP_EVENT_TYPES = ['gigConcert', 'concert', 'rehearsal', 'jamSession', 'recordedMusic', 'gigPromo'];
  if (!ALLOWED_MAP_EVENT_TYPES.includes(eventType)) {
    throw new HttpsError('invalid-argument', `Invalid event type "${eventType}". Only ordinary music pins are allowed.`);
  }

  // 2. Reject staffing request types if supplied in requestType
  const rawRequestType = data.requestType || data.RequestType;
  if (rawRequestType !== undefined && rawRequestType !== null) {
    if (typeof rawRequestType !== 'string') {
      throw new HttpsError('invalid-argument', 'requestType must be a string.');
    }
    const lowerType = rawRequestType.trim().toLowerCase();
    if (lowerType.includes('sub') || lowerType.includes('member') || lowerType.includes('paid')) {
      throw new HttpsError('invalid-argument', 'Staffing request types are not allowed for map pins.');
    }
  }

  // 3. Validate coordinates (numeric, finite, valid ranges)
  const rawLat = data.latitude !== undefined ? data.latitude : data.Latitude;
  const rawLng = data.longitude !== undefined ? data.longitude : data.Longitude;

  if (typeof rawLat !== 'number' || typeof rawLng !== 'number' || !Number.isFinite(rawLat) || !Number.isFinite(rawLng)) {
    throw new HttpsError('invalid-argument', 'Latitude and longitude must be finite numbers.');
  }
  if (rawLat < -90 || rawLat > 90) {
    throw new HttpsError('invalid-argument', 'Latitude must be between -90 and 90.');
  }
  if (rawLng < -180 || rawLng > 180) {
    throw new HttpsError('invalid-argument', 'Longitude must be between -180 and 180.');
  }

  // 4. Validate scalar string fields with length limits
  const location = validateOptionalString(data.location !== undefined ? data.location : data.Location, 'location', 300);
  const description = validateOptionalString(data.description !== undefined ? data.description : data.Description, 'description', 2000);
  const title = validateOptionalString(data.title !== undefined ? data.title : data.Title, 'title', 120);
  const bandName = validateOptionalString(data.bandName !== undefined ? data.bandName : data.BandName, 'bandName', 200);
  const style = validateOptionalString(data.style !== undefined ? data.style : data.Style, 'style', 100);
  const genre = validateOptionalString(data.genre !== undefined ? data.genre : data.Genre, 'genre', 100);
  const venue = validateOptionalString(data.venue !== undefined ? data.venue : data.Venue, 'venue', 200);
  const date = validateOptionalString(data.date !== undefined ? data.date : data.Date, 'date', 100);
  const startTime = validateOptionalString(data.startTime !== undefined ? data.startTime : data.StartTime, 'startTime', 50);
  const endTime = validateOptionalString(data.endTime !== undefined ? data.endTime : data.EndTime, 'endTime', 50);
  const audioSnippetUrl = validateOptionalString(data.audioSnippetUrl !== undefined ? data.audioSnippetUrl : data.extraFields?.audioSnippetUrl, 'audioSnippetUrl', 2000);
  const audioSnippetTitle = validateOptionalString(data.audioSnippetTitle !== undefined ? data.audioSnippetTitle : data.extraFields?.audioSnippetTitle, 'audioSnippetTitle', 200);
  const infoAudioTrack = validateOptionalString(data.infoAudioTrack !== undefined ? data.infoAudioTrack : data.extraFields?.infoAudioTrack, 'infoAudioTrack', 1000);

  const rawSubCat = data.subCategory !== undefined ? data.subCategory : data.SubCategory;
  const subCategory = validateOptionalString(rawSubCat, 'subCategory', 100);
  if (subCategory && subCategory !== 'Music') {
    throw new HttpsError('invalid-argument', 'Only Music subCategory is allowed for ordinary map pins.');
  }

  // Explicit canonical Map ownership, validated by the shared authority module.
  const bandId = membershipAuthority.canonicalField(data, 'BandId', 'bandId');
  const db = admin.database();
  await membershipAuthority.authorizeMapPin(db, callerUid, {
    CreatorUserId: callerUid, ...(bandId != null ? {BandId: bandId} : {}),
  });

  // 6. Generate server-owned Firebase push ID
  const subRequestsRef = db.ref('SubRequests');
  const newPinRef = subRequestsRef.push();
  const generatedId = newPinRef.key;
  if (!generatedId) {
    throw new HttpsError('internal', 'Failed to generate record key.');
  }

  const now = Date.now();

  // 7. Assemble sanitized payload with server-controlled authority
  const persistedPayload = {
    SubRequestId: generatedId,
    id: generatedId,
    subRequestId: generatedId,
    SlotId: generatedId,
    CreatorUserId: callerUid,
    UserId: callerUid,
    Status: 'published',
    NotificationMode: 'map_pin',
    notificationMode: 'map_pin',
    subCategory: 'Music',
    eventType: eventType,
    Latitude: rawLat,
    Longitude: rawLng,
    latitude: rawLat,
    longitude: rawLng,
    CreatedAt: now,
    createdAt: now,
    RequestType: 'Other',
    IsPaid: false,
  };

  if (title) {
    persistedPayload.Title = title;
    persistedPayload.title = title;
  }
  if (location) persistedPayload.Location = location;
  if (description) persistedPayload.Description = description;
  if (bandName) {
    persistedPayload.BandName = bandName;
    persistedPayload.bandName = bandName;
  }
  if (bandId) {
    persistedPayload.BandId = bandId;
    persistedPayload.bandId = bandId;
  }
  if (style || genre) {
    persistedPayload.Style = style || genre;
    persistedPayload.style = style || genre;
  }
  if (genre) persistedPayload.genre = genre;
  if (venue) persistedPayload.venue = venue;
  if (date) {
    persistedPayload.Date = date;
    persistedPayload.date = date;
  }
  if (startTime) {
    persistedPayload.StartTime = startTime;
    persistedPayload.startTime = startTime;
  }
  if (endTime) {
    persistedPayload.EndTime = endTime;
    persistedPayload.endTime = endTime;
  }
  if (audioSnippetUrl) persistedPayload.audioSnippetUrl = audioSnippetUrl;
  if (audioSnippetTitle) persistedPayload.audioSnippetTitle = audioSnippetTitle;
  if (infoAudioTrack) persistedPayload.infoAudioTrack = infoAudioTrack;

  const media = await require('./storage_media').bindMap(db, callerUid, generatedId,
    persistedPayload.BandId, audioSnippetUrl, admin.app().options.projectId || process.env.GCLOUD_PROJECT);
  if (media) { persistedPayload.audioSnippetUrl = media.url; persistedPayload.MediaObjectId = media.id; }

  // 8. Write atomically to canonical SubRequests/{generatedId} and publicMapPinFeed/{generatedId}
  const sanitizedProjection = sanitizeMapPinProjection(persistedPayload);
  const writeBatch = {};
  if (media) writeBatch[media.path] = generatedId;
  writeBatch[`SubRequests/${generatedId}`] = persistedPayload;
  if (sanitizedProjection) {
    writeBatch[`publicMapPinFeed/${generatedId}`] = sanitizedProjection;
  }
  await db.ref().update(writeBatch);

  // Safe logging: never log personal address, audio URL or full payload
  console.log(`[createMapPin] Successfully created map pin ${generatedId} for caller ${callerUid} (type: ${eventType})`);

  return {
    success: true,
    id: generatedId,
    pin: persistedPayload,
  };
});

/**
 * Server-owned Cloud Function callable to securely update an existing Map Pin.
 * Enforces authentication, creator or band leader authorization, validates updated fields,
 * and updates SubRequests/{id} without writing to staffing indexes.
 */
exports.updateMapPin = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to update a map pin.');
  }

  const data = request.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Request data must be an object.');
  }

  const pinId = data.pinId || data.id || data.subRequestId;
  if (!pinId || typeof pinId !== 'string' || pinId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Valid pin id is required.');
  }

  function validateOptionalString(val, name, maxLength) {
    if (val === undefined || val === null) return undefined;
    if (typeof val !== 'string') {
      throw new HttpsError('invalid-argument', `${name} must be a string.`);
    }
    const trimmed = val.trim();
    if (trimmed.length > maxLength) {
      throw new HttpsError('invalid-argument', `${name} exceeds maximum allowed length.`);
    }
    return trimmed;
  }

  const db = admin.database();
  const pinRef = db.ref(`SubRequests/${pinId}`);
  const snap = await pinRef.get();
  if (!snap.exists()) {
    throw new HttpsError('not-found', 'Map pin not found.');
  }

  const existing = snap.val() || {};
  const notifMode = existing.NotificationMode || existing.notificationMode || (existing.extraFields && (existing.extraFields.NotificationMode || existing.extraFields.notificationMode));
  if (notifMode !== 'map_pin') {
    throw new HttpsError('failed-precondition', 'updateMapPin can only update ordinary map pins.');
  }
  await membershipAuthority.authorizeMapPin(db, callerUid, existing);

  const updates = {};
  if (data.title !== undefined || data.Title !== undefined) {
    const val = validateOptionalString(data.title !== undefined ? data.title : data.Title, 'title', 120);
    if (val !== undefined) {
      updates['Title'] = val;
      updates['title'] = val;
    }
  }
  if (data.bandName !== undefined) {
    const val = validateOptionalString(data.bandName, 'bandName', 200);
    if (val !== undefined) {
      updates['BandName'] = val;
      updates['bandName'] = val;
    }
  }
  if (data.description !== undefined) {
    const val = validateOptionalString(data.description, 'description', 2000);
    if (val !== undefined) {
      updates['Description'] = val;
      updates['description'] = val;
    }
  }
  if (data.location !== undefined) {
    const val = validateOptionalString(data.location, 'location', 300);
    if (val !== undefined) {
      updates['Location'] = val;
      updates['location'] = val;
    }
  }
  if (data.genre !== undefined || data.style !== undefined) {
    const val = validateOptionalString(data.genre || data.style, 'genre', 100);
    if (val !== undefined) {
      updates['Style'] = val;
      updates['style'] = val;
      updates['genre'] = val;
    }
  }
  if (data.venue !== undefined) {
    const val = validateOptionalString(data.venue, 'venue', 200);
    if (val !== undefined) {
      updates['venue'] = val;
    }
  }
  if (data.date !== undefined) {
    const val = validateOptionalString(data.date, 'date', 100);
    if (val !== undefined) {
      updates['Date'] = val;
      updates['date'] = val;
    }
  }
  if (data.startTime !== undefined) {
    const val = validateOptionalString(data.startTime, 'startTime', 50);
    if (val !== undefined) {
      updates['StartTime'] = val;
      updates['startTime'] = val;
    }
  }
  if (data.endTime !== undefined) {
    const val = validateOptionalString(data.endTime, 'endTime', 50);
    if (val !== undefined) {
      updates['EndTime'] = val;
      updates['endTime'] = val;
    }
  }
  if (data.audioSnippetUrl !== undefined) {
    const val = validateOptionalString(data.audioSnippetUrl, 'audioSnippetUrl', 2000);
    if (val !== undefined) updates['audioSnippetUrl'] = val;
  }
  if (data.audioSnippetTitle !== undefined) {
    const val = validateOptionalString(data.audioSnippetTitle, 'audioSnippetTitle', 200);
    if (val !== undefined) updates['audioSnippetTitle'] = val;
  }
  if (data.infoAudioTrack !== undefined) {
    const val = validateOptionalString(data.infoAudioTrack, 'infoAudioTrack', 1000);
    if (val !== undefined) updates['infoAudioTrack'] = val;
  }
  if (data.latitude !== undefined || data.longitude !== undefined) {
    if (typeof data.latitude !== 'number' || !Number.isFinite(data.latitude) ||
        typeof data.longitude !== 'number' || !Number.isFinite(data.longitude) ||
        data.latitude < -90 || data.latitude > 90 ||
        data.longitude < -180 || data.longitude > 180) {
      throw new HttpsError('invalid-argument', 'Valid coordinates are required (latitude -90..90, longitude -180..180).');
    }
    updates['Latitude'] = data.latitude;
    updates['latitude'] = data.latitude;
    updates['Longitude'] = data.longitude;
    updates['longitude'] = data.longitude;
  }

  updates['UpdatedAt'] = Date.now();
  updates['updatedAt'] = Date.now();

  const media = data.audioSnippetUrl === undefined ? null :
    await require('./storage_media').bindMap(db, callerUid, pinId, existing.BandId,
      data.audioSnippetUrl, admin.app().options.projectId || process.env.GCLOUD_PROJECT);
  if (data.audioSnippetUrl !== undefined) {
    updates.MediaObjectId = media?.id ?? null;
    if (media) updates.audioSnippetUrl = media.url;
  }

  // Atomically update canonical pin and publicMapPinFeed projection
  const merged = { ...existing, ...updates };
  const rootUpdates = {};
  if (media) rootUpdates[media.path] = pinId;
  for (const [k, v] of Object.entries(updates)) {
    rootUpdates[`SubRequests/${pinId}/${k}`] = v;
  }

  const isStillValid = (merged.NotificationMode === 'map_pin' || merged.notificationMode === 'map_pin') &&
    merged.Status !== 'cancelled' && merged.status !== 'cancelled' &&
    merged.Status !== 'deleted' && merged.status !== 'deleted' &&
    merged.Status !== 'closed' && merged.status !== 'closed';

  if (isStillValid) {
    rootUpdates[`publicMapPinFeed/${pinId}`] = sanitizeMapPinProjection(merged);
  } else {
    rootUpdates[`publicMapPinFeed/${pinId}`] = null;
  }

  await db.ref().update(rootUpdates);

  console.log(`[updateMapPin] Successfully updated pin ${pinId} for caller ${callerUid}`);

  const updatedSnap = await pinRef.get();
  return {
    success: true,
    id: pinId,
    pin: updatedSnap.val(),
  };
});

// Live Band Audio Broadcasting (SEND-LIVE-01)
const {
  startLiveBroadcast,
  joinLiveBroadcast,
  leaveLiveBroadcast,
  stopLiveBroadcast,
} = require('./live_broadcasts');


/**
 * Server-owned Cloud Function callable to securely delete an existing Map Pin.
 * Requires authenticated caller, validates pin ID, verifies NotificationMode == 'map_pin',
 * enforces authorization (creator or band leader/admin), and atomically removes
 * canonical record and supported projection via a root multi-location update.
 */
exports.deleteMapPin = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to delete a map pin.');
  }

  const data = request.data;
  const pinId = data?.pinId || data?.id || data?.subRequestId;
  if (!pinId || typeof pinId !== 'string' || pinId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Valid pin id is required.');
  }

  const db = admin.database();
  let existing = null;

  const pinRef = db.ref(`SubRequests/${pinId}`);
  const snap = await pinRef.get();
  if (snap.exists()) {
    existing = snap.val() || {};
  }

  if (!existing) {
    // Idempotent: canonical absence is sufficient; obsolete stores are not consulted.
    return {
      success: true,
      id: pinId,
      alreadyDeleted: true,
    };
  }
  const notifMode = existing.NotificationMode || existing.notificationMode || (existing.extraFields && (existing.extraFields.NotificationMode || existing.extraFields.notificationMode));
  if (notifMode !== 'map_pin') {
    throw new HttpsError('failed-precondition', 'deleteMapPin can only delete ordinary map pins.');
  }

  await membershipAuthority.authorizeMapPin(db, callerUid, existing);

  const updates = {};
  updates[`SubRequests/${pinId}`] = null;
  updates[`publicMapPinFeed/${pinId}`] = null;


  await db.ref().update(updates);

  console.log(`[deleteMapPin] Successfully deleted map pin ${pinId} for caller ${callerUid}`);

  return {
    success: true,
    id: pinId,
  };
});

exports.startLiveBroadcast = startLiveBroadcast;
exports.joinLiveBroadcast = joinLiveBroadcast;
exports.leaveLiveBroadcast = leaveLiveBroadcast;
exports.stopLiveBroadcast = stopLiveBroadcast;
exports.KNOWN_FEATURE_IDS = KNOWN_FEATURE_IDS;
exports.resolveNotificationFeatureId = resolveNotificationFeatureId;


exports.buildEventProjections = buildEventProjections;
exports.getAuthorizedUserIdsForBandEvent = getAuthorizedUserIdsForBandEvent;
exports.calculateReconciliationDiff = calculateReconciliationDiff;
exports.buildProjectionIndexKey = buildProjectionIndexKey;
exports.sanitizeMapPinProjection = sanitizeMapPinProjection;
