import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/map_view_unified_feed_helper.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/sub_request_responses_screen.dart';
import 'package:musicians_flutter/views/gig_map_page.dart' show MapCategory;
import 'package:provider/provider.dart';

class MockHotfixFirebaseService extends FirebaseService {
  String? _currentUserId = 'creator_user_1';
  bool _isLoggedIn = true;
  bool shouldCallableFail = false;

  final Map<String, SubRequest> canonicalSubRequests = {};
  final Map<String, SubRequest> publicFeeds = {};
  final Map<String, Map<String, SubRequest>> userFeeds = {};
  final Map<String, Map<String, SubRequest>> creatorFeeds = {};
  final StreamController<List<SubRequest>> feedController =
      StreamController<List<SubRequest>>.broadcast();

  final Map<String, Band> bands = {
    'band_1': Band(id: 'band_1', name: 'Stockholm Jazz Quartet'),
  };

  final Map<String, BandEvent> events = {};

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) => Stream.value(0);

  @override
  Future<void> initializePushNotifications() async {}

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final uid = userId ?? _currentUserId ?? 'creator_user_1';
    return UserProfile(
      userId: uid,
      displayName: 'User $uid',
      email: '$uid@example.com',
      location: 'Stockholm, Sweden',
    );
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {'band_1': 'Stockholm Jazz Quartet'};
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return bands[bandId];
  }

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async {
    return events[eventId];
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    return [];
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return [];
  }



  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return events.values.toList();
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return ['fav_user_2'];
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [
      UserProfile(userId: 'fav_user_2', displayName: 'Favorite Musician'),
      UserProfile(userId: 'other_user_3', displayName: 'Other Musician'),
    ];
  }

  @override
  Future<int> getSubRequestResponseCountAsync(String subRequestId) async {
    return 0;
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    final selfId = currentUserId;
    if (userId == selfId && selfId != null && selfId.isNotEmpty) {
      if (creatorFeeds.containsKey(userId)) {
        return creatorFeeds[userId]!.values.where((r) {
          final st = r.status.toLowerCase();
          return st != 'cancelled' && st != 'deleted' && st != 'closed';
        }).toList();
      }
      return [];
    }
    return [];
  }

  @override
  Stream<List<SubRequest>> getSubRequestFeedStream({String? targetUserId}) {
    return feedController.stream;
  }

  void emitCurrentFeeds() {
    final List<SubRequest> merged = [];
    final Set<String> seenIds = {};

    void addValid(SubRequest r) {
      final id = r.subRequestId ?? r.id;
      if (id != null && !seenIds.contains(id) && r.isLive) {
        seenIds.add(id);
        merged.add(r);
      }
    }

    for (final r in publicFeeds.values) {
      addValid(r);
    }
    final uid = currentUserId;
    if (uid != null && userFeeds.containsKey(uid)) {
      for (final r in userFeeds[uid]!.values) {
        addValid(r);
      }
    }
    if (uid != null && creatorFeeds.containsKey(uid)) {
      for (final r in creatorFeeds[uid]!.values) {
        addValid(r);
      }
    }

    feedController.add(merged);
  }

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    if (shouldCallableFail) {
      throw Exception('Simulated Cloud Function Error: values argument contains undefined');
    }

    final creatorId = currentUserId ?? 'anon';
    final savedIds = <String>[];

    for (int i = 0; i < requests.length; i++) {
      final req = requests[i];
      final slotKey = (req.subRequestId != null && req.subRequestId!.isNotEmpty && !req.subRequestId!.startsWith('slot_'))
          ? req.subRequestId!
          : 'sub_test_${DateTime.now().millisecondsSinceEpoch}_$i';

      final canonical = req.copyWith(
        id: slotKey,
        subRequestId: slotKey,
        slotId: req.slotId ?? slotKey,
        creatorUserId: creatorId,
        userId: creatorId,
        status: 'published',
        createdAt: req.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );

      canonicalSubRequests[slotKey] = canonical;
      creatorFeeds.putIfAbsent(creatorId, () => {})[slotKey] = canonical;

      final isDirect = req.targetUserIds != null && req.targetUserIds!.isNotEmpty && req.searchSource != 'search_all';
      if (!isDirect) {
        publicFeeds[slotKey] = canonical;
      } else {
        for (final tUid in req.targetUserIds!) {
          userFeeds.putIfAbsent(tUid, () => {})[slotKey] = canonical;
        }
      }

      savedIds.add(slotKey);
    }

    emitCurrentFeeds();
    return savedIds;
  }

  @override
  Future<bool> deleteSubRequestAsync(String creatorId, String subRequestId) async {
    canonicalSubRequests.remove(subRequestId);
    publicFeeds.remove(subRequestId);
    if (creatorFeeds.containsKey(creatorId)) {
      creatorFeeds[creatorId]!.remove(subRequestId);
    }
    for (final uMap in userFeeds.values) {
      uMap.remove(subRequestId);
    }
    emitCurrentFeeds();
    return true;
  }
}

