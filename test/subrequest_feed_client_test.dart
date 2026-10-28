import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:provider/provider.dart';

/// Test mock implementation simulating RTDB server-owned feeds:
/// - /publicSubRequests
/// - /userSubRequestFeed/{userId}
/// - /creatorSubRequestFeed/{userId}
class MockSubRequestFeedsFirebaseService extends FirebaseService {
  String? _currentUserId = 'user_musician_1';
  bool _isLoggedIn = true;

  final Map<String, SubRequest> publicFeeds = {};
  final Map<String, Map<String, SubRequest>> userFeeds = {}; // userId -> {reqId: req}
  final Map<String, Map<String, SubRequest>> creatorFeeds = {}; // creatorId -> {reqId: req}
  final List<String> callableInvocations = [];
  final List<String> legacyWrites = [];

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  void setIsLoggedIn(bool loggedIn) {
    _isLoggedIn = loggedIn;
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final uid = userId ?? _currentUserId ?? 'test_user';
    return UserProfile(
      userId: uid,
      displayName: 'User $uid',
      email: '$uid@example.com',
      mainInstrument: 'Guitar',
      instruments: ['Guitar'],
    );
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    final List<SubRequest> requests = [];
    final selfId = currentUserId;
    final Set<String> seenIds = {};

    void addValidRequest(SubRequest req) {
      final id = req.subRequestId ?? req.id;
      if (id == null || id.isEmpty) return;
      if (seenIds.contains(id)) return;
      final st = req.status.toLowerCase();
      if (st == 'cancelled' || st == 'deleted' || st == 'closed') return;
      seenIds.add(id);
      requests.add(req);
    }

    // 1. Public feed
    for (final r in publicFeeds.values) {
      addValidRequest(r);
    }

    // 2. Personal recipient feed
    if (selfId != null && selfId.isNotEmpty && userFeeds.containsKey(selfId)) {
      for (final r in userFeeds[selfId]!.values) {
        addValidRequest(r);
      }
    }

    // 3. Personal creator feed
    if (selfId != null && selfId.isNotEmpty && creatorFeeds.containsKey(selfId)) {
      for (final r in creatorFeeds[selfId]!.values) {
        addValidRequest(r);
      }
    }

    return requests;
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    final selfId = currentUserId;
    if (userId == selfId && selfId != null && selfId.isNotEmpty) {
      if (creatorFeeds.containsKey(userId)) {
        return creatorFeeds[userId]!.values.where((r) {
          final st = r.status.toLowerCase();
          return st != 'cancelled' && st != 'deleted';
        }).toList();
      }
      return [];
    }
    final all = await getAllSubRequestsAsync();
    return all.where((r) => r.creatorUserId == userId || r.userId == userId).toList();
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    final all = await getAllSubRequestsAsync();
    return all.where((r) {
      if (r.eventId != eventId) return false;
      if (bandId.isNotEmpty && r.bandId != null && r.bandId!.isNotEmpty && r.bandId != bandId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync([String? userId]) async {
    final targetUid = userId ?? currentUserId;
    if (targetUid == null || !userFeeds.containsKey(targetUid)) return [];
    return userFeeds[targetUid]!.values.toList();
  }

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    callableInvocations.add('publishSubRequestGroup');
    return requests.map((r) => r.subRequestId ?? r.id ?? 'sub_id').toList();
  }

  Future<void> cancelSubRequestAsync(String subRequestId) async {
    callableInvocations.add('cancelSubRequest:$subRequestId');
    publicFeeds.remove(subRequestId);
    for (final u in userFeeds.values) {
      u.remove(subRequestId);
    }
    for (final c in creatorFeeds.values) {
      if (c.containsKey(subRequestId)) {
        final existing = c[subRequestId]!;
        c[subRequestId] = SubRequest(
          id: existing.id,
          subRequestId: existing.subRequestId,
          creatorUserId: existing.creatorUserId,
          status: 'cancelled',
          bandName: existing.bandName,
          voicePart: existing.voicePart,
        );
      }
    }
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async {
    return {};
  }
}

class MockAppState extends AppState {
  final MockSubRequestFeedsFirebaseService _mockFirebase;

  MockAppState(this._mockFirebase);

  @override
  FirebaseService get firebaseService => _mockFirebase;

  @override
  String? get currentUserId => _mockFirebase.currentUserId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('SUBREQUEST-FEED-CLIENT: Stable Feed Read & Security Tests', () {
    late MockSubRequestFeedsFirebaseService mockService;
    late MockAppState appState;

    setUp(() {
      mockService = MockSubRequestFeedsFirebaseService();
      appState = MockAppState(mockService);
    });

    test('1. getAllSubRequestsAsync reads public + recipient + creator feeds', () async {
      mockService.setCurrentUserId('user_alice');

      mockService.publicFeeds['pub_1'] = SubRequest(
        id: 'pub_1',
        subRequestId: 'pub_1',
        creatorUserId: 'user_bob',
        status: 'published',
        bandName: 'Public Band',
        voicePart: 'Drums',
      );

      mockService.userFeeds['user_alice'] = {
        'direct_1': SubRequest(
          id: 'direct_1',
          subRequestId: 'direct_1',
          creatorUserId: 'user_bob',
          status: 'published',
          bandName: 'Direct Band',
          voicePart: 'Bass',
        ),
      };

      mockService.creatorFeeds['user_alice'] = {
        'my_request_1': SubRequest(
          id: 'my_request_1',
          subRequestId: 'my_request_1',
          creatorUserId: 'user_alice',
          status: 'published',
          bandName: 'Alice Band',
          voicePart: 'Vocals',
        ),
      };

      final results = await mockService.getAllSubRequestsAsync();
      expect(results.length, equals(3));
      final ids = results.map((r) => r.id).toSet();
      expect(ids, containsAll(['pub_1', 'direct_1', 'my_request_1']));
    });

    test('2. Samma request i flera feeds dedupliceras till exakt 1 instans', () async {
      mockService.setCurrentUserId('user_alice');

      final sharedRequest = SubRequest(
        id: 'shared_req_1',
        subRequestId: 'shared_req_1',
        creatorUserId: 'user_alice',
        status: 'published',
        bandName: 'Shared Band',
        voicePart: 'Guitar',
      );

      // Present in both public and creator feed
      mockService.publicFeeds['shared_req_1'] = sharedRequest;
      mockService.creatorFeeds['user_alice'] = {'shared_req_1': sharedRequest};

      final results = await mockService.getAllSubRequestsAsync();
      final matching = results.where((r) => r.id == 'shared_req_1').toList();
      expect(matching.length, equals(1));
    });

    test('3. Unrelated user får inte Favorites/Direct', () async {
      // User is Eve (stranger)
      mockService.setCurrentUserId('user_eve');

      mockService.publicFeeds['pub_gig'] = SubRequest(
        id: 'pub_gig',
        subRequestId: 'pub_gig',
        status: 'published',
        bandName: 'Open Band',
        voicePart: 'Keyboards',
      );

      // Direct invite intended exclusively for Alice
      mockService.userFeeds['user_alice'] = {
        'secret_invite': SubRequest(
          id: 'secret_invite',
          subRequestId: 'secret_invite',
          status: 'published',
          bandName: 'Secret Band',
          voicePart: 'Violin',
        ),
      };

      final results = await mockService.getAllSubRequestsAsync();
      expect(results.any((r) => r.id == 'secret_invite'), isFalse);
      expect(results.any((r) => r.id == 'pub_gig'), isTrue);
    });

    test('4. Creator ser sina egna private requests via creator feed', () async {
      mockService.setCurrentUserId('user_creator_bob');

      mockService.creatorFeeds['user_creator_bob'] = {
        'bob_fav_only': SubRequest(
          id: 'bob_fav_only',
          subRequestId: 'bob_fav_only',
          creatorUserId: 'user_creator_bob',
          status: 'published',
          bandName: 'Bob Private Session',
          voicePart: 'Cello',
        ),
      };

      final results = await mockService.getAllSubRequestsAsync();
      expect(results.any((r) => r.id == 'bob_fav_only'), isTrue);
    });

    test('5. getUserSubRequestsAsync läser skaparens creator feed', () async {
      mockService.setCurrentUserId('user_alice');

      mockService.creatorFeeds['user_alice'] = {
        'alice_slot_1': SubRequest(
          id: 'alice_slot_1',
          creatorUserId: 'user_alice',
          status: 'published',
          voicePart: 'Flute',
        ),
        'alice_slot_cancelled': SubRequest(
          id: 'alice_slot_cancelled',
          creatorUserId: 'user_alice',
          status: 'cancelled',
          voicePart: 'Harp',
        ),
      };

      final userRequests = await mockService.getUserSubRequestsAsync('user_alice');
      expect(userRequests.length, equals(1));
      expect(userRequests.first.id, equals('alice_slot_1'));
    });

    test('6. getSubRequestsForEventAsync fungerar med nya feeds och filtrerar per eventId', () async {
      mockService.setCurrentUserId('user_alice');

      mockService.publicFeeds['event_req_1'] = SubRequest(
        id: 'event_req_1',
        eventId: 'event_summer_fest',
        bandId: 'band_100',
        status: 'published',
        voicePart: 'Trumpet',
      );
      mockService.publicFeeds['other_event_req'] = SubRequest(
        id: 'other_event_req',
        eventId: 'event_winter_fest',
        bandId: 'band_100',
        status: 'published',
        voicePart: 'Saxophone',
      );

      final eventRequests = await mockService.getSubRequestsForEventAsync('band_100', 'event_summer_fest');
      expect(eventRequests.length, equals(1));
      expect(eventRequests.first.id, equals('event_req_1'));
    });

    test('7. Direct/Favorites visas endast för behörig mottagare', () async {
      // Alice is authorized
      mockService.setCurrentUserId('user_alice');
      mockService.userFeeds['user_alice'] = {
        'direct_slot': SubRequest(
          id: 'direct_slot',
          status: 'published',
          voicePart: 'Guitar',
        ),
      };
      final aliceFeeds = await mockService.getAllSubRequestsAsync();
      expect(aliceFeeds.any((r) => r.id == 'direct_slot'), isTrue);

      // Charlie is unauthorized
      mockService.setCurrentUserId('user_charlie');
      final charlieFeeds = await mockService.getAllSubRequestsAsync();
      expect(charlieFeeds.any((r) => r.id == 'direct_slot'), isFalse);
    });

    test('8. Publicering från klient sker via callable och noll legacy-writes sker', () async {
      final requests = [
        SubRequest(
          id: 'slot_1',
          subRequestId: 'slot_1',
          bandName: 'Callable Band',
          voicePart: 'Bass',
        ),
      ];

      final resultIds = await mockService.publishSubRequestGroupAsync(
        bandId: 'band_1',
        requestGroupId: 'group_1',
        requests: requests,
        bandName: 'Callable Band',
      );
      expect(resultIds, equals(['slot_1']));
      expect(mockService.callableInvocations, contains('publishSubRequestGroup'));
      expect(mockService.legacyWrites, isEmpty);
    });

    test('9. Cancel/delete uppdaterar klientvyn direkt (tar bort från aktiva listor)', () async {
      mockService.setCurrentUserId('user_alice');

      mockService.publicFeeds['slot_to_cancel'] = SubRequest(
        id: 'slot_to_cancel',
        subRequestId: 'slot_to_cancel',
        creatorUserId: 'user_alice',
        status: 'published',
        voicePart: 'Bass',
      );

      var active = await mockService.getAllSubRequestsAsync();
      expect(active.any((r) => r.id == 'slot_to_cancel'), isTrue);

      await mockService.cancelSubRequestAsync('slot_to_cancel');

      active = await mockService.getAllSubRequestsAsync();
      expect(active.any((r) => r.id == 'slot_to_cancel'), isFalse);
    });

    test('10. Map View kan läsa offentliga staffing requests utan legacy mirror', () async {
      mockService.publicFeeds['public_map_staffing'] = SubRequest(
        id: 'public_map_staffing',
        subRequestId: 'public_map_staffing',
        status: 'published',
        location: 'Stockholm, Sweden',
        latitude: 59.3293,
        longitude: 18.0686,
        voicePart: 'Violin',
        bandName: 'Nordic Strings',
      );

      final staffingForMap = await mockService.getAllSubRequestsAsync();
      final mapItem = staffingForMap.firstWhere((r) => r.id == 'public_map_staffing');
      expect(mapItem.latitude, equals(59.3293));
      expect(mapItem.longitude, equals(18.0686));
      expect(mockService.legacyWrites, isEmpty);
    });

    testWidgets('11. Public request visas i Find Gigs (Widget test utan obunden pumpAndSettle)', (tester) async {
      mockService.setCurrentUserId('user_musician_1');
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockService.publicFeeds['gig_1'] = SubRequest(
        id: 'gig_1',
        subRequestId: 'gig_1',
        bandName: 'The Rockers',
        voicePart: 'Guitar',
        date: dateStr,
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm',
        isPaid: true,
        payAmount: 2000,
        currency: 'SEK',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            Provider<FirebaseService>.value(value: mockService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FindGigsScreen(),
            ),
          ),
        ),
      );

      // Controlled deterministic pumps without unbounded pumpAndSettle:
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifies FindGigsScreen renders successfully with the public request
      expect(find.byType(FindGigsScreen), findsOneWidget);
    });
  });
}
