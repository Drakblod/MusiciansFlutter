// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/views/home_screen.dart';

class MockFirebaseServiceForBadges extends FirebaseService {
  final Map<String, int> markedFeatures = {};
  Map<String, String> userBands = {'band_1': 'Test Band'};

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => userBands;

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async => [];

  @override
  Future<void> markFeatureNotificationsRead(String featureId) async {
    markedFeatures[featureId] = (markedFeatures[featureId] ?? 0) + 1;
  }

  @override
  Future<void> markFeatureNotificationsReadAsync(String featureId) async {
    markedFeatures[featureId] = (markedFeatures[featureId] ?? 0) + 1;
  }
}

class MockAppStateForBadges extends AppState {
  final MockFirebaseServiceForBadges _service = MockFirebaseServiceForBadges();
  List<String> _bubbles;
  List<AppNotification> _mockNotifications = [];

  MockAppStateForBadges({List<String>? bubbles})
      : _bubbles = bubbles ?? ['find_musicians', 'find_gigs', 'band_room'];

  @override
  List<AppNotification> get userNotifications => _mockNotifications;

  @override
  FirebaseService get firebaseService => _service;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'badge_test_user',
        displayName: 'Badge Tester',
      );

  @override
  String? get currentUserId => 'badge_test_user';

  @override
  List<String> get selectedBubbles => _bubbles;

  void setNotificationsForTest(List<AppNotification> notifs) {
    _mockNotifications = notifs;
    notifyListeners();
  }

  @override
  Future<void> markFeatureAsRead(String featureId) async {
    _mockNotifications = _mockNotifications.map((n) {
      if (n.effectiveFeatureId == featureId && !n.isRead) {
        return n.copyWith(isRead: true, readAt: DateTime.now().millisecondsSinceEpoch);
      }
      return n;
    }).toList();
    notifyListeners();
    await _service.markFeatureNotificationsReadAsync(featureId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('HOME-ACTIVITY-BADGES-01: Centralized Mapping and AppState Tests', () {
    test('1. Type-to-feature mapping resolves known and legacy types properly', () {
      // Direct explicit featureId takes precedence
      expect(
        AppNotification.resolveFeatureId('custom_type', 'find_gigs'),
        'find_gigs',
      );

      // Find Gigs types
      expect(AppNotification.resolveFeatureId('sub_request_invite'), 'find_gigs');
      expect(AppNotification.resolveFeatureId('sub_request'), 'find_gigs');
      expect(AppNotification.resolveFeatureId('grouped_sub_request'), 'find_gigs');
      expect(AppNotification.resolveFeatureId('gig_finalized'), 'find_gigs');

      // Find Musicians types
      expect(AppNotification.resolveFeatureId('sub_request_response'), 'find_musicians');
      expect(AppNotification.resolveFeatureId('sub_response'), 'find_musicians');

      // Collabs types
      expect(AppNotification.resolveFeatureId('session_application'), 'collabs');
      expect(AppNotification.resolveFeatureId('session_application_status'), 'collabs');
      expect(AppNotification.resolveFeatureId('session_message'), 'collabs');

      // Band Room types
      expect(AppNotification.resolveFeatureId('band_room_message'), 'band_room');
      expect(AppNotification.resolveFeatureId('band_section_chat'), 'band_room');
      expect(AppNotification.resolveFeatureId('event_invite'), 'band_room');
      expect(AppNotification.resolveFeatureId('event_reminder'), 'band_room');
      expect(AppNotification.resolveFeatureId('event_threshold'), 'band_room');
      expect(AppNotification.resolveFeatureId('event_milestone'), 'band_room');
      expect(AppNotification.resolveFeatureId('band_file_uploaded'), 'band_room');

      // Messages
      expect(AppNotification.resolveFeatureId('direct_message'), 'messages');

      // Unknown or unrelated
      expect(AppNotification.resolveFeatureId('random_unknown_type'), isNull);
      expect(AppNotification.resolveFeatureId('marketplace_sale'), isNull);
    });

    test('2. Unread notification derives correct feature unread count and hasUnreadActivity', () {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n1',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig invite',
          body: 'You are invited',
          createdAt: now,
          isRead: false,
        ),
      ]);

      expect(appState.hasUnreadActivity('find_gigs'), isTrue);
      expect(appState.unreadActivityCount('find_gigs'), 1);
      expect(appState.hasUnreadActivity('find_musicians'), isFalse);
    });

    test('3. Read notification creates no activity dot/count', () {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n2',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig invite',
          body: 'You are invited',
          createdAt: now,
          isRead: true,
          readAt: now,
        ),
      ]);

      expect(appState.hasUnreadActivity('find_gigs'), isFalse);
      expect(appState.unreadActivityCount('find_gigs'), 0);
    });

    test('4. Multiple notifications for one feature collapse to hasUnreadActivity = true', () {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n3',
          type: 'band_room_message',
          category: 'messages',
          title: 'Chat 1',
          body: 'Hey',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n4',
          type: 'band_file_uploaded',
          category: 'band',
          title: 'File 1',
          body: 'Score.pdf',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n5',
          type: 'event_invite',
          category: 'events',
          title: 'Rehearsal',
          body: 'RSVP needed',
          createdAt: now,
          isRead: false,
        ),
      ]);

      expect(appState.hasUnreadActivity('band_room'), isTrue);
      expect(appState.unreadActivityCount('band_room'), 3);
    });

    test('5. All 4 features correctly receive notifications independently', () {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_gig',
          type: 'grouped_sub_request',
          category: 'requests',
          title: 'Gig',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_mus',
          type: 'sub_request_response',
          category: 'requests',
          title: 'Musician applied',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_collab',
          type: 'session_application',
          category: 'collabs',
          title: 'Collab applied',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band Room',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      expect(appState.hasUnreadActivity('find_gigs'), isTrue);
      expect(appState.hasUnreadActivity('find_musicians'), isTrue);
      expect(appState.hasUnreadActivity('collabs'), isTrue);
      expect(appState.hasUnreadActivity('band_room'), isTrue);
    });
  });

  group('HOME-ACTIVITY-BADGES-01: UI Badge Rendering & Negative Tests', () {
    testWidgets('6. Negative assertions: Event Calendar, Profiles, Marketplace never display dots', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForBadges(
        bubbles: ['find_musicians', 'find_gigs', 'band_room'],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_g',
          type: 'sub_request',
          category: 'requests',
          title: 'Gig',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Negative assertions: verify that Profiles, Event Calendar, Marketplace never render 'new activity' semantics
      expect(
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.contains('new activity') ?? false) && (w.properties.label?.startsWith('Profiles') ?? false)),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.contains('new activity') ?? false) && (w.properties.label?.startsWith('Event Calendar') ?? false)),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.contains('new activity') ?? false) && (w.properties.label?.startsWith('Marketplace') ?? false)),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.contains('new activity') ?? false) && (w.properties.label?.startsWith('Events') ?? false)),
        findsNothing,
      );
    });

    testWidgets('7. Standard Home View: Action cards render red dot with semantics and no number text', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForBadges(
        bubbles: ['browse_musicians', 'create_event', 'marketplace'], // non-active bubbles so cards stay below
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_collab',
          type: 'session_application',
          category: 'collabs',
          title: 'Collab invite',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Collabs has new activity semantics
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Collabs, new activity'),
        findsOneWidget,
      );

      // Red dot has NO number string displayed
      expect(find.text('1'), findsNothing);
    });

    testWidgets('8. Realtime updates: Marking notification read removes dot immediately', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForBadges(
        bubbles: ['find_gigs', 'band_room', 'find_musicians'],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_gig',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Find Gigs, new activity'),
        findsOneWidget,
      );

      // Mark notification as read
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_gig',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig',
          body: '',
          createdAt: now,
          isRead: true,
          readAt: now,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Badge dot should be gone immediately
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Find Gigs, new activity'),
        findsNothing,
      );
    });

    testWidgets('9. Isolation: Marking one feature read leaves other feature badges intact', (tester) async {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;

      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_gig',
          type: 'gig_finalized',
          category: 'requests',
          title: 'Gig finalized',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band message',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      expect(appState.hasUnreadActivity('find_gigs'), isTrue);
      expect(appState.hasUnreadActivity('band_room'), isTrue);

      // Optimistic markFeatureAsRead for find_gigs
      await appState.markFeatureAsRead('find_gigs');

      expect(appState.hasUnreadActivity('find_gigs'), isFalse);
      expect(appState.hasUnreadActivity('band_room'), isTrue);
    });

    testWidgets('10. Layout verification at 320 px width produces no overflow or layout shift', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForBadges(
        bubbles: ['find_musicians', 'find_gigs', 'band_room'],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_all_1',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig invite',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_all_2',
          type: 'sub_request_response',
          category: 'requests',
          title: 'Musician apply',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_all_3',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band room',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify no RenderFlex overflow error is thrown
      expect(tester.takeException(), isNull);
    });
  });

  group('HOME-NAVIGATION-CLEARING-01: Home Action Navigation & Isolation', () {
    Widget buildTestApp(MockAppStateForBadges appState) {
      return ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          home: const Scaffold(body: HomeScreen()),
          routes: {
            '/find-gigs': (context) => const Scaffold(body: Text('Find Gigs Screen')),
            '/find-sub': (context) => const Scaffold(body: Text('Find Sub Screen')),
            '/collabs': (context) => const Scaffold(body: Text('Collabs Screen')),
            '/band-room': (context) => const Scaffold(body: Text('Band Room Screen')),
          },
        ),
      );
    }

    testWidgets('11. Find Gigs tap completes navigation, clears only find_gigs, removes red dot immediately', (tester) async {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_gig',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig invite',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_collab',
          type: 'session_application',
          category: 'collabs',
          title: 'Collab app',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('find_gigs'), isTrue);
      expect(appState.hasUnreadActivity('collabs'), isTrue);

      // Tap Find Gigs
      final findGigsCard = find.text('Find Gigs');
      expect(findGigsCard, findsOneWidget);
      await tester.tap(findGigsCard);
      await tester.pumpAndSettle();

      // Successfully reached Find Gigs Screen
      expect(find.text('Find Gigs Screen'), findsOneWidget);

      // Navigate back to Home
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Find Gigs dot is cleared immediately; collabs remains unread
      expect(appState.hasUnreadActivity('find_gigs'), isFalse);
      expect(appState.hasUnreadActivity('collabs'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['find_gigs'], 1);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['collabs'], isNull);
    });

    testWidgets('12. Collabs tap completes navigation, clears only collabs, removes red dot immediately', (tester) async {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_collab',
          type: 'session_application',
          category: 'collabs',
          title: 'Collab app',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_musician',
          type: 'sub_request_response',
          category: 'requests',
          title: 'Musician apply',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('collabs'), isTrue);
      expect(appState.hasUnreadActivity('find_musicians'), isTrue);

      // Tap Collabs
      final collabsCard = find.text('Collabs');
      expect(collabsCard, findsOneWidget);
      await tester.tap(collabsCard);
      await tester.pumpAndSettle();

      // Successfully reached Collabs Screen
      expect(find.text('Collabs Screen'), findsOneWidget);

      // Navigate back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Collabs dot is cleared; find_musicians dot remains
      expect(appState.hasUnreadActivity('collabs'), isFalse);
      expect(appState.hasUnreadActivity('find_musicians'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['collabs'], 1);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['find_musicians'], isNull);
    });

    testWidgets('13. Find Musicians tap completes navigation, clears only find_musicians, removes red dot immediately', (tester) async {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_musician',
          type: 'sub_request_response',
          category: 'requests',
          title: 'Musician apply',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band message',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('find_musicians'), isTrue);
      expect(appState.hasUnreadActivity('band_room'), isTrue);

      // Tap Find Musicians
      final findMusiciansCard = find.byIcon(Icons.people_outline_rounded);
      expect(findMusiciansCard, findsOneWidget);
      await tester.tap(findMusiciansCard);
      await tester.pumpAndSettle();

      // Successfully reached Find Sub Screen
      expect(find.text('Find Sub Screen'), findsOneWidget);

      // Navigate back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // find_musicians dot is cleared; band_room dot remains
      expect(appState.hasUnreadActivity('find_musicians'), isFalse);
      expect(appState.hasUnreadActivity('band_room'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['find_musicians'], 1);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['band_room'], isNull);
    });

    testWidgets('14. Band Room tap with active band completes navigation, clears only band_room, removes red dot', (tester) async {
      final appState = MockAppStateForBadges();
      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band message',
          body: '',
          createdAt: now,
          isRead: false,
        ),
        AppNotification(
          id: 'n_gig',
          type: 'sub_request_invite',
          category: 'requests',
          title: 'Gig invite',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('band_room'), isTrue);
      expect(appState.hasUnreadActivity('find_gigs'), isTrue);

      // Tap Band Room
      final bandRoomCard = find.text('Band Room');
      expect(bandRoomCard, findsOneWidget);
      await tester.tap(bandRoomCard);
      await tester.pumpAndSettle();

      // Successfully reached Band Room Screen
      expect(find.text('Band Room Screen'), findsOneWidget);

      // Navigate back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // band_room dot is cleared; find_gigs dot remains
      expect(appState.hasUnreadActivity('band_room'), isFalse);
      expect(appState.hasUnreadActivity('find_gigs'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['band_room'], 1);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['find_gigs'], isNull);
    });

    testWidgets('15. Band Room blocked when no active band: does not navigate and does NOT clear activity', (tester) async {
      final appState = MockAppStateForBadges();
      // Configure user with NO bands
      (appState.firebaseService as MockFirebaseServiceForBadges).userBands = {};

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band message',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('band_room'), isTrue);

      // Tap Band Room
      final bandRoomCard = find.text('Band Room');
      await tester.tap(bandRoomCard);
      await tester.pumpAndSettle();

      // Did NOT navigate to Band Room Screen
      expect(find.text('Band Room Screen'), findsNothing);
      expect(find.text('You need to be part of a band to access Band Room.'), findsOneWidget);

      // Red dot remains, markFeatureAsRead was NOT called
      expect(appState.hasUnreadActivity('band_room'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['band_room'], isNull);
    });

    testWidgets('16. Band selector dismissed without picking a band: does NOT navigate and does NOT clear activity', (tester) async {
      final appState = MockAppStateForBadges();
      // Configure user with multiple bands
      (appState.firebaseService as MockFirebaseServiceForBadges).userBands = {
        'band_1': 'Alpha Band',
        'band_2': 'Beta Band',
      };

      final now = DateTime.now().millisecondsSinceEpoch;
      appState.setNotificationsForTest([
        AppNotification(
          id: 'n_band',
          type: 'band_room_message',
          category: 'messages',
          title: 'Band message',
          body: '',
          createdAt: now,
          isRead: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(appState));
      await tester.pumpAndSettle();

      expect(appState.hasUnreadActivity('band_room'), isTrue);

      // Tap Band Room
      final bandRoomCard = find.text('Band Room');
      await tester.tap(bandRoomCard);
      await tester.pumpAndSettle();

      // Band selector sheet is shown
      expect(find.text('SELECT A BAND'), findsOneWidget);

      // Dismiss the bottom sheet without selecting
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Did NOT navigate to Band Room Screen
      expect(find.text('Band Room Screen'), findsNothing);

      // Red dot remains, markFeatureAsRead was NOT called
      expect(appState.hasUnreadActivity('band_room'), isTrue);
      expect((appState.firebaseService as MockFirebaseServiceForBadges).markedFeatures['band_room'], isNull);
    });
  });
}
