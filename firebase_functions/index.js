const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { onValueCreated, onValueWritten } = require('firebase-functions/v2/database');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const crypto = require('crypto');
if (!admin.apps.length) {
  admin.initializeApp();
}

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
exports.onEventResponseChanged = functions.database
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
  ref: '/Collabs/Applications/{sessionId}/{applicantId}'
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
        }
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
          }
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
  const role = roleSnap.val();
  if (role !== 'Leader' && role !== 'Admin') {
    throw new HttpsError('permission-denied', 'Only Leader or Admin members can trigger event reminders.');
  }

  const eventSnap = await admin.database().ref(`/Bands/${bandId}/Events/${eventId}`).once('value');
  if (!eventSnap.exists()) {
    throw new HttpsError('not-found', `Event ${eventId} not found.`);
  }
  const eventData = eventSnap.val();
  if (eventData.isLocked === true) {
    throw new HttpsError('failed-precondition', 'Cannot send reminder for a locked event.');
  }
  if (eventData.startDateTime && new Date(eventData.startDateTime).getTime() <= Date.now()) {
    throw new HttpsError('failed-precondition', 'Cannot send reminder for an event that has already started.');
  }
  // Load authoritative audit record early to check completed state before token checks
  const auditRef = admin.database().ref(`/eventReminderAudit/${bandId}/${eventId}/${reminderType}`);
  const auditSnap = await auditRef.once('value');
  if (auditSnap.exists()) {
    const existingAudit = auditSnap.val();
    if (existingAudit && existingAudit.status === 'completed') {
      const sentCount = existingAudit.successCount !== undefined
        ? existingAudit.successCount
        : (existingAudit.recipients ? Object.values(existingAudit.recipients).filter(r => r && r.status === 'sent').length : 0);
      return {
        status: 'already_sent',
        successCount: sentCount,
        failureCount: existingAudit.failureCount || 0,
        attemptedCount: existingAudit.attemptedCount || sentCount,
      };
    }
  }

  const membersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');
  const members = membersSnap.val() || {};
  const memberIds = Object.keys(members);

  const responses = eventData.Responses || {};
  const realResponseStatuses = ['YES', 'NO', 'UNCERTAIN', 'attending', 'declined', 'maybe'];

  const nonResponders = memberIds.filter((uid) => {
    const resp = responses[uid];
    if (!resp) return true;
    const status = (typeof resp === 'string' ? resp : resp.status || resp.Status || '').toUpperCase();
    if (!status || status === 'PENDING') return true;
    return !realResponseStatuses.map(s => s.toUpperCase()).includes(status);
  });

  if (nonResponders.length === 0) {
    return { status: 'no_non_responders', successCount: 0, attemptedCount: 0, failureCount: 0 };
  }

  let currentAudit = null;
  const nowIso = new Date().toISOString();
  const nowMs = Date.now();

  const txResult = await auditRef.transaction((current) => {
    if (current) {
      if (current.status === 'completed') {
        return current;
      }
      if (current.status === 'sending') {
        const reqAtMs = current.requestedAt ? new Date(current.requestedAt).getTime() : 0;
        if (nowMs - reqAtMs < 5 * 60 * 1000) {
          return;
        }
      }
    }
    return {
      status: 'sending',
      requestedBy: callerUid,
      requestedAt: nowIso,
      recipients: (current && current.recipients) ? current.recipients : {},
      attemptedCount: current ? (current.attemptedCount || 0) : 0,
      successCount: current ? (current.successCount || 0) : 0,
      failureCount: current ? (current.failureCount || 0) : 0,
    };
  });

  if (!txResult.committed) {
    const snapVal = txResult.snapshot.val();
    if (snapVal && snapVal.status === 'completed') {
      return { status: 'already_sent', successCount: snapVal.successCount || 0, attemptedCount: snapVal.attemptedCount || 0, failureCount: 0 };
    }
    throw new HttpsError('already-exists', 'A reminder request is currently in progress for this event.');
  }

  currentAudit = txResult.snapshot.val() || {};
  const existingRecipients = currentAudit.recipients || {};

  const eligibleRecipients = nonResponders.filter(uid => existingRecipients[uid]?.status !== 'sent');

  if (eligibleRecipients.length === 0) {
    return { status: 'already_sent', successCount: currentAudit.successCount || 0, attemptedCount: currentAudit.attemptedCount || 0, failureCount: 0 };
  }

  const recipientsWithTokens = [];
  const tokenPromises = eligibleRecipients.map(async (uid) => {
    const tokenSnap = await admin.database().ref(`/users/${uid}/info/PushToken`).once('value');
    const token = tokenSnap.val();
    if (token && typeof token === 'string' && token.trim().length > 0) {
      recipientsWithTokens.push({ userId: uid, token: token.trim() });
    }
  });

  await Promise.all(tokenPromises);

  if (recipientsWithTokens.length === 0) {
    await auditRef.update({
      status: 'failed',
      completedAt: new Date().toISOString(),
      failureReason: 'no_valid_tokens',
    });
    return { status: 'no_valid_tokens', successCount: 0, attemptedCount: 0, failureCount: eligibleRecipients.length };
  }

  const messages = recipientsWithTokens.map(r => ({
    token: r.token,
    notification: {
      title: `⏰ RSVP Reminder: ${eventData.title || 'Band Event'}`,
      body: `Please RSVP to the upcoming ${eventData.eventType || 'event'}! Let the band know if you can make it.`,
    },
    data: {
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
      bandId: bandId,
      eventId: eventId,
      type: 'event_reminder',
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

  let fcmResponse;
  if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.IS_EMULATOR_TEST === 'true') {
    // Emulator test transport: Safe mock responses without contacting external FCM
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

  const totalAttempted = (currentAudit.attemptedCount || 0) + recipientsWithTokens.length;
  const totalSuccess = (currentAudit.successCount || 0) + batchSuccess;
  const totalFailure = (currentAudit.failureCount || 0) + batchFailure;

  let finalStatus = 'completed';
  if (totalSuccess === 0 && totalFailure > 0) {
    finalStatus = 'failed';
  } else if (totalFailure > 0) {
    finalStatus = 'partial_success';
  }

  const auditUpdates = {
    ...recipientUpdates,
    status: finalStatus,
    attemptedCount: totalAttempted,
    successCount: totalSuccess,
    failureCount: totalFailure,
    completedAt: new Date().toISOString(),
  };

  await auditRef.update(auditUpdates);

  if (finalStatus === 'completed') {
    const legacyKeyMap = {
      '24h': 'sentReminder24h',
      '48h': 'sentReminder48h',
      '72h': 'sentReminder72h',
      'last': 'sentReminder84h',
    };
    const legacyKey = legacyKeyMap[reminderType];
    if (legacyKey) {
      await admin.database().ref(`/Bands/${bandId}/Events/${eventId}/${legacyKey}`).set(true);
    }
  }

  return {
    status: finalStatus,
    successCount: totalSuccess,
    failureCount: totalFailure,
    attemptedCount: totalAttempted,
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

  // Push notifications to all other current participants
  const otherParticipants = participantsList.filter(uid => uid !== senderUid);
  if (otherParticipants.length > 0) {
    try {
      const groupName = convVal.groupName || 'Section Chat';
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
  region: 'europe-west1'
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
