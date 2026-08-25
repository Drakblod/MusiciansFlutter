import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_details_screen.dart';

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

class MockAppStateForCalendarTest extends AppState {
  final SpyingFirebaseService spyService;

  MockAppStateForCalendarTest(this.spyService);

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
        'find_musicians',
        'band_room',
        'create_event',
        'browse_musicians',
        'find_gigs',
        'collabs',
        'event_calendar',
        'marketplace',
      ];
}

class FailingThenSucceedingRepository implements PublicEventRepository {
  bool shouldFail = true;
  final MockPublicEventRepository fallback;

  FailingThenSucceedingRepository(DateTime ref)
      : fallback = MockPublicEventRepository(referenceNow: ref);

  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async {
    if (shouldFail) {
      shouldFail = false;
      throw Exception('Network error');
    }
    return fallback.getUpcomingEvents();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  // August 1, 2026: +2 is Aug 3 (Aug), +9 is Aug 10 (Aug), +35 is Sept 5 (Sept)
  final fixedRef = DateTime(2026, 8, 1, 12, 0);

  Widget createTestWidget({
    PublicEventRepository? repository,
    SpyingFirebaseService? spyService,
    Widget? home,
  }) {
    final service = spyService ?? SpyingFirebaseService();
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockAppStateForCalendarTest(service),
      child: MaterialApp(
        routes: {
          '/event-calendar': (context) => PublicEventCalendarScreen(
                repository: repository ?? MockPublicEventRepository(referenceNow: fixedRef),
              ),
          '/public-event-details': (context) => const PublicEventDetailsScreen(),
          '/calendar': (context) => const CalendarScreen(bandId: 'b1'),
        },
        home: home ??
            PublicEventCalendarScreen(
              repository: repository ?? MockPublicEventRepository(referenceNow: fixedRef),
            ),
      ),
    );
  }

  group('PublicEventCalendarScreen Widget Tests', () {
    testWidgets('1. Renders title, subtitle and DEMO EVENTS badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('EVENT CALENDAR'), findsOneWidget);
      expect(find.text('Discover live music, open sessions, workshops and music events.'), findsOneWidget);
      expect(find.text('DEMO EVENTS'), findsOneWidget);
    });

    testWidgets('2. Displays 4 filter tabs in exact order', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Live/Gigs'), findsOneWidget);
      expect(find.text('Open Sessions'), findsOneWidget);
      expect(find.text('Workshops'), findsOneWidget);
    });

    testWidgets('3. Initial pagination shows 2 events and Load More button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Music Production Workshop'), findsNothing);
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('4. Tapping Load More reveals 3rd event and hides Load More', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final loadMoreBtn = find.text('Load More');
      expect(loadMoreBtn, findsOneWidget);
      await tester.tap(loadMoreBtn);
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Music Production Workshop'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('5. Filtering Live/Gigs shows only Stockholm Jazz Night without Load More', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Live/Gigs'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsNothing);
      expect(find.text('Music Production Workshop'), findsNothing);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('6. Filtering Open Sessions shows only Open Co-writing Session without Load More', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sessions'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsNothing);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Music Production Workshop'), findsNothing);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('7. Filtering Workshops shows only Music Production Workshop without Load More', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Workshops'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsNothing);
      expect(find.text('Open Co-writing Session'), findsNothing);
      expect(find.text('Music Production Workshop'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('8. Search matches by title, organizer, venue, city, genre, and descriptions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Search title
      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsNothing);

      // Search organizer
      await tester.enterText(find.byType(TextField), 'songwriters');
      await tester.pumpAndSettle();
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Stockholm Jazz Night'), findsNothing);

      // Search venue
      await tester.enterText(find.byType(TextField), 'nordic sound');
      await tester.pumpAndSettle();
      expect(find.text('Music Production Workshop'), findsOneWidget);

      // Search city
      await tester.enterText(find.byType(TextField), 'göteborg');
      await tester.pumpAndSettle();
      expect(find.text('Open Co-writing Session'), findsOneWidget);

      // Search genre
      await tester.enterText(find.byType(TextField), 'electronic');
      await tester.pumpAndSettle();
      expect(find.text('Music Production Workshop'), findsOneWidget);

      // Search full description keyword
      await tester.enterText(find.byType(TextField), 'spontaneous musical encounters');
      await tester.pumpAndSettle();
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
    });

    testWidgets('9. Combining search and type filters works correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Live/Gigs'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'workshop');
      await tester.pumpAndSettle();

      expect(find.text('No events match your search.'), findsOneWidget);
      expect(find.text('Stockholm Jazz Night'), findsNothing);
    });

    testWidgets('10. Clear filters restores results and resets pagination', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent query 123');
      await tester.pumpAndSettle();

      expect(find.text('No events match your search.'), findsOneWidget);
      final clearBtn = find.text('Clear filters');
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('11. Month headings are rendered once per visible month', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // August 2026 for events 1 & 2
      expect(find.text('AUGUST 2026'), findsOneWidget);
      expect(find.text('SEPTEMBER 2026'), findsNothing);

      // Load more to reveal event 3 in September
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(find.text('AUGUST 2026'), findsOneWidget);
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    });

    testWidgets('12. Empty repository shows No public events available yet.', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(repository: EmptyPublicEventRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No public events available yet.'), findsOneWidget);
      expect(find.text('Upcoming concerts, open sessions and workshops will appear here.'), findsOneWidget);
    });

    testWidgets('13. Failing repository shows error and retry button recovers when repository succeeds', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final retryRepo = FailingThenSucceedingRepository(fixedRef);
      await tester.pumpWidget(createTestWidget(repository: retryRepo));
      await tester.pumpAndSettle();

      expect(find.text('Could not load events.'), findsOneWidget);
      final retryBtn = find.text('Retry');
      expect(retryBtn, findsOneWidget);

      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      expect(find.text('Could not load events.'), findsNothing);
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
    });

    testWidgets('14. Pull-to-refresh re-fetches upcoming events', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
    });

    testWidgets('15. Tapping event card navigates to PublicEventDetailsScreen with event argument', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stockholm Jazz Night'));
      await tester.pumpAndSettle();

      expect(find.text('ABOUT THIS EVENT'), findsOneWidget);
      expect(find.text('Stockholm Jazz Collective'), findsOneWidget);
      expect(find.text('Jazzgränd 4 (Demo Venue), Gamla Stan'), findsOneWidget);
      expect(find.text('150 SEK'), findsOneWidget);
    });

    testWidgets('16. Zero Firebase service calls made by public calendar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spy = SpyingFirebaseService();
      await tester.pumpWidget(createTestWidget(spyService: spy));
      await tester.pumpAndSettle();

      expect(spy.callCount, 0);
    });
  });
}
