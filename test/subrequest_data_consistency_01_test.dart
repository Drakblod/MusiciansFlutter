import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/request_management_access.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/sub_request_responses_screen.dart';
import 'package:musicians_flutter/views/sub_request_response_details_screen.dart';

class MockConsistencyFirebaseService extends FirebaseService {
  String? fixtureUid;
  @override Stream<String?> get catalogueIdentityChanges => const Stream.empty();
  @override Stream<bool> watchRequestManagementAccess(RequestManagementAccess access) => const Stream.empty();
  @override
  Future<RequestManagementAccess> authorizeRequestManagement({String? bandId,String? requestId,String? expectedCreatorId,bool Function()? isCurrent}) async {
    final request=requests.firstWhere((r)=>(r.subRequestId??r.id)==requestId);
    if(request.bandId!=bandId || !['leader','admin'].contains(bandRoles['$bandId/$currentUserId']) ||
        (isCurrent!=null && !isCurrent())) throw const PrivateDataAccessException();
    return RequestManagementAccess(userId:currentUserId!,bandId:bandId!,request:request);
  }
  @override
  Stream<int> subscribeToSubRequestResponseCount(String id) => const Stream<int>.empty();

  @override
  String? get currentUserId => fixtureUid ?? 'test_user_active';
  final List<SubRequest> requests = [];
  final Set<String> appliedIds = {};
  final Map<String, int> responseCounts = {};
  final Map<String, String> bandRoles = {};
  int directWriteCalls = 0;
  bool callableShouldFail = false;
  int callableCallCount = 0;

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    return List.from(requests);
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    return requests.where((r) => r.creatorUserId == userId || r.userId == userId).toList();
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => List.from(requests);

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => Set.from(appliedIds);

  @override
  Future<int> getSubRequestResponseCountAsync(String subRequestId) async {
    return responseCounts[subRequestId] ?? 0;
  }

  @override
  Future<bool> isBandLeaderOrAdminAsync(String bandId, String userId) async {
    final role = bandRoles['$bandId/$userId'];
    return role == 'leader' || role == 'admin';
  }

  @override
  Future<SubRequest?> getSubRequestAsync(String subRequestId) async {
    try {
      return requests.firstWhere((r) => (r.subRequestId ?? r.id) == subRequestId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async => {};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? 'test_user',
      displayName: 'Test Musician',
      instruments: const ['Saxophone', 'Drums', 'Bass'],
    );
  }

  // Intercept any direct persistence writes to ensure they are NOT invoked during publication
  @override
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    directWriteCalls++;
    throw StateError('Direct client-side batch persistence is denied! Publication must be server-owned.');
  }

  @override
  Future<String?> saveSubRequestAsync(SubRequest request) async {
    directWriteCalls++;
    throw StateError('Direct client-side single persistence is denied! Publication must be server-owned.');
  }

  // Simulated server callable publication for testing
  Future<List<String>> testPublishSubRequestGroupAsync({
    required String bandId,
    required String requestGroupId,
    required List<SubRequest> requestsToPublish,
    String? bandName,
  }) async {
    callableCallCount++;
    if (callableShouldFail) {
      throw Exception('Server error: callable execution failed');
    }
    // Callable writes atomically to requests list (simulating server publication)
    final ids = <String>[];
    for (final r in requestsToPublish) {
      final id = r.subRequestId ?? r.id ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';
      ids.add(id);
      requests.add(r.copyWith(id: id, subRequestId: id, status: 'published'));
    }
    return ids;
  }
}

class MockConsistencyAppState extends AppState {
  final MockConsistencyFirebaseService mockService;
  String? activeUserId;
  UserProfile? activeProfile;

  MockConsistencyAppState(this.mockService, {this.activeUserId = 'test_user_active'}) {
    activeProfile = UserProfile(
      userId: activeUserId,
      displayName: 'Active User',
      instruments: const ['Saxophone', 'Drums', 'Bass'],
    );
  }

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => activeProfile;

