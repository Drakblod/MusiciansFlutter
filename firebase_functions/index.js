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

/**
 * HTTPS Triggered function to compile app usage metrics for investors.
 */
exports.getAppMetrics = functions.https.onRequest(async (req, res) => {
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

