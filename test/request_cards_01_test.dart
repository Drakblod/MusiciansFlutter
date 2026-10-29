import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/sub_request_responses_screen.dart';
import 'package:musicians_flutter/views/sub_request_response_details_screen.dart';
import 'package:musicians_flutter/utils/sub_request_card_helper.dart';

class MockCardsFirebaseService extends FirebaseService {
  final List<SubRequest> requests = [];
  final Set<String> appliedIds = {};
  final Map<String, int> responseCounts = {};
  final Map<String, String> bandRoles = {}; // '$bandId/$userId' -> 'leader'/'member'
  final List<String> deletedRequestIds = [];

  @override
  String? get currentUserId => 'test_user_active';

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => List.from(requests);

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async =>
      requests.where((r) => r.creatorUserId == userId || r.userId == userId).toList();

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => List.from(requests);

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => Set.from(appliedIds);

  @override
  Future<int> getSubRequestResponseCountAsync(String subRequestId) async {
    return responseCounts[subRequestId] ?? 0;
  }



  Completer<bool>? delayedAdminCompleter;
  int adminLookupCalls = 0;
  bool shouldFailAdminLookup = false;

  @override
  Future<bool> isBandLeaderOrAdminAsync(String bandId, String userId) async {
    adminLookupCalls++;
    if (shouldFailAdminLookup) {
      throw Exception('Network error during admin lookup');
    }
    if (delayedAdminCompleter != null) {
      return delayedAdminCompleter!.future;
    }
    final role = bandRoles['$bandId/$userId'];
    return role == 'leader' || role == 'admin';
  }

  @override
  Future<void> addResponseToSubRequestAsync(String subRequestId, String userId) async {
    appliedIds.add(subRequestId);
    for (final r in requests) {
      if ((r.subRequestId ?? r.id) == subRequestId) {
        r.responses[userId] = true;
      }
    }
  }

  @override
  Future<bool> deleteSubRequestAsync(String creatorId, String subRequestId) async {
    deletedRequestIds.add(subRequestId);
    requests.removeWhere((r) => (r.subRequestId ?? r.id) == subRequestId);
    return true;
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
      userId: userId ?? 'applicant_1',
      displayName: 'Applicant ${userId ?? "1"}',
      instruments: ['Saxophone'],
    );
  }
}

class MockCardsAppState extends AppState {
  final MockCardsFirebaseService mockService;
  String? activeUserId;
  UserProfile? activeProfile;

  MockCardsAppState(this.mockService, {this.activeUserId = 'test_user_active', List<String>? instruments}) {
    activeProfile = UserProfile(
      userId: activeUserId,
      displayName: 'Active User',
      instruments: instruments ?? const [],
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
  required MockCardsAppState appState,
  Size size = const Size(800, 2000),
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/sub-request-response-details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return SubRequestResponseDetailsScreen(subRequest: args['subRequest'] as SubRequest);
        },
      },
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
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

  group('REQUEST-CARDS-01 — Unified Card Presentation & Visual Hierarchy', () {
    // 1. Find Gigs uses the approved compact hierarchy
    testWidgets('1. Find Gigs uses the approved compact hierarchy (Band, Type·Role, Event·Paid, Date, Location, Action)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final gig = SubRequest(
        id: 'gig_1',
        subRequestId: 'gig_1',
        bandName: 'Deku Tree Bongo',
        requestType: 'Substitute',
        role: 'Substitute',
        voicePart: 'Alto Sax',
        date: '2026-10-30T18:00:00Z',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Sundsvall Music Hall, Sundsvall',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        extraFields: {'eventType': 'Concert'},
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'musician_other');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Deku Tree Bongo'), findsOneWidget);
      expect(find.text('Substitute · Alto Sax'), findsOneWidget);
      expect(find.textContaining('Concert · Paid'), findsOneWidget);
      expect(find.textContaining('18.00–21.30'), findsOneWidget);
      expect(find.text('Sundsvall Music Hall, Sundsvall'), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_apply_gig_1')), findsOneWidget);
    });

    // 2. Manage Requests uses the approved compact hierarchy
    testWidgets('2. Manage Requests uses the approved compact hierarchy', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final req = SubRequest(
        id: 'manage_1',
        subRequestId: 'manage_1',
        creatorUserId: 'test_creator',
        userId: 'test_creator',
        bandName: 'Deku Tree Bongo',
        requestType: 'Substitute',
        voicePart: 'Alto Sax',
        date: '2026-10-30T18:00:00Z',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Sundsvall Music Hall, Sundsvall',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        extraFields: {'eventType': 'Concert'},
      );
      mockService.requests.add(req);
      mockService.responseCounts['manage_1'] = 3;

      final appState = MockCardsAppState(mockService, activeUserId: 'test_creator');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Deku Tree Bongo'), findsOneWidget);
      expect(find.text('Substitute · Alto Sax'), findsOneWidget);
      expect(find.textContaining('Concert · Paid'), findsOneWidget);
      expect(find.textContaining('18.00–21.30'), findsOneWidget);
      expect(find.text('View Responses (3)'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete_request_manage_1')), findsOneWidget);
    });

    // 3. Large month/day badges are absent
    testWidgets('3. Large month/day badges are absent from compact cards', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'no_badge_req',
        bandName: 'Groove Band',
        date: '2026-10-30T18:00:00Z',
        voicePart: 'Bass',
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Month/day uppercase badge 'OCT' and '30' stacked container should not be rendered
      expect(find.text('OCT'), findsNothing);
    });

    // 4. Date line includes weekday, date and available times
    test('4. Date line includes weekday, date and available times (Fri, Oct 30 · 18.00–21.30)', () {
      final formatted = formatSubRequestDateTime(
        date: '2026-10-30T18:00:00Z',
        startTime: '18:00',
        endTime: '21:30',
      );
      expect(formatted, contains('Fri, Oct 30 · 18.00–21.30'));
    });

    // 5. No duration is invented when end time is missing
    test('5. No duration is invented when end time is missing', () {
      final formatted = formatSubRequestDateTime(
        date: '2026-10-30T18:00:00Z',
        startTime: '18:00',
        endTime: null,
      );
      expect(formatted, contains('Fri, Oct 30 · 18.00'));
      expect(formatted, isNot(contains('–')));
      expect(formatted, isNot(contains('21:00')));
    });

    // 6. Request Type appears before Role/Event Type in details
    testWidgets('6. Request Type appears before Role and Event Type in details bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'order_test_req',
        subRequestId: 'order_test_req',
        bandName: 'Hierarchy Band',
        requestType: 'Substitute',
        voicePart: 'Tenor Sax',
        date: '2026-11-15T19:00:00Z',
        extraFields: {'eventType': 'Festival'},
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap card to open details bottom sheet
      await tester.tap(find.text('Hierarchy Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final fReqType = find.text('Request Type');
      final fRole = find.text('Role / Instrument');
      final fEventType = find.text('Event Type');

      expect(fReqType, findsOneWidget);
      expect(fRole, findsOneWidget);
      expect(fEventType, findsOneWidget);

      final yReqType = tester.getTopLeft(fReqType).dy;
      final yRole = tester.getTopLeft(fRole).dy;
      final yEventType = tester.getTopLeft(fEventType).dy;

      // Required hierarchy: Request Type < Role < Event Type
      expect(yReqType, lessThan(yRole));
      expect(yRole, lessThan(yEventType));
    });

    // 7. Role / Instrument contains no Date & Time
    test('7. Role / Instrument contains no Date & Time', () {
      final req = SubRequest(
        role: 'Substitute',
        voicePart: 'Drums',
        date: '2026-10-30',
        startTime: '19:00',
      );
      final role = resolveSingleRole(req);
      expect(role, equals('Drums'));
      expect(role.contains('19:00'), isFalse);
      expect(role.contains('2026'), isFalse);
    });

    // 8. Role / Instrument contains no Event Name
    test('8. Role / Instrument contains no Event Name', () {
      final req = SubRequest(
        role: 'Substitute',
        voicePart: 'Keyboard',
        eventTitle: 'Big Jazz Gala',
      );
      final role = resolveSingleRole(req);
      expect(role, equals('Keyboard'));
      expect(role.contains('Big Jazz Gala'), isFalse);
    });

    // 9. Verbose “event(s) · position(s)” summary is absent
    testWidgets('9. Verbose "event(s) · position(s)" summary is absent from compact cards', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.addAll([
        SubRequest(id: 'r1', requestGroupId: 'grp1', bandName: 'Multi Band', voicePart: 'Trumpet', date: '2026-11-01'),
        SubRequest(id: 'r2', requestGroupId: 'grp1', bandName: 'Multi Band', voicePart: 'Trombone', date: '2026-11-01'),
      ]);

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('event ·'), findsNothing);
      expect(find.textContaining('events ·'), findsNothing);
      expect(find.textContaining('position'), findsNothing);
    });

