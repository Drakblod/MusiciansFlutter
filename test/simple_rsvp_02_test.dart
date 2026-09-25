import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';
import 'package:musicians_flutter/views/create_event_page.dart';

class MockSimpleRsvpFirebaseService extends FirebaseService {
  BandEvent? mockEvent;
  List<BandMember> mockMembers = [];
  Map<String, UserProfile> mockProfiles = {};
  List<BandEvent> mockBandEvents = [];

  String? lastUpdatedBandId;
  String? lastUpdatedEventId;
  String? lastUpdatedScheduleItemId;
  String? lastUpdatedUserId;
  String? lastUpdatedStatus;
  String? lastUpdatedUncertainReason;

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return 'Leader';
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: 'Test Band',
      userRole: 'Leader',
    );
  }

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    if (mockEvent != null && mockEvent!.id == eventId) {
      return Stream.value(mockEvent);
    }
    final found = mockBandEvents.where((e) => e.id == eventId);
    if (found.isNotEmpty) {
      return Stream.value(found.first);
    }
    return Stream.value(mockEvent);
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return mockMembers.isNotEmpty ? mockMembers : [BandMember(userId: 'user_1', role: 'Leader')];
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    if (mockBandEvents.isNotEmpty) return mockBandEvents;
    if (mockEvent != null) return [mockEvent!];
    return [];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    if (userId != null && mockProfiles.containsKey(userId)) {
      return mockProfiles[userId];
    }
    return UserProfile(
      userId: userId ?? 'u_default',
      displayName: 'User $userId',
    );
  }

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
    String? uncertainReason,
  }) async {
    lastUpdatedBandId = bandId;
    lastUpdatedEventId = eventId;
    lastUpdatedUserId = userId;
    lastUpdatedStatus = status;
    lastUpdatedUncertainReason = uncertainReason ?? comment;
  }

  @override
  Future<void> updateScheduleItemResponseAsync(
    String bandId,
    String eventId,
    String scheduleItemId,
    String userId,
    String status, {
    String? uncertainReason,
  }) async {
    lastUpdatedBandId = bandId;
    lastUpdatedEventId = eventId;
    lastUpdatedScheduleItemId = scheduleItemId;
    lastUpdatedUserId = userId;
    lastUpdatedStatus = status;
    lastUpdatedUncertainReason = uncertainReason;
  }
}

class MockSimpleRsvpAppState extends AppState {
  final MockSimpleRsvpFirebaseService mockFirebase;
  final String _testUserId;

  MockSimpleRsvpAppState(this.mockFirebase, {String testUserId = 'user_1'})
      : _testUserId = testUserId;

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => _testUserId;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: _testUserId,
        displayName: 'Current Test User',
        mainInstrument: 'Guitar',
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

  group('SIMPLE-RSVP-02 Tests', () {
    test('1. BandEvent model parses and serializes scheduleResponses correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawJson = {
        'id': 'ev_100',
        'title': 'Main Big Event',
        'description': 'Main event description',
        'eventType': 'Concert',
        'location': 'Main Venue',
        'startDateTime': '2026-10-01T20:00:00Z',
        'endDateTime': '2026-10-01T23:00:00Z',
        'createdBy': 'leader_1',
        'createdAt': now,
        'updatedAt': now,
        'Rehearsals': [
          {
            'id': 'sched_1',
            'title': 'Soundcheck',
            'type': 'Soundcheck',
            'date': '2026-10-01',
            'startTime': '16:00',
            'endTime': '17:00',
            'location': 'Main Stage',
          },
        ],
        'ScheduleResponses': {
          'sched_1': {
            'user_1': {
              'status': 'YES',
              'timestamp': now,
            },
            'user_2': {
              'status': 'UNCERTAIN',
              'uncertainReason': 'Stuck in traffic',
              'timestamp': now,
            },
          },
        },
      };

      final event = BandEvent.fromJson(rawJson, 'ev_100');
      expect(event.rehearsals.length, 1);
      expect(event.scheduleResponses.containsKey('sched_1'), isTrue);
      expect(event.scheduleResponses['sched_1']!['user_1']?.status, 'YES');
      expect(event.scheduleResponses['sched_1']!['user_2']?.status, 'UNCERTAIN');
      expect(event.scheduleResponses['sched_1']!['user_2']?.uncertainReason, 'Stuck in traffic');

      final serialized = event.toJson();
      expect(serialized['ScheduleResponses'], isNotNull);
      expect(serialized['ScheduleResponses']['sched_1']['user_1']['status'], 'YES');
      expect(serialized['ScheduleResponses']['sched_1']['user_2']['uncertainReason'], 'Stuck in traffic');
    });

    testWidgets('2. CreateEventPage enforces max 6 events cap (1 main + 5 attached)', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockSimpleRsvpFirebaseService();
      final appState = MockSimpleRsvpAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: CreateEventPage(bandId: 'band_1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Initially "+ Add Event" is visible
      expect(find.text('+ Add Event'), findsOneWidget);

      // Add 5 events to reach max 6 (1 main + 5 attached)
      for (int i = 0; i < 5; i++) {
        final addBtn = find.text('+ Add Event');
        await tester.ensureVisible(addBtn);
        await tester.pumpAndSettle();
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        final submitBtn = find.widgetWithText(ElevatedButton, 'Add Event');
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();
      }

      // "+ Add Event" should now be hidden and max notice shown
      expect(find.text('+ Add Event'), findsNothing);
      expect(find.text('Maximum 6 events per Event Schedule.'), findsOneWidget);
    });