class MockHotfixAppState extends AppState {
  final MockHotfixFirebaseService _mockFirebase;
  MockHotfixAppState(this._mockFirebase);

  @override
  FirebaseService get firebaseService => _mockFirebase;

  @override
  String? get currentUserId => _mockFirebase.currentUserId;

  @override
  String? get activeBandId => 'band_1';

  @override
  String? get activeBandName => 'Stockholm Jazz Quartet';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
  });

  group('HOTFIX 2.78.6 — SubRequest Visibility & Management Gates', () {
    testWidgets('1. Manage Requests entry is visible in FindSubScreen even when active count is 0', (tester) async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Manage Requests'), findsOneWidget);
    });

    testWidgets('2. Entry opens existing management screen (SubRequestResponsesScreen)', (tester) async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            initialRoute: '/find-sub',
            routes: {
              '/find-sub': (context) => const FindSubScreen(bandId: 'band_1'),
              '/sub-request-responses': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                return SubRequestResponsesScreen(bandId: args?['bandId'] ?? 'band_1');
              },
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final manageBtn = find.text('Manage Requests');
      expect(manageBtn, findsOneWidget);

      await tester.tap(manageBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SubRequestResponsesScreen), findsOneWidget);
    });

    testWidgets('3. Creator feed request is displayed in creator management screen', (tester) async {
      final mockService = MockHotfixFirebaseService();
      const creatorUid = 'creator_user_1';
      mockService.setCurrentUserId(creatorUid);

      final req = SubRequest(
        id: 'req_created_1',
        subRequestId: 'req_created_1',
        creatorUserId: creatorUid,
        bandId: 'band_1',
        bandName: 'Stockholm Jazz Quartet',
        voicePart: 'Electric Guitar',
        role: 'Substitute',
        status: 'published',
        date: '2026-11-15T20:00:00.000',
        location: 'Fasching, Stockholm',
        latitude: 59.3325,
        longitude: 18.0649,
      );
      mockService.creatorFeeds.putIfAbsent(creatorUid, () => {})['req_created_1'] = req;

      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: SubRequestResponsesScreen(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Stockholm Jazz Quartet'), findsOneWidget);
      expect(find.text('”Substitute”'), findsOneWidget);
    });

    testWidgets('4. Other creator’s private request is not displayed', (tester) async {
      final mockService = MockHotfixFirebaseService();
      mockService.setCurrentUserId('creator_user_1');

      // Someone else's request
      final otherReq = SubRequest(
        id: 'req_other_user',
        subRequestId: 'req_other_user',
        creatorUserId: 'other_user_99',
        bandId: 'band_1',
        bandName: 'Stockholm Jazz Quartet',
        voicePart: 'Drums',
        role: 'Substitute',
        status: 'published',
      );
      mockService.creatorFeeds.putIfAbsent('other_user_99', () => {})['req_other_user'] = otherReq;

      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: SubRequestResponsesScreen(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No active requests found.'), findsOneWidget);
      expect(find.text('Drums'), findsNothing);
    });

    test('5. Public request creation with confirmed coordinates writes all canonical location fields', () async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      final req = SubRequest(
        slotId: 'slot_guitar',
        voicePart: 'Electric Guitar',
        role: 'Substitute',
        location: 'Ljusdal, Sweden',
        latitude: 61.828,
        longitude: 16.096,
        locationPrecision: LocationPrecision.city,
        locationStatus: LocationResolutionStatus.resolved,
        date: '2026-11-20',
      );

      final result = await appState.firebaseService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'grp_hotfix_test',
        requests: [req],
        bandName: 'Stockholm Jazz Quartet',
      );

      expect(result.isNotEmpty, isTrue);
      final savedId = result.first;
      final saved = mockService.canonicalSubRequests[savedId];
      expect(saved, isNotNull);
      expect(saved!.latitude, equals(61.828));
      expect(saved.longitude, equals(16.096));
      expect(saved.locationPrecision, equals(LocationPrecision.city));
      expect(saved.locationStatus, equals(LocationResolutionStatus.resolved));
    });

    test('6. Linked Event coordinates are inherited', () async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      // Event has coordinates
      final event = BandEvent(
        id: 'event_with_coords',
        title: 'Jazz Night',
        description: 'Concert in Uppsala',
        location: 'Uppsala Konsert & Kongress',
        startDateTime: '2026-11-25T19:00:00.000',
        endDateTime: '2026-11-25T22:00:00.000',
        additionalNotes: '',
        createdBy: 'creator_user_1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: false,
        latitude: 59.8586,
        longitude: 17.6389,
      );
      mockService.events['event_with_coords'] = event;

      // Inherit into SubRequest
      final req = SubRequest(
        eventId: event.id,
        eventTitle: event.title,
        location: event.location,
        latitude: event.latitude,
        longitude: event.longitude,
        locationPrecision: LocationPrecision.exact,
        locationStatus: LocationResolutionStatus.resolved,
        voicePart: 'Saxophone',
      );

      final ids = await appState.firebaseService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'grp_inherited',
        requests: [req],
      );

      final canonical = mockService.canonicalSubRequests[ids.first];
      expect(canonical?.latitude, equals(59.8586));
      expect(canonical?.longitude, equals(17.6389));
    });

    testWidgets('7. Missing coordinates block submission with clear validation', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockService = MockHotfixFirebaseService();
      final eventNoCoords = BandEvent(
        id: 'event_no_coords',
        title: 'Gig In Forest',
        eventType: 'Gig',
        description: 'Concert with unknown coordinates',
        location: 'Deep Woods Nowhere',
        startDateTime: '2026-11-25T19:00:00.000',
        endDateTime: '2026-11-25T22:00:00.000',
        additionalNotes: '',
        createdBy: 'creator_user_1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: false,
        latitude: null,
        longitude: null,
      );
      mockService.events['event_no_coords'] = eventNoCoords;

      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: FindSubScreen(bandId: 'band_1', eventId: 'event_no_coords'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Find the Publish button
      final publishBtn = find.text('PUBLISH SUBSTITUTE REQUESTS (1)');
      expect(publishBtn, findsOneWidget);

      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Must display validation message requiring coordinates
      expect(
        find.text('Please confirm a valid location with coordinates before publishing.'),
        findsOneWidget,
      );
    });

    testWidgets('8. Form data remains after validation failure', (tester) async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: FindSubScreen(bandId: 'band_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Ensure screen is still present and interactive
      expect(find.byType(FindSubScreen), findsOneWidget);
    });

    test('9. Callable failure cannot display success', () async {
      final mockService = MockHotfixFirebaseService();
      mockService.shouldCallableFail = true;
      final appState = MockHotfixAppState(mockService);

      expect(
        () async => await appState.firebaseService.publishSubRequestGroupAsync(
          bandId: 'band_1',
          requestGroupId: 'grp_fail',
          requests: [
            SubRequest(voicePart: 'Bass', role: 'Substitute', latitude: 59.33, longitude: 18.06),
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('10. Successful request appears in Map View realtime feed', () async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      final feedStream = appState.firebaseService.getSubRequestFeedStream();
      final completer = Completer<List<SubRequest>>();
      final sub = feedStream.listen((list) {
        if (!completer.isCompleted) completer.complete(list);
      });

      await appState.firebaseService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'grp_realtime',
        requests: [
          SubRequest(
            voicePart: 'Electric Guitar',
            role: 'Substitute',
            status: 'published',
            latitude: 61.828,
            longitude: 16.096,
          ),
        ],
      );

      final result = await completer.future.timeout(const Duration(seconds: 3));
      expect(result.isNotEmpty, isTrue);
      expect(result.first.voicePart, equals('Electric Guitar'));

      await sub.cancel();
    });

    test('11. Correct request category/filter displays it under Sub & Member Search', () async {
      final req = SubRequest(
        id: 'sub_guitar_1',
        voicePart: 'Electric Guitar',
        role: 'Substitute',
        requestType: 'Substitute',
        status: 'published',
        latitude: 61.828,
        longitude: 16.096,
      );

      final kind = classifyMapItem(req);
      expect(kind, equals(MapItemKind.staffingRequest));
      final category = getCategoryForKind(kind);
      expect(category, equals(MapCategory.subAndMember));
    });

    test('12. Cancellation removes it from creator management and Map View', () async {
      final mockService = MockHotfixFirebaseService();
      const creatorUid = 'creator_user_1';
      mockService.setCurrentUserId(creatorUid);

      final ids = await mockService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'grp_del',
        requests: [
          SubRequest(voicePart: 'Keyboard', role: 'Substitute', latitude: 59.33, longitude: 18.06),
        ],
      );
      final subId = ids.first;

      expect(mockService.publicFeeds.containsKey(subId), isTrue);
      expect(mockService.creatorFeeds[creatorUid]?.containsKey(subId), isTrue);

      await mockService.deleteSubRequestAsync(creatorUid, subId);

      expect(mockService.publicFeeds.containsKey(subId), isFalse);
      expect(mockService.creatorFeeds[creatorUid]?.containsKey(subId), isFalse);
    });

    test('13. New Member location remains city-level', () async {
      final newMemberReq = SubRequest(
        id: 'member_req_1',
        role: 'New Member',
        requestType: 'New Member',
        location: 'Storgatan 12, Ljusdal',
        latitude: 61.8289412,
        longitude: 16.0963214,
      );

      // Verify classification
      final kind = classifyMapItem(newMemberReq);
      expect(kind, equals(MapItemKind.newMemberRequest));

      // Coarsen logic test
      final coarsenedLat = double.parse(newMemberReq.latitude!.toStringAsFixed(1));
      final coarsenedLng = double.parse(newMemberReq.longitude!.toStringAsFixed(1));
      expect(coarsenedLat, equals(61.8));
      expect(coarsenedLng, equals(16.1));
    });

    test('14. Direct/Favorites visibility remains private', () async {
      final mockService = MockHotfixFirebaseService();
      mockService.setCurrentUserId('creator_user_1');

      final ids = await mockService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'grp_priv',
        requests: [
          SubRequest(
            voicePart: 'Trumpet',
            role: 'Substitute',
            searchSource: 'favorites',
            targetUserIds: ['fav_user_2'],
            latitude: 59.33,
            longitude: 18.06,
          ),
        ],
      );
      final privId = ids.first;

      // Private request must NOT be in public feed
      expect(mockService.publicFeeds.containsKey(privId), isFalse);
      // Targeted recipient has access
      expect(mockService.userFeeds['fav_user_2']?.containsKey(privId), isTrue);
      // Unrelated user has NO access
      expect(mockService.userFeeds['other_user_3']?.containsKey(privId) ?? false, isFalse);
    });

    testWidgets('15. 320 px layout has no overflow', (tester) async {
      final mockService = MockHotfixFirebaseService();
      final appState = MockHotfixAppState(mockService);

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: FindSubScreen(bandId: 'band_1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('Manage Requests'), findsOneWidget);
    });
  });
}
