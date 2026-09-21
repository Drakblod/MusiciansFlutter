const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { onValueCreated, onValueWritten } = require('firebase-functions/v2/database');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const crypto = require('crypto');
if (!admin.apps.length) {
  admin.initializeApp();
}

// In production, RTDB is located in europe-west1 (musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app).
// During local emulator execution, RTDB emulator operates under default us-central1 routing.
const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true' ||
  process.env.FIREBASE_DATABASE_EMULATOR_HOST !== undefined ||
  process.env.FIREBASE_EMULATOR_HUB !== undefined;
const databaseTriggerRegion = isEmulator ? 'us-central1' : 'europe-west1';

/**
 * Helper to record a single user notification in /userNotifications/{recipientUserId}/{notificationId}
 */
async function recordUserNotification(recipientUserId, notificationData) {
  if (!recipientUserId) return;
  try {
    const now = Date.now();
    const notificationId = notificationData.id || `notif_${now}_${recipientUserId}_${Math.random().toString(36).substring(2, 8)}`;
    const payload = {
      id: notificationId,
      type: notificationData.type || 'system',
      category: notificationData.category || 'system',
      title: notificationData.title || '',
      body: notificationData.body || '',
      createdAt: notificationData.createdAt || now,
      isRead: false,
      readAt: null,
      data: notificationData.data || {},
    };
    await admin.database().ref(`/userNotifications/${recipientUserId}/${notificationId}`).set(payload);
  } catch (err) {
    console.error(`Error recording user notification for ${recipientUserId}:`, err);
  }
}

/**
 * Helper to record multiple user notifications in batch
 */
async function recordUserNotificationsBatch(recipientUserIds, notificationDataBuilder) {
  if (!recipientUserIds || recipientUserIds.length === 0) return;
  try {
    const updates = {};
    const now = Date.now();
    for (const recipientId of recipientUserIds) {
      if (!recipientId) continue;
      const notif = typeof notificationDataBuilder === 'function'
        ? notificationDataBuilder(recipientId)
        : notificationDataBuilder;
      const notificationId = notif.id || `notif_${now}_${recipientId}_${Math.random().toString(36).substring(2, 8)}`;
      updates[`/userNotifications/${recipientId}/${notificationId}`] = {
        id: notificationId,
        type: notif.type || 'system',
        category: notif.category || 'system',
        title: notif.title || '',
        body: notif.body || '',
        createdAt: notif.createdAt || now,
        isRead: false,
        readAt: null,
        data: notif.data || {},
      };
    }
    if (Object.keys(updates).length > 0) {
      await admin.database().ref().update(updates);
    }
  } catch (err) {
    console.error('Error batch recording user notifications:', err);
  }
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

      const memberIds = Object.keys(members);
      const otherMemberIds = memberIds.filter(userId => userId !== creatorId);

      // 1. Format Date/Time, Event Type, and Notification content safely
      const rawEventType = eventData.eventType || eventData.EventType;
      const normalizedEventType = (typeof rawEventType === 'string' && rawEventType.trim().length > 0)
        ? rawEventType.trim().toLowerCase()
        : 'event';

      const startLocal = eventData.startDateTime
        ? new Date(eventData.startDateTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        : 'TBD';

      const eventTitle = eventData.title || 'Band Event';
      const eventLocation = eventData.location || 'TBD';
      const notificationTitle = `🎼 New Event: ${eventTitle}`;
      const notificationBody = `New ${normalizedEventType} at ${eventLocation} starting at ${startLocal}. Please RSVP!`;

      // Record Notification Center entries for all other band members independently of push tokens
      await recordUserNotificationsBatch(otherMemberIds, (uid) => ({
        id: `notif_evt_inv_${bandId}_${eventId}_${uid}`,
        type: 'event_invite',
        category: 'events',
        title: notificationTitle,
        body: notificationBody,
        createdAt: Date.now(),
        data: {
          bandId,
          eventId,
          type: 'event_invite',
        },
      }));

      const recipients = []; // Array of { userId, token }

      // 2. Fetch the FCM push token for each member in parallel (excluding creator)
      const tokenPromises = otherMemberIds
        .map(async (userId) => {
          const tokenSnapshot = await admin.database().ref(`/users/${userId}/info/PushToken`).once('value');
          const token = tokenSnapshot.val();
          if (token && token.trim().length > 0) {
            recipients.push({ userId, token });
          }
        });

      await Promise.all(tokenPromises);

      if (recipients.length === 0) {
        console.log('No registered push tokens found for other band members.');
        return null;
      }

      // 3. Construct push notification messages for each token using FCM v1
      const messages = recipients.map(r => ({
        token: r.token,
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          bandId: bandId,
          eventId: eventId,
          type: 'event_invite',
        },
        android: {
          notification: {
            sound: 'reminder_rsvp',
            channelId: 'rsvp_reminder_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'reminder_rsvp.wav',
            },
          },
        },
      }));

      // 5. Dispatch notifications
      const response = await admin.messaging().sendEach(messages);
      console.log(`Successfully sent event push notifications: ${response.successCount} succeeded, ${response.failureCount} failed.`);
      
      // Clean up invalid/stale tokens
      response.responses.forEach((res, index) => {
        if (!res.success && res.error) {
          const error = res.error;
          const recipient = recipients[index];
          if (recipient) {
            console.error(`Failure sending notification to user ${recipient.userId} with token ${recipient.token}:`, error);
            if (error.code === 'messaging/invalid-registration-token' ||
                error.code === 'messaging/registration-token-not-registered') {
              // Remove bad token from database
              admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();
              console.log(`Removed invalid token for user ${recipient.userId}`);
            }
          }
        }
      });

      return null;
    } catch (error) {
      console.error('Error sending event push notification:', error);
      return null;
    }
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

  const rawVoicePart = subRequestData.VoicePart || subRequestData.voicePart;
  if (!rawVoicePart || typeof rawVoicePart !== 'string' || !rawVoicePart.trim()) {
    console.log(`Skipping legacy notification for subrequest ${subRequestId} due to missing or invalid VoicePart.`);
    return null;
  }
  const voicePart = rawVoicePart.trim();
  const creatorUserId = subRequestData.CreatorUserId || subRequestData.UserId;
  const location = subRequestData.Location || 'TBD';
  const bandName = subRequestData.BandName || 'Freelance Gig';
  const targetUserIds = subRequestData.TargetUserIds; // Array of user IDs

  try {
    // 1. Fetch all users to resolve target profiles/tokens
    const usersRef = admin.database().ref('/users');
    const usersSnapshot = await usersRef.once('value');
    const users = usersSnapshot.val();
    if (!users) {
      console.log('No users found in the system.');
      return null;
    }

    const matchingUserIds = [];
    const recipients = [];

    // 2. Identify target recipients and their tokens
    Object.keys(users).forEach((userId) => {
      // Exclude creator
      if (userId === creatorUserId) return;

      const userInfo = users[userId].info;
      if (!userInfo) return;

      let shouldNotify = false;
      if (targetUserIds && Array.isArray(targetUserIds) && targetUserIds.length > 0) {
        // Targeted mode: only selected user IDs
        shouldNotify = targetUserIds.includes(userId);
      } else {
        // Default mode: matches the requested instrument/voice part
        const userType = userInfo.UserType || userInfo.userType || '';
        const instruments = userInfo.Instruments || userInfo.instruments || [];
        
        const hasMatchingInstrument = 
          (typeof userType === 'string' && userType.toLowerCase() === voicePart.toLowerCase()) ||
          (Array.isArray(instruments) && instruments.some(i => typeof i === 'string' && i.toLowerCase() === voicePart.toLowerCase()));
          
        shouldNotify = hasMatchingInstrument;
      }

      if (shouldNotify) {
        matchingUserIds.push(userId);
        const token = userInfo.PushToken;
        if (token && token.trim().length > 0) {
          recipients.push({ userId, token: token.trim() });
        }
      }
    });

    // Record Notification Center entries for all matching users
    await recordUserNotificationsBatch(matchingUserIds, (uid) => ({
      id: `notif_sub_${subRequestId}_${uid}`,
      type: 'sub_request_invite',
      category: 'requests',
      title: `🎼 Musician Request`,
      body: `${voicePart} needed for ${bandName} in ${location}!`,
      createdAt: Date.now(),
      data: {
        subRequestId: subRequestId,
        type: 'sub_request_invite',
        bandId: subRequestData.bandId || subRequestData.BandId || '',
        eventId: subRequestData.eventId || subRequestData.EventId || '',
      },
    }));

    if (recipients.length === 0) {
      console.log('No matching recipients with push tokens found.');
      return null;
    }

    // 3. Construct messages for FCM v1
    const messages = recipients.map(r => ({
      token: r.token,
      notification: {
        title: `🎼 Musician Request`,
        body: `${voicePart} needed for ${bandName} in ${location}!`,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        subRequestId: subRequestId,
        type: 'sub_request_invite',
      },
      android: {
        notification: {
          sound: 'gig_rquest',
          channelId: 'gig_request_channel',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'gig_rquest.wav',
          },
        },
      },
    }));

    // 4. Send notifications
    const response = await admin.messaging().sendEach(messages);
    console.log(`Successfully sent sub request notifications: ${response.successCount} succeeded, ${response.failureCount} failed.`);

    // Clean up invalid/stale tokens
    response.responses.forEach((res, index) => {
      if (!res.success && res.error) {
        const error = res.error;
        const recipient = recipients[index];
        if (recipient) {
          console.error(`Failure sending notification to user ${recipient.userId} with token ${recipient.token}:`, error);
          if (error.code === 'messaging/invalid-registration-token' ||
              error.code === 'messaging/registration-token-not-registered') {
            // Remove bad token from database
            admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();
            console.log(`Removed invalid token for user ${recipient.userId}`);
          }
        }
      }
    });

    return null;
  } catch (error) {
    console.error('Error sending sub request notifications:', error);
    return null;
  }
});

