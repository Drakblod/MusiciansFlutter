import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';

class MockEventDetailsFirebaseService extends FirebaseService {
  BandEvent? mockEvent;
  Band? mockBand;
  List<BandMember> mockMembers = [];
  Map<String, UserProfile> mockProfiles = {};

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    return Stream.value(mockEvent);
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return mockBand;
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return mockMembers;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return mockEvent != null ? [mockEvent!] : [];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return mockProfiles[userId] ?? UserProfile(userId: userId ?? 'u1', displayName: 'User $userId');
  }

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {}

  @override
  Future<Map<String, dynamic>> triggerEventReminderAsync(
    String bandId,
    String eventId,
    String reminderType,
  ) async {
    lastTriggerReminderType = reminderType;
    return {
      'status': 'completed',
      'successCount': 3,
      'failureCount': 0,
      'attemptedCount': 3,
    };
  }

  String? lastTriggerReminderType;
}

class MockEventDetailsAppState extends AppState {
  final MockEventDetailsFirebaseService mockFirebase;
  final String? testUserId;

  MockEventDetailsAppState(this.mockFirebase, {this.testUserId = 'user_1'});

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => testUserId;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: testUserId ?? 'user_1',
        displayName: 'Alex',
      );
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

  BandEvent createTestBandEvent({
    required String title,
    String createdBy = 'leader_1',
    String location = 'Main Stage',
    String description = 'Event description',
    Map<String, EventResponse> responses = const {},
  }) {
    return BandEvent(
      id: 'evt_1',
      title: title,
      description: description,
      eventType: 'Concert',
      location: location,
      startDateTime: '2026-09-16T19:00:00Z',
      endDateTime: '2026-09-16T21:00:00Z',
      additionalNotes: '',
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      requireResponse: true,
      responses: responses,
    );
  }

  Widget createTestWidget({
    required BandEvent event,
    required MockEventDetailsFirebaseService mockFirebase,
    String role = 'Member',
    String currentUserId = 'user_1',
  }) {
    mockFirebase.mockEvent = event;
    mockFirebase.mockMembers = [
      BandMember(userId: currentUserId, role: role, nickname: 'Alex'),
    ];

    return ChangeNotifierProvider<AppState>(
      create: (_) => MockEventDetailsAppState(mockFirebase, testUserId: currentUserId),
      child: MaterialApp(
        home: EventDetailsPage(
          bandId: 'band_1',
          eventId: event.id ?? 'evt_1',
          initialEvent: event,
        ),
      ),
    );
  }

  group('EventDetailsPage RSVP Display Tests', () {
    testWidgets('1. Reflects Yes response when status is "Yes" in responses', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Torsdagskul',
        responses: {
          'user_1': EventResponse(
            status: 'Yes',
            timestamp: DateTime.now(),
          ),
        },
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('"Torsdagskul"'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'CustomTopBar' && (w as dynamic).title == 'Event Details',
        ),
        findsOneWidget,
      );
      expect(find.text('EVENT DETAILS'), findsNothing);
      expect(find.text('YOUR RESPONSE'), findsOneWidget);
      expect(find.text('YES'), findsOneWidget);

      // Verify that YES button is rendered with success styling (selected)
      final yesContainer = tester.widget<Container>(
        find.ancestor(
          of: find.text('YES'),
          matching: find.byType(Container),
        ).first,
      );
      final boxDecoration = yesContainer.decoration as BoxDecoration;
      final borderColor = (boxDecoration.border as Border).top.color;
      // AppTheme.success is selected border color
      expect(borderColor, equals(const Color(0xFF2ECC71)));
    });

    testWidgets('2. Reflects Uncertain response and displays comment', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Torsdagskul',
        responses: {
          'user_1': EventResponse(
            status: 'Uncertain',
            comment: 'Might be late',
            timestamp: DateTime.now(),
          ),
        },
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('WHY ARE YOU UNCERTAIN? (mandatory)'), findsOneWidget);
      expect(find.text('Might be late'), findsOneWidget);
    });

    testWidgets('3. Reminder Settings buttons are removed from Event Overview', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(title: 'Stockholm Gig');

      await tester.pumpWidget(createTestWidget(
        event: event,
        mockFirebase: mockFb,
        role: 'Leader',
      ));
      await tester.pumpAndSettle();

      expect(find.text('REMINDER SETTINGS'), findsNothing);
      expect(find.text('Trigger 24h Reminder'), findsNothing);
      expect(find.text('Trigger 48h Reminder'), findsNothing);
      expect(find.text('Trigger 72h Reminder'), findsNothing);
      expect(find.text('Trigger Final Reminder'), findsNothing);
    });

    testWidgets('4. Header displays exact hierarchy: Band name, quoted Event title, Date/Time, Location, Description', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      mockFb.mockBand = Band(id: 'band_1', name: 'The Rolling Beats');
      final event = createTestBandEvent(
        title: 'Summer Tour Kickoff',
        location: 'Central Arena',
        description: 'Important rehearsal before summer gig.',
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('The Rolling Beats'), findsOneWidget);
      expect(find.text('"Summer Tour Kickoff"'), findsOneWidget);
      expect(find.text('Central Arena'), findsOneWidget);
      expect(find.text('Important rehearsal before summer gig.'), findsOneWidget);

      // Event type 'Concert' is NOT rendered in the overview header
      expect(find.text('Concert'), findsNothing);
      expect(find.textContaining('EVENT SCHEDULE ('), findsNothing);

      // Verify vertical positioning: Band name above quoted title, quoted title above Date/Time
      final bandPos = tester.getTopLeft(find.text('The Rolling Beats')).dy;
      final titlePos = tester.getTopLeft(find.text('"Summer Tour Kickoff"')).dy;
      final datePos = tester.getTopLeft(find.byIcon(Icons.calendar_today_outlined)).dy;
      final locationPos = tester.getTopLeft(find.text('Central Arena')).dy;
      final descPos = tester.getTopLeft(find.text('Important rehearsal before summer gig.')).dy;

      expect(bandPos < titlePos, isTrue);
      expect(titlePos < datePos, isTrue);
      expect(datePos < locationPos, isTrue);
      expect(locationPos < descPos, isTrue);
    });

    testWidgets('5. Header falls back to "Band" if band name is missing or empty', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      mockFb.mockBand = null;
      final event = createTestBandEvent(title: 'Local Jam');

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('Band'), findsOneWidget);
      expect(find.text('"Local Jam"'), findsOneWidget);
    });

    testWidgets('6. Attendance breakdown is completely removed from Event Details', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Album Recording',
        responses: {
          'user_1': EventResponse(status: 'Yes', timestamp: DateTime.now()),
          'user_2': EventResponse(status: 'No', timestamp: DateTime.now()),
          'user_3': EventResponse(status: 'Uncertain', comment: 'Flu', timestamp: DateTime.now()),
        },
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      // Attendance breakdown heading and pills must not exist
      expect(find.text('ATTENDANCE RESPONSES'), findsNothing);
      expect(find.textContaining('YES ('), findsNothing);
      expect(find.textContaining('NO ('), findsNothing);
      expect(find.textContaining('UNCERTAIN ('), findsNothing);
      expect(find.textContaining('NO ANSWER ('), findsNothing);
    });

    testWidgets('7. Non-creator cannot see Event Creator Actions or View RSVP Results', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Private Event',
        createdBy: 'actual_creator_456',
      );

      await tester.pumpWidget(createTestWidget(
        event: event,
        mockFirebase: mockFb,
        currentUserId: 'different_user_123',
      ));
      await tester.pumpAndSettle();

      expect(find.text('EVENT CREATOR ACTIONS'), findsNothing);
      expect(find.text('View RSVP Results'), findsNothing);
      expect(find.text('Edit Event'), findsNothing);
      expect(find.text('Finalize Event & Lock RSVPs'), findsNothing);
      expect(find.text('Find Substitute(s)'), findsNothing);
    });

    testWidgets('8. Event Creator sees Event Creator Actions and View RSVP Results navigates to RSVP Results', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Festival Headliner',
        createdBy: 'creator_789',
      );

      await tester.pumpWidget(createTestWidget(
        event: event,
        mockFirebase: mockFb,
        currentUserId: 'creator_789',
      ));
      await tester.pumpAndSettle();

      expect(find.text('EVENT CREATOR ACTIONS'), findsOneWidget);
      expect(find.text('View RSVP Results'), findsOneWidget);
      expect(find.text('Edit Event'), findsOneWidget);
      expect(find.text('Finalize Event & Lock RSVPs'), findsOneWidget);
      expect(find.text('Find Substitute(s)'), findsOneWidget);

      // Tap View RSVP Results and verify navigation
      await tester.tap(find.text('View RSVP Results'));
      await tester.pumpAndSettle();

      expect(find.byType(EventResultsPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'CustomTopBar' && (w as dynamic).title == 'RSVP RESULTS',
        ),
        findsOneWidget,
      );
    });

    testWidgets('9. 320 px screen width renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockFb = MockEventDetailsFirebaseService();
      mockFb.mockBand = Band(id: 'band_1', name: 'Very Long Symphonic Orchestra Band Name');
      final event = createTestBandEvent(
        title: 'Massive Summer Festival Rehearsal Series Kickoff',
        location: 'Extremely Long Venue Location Address, Sweden',
        description: 'Detailed description with many words to test wrapping.',
        createdBy: 'creator_789',
      );

      await tester.pumpWidget(createTestWidget(
        event: event,
        mockFirebase: mockFb,
        currentUserId: 'creator_789',
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('10. Multi-part events: no EVENT SCHEDULE badge in overview header, schedule part cards render and function', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      mockFb.mockBand = Band(id: 'band_1', name: 'Multi Band');
      final event = BandEvent(
        id: 'evt_multi',
        title: 'Tour 2026',
        description: 'Multi event series',
        eventType: 'Concert',
        location: 'Venue A',
        startDateTime: '2026-09-16T19:00:00Z',
        endDateTime: '2026-09-16T21:00:00Z',
        additionalNotes: '',
        createdBy: 'leader_1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(
            id: 'reh_1',
            date: '2026-09-17',
            startTime: '18:00',
            endTime: '20:00',
            location: 'Venue B',
            type: 'Rehearsal',
            title: 'Rehearsal 1',
          ),
          EventRehearsal(
            id: 'reh_2',
            date: '2026-09-18',
            startTime: '19:00',
            endTime: '22:00',
            location: 'Venue C',
            type: 'Gig',
            title: 'Live Gig',
          ),
        ],
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      // Header overview has Band name and quoted title
      expect(find.text('Multi Band'), findsOneWidget);
      expect(find.text('"Tour 2026"'), findsOneWidget);

      // No Event Type and no EVENT SCHEDULE badge in overview header
      expect(find.textContaining('EVENT SCHEDULE ('), findsNothing);

      // Schedule cards still render further down
      expect(find.text('EVENT 1'), findsOneWidget);
      expect(find.text('Rehearsal 1'), findsOneWidget);
      expect(find.text('EVENT 2'), findsOneWidget);
      expect(find.text('Live Gig'), findsOneWidget);
    });
  });
}
