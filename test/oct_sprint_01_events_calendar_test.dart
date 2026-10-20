import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/create_public_event_screen.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';
import 'package:musicians_flutter/views/manage_events_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_details_screen.dart';

// --- Mocks for Events ---

class MockFirebaseForOctSprint extends FirebaseService {
  final Map<String, String> userBands = {
    'band_1': 'Nordic Groove',
  };

  final Map<String, List<BandEvent>> bandEvents = {
    'band_1': [
      BandEvent(
        id: 'new_ev_1',
        title: 'Summer Tour',
        eventType: 'Concert',
        location: 'Gröna Lund, Stockholm',
        description: 'Summer headline tour',
        startDateTime: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 5, hours: 2)).toIso8601String(),
        rehearsals: [
          EventRehearsal(
            id: 'reh_1',
            title: 'Part 1',
            date: '2026-09-10',
            startTime: '18:00',
            endTime: '19:00',
          ),
          EventRehearsal(
            id: 'reh_2',
            title: 'Part 2',
            date: '2026-09-10',
            startTime: '19:00',
            endTime: '20:00',
          ),
        ],
        additionalNotes: '',
        createdBy: 'user_creator',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        isLocked: false,
        responses: {
          'user_creator': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_2': EventResponse(status: 'NO', timestamp: DateTime.now()),
          'user_3': EventResponse(status: 'UNCERTAIN', timestamp: DateTime.now()),
        },
      ),
      BandEvent(
        id: 'upcoming_locked_1',
        title: 'Locked Festival Gig',
        eventType: 'Concert',
        location: 'Tele2 Arena',
        description: 'Finalized locked festival performance',
        startDateTime: DateTime.now().add(const Duration(days: 12)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 12, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_creator',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        isLocked: true,
        responses: {
          'user_creator': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      ),
      BandEvent(
        id: 'past_ev_1',
        title: 'Past Autumn Session',
        eventType: 'Rehearsal',
        location: 'Studio 1',
        description: 'Historic rehearsal run-through',
        startDateTime: DateTime.now().subtract(const Duration(days: 10)).toIso8601String(),
        endDateTime: DateTime.now().subtract(const Duration(days: 10, hours: -2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_creator',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        isLocked: false, // Old event that wasn't explicitly locked
        responses: {
          'user_creator': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_2': EventResponse(status: 'NO', timestamp: DateTime.now()),
        },
      ),
    ],
  };

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => Map.from(userBands);

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async => 'leader';

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value(bandEvents[bandId] ?? []);
  }

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    final list = bandEvents[bandId] ?? [];
    final found = list.where((e) => e.id == eventId);
    return Stream.value(found.isNotEmpty ? found.first : null);
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return bandEvents[bandId] ?? [];
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return [];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? 'user_creator',
      displayName: userId == 'user_creator' ? 'Test Creator' : 'Member $userId',
    );
  }

  @override
  Future<List<PublicCalendarEvent>> getPublicCalendarEventsAsync() async => [];
}

class MockAppStateForOctSprint extends Fake with ChangeNotifier implements AppState {
  final MockFirebaseForOctSprint mockFirebase = MockFirebaseForOctSprint();
  String _currentUserId = 'user_creator';

  void setUserId(String id) {
    _currentUserId = id;
    notifyListeners();
  }

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => _currentUserId;

  @override
  String? get activeBandId => 'band_1';

  @override
  String? get activeBandName => 'Nordic Groove';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: _currentUserId,
        displayName: 'Test Artist',
        email: 'artist@example.com',
      );

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  List<String> get selectedBubbles => ['event_calendar', 'band_room', 'create_event'];

  @override
  void selectBand(String bandId, String bandName) {}
}

class MockRepoForOctSprint implements PublicEventRepository {
  final List<PublicCalendarEvent> events;

  MockRepoForOctSprint(this.events);

  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async => events;

  @override
  Future<String> createEvent(PublicCalendarEvent event) async => event.id;

  @override
  Future<void> updateEvent(PublicCalendarEvent event) async {}

