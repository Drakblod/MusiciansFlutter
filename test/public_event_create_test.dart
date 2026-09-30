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
import 'package:musicians_flutter/views/create_public_event_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';

class SpyingFirebaseService extends FirebaseService {
  final List<PublicCalendarEvent> savedEvents = [];

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: 'user_test_123', displayName: 'Alex Tester');
  }

  @override
  Future<String> savePublicCalendarEventAsync(PublicCalendarEvent event) async {
    final id = event.id.isNotEmpty ? event.id : 'firebase_evt_${savedEvents.length + 1}';
    final saved = event.copyWith(id: id, isMock: false);
    savedEvents.add(saved);
    return id;
  }

  @override
  Future<List<PublicCalendarEvent>> getPublicCalendarEventsAsync() async {
    return List.from(savedEvents);
  }

  @override
  Future<String> uploadPublicEventCoverImageAsync(dynamic image, [String? eventId]) async {
    return 'https://firebasestorage.googleapis.com/v0/b/mock/cover_uploaded.jpg';
  }
}

class MockAppStateForCreateTest extends AppState {
  final SpyingFirebaseService spyService;

  MockAppStateForCreateTest(this.spyService);

  @override
  FirebaseService get firebaseService => spyService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_test_123',
        displayName: 'Alex Tester',
        email: 'alex@example.com',
      );

  @override
  String? get currentUserId => 'user_test_123';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('PublicCalendarEvent Model Tests', () {
    test('toJson and fromJson preserves all fields properly', () {
      final now = DateTime(2026, 10, 5, 20, 0);
      final later = DateTime(2026, 10, 5, 23, 0);

      final event = PublicCalendarEvent(
        id: 'test_id_1',
        title: 'Autumn Jazz Showcase',
        shortDescription: 'Live jazz at the café.',
        description: 'Detailed description about the musicians and setlist.',
        eventType: PublicEventType.liveGig,
        organizerName: 'Jazz Band',
        venueName: 'Café Blue',
        city: 'Stockholm',
        address: 'Storgatan 1',
        startDateTime: now,
        endDateTime: later,
        genres: ['Jazz', 'Swing'],
        priceAmount: 120.0,
        currency: 'SEK',
        isFree: false,
        status: PublicEventStatus.published,
        isMock: false,
        imageUrl: 'https://example.com/image.png',
        createdBy: 'user_test_123',
        createdAt: 1727700000000,
      );

      final json = event.toJson();
      expect(json['id'], 'test_id_1');
      expect(json['title'], 'Autumn Jazz Showcase');
      expect(json['eventType'], 'liveGig');
      expect(json['priceAmount'], 120.0);
      expect(json['isFree'], false);
      expect(json['createdBy'], 'user_test_123');

      final fromJson = PublicCalendarEvent.fromJson(json, 'test_id_1');
      expect(fromJson.id, 'test_id_1');
      expect(fromJson.title, 'Autumn Jazz Showcase');
      expect(fromJson.eventType, PublicEventType.liveGig);
      expect(fromJson.formattedPrice, '120 SEK');
      expect(fromJson.genres, ['Jazz', 'Swing']);
      expect(fromJson.createdBy, 'user_test_123');
      expect(fromJson.createdAt, 1727700000000);
    });

    test('Free event formats price label as Free', () {
      final event = PublicCalendarEvent(
        id: 'free_event_1',
        title: 'Open Jam',
        shortDescription: 'Open jam',
        description: 'Bring instruments',
        eventType: PublicEventType.openSession,
        organizerName: 'Local Jam',
        venueName: 'Studio A',
        city: 'Göteborg',
        address: '',
        startDateTime: DateTime.now(),
        endDateTime: DateTime.now().add(const Duration(hours: 2)),
        isFree: true,
      );

      expect(event.formattedPrice, 'Free');
    });
  });

  group('PublicEventRepository Tests', () {
    test('MockPublicEventRepository supports createEvent and keeps events in sorted order', () async {
      final repo = MockPublicEventRepository(referenceNow: DateTime(2026, 10, 1, 12, 0));
      final initialEvents = await repo.getUpcomingEvents();
      expect(initialEvents.length, 3);

      final newEvent = PublicCalendarEvent(
        id: '',
        title: 'Immediate Showcase',
        shortDescription: 'Tomorrow event',
        description: 'Details',
        eventType: PublicEventType.liveGig,
        organizerName: 'Band X',
        venueName: 'Club Y',
        city: 'Stockholm',
        address: 'Gatan 1',
        startDateTime: DateTime(2026, 10, 1, 18, 0), // 6 hours from ref
        endDateTime: DateTime(2026, 10, 1, 21, 0),
      );

      final createdId = await repo.createEvent(newEvent);
      expect(createdId.isNotEmpty, true);

      final updatedEvents = await repo.getUpcomingEvents();
      expect(updatedEvents.length, 4);
      // New event is earlier than mock event 1 (which is at ref + 2 days), so it should be first
      expect(updatedEvents.first.title, 'Immediate Showcase');
    });

    test('FirebasePublicEventRepository merges real and mock events', () async {
      final spyService = SpyingFirebaseService();
      final repo = FirebasePublicEventRepository(
        firebaseService: spyService,
        includeMock: true,
        referenceNow: DateTime(2026, 10, 1, 12, 0),
      );

      // Create through repository
      final newEvent = PublicCalendarEvent(
        id: '',
        title: 'Created Real Event',
        shortDescription: 'Real event description',
        description: 'Full real description',
        eventType: PublicEventType.workshopCourse,
        organizerName: 'Instructor Jane',
        venueName: 'Sound Lab',
        city: 'Malmö',
        address: 'Vägen 2',
        startDateTime: DateTime(2026, 10, 4, 14, 0),
        endDateTime: DateTime(2026, 10, 4, 18, 0),
      );

      await repo.createEvent(newEvent);
      expect(spyService.savedEvents.length, 1);

      final events = await repo.getUpcomingEvents();
      // 3 mock + 1 real
      expect(events.length, 4);
      expect(events.any((e) => e.title == 'Created Real Event'), true);
    });
  });

  group('CreatePublicEventScreen Widget Tests', () {
    testWidgets('Renders form fields and validates required inputs', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final spyService = SpyingFirebaseService();
      final appState = MockAppStateForCreateTest(spyService);
      final repo = MockPublicEventRepository();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: CreatePublicEventScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and headers
      expect(find.text('ADD TO EVENT CALENDAR'), findsOneWidget);
      expect(find.text('EVENT DETAILS'), findsOneWidget);

      final publishFinder = find.text('Publish Event');
      await tester.ensureVisible(publishFinder);
      await tester.pumpAndSettle();

      // Tap Publish with empty fields
      await tester.tap(publishFinder);
      await tester.pumpAndSettle();

      // Should show validation error snackbar
      expect(find.text('Please fill in all required fields.'), findsOneWidget);
    });

    testWidgets('Fills in form and successfully creates event', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final spyService = SpyingFirebaseService();
      final appState = MockAppStateForCreateTest(spyService);
      final repo = MockPublicEventRepository();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: CreatePublicEventScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter Event Title
      final titleField = find.widgetWithText(TextFormField, 'e.g. Stockholm Live Showcase, Jazz Jam');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'Nordic Synth Gathering');

      // Venue
      final venueField = find.widgetWithText(TextFormField, 'e.g. Jazzbaren, Fasching');
      expect(venueField, findsOneWidget);
      await tester.enterText(venueField, 'Kulturhuset Studio 3');

      // City
      final cityField = find.widgetWithText(TextFormField, 'e.g. Stockholm');
      expect(cityField, findsOneWidget);
      await tester.enterText(cityField, 'Stockholm');

      // Description
      final descField = find.widgetWithText(TextFormField, 'Detailed program, schedule, line-up, participant details...');
      expect(descField, findsOneWidget);
      await tester.enterText(descField, 'An immersive synth meetup with guest live performers.');

      // Toggle Free Admission
      final switchFinder = find.byType(Switch);
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Tap Publish Event
      final publishFinder = find.text('Publish Event');
      await tester.ensureVisible(publishFinder);
      await tester.pumpAndSettle();
      await tester.tap(publishFinder);
      await tester.pumpAndSettle();

      // Verify repository has the created event
      final events = await repo.getUpcomingEvents();
      expect(events.any((e) => e.title == 'Nordic Synth Gathering'), true);
      final created = events.firstWhere((e) => e.title == 'Nordic Synth Gathering');
      expect(created.venueName, 'Kulturhuset Studio 3');
      expect(created.isFree, true);
    });

    testWidgets('Renders Cover Image section and supports image URL', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final spyService = SpyingFirebaseService();
      final appState = MockAppStateForCreateTest(spyService);
      final repo = MockPublicEventRepository();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: CreatePublicEventScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Cover Image section title and upload prompt
      expect(find.text('COVER IMAGE & POSTER'), findsOneWidget);
      expect(find.text('Upload Cover Photo or Poster'), findsOneWidget);

      // Enter Event Details
      final titleField = find.widgetWithText(TextFormField, 'e.g. Stockholm Live Showcase, Jazz Jam');
      await tester.enterText(titleField, 'Poster Showcase');

      final venueField = find.widgetWithText(TextFormField, 'e.g. Jazzbaren, Fasching');
      await tester.enterText(venueField, 'Grand Hall');

      final cityField = find.widgetWithText(TextFormField, 'e.g. Stockholm');
      await tester.enterText(cityField, 'Malmö');

      final descField = find.widgetWithText(TextFormField, 'Detailed program, schedule, line-up, participant details...');
      await tester.enterText(descField, 'Show with poster.');

      // Enter custom image URL
      final urlField = find.widgetWithText(TextFormField, 'https://example.com/poster.jpg');
      await tester.ensureVisible(urlField);
      await tester.pumpAndSettle();
      await tester.enterText(urlField, 'https://example.com/custom_poster.jpg');
      await tester.pumpAndSettle();

      // Tap Publish Event
      final publishFinder = find.text('Publish Event');
      await tester.ensureVisible(publishFinder);
      await tester.pumpAndSettle();
      await tester.tap(publishFinder);
      await tester.pumpAndSettle();

      final events = await repo.getUpcomingEvents();
      final created = events.firstWhere((e) => e.title == 'Poster Showcase');
      expect(created.imageUrl, 'https://example.com/custom_poster.jpg');
    });
  });

  group('PublicEventCalendarScreen Add Event Navigation', () {
    testWidgets('Displays Add Event button in header and FloatingActionButton', (tester) async {
      final spyService = SpyingFirebaseService();
      final appState = MockAppStateForCreateTest(spyService);
      final repo = MockPublicEventRepository();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expect Add Event buttons
      expect(find.text('Add Event'), findsWidgets);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