    testWidgets('3. EventDetailsPage renders sequential RSVP for multi-schedule event', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'event_multi_1',
        title: 'Headline Festival',
        description: 'Big festival gig',
        eventType: 'Festival',
        location: 'Park Arena',
        startDateTime: '2026-10-05T18:00:00Z',
        endDateTime: '2026-10-05T23:00:00Z',
        additionalNotes: 'Bring gear',
        createdBy: 'leader_user',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(
            id: 'sched_loadin',
            title: 'Load-in & Line Check',
            type: 'Prep',
            date: '2026-10-05',
            startTime: '14:00',
            endTime: '15:30',
            location: 'Backstage',
          ),
        ],
        responses: {},
        scheduleResponses: {},
      );

      final mockService = MockSimpleRsvpFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [
        BandMember(userId: 'user_1', nickname: 'Alice'),
      ];

      final appState = MockSimpleRsvpAppState(mockService, testUserId: 'user_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventDetailsPage(
              bandId: 'band_1',
              eventId: 'event_multi_1',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Check EVENT 1 (Main Event) and EVENT 2 (Load-in) are displayed
      expect(find.textContaining('EVENT 1'), findsWidgets);
      expect(find.textContaining('EVENT 2'), findsWidgets);

      // Check RSVP buttons inside the active accordion item
      expect(find.text('YES'), findsWidgets);
      expect(find.text('NO'), findsWidgets);
      expect(find.text('UNCERTAIN'), findsWidgets);

      // Select YES on Event 1 (accordion item 0)
      await tester.tap(find.text('YES').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Save RSVP
      expect(find.text('Save RSVP'), findsWidgets);
      await tester.tap(find.text('Save RSVP').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(mockService.lastUpdatedEventId, 'event_multi_1');
      expect(mockService.lastUpdatedUserId, 'user_1');
      expect(mockService.lastUpdatedStatus, 'Yes');
    });

    testWidgets('4. EventDetailsPage displays all events answered confirmation banner', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'event_multi_answered',
        title: 'Two Part Gig',
        description: 'Two part gig description',
        eventType: 'Concert',
        location: 'Club Hall',
        startDateTime: '2026-10-06T19:00:00Z',
        endDateTime: '2026-10-06T22:00:00Z',
        additionalNotes: 'None',
        createdBy: 'leader_user',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(
            id: 'sched_warmup',
            title: 'Warmup',
            type: 'Rehearsal',
            date: '2026-10-06',
            startTime: '17:00',
            endTime: '18:00',
            location: 'Room B',
          ),
        ],
        responses: {
          'user_1': EventResponse(status: 'attending', timestamp: now),
        },
        scheduleResponses: {
          'sched_warmup': {
            'user_1': EventResponse(status: 'attending', timestamp: now),
          },
        },
      );

      final mockService = MockSimpleRsvpFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [BandMember(userId: 'user_1')];

      final appState = MockSimpleRsvpAppState(mockService, testUserId: 'user_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventDetailsPage(
              bandId: 'band_1',
              eventId: 'event_multi_answered',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Check confirmation banner
      expect(find.text('✓ All events answered'), findsOneWidget);
    });

    testWidgets('5. EventResultsPage displays multi-schedule items with filter pills and primary skills', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'event_results_multi',
        title: 'Grand Show',
        description: 'Grand theatre show',
        eventType: 'Concert',
        location: 'Grand Theatre',
        startDateTime: '2026-10-10T20:00:00Z',
        endDateTime: '2026-10-10T23:00:00Z',
        additionalNotes: 'Backstage pass required',
        createdBy: 'leader_user',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(
            id: 'sched_rehearsal',
            title: 'Dress Rehearsal',
            type: 'Rehearsal',
            date: '2026-10-10',
            startTime: '15:00',
            endTime: '17:00',
            location: 'Grand Theatre Stage',
          ),
        ],
        responses: {
          'u1': EventResponse(status: 'attending', timestamp: now),
          'u2': EventResponse(status: 'declined', timestamp: now),
        },
        scheduleResponses: {
          'sched_rehearsal': {
            'u1': EventResponse(status: 'attending', timestamp: now),
            'u2': EventResponse(
              status: 'UNCERTAIN',
              uncertainReason: 'Arriving late by train',
              timestamp: now,
            ),
          },
        },
      );

      final mockService = MockSimpleRsvpFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [
        BandMember(userId: 'u1', nickname: 'Alice'),
        BandMember(userId: 'u2', nickname: 'Bob'),
      ];
      mockService.mockProfiles = {
        'u1': UserProfile(userId: 'u1', displayName: 'Alice Lead', mainInstrument: 'Lead Guitar'),
        'u2': UserProfile(userId: 'u2', displayName: 'Bob Drummer', mainInstrument: 'Drums'),
      };

      final appState = MockSimpleRsvpAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventResultsPage(
              bandId: 'band_1',
              eventId: 'event_results_multi',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Check EVENT 1 and EVENT 2 headers
      expect(find.textContaining('EVENT 1'), findsOneWidget);
      expect(find.textContaining('EVENT 2'), findsOneWidget);

      // Event 1 has YES (1), NO (1)
      expect(find.text('YES (1)'), findsWidgets);
      expect(find.text('NO (1)'), findsWidgets);

      // Event 2 has UNCERTAIN (1)
      expect(find.text('UNCERTAIN (1)'), findsOneWidget);

      // Tap on UNCERTAIN (1) pill on Event 2 to expand
      await tester.tap(find.text('UNCERTAIN (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Bob Drummer, his primary skill "Drums", and uncertain reason are displayed
      expect(find.text('Bob Drummer'), findsOneWidget);
      expect(find.text('Drums'), findsOneWidget);
      expect(find.text('"Arriving late by train"'), findsOneWidget);
    });
  });
}
