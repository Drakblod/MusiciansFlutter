# CLEAN-SCHEMA-PRIVACY-CUTOVER-01 inventory and empty-launch contract

Starting point: main, 93953e05cbf801a28cc8fb9b10691ba49ad040b5, version 2.79.3+252; clean working tree and empty staging verified.

This is local review work. No production access, reset, deletion, migration, backfill or deployment is authorized. The only Map exception is sanitized public band-profile navigation for unrelated users.

Latest verification evidence is in **Final reconciliation evidence (2026-11-06)** below. Earlier run totals and workspace snapshots are historical and are superseded by that section.

## Source inventory before edits

Every matching production source occurrence is listed below, including reads, writes, model fields, and backend reconciliation. Line numbers refer to the starting checkpoint. Server Admin SDK consumers are not client read grants.

| File and line | Method/export | Exact source path/field operation |
| --- | --- | --- |
| `lib/models/band_event.dart:345` | `module` | `final Map<String, ExternalInvitee> externalInvitees;` |
| `lib/models/band_event.dart:346` | `module` | `final Map<String, SubstituteAssignment> substituteAssignments;` |
| `lib/models/band_event.dart:384` | `module` | `this.externalInvitees = const {},` |
| `lib/models/band_event.dart:385` | `module` | `this.substituteAssignments = const {},` |
| `lib/models/band_event.dart:435` | `module` | `final externalInviteesRaw = json['externalInvitees'];` |
| `lib/models/band_event.dart:436` | `module` | `if (externalInviteesRaw is Map) {` |
| `lib/models/band_event.dart:437` | `module` | `externalInviteesRaw.forEach((k, v) {` |
| `lib/models/band_event.dart:448` | `module` | `final subAssignmentsRaw = json['substituteAssignments'];` |
| `lib/models/band_event.dart:476` | `module` | `final Map<String, Map<String, EventResponse>> parsedScheduleResponses = {};` |
| `lib/models/band_event.dart:477` | `module` | `final scheduleResponsesRaw = json['ScheduleResponses'] ?? json['scheduleResponses'];` |
| `lib/models/band_event.dart:487` | `module` | `parsedScheduleResponses[scheduleId.toString()] = userMap;` |
| `lib/models/band_event.dart:538` | `module` | `externalInvitees: parsedExternalInvitees,` |
| `lib/models/band_event.dart:539` | `module` | `substituteAssignments: parsedSubstituteAssignments,` |
| `lib/models/band_event.dart:552` | `module` | `scheduleResponses: parsedScheduleResponses,` |
| `lib/models/band_event.dart:569` | `module` | `final Map<String, dynamic> externalInviteesMap = {};` |
| `lib/models/band_event.dart:570` | `module` | `externalInvitees.forEach((k, v) {` |
| `lib/models/band_event.dart:571` | `module` | `externalInviteesMap[k] = v.toJson();` |
| `lib/models/band_event.dart:575` | `module` | `substituteAssignments.forEach((k, v) {` |
| `lib/models/band_event.dart:614` | `module` | `'externalInvitees': externalInviteesMap,` |
| `lib/models/band_event.dart:615` | `module` | `if (subAssignmentsMap.isNotEmpty) 'substituteAssignments': subAssignmentsMap,` |
| `lib/models/band_event.dart:617` | `module` | `if (scheduleResponsesMap.isNotEmpty) 'ScheduleResponses': scheduleResponsesMap,` |
| `lib/services/firebase_service.dart:200` | `updateUserProfileFields` | `updates['users/$trimmedUid/info/$key'] = value;` |
| `lib/services/firebase_service.dart:202` | `updateUserProfileFields` | `updates['users/$trimmedUid/$key'] = value;` |
| `lib/services/firebase_service.dart:288` | `getUserProfileAsync` | `final snapshot = await _dbRef('users/$targetId').get();` |
| `lib/services/firebase_service.dart:375` | `isFavoriteAsync` | `'users/$selfId/Favorites/$targetUserId',` |
| `lib/services/firebase_service.dart:384` | `toggleFavoriteAsync` | `await _dbRef('users/$selfId/Favorites/$targetUserId').set(true);` |
| `lib/services/firebase_service.dart:386` | `toggleFavoriteAsync` | `await _dbRef('users/$selfId/Favorites/$targetUserId').remove();` |
| `lib/services/firebase_service.dart:393` | `getFavoriteUserIdsAsync` | `final snapshot = await _dbRef('users/$selfId/Favorites').get();` |
| `lib/services/firebase_service.dart:423` | `getBandInfoAsync` | `_dbRef('Bands/$bandId/$field').get()));` |
| `lib/services/firebase_service.dart:504` | `getBandMembersAsync` | `final snapshot = await _dbRef('Bands/$bandId/Members_band').get();` |
| `lib/services/firebase_service.dart:532` | `saveSubRequestAsync` | `final newRef = _dbRef('SubRequests').push();` |
| `lib/services/firebase_service.dart:578` | `saveSubRequestAsync` | `/// Writes exclusively to SubRequests/{generatedId} with NotificationMode: 'map_pin'.` |
| `lib/services/firebase_service.dart:579` | `saveSubRequestAsync` | `/// Does NOT write to BandEvents/PublishedSubRequests or users/{uid}/SubRequests,` |
| `lib/services/firebase_service.dart:734` | `getAllSubRequestsAsync` | `final pubSnap = await _dbRef('publicSubRequests').get();` |
| `lib/services/firebase_service.dart:825` | `getSubRequestFeedStream` | `publicSub = _dbRef('publicSubRequests').onValue.listen((event) {` |
| `lib/services/firebase_service.dart:1109` | `saveSubRequestsBatchAsync` | `// 2. Direct write to user's personal /users/$currentUserId/SubRequests/$key` |
| `lib/services/firebase_service.dart:1112` | `saveSubRequestsBatchAsync` | `await _dbRef('users/$currentUserId/SubRequests/$key').set(json);` |
| `lib/services/firebase_service.dart:1116` | `saveSubRequestsBatchAsync` | `debugPrint('[FirebaseService] Error saving users/$currentUserId/SubRequests/$key: $e');` |
| `lib/services/firebase_service.dart:1120` | `saveSubRequestsBatchAsync` | `// 3. Direct write to canonical /SubRequests/$key (best-effort)` |
| `lib/services/firebase_service.dart:1122` | `saveSubRequestsBatchAsync` | `await _dbRef('SubRequests/$key').set(json);` |
| `lib/services/firebase_service.dart:1124` | `saveSubRequestsBatchAsync` | `debugPrint('[FirebaseService] Error saving SubRequests/$key: $e');` |
| `lib/services/firebase_service.dart:1134` | `saveSubRequestsBatchAsync` | `'Bands/${req.bandId}/Events/${req.eventId}/externalInvitees/$targetId',` |
| `lib/services/firebase_service.dart:1270` | `getUserAppliedSubRequestIdsAsync` | `final snap = await _dbRef('users/$uid/AppliedSubRequests').get();` |
| `lib/services/firebase_service.dart:1306` | `resolveAppliedSubRequestIdsForCardAsync` | `// 2. For any remaining IDs, check the user's own authorized leaf SubRequests/$id/Responses/$uid` |
| `lib/services/firebase_service.dart:1310` | `resolveAppliedSubRequestIdsForCardAsync` | `final leafSnap = await _dbRef('SubRequests/$id/Responses/$uid').get();` |
| `lib/services/firebase_service.dart:1320` | `resolveAppliedSubRequestIdsForCardAsync` | `// 3. For any still-remaining IDs, check BandEvents/SubRequestResponses/$id/$uid` |
| `lib/services/firebase_service.dart:1324` | `resolveAppliedSubRequestIdsForCardAsync` | `final legacySnap = await _dbRef('BandEvents/SubRequestResponses/$id/$uid').get();` |
| `lib/services/firebase_service.dart:1343` | `isBandLeaderOrAdminAsync` | `final path = 'Bands/$bandId/Members_band/$uid';` |
| `lib/services/firebase_service.dart:1388` | `addResponseToSubRequestAsync` | `await _dbRef('users/$cleanUserId/AppliedSubRequests/$cleanSubId').set(true);` |
| `lib/services/firebase_service.dart:1390` | `addResponseToSubRequestAsync` | `debugPrint('[FirebaseService] Write users/$cleanUserId/AppliedSubRequests notice: $e');` |
| `lib/services/firebase_service.dart:1394` | `addResponseToSubRequestAsync` | `await _dbRef('SubRequests/$cleanSubId/Responses/$cleanUserId').set(true);` |
| `lib/services/firebase_service.dart:1400` | `addResponseToSubRequestAsync` | `await _dbRef('BandEvents/SubRequestResponses/$cleanSubId/$cleanUserId').set({` |
| `lib/services/firebase_service.dart:1405` | `addResponseToSubRequestAsync` | `debugPrint('[FirebaseService] Write BandEvents/SubRequestResponses notice: $e');` |
| `lib/services/firebase_service.dart:1429` | `addResponseToSubRequestAsync` | `await _dbRef('users/$creatorId/SubRequests/$cleanSubId/Responses/$cleanUserId').set(true);` |
| `lib/services/firebase_service.dart:1457` | `addResponseToSubRequestAsync` | `'Bands/$bandId/Events/$eventId/externalInvitees/$cleanUserId',` |
| `lib/services/firebase_service.dart:1460` | `addResponseToSubRequestAsync` | `'Bands/$bandId/Events/$eventId/updatedAt',` |
| `lib/services/firebase_service.dart:1510` | `addResponseToSubRequestAsync` | `await _dbRef('BandEvents/Notifications/$creatorId/$notifId').set(notifMap);` |
| `lib/services/firebase_service.dart:1512` | `addResponseToSubRequestAsync` | `debugPrint('[FirebaseService] Write BandEvents/Notifications error: $e');` |
| `lib/services/firebase_service.dart:1527` | `getSubRequestAsync` | `final snapshot = await _dbRef('SubRequests/$subRequestId').get();` |
| `lib/services/firebase_service.dart:1539` | `getSubRequestAsync` | `final pubSnap = await _dbRef('publicSubRequests/$subRequestId').get();` |
| `lib/services/firebase_service.dart:1611` | `getSubRequestResponsesAsync` | `final snapshot = await _dbRef('SubRequests/$subRequestId/Responses').get();` |
| `lib/services/firebase_service.dart:1618` | `getSubRequestResponsesAsync` | `debugPrint("[FirebaseService] Notice: could not read root SubRequests/$subRequestId/Responses: $e");` |
| `lib/services/firebase_service.dart:1621` | `getSubRequestResponsesAsync` | `// 2. BandEvents / SubRequestResponses` |
| `lib/services/firebase_service.dart:1623` | `getSubRequestResponsesAsync` | `final snap = await _dbRef('BandEvents/SubRequestResponses/$subRequestId').get();` |
| `lib/services/firebase_service.dart:1634` | `getSubRequestResponsesAsync` | `final userSnap = await _dbRef('users/$currentUserId/SubRequests/$subRequestId/Responses').get();` |
| `lib/services/firebase_service.dart:1650` | `getSubRequestResponsesAsync` | `final invSnap = await _dbRef('Bands/${sub.bandId}/Events/${sub.eventId}/externalInvitees').get();` |
| `lib/services/firebase_service.dart:1777` | `subscribeToConversationMetadata` | `final snap = await _dbRef('BandEvents/Agreements/$conversationId').get();` |
| `lib/services/firebase_service.dart:1786` | `subscribeToConversationMetadata` | `final snap = await _dbRef('users/$currentUserId/Agreements/$conversationId').get();` |
| `lib/services/firebase_service.dart:1998` | `subscribeToUserNotifications` | `sub2 = _dbRef('BandEvents/Notifications/$uid').onValue.listen((event) {` |
| `lib/services/firebase_service.dart:2012` | `subscribeToUserNotifications` | `debugPrint('[FirebaseService] BandEvents/Notifications stream notice: $err');` |
| `lib/services/firebase_service.dart:2043` | `markNotificationReadAsync` | `await _dbRef('BandEvents/Notifications/$uid/$notificationId').update({` |
| `lib/services/firebase_service.dart:2085` | `markAllNotificationsReadAsync` | `final bandSnap = await _dbRef('BandEvents/Notifications/$uid').get();` |
| `lib/services/firebase_service.dart:2089` | `markAllNotificationsReadAsync` | `updates['BandEvents/Notifications/$uid/$k/isRead'] = true;` |
| `lib/services/firebase_service.dart:2090` | `markAllNotificationsReadAsync` | `updates['BandEvents/Notifications/$uid/$k/readAt'] = DateTime.now().millisecondsSinceEpoch;` |
| `lib/services/firebase_service.dart:2110` | `getActiveConversationsAsync` | `// Also pre-fetch user's agreements and BandEvents agreements map` |
| `lib/services/firebase_service.dart:2113` | `getActiveConversationsAsync` | `final userAgreementsSnap = await _dbRef('users/$selfId/Agreements').get();` |
| `lib/services/firebase_service.dart:2122` | `getActiveConversationsAsync` | `final bandAgreementsSnap = await _dbRef('BandEvents/Agreements').get();` |
| `lib/services/firebase_service.dart:2321` | `addBandEventAsync` | `final ref = _dbRef('BandEvents/$bandId').push();` |
| `lib/services/firebase_service.dart:2343` | `getBandEventsAsync` | `Future<List<CalendarEvent>> getBandEventsAsync(String bandId) async {` |
| `lib/services/firebase_service.dart:2545` | `savePushTokenAsync` | `await _dbRef('users/$userId/info/PushToken').set(token);` |
| `lib/services/firebase_service.dart:2815` | `reportListingAsync` | `'externalInvitees',` |
| `lib/services/firebase_service.dart:2816` | `reportListingAsync` | `'substituteAssignments',` |
| `lib/services/firebase_service.dart:2828` | `reportListingAsync` | `return _dbRef('Bands/$bandId/Events').push().key ??` |
| `lib/services/firebase_service.dart:2860` | `createBandEventAsync` | `externalInvitees: event.externalInvitees,` |
| `lib/services/firebase_service.dart:2861` | `createBandEventAsync` | `substituteAssignments: event.substituteAssignments,` |
| `lib/services/firebase_service.dart:2909` | `saveBandEventAsync` | `'externalInvitees': event.externalInvitees.map((k, v) => MapEntry(k, v.toJson())),` |
| `lib/services/firebase_service.dart:2910` | `saveBandEventAsync` | `'substituteAssignments': event.substituteAssignments.map((k, v) => MapEntry(k, v.toJson())),` |
| `lib/services/firebase_service.dart:2923` | `getBandEventsListAsync` | `Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {` |
| `lib/services/firebase_service.dart:2948` | `getBandEventsListAsync` | `'Responses','ScheduleResponses','externalInvitees','excludedMemberIds',` |
| `lib/services/firebase_service.dart:2959` | `canManageBandEventAsync` | `final snapshot = await _dbRef('Bands/$bandId/Members_band/$uid').get();` |
| `lib/services/firebase_service.dart:2973` | `getManagerBandEventsListAsync` | `Future<List<BandEvent>> getManagerBandEventsListAsync(String bandId) async {` |
| `lib/services/firebase_service.dart:2992` | `_watchBandEvent` | `final member = await _dbRef('Bands/$bandId/Members_band/$uid').get();` |
| `lib/services/firebase_service.dart:3017` | `_watchBandEvent` | `authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){` |
| `lib/services/firebase_service.dart:3052` | `subscribeToManagerBandEvent` | `authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){` |
| `lib/services/firebase_service.dart:3084` | `subscribeToBandEvents` | `Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {` |
| `lib/services/firebase_service.dart:3107` | `subscribeToBandEvents` | `authoritySub=_dbRef('Bands/$bandId/Members_band/$uid').onValue.listen((event){` |
| `lib/services/firebase_service.dart:3138` | `getSubstituteAssignmentsAsync` | `final snap = await _dbRef('bandManagerEvents/$bandId/$eventId/substituteAssignments').get();` |
| `lib/services/firebase_service.dart:3162` | `updateEventResponseAsync` | `await _dbRef('Bands/$bandId/Events/$eventId/Responses/$userId').set({` |
| `lib/services/firebase_service.dart:3179` | `updateScheduleItemResponseAsync` | `'Bands/$bandId/Events/$eventId/ScheduleResponses/$scheduleItemId/$userId',` |
| `lib/services/firebase_service.dart:3249` | `postGigsNewsAsync` | `final ref = _dbRef('Bands/$bandId/GigsNews').push();` |
| `lib/services/firebase_service.dart:3259` | `subscribeToGigsNews` | `return _dbRef('Bands/$bandId/GigsNews').onValue.map((event) {` |
| `lib/services/firebase_service.dart:3281` | `deleteGigsNewsAsync` | `await _dbRef('Bands/$bandId/GigsNews/$postId').remove();` |
| `lib/services/firebase_service.dart:3289` | `getButtonClicksAsync` | `final snapshot = await _dbRef('users/$userId/metrics/buttonClicks').get();` |
| `lib/services/firebase_service.dart:3312` | `saveButtonClickAsync` | `await _dbRef('users/$userId/metrics/buttonClicks/$buttonId').set(count);` |
| `lib/services/firebase_service.dart:3375` | `getUserBandRoleAsync` | `'Bands/$bandId/Members_band/$userId/Role',` |
| `lib/services/firebase_service.dart:3767` | `createTemporaryEventRoomAsync` | `final ref = _dbRef('Bands/$bandId/eventRooms').push();` |
| `lib/services/firebase_service.dart:3802` | `subscribeToBandEventRooms` | `return _dbRef('Bands/$bandId/eventRooms').onValue.map((event) {` |
| `lib/services/firebase_service.dart:3824` | `addMemberToEventRoomAsync` | `await _dbRef('Bands/$bandId/eventRooms/$roomId/members/$userId').set(role);` |
| `lib/services/firebase_service.dart:3837` | `closeOrDeleteEventRoomAsync` | `await _dbRef('Bands/$bandId/eventRooms/$roomId').remove();` |
| `lib/services/firebase_service.dart:3839` | `closeOrDeleteEventRoomAsync` | `await _dbRef('Bands/$bandId/eventRooms/$roomId/isClosed').set(true);` |
| `lib/services/firebase_service.dart:3930` | `savePublicCalendarEventAsync` | `// 1. Save under user's node first (guaranteed permitted by users/$userId rules)` |
| `lib/services/firebase_service.dart:3934` | `savePublicCalendarEventAsync` | `await _dbRef('users/$uid/PublicEvents/$eventId').set(json);` |
| `lib/services/firebase_service.dart:3936` | `savePublicCalendarEventAsync` | `debugPrint('[FirebaseService] Could not save users/$uid/PublicEvents: $e');` |
| `lib/services/firebase_service.dart:3978` | `getPublicCalendarEventsAsync` | `final userSnap = await _dbRef('users/$uid/PublicEvents').get();` |
| `lib/services/firebase_service.dart:4006` | `deletePublicCalendarEventAsync` | `await _dbRef('users/$uid/PublicEvents/$eventId').remove();` |
| `lib/services/firebase_service.dart:4008` | `deletePublicCalendarEventAsync` | `debugPrint('[FirebaseService] Notice: could not remove users/$uid/PublicEvents/$eventId: $e');` |
| `lib/utils/band_membership_policy.dart:35` | `Function` | `final member = await read('Bands/$id/Members_band/$uid');` |
| `lib/utils/band_membership_policy.dart:39` | `Function` | `read('Bands/$id/Name'),` |
| `lib/utils/band_membership_policy.dart:40` | `Function` | `read('Bands/$id/isMock'),` |
| `lib/utils/band_membership_policy.dart:41` | `Function` | `read('Bands/$id/isDemo'),` |
| `lib/utils/secondary_skills_utils.dart:4` | `module` | `///   /users/{uid}/info/UserType     -> Primary Skill` |
| `lib/utils/secondary_skills_utils.dart:5` | `module` | `///   /users/{uid}/info/Instruments  -> [Primary Skill, ...Secondary Skills]` |
| `lib/views/band_room_chat_screen.dart:211` | `_initBand` | `.subscribeToBandEvents(bandId)` |
| `lib/views/browse_musicians_screen.dart:385` | `_openSkillsPicker` | `'Bands',` |
| `lib/views/calendar_screen.dart:42` | `_loadEvents` | `final list = await appState.firebaseService.getBandEventsAsync(_resolvedBandId!);` |
| `lib/views/create_event_page.dart:59` | `module` | `Map<String, ExternalInvitee> _externalInvitees = {};` |
| `lib/views/create_event_page.dart:87` | `module` | `_externalInvitees = Map<String, ExternalInvitee>.from(existing.externalInvitees);` |
| `lib/views/create_event_page.dart:159` | `_loadBandMembers` | `for (final uid in _externalInvitees.keys) {` |
| `lib/views/create_event_page.dart:715` | `_selectEndTime` | `currentExternalInvitees: _externalInvitees,` |
| `lib/views/create_event_page.dart:718` | `_selectEndTime` | `_externalInvitees[invitee.userId] = invitee;` |
| `lib/views/create_event_page.dart:733` | `_selectEndTime` | `final guestCount = _externalInvitees.length;` |
| `lib/views/create_event_page.dart:895` | `_selectEndTime` | `if (_externalInvitees.isEmpty)` |
| `lib/views/create_event_page.dart:914` | `_selectEndTime` | `..._externalInvitees.entries.map((entry) {` |
| `lib/views/create_event_page.dart:999` | `_selectEndTime` | `_externalInvitees.remove(uid);` |
| `lib/views/create_event_page.dart:1234` | `_selectEndTime` | `// Pre-process any new subs in _externalInvitees so subRequestId is linked immediately` |
| `lib/views/create_event_page.dart:1235` | `_selectEndTime` | `final Map<String, ExternalInvitee> updatedInvitees = Map.from(_externalInvitees);` |
| `lib/views/create_event_page.dart:1237` | `_selectEndTime` | `if (_externalInvitees.isNotEmpty) {` |
| `lib/views/create_event_page.dart:1240` | `_selectEndTime` | `for (final entry in _externalInvitees.entries) {` |
| `lib/views/create_event_page.dart:1331` | `_selectEndTime` | `externalInvitees: updatedInvitees,` |
| `lib/views/create_event_page.dart:1338` | `_selectEndTime` | `substituteAssignments: widget.existingEvent?.substituteAssignments ?? {},` |
| `lib/views/create_event_page.dart:1368` | `_selectEndTime` | `for (final entry in widget.existingEvent!.externalInvitees.entries) {` |
| `lib/views/create_event_page.dart:1369` | `_selectEndTime` | `if (!_externalInvitees.containsKey(entry.key)) {` |
| `lib/views/event_details_page.dart:247` | `_loadMembersAndProfiles` | `final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);` |
| `lib/views/event_details_page.dart:350` | `_loadMembersAndProfiles` | `} else if (event.externalInvitees.containsKey(currentUserId)) {` |
| `lib/views/event_details_page.dart:351` | `_loadMembersAndProfiles` | `mainStatus = event.externalInvitees[currentUserId]?.status;` |
| `lib/views/event_details_page.dart:352` | `_loadMembersAndProfiles` | `mainComment = event.externalInvitees[currentUserId]?.comment;` |
| `lib/views/event_details_page.dart:426` | `_saveRsvpForIndex` | `final isExternal = _event!.externalInvitees.containsKey(userId);` |
| `lib/views/event_details_page.dart:1533` | `_saveRsvpForIndex` | `.getManagerBandEventsListAsync(widget.bandId);` |
| `lib/views/event_results_page.dart:245` | `_loadData` | `final allEvents = await appState.firebaseService.getManagerBandEventsListAsync(widget.bandId);` |
| `lib/views/event_results_page.dart:285` | `_loadData` | `for (final k in _event!.externalInvitees.keys) {` |
| `lib/views/event_results_page.dart:288` | `_loadData` | `for (final sub in _event!.substituteAssignments.values) {` |
| `lib/views/event_results_page.dart:349` | `_loadData` | `for (final entry in event.substituteAssignments.entries) {` |
| `lib/views/event_results_page.dart:396` | `_loadData` | `for (final entry in event.externalInvitees.entries) {` |
| `lib/views/event_results_page.dart:478` | `_loadData` | `for (final entry in event.externalInvitees.entries) {` |
| `lib/views/find_sub_screen.dart:388` | `_loadDataAsync` | `final allBandEvents = await appState.firebaseService.getBandEventsListAsync(effectiveBandId);` |
| `lib/views/find_sub_screen.dart:391` | `_loadDataAsync` | `final hasChildEvents = allBandEvents.any((e) => e.parentEventId == currentId);` |
| `lib/views/find_sub_screen.dart:403` | `_loadDataAsync` | `final explicitChildren = allBandEvents` |
| `lib/views/find_sub_screen.dart:411` | `_loadDataAsync` | `relatedEvents = allBandEvents` |
| `lib/views/manage_events_screen.dart:146` | `_loadBandsAndEvents` | `final sub = appState.firebaseService.subscribeToBandEvents(bandId).listen((events) {` |
| `firebase_functions/band_membership_index.js:12` | `reconcileMembershipIndex` | `const ref = db.ref(`Bands/${bandId}/Members_band/${uid}`);` |
| `firebase_functions/band_membership_index.js:16` | `reconcileMembershipIndex` | `const name = (await db.ref(`Bands/${bandId}/Name`).get()).val();` |
| `firebase_functions/band_membership_index.js:23` | `reconcileMembershipIndex` | `[`users/${uid}/Bands/${bandId}`]: compatibility,` |
| `firebase_functions/band_membership_index.js:36` | `calculatePlan` | `malformed.push(`Bands/${bandId}/Members_band`);` |
| `firebase_functions/band_membership_index.js:45` | `calculatePlan` | `malformed.push(`Bands/${bandId}/Members_band/${uid}`);` |
| `firebase_functions/catalogue_projections.js:89` | `reconcile` | `const canonical=db.ref(`${user?'users':'Bands'}/${id}`),projection=db.ref(`${user?'publicUserProfiles':'publicBandProfiles'}/${id}`);` |
| `firebase_functions/event_mutations.js:65` | `fields` | `if(Object.hasOwn(input,'externalInvitees')){` |
| `firebase_functions/event_mutations.js:66` | `fields` | `if(!record(input.externalInvitees)\|\|Object.keys(input.externalInvitees).length>100)` |
| `firebase_functions/event_mutations.js:68` | `fields` | `const preserved=record(previous.externalInvitees)?previous.externalInvitees:{};` |
| `firebase_functions/event_mutations.js:72` | `fields` | `for(const [uid,invite] of Object.entries(input.externalInvitees)){` |
| `firebase_functions/event_mutations.js:81` | `fields` | `out.externalInvitees=next;` |
| `firebase_functions/event_mutations.js:91` | `mutate` | `const ref=db.ref(`Bands/${bandId}/Events/${eventId}`);` |
| `firebase_functions/event_mutations.js:95` | `mutate` | `const prior=(await ref.child(`externalInvitees/${uid}`).get()).val();` |
| `firebase_functions/event_mutations.js:103` | `mutate` | `await ref.child(`externalInvitees/${uid}`).update(update);` |
| `firebase_functions/event_mutations.js:133` | `mutate` | `if(prior.externalInvitees?.[target])continue;` |
| `firebase_functions/event_mutations.js:134` | `mutate` | `updates[`externalInvitees/${target}`]={userId:target,status:'pending',source:'manual',invitedAt:Date.now()};` |
| `firebase_functions/event_projection.js:139` | `getAuthorizedUserIdsForBandEvent` | `if (eventData.externalInvitees && typeof eventData.externalInvitees === 'object') {` |
| `firebase_functions/event_projection.js:140` | `getAuthorizedUserIdsForBandEvent` | `Object.entries(eventData.externalInvitees).forEach(([inviteeUid, inv]) => {` |
| `firebase_functions/event_projection.js:150` | `getAuthorizedUserIdsForBandEvent` | `if (eventData.substituteAssignments && typeof eventData.substituteAssignments === 'object') {` |
| `firebase_functions/event_projection.js:151` | `getAuthorizedUserIdsForBandEvent` | `Object.values(eventData.substituteAssignments).forEach((assign) => {` |
| `firebase_functions/event_read_models.js:104` | `verifiedAssignments` | `const raw=source?.substituteAssignments;` |
| `firebase_functions/event_read_models.js:122` | `project` | `const invitees=record(event?.externalInvitees)?event.externalInvitees:{};` |
| `firebase_functions/event_read_models.js:132` | `project` | `if(assignments.length)base.substituteAssignments=Object.fromEntries(assignments.map(a=>[a.slotId,a]));` |
| `firebase_functions/event_read_models.js:134` | `project` | `const schedule=scheduleResponseMap(event.ScheduleResponses??event.scheduleResponses);` |
| `firebase_functions/event_read_models.js:144` | `project` | `if(Object.keys(schedule).length)manager.ScheduleResponses=schedule;` |
| `firebase_functions/event_read_models.js:150` | `project` | `if(Object.keys(safeInvitees).length)manager.externalInvitees=safeInvitees;` |
| `firebase_functions/event_read_models.js:151` | `project` | `if(assignments.length)manager.substituteAssignments=Object.fromEntries(assignments.map(a=>{` |
| `firebase_functions/event_read_models.js:152` | `project` | `const raw=event.substituteAssignments[a.slotId];` |
| `firebase_functions/event_read_models.js:169` | `project` | `delete state.substituteAssignments;` |
| `firebase_functions/event_read_models.js:174` | `project` | `if(Object.keys(ownSchedule).length)state.ScheduleResponses=ownSchedule;` |
| `firebase_functions/event_read_models.js:175` | `project` | `if(isManual&&safeInvitees[uid])state.externalInvitees={[uid]:safeInvitees[uid]};` |
| `firebase_functions/event_read_models.js:183` | `requestsFor` | `const raw=event?.substituteAssignments;` |
| `firebase_functions/event_read_models.js:187` | `requestsFor` | `await Promise.all(ids.map(async id=>{requests[id]=(await db.ref(`SubRequests/${id}`).get()).val();}));` |
| `firebase_functions/event_read_models.js:193` | `reconcile` | `const sourceRef=db.ref(`Bands/${bandId}/Events/${eventId}`);` |
| `firebase_functions/event_read_models.js:196` | `reconcile` | `sourceRef.get(),db.ref(`Bands/${bandId}/Name`).get(),` |
| `firebase_functions/event_read_models.js:197` | `reconcile` | `db.ref(`Bands/${bandId}/Members_band`).get(),` |
| `firebase_functions/event_read_models.js:226` | `reconcileBand` | `db.ref(`Bands/${bandId}/Events`).get(),db.ref(`bandMemberEvents/${bandId}`).get(),` |
| `firebase_functions/event_read_models.js:237` | `reconcileBand` | `!event?.externalInvitees?.[uid] && !excludedIds(event).includes(uid) &&` |
| `firebase_functions/event_read_models.js:238` | `reconcileBand` | `!Object.values(event?.ScheduleResponses\|\|{}).some(users=>users?.[uid]) &&` |
| `firebase_functions/event_read_models.js:242` | `reconcileBand` | `if(!(await db.ref(`Bands/${bandId}/Name`).get()).exists())` |
| `firebase_functions/event_read_models.js:266` | `reconcileLegacyCalendar` | `const sourceRef=db.ref(`BandEvents/${bandId}/${eventId}`);` |
| `firebase_functions/event_read_models.js:268` | `reconcileLegacyCalendar` | `const [source,band]=await Promise.all([sourceRef.get(),db.ref(`Bands/${bandId}/Name`).get()]);` |
| `firebase_functions/index.js:59` | `resolveCatalogueCity` | `const exists=(await db.ref(`Bands/${targetId}`).get()).exists();` |
| `firebase_functions/index.js:79` | `commitUserCity` | `const infoRef=db.ref(`users/${uid}/info`);` |
| `firebase_functions/index.js:154` | `onCatalogueUserWritten` | `exports.onCatalogueUserWritten = onValueWritten({ref:'/users/{userId}',region:databaseTriggerRegion,retry:true},` |
| `firebase_functions/index.js:156` | `onCatalogueBandWritten` | `exports.onCatalogueBandWritten = onValueWritten({ref:'/Bands/{bandId}',region:databaseTriggerRegion,retry:true},` |
| `firebase_functions/index.js:167` | `onBandEventReadModelWritten` | `ref:'/Bands/{bandId}/Events/{eventId}',region:databaseTriggerRegion,retry:true,` |
| `firebase_functions/index.js:169` | `onBandEventReadModelWritten` | `const nonCalendarBandEvents = new Set(['Agreements','CancelledSubRequests',` |
| `firebase_functions/index.js:170` | `onBandEventReadModelWritten` | `'Notifications','PublishedSubRequests','SubRequestResponses']);` |
| `firebase_functions/index.js:172` | `onLegacyBandCalendarEventWritten` | `ref:'/BandEvents/{bandId}/{eventId}',region:databaseTriggerRegion,retry:true,` |
| `firebase_functions/index.js:174` | `onLegacyBandCalendarEventWritten` | `// BandEvents also contains unrelated legacy response, agreement and` |
| `firebase_functions/index.js:176` | `onLegacyBandCalendarEventWritten` | `if(nonCalendarBandEvents.has(event.params.bandId))return null;` |
| `firebase_functions/index.js:337` | `formatDateTimeLabel` | `* Triggered when a new event is created under /Bands/{bandId}/Events/{eventId}.` |
| `firebase_functions/index.js:341` | `onBandEventCreated` | `.ref('/Bands/{bandId}/Events/{eventId}')` |
| `firebase_functions/index.js:352` | `onBandEventCreated` | `const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);` |
| `firebase_functions/index.js:363` | `onBandEventCreated` | `const bandSnap = await admin.database().ref(`/Bands/${bandId}/Name`).once('value');` |
| `firebase_functions/index.js:410` | `onBandEventCreated` | `const tokenSnapshot = await admin.database().ref(`/users/${userId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:466` | `onBandEventCreated` | `admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();` |
| `firebase_functions/index.js:485` | `onBandEventWritten` | `.ref('/Bands/{bandId}/Events/{eventId}')` |
| `firebase_functions/index.js:499` | `onBandEventWritten` | `const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');` |
| `firebase_functions/index.js:567` | `onPublicEventWritten` | `* Triggered when a new substitute request is created under /SubRequests/{subRequestId}.` |
| `firebase_functions/index.js:571` | `sendSubRequestNotification` | `ref: '/SubRequests/{subRequestId}',` |
| `firebase_functions/index.js:613` | `sendSubRequestNotification` | `const usersRef = admin.database().ref('/users');` |
| `firebase_functions/index.js:736` | `sendSubRequestNotification` | `admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();` |
| `firebase_functions/index.js:789` | `onSubRequestGroupPublished` | `const usersRef = db.ref('/users');` |
| `firebase_functions/index.js:1370` | `publishSubRequestGroup` | `const existing = (await db.ref(`SubRequests/${id}`).get()).val();` |
| `firebase_functions/index.js:1377` | `publishSubRequestGroup` | `if (!(await db.ref(`Bands/${bandId}/Events/${linkedEvent}`).get()).exists()) throw new HttpsError('permission-denied','Owning band event was not found.');` |
| `firebase_functions/index.js:1387` | `publishSubRequestGroup` | `const evSnap = await db.ref(`/Bands/${bandId}/Events/${slotEventId}`).once('value');` |
| `firebase_functions/index.js:1396` | `publishSubRequestGroup` | `const callerFavSnap = await db.ref(`/users/${callerId}/Favorites`).once('value');` |
| `firebase_functions/index.js:1411` | `publishSubRequestGroup` | `: (db.ref('SubRequests').push().key \|\| `sub_${Date.now()}_${index}`);` |
| `firebase_functions/index.js:1503` | `publishSubRequestGroup` | `updates[`/SubRequests/${slotKey}`] = canonicalItem;` |
| `firebase_functions/index.js:1505` | `publishSubRequestGroup` | `updates[`/users/${callerId}/SubRequests/${slotKey}`] = canonicalItem;` |
| `firebase_functions/index.js:1572` | `matchesInstrument` | `const usersSnap = await db.ref('/users').once('value');` |
| `firebase_functions/index.js:1604` | `matchesInstrument` | `updates[`/publicSubRequests/${slotKey}`] = sanitizedItem;` |
| `firebase_functions/index.js:1631` | `matchesInstrument` | `updates[`/publicSubRequests/${slotKey}`] = null;` |
| `firebase_functions/index.js:1640` | `matchesInstrument` | `updates[`/publicSubRequests/${slotKey}`] = null;` |
| `firebase_functions/index.js:1685` | `respondToSubRequest` | `const subSnap = await db.ref(`SubRequests/${subRequestId}`).get();` |
| `firebase_functions/index.js:1707` | `respondToSubRequest` | `const roleSnap = await db.ref(`Bands/${bandId}/Members_band/${userId}/Role`).get();` |
| `firebase_functions/index.js:1755` | `respondToSubRequest` | `idempotentUpdates[`users/${userId}/AppliedSubRequests/${subRequestId}`] = true;` |
| `firebase_functions/index.js:1763` | `respondToSubRequest` | `updates[`SubRequests/${subRequestId}/Responses/${userId}`] = true;` |
| `firebase_functions/index.js:1765` | `respondToSubRequest` | `updates[`users/${userId}/AppliedSubRequests/${subRequestId}`] = true;` |
| `firebase_functions/index.js:1766` | `respondToSubRequest` | `updates[`BandEvents/SubRequestResponses/${subRequestId}/${userId}`] = {` |
| `firebase_functions/index.js:1772` | `respondToSubRequest` | `updates[`users/${creatorId}/SubRequests/${subRequestId}/Responses/${userId}`] = true;` |
| `firebase_functions/index.js:1776` | `respondToSubRequest` | `const userSnap = await db.ref(`users/${userId}`).get();` |
| `firebase_functions/index.js:1825` | `respondToSubRequest` | `updates[`BandEvents/Notifications/${creatorId}/${notifId}`] = notifData;` |
| `firebase_functions/index.js:1829` | `respondToSubRequest` | `const creatorTokenSnap = await db.ref(`/users/${creatorId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:1884` | `deleteSubRequest` | `const subSnap = await db.ref(`SubRequests/${subRequestId}`).get();` |
| `firebase_functions/index.js:1906` | `deleteSubRequest` | `updates[`SubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1907` | `deleteSubRequest` | `updates[`publicSubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1911` | `deleteSubRequest` | `updates[`users/${creatorId}/SubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1917` | `deleteSubRequest` | `updates[`BandEvents/PublishedSubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1918` | `deleteSubRequest` | `updates[`BandEvents/CancelledSubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1919` | `deleteSubRequest` | `updates[`BandEvents/SubRequestResponses/${subRequestId}`] = null;` |
| `firebase_functions/index.js:1952` | `assignSubstitute` | `const subReqRef = db.ref(`/SubRequests/${subRequestId}`);` |
| `firebase_functions/index.js:1966` | `assignSubstitute` | `(await db.ref(`Bands/${targetBandId}/Members_band/${callerId}`).get()).val();` |
| `firebase_functions/index.js:1971` | `assignSubstitute` | `const responsesSnap = await db.ref(`/SubRequests/${subRequestId}/Responses/${candidateUserId}`).once('value');` |
| `firebase_functions/index.js:1972` | `assignSubstitute` | `const legacyResponsesSnap = await db.ref(`/BandEvents/SubRequestResponses/${subRequestId}/${candidateUserId}`).once('value');` |
| `firebase_functions/index.js:2043` | `assignSubstitute` | `const existing = (await db.ref(`Bands/${targetBandId}/Members_band/${candidateUserId}`).get()).val();` |
| `firebase_functions/index.js:2050` | `assignSubstitute` | `// Multi-location idempotent derived updates (band event substitute assignments, externalInvitees, creator index)` |
| `firebase_functions/index.js:2053` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/substituteAssignments/${actualSlotId}`] = {` |
| `firebase_functions/index.js:2066` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/Responses/${candidateUserId}`] = {` |
| `firebase_functions/index.js:2071` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/userId`] = candidateUserId;` |
| `firebase_functions/index.js:2072` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/status`] = 'attending';` |
| `firebase_functions/index.js:2073` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/instrument`] = roleOrInstrument \|\| subReqData.VoicePart \|\| '';` |
| `firebase_functions/index.js:2075` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/displayName`] = candidateName;` |
| `firebase_functions/index.js:2077` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/source`] = 'subRequest';` |
| `firebase_functions/index.js:2078` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/externalInvitees/${candidateUserId}/subRequestId`] = subRequestId;` |
| `firebase_functions/index.js:2079` | `assignSubstitute` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/updatedAt`] = now;` |
| `firebase_functions/index.js:2085` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/IsSelected`] = true;` |
| `firebase_functions/index.js:2086` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/Status`] = 'assigned';` |
| `firebase_functions/index.js:2087` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserId`] = candidateUserId;` |
| `firebase_functions/index.js:2089` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedUserName`] = candidateName;` |
| `firebase_functions/index.js:2091` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedAt`] = now;` |
| `firebase_functions/index.js:2092` | `assignSubstitute` | `updates[`/users/${callerId}/SubRequests/${subRequestId}/AssignedBy`] = callerId;` |
| `firebase_functions/index.js:2096` | `assignSubstitute` | `updates[`/publicSubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:2097` | `assignSubstitute` | `updates[`/BandEvents/PublishedSubRequests/${subRequestId}`] = null;` |
| `firebase_functions/index.js:2153` | `assignSubstitute` | `const bSnap = await db.ref(`/Bands/${targetBandId}`).once('value');` |
| `firebase_functions/index.js:2175` | `assignSubstitute` | `const cSnap = await db.ref(`/users/${actualCreatorId}`).once('value');` |
| `firebase_functions/index.js:2185` | `assignSubstitute` | `const uSnap = await db.ref(`/users/${candidateUserId}`).once('value');` |
| `firebase_functions/index.js:2289` | `assignSubstitute` | `updates[`/BandEvents/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:2290` | `assignSubstitute` | `updates[`/users/${actualCreatorId}/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:2291` | `assignSubstitute` | `updates[`/users/${candidateUserId}/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:2317` | `assignSubstitute` | `const candidateTokenSnap = await db.ref(`/users/${candidateUserId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:2378` | `revokeSubstituteAssignment` | `const subReqRef = db.ref(`/SubRequests/${subRequestId}`);` |
| `firebase_functions/index.js:2393` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/IsSelected`] = false;` |
| `firebase_functions/index.js:2394` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/Status`] = 'published';` |
| `firebase_functions/index.js:2395` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/AssignedUserId`] = null;` |
| `firebase_functions/index.js:2396` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/AssignedUserName`] = null;` |
| `firebase_functions/index.js:2397` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/AssignedAt`] = null;` |
| `firebase_functions/index.js:2398` | `revokeSubstituteAssignment` | `updates[`/SubRequests/${subRequestId}/AssignedBy`] = null;` |
| `firebase_functions/index.js:2401` | `revokeSubstituteAssignment` | `updates[`/Bands/${targetBandId}/Events/${targetEventId}/substituteAssignments/${actualSlotId}`] = null;` |
| `firebase_functions/index.js:2406` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/IsSelected`] = false;` |
| `firebase_functions/index.js:2407` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/Status`] = 'published';` |
| `firebase_functions/index.js:2408` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/AssignedUserId`] = null;` |
| `firebase_functions/index.js:2409` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/AssignedUserName`] = null;` |
| `firebase_functions/index.js:2410` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/AssignedAt`] = null;` |
| `firebase_functions/index.js:2411` | `revokeSubstituteAssignment` | `updates[`/users/${actualCreatorId}/SubRequests/${subRequestId}/AssignedBy`] = null;` |
| `firebase_functions/index.js:2437` | `revokeSubstituteAssignment` | `updates[`/publicSubRequests/${subRequestId}`] = sanitizedItem;` |
| `firebase_functions/index.js:2474` | `getAppMetrics` | `const usersSnapshot = await db.ref('/users').once('value');` |
| `firebase_functions/index.js:2479` | `getAppMetrics` | `const bandsSnapshot = await db.ref('/Bands').once('value');` |
| `firebase_functions/index.js:2493` | `getAppMetrics` | `const subReqSnapshot = await db.ref('/SubRequests').once('value');` |
| `firebase_functions/index.js:2569` | `getAppMetrics` | `* Triggered when a member responds to an event under /Bands/{bandId}/Events/{eventId}/Responses/{userId}.` |
| `firebase_functions/index.js:2573` | `onEventResponseChanged` | `.ref('/Bands/{bandId}/Events/{eventId}/Responses/{userId}')` |
| `firebase_functions/index.js:2580` | `onEventResponseChanged` | `const eventRef = admin.database().ref(`/Bands/${bandId}/Events/${eventId}`);` |
| `firebase_functions/index.js:2596` | `onEventResponseChanged` | `const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);` |
| `firebase_functions/index.js:2638` | `onEventResponseChanged` | `const tokenSnapshot = await admin.database().ref(`/users/${creatorId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:2693` | `checkEventReminders` | `const bandsRef = admin.database().ref('/Bands');` |
| `firebase_functions/index.js:2705` | `checkEventReminders` | `const eventsRef = admin.database().ref(`/Bands/${bandId}/Events`);` |
| `firebase_functions/index.js:2753` | `checkEventReminders` | `const membersRef = admin.database().ref(`/Bands/${bandId}/Members_band`);` |
| `firebase_functions/index.js:2780` | `checkEventReminders` | `const tokenSnapshot = await admin.database().ref(`/users/${userId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:2828` | `checkEventReminders` | `await admin.database().ref(`/Bands/${bandId}/Events/${eventId}`).update(updateObj);` |
| `firebase_functions/index.js:2880` | `onCollabSessionApplicationChanged` | `const tokenSnapshot = await admin.database().ref(`/users/${creatorId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:2942` | `onCollabSessionApplicationChanged` | `const tokenSnapshot = await admin.database().ref(`/users/${applicantId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:3127` | `createAgreementConversation` | `const subReqSnap = await admin.database().ref(`/SubRequests/${subRequestId}`).once('value');` |
| `firebase_functions/index.js:3177` | `createAgreementConversation` | `const bSnap = await admin.database().ref(`/Bands/${targetBandId}`).once('value');` |
| `firebase_functions/index.js:3199` | `createAgreementConversation` | `const cSnap = await admin.database().ref(`/users/${creatorUid}`).once('value');` |
| `firebase_functions/index.js:3209` | `createAgreementConversation` | `const uSnap = await admin.database().ref(`/users/${applicantId}`).once('value');` |
| `firebase_functions/index.js:3314` | `createAgreementConversation` | `atomicUpdates[`/BandEvents/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:3315` | `createAgreementConversation` | `atomicUpdates[`/users/${creatorUid}/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:3316` | `createAgreementConversation` | `atomicUpdates[`/users/${applicantId}/Agreements/${conversationId}`] = agreementPayload;` |
| `firebase_functions/index.js:3423` | `sendDirectMessage` | `const senderSnap = await admin.database().ref(`/users/${senderUid}/info`).once('value');` |
| `firebase_functions/index.js:3601` | `triggerEventReminder` | `const roleSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${callerUid}/Role`).once('value');` |
| `firebase_functions/index.js:3604` | `triggerEventReminder` | `const eventSnap = await admin.database().ref(`/Bands/${bandId}/Events/${eventId}`).once('value');` |
| `firebase_functions/index.js:3642` | `triggerEventReminder` | `const membersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');` |
| `firebase_functions/index.js:3647` | `triggerEventReminder` | `const altMembersSnap = await admin.database().ref(`/Bands/${bandId}/Members`).once('value');` |
| `firebase_functions/index.js:3658` | `triggerEventReminder` | `if (eventData.externalInvitees && typeof eventData.externalInvitees === 'object') {` |
| `firebase_functions/index.js:3659` | `triggerEventReminder` | `Object.keys(eventData.externalInvitees).forEach(uid => memberIdsSet.add(uid));` |
| `firebase_functions/index.js:3689` | `triggerEventReminder` | ``/users/${uid}/info/PushToken`,` |
| `firebase_functions/index.js:3690` | `triggerEventReminder` | ``/users/${uid}/PushToken`,` |
| `firebase_functions/index.js:3691` | `triggerEventReminder` | ``/users/${uid}/info/pushToken`,` |
| `firebase_functions/index.js:3692` | `triggerEventReminder` | ``/users/${uid}/pushToken`,` |
| `firebase_functions/index.js:3693` | `triggerEventReminder` | ``/users/${uid}/fcmToken`,` |
| `firebase_functions/index.js:3694` | `triggerEventReminder` | ``/users/${uid}/info/fcmToken`,` |
| `firebase_functions/index.js:3791` | `triggerEventReminder` | `admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();` |
| `firebase_functions/index.js:3814` | `triggerEventReminder` | `await admin.database().ref(`/Bands/${bandId}/Events/${eventId}/${legacyKey}`).set(true);` |
| `firebase_functions/index.js:3851` | `createBandSectionConversation` | `const membersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');` |
| `firebase_functions/index.js:3864` | `createBandSectionConversation` | `const bandNameSnap = await admin.database().ref(`/Bands/${bandId}/Name`).once('value');` |
| `firebase_functions/index.js:3977` | `sendBandSectionMessage` | `const memberSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${senderUid}`).once('value');` |
| `firebase_functions/index.js:3984` | `sendBandSectionMessage` | `const userProfileSnap = await admin.database().ref(`/users/${senderUid}/info`).once('value');` |
| `firebase_functions/index.js:4054` | `sendBandSectionMessage` | `const tokenSnap = await admin.database().ref(`/users/${uid}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:4105` | `sendBandSectionMessage` | `admin.database().ref(`/users/${recipient.userId}/info/PushToken`).remove();` |
| `firebase_functions/index.js:4147` | `markBandSectionConversationRead` | `const memberSnap = await admin.database().ref(`/Bands/${bandId}/Members_band/${callerUid}`).once('value');` |
| `firebase_functions/index.js:4194` | `manageBandSectionConversation` | `const bandMembersSnap = await admin.database().ref(`/Bands/${bandId}/Members_band`).once('value');` |
| `firebase_functions/index.js:4323` | `manageBandSectionConversation` | `* Core handler for band membership changes (both /Bands/{bandId}/Members_band/{memberId}` |
| `firebase_functions/index.js:4341` | `handleBandMemberChange` | `const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');` |
| `firebase_functions/index.js:4343` | `handleBandMemberChange` | `const eventsSnap = await db.ref(`/Bands/${bandId}/Events`).once('value');` |
| `firebase_functions/index.js:4405` | `handleBandMemberChange` | `const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');` |
| `firebase_functions/index.js:4413` | `handleBandMemberChange` | `const eventsSnap = await db.ref(`/Bands/${bandId}/Events`).once('value');` |
| `firebase_functions/index.js:4456` | `handleBandMemberChange` | `* at canonical path /Bands/{bandId}/Members_band/{memberId}` |
| `firebase_functions/index.js:4459` | `onBandMemberWritten` | `ref: '/Bands/{bandId}/Members_band/{memberId}',` |
| `firebase_functions/index.js:4692` | `sendTestPushNotification` | `const usersSnap = await admin.database().ref('/users').once('value');` |
| `firebase_functions/index.js:4774` | `sendTestPushNotification` | `const tokenSnap = await admin.database().ref(`/users/${callerId}/info/PushToken`).once('value');` |
| `firebase_functions/index.js:4848` | `onBandRoomMessageCreated` | `const bandRef = admin.database().ref(`/Bands/${bandId}`);` |
| `firebase_functions/index.js:5003` | `markFeatureNotificationsRead` | `* Database trigger when a response is created under /SubRequests/{subRequestId}/Responses/{applicantId}.` |
| `firebase_functions/index.js:5007` | `onSubRequestResponseCreated` | `.ref('/SubRequests/{subRequestId}/Responses/{applicantId}')` |
| `firebase_functions/index.js:5015` | `onSubRequestResponseCreated` | `const subSnap = await db.ref(`/SubRequests/${subRequestId}`).once('value');` |
| `firebase_functions/index.js:5030` | `onSubRequestResponseCreated` | `const userSnap = await db.ref(`/users/${applicantId}`).once('value');` |
| `firebase_functions/index.js:5102` | `onBandFileUploaded` | `const bandRef = db.ref(`/Bands/${bandId}`);` |
| `firebase_functions/index.js:5168` | `deleteUserAccount` | `const legacy = (await db.ref(`users/${callerUid}/Bands`).get()).val() \|\| {};` |
| `firebase_functions/index.js:5170` | `deleteUserAccount` | `if (!(await db.ref(`Bands/${bandId}/Members_band/${callerUid}`).get()).exists()) {` |
| `firebase_functions/index.js:5178` | `deleteUserAccount` | `const subRequestsSnap = await db.ref('/SubRequests').once('value');` |
| `firebase_functions/index.js:5191` | `deleteUserAccount` | `if ((await db.ref(`Bands/${owningBand}`).get()).exists()) continue;` |
| `firebase_functions/index.js:5193` | `deleteUserAccount` | `subUpdates[`/SubRequests/${subId}`] = null;` |
| `firebase_functions/index.js:5236` | `deleteUserAccount` | `rootUpdates[`/users/${callerUid}`] = null;` |
| `firebase_functions/index.js:5261` | `deleteUserAccount` | `* Removes band references from all members' /users/{memberId}/Bands and deletes the band.` |
| `firebase_functions/index.js:5278` | `deleteBand` | `const bandRef = db.ref(`/Bands/${trimmedBandId}`);` |
| `firebase_functions/index.js:5300` | `deleteBand` | `updates[`/users/${memberId}/Bands/${trimmedBandId}`] = null;` |
| `firebase_functions/index.js:5436` | `sanitizeMapPinProjection` | `* Writes atomically to SubRequests/{generatedId} and publicMapPinFeed/{generatedId}.` |
| `firebase_functions/index.js:5437` | `sanitizeMapPinProjection` | `* Never writes to BandEvents/PublishedSubRequests or staffing notification feeds.` |
| `firebase_functions/index.js:5529` | `validateOptionalString` | `const memberSnap = await db.ref(`Bands/${bandId}/Members_band/${callerUid}`).once('value');` |
| `firebase_functions/index.js:5536` | `validateOptionalString` | `const subRequestsRef = db.ref('SubRequests');` |
| `firebase_functions/index.js:5604` | `validateOptionalString` | `// 8. Write atomically to canonical SubRequests/{generatedId} and publicMapPinFeed/{generatedId}` |
| `firebase_functions/index.js:5607` | `validateOptionalString` | `writeBatch[`SubRequests/${generatedId}`] = persistedPayload;` |
| `firebase_functions/index.js:5626` | `validateOptionalString` | `* and updates SubRequests/{id} without writing to staffing indexes.` |
| `firebase_functions/index.js:5657` | `validateOptionalString` | `const pinRef = db.ref(`SubRequests/${pinId}`);` |
| `firebase_functions/index.js:5674` | `validateOptionalString` | `const memberRoleSnap = await db.ref(`Bands/${bandId}/Members_band/${callerUid}/Role`).get();` |
| `firebase_functions/index.js:5782` | `validateOptionalString` | `rootUpdates[`SubRequests/${pinId}/${k}`] = v;` |
| `firebase_functions/index.js:5838` | `deleteMapPin` | `const pinRef = db.ref(`SubRequests/${pinId}`);` |
| `firebase_functions/index.js:5844` | `deleteMapPin` | `const pubSnap = await db.ref(`BandEvents/PublishedSubRequests/${pinId}`).get();` |
| `firebase_functions/index.js:5848` | `deleteMapPin` | `const userSnap = await db.ref(`users/${callerUid}/SubRequests/${pinId}`).get();` |
| `firebase_functions/index.js:5873` | `deleteMapPin` | `const memberRoleSnap = await db.ref(`Bands/${bandId}/Members_band/${callerUid}/Role`).get();` |
| `firebase_functions/index.js:5887` | `deleteMapPin` | `updates[`SubRequests/${pinId}`] = null;` |
| `firebase_functions/index.js:5889` | `deleteMapPin` | `updates[`BandEvents/PublishedSubRequests/${pinId}`] = null;` |
| `firebase_functions/index.js:5891` | `deleteMapPin` | `updates[`users/${creatorUid}/SubRequests/${pinId}`] = null;` |
| `firebase_functions/index.js:5893` | `deleteMapPin` | `updates[`users/${callerUid}/SubRequests/${pinId}`] = null;` |
| `firebase_functions/live_broadcasts.js:83` | `createAuthoritativeLiveKitToken` | `const bandSnap = await db.ref(`/Bands/${bandId}`).once('value');` |
| `firebase_functions/live_broadcasts.js:90` | `createAuthoritativeLiveKitToken` | `const memberSnap = await db.ref(`/Bands/${bandId}/Members_band/${callerUid}`).once('value');` |
| `firebase_functions/live_broadcasts.js:110` | `createAuthoritativeLiveKitToken` | `const userSnap = await db.ref(`/users/${callerUid}`).once('value');` |
| `firebase_functions/live_broadcasts.js:191` | `createAuthoritativeLiveKitToken` | `const userSnap = await db.ref(`/users/${callerUid}`).once('value');` |
| `firebase_functions/live_broadcasts.js:291` | `createAuthoritativeLiveKitToken` | `const memberSnap = await db.ref(`/Bands/${bVal.bandId}/Members_band/${callerUid}`).once('value');` |
| `firebase_functions/membership_authority.js:30` | `requireManager` | `const member = (await db.ref(`Bands/${id}/Members_band/${uid}`).get()).val();` |
| `firebase_functions/membership_authority.js:141` | `mutate` | `const ref = db.ref(`Bands/${bandId}`);` |


## Cutover decisions and intended schema

The table above records original source locations; the following decisions apply to all occurrences of each contract, including model parsing. Server Admin SDK reads are retained only behind callable/trigger authorization, never as client grants.

| Reader/writer (file unless specified: `lib/services/firebase_service.dart`) | Path and required fields | Audience | Decision and authority |
| --- | --- | --- | --- |
| `getUserProfileAsync` | own `/users/{uid}/info`, `UserType`, `Nickname`, `DisplayName` | exact owner; private profile fields | Migrated from parent read to exact required leaves. Other identities use `getPublicUserProfileAsync`. |
| `getBandInfoAsync`; Map `_openBandProfile` | own membership leaf; exact metadata/roster for active members | members for private metadata; unrelated users public allowlist only | Membership is checked before choosing the public/private branch; no exception-based fallback. Public route uses `PublicBandProfileScreen`. |
| `getAllUsersAsync`, `getAllBandsAsync`, public catalogue methods | `/publicUserProfiles`, `/publicBandProfiles`; decoder allowlists in `catalogue_profiles.dart` | signed-in discovery users | Retained complete uncapped catalogue; no canonical fallback. |
| `getUserBandsAsync`, membership policy | `/userBandMembershipIndex/{uid}` and exact canonical membership/name/mock flags | exact user | Retained server index plus canonical membership verification. Removed `/users/{uid}/Bands` writes. |
| `getSubRequestAsync`, `getAllSubRequestsAsync`, `getUserSubRequestsAsync`, feeds | creator/target/public feeds, canonical exact request only when authorized | exact creator/target or public advertised request | Removed other-user private copies and legacy response fallback. Permission denial stops further lookup. |
| `addResponseToSubRequestAsync`, `resolveAppliedSubRequestIdsForCardAsync` | canonical response and own `/users/{uid}/AppliedSubRequests` | applicant own leaf; manager/creator aggregate | Response creation exclusively `respondToSubRequest`; applied index server-owned. No applicant or notification compatibility copies. |
| `getSubRequestResponsesAsync`, response count | `/SubRequests/{id}/Responses` | exact creator or current owning-band Leader/Admin | Retained one canonical response authority. No externalInvitee inference or BandEvents fallback. |
| `saveSubRequestsBatchAsync`, publish/assign/revoke/delete | canonical SubRequests and sanitized public/user/creator feeds | authorized callable | Migrated batch to publish callable; removed obsolete mirror updates from `firebase_functions/index.js`. Failures propagate. |
| conversation metadata and `getActiveConversationsAsync` | own `/userConversations/{uid}`; exact `/conversations/{id}` | exact participants; active band member for band sections | Removed Agreement global scans and legacy user Agreement mirrors. Transitional broad conversation grant removed. |
| notification subscribe/read mutations | `/userNotifications/{uid}` | exact owner | Legacy BandEvents notification reads removed. Existing `markNotificationRead`/`markAllNotificationsRead` callables own mutations. |
| Event list/details/results and mutation APIs | member/user/manager Event projections; own canonical RSVP leaf writes | active member / exact invitee / exact manager | Existing sanitized Event projection architecture retained; canonical Event parent reads denied. |
| `addBandEventAsync`, `getBandEventsAsync` | `/Bands/{band}/Calendar/{event}` source, `/bandMemberCalendarEvents/{band}` read | manager writes via `mutateBandEvent`; member reads | Old `/BandEvents/{band}/{event}` source retired. Existing Calendar projection reused. |
| Collab discovery/create/update | `/Collabs/Sessions/{session}` allowlisted advertised fields | signed-in discovery; creator metadata writes | Private Responses cannot be embedded in public sessions. SessionChatId remains server-owned. |
| Session applications / RSVP | `/Collabs/Applications/{session}/{uid}`, `/Collabs/SessionResponses/{session}/{uid}` | creator aggregate; each participant own leaf | User-approved creator-and-own privacy. Accepted participants never receive another person's comments/reasons/contact/metadata. No participant list added because current UI does not require one. |
| `updateCollabApplicationStatusAsync`, session chat creation | existing session callables | exact creator; accepted members via server decision | Removed direct status/chat/index fallback writes. |
| Band files / news | `/files/{band}`, `/Bands/{band}/GigsNews` | exact active band | File writes require own uploader; news active-member write. Parent grants cannot expose other bands. |
| marketplace / reporting | `/marketplaceListings`, `/reportedListings` | advertised listings signed-in; reports server-private | Listings write only by immutable owner; reports create-only by identified reporter, no public read. |

### Supported top-level roots

| Roots | Authority / write owner | Readers | Lifecycle |
| --- | --- | --- | --- |
| `users` | own profile leaves; callable-owned applied index | exact own approved leaves | registration creates profile; account deletion removes own profile |
| `Bands` | membership/Event callables, own permitted RSVP; active-member news | approved member leaves only; own membership leaf; no canonical Event read | create sole Leader; mutate membership; authorized band deletion |
| `publicUserProfiles`, `publicBandProfiles` | derived allowlisted trigger projections | authenticated catalogue | reconciled on canonical changes/deletion |
| `userBandMembershipIndex` | derived membership trigger | exact indexed user | add/remove membership; canonical leaf remains authority |
| `bandMemberEvents`, `bandMemberCalendarEvents` | derived Event/Calendar triggers | exact active members | canonical create/update/delete |
| `bandManagerEvents` | derived Event trigger | exact active Leader/Admin | role loss denied immediately by canonical rules |
| `userEventReadModels` | derived Event trigger | own authorized member/invitee leaf | invitation/assignment revocation removes access |
| `eventReadProjectionIndex`, `mapEventProjectionIndex` | derived trigger bookkeeping | server only | updated with projection reconciliation |
| `SubRequests` | publish/respond/assign/revoke/delete callables | exact creator/active owning-band manager; applicant own response leaf | publish through closure/deletion; assignment authority lives here |
| `publicSubRequests`, `publicMapPinFeed`, `publicMapEventFeed` | derived allowlisted server feeds | authenticated advertised discovery | publication/update/revocation/deletion |
| `userSubRequestFeed`, `creatorSubRequestFeed`, `userMapEventFeed`, `creatorSubRequestGroups` | derived own-user server feeds | exact owner | mirror authorized publication lifecycle, not canonical authority |
| `subRequestAudience`, `subRequestPublications`, `subRequestNotificationAudit` | server targeting/idempotency | server only | publication/retry/delete |
| `conversations`, `userConversations` | conversation/Agreement callables | exact participants / own index | authoritative Agreement conversation and participant snapshots; no legacy mirror |
| `directConversationKeys`, `agreementConversationKeys`, `bandSectionConversations` | server idempotency/index | server only | create/retry and deletion |
| `userNotifications` | server triggers/callables | exact owner | delivery, read callables, account deletion |
| `eventReminderAudit` | server reminder bookkeeping | server only | reminder idempotency |
| `bandconversations`, `files` | existing authorized band operations | exact active band | band lifecycle; uploader-owned files |
| `Collabs` | creator public session/studio fields; own pending application; accepted own RSVP; acceptance/chat callable | public advertised records; private creator/own applications and RSVP | create/update/close/delete; RSVP separated from discovery |
| `marketplaceListings` | immutable listing owner | authenticated advertised discovery | active/sold/inactive/delete |
| `reportedListings` | reporter create-only; server moderation | server only | moderation retention, no public disclosure |
| `PublicEvents` | existing event owner | authenticated advertised events | create/update/delete |
| `LiveBroadcasts` | server broadcast authority | authenticated public broadcast summaries | start/end; provider tokens issued separately |
| `membershipMutationOperations` | server idempotency | server only | retry receipts |
| `citySearchRateState`, `citySearchSessions`, `cityVerificationGrants` | city-provider callables | server only | bounded rate/session/grant lifecycle |
| `userBandMemberships` | obsolete | denied | forbidden compatibility path |
| `BandEvents` | obsolete | denied | forbidden after empty launch; no compatibility writes |

Absent top-level keys remain denied by default. `/users/{uid}/Bands`, `/users/{uid}/SubRequests`, `/users/{uid}/Agreements` and every old `/BandEvents` descendant must not reappear. Existing Agreement keys/retry receipts not explicitly granted in rules are server-only by default.

### Empty bootstrap and failure semantics

1. Create Auth identity; write only its required private profile leaves. Catalogue triggers create public allowlisted records.
2. `mutateBandMembership` creates a band and sole Leader; membership trigger creates the own index. Existing manager-authorized member addition uses this server authority. There is no separate band invitation/acceptance workflow; the owner explicitly approved verifying the existing add-member flow for this gate.
3. `mutateBandEvent` creates canonical Event or Calendar; Event triggers produce member, exact-user and manager projections. Canonical parent reads remain denied.
4. `publishSubRequestGroup` creates canonical request, audience and supported feeds. `respondToSubRequest` creates the canonical response and own applied index. `assignSubstitute` authorizes the caller and creates the canonical Agreement conversation and own conversation indices atomically. Retries reuse server operation identities.
5. Logout/account switch discards private state and stale async results. Access errors must not trigger legacy reads or direct-write fallbacks. Authorized empty data is a separate result from a denied operation.
6. Existing authorized account/band deletion callables operate on supported canonical/derived data. This task does not invoke them outside local tests. Obsolete records are neither launch inputs nor migration targets.

No production Event backfill, migration or compatibility repair is planned. The Event backfill utility is restricted to demo loopback emulators as a validation tool. A future production reset remains separately authorized and has NOT been performed. Old clients fail closed at denied paths; no unreliable client-version check is used as a security boundary.

## Initial diagnostic run (superseded by final verification)

The first isolated full emulator diagnostic run produced 749 passed, 26 failed, 0 skipped (22 files), zero external attempts and zero Secret Manager attempts. This is not a passing gate. Findings included the transitional conversation grant, changed direct-response write expectations, legacy cleanup/mirror expectations and one catalogue convergence timeout. Updated tests must preserve or strengthen authorization assertions and prove the replacement callable path. Final results supersede these diagnostic counts only after a complete rerun.


### Session and access invalidation implementation

`FirebaseService._forCurrentSession` tracks identity events for protected one-shot reads, including A → B → A changes. `_sessionStream` clears its value and emits a neutral access error on identity change or authorization failure. SubRequest feed failures stop the combined stream instead of leaving cached private feed rows visible. Notification streams use the same boundary.

`SubRequestResponsesScreen` observes user/band changes and subscribes to each displayed request's exact canonical response count. Loss of authorization clears every rendered request/count and shows a neutral message. `SessionDetailsScreen` observes identity changes, clears applicant state, and rejects late asynchronous results. Existing Event manager streams remain on audience-scoped projections.

The Map production diff is confined to the band-profile action and public-screen import. It chooses member metadata only after exact own-membership verification; unrelated/inactive/removed users use the public decoder and public screen. Existing marker, feed, filtering, pin and navigation behavior elsewhere in Map is unchanged.


### Test contract changes (no authorization assertions weakened)

- Direct canonical response writes now assert denial even for audience members. The new real-callable bootstrap proves authorized submission via `respondToSubRequest` and authoritative assignment/Agreement creation.
- Old anonymous/unrelated legacy BandEvents reads now assert denial. Transitional conversation writes also assert denial, matching final rules.
- Account/profile reload checks require exact own `info` reads and explicitly deny the whole user parent. The catalogue source regression rejects the old parent read and requires the owner field allowlist.
- Band-file success fixtures now establish actual active membership; unrelated legacy-file reads assert denial.
- Agreement tests retain canonical snapshot/index/idempotency assertions and require obsolete mirrors to be absent. Fixtures containing obsolete records test that current callables do not treat them as authority or perform unsolicited legacy cleanup.
- Session RSVP tests target the private `Collabs/SessionResponses` authority and prove creator/own access plus cross-participant denial after accepted membership. Public-session creation with embedded Responses is rejected.
- Flutter service doubles implement the newly required live authorization streams. Existing assertions remain; new focused widget tests prove that authorization loss removes private band fields and Manage Requests counts immediately.

### Final analyzer comparison

Seven changed production Dart files were analyzed with `flutter analyze --no-pub`: service, Map band-profile action, public band profile, Session details, Manage Requests, Inbox, and Edit Band. Final result: 0 errors, 0 warnings, 108 infos. Clean HEAD has 109 infos for its corresponding six existing files. No new diagnostic code/message/file occurrences remain; the removed info is `prefer_final_fields` for Session details' now-cleared applicant profile map. No suppression was added.

## Full Flutter regression evidence

Full current run: 1,075 passed, 334 failed, 0 skipped across 105 files. Clean HEAD: 1,068 passed, 334 failed, 0 skipped across 104 files. Every failing name and normalized cause matched exactly; no new failures. The final focused suite additionally includes the new private-band access-loss test and passes 8/8. Supplementary changed-screen regressions are reconciled separately below.

| File | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| `test/account_and_band_deletion_test.dart` | 2 | 5 | 0 |
| `test/agreement_integrity_01_test.dart` | 28 | 0 | 0 |
| `test/agreements_ux_01a_test.dart` | 28 | 0 | 0 |
| `test/applied_lifecycle_01_test.dart` | 34 | 0 | 0 |
| `test/band_event_test.dart` | 10 | 0 | 0 |
| `test/band_member_hold_test.dart` | 2 | 3 | 0 |
| `test/band_membership_performance_01_test.dart` | 42 | 0 | 0 |
| `test/band_required_prompt_01_test.dart` | 33 | 0 | 0 |
| `test/band_room_files_category_test.dart` | 4 | 0 | 0 |
| `test/band_room_gigs_info_feed_test.dart` | 0 | 3 | 0 |
| `test/band_section_chat_test.dart` | 8 | 0 | 0 |
| `test/chat_architecture_test.dart` | 4 | 0 | 0 |
| `test/clean_schema_privacy_01_test.dart` | 7 | 0 | 0 |
| `test/collabs_landing_picker_test.dart` | 1 | 2 | 0 |
| `test/create_01_event_session_test.dart` | 15 | 9 | 0 |
| `test/create_edit_band_feedback_test.dart` | 1 | 10 | 0 |
| `test/create_event_edit_members_test.dart` | 1 | 4 | 0 |
| `test/currency_formatter_test.dart` | 3 | 0 | 0 |
| `test/edit_band_settings_test.dart` | 4 | 8 | 0 |
| `test/event_details_page_rsvp_test.dart` | 10 | 0 | 0 |
| `test/event_results_page_test.dart` | 10 | 0 | 0 |
| `test/feature_flags_live_broadcast_test.dart` | 2 | 0 | 0 |
| `test/find_gigs_feed_test.dart` | 0 | 12 | 0 |
| `test/find_musician_02_test.dart` | 14 | 21 | 0 |
| `test/find_musician_03a_test.dart` | 0 | 21 | 0 |
| `test/find_musician_03b_test.dart` | 1 | 40 | 0 |
| `test/find_musician_04_test.dart` | 3 | 16 | 0 |
| `test/find_musician_ux_01_test.dart` | 25 | 0 | 0 |
| `test/find_requests_01b_test.dart` | 2 | 16 | 0 |
| `test/find_sub_routing_and_banner_test.dart` | 2 | 0 | 0 |
| `test/gen_01_selection_field_tap_test.dart` | 8 | 2 | 0 |
| `test/gen_batch_ui_test.dart` | 1 | 7 | 0 |
| `test/geo_distance_test.dart` | 2 | 0 | 0 |
| `test/gig_map_guide_banner_test.dart` | 1 | 0 | 0 |
| `test/gig_map_pin_color_coding_test.dart` | 8 | 0 | 0 |
| `test/global_create_event_phase1_test.dart` | 10 | 2 | 0 |
| `test/home_activity_badges_test.dart` | 10 | 6 | 0 |
| `test/home_profiles_action_label_test.dart` | 2 | 0 | 0 |
| `test/inbox_null_timestamp_test.dart` | 1 | 0 | 0 |
| `test/instruments_list_update_test.dart` | 0 | 2 | 0 |
| `test/international_city_forms_01_test.dart` | 7 | 0 | 0 |
| `test/international_city_picker_01_test.dart` | 7 | 0 | 0 |
| `test/live_broadcast_service_test.dart` | 2 | 0 | 0 |
| `test/live_broadcast_test.dart` | 5 | 0 | 0 |
| `test/live_broadcaster_bar_test.dart` | 3 | 0 | 0 |
| `test/live_listener_sheet_test.dart` | 2 | 0 | 0 |
| `test/livekit_audio_controller_test.dart` | 6 | 0 | 0 |
| `test/manage_events_screen_test.dart` | 5 | 0 | 0 |
| `test/manage_requests_lifecycle_01_test.dart` | 48 | 0 | 0 |
| `test/map_crosshair_targeting_test.dart` | 12 | 0 | 0 |
| `test/map_crosshair_test.dart` | 3 | 0 | 0 |
| `test/map_event_activity_helper_test.dart` | 20 | 0 | 0 |
| `test/map_event_feed_test.dart` | 9 | 0 | 0 |
| `test/map_view_apply_test.dart` | 23 | 0 | 0 |
| `test/map_view_audio_focus_test.dart` | 20 | 0 | 0 |
| `test/map_view_backend_persistence_test.dart` | 11 | 0 | 0 |
| `test/map_view_feed_test.dart` | 0 | 1 | 0 |
| `test/map_view_feedback_04_test.dart` | 18 | 0 | 0 |
| `test/map_view_lifecycle_test.dart` | 6 | 0 | 0 |
| `test/map_view_light_version_test.dart` | 8 | 0 | 0 |
| `test/map_view_quick_polish_test.dart` | 12 | 0 | 0 |
| `test/map_view_snippet_crosshair_test.dart` | 6 | 0 | 0 |
| `test/map_view_unified_feed_test.dart` | 30 | 0 | 0 |
| `test/map_view_upload_parity_test.dart` | 17 | 0 | 0 |
| `test/marketplace_redesign_test.dart` | 7 | 9 | 0 |
| `test/membership_authority_hardening_01_test.dart` | 60 | 0 | 0 |
| `test/mock_rehearsal_volume_test.dart` | 4 | 0 | 0 |
| `test/multi_subs_01_test.dart` | 12 | 35 | 0 |
| `test/new_user_skills_and_band_guards_01_test.dart` | 35 | 0 | 0 |
| `test/notification_center_test.dart` | 16 | 2 | 0 |
| `test/oct_sprint_01_events_calendar_test.dart` | 0 | 14 | 0 |
| `test/p2_tasks_ui_cleanup_test.dart` | 1 | 4 | 0 |
| `test/profile_details_feedback_test.dart` | 0 | 8 | 0 |
| `test/profile_social_links_test.dart` | 0 | 2 | 0 |
| `test/profiles_picker_popup_test.dart` | 2 | 0 | 0 |
| `test/public_event_calendar_feedback_test.dart` | 0 | 18 | 0 |
| `test/public_event_calendar_repository_test.dart` | 10 | 0 | 0 |
| `test/public_event_calendar_screen_test.dart` | 0 | 16 | 0 |
| `test/public_event_create_test.dart` | 4 | 4 | 0 |
| `test/public_event_details_screen_test.dart` | 1 | 9 | 0 |
| `test/push_sound_admin_screen_test.dart` | 4 | 0 | 0 |
| `test/registration_flow_test.dart` | 5 | 0 | 0 |
| `test/registration_genres_test.dart` | 7 | 1 | 0 |
| `test/registration_secondary_skills_01_test.dart` | 49 | 0 | 0 |
| `test/request_cards_01_test.dart` | 60 | 0 | 0 |
| `test/rsvp_deadline_utils_test.dart` | 14 | 0 | 0 |
| `test/rsvp_design_03_test.dart` | 3 | 6 | 0 |
| `test/rsvp_reminder_dialog_test.dart` | 5 | 0 | 0 |
| `test/ruta_02_picker_hierarchy_test.dart` | 24 | 2 | 0 |
| `test/safe_catalogue_projections_01_test.dart` | 31 | 0 | 0 |
| `test/sanitized_event_read_model_01_test.dart` | 7 | 0 | 0 |
| `test/session_01_create_session_test.dart` | 14 | 0 | 0 |
| `test/simple_rsvp_02_test.dart` | 3 | 2 | 0 |
| `test/skills_taxonomy_test.dart` | 23 | 1 | 0 |
| `test/sub_request_location_override_regression_test.dart` | 7 | 0 | 0 |
| `test/sub_request_self_response_test.dart` | 4 | 0 | 0 |
| `test/subrequest_data_consistency_01_test.dart` | 12 | 0 | 0 |
| `test/subrequest_feed_client_test.dart` | 11 | 0 | 0 |
| `test/subrequest_hotfix_visibility_test.dart` | 9 | 6 | 0 |
| `test/subrequest_response_count_test.dart` | 1 | 0 | 0 |
| `test/task4_navigation_audio_test.dart` | 4 | 0 | 0 |
| `test/today_features_test.dart` | 0 | 4 | 0 |
| `test/tour_group_rendering_test.dart` | 4 | 0 | 0 |
| `test/user_profile_test.dart` | 3 | 0 | 0 |
| `test/widget_test.dart` | 0 | 1 | 0 |

Every failing name and its normalized cause is preserved in `build/clean-schema-flutter-failures.md`; machine-readable current/HEAD pairs are in `build/clean-schema-flutter-comparison.json`. Both were generated from actual JSON reporter runs against this working tree and a `git archive` of the exact starting HEAD, not inferred from older reports.

## Final isolated emulator verification

781 passed, 0 failed, 0 skipped across all 22 configured test files. The network guard ran in 153 processes and recorded zero external-network and zero Secret Manager attempts. Auth, RTDB and Functions all ran with the explicit demo project and isolated credential/config directories. Temporary fake provider configuration was restored/removed by the runner.

| File | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| `firebase_functions/test/emulator_membership_authority.test.js` | 106 | 0 | 0 |
| `firebase_functions/test/emulator_isolation.test.js` | 3 | 0 | 0 |
| `firebase_functions/test/emulator_clean_schema_privacy.test.js` | 22 | 0 | 0 |
| `firebase_functions/test/city_verification.test.js` | 6 | 0 | 0 |
| `firebase_functions/test/google_places_cities.test.js` | 21 | 0 | 0 |
| `firebase_functions/test/catalogue_projections.test.js` | 51 | 0 | 0 |
| `firebase_functions/test/emulator_city_verification.test.js` | 12 | 0 | 0 |
| `firebase_functions/test/emulator_catalogue_projections.test.js` | 24 | 0 | 0 |
| `firebase_functions/test/event_read_models.test.js` | 7 | 0 | 0 |
| `firebase_functions/test/backfill_event_read_models.test.js` | 2 | 0 | 0 |
| `firebase_functions/test/emulator_event_read_models.test.js` | 13 | 0 | 0 |
| `firebase_functions/test/band_membership_index.test.js` | 27 | 0 | 0 |
| `firebase_functions/test/emulator_band_membership_index.test.js` | 13 | 0 | 0 |
| `firebase_functions/test/emulator_rules.test.js` | 214 | 0 | 0 |
| `firebase_functions/test/emulator_callables.test.js` | 84 | 0 | 0 |
| `firebase_functions/test/functions_logic.test.js` | 100 | 0 | 0 |
| `firebase_functions/test/subrequest_security.test.js` | 14 | 0 | 0 |
| `firebase_functions/test/verify_subrequest_migration.test.js` | 8 | 0 | 0 |
| `firebase_functions/test/emulator_event_map_feed.test.js` | 19 | 0 | 0 |
| `firebase_functions/test/backfill_map_event_feed.test.js` | 10 | 0 | 0 |
| `firebase_functions/test/backfill_public_map_pin_feed.test.js` | 7 | 0 | 0 |
| `firebase_functions/test/emulator_map_pin_security.test.js` | 18 | 0 | 0 |

### Exact focused emulator test names

- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json anonymous cannot enumerate private roots or read canonical private descendants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json outsider cannot enumerate private roots or read canonical private descendants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json ordinary member reads approved data and only own target, never manager or applicants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json applicant reads only own canonical response and cannot forge another response
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json legacy reads and writes fail closed even for their former owner
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json all projection and server-index roots reject forged client writes
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json a noncreator Admin has exact-band aggregate access and loses it on demotion
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json Calendar creation uses canonical callable and existing member projection, never BandEvents
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json Session RSVP comments are creator-and-own only, never included in discovery
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json current Leader reads manager data; role loss denies member/manager projections but preserves exact creator request access
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json anonymous cannot enumerate private roots or read canonical private descendants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json outsider cannot enumerate private roots or read canonical private descendants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json ordinary member reads approved data and only own target, never manager or applicants
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json applicant reads only own canonical response and cannot forge another response
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json legacy reads and writes fail closed even for their former owner
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json all projection and server-index roots reject forged client writes
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json a noncreator Admin has exact-band aggregate access and loses it on demotion
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json Calendar creation uses canonical callable and existing member projection, never BandEvents
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json Session RSVP comments are creator-and-own only, never included in discovery
- CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json current Leader reads manager data; role loss denies member/manager projections but preserves exact creator request access

### Verification limits and launch prerequisites

- Full Flutter still has 334 failures that reproduce on the exact clean checkpoint with identical normalized causes. This is a local privacy review gate, not a claim that the entire application regression suite is green.
- The earlier emulator run used host Node 24. The final reconciliation below supersedes that runtime evidence using actual Node 22, with package engines unchanged.
- This schema is for a separately authorized empty-data launch. Do not deploy it as an in-place migration over obsolete records. In particular, new public Session metadata is allowlisted and cannot include Responses; old Session records containing private descendants must not be retained at launch.
- Production remains completely untouched. Old production grants are not claimed to be removed until a separately authorized rollout. No reset, data cleanup, migration or production backfill is authorized by this local result.
- Emulator-only fixture creation/deletion and local projection validation exercised the required lifecycle tests. No manual or production reset/deletion was performed.

## Final affected Flutter reconciliation and workspace state

The final 12-file affected subset produced 227 passed, 28 failed, 0 skipped. All 28 failing names and normalized causes match clean HEAD. The focused privacy file passed all 8 tests. The earlier missing mock-method diagnostic was repaired by implementing the new stream API in its service double; the original test assertions were retained and its final cause again matches clean HEAD.

JavaScript syntax passed for all 13 changed/new JavaScript files. Both rules files parsed as JSON and passed real emulator loading. There are no changed tracked Python scripts; the ignored local comparison utility passed Python compilation. `git diff --check` passed. Added tracked lines had no credential patterns in the performed private-key/token-pattern scan.

Branch remains `main`, HEAD remains `93953e05cbf801a28cc8fb9b10691ba49ad040b5`, and version remains `2.79.3+252`. Staging is empty. Exactly 33 tracked files are modified and 4 files are untracked. No commit, push, deployment, production access, production reset/deletion/cleanup, migration, production backfill, API enablement, production secret creation or version bump occurred.

### Exact final status

```text
 M database.rules.json
 M database.transitional.rules.json
 M firebase_functions/band_membership_index.js
 M firebase_functions/event_mutations.js
 M firebase_functions/event_read_models.js
 M firebase_functions/index.js
 M firebase_functions/package.json
 M firebase_functions/scripts/backfill_event_read_models.js
 M firebase_functions/test/backfill_event_read_models.test.js
 M firebase_functions/test/emulator_callables.test.js
 M firebase_functions/test/emulator_event_read_models.test.js
 M firebase_functions/test/emulator_map_pin_security.test.js
 M firebase_functions/test/emulator_membership_authority.test.js
 M firebase_functions/test/emulator_rules.test.js
 M firebase_functions/test/subrequest_security.test.js
 M lib/services/firebase_service.dart
 M lib/views/edit_band_info_screen.dart
 M lib/views/gig_map_page.dart
 M lib/views/inbox_screen.dart
 M lib/views/session_details_screen.dart
 M lib/views/sub_request_responses_screen.dart
 M test/account_and_band_deletion_test.dart
 M test/band_member_hold_test.dart
 M test/create_edit_band_feedback_test.dart
 M test/edit_band_settings_test.dart
 M test/gen_01_selection_field_tap_test.dart
 M test/international_city_forms_01_test.dart
 M test/manage_requests_lifecycle_01_test.dart
 M test/membership_authority_hardening_01_test.dart
 M test/request_cards_01_test.dart
 M test/safe_catalogue_projections_01_test.dart
 M test/subrequest_data_consistency_01_test.dart
 M test/subrequest_hotfix_visibility_test.dart
?? docs/clean_schema_privacy_cutover_01.md
?? firebase_functions/test/emulator_clean_schema_privacy.test.js
?? lib/views/public_band_profile_screen.dart
?? test/clean_schema_privacy_01_test.dart
```

### Exact focused Flutter test names

- live authorization failure clears previously rendered Manage Requests data
- band membership loss removes the private edit profile immediately
- public band profile renders catalogue fields and no private band controls
- nonmember band profile uses only sanitized public data: null
- nonmember band profile uses only sanitized public data: {Status: inactive}
- nonmember band profile uses only sanitized public data: {Status: removed}
- membership permission denial never triggers a public or legacy fallback
- A to B to A rejects a pending private band result

| Final affected file | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| `test/account_and_band_deletion_test.dart` | 2 | 5 | 0 |
| `test/agreement_integrity_01_test.dart` | 28 | 0 | 0 |
| `test/agreements_ux_01a_test.dart` | 28 | 0 | 0 |
| `test/band_member_hold_test.dart` | 2 | 3 | 0 |
| `test/clean_schema_privacy_01_test.dart` | 8 | 0 | 0 |
| `test/create_edit_band_feedback_test.dart` | 1 | 10 | 0 |
| `test/edit_band_settings_test.dart` | 4 | 8 | 0 |
| `test/gen_01_selection_field_tap_test.dart` | 8 | 2 | 0 |
| `test/international_city_forms_01_test.dart` | 7 | 0 | 0 |
| `test/manage_requests_lifecycle_01_test.dart` | 48 | 0 | 0 |
| `test/membership_authority_hardening_01_test.dart` | 60 | 0 | 0 |
| `test/safe_catalogue_projections_01_test.dart` | 31 | 0 | 0 |

## Final reconciliation evidence (2026-11-06)

This appendix supersedes earlier runtime and workspace totals. No production Flutter code changed during reconciliation. Test-only changes strengthen bootstrap assertions and record/enforce Node runtime versions. No assertion was removed or relaxed.

### Exact workspace state

Branch: `main`; HEAD: `93953e05cbf801a28cc8fb9b10691ba49ad040b5`; version: `2.79.3+252`; staged paths: `none`.

`git status --short`
```text
 M database.rules.json
 M database.transitional.rules.json
 M firebase_functions/band_membership_index.js
 M firebase_functions/event_mutations.js
 M firebase_functions/event_read_models.js
 M firebase_functions/index.js
 M firebase_functions/package.json
 M firebase_functions/scripts/backfill_event_read_models.js
 M firebase_functions/scripts/run_isolated_emulators.py
 M firebase_functions/test/backfill_event_read_models.test.js
 M firebase_functions/test/emulator_callables.test.js
 M firebase_functions/test/emulator_event_read_models.test.js
 M firebase_functions/test/emulator_isolation_guard.js
 M firebase_functions/test/emulator_map_pin_security.test.js
 M firebase_functions/test/emulator_membership_authority.test.js
 M firebase_functions/test/emulator_rules.test.js
 M firebase_functions/test/subrequest_security.test.js
 M lib/services/firebase_service.dart
 M lib/views/edit_band_info_screen.dart
 M lib/views/gig_map_page.dart
 M lib/views/inbox_screen.dart
 M lib/views/session_details_screen.dart
 M lib/views/sub_request_responses_screen.dart
 M test/account_and_band_deletion_test.dart
 M test/band_member_hold_test.dart
 M test/create_edit_band_feedback_test.dart
 M test/edit_band_settings_test.dart
 M test/gen_01_selection_field_tap_test.dart
 M test/international_city_forms_01_test.dart
 M test/manage_requests_lifecycle_01_test.dart
 M test/membership_authority_hardening_01_test.dart
 M test/request_cards_01_test.dart
 M test/safe_catalogue_projections_01_test.dart
 M test/subrequest_data_consistency_01_test.dart
 M test/subrequest_hotfix_visibility_test.dart
?? docs/clean_schema_privacy_cutover_01.md
?? firebase_functions/test/emulator_clean_schema_privacy.test.js
?? lib/views/public_band_profile_screen.dart
?? test/clean_schema_privacy_01_test.dart
```

`git diff --stat`
```text
 database.rules.json                                |  391 ++++++--
 database.transitional.rules.json                   |  404 ++++++--
 firebase_functions/band_membership_index.js        |    5 -
 firebase_functions/event_mutations.js              |    8 +-
 firebase_functions/event_read_models.js            |    2 +-
 firebase_functions/index.js                        |   91 +-
 firebase_functions/package.json                    |    2 +-
 .../scripts/backfill_event_read_models.js          |   16 +-
 .../scripts/run_isolated_emulators.py              |    2 +
 .../test/backfill_event_read_models.test.js        |    3 +
 firebase_functions/test/emulator_callables.test.js |   56 +-
 .../test/emulator_event_read_models.test.js        |    9 +-
 .../test/emulator_isolation_guard.js               |    6 +-
 .../test/emulator_map_pin_security.test.js         |    4 +-
 .../test/emulator_membership_authority.test.js     |    5 +-
 firebase_functions/test/emulator_rules.test.js     |   47 +-
 .../test/subrequest_security.test.js               |    8 +-
 lib/services/firebase_service.dart                 | 1052 +++++---------------
 lib/views/edit_band_info_screen.dart               |   54 +-
 lib/views/gig_map_page.dart                        |   13 +-
 lib/views/inbox_screen.dart                        |   69 +-
 lib/views/session_details_screen.dart              |   93 +-
 lib/views/sub_request_responses_screen.dart        |   70 +-
 test/account_and_band_deletion_test.dart           |    3 +
 test/band_member_hold_test.dart                    |    2 +
 test/create_edit_band_feedback_test.dart           |    3 +
 test/edit_band_settings_test.dart                  |    3 +
 test/gen_01_selection_field_tap_test.dart          |    3 +
 test/international_city_forms_01_test.dart         |    3 +
 test/manage_requests_lifecycle_01_test.dart        |    5 +
 test/membership_authority_hardening_01_test.dart   |    3 +
 test/request_cards_01_test.dart                    |    3 +
 test/safe_catalogue_projections_01_test.dart       |    7 +-
 test/subrequest_data_consistency_01_test.dart      |    3 +
 test/subrequest_hotfix_visibility_test.dart        |    3 +
 35 files changed, 1286 insertions(+), 1165 deletions(-)
```

`git diff --name-only` (untracked paths are listed separately by status)
```text
database.rules.json
database.transitional.rules.json
firebase_functions/band_membership_index.js
firebase_functions/event_mutations.js
firebase_functions/event_read_models.js
firebase_functions/index.js
firebase_functions/package.json
firebase_functions/scripts/backfill_event_read_models.js
firebase_functions/scripts/run_isolated_emulators.py
firebase_functions/test/backfill_event_read_models.test.js
firebase_functions/test/emulator_callables.test.js
firebase_functions/test/emulator_event_read_models.test.js
firebase_functions/test/emulator_isolation_guard.js
firebase_functions/test/emulator_map_pin_security.test.js
firebase_functions/test/emulator_membership_authority.test.js
firebase_functions/test/emulator_rules.test.js
firebase_functions/test/subrequest_security.test.js
lib/services/firebase_service.dart
lib/views/edit_band_info_screen.dart
lib/views/gig_map_page.dart
lib/views/inbox_screen.dart
lib/views/session_details_screen.dart
lib/views/sub_request_responses_screen.dart
test/account_and_band_deletion_test.dart
test/band_member_hold_test.dart
test/create_edit_band_feedback_test.dart
test/edit_band_settings_test.dart
test/gen_01_selection_field_tap_test.dart
test/international_city_forms_01_test.dart
test/manage_requests_lifecycle_01_test.dart
test/membership_authority_hardening_01_test.dart
test/request_cards_01_test.dart
test/safe_catalogue_projections_01_test.dart
test/subrequest_data_consistency_01_test.dart
test/subrequest_hotfix_visibility_test.dart
```

Modified: 35; untracked: 4.

| File | Classification |
| --- | --- |
| `database.rules.json` | rules |
| `database.transitional.rules.json` | rules |
| `firebase_functions/band_membership_index.js` | backend authority/projection |
| `firebase_functions/event_mutations.js` | backend authority/projection |
| `firebase_functions/event_read_models.js` | backend authority/projection |
| `firebase_functions/index.js` | backend authority/projection |
| `firebase_functions/package.json` | test |
| `firebase_functions/scripts/backfill_event_read_models.js` | backend authority/projection |
| `firebase_functions/scripts/run_isolated_emulators.py` | test |
| `firebase_functions/test/backfill_event_read_models.test.js` | test |
| `firebase_functions/test/emulator_callables.test.js` | test |
| `firebase_functions/test/emulator_event_read_models.test.js` | test |
| `firebase_functions/test/emulator_isolation_guard.js` | test |
| `firebase_functions/test/emulator_map_pin_security.test.js` | test |
| `firebase_functions/test/emulator_membership_authority.test.js` | test |
| `firebase_functions/test/emulator_rules.test.js` | test |
| `firebase_functions/test/subrequest_security.test.js` | test |
| `lib/services/firebase_service.dart` | Flutter client cutover |
| `lib/views/edit_band_info_screen.dart` | Flutter client cutover |
| `lib/views/gig_map_page.dart` | Map security-only adjustment |
| `lib/views/inbox_screen.dart` | Flutter client cutover |
| `lib/views/session_details_screen.dart` | Flutter client cutover |
| `lib/views/sub_request_responses_screen.dart` | Flutter client cutover |
| `test/account_and_band_deletion_test.dart` | test |
| `test/band_member_hold_test.dart` | test |
| `test/create_edit_band_feedback_test.dart` | test |
| `test/edit_band_settings_test.dart` | test |
| `test/gen_01_selection_field_tap_test.dart` | test |
| `test/international_city_forms_01_test.dart` | test |
| `test/manage_requests_lifecycle_01_test.dart` | test |
| `test/membership_authority_hardening_01_test.dart` | test |
| `test/request_cards_01_test.dart` | test |
| `test/safe_catalogue_projections_01_test.dart` | test |
| `test/subrequest_data_consistency_01_test.dart` | test |
| `test/subrequest_hotfix_visibility_test.dart` | test |
| `docs/clean_schema_privacy_cutover_01.md` | checked-in architecture documentation |
| `firebase_functions/test/emulator_clean_schema_privacy.test.js` | test |
| `lib/views/public_band_profile_screen.dart` | Flutter client cutover |
| `test/clean_schema_privacy_01_test.dart` | test |

No result/log/build/environment/credential file is tracked or untracked outside ignored build output. The checked-in documentation is the requested architecture audit, not an emulator result file.

### Remaining direct Flutter root references

Each table entry is a literal reference, not a whole-root read. `push().key` allocates locally without reading or writing. Method names and explanatory comments are excluded. No literal root-only users/Bands/BandEvents database reference remains.

| Source | Literal path | Safe purpose / boundary |
| --- | --- | --- |
| `lib/services/firebase_service.dart:264` | `users/$trimmedUid/info/$key` | Exact own profile/notification token fields; rules bind uid to auth.uid; other profiles use public catalogue. |
| `lib/services/firebase_service.dart:266` | `users/$trimmedUid/$key` | Exact own profile/notification token fields; rules bind uid to auth.uid; other profiles use public catalogue. |
| `lib/services/firebase_service.dart:354` | `users/$targetId/$field` | Exact own profile/notification token fields; rules bind uid to auth.uid; other profiles use public catalogue. |
| `lib/services/firebase_service.dart:444` | `users/$selfId/Favorites/$targetUserId` | Own favorites only; owner leaf read/write. |
| `lib/services/firebase_service.dart:453` | `users/$selfId/Favorites/$targetUserId` | Own favorites only; owner leaf read/write. |
| `lib/services/firebase_service.dart:455` | `users/$selfId/Favorites/$targetUserId` | Own favorites only; owner leaf read/write. |
| `lib/services/firebase_service.dart:462` | `users/$selfId/Favorites` | Own favorites only; owner leaf read/write. |
| `lib/services/firebase_service.dart:496` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:513` | `Bands/$bandId/$field` | Exact allowlisted band metadata leaf, active-member read; own-membership check first. |
| `lib/services/firebase_service.dart:525` | `Bands/$bandId/Members_band` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:601` | `Bands/$bandId/Members_band` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:1296` | `users/$uid/AppliedSubRequests` | Exact own applicant index; server writes only. |
| `lib/services/firebase_service.dart:1352` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:1877` | `Bands/$bandId/Calendar` | Local push-key allocation only; actual creation via authorized callable. |
| `lib/services/firebase_service.dart:2102` | `users/$userId/info/PushToken` | Exact own profile/notification token fields; rules bind uid to auth.uid; other profiles use public catalogue. |
| `lib/services/firebase_service.dart:2385` | `Bands/$bandId/Events` | Local push-key allocation only; actual creation via authorized callable. |
| `lib/services/firebase_service.dart:2516` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:2549` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:2574` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:2609` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:2664` | `Bands/$bandId/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:2719` | `Bands/$bandId/Events/$eventId/Responses/$userId` | Own Event RSVP leaf write only, unlocked Event and authorized participation; no canonical parent read. |
| `lib/services/firebase_service.dart:2736` | `Bands/$bandId/Events/$eventId/ScheduleResponses/$scheduleItemId/$userId` | Own Event RSVP leaf write only, unlocked Event and authorized participation; no canonical parent read. |
| `lib/services/firebase_service.dart:2806` | `Bands/$bandId/GigsNews` | Exact active-band news read/write; no other-band access. |
| `lib/services/firebase_service.dart:2816` | `Bands/$bandId/GigsNews` | Exact active-band news read/write; no other-band access. |
| `lib/services/firebase_service.dart:2838` | `Bands/$bandId/GigsNews/$postId` | Exact active-band news read/write; no other-band access. |
| `lib/services/firebase_service.dart:2846` | `users/$userId/metrics/buttonClicks` | Own metrics only; owner leaf read/write. |
| `lib/services/firebase_service.dart:2869` | `users/$userId/metrics/buttonClicks/$buttonId` | Own metrics only; owner leaf read/write. |
| `lib/services/firebase_service.dart:2932` | `Bands/$bandId/Members_band/$userId/Role` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/services/firebase_service.dart:3247` | `Bands/$bandId/eventRooms` | Exact active-band event-room reads; existing active-member room writes (not canonical membership authority). |
| `lib/services/firebase_service.dart:3282` | `Bands/$bandId/eventRooms` | Exact active-band event-room reads; existing active-member room writes (not canonical membership authority). |
| `lib/services/firebase_service.dart:3304` | `Bands/$bandId/eventRooms/$roomId/members/$userId` | Exact active-band event-room reads; existing active-member room writes (not canonical membership authority). |
| `lib/services/firebase_service.dart:3317` | `Bands/$bandId/eventRooms/$roomId` | Exact active-band event-room reads; existing active-member room writes (not canonical membership authority). |
| `lib/services/firebase_service.dart:3319` | `Bands/$bandId/eventRooms/$roomId/isClosed` | Exact active-band event-room reads; existing active-member room writes (not canonical membership authority). |
| `lib/services/firebase_service.dart:3414` | `users/$uid/PublicEvents/$eventId` | Exact own advertised-event copy; own-leaf read/write, no other-user lookup. |
| `lib/services/firebase_service.dart:3458` | `users/$uid/PublicEvents` | Exact own advertised-event copy; own-leaf read/write, no other-user lookup. |
| `lib/services/firebase_service.dart:3486` | `users/$uid/PublicEvents/$eventId` | Exact own advertised-event copy; own-leaf read/write, no other-user lookup. |
| `lib/utils/band_membership_policy.dart:35` | `Bands/$id/Members_band/$uid` | Own membership verification or active-member roster/role read; membership writes server-owned. |
| `lib/utils/band_membership_policy.dart:39` | `Bands/$id/Name` | Exact allowlisted band metadata leaf, active-member read; own-membership check first. |
| `lib/utils/band_membership_policy.dart:40` | `Bands/$id/isMock` | Exact allowlisted band metadata leaf, active-member read; own-membership check first. |
| `lib/utils/band_membership_policy.dart:41` | `Bands/$id/isDemo` | Exact allowlisted band metadata leaf, active-member read; own-membership check first. |

### Exact direct client write-rule inventory

All expressions below are copied from current rules. They are intentionally permitted direct writes; not every write is own-leaf (band news/rooms and public creator records retain their documented scopes). Membership/roles, audiences, manager grants, catalogue and Event projections remain server-owned. Own RSVP fields do not grant authority. Schema `.validate` constraints also apply.

#### database.rules.json

Root, `/users`, `/Bands`, `/BandEvents` reads: `false`.

| Write path | Exact rule |
| --- | --- |
| `/users/$userId/Favorites` | `auth != null && auth.uid == $userId` |
| `/users/$userId/Favorites/$targetUserId` | `auth != null && auth.uid == $userId` |
| `/users/$userId/info` | `auth != null && auth.uid == $userId && newData.child('Location').val() == data.child('Location').val() && newData.child('PublicLocation').val() == data.child('PublicLocation').val() && newData.child('LocationCleared').val() == data.child('LocationCleared').val() && newData.child('CityOperationId').val() == data.child('CityOperationId').val() && newData.child('CityUpdatedAt').val() == data.child('CityUpdatedAt').val()` |
| `/users/$userId/UserType` | `auth != null && auth.uid == $userId` |
| `/users/$userId/Nickname` | `auth != null && auth.uid == $userId` |
| `/users/$userId/DisplayName` | `auth != null && auth.uid == $userId` |
| `/users/$userId/metrics` | `auth != null && auth.uid == $userId` |
| `/users/$userId/PublicEvents` | `auth != null && auth.uid == $userId` |
| `/Bands/$bandId/GigsNews` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))` |
| `/Bands/$bandId/Events/$eventId/Responses/$userId` | `auth != null && auth.uid == $userId && root.child('Bands').child($bandId).child('Events').child($eventId).child('isLocked').val() != true && ((root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))) &#124;&#124; (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).exists() && (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'manual' &#124;&#124; root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'direct') && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').val().matches(/^ *(pending&#124;attending&#124;maybe&#124;declined) *$/i)))` |
| `/Bands/$bandId/Events/$eventId/ScheduleResponses/$scheduleItemId/$userId` | `auth != null && auth.uid == $userId && root.child('Bands').child($bandId).child('Events').child($eventId).child('isLocked').val() != true && ((root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))) &#124;&#124; (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).exists() && (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'manual' &#124;&#124; root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'direct') && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').val().matches(/^ *(pending&#124;attending&#124;maybe&#124;declined) *$/i)))` |
| `/bandconversations/$bandId/messages/$messageId` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && root.child('bandconversations').child($bandId).child('members').child(auth.uid).val() == true && !data.exists() && newData.child('SenderId').val() == auth.uid` |
| `/files/$bandId/$fileId` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && ((!data.exists() && newData.child('UploadedBy').val() == auth.uid) &#124;&#124; data.child('UploadedBy').val() == auth.uid)` |
| `/marketplaceListings/$listingId` | `auth != null && ((!data.exists() && newData.child('userId').val() == auth.uid) &#124;&#124; (data.child('userId').val() == auth.uid && (!newData.exists() &#124;&#124; newData.child('userId').val() == auth.uid)))` |
| `/reportedListings/$reportId` | `auth != null && !data.exists() && newData.child('reportedByUserId').val() == auth.uid` |
| `/PublicEvents/$eventId` | `auth != null && ( (!data.exists() && (newData.child('createdBy').val() == auth.uid &#124;&#124; !newData.child('createdBy').exists())) &#124;&#124; (data.exists() && (data.child('createdBy').val() == auth.uid &#124;&#124; !data.child('createdBy').exists())) )` |
| `/Collabs/Sessions/$sessionId` | `auth != null && ( (!data.exists() && newData.child('CreatorId').val() == auth.uid) &#124;&#124; (!newData.exists() && data.child('CreatorId').val() == auth.uid) )` |
| `/Collabs/Sessions/$sessionId/Title` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Description` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/SessionType` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/SessionCategory` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/IsDateFlexible` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/StartDateTime` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/EndDateTime` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Location` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Genres` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/RequireResponse` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/RsvpDeadline` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/ReminderIntervalHours` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/UpdatedAt` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Status` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Studios/$studioId` | `auth != null && ((!data.exists() && newData.child('CreatorId').val() == auth.uid) &#124;&#124; (data.child('CreatorId').val() == auth.uid && (!newData.exists() &#124;&#124; newData.child('CreatorId').val() == auth.uid)))` |
| `/Collabs/Applications/$sessionId/$applicantId` | `auth != null && ( (!data.exists() && auth.uid == $applicantId && newData.child('Status').val() == 'pending') &#124;&#124; (!newData.exists() && (auth.uid == $applicantId &#124;&#124; root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid)) )` |
| `/Collabs/Applications/$sessionId` | `auth != null && !newData.exists() && root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid` |
| `/Collabs/SessionResponses/$sessionId/$userId` | `auth != null && auth.uid == $userId && root.child('Collabs').child('Applications').child($sessionId).child(auth.uid).child('Status').val() == 'accepted'` |
| `/Collabs/SessionResponses/$sessionId` | `auth != null && !newData.exists() && root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid` |
#### database.transitional.rules.json

Root, `/users`, `/Bands`, `/BandEvents` reads: `false`.

| Write path | Exact rule |
| --- | --- |
| `/users/$userId/Favorites` | `auth != null && auth.uid == $userId` |
| `/users/$userId/Favorites/$targetUserId` | `auth != null && auth.uid == $userId` |
| `/users/$userId/info` | `auth != null && auth.uid == $userId && newData.child('Location').val() == data.child('Location').val() && newData.child('PublicLocation').val() == data.child('PublicLocation').val() && newData.child('LocationCleared').val() == data.child('LocationCleared').val() && newData.child('CityOperationId').val() == data.child('CityOperationId').val() && newData.child('CityUpdatedAt').val() == data.child('CityUpdatedAt').val()` |
| `/users/$userId/UserType` | `auth != null && auth.uid == $userId` |
| `/users/$userId/Nickname` | `auth != null && auth.uid == $userId` |
| `/users/$userId/DisplayName` | `auth != null && auth.uid == $userId` |
| `/users/$userId/metrics` | `auth != null && auth.uid == $userId` |
| `/users/$userId/PublicEvents` | `auth != null && auth.uid == $userId` |
| `/Bands/$bandId/GigsNews` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))` |
| `/Bands/$bandId/Events/$eventId/Responses/$userId` | `auth != null && auth.uid == $userId && root.child('Bands').child($bandId).child('Events').child($eventId).child('isLocked').val() != true && ((root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))) &#124;&#124; (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).exists() && (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'manual' &#124;&#124; root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'direct') && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').val().matches(/^ *(pending&#124;attending&#124;maybe&#124;declined) *$/i)))` |
| `/Bands/$bandId/Events/$eventId/ScheduleResponses/$scheduleItemId/$userId` | `auth != null && auth.uid == $userId && root.child('Bands').child($bandId).child('Events').child($eventId).child('isLocked').val() != true && ((root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i)))) &#124;&#124; (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).exists() && (root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'manual' &#124;&#124; root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('source').val() == 'direct') && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Events').child($eventId).child('externalInvitees').child(auth.uid).child('status').val().matches(/^ *(pending&#124;attending&#124;maybe&#124;declined) *$/i)))` |
| `/bandconversations/$bandId/messages/$messageId` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && root.child('bandconversations').child($bandId).child('members').child(auth.uid).val() == true && !data.exists() && newData.child('SenderId').val() == auth.uid` |
| `/files/$bandId/$fileId` | `auth != null && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).hasChildren() && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('Status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && (!root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').exists() &#124;&#124; (root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').isString() && root.child('Bands').child($bandId).child('Members_band').child(auth.uid).child('status').val().matches(/^ *(active&#124;on_hold&#124;temporarily_off) *$/i))) && ((!data.exists() && newData.child('UploadedBy').val() == auth.uid) &#124;&#124; data.child('UploadedBy').val() == auth.uid)` |
| `/marketplaceListings/$listingId` | `auth != null && ((!data.exists() && newData.child('userId').val() == auth.uid) &#124;&#124; (data.child('userId').val() == auth.uid && (!newData.exists() &#124;&#124; newData.child('userId').val() == auth.uid)))` |
| `/reportedListings/$reportId` | `auth != null && !data.exists() && newData.child('reportedByUserId').val() == auth.uid` |
| `/PublicEvents/$eventId` | `auth != null && ( (!data.exists() && (newData.child('createdBy').val() == auth.uid &#124;&#124; !newData.child('createdBy').exists())) &#124;&#124; (data.exists() && (data.child('createdBy').val() == auth.uid &#124;&#124; !data.child('createdBy').exists())) )` |
| `/Collabs/Sessions/$sessionId` | `auth != null && ( (!data.exists() && newData.child('CreatorId').val() == auth.uid) &#124;&#124; (!newData.exists() && data.child('CreatorId').val() == auth.uid) )` |
| `/Collabs/Sessions/$sessionId/Title` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Description` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/SessionType` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/SessionCategory` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/IsDateFlexible` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/StartDateTime` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/EndDateTime` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Location` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Genres` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/RequireResponse` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/RsvpDeadline` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/ReminderIntervalHours` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/UpdatedAt` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Sessions/$sessionId/Status` | `auth != null && data.parent().child('CreatorId').val() == auth.uid` |
| `/Collabs/Studios/$studioId` | `auth != null && ((!data.exists() && newData.child('CreatorId').val() == auth.uid) &#124;&#124; (data.child('CreatorId').val() == auth.uid && (!newData.exists() &#124;&#124; newData.child('CreatorId').val() == auth.uid)))` |
| `/Collabs/Applications/$sessionId/$applicantId` | `auth != null && ( (!data.exists() && auth.uid == $applicantId && newData.child('Status').val() == 'pending') &#124;&#124; (!newData.exists() && (auth.uid == $applicantId &#124;&#124; root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid)) )` |
| `/Collabs/Applications/$sessionId` | `auth != null && !newData.exists() && root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid` |
| `/Collabs/SessionResponses/$sessionId/$userId` | `auth != null && auth.uid == $userId && root.child('Collabs').child('Applications').child($sessionId).child(auth.uid).child('Status').val() == 'accepted'` |
| `/Collabs/SessionResponses/$sessionId` | `auth != null && !newData.exists() && root.child('Collabs').child('Sessions').child($sessionId).child('CreatorId').val() == auth.uid` |

### Final reconciliation scope and security conclusions

Production code was not changed during reconciliation. Changes are limited to the existing new bootstrap test (more assertions), the isolation guard (log process.version/entry and reject an unexpected configured major), the isolated runner (record observed versions in its summary), and this architecture documentation. package.json engines remain Node 22.

The Node runtime is the already-installed Playwright 1.50.1 binary, v22.13.1, copied to ignored build/node22-runtime. PATH selects that binary for Firebase and Functions; an ignored npm launcher invokes npm-cli.js through the same binary. EMULATOR_EXPECTED_NODE_MAJOR=22 fails closed in every preloaded CLI, npm, Mocha, and Functions-worker process. NODE_OPTIONS retains the existing external-network guard and deterministic Places/FCM/provider mocks. ADC and user configuration remain isolated. No download or external provider request was needed.

The Map production diff is only lib/views/gig_map_page.dart: the public-profile import and _openBandProfile action. It preserves the authorized private edit/profile destination after own-member verification; unrelated/inactive users receive only the existing publicBandProfiles decoder and PublicBandProfileScreen. A changed session rejects the result; failure shows a neutral snackbar. Permission denial propagates and never retries a canonical Bands path. No feed, pin, audio, upload, location, filtering, clustering, camera, unrelated navigation, or layout code changed. Public screen fields are name, ensemble type, validated city/country location, genres, style, level, active-member count, and public description/about; no roster, dedicated contact fields, rehearsal address, private events, or management controls.

Both rule roots and /users, /Bands, /BandEvents have .read=false. Exact owner profile leaves, exact own membership verification, authorized active-band metadata/roster and own RSVP writes are separate from public catalogue reads. No complete users/Bands query, BandEvents/SubRequestResponses read, other-user creator-copy fallback, user whole-band snapshot read, or permission-denied broader-path fallback remains in Flutter. The literal-reference appendix lists every remaining direct Flutter root-path string and its boundary. Server Admin SDK readers are not client grants: triggers/callables continue canonical reads for authorized mutations/projections, and the existing getAppMetrics endpoint computes public aggregate counts from server root scans; no claim is made that server root scans were eliminated.

The real clean-schema tests under BOTH rule files deny former-owner reads/writes to users/{uid}/Bands, SubRequests, Agreements and BandEvents legacy roots; deny all catalogue/Event projection and authority-index forgeries; deny unrelated/anonymous private root reads; allow exact noncreator Admin response reads only for the active band and deny after demotion. Existing membership-authority emulator tests independently reject forged memberships/roles/privilege changes. Canonical SubRequest response writes are callable-only; clients cannot recreate duplicate response copies. The exact direct-write inventory below distinguishes own-leaf writes from intentionally shared active-band news/room writes and creator-owned advertised records; these are not membership or manager-authority writes.

Session RSVP data is only Collabs/SessionResponses/{sessionId}/{uid}. Creator aggregate reads and the participant's own leaf reads are allowed; an unrelated user and a second accepted participant cannot read another participant's comment/reason. Accepted users can write only their own response. Public Collabs/Sessions metadata rejects embedded Responses. No attendee participant list is currently rendered or added, so there is no unsanitized attendee-list fallback. Creator lifecycle deletion is separately explicit in the rules. Both-rule test: "Session RSVP comments are creator-and-own only, never included in discovery".

The strengthened both-rule test "bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies" uses real Auth account creation and real callables, fresh missing user/band keys, own private profile writes, trigger-created public user/band records, sole Leader assertion, authorized add-member, sanitized Event creation, own RSVP/user projection, real signOut/signInWithEmailAndPassword and denied signed-out projection access, publication, response, assignment, and participant-authorized Agreement reads. The runner starts an unimported emulator; no legacy record is required. As explicitly confirmed by the owner, the existing manager-authorized add-member flow satisfies this gate; no separate band invitation/acceptance workflow is claimed.

Flutter evidence: fresh final full-tree run 1076 passed/334 failed/0 skipped vs executed clean HEAD 1068 passed/334 failed/0 skipped. The final affected rerun is 227 passed/28 failed/0 skipped. Machine-compared full and subset failure-name sets have zero current-only names, zero HEAD-only names, and zero differing normalized causes. Machine artifacts (ignored): build/clean-schema-full-comparison-final.json and build/clean-schema-affected-comparison-final.json contain both exact sets and both normalized causes. build/clean-schema-flutter-failures.md lists all 334 failures readably. The full tree, affected subset and all changed-production analysis were freshly rerun. All 228 Dart source files in the executed clean-HEAD snapshot were additionally compared to Git HEAD after line-ending normalization: zero mismatches.

Fully passing affected suites: clean_schema_privacy_01 (8), agreement_integrity_01 (28), agreements_ux_01a (28), international_city_forms_01 (7), manage_requests_lifecycle_01 (48), membership_authority_hardening_01 (60), safe_catalogue_projections_01 (31). Their source assertions were not removed/relaxed. Existing doubles now implement required authorization streams; the catalogue source test now rejects whole-profile reads and requires the explicit owner-field allowlist instead. The focused suite separately tests live authorization loss, stale A-to-B-to-A rejection, no private fallback, and public-only Map profile presentation.

Fresh analysis of all seven changed production Dart files: 0 errors, 0 warnings, 108 infos. Clean HEAD: 0 errors, 0 warnings, 109 infos for the corresponding six existing files. File/code/message multiset comparison gives zero new diagnostics; the only removed info is prefer_final_fields for SessionDetails' now-reset profile map. No suppressions were added. Node 22 syntax checks pass for all 14 changed/new JavaScript files; both rules JSON parse; the one changed Python runner compiles; git diff --check passes.

Remaining release blockers/prerequisites: 334 full Flutter failures still require resolution or an explicit release decision; the separately authorized empty-data production cutover, compatible-client rollout and production security verification have not occurred. Existing production privacy gaps are not claimed fixed by local rules. This is not an in-place migration: obsolete public Session records containing private descendants must not be retained. Old-client legacy writes/read paths fail closed under the new rules; obsolete records are not migration inputs. No production Event backfill is planned, and the backfill utility remains demo-loopback-only. Node 22 is no longer an unverified prerequisite once the final passing runtime result below is recorded.

No commit, push, deployment, production access, manual database reset/deletion, migration, production backfill, cleanup, API enablement, production secret creation, or version bump occurred. Only the requested isolated emulator tests created/updated/deleted their own fixtures; temporary runner configuration was restored. No production or user database was touched.

### Final Node 22 complete-suite result

Launcher `node --version`: **v22.13.1**. The Firebase CLI, Functions workers, and Mocha test process each independently logged **v22.13.1**. The binary SHA256 matches the installed source: `8F6945C55A51C893691534E7163372E4CEDB62C8AD80A2A975DF3F14A19FBA16`. Package engines stayed `22`.

Final isolated serial run: **781 passed, 0 failed, 0 skipped**, all **22** configured files, both rules files, **156** guarded Node processes, **0 external-network attempts**, **0 Secret Manager attempts**. No ambient ADC or production providers were used.

| Configured file (firebase_functions/test/) | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| `emulator_membership_authority.test.js` | 106 | 0 | 0 |
| `emulator_isolation.test.js` | 3 | 0 | 0 |
| `emulator_clean_schema_privacy.test.js` | 22 | 0 | 0 |
| `city_verification.test.js` | 6 | 0 | 0 |
| `google_places_cities.test.js` | 21 | 0 | 0 |
| `catalogue_projections.test.js` | 51 | 0 | 0 |
| `emulator_city_verification.test.js` | 12 | 0 | 0 |
| `emulator_catalogue_projections.test.js` | 24 | 0 | 0 |
| `event_read_models.test.js` | 7 | 0 | 0 |
| `backfill_event_read_models.test.js` | 2 | 0 | 0 |
| `emulator_event_read_models.test.js` | 13 | 0 | 0 |
| `band_membership_index.test.js` | 27 | 0 | 0 |
| `emulator_band_membership_index.test.js` | 13 | 0 | 0 |
| `emulator_rules.test.js` | 214 | 0 | 0 |
| `emulator_callables.test.js` | 84 | 0 | 0 |
| `functions_logic.test.js` | 100 | 0 | 0 |
| `subrequest_security.test.js` | 14 | 0 | 0 |
| `verify_subrequest_migration.test.js` | 8 | 0 | 0 |
| `emulator_event_map_feed.test.js` | 19 | 0 | 0 |
| `backfill_map_event_feed.test.js` | 10 | 0 | 0 |
| `backfill_public_map_pin_feed.test.js` | 7 | 0 | 0 |
| `emulator_map_pin_security.test.js` | 18 | 0 | 0 |

Run history is not hidden: the first Node 22 complete run passed 781/0/0. A subsequent run overlapping the full Flutter run produced 780/1/0: `Real Cloud Functions Emulator Integration Tests (JS Client SDK + Emulators) HOME-ACTIVITY-BADGES-01: Real Emulator Callables & Triggers 6. onBandFileUploaded trigger notifies band members and excludes uploader` did not observe the expected notification within its polling window. The final full serial run passed 781/0/0 with the exact same assertions and timeout. The failed run is preserved in ignored `build/clean-schema-node22-concurrent-summary.json`, `build/clean-schema-node22-concurrent-results.json`, and `build/clean-schema-node22-concurrent.log`. This intermittent timing sensitivity remains visible to release review.

The final complete run includes all strengthened empty-bootstrap assertions. Its exact bootstrap test names are:

- `CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.rules.json bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies`
- `CLEAN-SCHEMA-PRIVACY-CUTOVER-01 database.transitional.rules.json bootstraps new accounts, sole Leader, member, Event, response, assignment and Agreement without legacy copies`

Final tree remains main / 93953e05cbf801a28cc8fb9b10691ba49ad040b5 / 2.79.3+252. 35 modified tracked files + 4 untracked files; staging empty. The exact status/stat/name-only outputs and all 39 classifications appear above. No generated result/log/build/credential/environment artifact is included in that file list.

READY FOR CLEAN-SCHEMA-PRIVACY-CUTOVER-01 CHECKPOINT COMMIT
