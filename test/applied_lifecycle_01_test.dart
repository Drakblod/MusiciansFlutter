import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/utils/sub_request_card_helper.dart';

class MockLifecycleFirebaseService extends FirebaseService {
  List<SubRequest> feedRequests = [];
  Set<String> appliedIds = {};
  int rtdbWriteCount = 0;
  bool rootSubRequestsListenerAttached = false;
  Completer<List<SubRequest>>? delayedFeedCompleter;

  @override
  String? get currentUserId => 'user_musician_1';

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    if (delayedFeedCompleter != null) {
      return delayedFeedCompleter!.future;
    }
    return List.from(feedRequests);
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async {
    return Set.from(appliedIds);
  }

  @override
  Future<bool> isBandLeaderOrAdminAsync(String bandId, String userId) async {
    return false;
  }

  @override
  Future<void> addResponseToSubRequestAsync(String subRequestId, String userId) async {
    rtdbWriteCount++;
    appliedIds.add(subRequestId);
    for (final r in feedRequests) {
      if ((r.subRequestId ?? r.id) == subRequestId) {
        r.responses[userId] = true;
      }
    }
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: userId ?? 'user_musician_1',
      displayName: 'Musician 1',
      instruments: const ['Guitar', 'Bass', 'Drums', 'Tenor Saxophone'],
    );
  }
}

class MockLifecycleAppState extends AppState {
  final MockLifecycleFirebaseService mockService;
  String? activeUserId;
  UserProfile? activeProfile;

  MockLifecycleAppState(this.mockService, {this.activeUserId = 'user_musician_1'}) {
    activeProfile = UserProfile(
      userId: activeUserId,
      displayName: 'Musician $activeUserId',
      instruments: const ['Guitar', 'Bass', 'Drums', 'Tenor Saxophone'],
    );
  }

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => activeProfile;

  @override
  String? get currentUserId => activeUserId;

  void switchUser(String? newUserId) {
    clearSessionAppliedSubRequestsForTest();
    activeUserId = newUserId;
    if (newUserId != null) {
      activeProfile = UserProfile(
        userId: newUserId,
        displayName: 'Musician $newUserId',
        instruments: const ['Guitar', 'Bass', 'Drums', 'Tenor Saxophone'],
      );
    } else {
      activeProfile = null;
    }
    notifyListeners();
  }
}