/**
 * Triggered when a grouped substitute request publication manifest is created under /subRequestPublications/{publicationId}.
 * Sends exactly one combined push notification per recipient for all matching/targeted slots in the publication.
 */
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
 * Triggered when a grouped substitute request publication manifest is created under /subRequestPublications/{publicationId}.
 * Maintains server-authorized audience and feed indexes and sends exactly one combined push notification per recipient.
 */
exports.onSubRequestGroupPublished = onValueCreated({
  ref: '/subRequestPublications/{publicationId}',
  region: databaseTriggerRegion
}, async (event) => {
  const pubData = event.data.val();
  if (!pubData) return null;

  const publicationId = event.params.publicationId;
  const requestGroupId = pubData.requestGroupId || publicationId;
  const creatorUserId = pubData.creatorUserId;
  const bandName = pubData.bandName || 'Freelance Gig';
  const slots = pubData.slots || [];

  if (!slots.length) return null;

  try {
    const db = admin.database();
    const auditRef = db.ref(`/subRequestNotificationAudit/${publicationId}`);
    const auditRecipientsSnap = await auditRef.child('recipients').once('value');
    const existingNotifiedRecipients = auditRecipientsSnap.val() || {};

    const usersRef = db.ref('/users');
    const usersSnapshot = await usersRef.once('value');
    const users = usersSnapshot.val();
    if (!users) return null;

    const recipientMap = new Map(); // userId -> { token, matchingSlots: [] }
    const indexUpdates = {};

    // Creator management index
    if (creatorUserId) {
      indexUpdates[`/creatorSubRequestGroups/${creatorUserId}/${requestGroupId}`] = true;
    }

    Object.keys(users).forEach((userId) => {
      const userInfo = users[userId].info;
      const token = userInfo ? userInfo.PushToken : null;
      const userType = (userInfo ? (userInfo.UserType || userInfo.userType || '') : '').toLowerCase();
      const instruments = (userInfo ? (userInfo.Instruments || userInfo.instruments || []) : []).map(i => (i || '').toLowerCase());

      const userMatchingSlots = [];

      slots.forEach((slot) => {
        const slotKey = slot.subRequestId || slot.slotId;
        const voicePart = (slot.voicePart || '').toLowerCase();
        const searchSource = slot.searchSource || 'search_all';
        const targetUserIds = slot.targetUserIds || [];

        let isEligible = false;
        if (searchSource === 'favorites') {
          isEligible = Array.isArray(targetUserIds) && targetUserIds.includes(userId);
        } else {
          isEligible = userType === voicePart || instruments.includes(voicePart);
        }

        if (isEligible) {
          userMatchingSlots.push(slot);
          if (slotKey) {
            indexUpdates[`/subRequestAudience/${slotKey}/${userId}`] = true;
            indexUpdates[`/userSubRequestFeed/${userId}/${slotKey}`] = {
              slotId: slot.slotId || slotKey,
              requestGroupId: requestGroupId,
              bandName: bandName,
              voicePart: slot.voicePart || '',
              date: slot.date || '',
              searchSource: searchSource,
              publishedAt: pubData.publishedAt || Date.now(),
            };
          }
        }
      });

      // Eligible non-creator users with matching slots
      if (userId !== creatorUserId && userMatchingSlots.length > 0) {
        if (token && token.trim() && !existingNotifiedRecipients[userId]) {
          recipientMap.set(userId, { token, matchingSlots: userMatchingSlots });
        }
        // Record Notification Center entry
        const matchCount = userMatchingSlots.length;
        const firstSlot = userMatchingSlots[0];
        const title = `🎼 Musician Request`;
        const body = matchCount === 1
          ? `${firstSlot.voicePart} needed for ${bandName}!`
          : `Multiple substitute positions (${matchCount}) open for ${bandName}!`;
        indexUpdates[`/userNotifications/${userId}/notif_sub_grp_${publicationId}_${userId}`] = {
          id: `notif_sub_grp_${publicationId}_${userId}`,
          type: 'grouped_sub_request',
          category: 'requests',
          title,
          body,
          createdAt: pubData.publishedAt || Date.now(),
          isRead: false,
          readAt: null,
          data: {
            requestGroupId,
            publicationId,
            type: 'grouped_sub_request',
          },
        };
      }
    });

    // Write server-maintained audience, feed, and notification indexes in bulk
    if (Object.keys(indexUpdates).length > 0) {
      await db.ref().update(indexUpdates);
    }

    // Atomic per-recipient transaction claim to protect from concurrent trigger executions
    const claimedRecipients = [];
    for (const [userId, entry] of recipientMap.entries()) {
      const recipientAuditRef = auditRef.child('recipients').child(userId);
      const claimTx = await recipientAuditRef.transaction((current) => {
        if (current && (current.status === 'sent' || (current.status === 'claimed' && Date.now() - current.claimedAt < 60000))) {
          return; // Abort: already sent or claimed by an active invocation
        }
        return { status: 'claimed', claimedAt: Date.now() };
      });

      if (claimTx.committed && claimTx.snapshot.val() && claimTx.snapshot.val().status === 'claimed') {
        claimedRecipients.push({ userId, entry });
      }
    }

    if (claimedRecipients.length === 0) {
      await auditRef.update({
        processedAt: Date.now(),
        requestGroupId,
        notifiedCount: Object.keys(existingNotifiedRecipients).length,
      });
      return null;
    }

    const messages = [];
    const messageRecipients = [];

    claimedRecipients.forEach(({ userId, entry }) => {
      const matchCount = entry.matchingSlots.length;
      const firstSlot = entry.matchingSlots[0];
      const title = `🎼 Musician Request`;
      const body = matchCount === 1
        ? `${firstSlot.voicePart} needed for ${bandName}!`
        : `Multiple substitute positions (${matchCount}) open for ${bandName}!`;

      messages.push({
        token: entry.token,
        notification: {
          title,
          body,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          requestGroupId: requestGroupId,
          publicationId: publicationId,
          type: 'grouped_sub_request',
        },
        android: {
          notification: {
            sound: 'gig_rquest',
            channelId: 'gig_request_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'gig_rquest.wav',
            },
          },
        },
      });
      messageRecipients.push(userId);
    });

    const response = await admin.messaging().sendEach(messages);
    console.log(`Sent grouped sub request notifications for ${publicationId}: ${response.successCount} succeeded, ${response.failureCount} failed.`);

    // Per-recipient delivery audit state for partial recovery
    const perRecipientAuditUpdates = {};
    messageRecipients.forEach((uid, idx) => {
      if (response.responses[idx] && response.responses[idx].success) {
        perRecipientAuditUpdates[`/subRequestNotificationAudit/${publicationId}/recipients/${uid}`] = {
          notifiedAt: Date.now(),
          status: 'sent',
        };
      } else {
        perRecipientAuditUpdates[`/subRequestNotificationAudit/${publicationId}/recipients/${uid}`] = {
          failedAt: Date.now(),
          status: 'failed',
          error: response.responses[idx]?.error?.message || 'Unknown send error',
        };
      }
    });

    perRecipientAuditUpdates[`/subRequestNotificationAudit/${publicationId}/processedAt`] = Date.now();
    perRecipientAuditUpdates[`/subRequestNotificationAudit/${publicationId}/requestGroupId`] = requestGroupId;
    perRecipientAuditUpdates[`/subRequestNotificationAudit/${publicationId}/notifiedCount`] =
      Object.keys(existingNotifiedRecipients).length + response.successCount;

    await db.ref().update(perRecipientAuditUpdates);

    return null;
  } catch (error) {
    console.error('Error in onSubRequestGroupPublished:', error);
    return null;
  }
});

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
  const { bandId, requestGroupId, eventId, slots, bandName } = data;

  if (!requestGroupId || !slots || !Array.isArray(slots) || slots.length === 0) {
    throw new HttpsError('invalid-argument', 'Invalid request payload.');
  }

  const db = admin.database();

  // 1. Validate band authorization and event ownership if bandId is provided
  if (bandId) {
    const memberRoleSnap = await db.ref(`/Bands/${bandId}/Members_band/${callerId}/Role`).once('value');
    const role = memberRoleSnap.val();
    if (role !== 'Leader' && role !== 'Admin') {
      throw new HttpsError('permission-denied', 'Only Band Leaders or Admins can publish substitute requests for this band.');
    }

    // Verify all slots belong to the band and verify event ownership
    for (const slot of slots) {
      if (slot.bandId && slot.bandId !== bandId) {
        throw new HttpsError('invalid-argument', 'Mixed band slots in a single publication group are rejected.');
      }
      const slotEventId = slot.eventId || eventId;
      if (slotEventId && slotEventId !== 'standalone') {
        const evSnap = await db.ref(`/Bands/${bandId}/Events/${slotEventId}`).once('value');
        if (!evSnap.exists()) {
          throw new HttpsError('permission-denied', `Event ${slotEventId} does not belong to band ${bandId}.`);
        }
      }
    }
  }

  // 2. Fetch creator favorites to strictly validate targeted favorites
  const callerFavSnap = await db.ref(`/users/${callerId}/Favorites`).once('value');
  const callerFavorites = callerFavSnap.val() || {};

  const slotIds = slots.map(s => s.subRequestId || s.slotId).filter(Boolean);
  const publicationId = computeStablePublicationId(requestGroupId, slotIds);

  const updates = {};
  const now = Date.now();

  // 3. Write each canonical SubRequest
  slots.forEach((slot) => {
    const slotKey = slot.subRequestId || slot.slotId;
    updates[`/SubRequests/${slotKey}`] = {
      ...slot,
      SubRequestId: slotKey,
      SlotId: slot.slotId || slotKey,
      RequestGroupId: requestGroupId,
      PublicationId: publicationId,
      NotificationMode: 'grouped',
      CreatorUserId: callerId,
      Status: 'published',
      CreatedAt: slot.createdAt || now,
    };
  });

  // 4. Write publication manifest
  updates[`/subRequestPublications/${publicationId}`] = {
    publicationId,
    requestGroupId,
    creatorUserId: callerId,
    bandId: bandId || null,
    bandName: bandName || 'Freelance Gig',
    publishedAt: now,
    slots: slots.map(s => ({
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

  // 5. Populate audience and feed indexes across users
  const usersSnap = await db.ref('/users').once('value');
  const users = usersSnap.val() || {};

  if (callerId) {
    updates[`/creatorSubRequestGroups/${callerId}/${requestGroupId}`] = true;
  }

  Object.keys(users).forEach((userId) => {
    const userInfo = users[userId].info;
    const userType = (userInfo ? (userInfo.UserType || userInfo.userType || '') : '').toLowerCase();
    const instruments = (userInfo ? (userInfo.Instruments || userInfo.instruments || []) : []).map(i => (i || '').toLowerCase());

    slots.forEach((slot) => {
      const slotKey = slot.subRequestId || slot.slotId;
      const voicePart = (slot.voicePart || slot.VoicePart || '').toLowerCase();
      const searchSource = slot.searchSource || slot.SearchSource || 'search_all';
      const rawTargetUserIds = slot.targetUserIds || slot.TargetUserIds || [];

      let isEligible = false;
      if (searchSource === 'favorites') {
        // Enforce that target user is genuinely in the caller's favorites list
        const isVerifiedFavorite = callerFavorites[userId] === true || callerFavorites[userId] === 'true';
        isEligible = isVerifiedFavorite && Array.isArray(rawTargetUserIds) && rawTargetUserIds.includes(userId);
      } else {
        isEligible = userType === voicePart || instruments.includes(voicePart);
      }

      if (isEligible && slotKey) {
        updates[`/subRequestAudience/${slotKey}/${userId}`] = true;
        updates[`/userSubRequestFeed/${userId}/${slotKey}`] = {
          slotId: slot.slotId || slotKey,
          requestGroupId: requestGroupId,
          bandName: bandName || 'Freelance Gig',
          voicePart: slot.voicePart || slot.VoicePart || '',
          date: slot.date || slot.Date || '',
          searchSource: searchSource,
          publishedAt: now,
        };
      }
    });
  });

  // Single atomic root multi-location update containing all prerequisites and manifest
  await db.ref().update(updates);

  return {
    success: true,
    publicationId,
    requestGroupId,
    slotCount: slots.length,
  };
});

/**
 * Secure server-owned Cloud Function callable to assign a candidate to a SubRequest slot.
 * Enforces authentication, Band Leader/Admin/Creator authorization, candidate eligibility,
 * and performs an atomic RTDB transaction rejecting competing candidates while ensuring idempotent retry.
 */
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

  const db = admin.database();
  const subReqRef = db.ref(`/SubRequests/${subRequestId}`);
  const subReqSnap = await subReqRef.once('value');
  if (!subReqSnap.exists()) {
    throw new HttpsError('not-found', `SubRequest ${subRequestId} does not exist.`);
  }

  const subReqData = subReqSnap.val();
  const targetBandId = bandId || subReqData.bandId || subReqData.BandId;
  const targetEventId = eventId || subReqData.eventId || subReqData.EventId;
  const creatorUserId = subReqData.CreatorUserId || subReqData.UserId;

  // Authorization check: Caller must be creator OR Band Leader/Admin of the request's band
  let isAuthorized = (creatorUserId === callerId);
  if (!isAuthorized && targetBandId) {
    const memberSnap = await db.ref(`/Bands/${targetBandId}/Members_band/${callerId}`).once('value');
    if (memberSnap.exists()) {
      const role = memberSnap.val()?.Role || memberSnap.val()?.role;
      if (role === 'Leader' || role === 'Admin') {
        isAuthorized = true;
      }
    }
  }

  if (!isAuthorized) {
    throw new HttpsError('permission-denied', 'Only Band Leaders, Band Admins, or the Request Creator can assign substitutes.');
  }

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

    updates[`/Bands/${targetBandId}/Members_band/${candidateUserId}`] = {
      Nickname: candidateName || 'Substitute',
      Role: 'Substitute',
    };
    updates[`/bandconversations/${targetBandId}/members/${candidateUserId}`] = true;
  }

  if (targetBandId) {
    try {
      const bandSnap = await db.ref(`/Bands/${targetBandId}`).once('value');
      if (bandSnap.exists()) {
        updates[`/users/${candidateUserId}/Bands/${targetBandId}`] = bandSnap.val();
      }
    } catch (e) {
      console.error('Error fetching band for user index:', e);
    }
  }

  if (callerId) {
    updates[`/users/${callerId}/SubRequests/${subRequestId}/IsSelected`] = true;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/Status`] = 'assigned';
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserId`] = candidateUserId;
    if (candidateName) {
      updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserName`] = candidateName;
    }
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedAt`] = now;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedBy`] = callerId;
  }

  if (Object.keys(updates).length > 0) {
    await db.ref().update(updates);
  }

  // Record Notification Center entry for candidate
  const gigTitle = subReqData.VoicePart ? `Gig Confirmed: ${subReqData.VoicePart}` : 'Gig Confirmed!';
  const bandDesc = targetBandId ? `You have been assigned to play with ${subReqData.BandName || 'the band'}!` : 'You have been confirmed for the gig!';
  await recordUserNotification(candidateUserId, {
    id: `notif_gig_fin_${subRequestId}_${candidateUserId}`,
    type: 'gig_finalized',
    category: 'requests',
    title: `🎉 ${gigTitle}`,
    body: bandDesc,
    createdAt: now,
    data: {
      subRequestId: subRequestId,
      bandId: targetBandId || '',
      eventId: targetEventId || '',
      type: 'gig_finalized',
    },
  });

  // Dispatch finalized gig push notification to candidate
  try {
    const candidateTokenSnap = await db.ref(`/users/${candidateUserId}/info/PushToken`).once('value');
    const candidateToken = candidateTokenSnap.val();
    if (candidateToken && typeof candidateToken === 'string' && candidateToken.trim()) {
      await admin.messaging().send({
        token: candidateToken.trim(),
        notification: {
          title: `🎉 ${gigTitle}`,
          body: bandDesc,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          subRequestId: subRequestId,
          type: 'gig_finalized',
        },
        android: {
          notification: {
            sound: 'finalized_gig',
            channelId: 'finalized_gig_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'finalized_gig.wav',
            },
          },
        },
      });
      console.log(`Sent gig finalized push notification to candidate ${candidateUserId}`);
    }
  } catch (pushErr) {
    console.warn(`Failed to send gig finalized push notification to candidate: ${pushErr.message}`);
  }

  return {
    success: true,
    subRequestId,
    assignedUserId: candidateUserId,
    status: 'assigned',
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

  const db = admin.database();
  const subReqRef = db.ref(`/SubRequests/${subRequestId}`);
  const subReqSnap = await subReqRef.once('value');
  if (!subReqSnap.exists()) {
    throw new HttpsError('not-found', `SubRequest ${subRequestId} does not exist.`);
  }

  const subReqData = subReqSnap.val();
  const targetBandId = bandId || subReqData.bandId || subReqData.BandId;
  const targetEventId = eventId || subReqData.eventId || subReqData.EventId;
  const creatorUserId = subReqData.CreatorUserId || subReqData.UserId;

  let isAuthorized = (creatorUserId === callerId);
  if (!isAuthorized && targetBandId) {
    const memberSnap = await db.ref(`/Bands/${targetBandId}/Members_band/${callerId}`).once('value');
    if (memberSnap.exists()) {
      const role = memberSnap.val()?.Role || memberSnap.val()?.role;
      if (role === 'Leader' || role === 'Admin') {
        isAuthorized = true;
      }
    }
  }

  if (!isAuthorized) {
    throw new HttpsError('permission-denied', 'Only Band Leaders, Band Admins, or Creator can revoke assignments.');
  }

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

  if (callerId) {
    updates[`/users/${callerId}/SubRequests/${subRequestId}/IsSelected`] = false;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/Status`] = 'published';
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserId`] = null;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserName`] = null;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedAt`] = null;
    updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedBy`] = null;
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

        // Record Notification Center entry for creator
        await recordUserNotification(creatorId, {
          id: `notif_evt_thresh_${bandId}_${eventId}_${creatorId}`,
          type: 'event_threshold',
          category: 'events',
          title: `📈 Event RSVP Milestone!`,
          body: `70% or more of invited members have responded to your event: "${eventData.title || 'Band Event'}"`,
          createdAt: Date.now(),
          data: {
            bandId: bandId,
            eventId: eventId,
            type: 'event_threshold',
          },
        });

        // Fetch creator push token
        const tokenSnapshot = await admin.database().ref(`/users/${creatorId}/info/PushToken`).once('value');
        const token = tokenSnapshot.val();

        if (token && token.trim().length > 0) {
          const message = {
            token: token,
            notification: {
              title: `📈 Event RSVP Milestone!`,
              body: `70% or more of invited members have responded to your event: "${eventData.title}"`,
            },
            data: {
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              bandId: bandId,
              eventId: eventId,
              type: 'event_threshold',
            },
            android: {
              notification: {
                sound: 'reminder_rsvp',
                channelId: 'rsvp_reminder_channel',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'reminder_rsvp.wav',
                },
              },
            },
          };

          await admin.messaging().send(message);
          console.log(`Sent threshold push notification to creator ${creatorId}`);
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
exports.checkEventReminders = functions.pubsub
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
            const memberIds = Object.keys(members);

            // Get users who have NOT responded yet (not present in Responses)
            const responses = event.Responses || {};
            const nonRespondedMemberIds = memberIds.filter(userId => !responses[userId]);

            if (nonRespondedMemberIds.length > 0) {
              const reminderHours = send84 ? '84h' : (send72 ? '72h' : (send48 ? '48h' : 'rem'));
              await recordUserNotificationsBatch(nonRespondedMemberIds, (uid) => ({
                id: `notif_evt_rem_${bandId}_${eventId}_${uid}_${reminderHours}`,
                type: 'event_reminder',
                category: 'events',
                title: `⏰ RSVP Reminder: ${event.title || 'Band Event'}`,
                body: `Please RSVP to the upcoming ${(event.eventType || 'event').toLowerCase()}! Let the band know if you can make it.`,
                createdAt: Date.now(),
                data: {
                  bandId,
                  eventId,
                  type: 'event_reminder',
                },
              }));

              const recipients = [];
              const tokenPromises = nonRespondedMemberIds.map(async (userId) => {
                const tokenSnapshot = await admin.database().ref(`/users/${userId}/info/PushToken`).once('value');
                const token = tokenSnapshot.val();
                if (token && token.trim().length > 0) {
                  recipients.push({ userId, token });
                }
              });

              await Promise.all(tokenPromises);

              if (recipients.length > 0) {
                const messages = recipients.map(r => ({
                  token: r.token,
                  notification: {
                    title: `⏰ RSVP Reminder: ${event.title}`,
                    body: `Please RSVP to the upcoming ${event.eventType.toLowerCase()}! Let the band know if you can make it.`,
                  },
                  data: {
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    bandId: bandId,
                    eventId: eventId,
                    type: 'event_reminder',
                  },
                  android: {
                    notification: {
                      sound: 'reminder_rsvp',
                      channelId: 'rsvp_reminder_channel',
                    },
                  },
                  apns: {
                    payload: {
                      aps: {
                        sound: 'reminder_rsvp.wav',
                      },
                    },
                  },
                }));

                const dispatchRes = await admin.messaging().sendEach(messages);
                console.log(`Dispatched ${dispatchRes.successCount} reminders for event ${eventId}`);
              }
            }

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

    if (!beforeData) {
      const creatorId = afterData.CreatorId || afterData.creatorId;
      if (!creatorId) {
        console.log('No CreatorId specified for the session application.');
        return null;
      }

      const sessionSnapshot = await admin.database().ref(`/Collabs/Sessions/${sessionId}/Title`).once('value');
      const sessionTitle = sessionSnapshot.val() || 'Collab Session';

      // Record Notification Center entry for session creator
      await recordUserNotification(creatorId, {
        id: `notif_collab_app_${sessionId}_${applicantId}`,
        type: 'session_application',
        category: 'requests',
        title: 'New Session Application',
        body: `A user has requested to join your session: "${sessionTitle}"`,
        createdAt: Date.now(),
        data: {
          sessionId: sessionId,
          applicantId: applicantId,
          type: 'session_application',
        },
      });

      const tokenSnapshot = await admin.database().ref(`/users/${creatorId}/info/PushToken`).once('value');
      const token = tokenSnapshot.val();

      if (!token) {
        console.log(`No registered push token found for session creator ${creatorId}`);
        return null;
      }

      const message = {
        token: token,
        notification: {
          title: 'New Session Application',
          body: `A user has requested to join your session: "${sessionTitle}"`,
        },
        data: {
          type: 'session_application',
          sessionId: sessionId,
          applicantId: applicantId,
        },
        android: {
          notification: {
            sound: 'gig_rquest_response',
            channelId: 'gig_response_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'gig_rquest_response.wav',
            },
          },
        },
      };

      await admin.messaging().send(message);
      console.log(`Sent new application notification to session creator ${creatorId}`);
      return null;
    }

    const beforeStatus = beforeData.Status || beforeData.status;
    const afterStatus = afterData.Status || afterData.status;

    if (beforeStatus !== afterStatus) {
      if (afterStatus === 'accepted' || afterStatus === 'declined') {
        const sessionSnapshot = await admin.database().ref(`/Collabs/Sessions/${sessionId}/Title`).once('value');
        const sessionTitle = sessionSnapshot.val() || 'Collab Session';

        // Record Notification Center entry for applicant
        await recordUserNotification(applicantId, {
          id: `notif_collab_status_${sessionId}_${applicantId}_${afterStatus}`,
          type: 'session_application_status',
          category: 'requests',
          title: `Session Request ${afterStatus.toUpperCase()}`,
          body: `Your request to join "${sessionTitle}" has been ${afterStatus}.`,
          createdAt: Date.now(),
          data: {
            sessionId: sessionId,
            status: afterStatus,
            type: 'session_application_status',
          },
        });

        const tokenSnapshot = await admin.database().ref(`/users/${applicantId}/info/PushToken`).once('value');
        const token = tokenSnapshot.val();

        if (!token) {
          console.log(`No registered push token found for applicant ${applicantId}`);
          return null;
        }

        const message = {
          token: token,
          notification: {
            title: `Session Request ${afterStatus.toUpperCase()}`,
            body: `Your request to join "${sessionTitle}" has been ${afterStatus}.`,
          },
          data: {
            type: 'session_application_status',
            sessionId: sessionId,
            status: afterStatus,
          },
          android: {
            notification: {
              sound: 'gig_rquest_response',
              channelId: 'gig_response_channel',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'gig_rquest_response.wav',
              },
            },
          },
        };

        await admin.messaging().send(message);
        console.log(`Sent application status ${afterStatus} notification to applicant ${applicantId}`);
      }
      return null;
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

  // Caller must be either creatorUid or applicantId
  if (callerUid !== creatorUid && callerUid !== applicantId) {
    throw new HttpsError('permission-denied', 'You are not authorized for this agreement conversation.');
  }

  // Receiver is the other party
  const receiverUid = (callerUid === applicantId) ? creatorUid : applicantId;

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

  const agreementPayload = {
    subRequestId: subRequestId,
    applicantId: applicantId,
    creatorId: creatorUid,
    bandName: subReqData.BandName || 'Gig Agreement',
    voicePart: subReqData.VoicePart || 'Musician',
    status: 'pending',
  };

  const convRef = admin.database().ref(`/conversations/${conversationId}`);
  const convSnap = await convRef.once('value');

  if (!convSnap.exists()) {
    await convRef.set({
      participants: { [callerUid]: true, [receiverUid]: true },
      Participants: [callerUid, receiverUid],
      createdTimestamp: new Date().toISOString(),
      agreement: agreementPayload,
      Agreement: agreementPayload,
    });
  }

  // Idempotent user index repair
  const u1Ref = admin.database().ref(`/userConversations/${callerUid}/${conversationId}`);
  const u2Ref = admin.database().ref(`/userConversations/${receiverUid}/${conversationId}`);

  const [u1Snap, u2Snap] = await Promise.all([u1Ref.once('value'), u2Ref.once('value')]);

  if (!u1Snap.exists()) {
    await u1Ref.set({
      otherUserId: receiverUid,
      lastMessageText: `Agreement Request: ${subReqData.VoicePart || 'Gig'}`,
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: false,
      conversationType: 'agreement',
    });
  }

  if (!u2Snap.exists()) {
    await u2Ref.set({
      otherUserId: callerUid,
      lastMessageText: `Agreement Request: ${subReqData.VoicePart || 'Gig'}`,
      lastMessageTimestamp: new Date().toISOString(),
      hasUnread: true,
      conversationType: 'agreement',
    });
  }

  return { conversationId };
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

  // Record user notifications in Notification Center
  try {
    let senderName = 'Musician';
    const senderSnap = await admin.database().ref(`/users/${senderUid}/info`).once('value');
    if (senderSnap.exists()) {
      const info = senderSnap.val();
      senderName = info.DisplayName || info.displayName || info.Nickname || info.nickname || 'Musician';
    }

    if (isSessionChat) {
      const sessionTitle = convVal.sessionTitle || 'Session Chat';
      const participantList = (pMap && typeof pMap === 'object')
        ? Object.keys(pMap).filter(id => isParticipantMember(pMap, id))
        : (Array.isArray(pMap) ? pMap.map(String) : [senderUid]);
      const otherParticipants = participantList.filter(pUid => pUid !== senderUid);
      if (otherParticipants.length > 0) {
        await recordUserNotificationsBatch(otherParticipants, (uid) => ({
          id: `notif_sess_${conversationId}_${msgId}_${uid}`,
          type: 'session_message',
          category: 'messages',
          title: `💬 ${sessionTitle}`,
          body: `${senderName}: ${text.trim().length > 100 ? `${text.trim().substring(0, 97)}...` : text.trim()}`,
          createdAt: Date.now(),
          data: {
            conversationId: conversationId,
            sessionId: convVal.sessionId || '',
            senderId: senderUid,
            type: 'session_message',
          },
        }));
      }
    } else if (receiverUid) {
      await recordUserNotification(receiverUid, {
        id: `notif_dm_${conversationId}_${msgId}`,
        type: 'direct_message',
        category: 'messages',
        title: `Message from ${senderName}`,
        body: text.trim().length > 100 ? `${text.trim().substring(0, 97)}...` : text.trim(),
        createdAt: Date.now(),
        data: {
          conversationId: conversationId,
          senderId: senderUid,
          type: 'direct_message',
        },
      });
    }
  } catch (notifErr) {
    console.error('Error recording direct/session message notification:', notifErr);
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

  const recipientsWithTokens = [];
  const tokenPromises = memberIds.map(async (uid) => {
    let token = null;
    const tokenPaths = [
      `/users/${uid}/info/PushToken`,
      `/users/${uid}/PushToken`,
      `/users/${uid}/info/pushToken`,
      `/users/${uid}/pushToken`,
      `/users/${uid}/fcmToken`,
      `/users/${uid}/info/fcmToken`,
    ];
    for (const path of tokenPaths) {
      if (token) break;
      const snap = await admin.database().ref(path).once('value');
      if (snap.exists() && typeof snap.val() === 'string' && snap.val().trim().length > 15) {
        token = snap.val().trim();
      }
    }
    if (token) {
      recipientsWithTokens.push({ userId: uid, token: token });
    }
  });

  await Promise.all(tokenPromises);

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

  const reminderLabels = {
    '24h': '24-Hour Reminder',
    '48h': '48-Hour Reminder',
    '72h': '72-Hour Reminder',
    'last': 'Final Reminder',
  };
  const reminderLabel = reminderLabels[reminderType] || `${reminderType.toUpperCase()} Reminder`;

  const messages = recipientsWithTokens.map(r => ({
    token: r.token,
    notification: {
      title: `⏰ ${reminderLabel}: ${eventData.title || 'Band Event'}`,
      body: `Please RSVP to ${eventData.title || 'the upcoming event'} (${eventData.eventType || 'Event'})! Let the band know if you can make it.`,
    },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      bandId: bandId,
      eventId: eventId,
      type: 'event_reminder',
      reminderType: reminderType,
      timestamp: Date.now().toString(),
    },
    android: {
      notification: {
        sound: 'reminder_rsvp',
        channelId: 'rsvp_reminder_channel',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'reminder_rsvp.wav',
        },
      },
    },
  }));

  let fcmResponse;
  if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.IS_EMULATOR_TEST === 'true') {
    fcmResponse = {
      responses: messages.map(() => ({ success: true, messageId: 'emulator_mock_fcm_id' })),
    };
  } else {
    fcmResponse = await admin.messaging().sendEach(messages);
  }

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
      recipientUpdates[`recipients/${recipient.userId}`] = { status: 'failed', error: res.error ? res.error.message : 'Unknown FCM error' };
      if (res.error && (res.error.code === 'messaging/invalid-registration-token' || res.error.code === 'messaging/registration-token-not-registered')) {
        admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();
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
    missingTokensCount: memberIds.length - recipientsWithTokens.length,
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
    missingTokensCount: memberIds.length - recipientsWithTokens.length,
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

  // Push notifications and notification center entries to all other current participants
  const otherParticipants = participantsList.filter(uid => uid !== senderUid);
  if (otherParticipants.length > 0) {
    try {
      const groupName = convVal.groupName || 'Section Chat';

      // Record Notification Center feed entry for all other participants
      await recordUserNotificationsBatch(otherParticipants, (uid) => ({
        id: `notif_sec_${bandId}_${conversationId}_${msgId}_${uid}`,
        type: 'band_section_chat',
        category: 'messages',
        title: `💬 ${groupName}`,
        body: `${senderName}: ${text.trim().length > 100 ? `${text.trim().substring(0, 97)}...` : text.trim()}`,
        createdAt: Date.now(),
        data: {
          conversationId: conversationId,
          bandId: bandId,
          senderId: senderUid,
          type: 'band_section_chat',
        },
      }));

      const tokenPromises = otherParticipants.map(async (uid) => {
        const tokenSnap = await admin.database().ref(`/users/${uid}/info/PushToken`).once('value');
        const token = tokenSnap.val();
        if (token && typeof token === 'string' && token.trim().length > 0) {
          return { userId: uid, token: token.trim() };
        }
        return null;
      });

      const recipientsWithTokens = (await Promise.all(tokenPromises)).filter(Boolean);

      if (recipientsWithTokens.length > 0) {
        const messages = recipientsWithTokens.map(r => ({
          token: r.token,
          notification: {
            title: `💬 ${groupName}`,
            body: `${senderName}: ${text.trim()}`,
          },
          data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            conversationId: conversationId,
            bandId: bandId,
            type: 'band_section_chat',
          },
          android: {
            notification: {
              sound: 'default',
              channelId: 'chat_notifications',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        }));

        let fcmResponse;
        if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.IS_EMULATOR_TEST === 'true') {
          fcmResponse = {
            responses: messages.map(() => ({ success: true, messageId: 'emulator_mock_fcm_id' })),
          };
        } else {
          fcmResponse = await admin.messaging().sendEach(messages);
        }

        fcmResponse.responses.forEach((res, index) => {
          if (!res.success && res.error) {
            const recipient = recipientsWithTokens[index];
            if (recipient && (res.error.code === 'messaging/invalid-registration-token' || res.error.code === 'messaging/registration-token-not-registered')) {
              admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();
            }
          }
        });
      }
    } catch (pushErr) {
      console.error('Error dispatching band section push notifications:', pushErr);
    }
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
 * 10. onBandMemberRemoved
 * Cleanup trigger when a member is removed from /Bands/{bandId}/Members_band/{memberId}
 */
exports.onBandMemberRemoved = onValueWritten({
  ref: '/Bands/{bandId}/Members_band/{memberId}',
  region: databaseTriggerRegion
}, async (event) => {
  // Only trigger on deletion
  if (event.data.after.exists()) return null;

  const bandId = event.params.bandId;
  const memberId = event.params.memberId;

  try {
    const bandSectionSnap = await admin.database().ref(`/bandSectionConversations/${bandId}`).once('value');
    if (!bandSectionSnap.exists() || !bandSectionSnap.val()) return null;

    const convIds = Object.keys(bandSectionSnap.val());
    const updates = {};

    for (const convId of convIds) {
      const convSnap = await admin.database().ref(`/conversations/${convId}`).once('value');
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

          // Ensure group still has an admin if the removed member was the only admin
          const remainingAdmins = Object.keys(convVal.admins || {}).filter(uid => uid !== memberId && convVal.admins[uid]);
          if (remainingAdmins.length === 0 && remainingParticipants.length > 0) {
            updates[`/conversations/${convId}/admins/${remainingParticipants[0]}`] = true;
          }
        }
      }
    }

    if (Object.keys(updates).length > 0) {
      await admin.database().ref().update(updates);
      console.log(`Cleaned up section conversations for removed band member ${memberId} in band ${bandId}`);
    }

    return null;
  } catch (error) {
    console.error('Error in onBandMemberRemoved trigger:', error);
    return null;
  }
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
  const { soundType, customToken, broadcastToAll } = request.data || {};

  if (!soundType) {
    throw new HttpsError('invalid-argument', 'soundType is required.');
  }

  const soundConfigs = {
    gig_rquest: {
      channelId: 'gig_request_channel',
      androidSound: 'gig_rquest',
      apnsSound: 'gig_rquest.wav',
      title: '🎸 New Gig Request',
      body: 'Test Push: Bassist needed for Summer Fest in Gothenburg!',
    },
    gig_rquest_response: {
      channelId: 'gig_response_channel',
      androidSound: 'gig_rquest_response',
      apnsSound: 'gig_rquest_response.wav',
      title: '📬 Gig Request Response',
      body: 'Test Push: A musician applied for your gig request!',
    },
    reminder_rsvp: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '⏰ RSVP Reminder',
      body: 'Test Push: Rehearsal tomorrow at 18:00. Please confirm your attendance!',
    },
    reminder_24h: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '⏰ 24h RSVP Reminder',
      body: 'Test Push: Rehearsal in 24 hours! Please confirm your attendance.',
    },
    reminder_48h: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '⏰ 48h RSVP Reminder',
      body: 'Test Push: Rehearsal in 48 hours! Please confirm if you can make it.',
    },
    reminder_72h: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '⏰ 72h RSVP Reminder',
      body: 'Test Push: Upcoming gig in 72 hours! Please let the band know if you can make it.',
    },
    reminder_final: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '🚨 Final RSVP Reminder',
      body: 'Test Push: Final reminder! RSVP attendance before line-up locks!',
    },
    reminder_last: {
      channelId: 'rsvp_reminder_channel',
      androidSound: 'reminder_rsvp',
      apnsSound: 'reminder_rsvp.wav',
      title: '🚨 Final RSVP Reminder',
      body: 'Test Push: Final reminder! RSVP attendance before line-up locks!',
    },
    finalized_gig: {
      channelId: 'finalized_gig_channel',
      androidSound: 'finalized_gig',
      apnsSound: 'finalized_gig.wav',
      title: '🎉 Gig Finalized!',
      body: 'Test Push: You have been confirmed for the tour gig!',
    },
  };

  const config = soundConfigs[soundType];
  if (!config) {
    throw new HttpsError('invalid-argument', `Invalid soundType. Must be one of: ${Object.keys(soundConfigs).join(', ')}`);
  }

  // If broadcastToAll is requested, deliver to all registered push tokens in RTDB
  if (broadcastToAll === true) {
    const usersSnap = await admin.database().ref('/users').once('value');
    const users = usersSnap.val() || {};
    const recipientTokens = [];
    const seenTokens = new Set();

    for (const [uid, u] of Object.entries(users)) {
      if (!u || typeof u !== 'object') continue;
      const candidates = [
        u.info?.PushToken,
        u.PushToken,
        u.info?.pushToken,
        u.pushToken,
        u.info?.fcmToken,
        u.fcmToken,
      ];
      for (const t of candidates) {
        if (t && typeof t === 'string' && t.trim().length > 15 && !seenTokens.has(t.trim())) {
          seenTokens.add(t.trim());
          recipientTokens.push({ uid, token: t.trim() });
          break;
        }
      }
    }

    if (recipientTokens.length === 0) {
      return {
        success: false,
        error: 'No registered push tokens found in database across all users.',
      };
    }

    const messages = recipientTokens.map(r => ({
      token: r.token,
      notification: {
        title: config.title,
        body: config.body,
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        type: 'sound_test',
        soundType: soundType,
        timestamp: Date.now().toString(),
      },
      android: {
        notification: {
          sound: config.androidSound,
          channelId: config.channelId,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: config.apnsSound,
          },
        },
      },
    }));

    try {
      const response = await admin.messaging().sendEach(messages);
      console.log(`Broadcasted test push ${soundType}: ${response.successCount} succeeded, ${response.failureCount} failed.`);
      return {
        success: true,
        broadcast: true,
        total: messages.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
        soundType,
        channelId: config.channelId,
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
  let token = (typeof customToken === 'string' && customToken.trim().length > 10) ? customToken.trim() : null;
  if (!token && callerId) {
    const tokenSnap = await admin.database().ref(`/users/${callerId}/info/PushToken`).once('value');
    token = tokenSnap.val();
  }

  if (!token || typeof token !== 'string' || !token.trim() || token.trim().length < 15) {
    return {
      success: false,
      error: 'No valid device push token provided. Please run on a mobile device or paste a valid FCM token.',
    };
  }

  const message = {
    token: token.trim(),
    notification: {
      title: config.title,
      body: config.body,
    },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      type: 'sound_test',
      soundType: soundType,
      timestamp: Date.now().toString(),
    },
    android: {
      notification: {
        sound: config.androidSound,
        channelId: config.channelId,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: config.apnsSound,
        },
      },
    },
  };

  try {
    const messageId = await admin.messaging().send(message);
    return {
      success: true,
      broadcast: false,
      messageId,
      soundType,
      channelId: config.channelId,
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
    const senderName = msgData.senderName || msgData.SenderName || 'Musician';
    const text = msgData.text || msgData.Text || '';

    try {
      // 1. Fetch band name and members
      const bandRef = admin.database().ref(`/Bands/${bandId}`);
      const bandSnap = await bandRef.once('value');
      const bandVal = bandSnap.val() || {};
      const bandName = bandVal.Name || bandVal.name || bandId;

      let memberIds = [];
      if (bandVal.Members_band) {
        memberIds = Object.keys(bandVal.Members_band);
      } else if (bandVal.Members) {
        memberIds = Object.keys(bandVal.Members);
      }

      // Also check /bandconversations/{bandId}/members if band node didn't have members
      if (memberIds.length === 0) {
        const convMembersSnap = await admin.database().ref(`/bandconversations/${bandId}/members`).once('value');
        if (convMembersSnap.exists() && convMembersSnap.val()) {
          memberIds = Object.keys(convMembersSnap.val());
        }
      }

      const recipients = memberIds.filter(uid => uid && uid !== senderId);
      if (recipients.length === 0) return null;

      // 2. Record persistent notifications in Notification Center
      await recordUserNotificationsBatch(recipients, (uid) => ({
        id: `notif_br_${bandId}_${messageId}_${uid}`,
        type: 'band_room_message',
        category: 'messages',
        title: `🎵 ${bandName}`,
        body: `${senderName}: ${text.length > 100 ? `${text.substring(0, 97)}...` : text}`,
        createdAt: Date.now(),
        data: {
          bandId: bandId,
          messageId: messageId,
          senderId: senderId || '',
          type: 'band_room_message',
        },
      }));

      return null;
    } catch (err) {
      console.error('Error in onBandRoomMessageCreated trigger:', err);
      return null;
    }
  });

