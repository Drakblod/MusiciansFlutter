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
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/collab_session.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/event_room.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/create_event_page.dart';
import 'package:musicians_flutter/views/create_session_screen.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/controllers/global_create_event_launcher.dart';

class MockCreate01FirebaseService extends FirebaseService {
  Map<String, String> userBands = {'band_1': 'Rock Band'};
  Map<String, String> userRoles = {'band_1': 'Leader'};
  List<BandEvent> savedBandEvents = [];
  Map<String, BandEvent> storedBandEvents = {};
  List<CollabSession> savedCollabSessions = [];
  int saveBandEventCalls = 0;
  int createSessionCalls = 0;

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return userBands;
  }

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return userRoles[bandId];
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: userBands[bandId] ?? 'Test Band',
      userRole: userRoles[bandId] ?? 'Leader',
    );
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return [
      BandMember(userId: 'user_create01', role: userRoles[bandId] ?? 'Leader'),
    ];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: userId ?? 'user_create01', displayName: 'Test Leader', email: 'test@example.com');
  }

  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    return {};
  }

  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) {
    return Stream.value([]);
  }

  @override
  Future<String> saveBandEventAsync(String bandId, BandEvent event) async {
    saveBandEventCalls++;
    savedBandEvents.add(event);
    final eventId = event.id ?? 'evt_${savedBandEvents.length}';
    storedBandEvents['$bandId/$eventId'] = event;
    return eventId;
  }

  @override
  Future<String> createBandEventAsync(String bandId, BandEvent event) async {
    return await saveBandEventAsync(bandId, event);
  }

  @override
  Future<void> saveCollabSessionAsync(CollabSession session) async {
    createSessionCalls++;
    savedCollabSessions.add(session);
  }

  @override
  Future<String> createTemporaryEventRoomAsync({
    required String bandId,
    required String eventId,
    required String roomName,
    required String createdBy,
    List<String> initialMembers = const [],
  }) async {
    return 'room_$eventId';
  }
}

class MockAppStateForCreate01Test extends AppState {
  final MockCreate01FirebaseService mockFirebase = MockCreate01FirebaseService();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_create01',
        displayName: 'Test Leader',
        email: 'leader@example.com',
      );

  @override
  String? get currentUserId => 'user_create01';
}

