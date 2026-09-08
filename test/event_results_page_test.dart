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
import 'package:musicians_flutter/views/event_results_page.dart';

BandEvent createTestBandEvent({
  String? id,
  required String title,
  String description = 'Test Description',
  String eventType = 'Concert',
  String location = 'Test Location',
  String startDateTime = '2026-09-12T20:00:00Z',
  String endDateTime = '2026-09-12T23:00:00Z',
  String additionalNotes = 'Test Notes',
  String createdBy = 'leader_user',
  int? createdAt,
  int? updatedAt,
  bool requireResponse = true,
  Map<String, EventResponse> responses = const {},
  Map<String, SubstituteAssignment> substituteAssignments = const {},
  Map<String, ExternalInvitee> externalInvitees = const {},
  String? parentEventId,
  int? subEventSequence,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return BandEvent(
    id: id,
    title: title,
    description: description,
    eventType: eventType,
    location: location,
    startDateTime: startDateTime,
    endDateTime: endDateTime,
    additionalNotes: additionalNotes,
    createdBy: createdBy,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    requireResponse: requireResponse,
    responses: responses,
    substituteAssignments: substituteAssignments,
    externalInvitees: externalInvitees,
    parentEventId: parentEventId,
    subEventSequence: subEventSequence,
  );
}

class MockResultsFirebaseService extends FirebaseService {
  BandEvent? mockEvent;
  List<BandMember> mockMembers = [];
  Map<String, UserProfile> mockProfiles = {};
  Map<String, SubstituteAssignment> mockSubAssignments = {};
  List<BandEvent> mockBandEvents = [];

  int writeCount = 0;

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
    return mockMembers;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    if (mockBandEvents.isNotEmpty) return mockBandEvents;
    if (mockEvent != null) return [mockEvent!];
    return [];
  }

  @override
  Future<Map<String, SubstituteAssignment>> getSubstituteAssignmentsAsync(
    String bandId,
    String eventId,
  ) async {
    return mockSubAssignments;
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
  Future<void> updateBandEventAsync(
    String bandId,
    String eventId,
    Map<String, dynamic> editableFields,
  ) async {
    writeCount++;
  }

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    writeCount++;
  }
}

class MockResultsAppState extends AppState {
  final MockResultsFirebaseService mockFirebase;

  MockResultsAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => 'leader_user';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'leader_user',
        displayName: 'Leader User',
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