    // 10. Verbose “positions filled” summary is absent from compact cards
    testWidgets('10. Verbose "positions filled" summary is absent from compact cards', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.addAll([
        SubRequest(id: 'r1', requestGroupId: 'grp1', bandName: 'Multi Band', voicePart: 'Trumpet', date: '2026-11-01'),
        SubRequest(id: 'r2', requestGroupId: 'grp1', bandName: 'Multi Band', voicePart: 'Trombone', date: '2026-11-01', status: 'assigned'),
      ]);

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('positions filled'), findsNothing);
      expect(find.textContaining('of 2 positions'), findsNothing);
    });

    // 11. Paid request shows payment amount and currency
    testWidgets('11. Paid request shows payment amount and currency', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'paid_req',
        bandName: 'Paid Band',
        voicePart: 'Violin',
        isPaid: true,
        payAmount: 2500,
        currency: 'SEK',
        extraFields: {'eventType': 'Concert'},
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('2,500 SEK'), findsOneWidget);
      expect(find.textContaining(',00'), findsNothing);
    });

    // 12. Unpaid request does not render an empty Paid row
    testWidgets('12. Unpaid request does not render an empty Paid row', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'unpaid_req',
        bandName: 'Free Band',
        voicePart: 'Clarinet',
        isPaid: false,
        extraFields: {'eventType': 'Jam Session'},
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Paid'), findsNothing);
      expect(find.text('Jam Session'), findsOneWidget);
    });

    // 13. Payment Details renders only when present
    testWidgets('13. Payment Details renders only when present', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'pay_details_req',
        bandName: 'Payment Info Band',
        voicePart: 'Cello',
        isPaid: true,
        payAmount: 1800,
        payDetails: 'Travel and hotel compensated',
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open details bottom sheet
      await tester.tap(find.text('Payment Info Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('Travel and hotel compensated'), findsOneWidget);
    });

    // 14. Description / Details renders once and expands fully in details
    testWidgets('14. Description / Details renders once and displays full text in details', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      const fullDesc = 'Full concert performance with soundcheck at 16:00 and dinner provided.';
      mockService.requests.add(SubRequest(
        id: 'desc_req',
        bandName: 'Desc Band',
        voicePart: 'Flute',
        description: fullDesc,
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open details
      await tester.tap(find.text('Desc Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text(fullDesc), findsOneWidget);
    });

    // 15. Location / Venue uses the standardized label
    testWidgets('15. Location / Venue uses the standardized label in details and header', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'loc_venue_req',
        bandName: 'Venue Band',
        voicePart: 'Organ',
        location: 'Stockholm Cathedral',
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Venue Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Location / Venue'), findsOneWidget);
    });

    // 16. Canonical New Member displays as New Band Member
    test('16. Canonical New Member displays as New Band Member', () {
      final req = SubRequest(
        requestType: 'New Member',
        role: 'New Member',
        voicePart: 'Bassist',
      );
      final label = resolveRequestTypeLabel(req);
      expect(label, equals('New Band Member'));
    });

    // 17. New Band Member omits irrelevant Event Type/date placeholders
    testWidgets('17. New Band Member omits irrelevant Event Type and date placeholders', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'member_req_1',
        subRequestId: 'member_req_1',
        bandName: 'Recruiting Band',
        requestType: 'New Member',
        role: 'New Member',
        voicePart: 'Lead Vocalist',
        location: 'Uppsala',
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Members tab
      await tester.tap(find.textContaining('New Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Recruiting Band'), findsOneWidget);
      expect(find.text('New Band Member · Lead Vocalist'), findsOneWidget);
      // No event type or date placeholders
      expect(find.textContaining('Event Type'), findsNothing);
      expect(find.textContaining('Date & Time'), findsNothing);
    });

    // 18. Creator sees Manage Request rather than Your Request
    testWidgets('18. Creator sees Manage Request rather than Your Request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'creator_req_1',
        subRequestId: 'creator_req_1',
        creatorUserId: 'test_creator_123',
        bandName: 'My Awesome Band',
        voicePart: 'Drums',
        date: '2026-11-20',
      ));

      final appState = MockCardsAppState(mockService, activeUserId: 'test_creator_123');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Manage Request'), findsOneWidget);
      expect(find.text('Your Request'), findsNothing);
    });

    // 19. Creator does not see Apply
    testWidgets('19. Creator does not see Apply on their own request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'creator_req_2',
        subRequestId: 'creator_req_2',
        creatorUserId: 'test_creator_123',
        bandName: 'My Awesome Band',
        voicePart: 'Drums',
        date: '2026-11-20',
      ));

      final appState = MockCardsAppState(mockService, activeUserId: 'test_creator_123');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Apply'), findsNothing);
    });

    // 20. Eligible unrelated user sees Apply
    testWidgets('20. Eligible unrelated user sees Apply', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'unrelated_req',
        subRequestId: 'unrelated_req',
        creatorUserId: 'other_user',
        bandName: 'Other Band',
        voicePart: 'Alto Sax',
        date: '2026-11-20',
      ));

      final appState = MockCardsAppState(mockService, activeUserId: 'candidate_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('find_gigs_apply_unrelated_req')), findsOneWidget);
    });

    // 21. Applied user sees Applied
    testWidgets('21. Applied user sees Applied', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'applied_req',
        subRequestId: 'applied_req',
        creatorUserId: 'other_user',
        bandName: 'Other Band',
        voicePart: 'Alto Sax',
        date: '2026-11-20',
        responses: {'candidate_user': true},
      ));
      mockService.appliedIds.add('applied_req');

      final appState = MockCardsAppState(mockService, activeUserId: 'candidate_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
    });

    // 22. Ordinary band member cannot see Manage Request
    testWidgets('22. Ordinary band member cannot see Manage Request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'member_view_req',
        subRequestId: 'member_view_req',
        creatorUserId: 'leader_user',
        bandId: 'band_rock',
        bandName: 'Rock Band',
        voicePart: 'Alto Sax',
        date: '2026-11-20',
      ));
      // User is ordinary member, NOT leader/admin
      mockService.bandRoles['band_rock/ordinary_member'] = 'member';

      final appState = MockCardsAppState(mockService, activeUserId: 'ordinary_member');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Manage Request'), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_apply_member_view_req')), findsOneWidget);
    });

    // 23. Correct Leader/Admin authorization is preserved
    testWidgets('23. Correct Leader/Admin authorization is preserved and shows Manage Request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'admin_req',
        subRequestId: 'admin_req',
        creatorUserId: 'coleader_user',
        bandId: 'band_rock',
        bandName: 'Rock Band',
        voicePart: 'Alto Sax',
        date: '2026-11-20',
      ));
      mockService.bandRoles['band_rock/band_leader'] = 'leader';

      final appState = MockCardsAppState(mockService, activeUserId: 'band_leader');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // As leader, user sees Manage Request
      expect(find.byKey(const ValueKey('find_gigs_manage_request_admin_req')), findsOneWidget);
    });

    // 24. View Responses opens the matching subRequestId
    testWidgets('24. View Responses opens the matching subRequestId', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final targetReq = SubRequest(
        id: 'req_target_24',
        subRequestId: 'req_target_24',
        creatorUserId: 'test_creator',
        bandName: 'Target Band',
        voicePart: 'Trumpet',
        date: '2026-11-25',
      );
      mockService.requests.add(targetReq);
      mockService.responseCounts['req_target_24'] = 2;

      final appState = MockCardsAppState(mockService, activeUserId: 'test_creator');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('view_responses_req_target_24')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view_responses_req_target_24')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Navigated to response details header
      expect(find.text('Target Band'), findsWidgets);
      expect(find.text('CANDIDATES & RESPONSES'), findsOneWidget);
    });

    // 25. Response counts remain isolated to the matching subRequestId
    testWidgets('25. Response counts remain isolated to the matching subRequestId', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.addAll([
        SubRequest(id: 'iso_1', subRequestId: 'iso_1', creatorUserId: 'creator_iso', bandName: 'Band A', voicePart: 'Flute', date: '2026-11-20'),
        SubRequest(id: 'iso_2', subRequestId: 'iso_2', creatorUserId: 'creator_iso', bandName: 'Band B', voicePart: 'Oboe', date: '2026-11-20'),
      ]);
      mockService.responseCounts['iso_1'] = 5;
      mockService.responseCounts['iso_2'] = 1;

      final appState = MockCardsAppState(mockService, activeUserId: 'creator_iso');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('View Responses (5)'), findsOneWidget);
      expect(find.text('View Responses (1)'), findsOneWidget);
    });

    // 26. Delete remains available as a secondary action
    testWidgets('26. Delete remains available as a secondary action with accessible tooltip', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'del_test_26',
        subRequestId: 'del_test_26',
        creatorUserId: 'creator_del',
        bandName: 'Delete Me Band',
        voicePart: 'Bass',
        date: '2026-11-20',
      ));

      final appState = MockCardsAppState(mockService, activeUserId: 'creator_del');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final deleteBtn = find.byKey(const ValueKey('delete_request_del_test_26'));
      expect(deleteBtn, findsOneWidget);
      final iconBtn = tester.widget<IconButton>(deleteBtn);
      expect(iconBtn.tooltip, equals('Delete request'));
    });

    // 27. Delete retains confirmation
    testWidgets('27. Delete retains confirmation dialog before deleting', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'del_confirm_27',
        subRequestId: 'del_confirm_27',
        creatorUserId: 'creator_del',
        bandName: 'Confirm Delete Band',
        voicePart: 'Bass',
        date: '2026-11-20',
      ));

      final appState = MockCardsAppState(mockService, activeUserId: 'creator_del');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('delete_request_del_confirm_27')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Confirm Delete'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this request?'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.widgetWithText(ElevatedButton, 'Yes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.deletedRequestIds, contains('del_confirm_27'));
    });

    // 28. Grouped requests list all roles without duplicate cards
    testWidgets('28. Grouped requests show first role +N on card and list all roles in details', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.addAll([
        SubRequest(id: 'grp_r1', subRequestId: 'grp_r1', requestGroupId: 'brass_group', bandName: 'Brass Quintet', voicePart: 'Trumpet 1', location: 'Gothenburg', date: '2026-11-20'),
        SubRequest(id: 'grp_r2', subRequestId: 'grp_r2', requestGroupId: 'brass_group', bandName: 'Brass Quintet', voicePart: 'French Horn', location: 'Gothenburg', date: '2026-11-20'),
        SubRequest(id: 'grp_r3', subRequestId: 'grp_r3', requestGroupId: 'brass_group', bandName: 'Brass Quintet', voicePart: 'Tuba', location: 'Gothenburg', date: '2026-11-20'),
      ]);

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Only one card rendered for the group
      expect(find.text('Brass Quintet'), findsOneWidget);
      expect(find.text('Substitute · Trumpet 1 (+2)'), findsOneWidget);

      // Open details
      await tester.tap(find.text('Brass Quintet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // All 3 individual roles listed cleanly
      expect(find.text('Trumpet 1'), findsOneWidget);
      expect(find.text('French Horn'), findsOneWidget);
      expect(find.text('Tuba'), findsOneWidget);
    });

    // 29. Grouped request actions affect only the correct IDs
    testWidgets('29. Grouped request actions affect only the matching slot ID', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.addAll([
        SubRequest(id: 'slot_a', subRequestId: 'slot_a', requestGroupId: 'grp_pair', bandName: 'Pair Band', voicePart: 'Alto Sax', location: 'Stockholm', date: '2026-11-20'),
        SubRequest(id: 'slot_b', subRequestId: 'slot_b', requestGroupId: 'grp_pair', bandName: 'Pair Band', voicePart: 'Electric Guitar', location: 'Stockholm', date: '2026-11-20'),
      ]);

      final appState = MockCardsAppState(mockService, activeUserId: 'candidate_user_99');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open details
      await tester.tap(find.text('Pair Band'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Apply specifically to slot_b
      expect(find.byKey(const ValueKey('details_apply_slot_b')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('details_apply_slot_b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.appliedIds, contains('slot_b'));
      expect(mockService.appliedIds, isNot(contains('slot_a')));
    });

    // 30. Missing optional legacy data produces no null/empty separator text
    test('30. Missing optional legacy data produces no null or empty separator text', () {
      final legacyReq = SubRequest(
        id: 'legacy_bare',
        // All optional fields absent:
        bandName: null,
        eventTitle: null,
        location: null,
        city: null,
        date: null,
        startTime: null,
        endTime: null,
        payAmount: null,
        payDetails: null,
        description: null,
        extraFields: {},
      );

      final presentation = SubRequestCardPresentation.fromSubRequest(legacyReq);

      expect(presentation.bandName, equals('Band'));
      expect(presentation.roleInstrument, equals('Musician'));
      expect(presentation.eventTypeAndPaymentLine, isNull);
      expect(presentation.formattedDateTime, isNull);
      expect(presentation.locationVenue, isNull);
      expect(presentation.description, isNull);
      expect(presentation.payDetails, isNull);
    });

    // 31. 320 px Find Gigs card has no overflow
    testWidgets('31. 320 px Find Gigs card has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'narrow_gig',
        bandName: 'Very Long Symphony Orchestra Ensemble Project Name',
        voicePart: 'First Principal French Horn',
        date: '2026-11-20T19:00:00Z',
        startTime: '19:00',
        endTime: '22:30',
        location: 'Extremely Long Venue Location Name in Stockholm City Center',
        isPaid: true,
        payAmount: 3500,
        currency: 'SEK',
        extraFields: {'eventType': 'Orchestral Concert'},
      ));

      final appState = MockCardsAppState(mockService);
      await tester.pumpWidget(createTestApp(
        child: const FindGigsScreen(),
        appState: appState,
        size: const Size(320, 1000),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    // 32. 320 px Manage Requests card has no overflow
    testWidgets('32. 320 px Manage Requests card has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.requests.add(SubRequest(
        id: 'narrow_manage',
        subRequestId: 'narrow_manage',
        creatorUserId: 'active_creator',
        bandName: 'Very Long Symphony Orchestra Ensemble Project Name',
        voicePart: 'First Principal French Horn',
        date: '2026-11-20T19:00:00Z',
        startTime: '19:00',
        endTime: '22:30',
        location: 'Extremely Long Venue Location Name in Stockholm City Center',
        isPaid: true,
        payAmount: 3500,
        currency: 'SEK',
        extraFields: {'eventType': 'Orchestral Concert'},
      ));
      mockService.responseCounts['narrow_manage'] = 12;

      final appState = MockCardsAppState(mockService, activeUserId: 'active_creator');
      await tester.pumpWidget(createTestApp(
        child: const SubRequestResponsesScreen(bandId: 'all'),
        appState: appState,
        size: const Size(320, 1000),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    // 33. Existing Map View Apply/Manage Request behavior remains intact
    testWidgets('33. Map View presentation preserves CanonicalLocation and privacy rules', (tester) async {
      final substituteReq = SubRequest(
        id: 'map_sub',
        requestType: 'Substitute',
        location: 'Kafé 44, Stockholm',
        latitude: 59.3145,
        longitude: 18.0812,
      );
      final memberReq = SubRequest(
        id: 'map_member',
        requestType: 'New Member',
        location: 'Stockholm, Sweden',
        city: 'Stockholm',
        latitude: 59.3293,
        longitude: 18.0686,
      );

      final subPres = SubRequestCardPresentation.fromSubRequest(substituteReq);
      final memPres = SubRequestCardPresentation.fromSubRequest(memberReq);

      expect(subPres.requestType, equals('Substitute'));
      expect(subPres.locationVenue, equals('Kafé 44, Stockholm'));

      expect(memPres.requestType, equals('New Band Member'));
      expect(memPres.locationVenue, equals('Stockholm, Sweden'));
      expect(memPres.eventTypeAndPaymentLine, isNull);
      expect(memPres.formattedDateTime, isNull);
    });

    // -------------------------------------------------------------
    // EXACT MANAGE REQUEST NAVIGATION
    // -------------------------------------------------------------
    testWidgets('34. Manage Request from Find Gigs opens exact matching SubRequestResponseDetailsScreen for single request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final req1 = SubRequest(
        id: 'req_single_1',
        subRequestId: 'req_single_1',
        creatorUserId: 'user_active',
        bandId: 'band_100',
        bandName: 'Band One',
        role: 'Drummer',
      );
      mockService.requests.add(req1);

      final appState = MockCardsAppState(mockService, activeUserId: 'user_active');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('find_gigs_manage_request_req_single_1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('find_gigs_manage_request_req_single_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verifies SubRequestResponseDetailsScreen was opened for req_single_1
      expect(find.byType(SubRequestResponseDetailsScreen), findsOneWidget);
      expect(find.text('Band One'), findsWidgets);
      expect(find.text('Substitute · Drummer'), findsOneWidget);
    });

    testWidgets('35. Two requests from the same band: tapping Manage Request on request A opens request A only, never request B', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final reqA = SubRequest(
        id: 'req_A',
        subRequestId: 'req_A',
        creatorUserId: 'same_band_creator',
        bandId: 'shared_band_1',
        bandName: 'Shared Band',
        role: 'Lead Guitarist',
        description: 'Audition for Lead Guitar slot A',
      );
      final reqB = SubRequest(
        id: 'req_B',
        subRequestId: 'req_B',
        creatorUserId: 'same_band_creator',
        bandId: 'shared_band_1',
        bandName: 'Shared Band',
        role: 'Keyboardist',
        description: 'Audition for Keyboard slot B',
      );
      mockService.requests.addAll([reqA, reqB]);

      final appState = MockCardsAppState(mockService, activeUserId: 'same_band_creator');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Manage Request on card A
      await tester.tap(find.byKey(const ValueKey('find_gigs_manage_request_req_A')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SubRequestResponseDetailsScreen), findsOneWidget);
      expect(find.text('Substitute · Lead Guitarist'), findsOneWidget);
      expect(find.text('Audition for Lead Guitar slot A'), findsOneWidget);
      expect(find.text('Substitute · Keyboardist'), findsNothing);
      expect(find.text('Audition for Keyboard slot B'), findsNothing);
    });

    testWidgets('36. Two requests from the same band: tapping Manage Request on request B opens request B only, never request A', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final reqA = SubRequest(
        id: 'req_A2',
        subRequestId: 'req_A2',
        creatorUserId: 'same_band_creator2',
        bandId: 'shared_band_2',
        bandName: 'Shared Band Two',
        role: 'Lead Guitarist',
        description: 'Audition for Lead Guitar slot A',
      );
      final reqB = SubRequest(
        id: 'req_B2',
        subRequestId: 'req_B2',
        creatorUserId: 'same_band_creator2',
        bandId: 'shared_band_2',
        bandName: 'Shared Band Two',
        role: 'Keyboardist',
        description: 'Audition for Keyboard slot B',
      );
      mockService.requests.addAll([reqA, reqB]);

      final appState = MockCardsAppState(mockService, activeUserId: 'same_band_creator2');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Manage Request on card B
      await tester.tap(find.byKey(const ValueKey('find_gigs_manage_request_req_B2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SubRequestResponseDetailsScreen), findsOneWidget);
      expect(find.text('Substitute · Keyboardist'), findsOneWidget);
      expect(find.text('Audition for Keyboard slot B'), findsOneWidget);
      expect(find.text('Substitute · Lead Guitarist'), findsNothing);
      expect(find.text('Audition for Lead Guitar slot A'), findsNothing);
    });

    testWidgets('37. Back navigation from SubRequestResponseDetailsScreen returns safely to Find Gigs', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final req = SubRequest(
        id: 'req_nav_back',
        subRequestId: 'req_nav_back',
        creatorUserId: 'creator_back',
        bandName: 'Return Band',
        role: 'Cellist',
      );
      mockService.requests.add(req);

      final appState = MockCardsAppState(mockService, activeUserId: 'creator_back');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open details
      await tester.tap(find.byKey(const ValueKey('find_gigs_manage_request_req_nav_back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SubRequestResponseDetailsScreen), findsOneWidget);

      // Tap Back button in details screen
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FindGigsScreen), findsOneWidget);
      expect(find.byType(SubRequestResponseDetailsScreen), findsNothing);
    });

    testWidgets('38. Grouped multi-position request: tapping Manage Request opens slot picker bottom sheet with individually actionable slots', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final slot1 = SubRequest(
        id: 'grp_slot_1',
        subRequestId: 'grp_slot_1',
        requestGroupId: 'common_group_1',
        creatorUserId: 'group_creator',
        bandName: 'Multi Slot Band',
        role: 'First Violin',
      );
      final slot2 = SubRequest(
        id: 'grp_slot_2',
        subRequestId: 'grp_slot_2',
        requestGroupId: 'common_group_1',
        creatorUserId: 'group_creator',
        bandName: 'Multi Slot Band',
        role: 'Second Violin',
      );
      mockService.requests.addAll([slot1, slot2]);

      final appState = MockCardsAppState(mockService, activeUserId: 'group_creator');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tapping card Manage Request opens the bottom sheet picker
      await tester.tap(find.byKey(const ValueKey('find_gigs_manage_request_grp_slot_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('details_manage_request_grp_slot_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('details_manage_request_grp_slot_2')), findsOneWidget);

      // Tapping slot 2 opens SubRequestResponseDetailsScreen targeting slot 2
      await tester.tap(find.byKey(const ValueKey('details_manage_request_grp_slot_2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SubRequestResponseDetailsScreen), findsOneWidget);
      expect(find.text('Substitute · Second Violin'), findsOneWidget);
      expect(find.text('Substitute · First Violin'), findsNothing);
    });

    // -------------------------------------------------------------
    // ASYNCHRONOUS LEADER/ADMIN AUTHORIZATION & CACHING
    // -------------------------------------------------------------
    testWidgets('41. Delayed admin check does not temporarily expose Apply (renders pending state)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.delayedAdminCompleter = Completer<bool>(); // Pending
      final gig = SubRequest(
        id: 'admin_pending_gig',
        subRequestId: 'admin_pending_gig',
        creatorUserId: 'other_creator_person',
        bandId: 'slow_auth_band',
        bandName: 'Slow Auth Band',
        role: 'Bassist',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'admin_candidate');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Neither Apply nor Manage Request must be exposed while admin check is pending
      expect(find.byKey(const ValueKey('find_gigs_apply_admin_pending_gig')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_admin_pending_gig')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_admin_pending_gig')), findsOneWidget);

      // Now resolve as admin
      mockService.delayedAdminCompleter!.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Flips to Manage Request
      expect(find.byKey(const ValueKey('find_gigs_manage_request_admin_pending_gig')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_apply_admin_pending_gig')), findsNothing);
    });

    testWidgets('42. Delayed ordinary-member check does not expose Manage Request, then resolves to Apply', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.delayedAdminCompleter = Completer<bool>(); // Pending
      final gig = SubRequest(
        id: 'member_pending_gig',
        subRequestId: 'member_pending_gig',
        creatorUserId: 'other_creator_person',
        bandId: 'member_band_check',
        bandName: 'Member Band',
        role: 'Keyboardist',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'ordinary_member');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Pending state
      expect(find.byKey(const ValueKey('find_gigs_manage_request_member_pending_gig')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_apply_member_pending_gig')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_member_pending_gig')), findsOneWidget);

      // Resolve as false (not admin)
      mockService.delayedAdminCompleter!.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Flips to Apply
      expect(find.byKey(const ValueKey('find_gigs_apply_member_pending_gig')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_member_pending_gig')), findsNothing);
    });

    testWidgets('43. Non-creator request without bandId resolves safely to Apply, not an infinite pending spinner', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final gigNoBand = SubRequest(
        id: 'gig_no_band',
        subRequestId: 'gig_no_band',
        creatorUserId: 'external_organizer',
        bandId: null, // No bandId
        bandName: 'Freelance Project',
        role: 'Drummer',
      );
      mockService.requests.add(gigNoBand);

      final appState = MockCardsAppState(mockService, activeUserId: 'applicant_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must immediately show Apply, never an infinite pending spinner
      expect(find.byKey(const ValueKey('find_gigs_apply_gig_no_band')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_gig_no_band')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_gig_no_band')), findsNothing);
    });

    testWidgets('44. Failed admin lookup shows neither Apply nor Manage Request and exposes retry action', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.shouldFailAdminLookup = true; // Simulates backend network error

      final gigFail = SubRequest(
        id: 'gig_fail_check',
        subRequestId: 'gig_fail_check',
        creatorUserId: 'someone_else',
        bandId: 'band_fail_test',
        bandName: 'Fail Check Band',
        role: 'Saxophone',
      );
      mockService.requests.add(gigFail);

      final appState = MockCardsAppState(mockService, activeUserId: 'applicant_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // After failed lookup, never grant Manage Request, never grant Apply, do not leave infinite spinner
      expect(find.byKey(const ValueKey('find_gigs_manage_request_gig_fail_check')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_apply_gig_fail_check')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_gig_fail_check')), findsNothing);

      // Exposes a neutral compact error/retry action
      final retryBtn = find.byKey(const ValueKey('find_gigs_auth_retry_gig_fail_check'));
      expect(retryBtn, findsOneWidget);
      expect(find.byTooltip('Could not verify permissions. Retry'), findsOneWidget);
    });

    testWidgets('44b. Retry can resolve to authorized and show Manage Request', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.shouldFailAdminLookup = true;

      final gigFail = SubRequest(
        id: 'gig_retry_admin',
        subRequestId: 'gig_retry_admin',
        creatorUserId: 'someone_else',
        bandId: 'band_retry_admin',
        bandName: 'Retry Admin Band',
        role: 'Trumpet',
      );
      mockService.requests.add(gigFail);

      final appState = MockCardsAppState(mockService, activeUserId: 'applicant_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_admin')), findsOneWidget);

      // Network recovers and user is confirmed as leader
      mockService.shouldFailAdminLookup = false;
      mockService.bandRoles['band_retry_admin/applicant_user'] = 'leader';

      // Tap Retry
      await tester.tap(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_admin')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Resolves to Manage Request
      expect(find.byKey(const ValueKey('find_gigs_manage_request_gig_retry_admin')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_apply_gig_retry_admin')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_admin')), findsNothing);
    });

    testWidgets('44c. Retry can resolve to unauthorized and show Apply', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.shouldFailAdminLookup = true;

      final gigFail = SubRequest(
        id: 'gig_retry_member',
        subRequestId: 'gig_retry_member',
        creatorUserId: 'someone_else',
        bandId: 'band_retry_member',
        bandName: 'Retry Member Band',
        role: 'Flute',
      );
      mockService.requests.add(gigFail);

      final appState = MockCardsAppState(mockService, activeUserId: 'applicant_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_member')), findsOneWidget);

      // Network recovers and user is ordinary member (not leader)
      mockService.shouldFailAdminLookup = false;
      mockService.bandRoles['band_retry_member/applicant_user'] = 'member';

      // Tap Retry
      await tester.tap(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_member')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Resolves to Apply
      expect(find.byKey(const ValueKey('find_gigs_apply_gig_retry_member')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_gig_retry_member')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_retry_gig_retry_member')), findsNothing);
    });

    testWidgets('44d. Repeated failures do not create concurrent duplicate calls', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.shouldFailAdminLookup = true;

      final gigFail = SubRequest(
        id: 'gig_multi_fail',
        subRequestId: 'gig_multi_fail',
        creatorUserId: 'someone_else',
        bandId: 'band_multi_fail',
        bandName: 'Multi Fail Band',
        role: 'Cello',
      );
      mockService.requests.add(gigFail);

      final appState = MockCardsAppState(mockService, activeUserId: 'applicant_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.adminLookupCalls, equals(1));

      // Tapping retry while failed invokes retry cleanly
      final retryBtn = find.byKey(const ValueKey('find_gigs_auth_retry_gig_multi_fail'));
      await tester.tap(retryBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.adminLookupCalls, equals(2));
    });

    testWidgets('45. Creator identification renders Manage Request immediately without waiting for admin check', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      // Even if admin check is delayed/unresolved:
      mockService.delayedAdminCompleter = Completer<bool>();
      final gig = SubRequest(
        id: 'creator_fast_gig',
        subRequestId: 'creator_fast_gig',
        creatorUserId: 'fast_creator_user',
        bandId: 'some_band_id',
        bandName: 'Instant Band',
        role: 'Vocalist',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'fast_creator_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();

      // Renders Manage Request immediately!
      expect(find.byKey(const ValueKey('find_gigs_manage_request_creator_fast_gig')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_creator_fast_gig')), findsNothing);
    });

    testWidgets('46. User A cached admin status is not inherited by User B (cache scoped by userId and bandId)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.bandRoles['band_alpha/user_A'] = 'leader'; // User A is leader
      mockService.bandRoles['band_alpha/user_B'] = 'member'; // User B is not leader

      final gig = SubRequest(
        id: 'band_alpha_gig',
        subRequestId: 'band_alpha_gig',
        creatorUserId: 'external_person',
        bandId: 'band_alpha',
        bandName: 'Band Alpha',
        role: 'Guitarist',
      );
      mockService.requests.add(gig);

      // Render as User A
      final appState = MockCardsAppState(mockService, activeUserId: 'user_A');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('find_gigs_manage_request_band_alpha_gig')), findsOneWidget);

      // Switch to User B (simulate re-render with new user)
      appState.activeUserId = 'user_B';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // User B must NOT inherit User A's Manage Request!
      expect(find.byKey(const ValueKey('find_gigs_apply_band_alpha_gig')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_band_alpha_gig')), findsNothing);
    });

    testWidgets('47. Multiple cards from the same band and user share one in-flight/cached lookup', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      mockService.bandRoles['band_shared/single_user'] = 'leader';

      mockService.requests.addAll([
        SubRequest(id: 'c1', subRequestId: 'c1', creatorUserId: 'someone_1', bandId: 'band_shared', bandName: 'Shared Band', role: 'Guitar'),
        SubRequest(id: 'c2', subRequestId: 'c2', creatorUserId: 'someone_2', bandId: 'band_shared', bandName: 'Shared Band', role: 'Bass'),
        SubRequest(id: 'c3', subRequestId: 'c3', creatorUserId: 'someone_3', bandId: 'band_shared', bandName: 'Shared Band', role: 'Drums'),
      ]);

      final appState = MockCardsAppState(mockService, activeUserId: 'single_user');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // All 3 cards resolve to Manage Request
      expect(find.byKey(const ValueKey('find_gigs_manage_request_c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_c3')), findsOneWidget);

      // But backend isBandLeaderOrAdminAsync was called only once for band_shared
      expect(mockService.adminLookupCalls, equals(1));
    });

    testWidgets('48. A -> B user switch discards A result', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final completerA = Completer<bool>();
      mockService.delayedAdminCompleter = completerA;

      final gig = SubRequest(
        id: 'stale_test_gig',
        subRequestId: 'stale_test_gig',
        creatorUserId: 'external_host',
        bandId: 'stale_band',
        bandName: 'Stale Band',
        role: 'Pianist',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'user_A');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // User switch occurs while check for A is in-flight!
      appState.activeUserId = 'user_B';
      mockService.delayedAdminCompleter = null;
      mockService.bandRoles['stale_band/user_B'] = 'member';
      appState.notifyListeners();

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now complete old A lookup as leader
      completerA.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // For user_B, must remain Apply and must NOT be overwritten by A's late result
      expect(find.byKey(const ValueKey('find_gigs_apply_stale_test_gig')), findsOneWidget);
      expect(find.byKey(const ValueKey('find_gigs_manage_request_stale_test_gig')), findsNothing);
    });

    testWidgets('48b. A -> B -> A user switch discards the original A result', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final completerA1 = Completer<bool>();
      mockService.delayedAdminCompleter = completerA1;

      final gig = SubRequest(
        id: 'aba_gig',
        subRequestId: 'aba_gig',
        creatorUserId: 'external_host',
        bandId: 'aba_band',
        bandName: 'ABA Band',
        role: 'Bass',
      );
      mockService.requests.add(gig);

      // Session 1: User A
      final appState = MockCardsAppState(mockService, activeUserId: 'user_A');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Session 2: User B
      appState.activeUserId = 'user_B';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Session 3: Switch back to User A (generation token incremented again!)
      final completerA2 = Completer<bool>();
      mockService.delayedAdminCompleter = completerA2;
      appState.activeUserId = 'user_A';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Complete original A1 lookup with false
      completerA1.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should still be in pending state for current A2 generation, not finalized to false by stale A1
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_aba_gig')), findsOneWidget);

      // Now complete newest A2 lookup as leader
      completerA2.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Finalizes to Manage Request
      expect(find.byKey(const ValueKey('find_gigs_manage_request_aba_gig')), findsOneWidget);
    });

    testWidgets('48c. A new A lookup is not removed by completion of the old A lookup', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final completerOld = Completer<bool>();
      mockService.delayedAdminCompleter = completerOld;

      final gig = SubRequest(
        id: 'new_lookup_gig',
        subRequestId: 'new_lookup_gig',
        creatorUserId: 'external_host',
        bandId: 'new_lookup_band',
        bandName: 'New Lookup Band',
        role: 'Oboe',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'user_A');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Trigger user reload/switch cycle
      appState.activeUserId = 'user_B';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();

      final completerNew = Completer<bool>();
      mockService.delayedAdminCompleter = completerNew;
      appState.activeUserId = 'user_A';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Completing the old lookup must NOT remove the newer in-flight entry
      completerOld.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('find_gigs_auth_pending_new_lookup_gig')), findsOneWidget);

      // Completing newer lookup succeeds
      completerNew.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('find_gigs_manage_request_new_lookup_gig')), findsOneWidget);
    });

    testWidgets('48d. Only the newest matching generation may update the card', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockCardsFirebaseService();
      final completer1 = Completer<bool>();
      mockService.delayedAdminCompleter = completer1;

      final gig = SubRequest(
        id: 'gen_match_gig',
        subRequestId: 'gen_match_gig',
        creatorUserId: 'external_host',
        bandId: 'gen_band',
        bandName: 'Gen Band',
        role: 'Harp',
      );
      mockService.requests.add(gig);

      final appState = MockCardsAppState(mockService, activeUserId: 'user_A');
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();

      // Cycle to generation 2 with its own independent completer
      final completer2 = Completer<bool>();
      mockService.delayedAdminCompleter = completer2;
      appState.activeUserId = 'user_B';
      appState.notifyListeners();
      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();

      // Completer 1 from generation 1 resolves as true
      completer1.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Old generation 1 result must NOT update generation 2 card (remains pending on completer2)
      expect(find.byKey(const ValueKey('find_gigs_manage_request_gen_match_gig')), findsNothing);
      expect(find.byKey(const ValueKey('find_gigs_auth_pending_gen_match_gig')), findsOneWidget);

      // Now complete generation 2 as false (member)
      completer2.complete(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('find_gigs_apply_gen_match_gig')), findsOneWidget);
    });

    // -------------------------------------------------------------
    // PAYMENT AMOUNT FORMAT AUDIT
    // -------------------------------------------------------------
    test('49. Formats explicit SEK as Paid · 1,500 SEK without decimals or trailing zeros', () {
      final req = SubRequest(
        id: 'pay_fmt_1',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
      );
      expect(formatSubRequestPaymentDisplay(req), equals('Paid · 1,500 SEK'));
    });

    test('50. Formats explicit non-SEK currency as Paid · 1,500 EUR', () {
      final reqEur = SubRequest(
        id: 'pay_fmt_2a',
        isPaid: true,
        payAmount: 1500,
        currency: 'EUR',
      );
      expect(formatSubRequestPaymentDisplay(reqEur), equals('Paid · 1,500 EUR'));

      final reqUsd = SubRequest(
        id: 'pay_fmt_2b',
        isPaid: true,
        payAmount: 1500,
        currency: 'USD',
      );
      expect(formatSubRequestPaymentDisplay(reqUsd), equals('Paid · 1,500 USD'));
    });

    test('51. Formats missing currency as Paid · 1,500 without an invented currency', () {
      final req = SubRequest(
        id: 'pay_fmt_3',
        isPaid: true,
        payAmount: 1500,
        currency: null,
      );
      expect(formatSubRequestPaymentDisplay(req), equals('Paid · 1,500'));
      expect(formatSubRequestPaymentDisplay(req), isNot(contains('null')));
      expect(formatSubRequestPaymentDisplay(req), isNot(contains('SEK')));
    });

    test('52. Formats malformed currency as Paid · 1,500 without rendering invalid code', () {
      final reqNumber = SubRequest(
        id: 'pay_fmt_4a',
        isPaid: true,
        payAmount: 1500,
        currency: '123',
      );
      expect(formatSubRequestPaymentDisplay(reqNumber), equals('Paid · 1,500'));

      final reqStringNull = SubRequest(
        id: 'pay_fmt_4b',
        isPaid: true,
        payAmount: 1500,
        currency: 'null',
      );
      expect(formatSubRequestPaymentDisplay(reqStringNull), equals('Paid · 1,500'));

      final reqSpecial = SubRequest(
        id: 'pay_fmt_4c',
        isPaid: true,
        payAmount: 1500,
        currency: '!@#',
      );
      expect(formatSubRequestPaymentDisplay(reqSpecial), equals('Paid · 1,500'));
    });

    test('53. Paid without amount displays Paid without empty separator', () {
      final req = SubRequest(
        id: 'pay_fmt_5a',
        isPaid: true,
        payAmount: 0,
        currency: 'SEK',
      );
      expect(formatSubRequestPaymentDisplay(req), equals('Paid'));

      final reqNull = SubRequest(
        id: 'pay_fmt_5b',
        isPaid: true,
      );
      expect(formatSubRequestPaymentDisplay(reqNull), equals('Paid'));
    });

    test('54. Unpaid request renders no paid text and omits payment line', () {
      final req = SubRequest(
        id: 'pay_fmt_6',
        isPaid: false,
        payAmount: 1500,
      );
      expect(formatSubRequestPaymentDisplay(req), isNull);
    });

    test('55. Formats decimal amount as Paid · 1,500.50 SEK when genuinely needed', () {
      final req = SubRequest(
        id: 'pay_fmt_7',
        isPaid: true,
        payAmountMinor: 150050,
        currency: 'SEK',
      );
      expect(formatSubRequestPaymentDisplay(req), equals('Paid · 1,500.50 SEK'));
    });

    test('56. Legacy numeric and string formats (int, double, extraFields) format cleanly into approved English style', () {
      final reqMinor = SubRequest(
        id: 'pay_fmt_8',
        isPaid: true,
        payAmountMinor: 150000,
        currency: 'SEK',
      );
      expect(formatSubRequestPaymentDisplay(reqMinor), equals('Paid · 1,500 SEK'));

      final reqExtra = SubRequest(
        id: 'pay_fmt_9',
        isPaid: true,
        extraFields: {'payAmount': '2200', 'currency': 'EUR'},
      );
      expect(formatSubRequestPaymentDisplay(reqExtra), equals('Paid · 2,200 EUR'));
    });
  });
}