  @override
  Future<void> deleteEvent(String eventId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('OCT-SPRINT-01: Events-listan förenkling', () {
    testWidgets('1 & 2. Bandnamn är visuellt överordnat och eventnamn visas inom raka citationstecken', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Band name
      final bandFinder = find.text('Nordic Groove');
      expect(bandFinder, findsOneWidget);
      final bandTextWidget = tester.widget<Text>(bandFinder);
      expect(bandTextWidget.style?.fontSize, 18);
      expect(bandTextWidget.style?.fontWeight, FontWeight.bold);

      // Event title within straight quotes
      final titleFinder = find.text('"Summer Tour"');
      expect(titleFinder, findsOneWidget);
      final titleTextWidget = tester.widget<Text>(titleFinder);
      expect(titleTextWidget.style?.fontSize, 13);
      expect(titleTextWidget.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('3. Part Event visas inte på listkorten och eventtyp visas separat', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // "2 Part Event" must not be displayed on the card
      expect(find.textContaining('Part Event'), findsNothing);

      // Session/event type "Concert" is displayed separately
      expect(find.text('Concert'), findsOneWidget);
    });

    testWidgets('4 & 5. New Events saknar inline-RSVP kontroller och saknar svarssammanställning', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Inline RSVP controls removed from New Events
      expect(find.text('Your RSVP'), findsNothing);
      expect(find.text('RSVP Required'), findsNothing);
      expect(find.text('Please respond'), findsNothing);
      expect(find.text('Change'), findsNothing);
      expect(find.text('Maybe'), findsNothing);

      // Svarssammanställning (1 Yes, 1 No, 1 ?) removed from New Events card
      expect(find.text('1 Yes'), findsNothing);
      expect(find.text('1 No'), findsNothing);
      expect(find.text('1 ?'), findsNothing);
    });

    testWidgets('6 & 7. New Event-kort är klickbart och öppnar EventDetailsPage med YOUR RESPONSE intakt', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the card
      await tester.tap(find.text('"Summer Tour"'));
      await tester.pumpAndSettle();

      // Opened EventDetailsPage
      expect(find.byType(EventDetailsPage), findsOneWidget);

      // YOUR RESPONSE exists on details page
      expect(find.text('YOUR RESPONSE'), findsWidgets);
    });

    testWidgets('8 & 9. Past Events visar inga redigerbara RSVP-kontroller och behåller resultatsammanställning', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Past Events
      await tester.tap(find.text('PAST EVENTS'));
      await tester.pumpAndSettle();

      expect(find.text('"Past Autumn Session"'), findsOneWidget);

      // No editable RSVP controls
      expect(find.text('Please respond'), findsNothing);
      expect(find.text('Your RSVP'), findsNothing);
      expect(find.text('Change'), findsNothing);

      // Preserves attendance results breakdown for historic event
      expect(find.text('1 Yes'), findsOneWidget);
      expect(find.text('1 No'), findsOneWidget);
    });

    testWidgets('10. Upcoming and Past navigation opens read-only results page', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Upcoming tab
      await tester.tap(find.text('UPCOMING (Finalized)'));
      await tester.pumpAndSettle();

      expect(find.text('"Locked Festival Gig"'), findsOneWidget);

      // Tap card
      await tester.tap(find.text('"Locked Festival Gig"'));
      await tester.pumpAndSettle();

      // Opens EventResultsPage
      expect(find.byType(EventResultsPage), findsOneWidget);
    });

