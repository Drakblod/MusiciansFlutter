import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';

class Mock01bFirebaseService extends Fake implements FirebaseService {
  final Map<String, BandEvent> events = {};
  final Map<String, List<BandEvent>> bandEvents = {};
  final Map<String, List<SubRequest>> eventSubRequests = {};
  final Map<String, UserProfile> userProfiles = {};
  final List<String> favoriteUserIds = [];
  final List<SubRequest> allSubRequests = [];
  final List<SubRequest> savedBatchRequests = [];

  int publishCalls = 0;
  int eventWriteCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUserId => 'test_user_leader';

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) => const Stream.empty();

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => List.from(allSubRequests);

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => List.from(allSubRequests);

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async {
    return events[eventId];
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return bandEvents[bandId] ?? [];
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    return eventSubRequests[eventId] ?? [];
  }

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async => {};

  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async => {};

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => {'band_123': 'Test Band'};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final uid = userId ?? currentUserId;
    if (uid == null) return null;
    return userProfiles[uid] ?? UserProfile(
      userId: uid,
      displayName: 'Leader User',
      email: '$uid@test.com',
      location: 'Stockholm, Sweden',
      instruments: const [],
      userType: '',
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => userProfiles.values.toList();

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => List.from(favoriteUserIds);

  @override
  Future<bool> isFavoriteAsync(String targetUserId) async => favoriteUserIds.contains(targetUserId);

  @override
  Future<Band?> getBandInfoAsync(String bandId) async => Band(
    id: bandId,
    name: 'Test Band',
    userRole: 'Leader',
    location: 'Stockholm, Sweden',
  );

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async => [
    BandMember(userId: 'test_user_leader', role: 'Leader', nickname: 'Leader User'),
  ];

  @override
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    publishCalls++;
    savedBatchRequests.addAll(requests);
    for (final r in requests) {
      if (r.eventId != null) {
        eventSubRequests.putIfAbsent(r.eventId!, () => []).add(r);
      }
      allSubRequests.add(r);
    }
    return requests.map((r) => r.id ?? 'sub_id').toList();
  }

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    publishCalls++;
    savedBatchRequests.addAll(requests);
    for (final r in requests) {
      if (r.eventId != null) {
        eventSubRequests.putIfAbsent(r.eventId!, () => []).add(r);
      }
      allSubRequests.add(r);
    }
    return requests.map((r) => r.id ?? 'sub_id').toList();
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    return allSubRequests.where((r) => r.userId == userId).toList();
  }

  @override
  Future<String> saveBandEventAsync(String bandId, BandEvent event) async {
    eventWriteCalls++;
    events[event.id ?? ''] = event;
    return event.id ?? 'ev_1';
  }
}

class Mock01bAppState extends AppState {
  final Mock01bFirebaseService mockFirebase;

  Mock01bAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => mockFirebase.currentUserId;

  @override
  UserProfile? get currentUserProfile => UserProfile(
    userId: 'test_user_leader',
    displayName: 'Leader User',
    email: 'leader@test.com',
    location: 'Stockholm, Sweden',
    instruments: const [],
    userType: '',
  );

  @override
  String? get activeBandId => 'band_123';

  @override
  String? get activeBandName => 'Test Band';
}

Widget createTestApp({required Mock01bFirebaseService mockService, required Widget child, Size? size}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: Mock01bAppState(mockService)),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size ?? const Size(800, 2400)),
        child: child,
      ),
    ),
  );
}

