const functions = require('firebase-functions');
const admin = require('firebase-admin');
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
      const tokens = [];

      // 2. Fetch the FCM push token for each member in parallel (excluding creator)
      const tokenPromises = memberIds
        .filter(userId => userId !== creatorId)
        .map(async (userId) => {
          const tokenSnapshot = await admin.database().ref(`/users/${userId}/info/PushToken`).once('value');
          const token = tokenSnapshot.val();
          if (token && token.trim().length > 0) {
            tokens.push(token);
          }
        });

      await Promise.all(tokenPromises);

      if (tokens.length === 0) {
        console.log('No registered push tokens found for other band members.');
        return null;
      }

      // 3. Format Date/Time for display in the notification body
      const startLocal = eventData.startDateTime
        ? new Date(eventData.startDateTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        : 'TBD';

      // 4. Construct push notification payload
      const payload = {
        notification: {
          title: `🎼 New Event: ${eventData.title}`,
          body: `New ${eventData.eventType.toLowerCase()} at ${eventData.location || 'TBD'} starting at ${startLocal}. Please RSVP!`,
          sound: 'default',
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          bandId: bandId,
          eventId: eventId,
          type: 'event_invite',
        },
      };

      // 5. Dispatch notification to all tokens
      const response = await admin.messaging().sendToDevice(tokens, payload);
      console.log(`Successfully sent event push notifications: ${response.successCount} succeeded, ${response.failureCount} failed.`);
      
      // Clean up invalid/stale tokens
      response.results.forEach((result, index) => {
        const error = result.error;
        if (error) {
          console.error('Failure sending notification to token:', tokens[index], error);
          if (error.code === 'messaging/invalid-registration-token' ||
              error.code === 'messaging/registration-token-not-registered') {
            // Remove bad token from database
            const userId = memberIds.filter(userId => userId !== creatorId)[index];
            if (userId) {
              admin.database().ref(`/users/${userId}/info/PushToken`).remove();
              console.log(`Removed invalid token for user ${userId}`);
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
