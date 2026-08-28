import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/create_event_page.dart';
import 'package:musicians_flutter/views/create_session_screen.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/widgets/animated_tap_detector.dart';
import 'package:musicians_flutter/controllers/global_create_event_launcher.dart';

class MockGlobalEventFirebaseService extends FirebaseService {
  Map<String, String> bandsToReturn = {};
  Map<String, String> rolesToReturn = {};
  bool throwOnBands = false;
  bool throwOnRoles = false;
  int getUserBandsCalls = 0;
  int getUserBandRoleCalls = 0;

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    getUserBandsCalls++;
    if (throwOnBands) {
      throw Exception('Database connection failed');
    }
    return bandsToReturn;
  }

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    getUserBandRoleCalls++;
    if (throwOnRoles) {
      throw Exception('Role lookup failed');
    }
    return rolesToReturn[bandId];
  }
}

class MockAppStateForGlobalEventTest extends AppState {
  final MockGlobalEventFirebaseService mockFirebase = MockGlobalEventFirebaseService();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_123',
        displayName: 'Test Musician',
        email: 'test@example.com',
      );

  @override
  String? get currentUserId => 'user_123';
}

Widget createTestApp({
  required AppState appState,
  Widget? homeWidget,
  String initialRoute = '/',
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      initialRoute: initialRoute,
      routes: {
        '/': (context) => Scaffold(body: homeWidget ?? const HomeScreen()),
        '/create-session': (context) => const CreateSessionScreen(),
        '/band-room': (context) => const Scaffold(body: Text('Band Room Screen')),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('Global Create Event Entry Point - Phase 1 Verification Tests', () {
    test('1. AppState validateAndSanitizeBubbles handles defaults, valid selections, and invalid IDs safely', () {
      final defaults = AppState.validateAndSanitizeBubbles(null);
      expect(defaults, equals(['find_musicians', 'band_room', 'create_event']));

      final validUserSaved = AppState.validateAndSanitizeBubbles(['browse_musicians', 'find_gigs', 'marketplace']);
      expect(validUserSaved, equals(['browse_musicians', 'find_gigs', 'marketplace']));

      final invalidIds = AppState.validateAndSanitizeBubbles(['unknown_1', 'obsolete_2', 'fake_3']);
      expect(invalidIds, equals(['find_musicians', 'band_room', 'create_event']));

      final duplicates = AppState.validateAndSanitizeBubbles(['find_musicians', 'find_musicians', 'band_room']);
      expect(duplicates, equals(['find_musicians', 'band_room', 'create_event']));

      final wrongLength = AppState.validateAndSanitizeBubbles(['find_musicians']);
      expect(wrongLength, equals(['find_musicians', 'band_room', 'create_event']));
    });

    test('2. HomeUsageTracker getClicks and resetClicks safely include create_event', () async {
      final clicks = await HomeUsageTracker.getClicks();
      expect(clicks.containsKey('create_event'), isTrue);
      await HomeUsageTracker.resetClicks();
      final resetClicks = await HomeUsageTracker.getClicks();
      expect(resetClicks['create_event'], equals(0));
    });

    testWidgets('3. Create Event action is visible on Home View and opens two-choice launcher', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForGlobalEventTest();
      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Create Event'), findsWidgets);

      final createEventCard = find.widgetWithText(GestureDetector, 'Create Event').first;
      if (createEventCard.evaluate().isNotEmpty) {
        await tester.tap(createEventCard);
      } else {
        await tester.tap(find.text('Create Event').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('WHAT WOULD YOU LIKE TO CREATE?'), findsOneWidget);
      expect(find.text('Create Event'), findsWidgets);
      expect(find.text('Create Session'), findsOneWidget);
      expect(find.text('Create rehearsal, gig, tour, show...'), findsOneWidget);
      expect(find.text('Create songwriting session, jam, recording, workshop...'), findsOneWidget);
    });

    testWidgets('4. Selecting Create Session opens CreateSessionScreen without band/role queries', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final appState = MockAppStateForGlobalEventTest();
      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      unawaited(GlobalCreateEventLauncher.showLauncherSheet(
        tester.element(find.byType(HomeScreen)),
        appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sessionCard = find.text('Create Session');
      expect(sessionCard, findsOneWidget);

      await tester.tap(sessionCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateSessionScreen), findsOneWidget);
      expect(appState.mockFirebase.getUserBandsCalls, equals(0));
      expect(appState.mockFirebase.getUserBandRoleCalls, equals(0));
    });

    testWidgets('5. User with no bands cannot open CreateEventPage and sees explanation', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.bandsToReturn = {};

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      await GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsNothing);
      expect(find.text('You need to be a Leader, Admin, or MOD of a band to create a Band Event. You can create a Session without a band.'), findsOneWidget);
    });

    testWidgets('6. Ordinary band Member cannot open CreateEventPage and sees explanation', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.bandsToReturn = {'b1': 'Rockers'};
      appState.mockFirebase.rolesToReturn = {'b1': 'Member'};

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      await GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsNothing);
      expect(find.text('You need to be a Leader, Admin, or MOD of a band to create a Band Event. You can create a Session without a band.'), findsOneWidget);
    });

    testWidgets('7. User with exactly 1 authorized band (Leader) opens CreateEventPage directly', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.bandsToReturn = {'b1': 'Jazz Trio'};
      appState.mockFirebase.rolesToReturn = {'b1': 'Leader'};

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsOneWidget);
      expect(appState.activeBandId, equals('b1'));
    });

    testWidgets('8. User with multiple bands sees ONLY authorized bands in selector sheet', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.bandsToReturn = {
        'b1': 'Authorized Leader Band',
        'b2': 'Unauthorized Member Band',
        'b3': 'Authorized Admin Band',
      };
      appState.mockFirebase.rolesToReturn = {
        'b1': 'Leader',
        'b2': 'Member',
        'b3': 'Admin',
      };

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('SELECT A BAND'), findsOneWidget);
      expect(find.text('Authorized Leader Band'), findsOneWidget);
      expect(find.text('Authorized Admin Band'), findsOneWidget);
      expect(find.text('Unauthorized Member Band'), findsNothing);
    });

    testWidgets('9. Exact role authorization accepts Leader, Admin, and MOD (case-insensitive with trimming)', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.bandsToReturn = {'b1': 'Mod Band'};
      appState.mockFirebase.rolesToReturn = {'b1': '  MoD  '};

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsOneWidget);
    });

    testWidgets('10. Permission lookup failure fails closed with error message', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.throwOnBands = true;

      await tester.pumpWidget(createTestApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsNothing);
      expect(find.textContaining('Permission check failed'), findsOneWidget);
    });

    testWidgets('11. CreateEventPage._checkPermission fails closed if getUserBandRoleAsync throws', (WidgetTester tester) async {
      final appState = MockAppStateForGlobalEventTest();
      appState.mockFirebase.throwOnRoles = true;

      await tester.pumpWidget(createTestApp(
        appState: appState,
        homeWidget: const CreateEventPage(bandId: 'b1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Permission check failed'), findsOneWidget);
    });

    testWidgets('12. Preserved Band Room Create Event entry point remains present', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForGlobalEventTest();
      appState.selectBand('b1', 'Test Band');
      appState.mockFirebase.rolesToReturn = {'b1': 'Leader'};

      await tester.pumpWidget(createTestApp(
        appState: appState,
        homeWidget: const BandRoomChatScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BandRoomChatScreen), findsOneWidget);
      expect(find.byType(AnimatedTapDetector), findsWidgets);
    });
  });
}
