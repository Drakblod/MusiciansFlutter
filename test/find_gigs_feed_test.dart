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
}
