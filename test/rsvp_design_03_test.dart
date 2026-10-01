import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/event_room.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/create_event_page.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/manage_events_screen.dart';
import 'package:musicians_flutter/utils/date_parser.dart';

class MockRsvpDesignFirebaseService extends FirebaseService {
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
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {'band_1': 'Test Band'};
  }

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
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    return {};
  }

  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) {
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
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    if (mockBandEvents.isNotEmpty) return Stream.value(mockBandEvents);
    if (mockEvent != null) return Stream.value([mockEvent!]);
    return Stream.value([]);
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

class MockRsvpDesignAppState extends AppState {
  final MockRsvpDesignFirebaseService mockFirebase;
  final String _testUserId;

  MockRsvpDesignAppState(this.mockFirebase, {String testUserId = 'creator_user_1'})
      : _testUserId = testUserId;

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => _testUserId;

  @override
  String? get activeBandId => 'band_1';

  @override
  String? get activeBandName => 'Test Band';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: _testUserId,
        displayName: 'Test User Profile',
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

  group('RSVP-DESIGN-03 Comprehensive Checklist Tests', () {
    testWidgets('1 & 2. CreateEventPage exact labels and structure: Main Event Name, Event Description directly below, Start/End Date', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockRsvpDesignFirebaseService();
      final appState = MockRsvpDesignAppState(mockService);

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

      // 1. Exact label "Main Event Name"
      expect(find.text('Main Event Name'), findsOneWidget);

      // 2. Exact label "Event Description (Describe ALL parts of Main Event here)"
      expect(find.text('Event Description (Describe ALL parts of Main Event here)'), findsOneWidget);

      // 3. Parent container Date Range (Start Date and End Date) removed to save space and computed automatically
      expect(find.text('Start Date'), findsNothing);
      expect(find.text('End Date'), findsNothing);
      expect(find.text('Start Time'), findsNothing);
      expect(find.text('End Time'), findsNothing);

      // 4. Placeholder above attached schedule items
      expect(find.text('EVENT SCHEDULE'), findsOneWidget);
      expect(find.textContaining('Main Event Name'), findsWidgets);
    });

    testWidgets('5 & 6. CreateEventPage attached items start from EVENT 1 and maximum 6 attached events', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockRsvpDesignFirebaseService();
      final appState = MockRsvpDesignAppState(mockService);

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

      // Add 6 attached events
      for (int i = 0; i < 6; i++) {
        final addBtn = find.text('+ Add Event');
        expect(addBtn, findsOneWidget);
        await tester.ensureVisible(addBtn);
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        final submitBtn = find.widgetWithText(ElevatedButton, 'Add Event');
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();
      }

      // First attached item is EVENT 1 (not EVENT 2)
      expect(find.text('EVENT 1'), findsOneWidget);
      expect(find.text('EVENT 6'), findsOneWidget);

      // + Add Event is gone and limit notice is shown
      expect(find.text('+ Add Event'), findsNothing);
      expect(find.text('Maximum 6 events per Event Schedule.'), findsOneWidget);
    });

    testWidgets('7. EventDetailsPage restricts Creator Actions strictly to createdBy user', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'event_creator_test',
        title: 'Main Fest',
        description: 'Festival desc',
        eventType: 'Festival',
        location: 'Park',
        startDateTime: '2026-10-10T00:00:00Z',
        endDateTime: '2026-10-10T23:59:59Z',
        additionalNotes: 'None',
        createdBy: 'actual_creator_123',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [
        BandMember(userId: 'non_creator_leader', role: 'Leader'),
        BandMember(userId: 'actual_creator_123', role: 'Member'),
      ];

      // Case A: Current user is NOT the creator (even if Leader)
      final appStateNonCreator = MockRsvpDesignAppState(mockService, testUserId: 'non_creator_leader');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appStateNonCreator,
          child: MaterialApp(
            home: EventDetailsPage(
              bandId: 'band_1',
              eventId: 'event_creator_test',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Creator actions should NOT be shown
      expect(find.text('EVENT CREATOR ACTIONS'), findsNothing);
      expect(find.text('Edit Event'), findsNothing);
      expect(find.text('Finalize Event & Lock RSVPs'), findsNothing);
      expect(find.text('Find Substitute(s)'), findsNothing);

      // Case B: Current user IS the creator
      final appStateCreator = MockRsvpDesignAppState(mockService, testUserId: 'actual_creator_123');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appStateCreator,
          child: MaterialApp(
            home: EventDetailsPage(
              bandId: 'band_1',
              eventId: 'event_creator_test',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Creator actions SHOULD be shown
      expect(find.text('EVENT CREATOR ACTIONS'), findsOneWidget);
      expect(find.text('Edit Event'), findsOneWidget);
      expect(find.text('Finalize Event & Lock RSVPs'), findsOneWidget);
      expect(find.text('Find Substitute(s)'), findsOneWidget);
    });

    testWidgets('8 & 9. Band Room Events tab displays exact headings and routes finalized/past to Results', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 5));
      final pastDate = now.subtract(const Duration(days: 5));

      final newEvent = BandEvent(
        id: 'ev_new',
        title: 'New Unfinalized Event',
        description: 'New desc',
        location: 'Club A',
        additionalNotes: 'None',
        eventType: 'Concert',
        startDateTime: futureDate.toIso8601String(),
        endDateTime: futureDate.add(const Duration(hours: 3)).toIso8601String(),
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: false,
        responses: {
          'creator_1': EventResponse(status: 'Yes', timestamp: now),
        },
      );

      final finalizedEvent = BandEvent(
        id: 'ev_finalized',
        title: 'Finalized Upcoming Event',
        description: 'Finalized desc',
        location: 'Club B',
        additionalNotes: 'None',
        eventType: 'Concert',
        startDateTime: futureDate.toIso8601String(),
        endDateTime: futureDate.add(const Duration(hours: 3)).toIso8601String(),
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: true,
      );

      final pastEvent = BandEvent(
        id: 'ev_past',
        title: 'Past Event',
        description: 'Past desc',
        location: 'Club C',
        additionalNotes: 'None',
        eventType: 'Concert',
        startDateTime: pastDate.toIso8601String(),
        endDateTime: pastDate.add(const Duration(hours: 3)).toIso8601String(),
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: false,
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockMembers = [
        BandMember(userId: 'creator_1', nickname: 'Creator', role: 'Leader'),
      ];
      mockService.mockBandEvents = [newEvent, finalizedEvent, pastEvent];
      final appState = MockRsvpDesignAppState(mockService, testUserId: 'creator_1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: const MaterialApp(
            home: BandRoomChatScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Events tab
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      // 8. Verify exact headings
      expect(find.text('New Events (Need RSVP)'), findsOneWidget);
      expect(find.text('Upcoming Events (Finalized)'), findsOneWidget);
      expect(find.text('Past Events'), findsOneWidget);

      // 9. Tap on Finalized event card -> navigates to EventResultsPage
      await tester.tap(find.text('Finalized Upcoming Event'));
      await tester.pumpAndSettle();
      expect(find.byType(EventResultsPage), findsOneWidget);
    });

    testWidgets('10, 11, 12, 13. EventResultsPage standardized 5 pills, substitute pill, primary skill only, tap expansion', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'event_results_full_test',
        title: 'Autumn Gala',
        description: 'Gala concert at city hall',
        eventType: 'Concert',
        location: 'City Hall',
        startDateTime: '2026-11-01T00:00:00Z',
        endDateTime: '2026-11-01T23:59:59Z',
        additionalNotes: 'Formal dress',
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: true,
        responses: {
          'u1': EventResponse(status: 'YES', timestamp: now),
          'u2': EventResponse(status: 'NO', timestamp: now),
          'u3': EventResponse(status: 'UNCERTAIN', uncertainReason: 'Waiting for childcare', timestamp: now),
        },
        substituteAssignments: {
          'sub_slot_1': SubstituteAssignment(
            slotId: 'sub_slot_1',
            assignedUserId: 'sub_user_99',
            assignedUserName: 'Sam Sub',
            instrument: 'Bass',
            replacedMemberName: 'Bob Original',
            status: 'assigned',
          ),
        },
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [
        BandMember(userId: 'u1', nickname: 'Alice'),
        BandMember(userId: 'u2', nickname: 'Bob'),
        BandMember(userId: 'u3', nickname: 'Charlie'),
        BandMember(userId: 'u4', nickname: 'Diana'), // No answer
      ];
      mockService.mockProfiles = {
        'u1': UserProfile(userId: 'u1', displayName: 'Alice Vocal', mainInstrument: 'Vocals', instruments: ['Guitar', 'Piano']),
        'u2': UserProfile(userId: 'u2', displayName: 'Bob Bass', mainInstrument: 'Bass'),
        'u3': UserProfile(userId: 'u3', displayName: 'Charlie Drum', mainInstrument: 'Drums'),
        'u4': UserProfile(userId: 'u4', displayName: 'Diana Keys', mainInstrument: 'Keyboard'),
        'sub_user_99': UserProfile(userId: 'sub_user_99', displayName: 'Sam Sub', mainInstrument: 'Bass'),
      };

      final appState = MockRsvpDesignAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventResultsPage(
              bandId: 'band_1',
              eventId: 'event_results_full_test',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Top overview card shows title & date
      expect(find.text('Autumn Gala'), findsOneWidget);
      expect(find.text('Finalized'), findsOneWidget);

      // 10. Horizontal pills: YES (1), NO (1), UNCERTAIN (1), NO ANSWER (1), SUBSTITUTES (1)
      expect(find.text('YES (1)'), findsOneWidget);
      expect(find.text('NO (1)'), findsOneWidget);
      expect(find.text('UNCERTAIN (1)'), findsOneWidget);
      expect(find.text('NO ANSWER (1)'), findsOneWidget);
      expect(find.text('SUBSTITUTES (1)'), findsOneWidget);

      // Initially names are hidden
      expect(find.text('Alice Vocal'), findsNothing);
      expect(find.text('Sam Sub'), findsNothing);

      // Tap YES (1) pill -> Alice expands
      await tester.tap(find.text('YES (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Alice Vocal'), findsOneWidget);
      // 12. Only primary skill displayed (Vocals), secondary skills (Guitar, Piano) NOT shown
      expect(find.text('Vocals'), findsOneWidget);
      expect(find.text('Guitar'), findsNothing);
      expect(find.text('Piano'), findsNothing);

      // Tap YES (1) pill again -> collapses
      await tester.tap(find.text('YES (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Alice Vocal'), findsNothing);

      // Tap SUBSTITUTES (1) -> Sam Sub expands with replacement
      await tester.tap(find.text('SUBSTITUTES (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Sam Sub'), findsOneWidget);
      expect(find.text('Bass'), findsOneWidget);
      expect(find.text('Replacing Bob Original'), findsOneWidget);

      // Tap UNCERTAIN (1) -> Charlie Drum expands with reason
      await tester.tap(find.text('UNCERTAIN (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Charlie Drum'), findsOneWidget);
      expect(find.text('"Waiting for childcare"'), findsOneWidget);
    });

    testWidgets('14. Layout works at 320 px width without horizontal overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final event = BandEvent(
        id: 'ev_narrow',
        title: 'Narrow Screen Gala',
        description: 'Testing narrow 320px screen responsiveness',
        eventType: 'Concert',
        location: 'Narrow Hall',
        startDateTime: '2026-11-01T00:00:00Z',
        endDateTime: '2026-11-01T23:59:59Z',
        additionalNotes: 'None',
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: true,
        rehearsals: [
          EventRehearsal(
            id: 'item_1',
            title: 'Narrow Item 1',
            type: 'Prep',
            date: '2026-11-01',
            startTime: '10:00',
            endTime: '12:00',
          ),
        ],
        responses: {
          'u1': EventResponse(status: 'YES', timestamp: now),
        },
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockEvent = event;
      mockService.mockMembers = [BandMember(userId: 'u1')];
      final appState = MockRsvpDesignAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventResultsPage(
              bandId: 'band_1',
              eventId: 'ev_narrow',
              initialEvent: event,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // No assertion errors or overflow errors thrown
      expect(tester.takeException(), isNull);
      expect(find.text('Narrow Screen Gala'), findsOneWidget);
      expect(find.textContaining('EVENT 1'), findsOneWidget);
    });

    test('15. formatMainEventDateRange handles same day, same month, different months, and different years correctly', () {
      // Case 1: Same day -> "September 27, 2026"
      final sameDayStart = DateTime(2026, 9, 27, 10, 0);
      final sameDayEnd = DateTime(2026, 9, 27, 18, 0);
      expect(formatMainEventDateRange(sameDayStart, sameDayEnd), equals('September 27, 2026'));

      // Case 2: Same month -> "September 27–29, 2026" (with en-dash)
      final sameMonthStart = DateTime(2026, 9, 27);
      final sameMonthEnd = DateTime(2026, 9, 29);
      expect(formatMainEventDateRange(sameMonthStart, sameMonthEnd), equals('September 27\u201329, 2026'));

      // Case 3: Different months, same year -> "September 30 – October 2, 2026"
      final diffMonthsStart = DateTime(2026, 9, 30);
      final diffMonthsEnd = DateTime(2026, 10, 2);
      expect(formatMainEventDateRange(diffMonthsStart, diffMonthsEnd), equals('September 30 \u2013 October 2, 2026'));

      // Case 4: Different years -> "December 30, 2026 – January 2, 2027"
      final diffYearsStart = DateTime(2026, 12, 30);
      final diffYearsEnd = DateTime(2027, 1, 2);
      expect(formatMainEventDateRange(diffYearsStart, diffYearsEnd), equals('December 30, 2026 \u2013 January 2, 2027'));

      // Verify no weekdays or clock times in formatted results
      expect(formatMainEventDateRange(sameDayStart, sameDayEnd).contains(RegExp(r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun|:\d\d)')), isFalse);
      expect(formatMainEventDateRange(sameMonthStart, sameMonthEnd).contains(RegExp(r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun|:\d\d)')), isFalse);
      expect(formatMainEventDateRange(diffMonthsStart, diffMonthsEnd).contains(RegExp(r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun|:\d\d)')), isFalse);
      expect(formatMainEventDateRange(diffYearsStart, diffYearsEnd).contains(RegExp(r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun|:\d\d)')), isFalse);
    });

    testWidgets('16. EventResultsPage standalone Event Description card directly below Main Event Name, with empty fallback', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      // Case A: With description
      final eventWithDesc = BandEvent(
        id: 'ev_desc',
        title: 'Festival Deluxe',
        description: 'Complete festival details and soundcheck guidelines.',
        eventType: 'Festival',
        location: 'Park',
        startDateTime: '2026-10-10T00:00:00Z',
        endDateTime: '2026-10-10T23:59:59Z',
        additionalNotes: '',
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: true,
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockEvent = eventWithDesc;
      final appState = MockRsvpDesignAppState(mockService);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventResultsPage(
              key: const ValueKey('with_desc'),
              bandId: 'band_1',
              eventId: 'ev_desc',
              initialEvent: eventWithDesc,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Event Description'), findsOneWidget);
      expect(find.text('Complete festival details and soundcheck guidelines.'), findsOneWidget);

      // Case B: Without description (empty) -> shows fallback
      final eventNoDesc = BandEvent(
        id: 'ev_no_desc',
        title: 'Festival Deluxe No Desc',
        description: '',
        eventType: 'Festival',
        location: 'Park',
        startDateTime: '2026-10-10T00:00:00Z',
        endDateTime: '2026-10-10T23:59:59Z',
        additionalNotes: '',
        createdBy: 'creator_1',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        isLocked: true,
      );
      mockService.mockEvent = eventNoDesc;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: EventResultsPage(
              key: const ValueKey('no_desc'),
              bandId: 'band_1',
              eventId: 'ev_no_desc',
              initialEvent: eventNoDesc,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Event Description'), findsOneWidget);
      expect(find.text('No event description provided.'), findsOneWidget);
    });

    testWidgets('17. ManageEventsScreen displays upper Part Event badge and restricts edit action to Event Creator', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 5));
      final dateStr = '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';
      final event3Part = BandEvent(
        id: 'ev_3part',
        title: 'Three Part Gig',
        description: 'Multi-part event',
        eventType: 'Concert',
        location: 'Arena',
        startDateTime: futureDate.toIso8601String(),
        endDateTime: futureDate.add(const Duration(hours: 5)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'actual_creator_456',
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(id: 'r1', title: 'Part 1', type: 'Soundcheck', date: dateStr, startTime: '12:00', endTime: '13:00'),
          EventRehearsal(id: 'r2', title: 'Part 2', type: 'Dinner', date: dateStr, startTime: '17:00', endTime: '18:00'),
          EventRehearsal(id: 'r3', title: 'Part 3', type: 'Show', date: dateStr, startTime: '20:00', endTime: '22:00'),
        ],
      );

      final mockService = MockRsvpDesignFirebaseService();
      mockService.mockBandEvents = [event3Part];
      mockService.mockMembers = [
        BandMember(userId: 'non_creator_admin', role: 'Leader'),
        BandMember(userId: 'actual_creator_456', role: 'Member'),
      ];

      // Non-creator view
      final appStateNonCreator = MockRsvpDesignAppState(mockService, testUserId: 'non_creator_admin');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appStateNonCreator,
          child: const MaterialApp(
            home: ManageEventsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // 3 Part Event badge shown in top-right
      expect(find.text('3 Part Event'), findsOneWidget);
      expect(find.textContaining('Sessions attached'), findsNothing);

      // Popup menu for non-creator should NOT have 'Edit Event'
      final popupBtn = find.byIcon(Icons.more_vert);
      expect(popupBtn, findsOneWidget);
      await tester.tap(popupBtn);
      await tester.pumpAndSettle();
      expect(find.text('Edit Event'), findsNothing);

      // Dismiss popup
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Creator view
      final appStateCreator = MockRsvpDesignAppState(mockService, testUserId: 'actual_creator_456');
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appStateCreator,
          child: const MaterialApp(
            home: ManageEventsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final popupBtnCreator = find.byIcon(Icons.more_vert);
      expect(popupBtnCreator, findsOneWidget);
      await tester.tap(popupBtnCreator);
      await tester.pumpAndSettle();
      expect(find.text('Edit Event'), findsOneWidget);
    });
  });
}
