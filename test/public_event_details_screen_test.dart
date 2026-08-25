import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/calendar_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_details_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SpyingFirebaseService extends FirebaseService {
  int callCount = 0;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    callCount++;
    return UserProfile(userId: 'u1', displayName: 'Test User');
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    callCount++;
    return {'b1': 'Test Band'};
  }
}

class MockAppStateForDetailsTest extends AppState {
  final SpyingFirebaseService spyService;

  MockAppStateForDetailsTest(this.spyService);

  @override
  FirebaseService get firebaseService => spyService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_1',
        displayName: 'Test Musician',
        email: 'test@example.com',
      );

  @override
  String? get currentUserId => 'test_user_1';

  @override
  List<String> get selectedBubbles => [
        'event_calendar',
        'band_room',
        'create_event',
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testEvent = PublicCalendarEvent(
    id: 'mock_test_1',
    title: 'Stockholm Jazz Night',
    eventType: PublicEventType.liveGig,
    organizerName: 'Stockholm Jazz Collective',
    venueName: 'Jazzbaren',
    city: 'Stockholm',
    address: 'Jazzgränd 4 (Demo Venue), Gamla Stan',
    startDateTime: DateTime(2026, 8, 27, 20, 0),
    endDateTime: DateTime(2026, 8, 27, 23, 0),
    genres: const ['Jazz', 'Swing'],
    priceAmount: 150,
    currency: 'SEK',
    isFree: false,
    shortDescription: 'Short desc',
    description: 'Full jazz description text for testing details rendering.',
    status: PublicEventStatus.published,
    isMock: true,
  );

  final testFreeEvent = PublicCalendarEvent(
    id: 'mock_test_2',
    title: 'Open Co-writing Session',
    eventType: PublicEventType.openSession,
    organizerName: 'West Coast Songwriters',
    venueName: 'Song Lab Göteborg',
    city: 'Göteborg',
    address: 'Musikgatan 12 (Demo Studio), Majorna',
    startDateTime: DateTime(2026, 9, 3, 18, 30),
    endDateTime: DateTime(2026, 9, 3, 21, 30),
    genres: const ['Pop', 'Songwriting'],
    priceAmount: null,
    currency: 'SEK',
    isFree: true,
    shortDescription: 'Short desc',
    description: 'Full songwriting session description.',
    status: PublicEventStatus.published,
    isMock: true,
  );

  Widget createDetailsTestWidget({PublicCalendarEvent? event, Object? routeArgument}) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockAppStateForDetailsTest(SpyingFirebaseService()),
      child: MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == '/public-event-details') {
            final arg = settings.arguments is PublicCalendarEvent
                ? settings.arguments as PublicCalendarEvent
                : null;
            return MaterialPageRoute(
              builder: (context) => PublicEventDetailsScreen(event: arg),
              settings: settings,
            );
          }
          if (settings.name == '/event-calendar') {
            return MaterialPageRoute(
              builder: (context) => const PublicEventCalendarScreen(),
              settings: settings,
            );
          }
          if (settings.name == '/calendar') {
            return MaterialPageRoute(
              builder: (context) => const CalendarScreen(bandId: 'b1'),
              settings: settings,
            );
          }
          return null;
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/public-event-details',
                    arguments: routeArgument ?? event,
                  );
                },
                child: const Text('Open Details'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('PublicEventDetailsScreen & Integration Tests', () {
    testWidgets('1. Renders all details fields, genres, DEMO EVENT, and price correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testEvent));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Details'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('DEMO EVENT'), findsOneWidget);
      expect(find.text('Live/Gig'), findsOneWidget);
      expect(find.text('Stockholm Jazz Collective'), findsOneWidget);
      expect(find.text('Jazzbaren, Stockholm'), findsOneWidget);
      expect(find.text('Jazzgränd 4 (Demo Venue), Gamla Stan'), findsOneWidget);
      expect(find.text('150 SEK'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('Swing'), findsOneWidget);
      expect(find.text('Full jazz description text for testing details rendering.'), findsOneWidget);
      expect(find.text('Back to Calendar'), findsOneWidget);
    });

    testWidgets('2. Free event displays Free in price badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testFreeEvent));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Details'));
      await tester.pumpAndSettle();

      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Song Lab Göteborg, Göteborg'), findsOneWidget);
    });

    testWidgets('3. Invalid navigation argument gracefully displays fallback without crashing', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(routeArgument: 'invalid_string_argument'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Details'));
      await tester.pumpAndSettle();

      expect(find.text('Event Not Found'), findsOneWidget);
      expect(find.text('The requested event could not be loaded.'), findsOneWidget);
    });

    testWidgets('4. Back to Calendar button pops details view', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testEvent));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Details'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);

      await tester.tap(find.text('Back to Calendar'));
      await tester.pumpAndSettle();

      expect(find.text('Open Details'), findsOneWidget);
    });

    testWidgets('5. Home View Event Calendar button navigates to /event-calendar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForDetailsTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: MaterialApp(
            routes: {
              '/event-calendar': (context) => const PublicEventCalendarScreen(),
              '/public-event-details': (context) => const PublicEventDetailsScreen(),
              '/calendar': (context) => const CalendarScreen(bandId: 'b1'),
            },
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final eventCalendarAction = find.text('Event Calendar');
      expect(eventCalendarAction, findsOneWidget);

      await tester.tap(eventCalendarAction);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EVENT CALENDAR'), findsOneWidget);
      expect(find.text('DEMO EVENTS'), findsOneWidget);
    });

    testWidgets('6. Existing /calendar route resolves to private CalendarScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForDetailsTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: MaterialApp(
            routes: {
              '/calendar': (context) => const CalendarScreen(bandId: 'b1'),
            },
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/calendar', arguments: 'b1'),
                    child: const Text('Open Band Calendar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Open Band Calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CalendarScreen), findsOneWidget);
    });
  });
}