Future<void> pumpTestApp(WidgetTester tester, {required Mock01bFirebaseService mockService, required Widget child, Size? size}) async {
  tester.view.physicalSize = size ?? const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(createTestApp(mockService: mockService, child: child, size: size));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('FIND-REQUESTS-01B: Specification Verification', () {
    // 1. Visible order of editable request fields matches 1 to 6 in Find Musician/Vocalist
    testWidgets('1. Visible order of editable request fields matches 1 to 6 in Find Musician/Vocalist', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      final eventTypeFinder = find.text('Event Type');
      final reqTypeFinder = find.text('Request Type');
      final locationFinder = find.text('Location');
      final dateTimeFinder = find.text('Date & Time');
      final descFinder = find.text('Description (optional)');
      final roleFinder = find.text('Role / Instrument');

      expect(eventTypeFinder, findsOneWidget);
      expect(reqTypeFinder, findsOneWidget);
      expect(locationFinder, findsOneWidget);
      expect(dateTimeFinder, findsOneWidget);
      expect(descFinder, findsOneWidget);
      expect(roleFinder, findsOneWidget);

      final p1 = tester.getTopLeft(eventTypeFinder).dy;
      final p2 = tester.getTopLeft(reqTypeFinder).dy;
      final p3 = tester.getTopLeft(locationFinder).dy;
      final p4 = tester.getTopLeft(dateTimeFinder).dy;
      final p5 = tester.getTopLeft(descFinder).dy;
      final p6 = tester.getTopLeft(roleFinder).dy;

      expect(p1, lessThan(p2));
      expect(p2, lessThan(p3));
      expect(p3, lessThan(p4));
      expect(p4, lessThan(p5));
      expect(p5, lessThan(p6));
    });

    // 2. Form does not render a visible "Name of Event" input
    testWidgets('2. Form does not render a visible Name of Event input', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      expect(find.text('Name of Event'), findsNothing);
      expect(find.text('Enter event name'), findsNothing);
    });

    // 3. Event Type options use BandEvent.standardEventTypes
    testWidgets('3. Event Type options use BandEvent.standardEventTypes', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      for (final type in BandEvent.standardEventTypes) {
        expect(find.text(type), findsWidgets, reason: 'Expected $type in Event Type dropdown');
      }
    });

    // 4. Request Type options are Substitute, New Member, Other
    testWidgets('4. Request Type options are Substitute, New Member, Other', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      // Open Request Type dropdown
      await tester.tap(find.text('Substitute').last);
      await tester.pumpAndSettle();

      expect(find.text('Substitute'), findsWidgets);
      expect(find.text('New Member'), findsWidgets);
      expect(find.text('Other'), findsWidgets);
    });

    // 5. Publishing Substitute persists RequestType = 'Substitute'
    testWidgets('5. Publishing Substitute persists RequestType = Substitute', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      // Select Event Type
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concert').last);
      await tester.pumpAndSettle();

      // Publish Substitute
      await tester.tap(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'));
      await tester.pumpAndSettle();

      expect(mock.publishCalls, equals(1));
      expect(mock.savedBatchRequests, isNotEmpty);
      final published = mock.savedBatchRequests.first;
      expect(published.requestType, equals('Substitute'));
      expect(published.role, equals('Substitute'));
      expect(published.toJson()['RequestType'], equals('Substitute'));
    });

    // 6. Publishing New Member persists RequestType = 'New Member'
    testWidgets('6. Publishing New Member persists RequestType = New Member', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      // Select Event Type
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rehearsal').last);
      await tester.pumpAndSettle();

      // Switch to New Member
      await tester.tap(find.text('Substitute').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Member').last);
      await tester.pumpAndSettle();

      // Publish New Member
      await tester.tap(find.text('PUBLISH NEW MEMBER SEARCH'));
      await tester.pumpAndSettle();

      expect(mock.publishCalls, equals(1));
      expect(mock.savedBatchRequests, isNotEmpty);
      final published = mock.savedBatchRequests.first;
      expect(published.requestType, equals('New Member'));
      expect(published.role, equals('New Member'));
      expect(published.toJson()['RequestType'], equals('New Member'));
    });

    // 7. Publishing Other + DJ persists RequestType = 'Other' and role/instrument DJ
    testWidgets('7. Publishing Other + DJ persists RequestType = Other and role/instrument DJ', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      // Select Event Type
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Festival').last);
      await tester.pumpAndSettle();

      // Switch to Other
      await tester.tap(find.text('Substitute').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();

      // Default instrument for Other is DJ
      expect(find.text('DJ'), findsOneWidget);

      // Publish Other
      await tester.tap(find.text('PUBLISH REQUEST'));
      await tester.pumpAndSettle();

      expect(mock.publishCalls, equals(1));
      expect(mock.savedBatchRequests, isNotEmpty);
      final published = mock.savedBatchRequests.first;
      expect(published.requestType, equals('Other'));
      expect(published.role, equals('Other'));
      expect(published.voicePart, equals('DJ'));
      expect(published.toJson()['RequestType'], equals('Other'));
      expect(published.toJson()['Role'], equals('Other'));
      expect(published.toJson()['VoicePart'], equals('DJ'));
    });

    // 8. Publishing Other + Sound Engineer / Producer behaves equivalently
    testWidgets('8. Publishing Other + Sound Engineer / Producer behaves equivalently', (tester) async {
      final mock = Mock01bFirebaseService();
      final initialReq = SubRequest(
        requestType: 'Other',
        role: 'Other',
        voicePart: 'Sound Engineer',
      );
      await pumpTestApp(tester, mockService: mock, child: FindSubScreen(initialRequest: initialReq));

      // Select Event Type
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Club Gig').last);
      await tester.pumpAndSettle();

      // Verify Sound Engineer role is active
      expect(find.text('Sound Engineer'), findsOneWidget);

      // Publish
      await tester.tap(find.text('PUBLISH REQUEST'));
      await tester.pumpAndSettle();

      expect(mock.publishCalls, equals(1));
      expect(mock.savedBatchRequests, isNotEmpty);
      final published = mock.savedBatchRequests.first;
      expect(published.requestType, equals('Other'));
      expect(published.role, equals('Other'));
      expect(published.voicePart, equals('Sound Engineer'));
    });

    // 9. Legacy requests lacking RequestType deserialize into correct effective types
    test('9. Legacy requests lacking RequestType deserialize into correct effective types', () {
      final legacySubJson = {
        'SubRequestId': 'sub_1',
        'Role': 'Substitute',
        'VoicePart': 'Bass',
      };
      final parsedSub = SubRequest.fromJson(legacySubJson, 'sub_1');
      expect(parsedSub.requestType, equals('Substitute'));
      expect(parsedSub.role, equals('Substitute'));

      final legacyMemberJson = {
        'SubRequestId': 'mem_1',
        'Role': 'New Member',
        'VoicePart': 'Drums',
      };
      final parsedMember = SubRequest.fromJson(legacyMemberJson, 'mem_1');
      expect(parsedMember.requestType, equals('New Member'));
      expect(parsedMember.role, equals('New Member'));

      final legacyCaseJson = {
        'SubRequestId': 'mem_2',
        'Role': ' new member ',
        'VoicePart': 'Vocals',
      };
      final parsedCase = SubRequest.fromJson(legacyCaseJson, 'mem_2');
      expect(parsedCase.requestType, equals('New Member'));

      final explicitOtherJson = {
        'SubRequestId': 'oth_1',
        'RequestType': 'Other',
        'Role': 'Other',
        'VoicePart': 'DJ',
      };
      final parsedOther = SubRequest.fromJson(explicitOtherJson, 'oth_1');
      expect(parsedOther.requestType, equals('Other'));
    });

    // 10. Existing-event entry preserves eventId and bandId and does not mutate BandEvent
    testWidgets('10. Existing-event entry preserves eventId and bandId and does not mutate BandEvent', (tester) async {
      final mock = Mock01bFirebaseService();
      final existingEvent = BandEvent(
        id: 'event_orig_123',
        title: 'Original Event Name',
        description: 'Original Event Description',
        additionalNotes: '',
        eventType: 'Concert',
        location: 'Stockholm Konserthus',
        startDateTime: '2026-10-15T19:00:00Z',
        endDateTime: '2026-10-15T22:00:00Z',
        createdBy: 'test_user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      mock.events['event_orig_123'] = existingEvent;

      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen(eventId: 'event_orig_123', bandId: 'band_123'));

      // Event Type is prefilled
      expect(find.text('Concert'), findsOneWidget);
      // Location is prefilled
      expect(find.text('Stockholm Konserthus'), findsOneWidget);
      // No editable Event Name input
      expect(find.text('Original Event Name'), findsNothing);

      // Edit location locally
      await tester.enterText(find.widgetWithText(TextField, 'Enter location'), 'Gothenburg');
      await tester.pumpAndSettle();

      // Original event in mockService must NOT be mutated
      expect(mock.events['event_orig_123']!.location, equals('Stockholm Konserthus'));
      expect(mock.events['event_orig_123']!.title, equals('Original Event Name'));
      expect(mock.eventWriteCalls, equals(0));
    });

    // 11. Find Gigs cards classify Substitute, New Member and Other correctly
    testWidgets('11. Find Gigs cards classify Substitute, New Member and Other correctly', (tester) async {
      final mock = Mock01bFirebaseService();
      final subReq = SubRequest(
        id: 'req_sub',
        bandId: 'band_1',
        bandName: 'Band A',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Drums',
        date: '2026-11-01T20:00:00Z',
        location: 'Uppsala',
      );
      final memReq = SubRequest(
        id: 'req_mem',
        bandId: 'band_2',
        bandName: 'Band B',
        requestType: 'New Member',
        role: 'New Member',
        voicePart: 'Bass',
        date: '2026-11-02T20:00:00Z',
        location: 'Malmö',
      );
      final otherReq = SubRequest(
        id: 'req_oth',
        bandId: 'band_3',
        bandName: 'Band C',
        requestType: 'Other',
        role: 'Other',
        voicePart: 'DJ',
        date: '2026-11-03T20:00:00Z',
        location: 'Stockholm',
      );
      mock.allSubRequests.addAll([subReq, memReq, otherReq]);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      // Tab 1: Substitute Requests (shows Substitute and Other)
      expect(find.text('Band A'), findsOneWidget);
      expect(find.text('Substitute Request'), findsOneWidget);
      expect(find.text('Band C'), findsOneWidget);
      expect(find.text('Other Request'), findsOneWidget);
      expect(find.text('Band B'), findsNothing);

      // Switch to Tab 2: New Member Requests
      await tester.tap(find.text('New Member Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Band B'), findsOneWidget);
      expect(find.text('New Member Request'), findsOneWidget);
      expect(find.text('Band A'), findsNothing);
      expect(find.text('Band C'), findsNothing);
    });

    // 12. Find Gigs details sheet uses the required visible order 1 to 6
    testWidgets('12. Find Gigs details sheet uses the required visible order 1 to 6', (tester) async {
      final mock = Mock01bFirebaseService();
      final gigReq = SubRequest(
        id: 'req_sheet_test',
        bandId: 'band_alpha',
        bandName: 'Alpha Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Keyboards',
        date: '2026-11-10T19:00:00Z',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm Jazz Club',
        description: 'Need pianist for jazz concert',
        extraFields: {'eventType': 'Concert'},
      );
      mock.allSubRequests.add(gigReq);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      // Open details bottom sheet
      await tester.tap(find.text('Alpha Band'));
      await tester.pumpAndSettle();

      final fEventType = find.text('Event Type');
      final fReqType = find.text('Request Type');
      final fLocation = find.text('Location');
      final fDateTime = find.text('Date & Time');
      final fDesc = find.text('Description (optional)');
      final fRole = find.text('Role / Instrument');

      expect(fEventType, findsOneWidget);
      expect(fReqType, findsOneWidget);
      expect(fLocation, findsOneWidget);
      expect(fDateTime, findsOneWidget);
      expect(fDesc, findsOneWidget);
      expect(fRole, findsOneWidget);

      final y1 = tester.getTopLeft(fEventType).dy;
      final y2 = tester.getTopLeft(fReqType).dy;
      final y3 = tester.getTopLeft(fLocation).dy;
      final y4 = tester.getTopLeft(fDateTime).dy;
      final y5 = tester.getTopLeft(fDesc).dy;
      final y6 = tester.getTopLeft(fRole).dy;

      expect(y1, lessThan(y2));
      expect(y2, lessThan(y3));
      expect(y3, lessThan(y4));
      expect(y4, lessThan(y5));
      expect(y5, lessThan(y6));
    });

    // 13. Details sheet never shows the event name as Event Type
    testWidgets('13. Details sheet never shows the event name as Event Type', (tester) async {
      final mock = Mock01bFirebaseService();
      final gigReq = SubRequest(
        id: 'req_evtype_test',
        bandId: 'band_beta',
        bandName: 'Beta Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Electric Guitar',
        date: '2026-11-12T19:00:00Z',
        eventTitle: 'Secret Arena Show',
        location: 'Stockholm',
        description: 'Show details here',
      );
      mock.allSubRequests.add(gigReq);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      await tester.tap(find.text('Beta Band'));
      await tester.pumpAndSettle();

      // Event Type row must show 'Not provided', NEVER 'Secret Arena Show'
      expect(find.text('Not provided'), findsOneWidget);
      expect(find.text('Secret Arena Show'), findsNothing);
    });

    // 14. Details sheet formats date & time without fabricating fallback hours
    testWidgets('14. Details sheet formats date & time without fabricating fallback hours', (tester) async {
      final mock = Mock01bFirebaseService();
      final noTimeReq = SubRequest(
        id: 'req_notime',
        bandId: 'band_notime',
        bandName: 'Acoustic Trio',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Cello',
        date: '2026-11-20T00:00:00Z',
        location: 'Lund',
      );
      mock.allSubRequests.add(noTimeReq);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      await tester.tap(find.text('Acoustic Trio'));
      await tester.pumpAndSettle();

      // Must not fabricate '18:00 - 21:00'
      expect(find.textContaining('18:00 - 21:00'), findsNothing);
      expect(find.textContaining('18:00'), findsNothing);
    });

    // 15. Multiple substitute slots can still be added/removed
    testWidgets('15. Multiple substitute slots can still be added/removed', (tester) async {
      final mock = Mock01bFirebaseService();
      await pumpTestApp(tester, mockService: mock, child: const FindSubScreen());

      expect(find.text('+ Add Substitute'), findsOneWidget);
      expect(find.text('SUBSTITUTE 1'), findsNothing);

      // Add second slot
      await tester.tap(find.text('+ Add Substitute'));
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsOneWidget);
      expect(find.text('SUBSTITUTE 2'), findsOneWidget);

      // Remove second slot
      final removeButtons = find.text('Remove Substitute');
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsNothing);
    });

    // 16. Direct invitations remain classified correctly and are not duplicated
    testWidgets('16. Direct invitations remain classified correctly and are not duplicated', (tester) async {
      final mock = Mock01bFirebaseService();
      final directInviteSub = SubRequest(
        id: 'req_direct_sub',
        bandId: 'band_direct',
        bandName: 'Direct Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Electric Guitar',
        targetUserIds: ['test_user_leader'],
        date: '2026-11-25T19:00:00Z',
        location: 'Stockholm',
      );
      mock.allSubRequests.add(directInviteSub);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      // Appears in Substitute Requests with Direct Invite badge
      expect(find.text('Direct Band'), findsOneWidget);
      expect(find.text('Direct Invite'), findsOneWidget);

      // Not duplicated
      expect(find.text('Direct Band'), findsNWidgets(1));
    });

    // 17. Paid requests show payment amount and Details; unpaid requests do not show payment UI
    testWidgets('17. Paid requests show payment amount and Details; unpaid requests do not show payment UI', (tester) async {
      final mock = Mock01bFirebaseService();
      final paidReq = SubRequest(
        id: 'req_paid_test',
        bandId: 'band_paid',
        bandName: 'Paid Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Bass',
        isPaid: true,
        payAmount: 2500,
        payDetails: 'Includes dinner and hotel',
        date: '2026-11-30T20:00:00Z',
        location: 'Malmö',
      );
      final unpaidReq = SubRequest(
        id: 'req_unpaid_test',
        bandId: 'band_unpaid',
        bandName: 'Free Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Bass',
        isPaid: false,
        date: '2026-12-01T20:00:00Z',
        location: 'Malmö',
      );
      mock.allSubRequests.addAll([paidReq, unpaidReq]);

      await pumpTestApp(tester, mockService: mock, child: const FindGigsScreen());

      // Paid gig shows payment badge on card
      expect(find.textContaining('2,500'), findsOneWidget);

      // Open paid gig details sheet
      await tester.tap(find.text('Paid Band'));
      await tester.pumpAndSettle();

      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Includes dinner and hotel'), findsOneWidget);

      // Close bottom sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Open unpaid gig details sheet
      await tester.tap(find.text('Free Band'));
      await tester.pumpAndSettle();

      expect(find.text('Payment'), findsNothing);
      expect(find.text('Includes dinner and hotel'), findsNothing);
    });

    // 18. Responsive rendering at 320 px width succeeds without RenderFlex overflow
    testWidgets('18. Responsive rendering at 320 px width succeeds without RenderFlex overflow', (tester) async {
      final mock = Mock01bFirebaseService();
      final gigReq = SubRequest(
        id: 'req_narrow_test',
        bandId: 'band_narrow',
        bandName: 'Narrow Band With A Very Long Name',
        requestType: 'Other',
        role: 'Other',
        voicePart: 'Sound Engineer',
        date: '2026-12-10T19:00:00Z',
        location: 'Very Long Stockholm Location Name That Could Overflow',
      );
      mock.allSubRequests.add(gigReq);

      // Test FindSubScreen at 320 px
      await pumpTestApp(tester, mockService: mock, size: const Size(320, 640), child: const FindSubScreen());
      expect(tester.takeException(), isNull);

      // Test FindGigsScreen at 320 px
      await pumpTestApp(tester, mockService: mock, size: const Size(320, 640), child: const FindGigsScreen());
      expect(tester.takeException(), isNull);
    });
  });
}