/**
 * Marks a single notification as read in the caller's /userNotifications/{callerUid}/{notificationId} feed.
 */
exports.markNotificationRead = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const notificationId = request.data?.notificationId;
  if (!notificationId || typeof notificationId !== 'string' || notificationId.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'notificationId is required.');
  }

  const notifRef = admin.database().ref(`/userNotifications/${callerUid}/${notificationId.trim()}`);
  const notifSnap = await notifRef.once('value');
  if (!notifSnap.exists()) {
    throw new HttpsError('not-found', 'Notification not found.');
  }

  await notifRef.update({
    isRead: true,
    readAt: Date.now(),
  });

  return { success: true };
});

/**
 * Marks all unread notifications as read in the caller's /userNotifications/{callerUid} feed.
 */
exports.markAllNotificationsRead = onCall({ region: 'europe-west1' }, async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const feedRef = admin.database().ref(`/userNotifications/${callerUid}`);
  const feedSnap = await feedRef.once('value');

  if (!feedSnap.exists() || !feedSnap.val()) {
    return { success: true, updatedCount: 0 };
  }

  const notifs = feedSnap.val();
  const updates = {};
  const now = Date.now();
  let updatedCount = 0;

  Object.keys(notifs).forEach((nId) => {
    const n = notifs[nId];
    if (n && !n.isRead) {
      updates[`/userNotifications/${callerUid}/${nId}/isRead`] = true;
      updates[`/userNotifications/${callerUid}/${nId}/readAt`] = now;
      updatedCount++;
    }
  });

  if (updatedCount > 0) {
    await admin.database().ref().update(updates);
  }

  return { success: true, updatedCount };
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

  const db = admin.database();

  try {
    // 1. Process band memberships & leadership transfer
    const userBandsSnap = await db.ref(`/users/${callerUid}/Bands`).once('value');
    if (userBandsSnap.exists() && userBandsSnap.val()) {
      const userBands = userBandsSnap.val();
      const bandIds = Object.keys(userBands);

      for (const bandId of bandIds) {
        const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');
        if (!bandSnap.exists()) continue;

        const bandData = bandSnap.val() || {};
        const members = bandData.Members_band || {};
        const callerMember = members[callerUid];

        if (callerMember) {
          const userRole = (callerMember.Role || callerMember.role || '').toLowerCase();
          const otherMemberIds = Object.keys(members).filter((id) => id !== callerUid);

          if (userRole === 'leader') {
            if (otherMemberIds.length === 0) {
              // Sole member / leader: Delete orphaned band completely
              await db.ref(`/Bands/${bandId}`).remove();
              await db.ref(`/bandconversations/${bandId}`).remove();
              await db.ref(`/bandSectionConversations/${bandId}`).remove();
            } else {
              // Auto-transfer leadership to an Admin, or next available member
              let successorId = otherMemberIds.find((id) => {
                const r = (members[id]?.Role || members[id]?.role || '').toLowerCase();
                return r === 'admin';
              });
              if (!successorId) {
                successorId = otherMemberIds[0];
              }

              // Promote successor to Leader
              await db.ref(`/Bands/${bandId}/Members_band/${successorId}/Role`).set('Leader');
              // Remove deleting user from band
              await db.ref(`/Bands/${bandId}/Members_band/${callerUid}`).remove();
              await db.ref(`/bandconversations/${bandId}/members/${callerUid}`).remove();

              // Send system notification to new leader
              const bandName = bandData.Name || bandData.name || bandId;
              await recordUserNotification(successorId, {
                type: 'band_leadership_promoted',
                category: 'events',
                title: '👑 You are now the Band Leader',
                body: `You have been promoted to Leader of ${bandName}.`,
                data: { bandId: bandId },
              });
            }
          } else {
            // Normal member: remove from band members
            await db.ref(`/Bands/${bandId}/Members_band/${callerUid}`).remove();
            await db.ref(`/bandconversations/${bandId}/members/${callerUid}`).remove();
          }
        }
      }
    }

    // 2. Clean up user's sub-requests
    const subRequestsSnap = await db.ref('/SubRequests').once('value');
    if (subRequestsSnap.exists() && subRequestsSnap.val()) {
      const allSubRequests = subRequestsSnap.val();
      const subUpdates = {};
      Object.keys(allSubRequests).forEach((subId) => {
        const item = allSubRequests[subId];
        if (item && (item.CreatorUserId === callerUid || item.UserId === callerUid || item.creatorUserId === callerUid || item.userId === callerUid)) {
          subUpdates[`/SubRequests/${subId}`] = null;
          subUpdates[`/subRequestAudience/${subId}`] = null;
        }
      });
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

    // 4. Clean up user-specific nodes
    const rootUpdates = {};
    rootUpdates[`/users/${callerUid}`] = null;
    rootUpdates[`/userNotifications/${callerUid}`] = null;
    rootUpdates[`/userSubRequestFeed/${callerUid}`] = null;
    rootUpdates[`/creatorSubRequestGroups/${callerUid}`] = null;
    rootUpdates[`/userConversations/${callerUid}`] = null;
    await db.ref().update(rootUpdates);

    // 5. Delete Firebase Authentication user record
    try {
      await admin.auth().deleteUser(callerUid);
    } catch (authErr) {
      console.warn(`Auth user delete notice for ${callerUid}:`, authErr.message);
    }

    return { success: true };
  } catch (err) {
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
      throw new HttpsError('not-found', 'Band not found.');
    }

    const bandData = bandSnap.val() || {};
    const members = bandData.Members_band || {};
    const callerMember = members[callerUid];

    if (!callerMember) {
      throw new HttpsError('permission-denied', 'You are not a member of this band.');
    }

    const callerRole = (callerMember.Role || callerMember.role || '').toLowerCase();
    if (callerRole !== 'leader') {
      throw new HttpsError('permission-denied', 'Only the band leader can delete this band.');
    }

    const memberIds = Object.keys(members);
    const updates = {};

    // 1. Remove band from each member's user profile
    for (const memberId of memberIds) {
      updates[`/users/${memberId}/Bands/${trimmedBandId}`] = null;
    }

    // 2. Remove band conversations & section conversations
    updates[`/bandconversations/${trimmedBandId}`] = null;
    updates[`/bandSectionConversations/${trimmedBandId}`] = null;

    // 3. Remove the band itself
    updates[`/Bands/${trimmedBandId}`] = null;

    await db.ref().update(updates);

    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error(`Error deleting band ${trimmedBandId} by ${callerUid}:`, err);
    throw new HttpsError('internal', `Failed to delete band: ${err.message}`);
  }
});
