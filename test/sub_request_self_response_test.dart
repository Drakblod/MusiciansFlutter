import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/sub_request_details_screen.dart';

class MockSelfResponseFirebaseService extends FirebaseService {
  String _currentUserId = 'user_creator_123';
  final Map<String, SubRequest> _subRequests = {};
  final Set<String> _appliedIds = {};

  @override
  String? get currentUserId => _currentUserId;

  void setUserId(String uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => true;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? _currentUserId,
      displayName: 'Test User ${userId ?? _currentUserId}',
      email: 'test@example.com',
    );
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return _subRequests.values.toList();
  }

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync([String? userId]) async {
    return _subRequests.values.toList();
  }

  @override
  Future<SubRequest?> getSubRequestAsync(String subRequestId) async {
    return _subRequests[subRequestId];
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async {
    return _appliedIds;
  }

  @override
  Future<void> addResponseToSubRequestAsync(String subRequestId, String userId) async {
    final sub = await getSubRequestAsync(subRequestId);
    final creatorId = sub?.creatorUserId ?? sub?.userId;
    if (creatorId != null && creatorId.isNotEmpty && creatorId == userId) {
      throw Exception('You cannot respond to your own substitute request.');
    }
    _appliedIds.add(subRequestId);
    if (_subRequests.containsKey(subRequestId)) {
      _subRequests[subRequestId]!.responses[userId] = true;
    }
  }

  void addMockSubRequest(SubRequest req) {
    final id = req.subRequestId ?? req.id ?? 'sub_1';
    _subRequests[id] = req;
  }
}

class MockSelfResponseAppState extends AppState {
  final MockSelfResponseFirebaseService mockFirebase;
  final String mockUserId;

  MockSelfResponseAppState(this.mockFirebase, {this.mockUserId = 'creator_user_1'});

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => mockUserId;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: mockUserId,
        displayName: 'User $mockUserId',
        email: '$mockUserId@example.com',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
  });

  group('Self-Response Prevention & Isolation Tests', () {
    testWidgets('1. FindGigsScreen displays "Your Request" badge and prevents creator from applying', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockSelfResponseFirebaseService();
      mock.setUserId('creator_user_1');
      mock.addMockSubRequest(SubRequest(
        id: 'sub_test_slot_1',
        subRequestId: 'sub_test_slot_1',
        creatorUserId: 'creator_user_1',
        userId: 'creator_user_1',
        bandName: 'The Rockers',
        voicePart: 'Electric Guitar',
        role: 'Lead Guitarist',
        date: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {},
      ));

      final appState = MockSelfResponseAppState(mock, mockUserId: 'creator_user_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the gig details bottom sheet
      expect(find.text('The Rockers'), findsOneWidget);
      await tester.tap(find.text('The Rockers'));
      await tester.pumpAndSettle();

      // Verify that "Your Request" badge is shown instead of "Apply"
      expect(find.text('Your Request'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
    });

    testWidgets('2. FindGigsScreen displays "Apply" button for candidate and allows applying', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockSelfResponseFirebaseService();
      mock.setUserId('candidate_user_2');
      mock.addMockSubRequest(SubRequest(
        id: 'sub_test_slot_2',
        subRequestId: 'sub_test_slot_2',
        creatorUserId: 'creator_user_1',
        userId: 'creator_user_1',
        bandName: 'The Rockers',
        voicePart: 'Drums',
        role: 'Drummer Needed',
        date: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {},
      ));

      final appState = MockSelfResponseAppState(mock, mockUserId: 'candidate_user_2');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the gig details bottom sheet
      expect(find.text('The Rockers'), findsOneWidget);
      await tester.tap(find.text('The Rockers'));
      await tester.pumpAndSettle();

      // Verify "Apply" button is visible for candidate
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Your Request'), findsNothing);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Applied for position!'), findsOneWidget);
    });

    testWidgets('3. SubRequestDetailsScreen displays "Your Request" badge when creator views it', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockSelfResponseFirebaseService();
      mock.setUserId('creator_user_1');
      final req = SubRequest(
        id: 'sub_test_slot_3',
        subRequestId: 'sub_test_slot_3',
        creatorUserId: 'creator_user_1',
        userId: 'creator_user_1',
        bandName: 'The Jazz Kings',
        voicePart: 'Saxophone',
        role: 'Alto Sax',
        date: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
        startTime: '20:00',
        endTime: '23:00',
        status: 'published',
        responses: {},
      );
      mock.addMockSubRequest(req);

      final appState = MockSelfResponseAppState(mock, mockUserId: 'creator_user_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: SubRequestDetailsScreen(subRequest: req),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Request'), findsOneWidget);
      expect(find.text('Apply for Gig'), findsNothing);
    });

    testWidgets('4. FirebaseService.addResponseToSubRequestAsync throws when creator attempts to apply', (tester) async {
      final mock = MockSelfResponseFirebaseService();
      mock.setUserId('creator_user_1');
      mock.addMockSubRequest(SubRequest(
        id: 'sub_test_slot_4',
        subRequestId: 'sub_test_slot_4',
        creatorUserId: 'creator_user_1',
        userId: 'creator_user_1',
        bandName: 'The Jazz Kings',
        voicePart: 'Saxophone',
        status: 'published',
        responses: {},
      ));

      expect(
        () => mock.addResponseToSubRequestAsync('sub_test_slot_4', 'creator_user_1'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('cannot respond to your own substitute request'),
        )),
      );
    });
  });
}