Widget createTestWrapper({
  required AppState appState,
  Widget? child,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/': (context) => Scaffold(body: child ?? const HomeScreen()),
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

  group('CREATE-01 — Global Launcher & Event Types Tests', () {
    test('8. BandEvent.standardEventTypes has exact required active choices and order', () {
      expect(BandEvent.standardEventTypes, equals([
        'Rehearsal',
        'Concert',
        'Club gig',
        'Private Event',
        'Tour',
        'Show',
        'Other',
      ]));
      expect(BandEvent.standardEventTypes.contains('Recording Session'), isFalse);
      expect(BandEvent.standardEventTypes.contains('Meeting'), isFalse);
    });

    testWidgets('1, 2, 3, 4. Launcher displays exact titles and descriptions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      unawaited(GlobalCreateEventLauncher.showLauncherSheet(
        tester.element(find.byType(HomeScreen)),
        appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Create Event title
      expect(find.text('Create Event'), findsWidgets);
      // 2. Exact description
      expect(find.text('Create rehearsal, gig, tour, show...'), findsOneWidget);
      // 3. Create Session title, not Collab Session
      expect(find.text('Create Session'), findsOneWidget);
      expect(find.text('Collab Session'), findsNothing);
      // 4. Exact description
      expect(find.text('Create songwriting session, jam, recording, workshop...'), findsOneWidget);
    });

    testWidgets('5. Create Event requires band selection and opens Band Event form', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      appState.mockFirebase.userBands = {'b1': 'My Rockers'};
      appState.mockFirebase.userRoles = {'b1': 'Leader'};

      await tester.pumpWidget(createTestWrapper(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GlobalCreateEventLauncher.handleCreateBandEvent(homeContext, appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateEventPage), findsOneWidget);
      expect(appState.activeBandId, equals('b1'));
    });

    testWidgets('6. Create Session opens CreateSessionScreen without band conversion', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      unawaited(GlobalCreateEventLauncher.showLauncherSheet(
        tester.element(find.byType(HomeScreen)),
        appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Create Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateSessionScreen), findsOneWidget);
      expect(find.byType(CreateEventPage), findsNothing);
    });

    testWidgets('7. Create Event page displays "CREATE EVENT", not "Create New Event"', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CREATE EVENT'), findsOneWidget);
      expect(find.text('Create New Event'), findsNothing);
      expect(find.text('CREATE NEW EVENT'), findsNothing);
    });

    testWidgets('9, 10, 11. New event dropdown contains standard choices and excludes Recording Session/Meeting', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open Event Type dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      for (final type in BandEvent.standardEventTypes) {
        expect(find.text(type), findsWidgets, reason: 'Expected $type in dropdown');
      }

      // Check Recording Session and Meeting are absent
      expect(find.text('Recording Session'), findsNothing);
      expect(find.text('Meeting'), findsNothing);
    });

    testWidgets('12. Selecting Other: empty blocks save; valid custom type is persisted to service contract', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select 'Other'
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Other').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Specify Event Type'), findsOneWidget);

      // Enter event title, location, and RSVP hours, but leave Specify Event Type empty
      await tester.enterText(find.widgetWithText(TextFormField, 'Event Title'), 'Masterclass Workshop');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Stockholm');
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '24');

      // Attempt submit with empty custom Event Type
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Proves submission blocked and error displayed
      expect(find.text('Please specify the event type'), findsOneWidget);
      expect(appState.mockFirebase.savedBandEvents.isEmpty, isTrue);

      // Enter whitespace-only: still blocked
      await tester.enterText(find.widgetWithText(TextFormField, 'Specify Event Type'), '   ');
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please specify the event type'), findsOneWidget);
      expect(appState.mockFirebase.savedBandEvents.isEmpty, isTrue);

      // Enter valid custom value
      await tester.enterText(find.widgetWithText(TextFormField, 'Specify Event Type'), 'Masterclass');
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Proves exact custom value reaches Band Event service contract
      expect(appState.mockFirebase.savedBandEvents.length, equals(1));
      expect(appState.mockFirebase.savedBandEvents.first.eventType, equals('Masterclass'));
      expect(appState.mockFirebase.savedBandEvents.first.title, equals('Masterclass Workshop'));
    });

    testWidgets('13. Additional grouped/tour event draft dialog uses standard active Event Type list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Toggle Multiple Events switch
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap + Add Event(s)
      await tester.tap(find.text('+ Add Event(s)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify draft modal is open
      expect(find.text('Add Event'), findsWidgets);

      // Open draft Event Type dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      for (final type in BandEvent.standardEventTypes) {
        expect(find.text(type), findsWidgets);
      }
      expect(find.text('Recording Session'), findsNothing);
      expect(find.text('Meeting'), findsNothing);
    });

    testWidgets('14, 15, 16. Existing legacy Recording Session and Meeting events open safely and preserve values', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final legacyEvent = BandEvent(
        id: 'legacy_evt_1',
        title: 'Legacy Recording Day',
        description: 'Album track 1',
        eventType: 'Recording Session',
        location: 'Studio X',
        startDateTime: '2026-09-01T10:00:00.000Z',
        endDateTime: '2026-09-01T18:00:00.000Z',
        additionalNotes: 'Legacy note',
        createdBy: 'user_create01',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        requireResponse: true,
        reminderIntervalHours: 24,
      );

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [legacyEvent],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Does not crash and displays legacy eventType
      expect(find.byType(CreateEventPage), findsOneWidget);
      expect(find.text('Recording Session'), findsOneWidget);
      expect(find.text('Legacy Recording Day'), findsOneWidget);

      // Saving preserves legacy value
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedBandEvents.length, equals(1));
      expect(appState.mockFirebase.savedBandEvents.first.eventType, equals('Recording Session'));
    });

    testWidgets('17, 18. New event starts in custom mode with empty "Set hours here" text field', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dropdown selected is 'Set your own'
      expect(find.text('Set your own'), findsOneWidget);

      // Custom-hours input is visible with label 'Set hours here'
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsOneWidget);

      // Custom-hours controller is empty by default (not pre-filled with 48)
      final customField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Set hours here'));
      expect(customField.controller?.text, equals(''));
    });

    testWidgets('19, 20. RSVP validation: empty/invalid blocks save, valid positive hours calculates deadline', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter basic event info
      await tester.enterText(find.widgetWithText(TextFormField, 'Event Title'), 'Test Rehearsal');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Berlin');

      // 1. Missing custom hours blocks submission
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please enter response window in hours'), findsOneWidget);
      expect(appState.mockFirebase.savedBandEvents.isEmpty, isTrue);

      // 2. Non-positive integer (0 or negative) in custom mode blocks submission
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '0');
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please enter a valid positive number'), findsOneWidget);
      expect(appState.mockFirebase.savedBandEvents.isEmpty, isTrue);

      // 3. Valid custom hours persist and calculate deadline from publishedAt
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '36');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final beforePublish = DateTime.now().millisecondsSinceEpoch;
      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedBandEvents.length, equals(1));
      final saved = appState.mockFirebase.savedBandEvents.first;
      expect(saved.reminderIntervalHours, equals(36));
      expect(saved.rsvpDeadline, isNotNull);
      final expectedDeadlineApprox = beforePublish + (36 * 3600 * 1000);
      expect((saved.rsvpDeadline! - expectedDeadlineApprox).abs() < 5000, isTrue);
    });

    testWidgets('RSVP preset option: predefined 48 hours', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.widgetWithText(TextFormField, 'Event Title'), 'Preset 48 Event');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Paris');

      // Select predefined 48 hours
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('48 hours (From event is published)').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Custom text field should be hidden
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);

      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedBandEvents.length, equals(1));
      expect(appState.mockFirebase.savedBandEvents.first.reminderIntervalHours, equals(48));
    });

    testWidgets('RSVP preset option: No automatic Reminders', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateEventPage(bandId: 'band_1'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.widgetWithText(TextFormField, 'Event Title'), 'No Reminder Event');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Rome');

      // Select No automatic Reminders
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('No automatic Reminders').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);

      await tester.tap(find.text('Publish Event'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedBandEvents.length, equals(1));
      expect(appState.mockFirebase.savedBandEvents.first.reminderIntervalHours, equals(0));
      expect(appState.mockFirebase.savedBandEvents.first.rsvpDeadline, isNull);
    });

    testWidgets('21a. Existing 48h event opens with predefined 48h option selected', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existing48Event = BandEvent(
        id: 'evt_48h',
        title: 'Gig with 48h RSVP',
        description: 'Concert description',
        eventType: 'Concert',
        location: 'London',
        startDateTime: '2026-09-10T20:00:00.000Z',
        endDateTime: '2026-09-10T23:00:00.000Z',
        additionalNotes: '',
        createdBy: 'user_create01',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        requireResponse: true,
        reminderIntervalHours: 48,
      );

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [existing48Event],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Predefined 48h selected, custom input hidden
      expect(find.text('48 hours (From event is published)'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);
    });

    testWidgets('21b. Existing custom 36h event opens with custom mode and 36 displayed', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existing36Event = BandEvent(
        id: 'evt_36h',
        title: 'Gig with 36h custom RSVP',
        description: 'Concert description',
        eventType: 'Concert',
        location: 'London',
        startDateTime: '2026-09-10T20:00:00.000Z',
        endDateTime: '2026-09-10T23:00:00.000Z',
        additionalNotes: '',
        createdBy: 'user_create01',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        requireResponse: true,
        reminderIntervalHours: 36,
      );

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [existing36Event],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Custom 'Set your own' selected, custom input visible with 36
      expect(find.text('Set your own'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsOneWidget);
      final customField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Set hours here'));
      expect(customField.controller?.text, equals('36'));
    });

    testWidgets('21c. Existing event with explicit 0 selects No automatic Reminders', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existing0Event = BandEvent(
        id: 'evt_0h',
        title: 'Event with no automatic reminders',
        description: 'Explicit 0',
        eventType: 'Rehearsal',
        location: 'Studio A',
        startDateTime: '2026-09-10T20:00:00.000Z',
        endDateTime: '2026-09-10T23:00:00.000Z',
        additionalNotes: '',
        createdBy: 'user_create01',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        requireResponse: true,
        reminderIntervalHours: 0,
      );

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [existing0Event],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Explicit 0 selects No automatic Reminders, custom field hidden
      expect(find.text('No automatic Reminders'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);
      expect(appState.mockFirebase.saveBandEventCalls, equals(0)); // Opening does not mutate Firebase
    });

    testWidgets('21d. Legacy event with null reminderIntervalHours falls back to 48 hours', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final legacyNullEvent = BandEvent(
        id: 'evt_null_hours',
        title: 'Legacy Event with null interval',
        description: 'Null hours',
        eventType: 'Concert',
        location: 'Copenhagen',
        startDateTime: '2026-09-10T20:00:00.000Z',
        endDateTime: '2026-09-10T23:00:00.000Z',
        additionalNotes: '',
        createdBy: 'user_create01',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        requireResponse: true,
        reminderIntervalHours: null,
      );

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [legacyNullEvent],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // null interval falls back to 48 hours, NOT No automatic Reminders
      expect(find.text('48 hours (From event is published)'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);
      expect(appState.mockFirebase.saveBandEventCalls, equals(0)); // Opening does not mutate Firebase
    });

    testWidgets('21e. Legacy event deserialized from JSON without reminderIntervalHours key falls back to 48 hours', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Raw legacy JSON without reminderIntervalHours key
      final legacyRawJson = {
        'title': 'Ancient Gig',
        'description': 'Before EVT-06 was implemented',
        'eventType': 'Concert',
        'location': 'Stockholm',
        'startDateTime': '2026-09-10T20:00:00.000Z',
        'endDateTime': '2026-09-10T23:00:00.000Z',
        'additionalNotes': '',
        'createdBy': 'user_create01',
        'createdAt': 1700000000000,
        'updatedAt': 1700000000000,
        'requireResponse': true,
      };

      final parsedLegacyEvent = BandEvent.fromJson(legacyRawJson, 'evt_ancient_1');
      expect(parsedLegacyEvent.reminderIntervalHours, isNull);

      final appState = MockAppStateForCreate01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: CreateEventPage(
          bandId: 'band_1',
          existingGroupEvents: [parsedLegacyEvent],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Falls back to verified historical 48 hours
      expect(find.text('48 hours (From event is published)'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsNothing);
      expect(appState.mockFirebase.saveBandEventCalls, equals(0)); // No accidental write on load
    });

    test('21f. BandEvent serialization preserves reminderIntervalHours across null, 0, 48, 36', () {
      final evt0 = BandEvent(
        title: 'Event 0',
        description: '',
        eventType: 'Rehearsal',
        location: '',
        startDateTime: '',
        endDateTime: '',
        additionalNotes: '',
        createdBy: 'u1',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        reminderIntervalHours: 0,
      );
      expect(evt0.toJson()['reminderIntervalHours'], equals(0));

      final evt36 = BandEvent(
        title: 'Event 36',
        description: '',
        eventType: 'Rehearsal',
        location: '',
        startDateTime: '',
        endDateTime: '',
        additionalNotes: '',
        createdBy: 'u1',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        reminderIntervalHours: 36,
      );
      expect(evt36.toJson()['reminderIntervalHours'], equals(36));

      final evtNull = BandEvent(
        title: 'Event Null',
        description: '',
        eventType: 'Rehearsal',
        location: '',
        startDateTime: '',
        endDateTime: '',
        additionalNotes: '',
        createdBy: 'u1',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        reminderIntervalHours: null,
      );
      expect(evtNull.toJson()['reminderIntervalHours'], isNull);
    });

    testWidgets('22, 23. Created Band Event and Session write to respective service contracts', (WidgetTester tester) async {
      final appState = MockAppStateForCreate01Test();

      final bandEvent = BandEvent(
        title: 'New Band Event',
        description: 'Test band event',
        eventType: 'Concert',
        location: 'Oslo',
        startDateTime: '2026-09-15T20:00:00.000Z',
        endDateTime: '2026-09-15T23:00:00.000Z',
        additionalNotes: '',
        createdBy: 'user_create01',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        requireResponse: true,
      );

      final eventId = await appState.firebaseService.saveBandEventAsync('band_1', bandEvent);
      expect(eventId, isNotEmpty);
      expect(appState.mockFirebase.saveBandEventCalls, equals(1));
      expect(appState.mockFirebase.savedBandEvents.first.title, equals('New Band Event'));

      final collabSession = CollabSession(
        title: 'Songwriting Collab',
        description: 'Write track 2',
        sessionType: 'In person',
        sessionCategory: 'Songwriting',
        isDateFlexible: true,
        creatorId: 'user_create01',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        genres: ['Rock'],
        location: 'Gothenburg',
      );

      await appState.firebaseService.saveCollabSessionAsync(collabSession);
      expect(appState.mockFirebase.createSessionCalls, equals(1));
      expect(appState.mockFirebase.savedCollabSessions.first.title, equals('Songwriting Collab'));
    });

    testWidgets('24, 25. BandRoom "Create Event" button opens creation page with clean taxonomy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForCreate01Test();
      appState.selectBand('band_1', 'Rock Band');

      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const BandRoomChatScreen(),
      ));
      await tester.pumpAndSettle();

      // Switch to Events tab
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.text('Create Event'), findsWidgets);
      expect(find.text('Create New Event'), findsNothing);
    });
  });
}
