const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { onValueCreated } = require('firebase-functions/v2/database');
admin.initializeApp();

/**
 * Triggered when a new event is created under /Bands/{bandId}/Events/{eventId}.
 * Sends a push notification to all band members except the event creator.
 */
exports.onBandEventCreated = functions.database
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
      const recipients = []; // Array of { userId, token }

      // 2. Fetch the FCM push token for each member in parallel (excluding creator)
      const tokenPromises = memberIds
        .filter(userId => userId !== creatorId)
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

      // 3. Format Date/Time for display in the notification body
      const startLocal = eventData.startDateTime
        ? new Date(eventData.startDateTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        : 'TBD';

      // 4. Construct push notification messages for each token using FCM v1
      const messages = recipients.map(r => ({
        token: r.token,
        notification: {
          title: `🎼 New Event: ${eventData.title}`,
          body: `New ${eventData.eventType.toLowerCase()} at ${eventData.location || 'TBD'} starting at ${startLocal}. Please RSVP!`,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          bandId: bandId,
          eventId: eventId,
          type: 'event_invite',
        },
        android: {
          notification: {
            sound: 'guitarsound',
            channelId: 'event_notifications',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'guitarsound.caf',
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
  region: 'europe-west1'
}, async (event) => {
  const subRequestData = event.data.val();
  if (!subRequestData) return null;

  const subRequestId = event.params.subRequestId;
  const voicePart = subRequestData.VoicePart;
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

    const recipients = [];

    // 2. Identify target recipients and their tokens
    Object.keys(users).forEach((userId) => {
      // Exclude creator
      if (userId === creatorUserId) return;

      const userInfo = users[userId].info;
      if (!userInfo) return;

      const token = userInfo.PushToken;
      if (!token || token.trim().length === 0) return;

      let shouldNotify = false;
      if (targetUserIds && Array.isArray(targetUserIds) && targetUserIds.length > 0) {
        // Targeted mode: only selected user IDs
        shouldNotify = targetUserIds.includes(userId);
      } else {
        // Default mode: matches the requested instrument/voice part
        const userType = userInfo.UserType || userInfo.userType;
        const instruments = userInfo.Instruments || userInfo.instruments || [];
        
        const hasMatchingInstrument = 
          (userType && userType.toLowerCase() === voicePart.toLowerCase()) ||
          instruments.some(i => i.toLowerCase() === voicePart.toLowerCase());
          
        shouldNotify = hasMatchingInstrument;
      }

      if (shouldNotify) {
        recipients.push({ userId, token });
      }
    });

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
          sound: 'default',
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