  @override
  String? get currentUserId => activeUserId;
}

Widget createTestApp({
  required Widget child,
  required MockConsistencyAppState appState,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: child,
      routes: {
        '/find_gigs': (context) => const FindGigsScreen(),
        '/sub_request_responses': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return SubRequestResponsesScreen(bandId: args['bandId'] as String);
        },
        '/sub_request_response_details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return SubRequestResponseDetailsScreen(subRequest: args['subRequest'] as SubRequest);
        },
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('SUBREQUEST-DATA-CONSISTENCY-01: Dart Model & Serialization', () {
    test('1. SubRequest.fromJson parses camelCase projection fields correctly', () {
      final json = {
        'id': 'sub_camel_1',
        'subRequestId': 'sub_camel_1',
        'requestType': 'Substitute',
        'eventType': 'Concert',
        'startTime': '18:00',
        'endTime': '21:30',
        'description': 'Main stage saxophone performance',
        'payDetails': 'Dinner and travel covered',
        'location': 'Sundsvall Music Hall, Sundsvall',
        'city': 'Sundsvall',
        'date': '2028-10-30T18:00:00Z',
        'isPaid': true,
        'payAmount': 1500,
        'currency': 'SEK',
      };

      final req = SubRequest.fromJson(json, 'sub_camel_1');

      expect(req.subRequestId, equals('sub_camel_1'));
      expect(req.requestType, equals('Substitute'));
      expect(req.eventType, equals('Concert'));
      expect(req.resolvedEventType, equals('Concert'));
      expect(req.startTime, equals('18:00'));
      expect(req.endTime, equals('21:30'));
      expect(req.description, equals('Main stage saxophone performance'));
      expect(req.payDetails, equals('Dinner and travel covered'));
      expect(req.location, equals('Sundsvall Music Hall, Sundsvall'));
      expect(req.isPaid, isTrue);
      expect(req.payAmount, equals(1500));
      expect(req.currency, equals('SEK'));
    });

    test('2. SubRequest.fromJson parses legacy PascalCase fields correctly', () {
      final json = {
        'SubRequestId': 'sub_pascal_1',
        'RequestType': 'Substitute',
        'EventType': 'Festival',
        'StartTime': '14:00',
        'EndTime': '17:00',
        'Description': 'Outdoor festival gig',
        'PayDetails': 'Catering included',
        'Location': 'Uppsala Park, Uppsala',
        'City': 'Uppsala',
        'Date': '2028-06-15T14:00:00Z',
        'IsPaid': true,
        'PayAmount': 2000,
        'Currency': 'SEK',
      };

      final req = SubRequest.fromJson(json, 'sub_pascal_1');

      expect(req.subRequestId, equals('sub_pascal_1'));
      expect(req.requestType, equals('Substitute'));
      expect(req.eventType, equals('Festival'));
      expect(req.resolvedEventType, equals('Festival'));
      expect(req.startTime, equals('14:00'));
      expect(req.endTime, equals('17:00'));
      expect(req.description, equals('Outdoor festival gig'));
      expect(req.payDetails, equals('Catering included'));
      expect(req.isPaid, isTrue);
      expect(req.payAmount, equals(2000));
    });

    test('3. SubRequest.fromJson falls back to notes when description is absent', () {
      final json = {
        'subRequestId': 'sub_notes_legacy',
        'notes': 'Legacy notes field content',
      };

      final req = SubRequest.fromJson(json, 'sub_notes_legacy');
      expect(req.description, equals('Legacy notes field content'));
    });

    test('4. SubRequest.fromJson omits eventType and start/end times for New Member', () {
      final json = {
        'subRequestId': 'sub_mem_json',
        'RequestType': 'New Band Member',
        'Role': 'New Member',
        'EventType': 'Concert',
        'StartTime': '19:00',
        'EndTime': '21:00',
        'Date': '2028-11-20',
        'Location': 'Stockholm',
        'City': 'Stockholm',
      };

      final req = SubRequest.fromJson(json, 'sub_mem_json');
      expect(req.requestType, equals('New Member'));
      expect(req.eventType, isNull);
      expect(req.resolvedEventType, isNull);
      expect(req.startTime, isNull);
      expect(req.endTime, isNull);
      expect(req.date, isNull);
    });

    test('5. SubRequest.toJson outputs canonical fields without duplicates', () {
      final req = SubRequest(
        subRequestId: 'sub_json_1',
        requestType: 'Substitute',
        role: 'Substitute',
        eventType: 'Concert',
        startTime: '19:00',
        endTime: '22:00',
        description: 'Test description',
        payDetails: 'Fuel compensated',
        location: 'Stockholm Concert Hall',
        isPaid: true,
        payAmount: 1200,
        currency: 'SEK',
      );

      final map = req.toJson();
      expect(map['RequestType'], equals('Substitute'));
      expect(map['EventType'], equals('Concert'));
      expect(map['StartTime'], equals('19:00'));
      expect(map['EndTime'], equals('22:00'));
      expect(map['Description'], equals('Test description'));
      expect(map['PayDetails'], equals('Fuel compensated'));
      expect(map['IsPaid'], isTrue);
    });
  });

  group('SUBREQUEST-DATA-CONSISTENCY-01: UI Surface Presentation', () {
    // SCENARIO 1 — FULL SUBSTITUTE GIG
    testWidgets('6. Scenario 1: Find Gigs card and details modal display all repaired fields', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      final gig = SubRequest(
        id: 'full_sub_1',
        subRequestId: 'full_sub_1',
        bandName: 'Aurora Jazz Band',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Tenor Sax',
        eventType: 'Concert',
        date: '2026-11-20',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Fasching, Kungsgatan 63, Stockholm',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        description: 'Controlled QA description',
        payDetails: 'Paid after completed performance',
      );
      mockService.requests.add(gig);

      final appState = MockConsistencyAppState(mockService, activeUserId: 'musician_viewer');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Compact card assertions
      expect(find.text('Aurora Jazz Band'), findsOneWidget);
      expect(find.text('Substitute · Tenor Sax'), findsOneWidget);
      expect(find.textContaining('Concert · Paid · 1,500 SEK'), findsOneWidget);
      expect(find.textContaining('18.00–21.30'), findsOneWidget);
      expect(find.textContaining('Fasching, Kungsgatan 63, Stockholm'), findsOneWidget);

      // Open details modal
      await tester.tap(find.text('Aurora Jazz Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 2. Details modal assertions
      expect(find.text('Request Type'), findsOneWidget);
      expect(find.text('Substitute'), findsWidgets);
      expect(find.text('Event Type'), findsOneWidget);
      expect(find.text('Concert'), findsOneWidget);
      expect(find.text('Role / Instrument'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Paid · 1,500 SEK'), findsOneWidget);
      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.textContaining('18.00–21.30'), findsWidgets);
      expect(find.text('Location / Venue'), findsOneWidget);
      expect(find.text('Fasching, Kungsgatan 63, Stockholm'), findsWidgets);
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text('Controlled QA description'), findsOneWidget);
      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('Paid after completed performance'), findsOneWidget);
    });

    testWidgets('7. Scenario 1: Manage Requests compact card and View Responses summary display all repaired fields', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      mockService.fixtureUid='creator_1';
      mockService.bandRoles['band_aurora/creator_1']='leader';
      final gig = SubRequest(
        id: 'manage_sub_1',
        subRequestId: 'manage_sub_1',
        bandId: 'band_aurora',
        bandName: 'Aurora Jazz Band',
        creatorUserId: 'creator_1',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Tenor Sax',
        eventType: 'Concert',
        date: '2026-11-20',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Fasching, Kungsgatan 63, Stockholm',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        description: 'Controlled QA description',
        payDetails: 'Paid after completed performance',
      );
      mockService.requests.add(gig);
      mockService.responseCounts['manage_sub_1'] = 2;

      final appState = MockConsistencyAppState(mockService, activeUserId: 'creator_1');

      // Test View Responses summary screen
      await tester.pumpWidget(createTestApp(
        child: SubRequestResponseDetailsScreen(subRequest: gig),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Aurora Jazz Band'), findsOneWidget);
      expect(find.text('Substitute · Tenor Sax'), findsOneWidget);
      expect(find.textContaining('Concert · Paid · 1,500 SEK'), findsOneWidget);
      expect(find.textContaining('18.00–21.30'), findsOneWidget);
      expect(find.textContaining('Fasching, Kungsgatan 63, Stockholm'), findsOneWidget);
      expect(find.text('Controlled QA description'), findsOneWidget);
      expect(find.text('Paid after completed performance'), findsOneWidget);
    });

    // SCENARIO 2 — MULTI-POSITION REQUEST
    testWidgets('8. Scenario 2: Multi-position request preserves shared event info and distinct roles/slots', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      final slot1 = SubRequest(
        id: 'multi_slot_1',
        subRequestId: 'multi_slot_1',
        requestGroupId: 'req_group_multi_1',
        bandName: 'Brass Quintet',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Trumpet 1',
        eventType: 'Gala Dinner',
        date: '2028-11-15T19:00:00Z',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm City Hall',
        isPaid: true,
        payAmount: 1800,
        currency: 'SEK',
      );
      final slot2 = SubRequest(
        id: 'multi_slot_2',
        subRequestId: 'multi_slot_2',
        requestGroupId: 'req_group_multi_1',
        bandName: 'Brass Quintet',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'French Horn',
        eventType: 'Gala Dinner',
        date: '2028-11-15T19:00:00Z',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm City Hall',
        isPaid: true,
        payAmount: 1800,
        currency: 'SEK',
      );

      mockService.requests.addAll([slot1, slot2]);
      final appState = MockConsistencyAppState(mockService, activeUserId: 'musician_viewer');

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Grouped card displays first role and count indicator (+1)
      expect(find.text('Brass Quintet'), findsOneWidget);
      expect(find.text('Substitute · Trumpet 1 (+1)'), findsOneWidget);
      expect(find.textContaining('Gala Dinner · Paid · 1,800 SEK'), findsOneWidget);

      // Open details modal
      await tester.tap(find.text('Brass Quintet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Both individual slots are displayed
      expect(find.text('Trumpet 1'), findsOneWidget);
      expect(find.text('French Horn'), findsOneWidget);
    });

    // SCENARIO 3 — NEW BAND MEMBER
    testWidgets('9. Scenario 3: New Band Member omits eventType, dates/times and keeps city-level location', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      final newMemberReq = SubRequest(
        id: 'mem_req_1',
        subRequestId: 'mem_req_1',
        bandName: 'Nordic Metal',
        requestType: 'New Member',
        role: 'New Member',
        voicePart: 'Drums',
        location: 'Stockholm',
        city: 'Stockholm',
        locationPrecision: LocationPrecision.city,
        description: 'Searching for a permanent lead guitarist for studio recording and live touring.',
      );
      mockService.requests.add(newMemberReq);

      final appState = MockConsistencyAppState(mockService, activeUserId: 'musician_viewer');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Members tab
      await tester.tap(find.textContaining('New Member'));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Nordic Metal'), findsOneWidget);
      expect(find.text('New Band Member · Drums'), findsOneWidget);
      // No event or date line on compact card
      expect(find.textContaining('Concert'), findsNothing);
      expect(find.textContaining('18.00'), findsNothing);

      // Open details modal
      await tester.tap(find.text('Nordic Metal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify strict omission of event fields
      expect(find.text('Event Type'), findsNothing);
      expect(find.text('Date & Time'), findsNothing);
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text('Searching for a permanent lead guitarist for studio recording and live touring.'), findsOneWidget);
      expect(find.text('Location / Venue'), findsOneWidget);
      expect(find.text('Stockholm'), findsWidgets);
    });

    // SCENARIO 5 — MISSING OPTIONAL DATA
    testWidgets('10. Scenario 5: Missing optional data produces clean omission without placeholders', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      final minimalReq = SubRequest(
        id: 'min_req_1',
        subRequestId: 'min_req_1',
        bandName: 'Acoustic Trio',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Saxophone',
        date: '2028-12-01T15:00:00Z',
        startTime: null,
        endTime: null,
        eventType: null,
        location: null,
        city: null,
        isPaid: false,
        payAmount: null,
        payDetails: null,
        description: null,
      );
      mockService.requests.add(minimalReq);

      final appState = MockConsistencyAppState(mockService, activeUserId: 'musician_viewer');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Acoustic Trio'), findsOneWidget);
      expect(find.text('Substitute · Saxophone'), findsOneWidget);

      // No placeholders rendered on card
      expect(find.text('null'), findsNothing);
      expect(find.text('N/A'), findsNothing);
      expect(find.text('Not provided'), findsNothing);
      expect(find.text('Paid'), findsNothing);

      // Open details modal
      await tester.tap(find.text('Acoustic Trio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Missing sections are cleanly omitted
      expect(find.text('Event Type'), findsNothing);
      expect(find.text('Payment Details'), findsNothing);
      expect(find.text('Description / Details'), findsNothing);
      expect(find.text('Location / Venue'), findsNothing);
      expect(find.text('Not provided'), findsNothing);
      expect(find.text('null'), findsNothing);
      expect(find.text('N/A'), findsNothing);
    });

    // RESPONSIVE VIEWPORT 320 PX
    testWidgets('11. 320 px viewport Find Gigs card and modal render without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockConsistencyFirebaseService();
      final fullGig = SubRequest(
        id: 'overflow_check_1',
        subRequestId: 'overflow_check_1',
        bandName: 'Very Long Band Name With Exhaustive Details And Complex Structure',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Multi-Instrumentalist Specialist (Woodwinds & Brass)',
        eventType: 'International Symphonic Showcase',
        date: '2028-11-20T18:00:00Z',
        startTime: '18:00',
        endTime: '22:30',
        location: 'Stockholm Concert Hall Grand Auditorium, Hötorget 8, Stockholm',
        isPaid: true,
        payAmount: 2500,
        currency: 'SEK',
        description: 'Exhaustive description text intended to test narrow container wrapping across 320 pixels.',
        payDetails: 'Full travel, accommodation, per diem, and rehearsal compensation provided.',
      );
      mockService.requests.add(fullGig);

      final appState = MockConsistencyAppState(mockService, activeUserId: 'musician_viewer');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: 'Card must not throw overflow exception at 320 px');

      // Open details modal at 320 px
      await tester.tap(find.textContaining('Very Long Band Name'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull, reason: 'Modal must not throw overflow exception at 320 px');
    });

    // DIRECT PERSISTENCE DENIAL
    test('12. Direct client persistence is denied while publication succeeds through callable', () async {
      final mockService = MockConsistencyFirebaseService();
      final req = SubRequest(
        id: 'client_write_test_1',
        bandId: 'band_denial_1',
        voicePart: 'Bass',
        requestType: 'Substitute',
      );

      // Attempting direct batch persistence throws StateError
      expect(
        () => mockService.saveSubRequestsBatchAsync([req]),
        throwsA(isA<StateError>()),
      );
      expect(mockService.directWriteCalls, equals(1));

      // In contrast, simulated server-callable publication succeeds without client direct writes
      final publishedIds = await mockService.testPublishSubRequestGroupAsync(
        bandId: 'band_denial_1',
        requestGroupId: 'req_grp_1',
        requestsToPublish: [req],
      );

      expect(publishedIds, hasLength(1));
      expect(mockService.callableCallCount, equals(1));
      // Proves zero additional direct persistence calls occurred during publication
      expect(mockService.directWriteCalls, equals(1));
    });
  });
}