  Widget createTestWidget({
    required MockResultsFirebaseService service,
    required String bandId,
    required String eventId,
    BandEvent? initialEvent,
  }) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockResultsAppState(service),
      child: MaterialApp(
        home: EventResultsPage(
          bandId: bandId,
          eventId: eventId,
          initialEvent: initialEvent,
        ),
      ),
    );
  }

  group('EventResultsPage Tests', () {
    testWidgets(
      'Regular members are grouped into YES, NO, UNCERTAIN, NO ANSWER with reasons and counts',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockResultsFirebaseService();

        // Setup 6 band members
        mockService.mockMembers = [
          BandMember(userId: 'u1', nickname: 'Alice'),
          BandMember(userId: 'u2', nickname: 'Bob'),
          BandMember(userId: 'u3', nickname: 'Charlie'),
          BandMember(userId: 'u4', nickname: 'Diana'),
          BandMember(userId: 'u5', nickname: 'Evan'),
          BandMember(userId: 'u6', nickname: 'Frank'),
        ];

        mockService.mockProfiles = {
          'u1': UserProfile(userId: 'u1', displayName: 'Alice Vocalist', mainInstrument: 'Vocals'),
          'u2': UserProfile(userId: 'u2', displayName: 'Bob Guitar', mainInstrument: 'Guitar'),
          'u3': UserProfile(userId: 'u3', displayName: 'Charlie Bass', mainInstrument: 'Bass'),
          'u4': UserProfile(userId: 'u4', displayName: 'Diana Drum', mainInstrument: 'Drums'),
          'u5': UserProfile(userId: 'u5', displayName: 'Evan Keys', mainInstrument: 'Keys'),
          'u6': UserProfile(userId: 'u6', displayName: 'Frank Horn', mainInstrument: 'Saxophone'),
        };

        final now = DateTime.now();
        final event = createTestBandEvent(
          id: 'event_test_1',
          title: 'Friday Big Show',
          description: 'Headline concert at venue',
          eventType: 'Concert',
          location: 'Grand Ballroom',
          startDateTime: '2026-09-12T20:00:00Z',
          endDateTime: '2026-09-12T23:00:00Z',
          additionalNotes: 'Bring backline',
          responses: {
            // YES normalized variants
            'u1': EventResponse(status: 'YES', timestamp: now),
            'u2': EventResponse(status: 'attending', timestamp: now),
            // NO normalized variants
            'u3': EventResponse(status: 'declined', timestamp: now),
            // UNCERTAIN with uncertainReason
            'u4': EventResponse(
              status: 'UNCERTAIN',
              timestamp: now,
              uncertainReason: 'Flight might be delayed',
            ),
            // UNCERTAIN with fallback comment
            'u5': EventResponse(
              status: 'maybe',
              timestamp: now,
              comment: 'Need to check family calendar',
            ),
            // u6 has no response -> should be NO ANSWER
          },
        );

        mockService.mockEvent = event;

        await tester.pumpWidget(
          createTestWidget(
            service: mockService,
            bandId: 'band_1',
            eventId: 'event_test_1',
            initialEvent: event,
          ),
        );

        await tester.pumpAndSettle();

        // 1. Verify Header title and metadata
        expect(find.text('Friday Big Show'), findsWidgets);
        expect(find.text('Grand Ballroom'), findsWidgets);

        // 2. Verify all 4 exact category headers are present with counts
        expect(find.textContaining('YES (2)'), findsOneWidget);
        expect(find.textContaining('NO (1)'), findsOneWidget);
        expect(find.textContaining('UNCERTAIN (2)'), findsOneWidget);
        expect(find.textContaining('NO ANSWER (1)'), findsOneWidget);

        // 3. Verify names under their respective sections
        expect(find.text('Alice Vocalist'), findsOneWidget);
        expect(find.text('Bob Guitar'), findsOneWidget);
        expect(find.text('Charlie Bass'), findsOneWidget);
        expect(find.text('Diana Drum'), findsOneWidget);
        expect(find.text('Evan Keys'), findsOneWidget);
        expect(find.text('Frank Horn'), findsOneWidget);

        // 4. Verify reasons rendered under UNCERTAIN
        expect(find.textContaining('Flight might be delayed'), findsOneWidget);
        expect(find.textContaining('Need to check family calendar'), findsOneWidget);

        // 5. Zero write calls occurred
        expect(mockService.writeCount, 0);
      },
    );

    testWidgets(
      'Substitutes section shows confirmed assignments, legacy subRequest fallback, excludes cancelled slots, and handles empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockResultsFirebaseService();

        mockService.mockMembers = [
          BandMember(userId: 'u1', nickname: 'Alice'),
        ];
        mockService.mockProfiles = {
          'u1': UserProfile(userId: 'u1', displayName: 'Alice Vocalist'),
          'sub_1': UserProfile(userId: 'sub_1', displayName: 'Sam Substitute'),
          'sub_2': UserProfile(userId: 'sub_2', displayName: 'Leo LegacySub'),
        };

        final now = DateTime.now();
        final event = createTestBandEvent(
          id: 'event_test_2',
          title: 'Sub Show',
          eventType: 'Concert',
          startDateTime: '2026-09-15T19:00:00Z',
          endDateTime: '2026-09-15T22:00:00Z',
          responses: {
            'u1': EventResponse(status: 'YES', timestamp: now),
          },
          substituteAssignments: {
            'slot_active': SubstituteAssignment(
              slotId: 'slot_active',
              assignedUserId: 'sub_1',
              assignedUserName: 'Sam Substitute',
              instrument: 'Bass Guitar',
              replacedMemberName: 'Charlie Original',
              status: 'assigned',
            ),
            'slot_cancelled': SubstituteAssignment(
              slotId: 'slot_cancelled',
              assignedUserId: 'cancelled_sub',
              assignedUserName: 'Cancelled Sub',
              instrument: 'Keys',
              status: 'cancelled',
            ),
          },
          externalInvitees: {
            // Legacy subRequest that is attending
            'sub_2': ExternalInvitee(
              userId: 'sub_2',
              displayName: 'Leo LegacySub',
              status: 'attending',
              source: 'subRequest',
              instrument: 'Drums',
              invitedAt: now.millisecondsSinceEpoch,
            ),
            // Non-sub external invitee (guest)
            'guest_1': ExternalInvitee(
              userId: 'guest_1',
              displayName: 'Vip Guest',
              status: 'attending',
              source: 'vip',
              invitedAt: now.millisecondsSinceEpoch,
            ),
          },
        );

        mockService.mockEvent = event;
        mockService.mockSubAssignments = event.substituteAssignments;

        await tester.pumpWidget(
          createTestWidget(
            service: mockService,
            bandId: 'band_1',
            eventId: 'event_test_2',
            initialEvent: event,
          ),
        );

        await tester.pumpAndSettle();

        // Header shows 2 distinct confirmed substitutes (Sam Substitute and Leo LegacySub)
        expect(find.text('SUBSTITUTES'), findsOneWidget);
        expect(find.textContaining('2 slots (2 people)'), findsOneWidget);

        // Confirmed slot visible
        expect(find.text('Sam Substitute'), findsOneWidget);
        expect(find.text('Bass Guitar'), findsOneWidget);
        expect(find.textContaining('Replacing Charlie Original'), findsOneWidget);

        // Legacy sub visible
        expect(find.text('Leo LegacySub'), findsOneWidget);
        expect(find.text('Drums'), findsOneWidget);

        // Cancelled sub should NOT be shown
        expect(find.text('Cancelled Sub'), findsNothing);

        // VIP guest is shown under EXTERNAL GUESTS, not counted in substitutes (which only has 2 slots)
        expect(find.text('EXTERNAL GUESTS'), findsOneWidget);
        expect(find.text('Vip Guest'), findsOneWidget);

        // Non-sub guest is NOT counted in regular member total
        expect(find.textContaining('YES (1)'), findsOneWidget);
      },
    );

    testWidgets('Empty substitutes displays "No substitutes assigned"', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockResultsFirebaseService();
      mockService.mockMembers = [BandMember(userId: 'u1')];
      final event = createTestBandEvent(
        id: 'event_test_empty_subs',
        title: 'Rehearsal',
        eventType: 'Rehearsal',
        startDateTime: '2026-09-18T18:00:00Z',
        endDateTime: '2026-09-18T20:00:00Z',
      );
      mockService.mockEvent = event;

      await tester.pumpWidget(
        createTestWidget(
          service: mockService,
          bandId: 'band_1',
          eventId: 'event_test_empty_subs',
          initialEvent: event,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTES'), findsOneWidget);
      expect(find.textContaining('0 slots (0 people)'), findsOneWidget);
      expect(find.text('No substitutes assigned'), findsOneWidget);
    });

    testWidgets('Strictly read-only: No RSVP buttons, no chat creation, no find sub, no write calls', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockResultsFirebaseService();
      mockService.mockMembers = [BandMember(userId: 'leader_user')];
      final event = createTestBandEvent(
        id: 'event_test_ro',
        title: 'Tour Date 1',
        eventType: 'Concert',
        startDateTime: '2026-09-20T20:00:00Z',
        endDateTime: '2026-09-20T23:00:00Z',
        requireResponse: true,
      );
      mockService.mockEvent = event;

      await tester.pumpWidget(
        createTestWidget(
          service: mockService,
          bandId: 'band_1',
          eventId: 'event_test_ro',
          initialEvent: event,
        ),
      );
      await tester.pumpAndSettle();

      // No interactive management/RSVP buttons
      expect(find.text('Find Sub'), findsNothing);
      expect(find.text('RSVP / Details'), findsNothing);
      expect(find.text('Event Chat'), findsNothing);
      expect(find.text('Send Reminder'), findsNothing);
      expect(find.text('Finalize'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      // Verify zero writes
      expect(mockService.writeCount, 0);
    });

    testWidgets('Grouped multi-day events allow switching between dates/parts', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockResultsFirebaseService();
      mockService.mockMembers = [
        BandMember(userId: 'u1', nickname: 'Alice'),
      ];

      final now = DateTime.now();
      final eventPart1 = createTestBandEvent(
        id: 'festival_p1',
        title: 'Summer Fest - Part 1',
        eventType: 'Festival',
        parentEventId: 'fest_parent',
        subEventSequence: 1,
        startDateTime: '2026-08-01T15:00:00Z',
        endDateTime: '2026-08-01T18:00:00Z',
        responses: {
          'u1': EventResponse(status: 'YES', timestamp: now),
        },
      );

      final eventPart2 = createTestBandEvent(
        id: 'festival_p2',
        title: 'Summer Fest - Part 2',
        eventType: 'Festival',
        parentEventId: 'fest_parent',
        subEventSequence: 2,
        startDateTime: '2026-08-02T15:00:00Z',
        endDateTime: '2026-08-02T18:00:00Z',
        responses: {
          'u1': EventResponse(status: 'NO', timestamp: now),
        },
      );

      mockService.mockBandEvents = [eventPart1, eventPart2];
      mockService.mockEvent = eventPart1;

      await tester.pumpWidget(
        createTestWidget(
          service: mockService,
          bandId: 'band_1',
          eventId: 'festival_p1',
          initialEvent: eventPart1,
        ),
      );
      await tester.pumpAndSettle();

      // In Part 1: YES (1), NO (0)
      expect(find.textContaining('YES (1)'), findsOneWidget);
      expect(find.textContaining('NO (0)'), findsOneWidget);

      // Switch to Part 2
      final part2Chip = find.textContaining('Part 2');
      expect(part2Chip, findsOneWidget);
      await tester.tap(part2Chip);
      await tester.pumpAndSettle();

      // In Part 2: YES (0), NO (1)
      expect(find.textContaining('YES (0)'), findsOneWidget);
      expect(find.textContaining('NO (1)'), findsOneWidget);
    });

    testWidgets(
      'Behavioral test: linked occurrences switch event ID, metadata, responses, uncertainty reasons, and substitutes, ignoring synthetic parent',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockResultsFirebaseService();
        mockService.mockMembers = [
          BandMember(userId: 'u1', nickname: 'Alice'),
          BandMember(userId: 'u2', nickname: 'Bob'),
        ];

        final now = DateTime.now();

        // Synthetic parent event header: should NOT be rendered as an occurrence
        final parentEvent = createTestBandEvent(
          id: 'parent_tour_group',
          title: 'Arena Tour Weekend',
          eventType: 'Multiple (2 dates)',
          startDateTime: '2026-10-10T19:00:00Z',
          endDateTime: '2026-10-11T23:00:00Z',
        );

        // Occurrence 1 (Part 1)
        final eventPart1 = createTestBandEvent(
          id: 'occ_part_1',
          title: 'Arena Tour - Part 1',
          eventType: 'Concert',
          location: 'Stockholm Globe',
          parentEventId: 'parent_tour_group',
          subEventSequence: 1,
          startDateTime: '2026-10-10T19:00:00Z',
          endDateTime: '2026-10-10T22:00:00Z',
          responses: {
            'u1': EventResponse(status: 'YES', timestamp: now),
            'u2': EventResponse(
              status: 'UNCERTAIN',
              uncertainReason: 'Has dentist appointment',
              timestamp: now,
            ),
          },
          substituteAssignments: {
            'sub_slot_bass': SubstituteAssignment(
              slotId: 'sub_slot_bass',
              assignedUserId: 'sub_sam',
              assignedUserName: 'Sam On Bass',
              instrument: 'Bass',
              status: 'assigned',
            ),
          },
        );

        // Occurrence 2 (Part 2) with deliberately different responses, reasons, and substitutes
        final eventPart2 = createTestBandEvent(
          id: 'occ_part_2',
          title: 'Arena Tour - Part 2',
          eventType: 'Concert',
          location: 'Gothenburg Arena',
          parentEventId: 'parent_tour_group',
          subEventSequence: 2,
          startDateTime: '2026-10-11T19:00:00Z',
          endDateTime: '2026-10-11T22:00:00Z',
          responses: {
            'u1': EventResponse(status: 'NO', timestamp: now),
            'u2': EventResponse(status: 'YES', timestamp: now),
          },
          substituteAssignments: {
            'sub_slot_drums': SubstituteAssignment(
              slotId: 'sub_slot_drums',
              assignedUserId: 'sub_leo',
              assignedUserName: 'Leo On Drums',
              instrument: 'Drums',
              status: 'assigned',
            ),
          },
        );

        mockService.mockBandEvents = [parentEvent, eventPart1, eventPart2];
        mockService.mockEvent = eventPart1;

        await tester.pumpWidget(
          createTestWidget(
            service: mockService,
            bandId: 'band_1',
            eventId: 'occ_part_1',
            initialEvent: eventPart1,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify synthetic parent is NOT counted as an occurrence
        // Only Part 1 and Part 2 are shown in date chips
        expect(find.textContaining('SWITCH EVENT OCCURRENCE (2 PARTS)'), findsOneWidget);
        expect(find.textContaining('Arena Tour Weekend'), findsNothing);

        // 2. Verify Part 1 details:
        // Metadata
        expect(find.text('Stockholm Globe'), findsOneWidget);
        // Member responses & counts
        expect(find.textContaining('YES (1)'), findsOneWidget);
        expect(find.textContaining('NO (0)'), findsOneWidget);
        expect(find.textContaining('UNCERTAIN (1)'), findsOneWidget);
        // Reason displayed
        expect(find.text('"Has dentist appointment"'), findsOneWidget);
        // Substitute
        expect(find.text('Sam On Bass'), findsOneWidget);
        expect(find.text('Leo On Drums'), findsNothing);

        // 3. Switch to Occurrence 2 (Part 2)
        final part2Chip = find.textContaining('Part 2');
        expect(part2Chip, findsOneWidget);
        await tester.tap(part2Chip);
        await tester.pumpAndSettle();

        // 4. Verify Part 2 details:
        // Metadata changes
        expect(find.text('Gothenburg Arena'), findsOneWidget);
        expect(find.text('Stockholm Globe'), findsNothing);
        // Responses change: Alice is NO, Bob is YES
        expect(find.textContaining('YES (1)'), findsOneWidget);
        expect(find.textContaining('NO (1)'), findsOneWidget);
        expect(find.textContaining('UNCERTAIN (0)'), findsOneWidget);
        // Reason disappears
        expect(find.text('"Has dentist appointment"'), findsNothing);
        // Substitute changes: Leo on Drums is visible, Sam on Bass is gone
        expect(find.text('Leo On Drums'), findsOneWidget);
        expect(find.text('Sam On Bass'), findsNothing);

        // 5. Switch back to Part 1
        final part1Chip = find.textContaining('Part 1');
        await tester.tap(part1Chip);
        await tester.pumpAndSettle();

        // Verify Part 1 is restored
        expect(find.text('Stockholm Globe'), findsOneWidget);
        expect(find.text('"Has dentist appointment"'), findsOneWidget);
        expect(find.text('Sam On Bass'), findsOneWidget);
      },
    );

    testWidgets(
      'Substitute identification: name-only, applicant, valid canonical, revoked with stale externalInvitee, and multi-slot same person',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockService = MockResultsFirebaseService();
        mockService.mockMembers = [BandMember(userId: 'u1')];

        final now = DateTime.now();
        final event = createTestBandEvent(
          id: 'event_sub_tightened',
          title: 'Sub Audit Event',
          eventType: 'Concert',
          startDateTime: '2026-10-15T20:00:00Z',
          endDateTime: '2026-10-15T23:00:00Z',
          substituteAssignments: {
            // Valid canonical assignment 1 (assigned status, non-empty userId)
            'slot_valid_1': SubstituteAssignment(
              slotId: 'slot_valid_1',
              subRequestId: 'req_valid_1',
              assignedUserId: 'musician_alice',
              assignedUserName: 'Alice Valid Bass',
              instrument: 'Bass',
              status: 'assigned',
            ),
            // Valid canonical assignment 2: SAME PERSON assigned to second slot (e.g. Synth)
            'slot_valid_2': SubstituteAssignment(
              slotId: 'slot_valid_2',
              subRequestId: 'req_valid_2',
              assignedUserId: 'musician_alice',
              assignedUserName: 'Alice Valid Synth',
              instrument: 'Synth',
              status: 'assigned',
            ),
            // Name-only record: empty assignedUserId -> MUST NOT be confirmed
            'slot_name_only': SubstituteAssignment(
              slotId: 'slot_name_only',
              assignedUserId: '',
              assignedUserName: 'Phantom Name Only',
              instrument: 'Flute',
              status: 'assigned',
            ),
            // Whitespace-only record -> MUST NOT be confirmed
            'slot_ws_only': SubstituteAssignment(
              slotId: 'slot_ws_only',
              assignedUserId: '   ',
              assignedUserName: 'Whitespace Musician',
              instrument: 'Violin',
              status: 'assigned',
            ),
            // Accepted-but-unassigned applicant -> MUST NOT be confirmed
            'slot_applicant': SubstituteAssignment(
              slotId: 'slot_applicant',
              assignedUserId: 'applicant_bob',
              assignedUserName: 'Bob Applicant',
              instrument: 'Trumpet',
              status: 'accepted',
            ),
            // Selected favorite -> MUST NOT be confirmed
            'slot_favorite': SubstituteAssignment(
              slotId: 'slot_favorite',
              assignedUserId: 'fav_user',
              assignedUserName: 'Fav Musician',
              instrument: 'Saxophone',
              status: 'selected',
            ),
            // Authoritative REVOKED slot
            'slot_revoked': SubstituteAssignment(
              slotId: 'slot_revoked',
              subRequestId: 'req_revoked_charlie',
              assignedUserId: 'user_charlie',
              assignedUserName: 'Charlie Revoked',
              instrument: 'Guitar',
              status: 'revoked',
            ),
          },
          externalInvitees: {
            // STALE attending external invitee for Charlie whose assignment was revoked!
            // Must NOT resurrect Charlie's revoked assignment!
            'user_charlie': ExternalInvitee(
              userId: 'user_charlie',
              displayName: 'Charlie Revoked',
              status: 'attending',
              source: 'subRequest',
              subRequestId: 'req_revoked_charlie',
              instrument: 'Guitar',
              invitedAt: now.millisecondsSinceEpoch,
            ),
            // Legitimate legacy substitution: NO canonical record in substituteAssignments,
            // source is subRequest, status is attending -> MUST BE PRESERVED!
            'legacy_dave': ExternalInvitee(
              userId: 'legacy_dave',
              displayName: 'Dave Legacy Drums',
              status: 'attending',
              source: 'subRequest',
              subRequestId: 'req_legacy_dave',
              instrument: 'Drums',
              invitedAt: now.millisecondsSinceEpoch,
            ),
          },
        );

        mockService.mockBandEvents = [event];
        mockService.mockEvent = event;

        await tester.pumpWidget(
          createTestWidget(
            service: mockService,
            bandId: 'band_1',
            eventId: 'event_sub_tightened',
            initialEvent: event,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Check substitutes header count:
        // Alice has 2 slots (Bass + Synth).
        // Dave has 1 legacy slot (Drums).
        // Total = 3 slots (2 people: Alice, Dave).
        // Stale Charlie (revoked), phantom name-only, whitespace, applicant Bob, and favorite are NOT included!
        expect(find.text('SUBSTITUTES'), findsOneWidget);
        expect(find.textContaining('3 slots (2 people)'), findsOneWidget);

        // 2. Both slots for Alice are visible
        expect(find.text('Alice Valid Bass'), findsOneWidget);
        expect(find.text('Alice Valid Synth'), findsOneWidget);

        // 3. Legacy substitute Dave is visible
        expect(find.text('Dave Legacy Drums'), findsOneWidget);

        // 4. Excluded items:
        expect(find.text('Phantom Name Only'), findsNothing);
        expect(find.text('Whitespace Musician'), findsNothing);
        expect(find.text('Bob Applicant'), findsNothing);
        expect(find.text('Fav Musician'), findsNothing);
        expect(find.text('Charlie Revoked'), findsNothing);

        // 5. Stale Charlie is NOT shown under EXTERNAL GUESTS either
        expect(find.text('Charlie Revoked'), findsNothing);
      },
    );
  });
}
