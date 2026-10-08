import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';

class MockFindGigsFirebaseService extends FirebaseService {
  List<SubRequest> storedRequests = [];

  @override
  String? get currentUserId => 'test_musician_1';

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    return storedRequests;
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return storedRequests;
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async {
    return {};
  }
}

class MockFindGigsAppState extends AppState {
  final MockFindGigsFirebaseService mockFirebase;
  UserProfile? testUserProfile;
  String? testUserId;

  MockFindGigsAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => testUserProfile;

  @override
  String? get currentUserId => testUserId ?? 'test_musician_1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  testWidgets('FindGigsScreen displays Electric Guitar subrequest for Guitarist user', (WidgetTester tester) async {
    final mockFirebase = MockFindGigsFirebaseService();
    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

    mockFirebase.storedRequests = [
      SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        bandName: 'The Rockers',
        voicePart: 'Electric Guitar',
        date: dateStr,
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm',
        isPaid: true,
        payAmount: 2000,
        currency: 'SEK',
      ),
      SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        bandName: '', // Freelance gig without band name
        eventTitle: 'Studio Session Guitarist',
        voicePart: 'Guitar',
        date: dateStr,
        startTime: '14:00',
        endTime: '18:00',
        location: 'Gothenburg',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
      ),
      SubRequest(
        id: 'sub_3',
        subRequestId: 'sub_3',
        bandName: 'Brass Ensemble',
        voicePart: 'Trumpet',
        date: dateStr,
        startTime: '18:00',
        endTime: '20:00',
        location: 'Malmö',
      ),
    ];

    final appState = MockFindGigsAppState(mockFirebase);
    appState.testUserId = 'test_musician_1';
    appState.testUserProfile = UserProfile(
      userId: 'test_musician_1',
      displayName: 'Alex Guitarist',
      instruments: ['Electric Guitar'],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindGigsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify "The Rockers" and "Studio Session Guitarist" are visible
    expect(find.text('The Rockers'), findsOneWidget);
    expect(find.text('Studio Session Guitarist'), findsOneWidget);

    // Verify Trumpet gig is not in the live feed for Electric Guitarist
    expect(find.text('Brass Ensemble'), findsNothing);
  });

  testWidgets('FindGigsScreen displays all gigs if user has no instruments set', (WidgetTester tester) async {
    final mockFirebase = MockFindGigsFirebaseService();
    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

    mockFirebase.storedRequests = [
      SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        bandName: 'The Rockers',
        voicePart: 'Electric Guitar',
        date: dateStr,
        location: 'Stockholm',
      ),
    ];

    final appState = MockFindGigsAppState(mockFirebase);
    appState.testUserId = 'test_musician_2';
    appState.testUserProfile = UserProfile(
      userId: 'test_musician_2',
      displayName: 'New Musician',
      instruments: [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindGigsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('The Rockers'), findsOneWidget);
  });

  testWidgets('FindGigsScreen displays today gig with ISO string for user with mainInstrument', (WidgetTester tester) async {
    final mockFirebase = MockFindGigsFirebaseService();
    final todayIso = DateTime.now().toIso8601String();

    mockFirebase.storedRequests = [
      SubRequest(
        id: 'sub_today',
        subRequestId: 'sub_today',
        bandName: 'Electric Groove',
        voicePart: 'Electric Guitar',
        date: todayIso,
        startTime: '20:00',
        endTime: '23:00',
        location: 'Stockholm',
      ),
    ];

    final appState = MockFindGigsAppState(mockFirebase);
    appState.testUserId = 'test_musician_3';
    appState.testUserProfile = UserProfile(
      userId: 'test_musician_3',
      userType: 'Musician',
      mainInstrument: 'Electric Guitar',
      instruments: ['Electric Guitar'],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindGigsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Electric Groove'), findsOneWidget);
  });

  testWidgets('FindGigsScreen filters out cancelled and deleted gigs', (WidgetTester tester) async {
    final mockFirebase = MockFindGigsFirebaseService();
    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

    mockFirebase.storedRequests = [
      SubRequest(
        id: 'sub_active',
        subRequestId: 'sub_active',
        bandName: 'Active Rockers',
        voicePart: 'Electric Guitar',
        date: dateStr,
        status: 'published',
      ),
      SubRequest(
        id: 'sub_cancelled',
        subRequestId: 'sub_cancelled',
        bandName: 'Cancelled Band',
        voicePart: 'Electric Guitar',
        date: dateStr,
        status: 'cancelled',
      ),
      SubRequest(
        id: 'sub_deleted',
        subRequestId: 'sub_deleted',
        bandName: 'Deleted Band',
        voicePart: 'Electric Guitar',
        date: dateStr,
        status: 'deleted',
      ),
    ];

    final appState = MockFindGigsAppState(mockFirebase);
    appState.testUserId = 'test_musician_4';
    appState.testUserProfile = UserProfile(
      userId: 'test_musician_4',
      displayName: 'Electric Player',
      instruments: ['Electric Guitar'],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindGigsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Active Rockers'), findsOneWidget);
    expect(find.text('Cancelled Band'), findsNothing);
    expect(find.text('Deleted Band'), findsNothing);
  });

  group('FIND-GIGS-01A Specification Verification', () {
    testWidgets('1. Tabs are exactly Substitute Requests, New Member Requests, and Saved', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final appState = MockFindGigsAppState(mockFirebase);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Substitute Requests'), findsOneWidget);
      expect(find.text('New Member Requests'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Available gigs'), findsNothing);
      expect(find.text('Direct Invitations'), findsNothing);
    });

    testWidgets('2 & 3. Substitute and New Member classification and Direct Invitations without duplicates', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_sub_1',
          subRequestId: 'sub_sub_1',
          bandName: 'Rock Band Sub',
          role: 'Substitute',
          voicePart: 'Electric Guitar',
          date: dateStr,
          targetUserIds: ['test_musician_1'], // Direct invite
        ),
        SubRequest(
          id: 'sub_member_1',
          subRequestId: 'sub_member_1',
          bandName: 'Jazz Band Member',
          role: 'New Member',
          voicePart: 'Trumpet',
          date: dateStr,
          targetUserIds: ['test_musician_1'], // Direct invite
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(
        userId: 'test_musician_1',
        instruments: ['Electric Guitar', 'Trumpet'],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On Substitute Requests tab (first tab)
      expect(find.text('Rock Band Sub'), findsOneWidget);
      expect(find.text('Substitute Request'), findsOneWidget);
      expect(find.text('Jazz Band Member'), findsNothing);
      expect(find.text('Direct Invite'), findsOneWidget);

      // Switch to New Member Requests tab
      await tester.tap(find.text('New Member Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Jazz Band Member'), findsOneWidget);
      expect(find.text('New Member Request'), findsOneWidget);
      expect(find.text('Rock Band Sub'), findsNothing);
      expect(find.text('Direct Invite'), findsOneWidget);
    });

    testWidgets('2b. New Member classification is case-insensitive and whitespace-tolerant', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_nm_exact',
          subRequestId: 'sub_nm_exact',
          bandName: 'Band Exact NM',
          role: 'New Member',
          voicePart: 'Bass',
          date: dateStr,
        ),
        SubRequest(
          id: 'sub_nm_lower',
          subRequestId: 'sub_nm_lower',
          bandName: 'Band Lower NM',
          role: 'new member',
          voicePart: 'Keys',
          date: dateStr,
        ),
        SubRequest(
          id: 'sub_nm_spaces',
          subRequestId: 'sub_nm_spaces',
          bandName: 'Band Spaced NM',
          role: '  New Member  ',
          voicePart: 'Drums',
          date: dateStr,
        ),
        SubRequest(
          id: 'sub_normal_sub',
          subRequestId: 'sub_normal_sub',
          bandName: 'Band Standard Sub',
          role: 'Substitute',
          voicePart: 'Guitar',
          date: dateStr,
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(
        userId: 'test_musician_1',
        instruments: [],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On Substitute Requests tab: only standard sub is present
      expect(find.text('Band Standard Sub'), findsOneWidget);
      expect(find.text('Band Exact NM'), findsNothing);
      expect(find.text('Band Lower NM'), findsNothing);
      expect(find.text('Band Spaced NM'), findsNothing);

      // Switch to New Member Requests tab
      await tester.tap(find.text('New Member Requests'));
      await tester.pumpAndSettle();

      // All 3 variations are classified under New Member Requests
      expect(find.text('Band Exact NM'), findsOneWidget);
      expect(find.text('Band Lower NM'), findsOneWidget);
      expect(find.text('Band Spaced NM'), findsOneWidget);
      expect(find.text('Band Standard Sub'), findsNothing);

      // Verify each shows the New Member Request label
      expect(find.text('New Member Request'), findsNWidgets(3));
    });

    testWidgets('4 & 5. Single grouped request does not show 1 event · 1 position and shows Role / Instrument', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_single_grouped',
          subRequestId: 'sub_single_grouped',
          bandName: 'Single Grouped Band',
          role: 'Substitute',
          voicePart: 'Tenor Sax',
          date: dateStr,
          requestGroupId: 'req_grp_single_123',
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(userId: 'test_musician_1', instruments: []);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Single Grouped Band'), findsOneWidget);
      expect(find.text('Tenor Sax'), findsOneWidget);
      expect(find.textContaining('1 event'), findsNothing);
      expect(find.textContaining('1 position'), findsNothing);
    });

    testWidgets('6. Details sheet hides Event #1 for single event but retains numbering for two events', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dayAfter = DateTime.now().add(const Duration(days: 3));
      final dateStr1 = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
      final dateStr2 = "${dayAfter.year}-${dayAfter.month.toString().padLeft(2, '0')}-${dayAfter.day.toString().padLeft(2, '0')}";

      // Single event test
      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_single_ev',
          subRequestId: 'sub_single_ev',
          bandName: 'Solo Event Band',
          eventTitle: 'Solo Gig',
          role: 'Substitute',
          voicePart: 'Drums',
          date: dateStr1,
          eventSequence: 1,
          requestGroupId: 'grp_solo',
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(userId: 'test_musician_1', instruments: []);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solo Event Band'));
      await tester.pumpAndSettle();

      expect(find.text('Event #1'), findsNothing);

      // Close bottom sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Multi-event test
      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_multi_ev_1',
          subRequestId: 'sub_multi_ev_1',
          bandName: 'Duo Event Band',
          eventTitle: 'Gig Part 1',
          role: 'Substitute',
          voicePart: 'Drums',
          date: dateStr1,
          eventSequence: 1,
          requestGroupId: 'grp_duo',
        ),
        SubRequest(
          id: 'sub_multi_ev_2',
          subRequestId: 'sub_multi_ev_2',
          bandName: 'Duo Event Band',
          eventTitle: 'Gig Part 2',
          role: 'Substitute',
          voicePart: 'Bass',
          date: dateStr2,
          eventSequence: 2,
          requestGroupId: 'grp_duo',
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(key: ValueKey('duo')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duo Event Band'));
      await tester.pumpAndSettle();

      expect(find.text('Event #1'), findsOneWidget);
      expect(find.text('Event #2'), findsOneWidget);
    });

    testWidgets('7 & 8. Unpaid requests show no badge/text; Paid requests retain amount and Details', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_unpaid',
          subRequestId: 'sub_unpaid',
          bandName: 'Acoustic Jam',
          role: 'Substitute',
          voicePart: 'Flute',
          date: dateStr,
          isPaid: false,
        ),
        SubRequest(
          id: 'sub_paid',
          subRequestId: 'sub_paid',
          bandName: 'Paid Band',
          role: 'Substitute',
          voicePart: 'Piano',
          date: dateStr,
          isPaid: true,
          payAmount: 3500,
          currency: 'SEK',
          payDetails: 'Dinner and drinks provided',
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(userId: 'test_musician_1', instruments: []);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No Unpaid text anywhere
      expect(find.text('Unpaid'), findsNothing);
      expect(find.textContaining('Unpaid'), findsNothing);

      // Paid badge appears with formatted currency
      expect(find.text('Paid · SEK 3,500'), findsOneWidget);

      // Open paid gig details
      await tester.tap(find.text('Paid Band'));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Dinner and drinks provided'), findsOneWidget);
    });

    testWidgets('9. Page renders at 320 px width without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockFirebase = MockFindGigsFirebaseService();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_tight_1',
          subRequestId: 'sub_tight_1',
          bandName: 'Very Long Band Name For Testing Overflow',
          role: 'Substitute',
          voicePart: 'Electric Guitar, Synthesizer, Backing Vocals',
          date: dateStr,
          isPaid: true,
          payAmount: 5000,
          currency: 'SEK',
          targetUserIds: ['test_musician_1'],
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(userId: 'test_musician_1', instruments: []);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('10. Nearest upcoming request remains sorted first', (WidgetTester tester) async {
      final mockFirebase = MockFindGigsFirebaseService();
      final inTenDays = DateTime.now().add(const Duration(days: 10));
      final inTwoDays = DateTime.now().add(const Duration(days: 2));
      final dateTenDays = "${inTenDays.year}-${inTenDays.month.toString().padLeft(2, '0')}-${inTenDays.day.toString().padLeft(2, '0')}";
      final dateTwoDays = "${inTwoDays.year}-${inTwoDays.month.toString().padLeft(2, '0')}-${inTwoDays.day.toString().padLeft(2, '0')}";

      // Feed returns later gig first
      mockFirebase.storedRequests = [
        SubRequest(
          id: 'sub_later',
          subRequestId: 'sub_later',
          bandName: 'Later Gig Band',
          role: 'Substitute',
          voicePart: 'Guitar',
          date: dateTenDays,
        ),
        SubRequest(
          id: 'sub_earlier',
          subRequestId: 'sub_earlier',
          bandName: 'Earlier Gig Band',
          role: 'Substitute',
          voicePart: 'Guitar',
          date: dateTwoDays,
        ),
      ];

      final appState = MockFindGigsAppState(mockFirebase);
      appState.testUserId = 'test_musician_1';
      appState.testUserProfile = UserProfile(userId: 'test_musician_1', instruments: []);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final earlierOffset = tester.getTopLeft(find.text('Earlier Gig Band'));
      final laterOffset = tester.getTopLeft(find.text('Later Gig Band'));

      // Earlier gig must appear above later gig
      expect(earlierOffset.dy, lessThan(laterOffset.dy));
    });
  });
}