    testWidgets('11. Events-listan fungerar vid 320 px bredd utan overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: ManageEventsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('EVENTS'), findsOneWidget);
      expect(find.text('"Summer Tour"'), findsOneWidget);

      // Switch to Past tab at 320px
      await tester.tap(find.text('PAST EVENTS'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('"Past Autumn Session"'), findsOneWidget);
    });
  });

  group('OCT-SPRINT-01: Event Calendar polish', () {
    final imageEvent = PublicCalendarEvent(
      id: 'img_cal_1',
      title: 'Stockholm Sound Gala',
      eventType: PublicEventType.liveGig,
      organizerName: 'Nordic Sound Academy',
      venueName: 'Konserthuset',
      city: 'Stockholm',
      address: 'Hötorget 8',
      startDateTime: DateTime(2026, 9, 15, 19, 30),
      endDateTime: DateTime(2026, 9, 15, 22, 30),
      shortDescription: 'Grand gala with live orchestra.',
      description: 'Full gala description for orchestral showcase.',
      imageUrl: 'https://example.com/gala.jpg',
      priceAmount: 200,
      isFree: false,
      createdBy: 'user_creator',
      status: PublicEventStatus.published,
      isMock: false,
    );

    final noImageEvent = PublicCalendarEvent(
      id: 'no_img_cal_2',
      title: 'Acoustic Jam Session',
      eventType: PublicEventType.openSession,
      organizerName: 'Folk Musicians',
      venueName: 'Kafé 44',
      city: 'Stockholm',
      address: 'Tjärhovsgatan 44',
      startDateTime: DateTime(2026, 9, 16, 18, 0),
      endDateTime: DateTime(2026, 9, 16, 21, 0),
      shortDescription: 'Open acoustic jam session.',
      description: 'Full description of acoustic jam session.',
      imageUrl: null,
      isFree: true,
      createdBy: 'other_user',
      status: PublicEventStatus.published,
      isMock: false,
    );

    testWidgets('1. Kalenderkortet visar inte Live/Gig eller annan eventtyp-badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();
      final repo = MockRepoForOctSprint([imageEvent, noImageEvent]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Neither card displays the visible event type badge (e.g. Live/Gig or Open Session)
      expect(find.text('Live/Gig'), findsNothing);
      expect(find.text('Open Session'), findsNothing);
    });

    testWidgets('2 & 3. Datumet visas högst upp på kort med bild och utan bild', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();
      final repo = MockRepoForOctSprint([imageEvent, noImageEvent]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Image event has date "15" and "SEP"
      expect(find.text('15'), findsWidgets);
      expect(find.text('SEP'), findsWidgets);

      // No image event has date "16"
      expect(find.text('16'), findsWidgets);
    });

    testWidgets('4. Eventtypen finns fortfarande kvar och visas på Event Details', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventDetailsScreen(
              event: imageEvent,
              repository: MockRepoForOctSprint([imageEvent]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On details screen, event type badge is clearly visible
      expect(find.text('Live/Gig'), findsOneWidget);
    });

    testWidgets('5 & 6. Upload from this device visas och ingen Choose from Gallery text kvarstår', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: CreatePublicEventScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Helper text updated
      expect(find.text('Tap to upload from this device or use Camera'), findsOneWidget);
      expect(find.textContaining('Choose from Gallery'), findsNothing);

      // Tap on the cover upload zone to open sheet
      await tester.tap(find.text('Upload Cover Photo or Poster'));
      await tester.pumpAndSettle();

      // Modal options
      expect(find.text('Upload from this device'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsNothing);
    });

    testWidgets('7 & 8. Edit-knapp visas för skapare men inte för andra användare', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint(); // currentUserId is 'user_creator'
      final repo = MockRepoForOctSprint([imageEvent, noImageEvent]); // imageEvent created by 'user_creator', noImageEvent created by 'other_user'

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only ONE edit button found (for imageEvent, because current user is creator)
      final editButtons = find.byTooltip('Edit Event');
      expect(editButtons, findsOneWidget);

      // Verify it's on imageEvent
      expect(find.bySemanticsLabel('Edit event Stockholm Sound Gala'), findsOneWidget);
      // Not on noImageEvent
      expect(find.bySemanticsLabel('Edit event Acoustic Jam Session'), findsNothing);
    });

    testWidgets('9. Vanliga användare kan öppna och läsa eventet men inte se Edit-knappen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();
      appState.setUserId('guest_reader_user'); // Not creator of either event

      final repo = MockRepoForOctSprint([imageEvent, noImageEvent]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            routes: {
              '/public-event-details': (context) => const PublicEventDetailsScreen(),
            },
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No edit buttons in list
      expect(find.byTooltip('Edit Event'), findsNothing);

      // Open event details
      await tester.tap(find.text('Stockholm Sound Gala'));
      await tester.pumpAndSettle();

      // Details page opens
      expect(find.byType(PublicEventDetailsScreen), findsOneWidget);
      expect(find.text('ABOUT THIS EVENT'), findsOneWidget);

      // No edit button on details page for non-creator
      expect(find.text('Edit Event'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('10. Event Calendar fungerar vid 320 px bredd utan overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForOctSprint();
      final repo = MockRepoForOctSprint([imageEvent, noImageEvent]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: PublicEventCalendarScreen(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('EVENT CALENDAR'), findsOneWidget);
      expect(find.text('Stockholm Sound Gala'), findsOneWidget);
      expect(find.text('Acoustic Jam Session'), findsOneWidget);
    });
  });
}