Widget createTestApp({
  required Widget child,
  required MockLifecycleAppState appState,
  Size size = const Size(800, 2400),
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
  });

  group('Pure Lifecycle Policy - isActiveAppliedRequest', () {
    final fixedNow = DateTime(2026, 11, 2, 14, 0); // Mon Nov 2, 2026 at 14:00

    test('1. Future published Substitute application is visible', () {
      final req = SubRequest(
        subRequestId: 'req_future',
        bandName: 'Future Band',
        role: 'Guitar',
        date: '2026-11-10',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isTrue);
    });

    test('2. Current published Substitute before end time is visible', () {
      final req = SubRequest(
        subRequestId: 'req_today_active',
        bandName: 'Current Band',
        role: 'Bass',
        date: '2026-11-02',
        startTime: '12:00',
        endTime: '18:00',
        status: 'published',
        responses: {'u1': true},
      );
      // fixedNow is 14:00, before 18:00
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isTrue);
    });

    test('3. Exact end boundary is absent', () {
      final req = SubRequest(
        subRequestId: 'req_exact_end',
        bandName: 'Exact Band',
        role: 'Bass',
        date: '2026-11-02',
        startTime: '10:00',
        endTime: '14:00',
        status: 'published',
        responses: {'u1': true},
      );
      // fixedNow is exactly 14:00:00
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('4. Past Substitute is absent', () {
      final req = SubRequest(
        subRequestId: 'req_past',
        bandName: 'Old Band',
        role: 'Drums',
        date: '2026-10-15',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('5. Past request with missing end time is absent after the end of its calendar date (next day 00:00)', () {
      final req = SubRequest(
        subRequestId: 'req_no_end',
        bandName: 'Yesterday Band',
        role: 'Guitar',
        date: '2026-11-01', // yesterday
        status: 'published',
        responses: {'u1': true},
      );
      // boundary is 2026-11-02 00:00:00; fixedNow is 2026-11-02 14:00
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);

      // On the same day (e.g. 2026-11-02 23:59:59), a 2026-11-02 request with no end time remains visible
      final todayReq = SubRequest(
        subRequestId: 'req_today_no_end',
        bandName: 'Today Band',
        role: 'Guitar',
        date: '2026-11-02',
        status: 'published',
        responses: {'u1': true},
      );
      final beforeMidnight = DateTime(2026, 11, 2, 23, 59, 59, 999);
      final exactMidnight = DateTime(2026, 11, 3, 0, 0, 0, 0);
      expect(isActiveAppliedRequest(todayReq, currentUserId: 'u1', now: beforeMidnight), isTrue);
      expect(isActiveAppliedRequest(todayReq, currentUserId: 'u1', now: exactMidnight), isFalse);
    });

    test('6. Cancelled request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_cancelled',
        bandName: 'Cancelled Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'cancelled',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('7. Canceled legacy spelling is absent', () {
      final req = SubRequest(
        subRequestId: 'req_canceled',
        bandName: 'Canceled Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'canceled',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('8. Deleted request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_deleted',
        bandName: 'Deleted Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'deleted',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('9. Closed request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_closed',
        bandName: 'Closed Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'closed',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('10. Archived request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_archived',
        bandName: 'Archived Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'archived',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('11. Filled request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_filled',
        bandName: 'Filled Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'filled',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('12. Assigned-to-current-user request is absent from Applied', () {
      final req = SubRequest(
        subRequestId: 'req_assigned_self',
        bandName: 'Assigned Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'assigned',
        assignedUserId: 'u1',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('13. Assigned-to-another-user request is absent', () {
      final req = SubRequest(
        subRequestId: 'req_assigned_other',
        bandName: 'Assigned Other Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'assigned',
        assignedUserId: 'other_user',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('13b. AssignedUserId null, empty or whitespace vs real assignedUserId and assigned status', () {
      // 1. status published + assignedUserId null -> active when otherwise eligible
      final reqNull = SubRequest(
        subRequestId: 'req_assign_null',
        bandName: 'Band Null',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
        assignedUserId: null,
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqNull, currentUserId: 'u1', now: fixedNow), isTrue);

      // 2. status published + assignedUserId empty -> active when otherwise eligible
      final reqEmpty = SubRequest(
        subRequestId: 'req_assign_empty',
        bandName: 'Band Empty',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
        assignedUserId: '',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqEmpty, currentUserId: 'u1', now: fixedNow), isTrue);

      // 3. status published + assignedUserId whitespace -> active when otherwise eligible
      final reqWhitespace = SubRequest(
        subRequestId: 'req_assign_whitespace',
        bandName: 'Band Whitespace',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
        assignedUserId: '   	  ',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqWhitespace, currentUserId: 'u1', now: fixedNow), isTrue);

      // 4. status published + real assignedUserId -> absent
      final reqRealAssigned = SubRequest(
        subRequestId: 'req_assign_real',
        bandName: 'Band Real',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
        assignedUserId: 'other_user_123',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqRealAssigned, currentUserId: 'u1', now: fixedNow), isFalse);

      // 5. status assigned + no assignedUserId -> absent
      final reqStatusAssignedNoId = SubRequest(
        subRequestId: 'req_assign_status_only',
        bandName: 'Band Status Only',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'assigned',
        assignedUserId: null,
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqStatusAssignedNoId, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('14. New Band Member without a date remains visible while published', () {
      final req = SubRequest(
        subRequestId: 'req_nbm_open',
        bandName: 'Recruiting Band',
        role: 'New Member',
        requestType: 'New Member',
        status: 'published',
        responses: {'u1': true},
      );
      expect(req.isNewMember, isTrue);
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isTrue);
    });

    test('15. Closed New Band Member without a date is absent', () {
      final req = SubRequest(
        subRequestId: 'req_nbm_closed',
        bandName: 'Recruiting Band',
        role: 'New Member',
        requestType: 'New Member',
        status: 'closed',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('16. Malformed date does not crash and falls back to active status', () {
      final req = SubRequest(
        subRequestId: 'req_malformed_date',
        bandName: 'Weird Date Band',
        role: 'Guitar',
        date: 'not-a-valid-date',
        status: 'published',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isTrue);
    });

    test('17. Missing date on legacy Substitute does not crash and falls back to active status', () {
      final req = SubRequest(
        subRequestId: 'req_no_date_sub',
        bandName: 'No Date Band',
        role: 'Guitar',
        date: null,
        status: 'published',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: fixedNow), isTrue);
    });

    test('Midnight-crossing time ranges: before midnight, after midnight, exact end, after end', () {
      // Event on Nov 2 from 22:00 to 02:00 (crosses midnight into Nov 3)
      final req = SubRequest(
        subRequestId: 'req_midnight',
        bandName: 'Night Owls',
        role: 'Drums',
        date: '2026-11-02',
        startTime: '22:00',
        endTime: '02:00',
        status: 'published',
        responses: {'u1': true},
      );

      final beforeMidnight = DateTime(2026, 11, 2, 23, 30);
      final afterMidnightBeforeEnd = DateTime(2026, 11, 3, 1, 30);
      final exactEnd = DateTime(2026, 11, 3, 2, 0);
      final immediatelyAfterEnd = DateTime(2026, 11, 3, 2, 0, 1);

      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: beforeMidnight), isTrue);
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: afterMidnightBeforeEnd), isTrue);
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: exactEnd), isFalse);
      expect(isActiveAppliedRequest(req, currentUserId: 'u1', now: immediatelyAfterEnd), isFalse);
    });

    test('Unknown or empty status is conservatively absent without mutating record', () {
      final reqUnknown = SubRequest(
        subRequestId: 'req_unknown',
        bandName: 'Unknown Status Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'custom_weird_status',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqUnknown, currentUserId: 'u1', now: fixedNow), isFalse);

      final reqEmpty = SubRequest(
        subRequestId: 'req_empty',
        bandName: 'Empty Status Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: '',
        responses: {'u1': true},
      );
      expect(isActiveAppliedRequest(reqEmpty, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('18. Two slots in one request group remain isolated by subRequestId', () {
      final slotA = SubRequest(
        subRequestId: 'slot_A',
        requestGroupId: 'group_fest',
        bandName: 'Festival Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
        responses: {'u1': true}, // User 1 applied
      );
      final slotB = SubRequest(
        subRequestId: 'slot_B',
        requestGroupId: 'group_fest',
        bandName: 'Festival Band',
        role: 'Bass',
        date: '2026-11-20',
        status: 'published',
        responses: {}, // User 1 did NOT apply
      );

      expect(isActiveAppliedRequest(slotA, currentUserId: 'u1', now: fixedNow), isTrue);
      expect(isActiveAppliedRequest(slotB, currentUserId: 'u1', now: fixedNow), isFalse);
    });

    test('19. Applying to one slot does not mark the sibling slot as Applied', () {
      final slotA = SubRequest(
        subRequestId: 'slot_A',
        requestGroupId: 'group_fest',
        bandName: 'Festival Band',
        role: 'Guitar',
        date: '2026-11-20',
        status: 'published',
      );
      final slotB = SubRequest(
        subRequestId: 'slot_B',
        requestGroupId: 'group_fest',
        bandName: 'Festival Band',
        role: 'Bass',
        date: '2026-11-20',
        status: 'published',
      );

      final appliedIds = {'slot_A'};
      expect(isActiveAppliedRequest(slotA, currentUserId: 'u1', now: fixedNow, appliedIds: appliedIds), isTrue);
      expect(isActiveAppliedRequest(slotB, currentUserId: 'u1', now: fixedNow, appliedIds: appliedIds), isFalse);
    });
  });

  group('FindGigsScreen Applied Tab Widget & Pipeline Tests', () {
    late MockLifecycleFirebaseService mockService;
    late MockLifecycleAppState appState;

    setUp(() {
      mockService = MockLifecycleFirebaseService();
      appState = MockLifecycleAppState(mockService, activeUserId: 'u_tester');
    });

    testWidgets('Active future application appears under Applied tab', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final futureReq = SubRequest(
        subRequestId: 'sub_future_1',
        requestGroupId: 'grp_future_1',
        bandName: 'The Starlight Band',
        role: 'Guitar',
        date: '2026-12-15',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {'u_tester': true},
      );
      mockService.feedRequests = [futureReq];
      mockService.appliedIds = {'sub_future_1'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on Tab 3: Applied
      final tabs = find.byType(Tab);
      await tester.tap(tabs.at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('The Starlight Band'), findsWidgets);
      expect(find.text('Substitute · Guitar'), findsWidgets);
    });

    testWidgets('July and October expired applications do NOT appear under Applied tab', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final julyReq = SubRequest(
        subRequestId: 'sub_july_1',
        requestGroupId: 'grp_july_1',
        bandName: 'Summer Fest 2026',
        role: 'Guitar',
        date: '2026-07-15',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {'u_tester': true},
      );
      final octReq = SubRequest(
        subRequestId: 'sub_oct_1',
        requestGroupId: 'grp_oct_1',
        bandName: 'Autumn Groove 2026',
        role: 'Bass',
        date: '2026-10-15',
        startTime: '18:00',
        endTime: '21:00',
        status: 'published',
        responses: {'u_tester': true},
      );
      final activeReq = SubRequest(
        subRequestId: 'sub_future_ok',
        requestGroupId: 'grp_future_ok',
        bandName: 'Winter Concert',
        role: 'Drums',
        date: '2026-12-20',
        startTime: '20:00',
        endTime: '23:00',
        status: 'published',
        responses: {'u_tester': true},
      );

      mockService.feedRequests = [julyReq, octReq, activeReq];
      mockService.appliedIds = {'sub_july_1', 'sub_oct_1', 'sub_future_ok'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Summer Fest 2026'), findsNothing);
      expect(find.text('Autumn Groove 2026'), findsNothing);
      expect(find.text('Winter Concert'), findsWidgets);
    });

    testWidgets('Cancelled, closed, and filled applications do NOT appear under Applied', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cancelledReq = SubRequest(
        subRequestId: 'sub_cancelled',
        bandName: 'Cancelled Fest',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'cancelled',
        responses: {'u_tester': true},
      );
      final closedReq = SubRequest(
        subRequestId: 'sub_closed',
        bandName: 'Closed Gig',
        role: 'Bass',
        date: '2026-12-10',
        status: 'closed',
        responses: {'u_tester': true},
      );
      final filledReq = SubRequest(
        subRequestId: 'sub_filled',
        bandName: 'Filled Gig',
        role: 'Drums',
        date: '2026-12-10',
        status: 'filled',
        responses: {'u_tester': true},
      );

      mockService.feedRequests = [cancelledReq, closedReq, filledReq];
      mockService.appliedIds = {'sub_cancelled', 'sub_closed', 'sub_filled'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cancelled Fest'), findsNothing);
      expect(find.text('Closed Gig'), findsNothing);
      expect(find.text('Filled Gig'), findsNothing);
      expect(find.text('No gigs in this list.'), findsOneWidget);
    });

    testWidgets('Multi-position group isolation: Slot A appears, Slot B does not, no (+1)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final slotA = SubRequest(
        subRequestId: 'slot_guitar',
        requestGroupId: 'grp_multi_1',
        bandName: 'Brass & Strings',
        role: 'Guitar',
        date: '2026-12-15',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {'u_tester': true}, // User applied
      );
      final slotB = SubRequest(
        subRequestId: 'slot_drums',
        requestGroupId: 'grp_multi_1',
        bandName: 'Brass & Strings',
        role: 'Drums',
        date: '2026-12-15',
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
        responses: {}, // User did NOT apply
      );

      mockService.feedRequests = [slotA, slotB];
      mockService.appliedIds = {'slot_guitar'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check Substitute Requests tab: group has 2 positions and shows Guitar (+1)
      expect(find.text('Brass & Strings'), findsWidgets);
      expect(find.text('Substitute · Guitar (+1)'), findsOneWidget);

      // Switch to Applied tab
      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // In Applied tab: group contains ONLY Slot A (Guitar). Must NOT show (+1)
      expect(find.text('Brass & Strings'), findsWidgets);
      expect(find.text('Substitute · Guitar'), findsOneWidget);
      expect(find.text('Substitute · Guitar (+1)'), findsNothing); // Offstage on Tab 1, not on Applied tab

      // Tap card in Applied tab
      await tester.tap(find.text('Brass & Strings').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Bottom sheet in Applied tab must list Guitar as Applied, and MUST NOT list Drums
      expect(find.text('Guitar'), findsWidgets);
      expect(find.text('Drums'), findsNothing);
    });

    testWidgets('20. Duplicate public/private feed copies produce one visible item', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final reqPub = SubRequest(
        subRequestId: 'dup_req_1',
        bandName: 'Duplicate Test Band',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'u_tester': true},
      );
      final reqFeed = SubRequest(
        subRequestId: 'dup_req_1',
        bandName: 'Duplicate Test Band',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'u_tester': true},
      );

      mockService.feedRequests = [reqPub, reqFeed];
      mockService.appliedIds = {'dup_req_1'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Duplicate Test Band'), findsWidgets);
    });

    testWidgets('21 & 22. Deleted or revoked projection disappears after refresh', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final req1 = SubRequest(
        subRequestId: 'revokable_req',
        bandName: 'Private Secret Gig',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'u_tester': true},
      );

      mockService.feedRequests = [req1];
      mockService.appliedIds = {'revokable_req'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Private Secret Gig'), findsWidgets);

      // Now feed authorization is revoked / record is deleted from feed
      mockService.feedRequests = [];

      // Re-trigger load by re-notifying app state dependency
      appState.switchUser('u_tester_refreshed');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Private Secret Gig'), findsNothing);
      expect(find.text('No gigs in this list.'), findsOneWidget);
    });

    testWidgets('23 & 24. Logout and user switch clear Applied state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final reqA = SubRequest(
        subRequestId: 'req_user_a',
        bandName: 'Band of User A',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'user_A': true},
      );

      mockService.feedRequests = [reqA];
      mockService.appliedIds = {'req_user_a'};
      appState.switchUser('user_A');

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Band of User A'), findsWidgets);

      // Switch to User B (who has applied to nothing)
      mockService.appliedIds = {};
      appState.switchUser('user_B');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // User B has no applied gigs -> Applied tab shows empty state
      expect(find.text('No gigs in this list.'), findsOneWidget);

      // Log out completely
      appState.switchUser(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No gigs in this list.'), findsOneWidget);
    });

    testWidgets('25. A -> B -> A switch rejects stale asynchronous results', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final reqA = SubRequest(
        subRequestId: 'req_a_fresh',
        bandName: 'Fresh Band A',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'user_A': true},
      );
      final reqStale = SubRequest(
        subRequestId: 'req_a_stale',
        bandName: 'STALE GHOST BAND',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'user_A': true},
      );

      appState.switchUser('user_A');
      mockService.appliedIds = {'req_a_fresh', 'req_a_stale'};

      // 1. Initial load for A with delayed completer
      final completer1 = Completer<List<SubRequest>>();
      mockService.delayedFeedCompleter = completer1;

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump(); // starts load 1

      // 2. Switch to User B
      mockService.delayedFeedCompleter = null;
      mockService.feedRequests = [];
      appState.switchUser('user_B');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Switch back to User A
      mockService.feedRequests = [reqA];
      appState.switchUser('user_A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 4. Resolve the stale completer 1 with STALE GHOST BAND
      completer1.complete([reqStale]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Stale ghost band must have been discarded due to generation token
      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('STALE GHOST BAND'), findsNothing);
      expect(find.text('Fresh Band A'), findsWidgets);
    });

    testWidgets('26. 320 px viewport has no overflow on Applied tab', (tester) async {
      final req = SubRequest(
        subRequestId: 'narrow_req',
        bandName: 'A Very Long Symphony Orchestra Name For Testing',
        role: 'First Chair Lead Alto Saxophone',
        date: '2026-12-10',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Stockholm Concert Hall, Big Stage',
        description: 'Comprehensive detailed note for this audition performance.',
        isPaid: true,
        payAmount: 2500,
        currency: 'SEK',
        status: 'published',
        responses: {'u_tester': true},
      );
      mockService.feedRequests = [req];
      mockService.appliedIds = {'narrow_req'};

      await tester.pumpWidget(createTestApp(
        child: const FindGigsScreen(),
        appState: appState,
        size: const Size(320, 800),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify no overflow error occurred
      expect(tester.takeException(), isNull);
      expect(find.text('A Very Long Symphony Orchestra Name For Testing'), findsWidgets);
    });

    testWidgets('27. Empty Applied state appears when all applications are inactive', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final expiredReq = SubRequest(
        subRequestId: 'old_req',
        bandName: 'Past Gig',
        role: 'Guitar',
        date: '2026-05-01',
        status: 'published',
        responses: {'u_tester': true},
      );
      mockService.feedRequests = [expiredReq];
      mockService.appliedIds = {'old_req'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No gigs in this list.'), findsOneWidget);
    });

    testWidgets('28 & 29. Filtering performs zero RTDB writes and introduces no root listener', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      mockService.rtdbWriteCount = 0;
      mockService.rootSubRequestsListenerAttached = false;

      final req = SubRequest(
        subRequestId: 'safe_req',
        bandName: 'Safe Band',
        role: 'Guitar',
        date: '2026-12-10',
        status: 'published',
        responses: {'u_tester': true},
      );
      mockService.feedRequests = [req];
      mockService.appliedIds = {'safe_req'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.rtdbWriteCount, 0);
      expect(mockService.rootSubRequestsListenerAttached, isFalse);
    });

    testWidgets('30. Full-field presentation from 2.79.1 remains intact under Applied', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final req = SubRequest(
        subRequestId: 'full_field_req',
        bandName: 'The Jazz Messengers',
        role: 'Tenor Saxophone',
        requestType: 'Substitute',
        eventType: 'Corporate Event',
        date: '2026-12-25',
        startTime: '18:00',
        endTime: '22:00',
        location: 'Grand Hotel, Stockholm',
        description: 'Black tie corporate gala event. Full chart reading required.',
        isPaid: true,
        payAmount: 3500,
        currency: 'SEK',
        payDetails: 'Includes dinner and travel reimbursement',
        status: 'published',
        responses: {'u_tester': true},
      );
      mockService.feedRequests = [req];
      mockService.appliedIds = {'full_field_req'};

      await tester.pumpWidget(createTestApp(child: const FindGigsScreen(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Tab).at(2)); await tester.pump(); await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Band Name
      expect(find.text('The Jazz Messengers'), findsWidgets);
      // Request Type · Role
      expect(find.text('Substitute · Tenor Saxophone'), findsWidgets);
      // Event Type · Paid line
      expect(find.text('Corporate Event · Paid · 3,500 SEK'), findsWidgets);
      // Date and time line (Dec 25 2026 is Fri)
      expect(find.text('Fri, Dec 25 · 18.00–22.00'), findsWidgets);
      // Location
      expect(find.text('Grand Hotel, Stockholm'), findsWidgets);

      await tester.tap(find.text('The Jazz Messengers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Description and Pay Details in details sheet
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text('Black tie corporate gala event. Full chart reading required.'), findsOneWidget);
      expect(find.text('Includes dinner and travel reimbursement'), findsOneWidget);
    });
  });
}
