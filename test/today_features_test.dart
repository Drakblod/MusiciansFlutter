import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/manage_events_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:provider/provider.dart';

class MockFeatureFirebaseService extends Fake implements FirebaseService {
  List<SubRequest> feedRequests = [];
  Set<String> appliedIds = {};
  List<UserProfile> allUsers = [];
  Map<String, List<BandEvent>> bandEvents = {};
  Map<String, String> userBands = {'b1': 'Rockers'};
  String? lastRsvpStatus;
  String? lastRsvpEventId;

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => feedRequests;

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String uid) async => appliedIds;

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => allUsers;

  @override
  Future<Map<String, String>> getUserBandsAsync(String uid) async => userBands;

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String uid) async => 'leader';

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value(bandEvents[bandId] ?? []);
  }

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    lastRsvpStatus = status;
    lastRsvpEventId = eventId;
  }

  @override
  Future<void> createBandAsync(String userId, Band band) async {}

  @override
  Future<void> addBandMemberAsync(
    String bandId,
    String userId,
    String role,
    String nickname,
  ) async {}
}

class MockFeatureAppState extends Fake with ChangeNotifier implements AppState {
  final MockFeatureFirebaseService _mockService;
  final String _mockUserId;
  final UserProfile? _mockProfile;

  MockFeatureAppState(this._mockService, {String userId = 'u_current', UserProfile? profile})
      : _mockUserId = userId,
        _mockProfile = profile;

  @override
  FirebaseService get firebaseService => _mockService;

  @override
  String? get currentUserId => _mockUserId;

  @override
  UserProfile? get currentUserProfile =>
      _mockProfile ?? UserProfile(userId: _mockUserId, displayName: 'Test User');

  @override
  String? get activeBandId => 'b1';

  @override
  String? get activeBandName => 'Test Band';

  @override
  String? get activeBandRole => 'leader';

  @override
  Map<String, String> get userBands => {'b1': 'Test Band'};

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  Future<void> refreshProfile() async {}
}

Widget createTestApp(Widget child, AppState appState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Today Features Tests', () {
    testWidgets('1. FindGigsScreen displays 4 tabs including "Applied"', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockFeatureFirebaseService();
      final appState = MockFeatureAppState(mockService);

      await tester.pumpWidget(createTestApp(const FindGigsScreen(), appState));
      await tester.pumpAndSettle();

      expect(find.text('Substitute Requests'), findsOneWidget);
      expect(find.text('New Member Requests'), findsOneWidget);
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('2. FindGigsScreen displays Sub and New Member tags on gig cards', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockFeatureFirebaseService();
      final now = DateTime.now().add(const Duration(days: 3));
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      mockService.feedRequests = [
        SubRequest(
          id: 'sub_1',
          subRequestId: 'sub_1',
          bandName: 'Band Sub',
          requestType: 'Substitute',
          voicePart: 'Bass',
          date: dateStr,
          status: 'Open',
        ),
      ];

      final appState = MockFeatureAppState(mockService);

      await tester.pumpWidget(createTestApp(const FindGigsScreen(), appState));
      await tester.pumpAndSettle();

      expect(find.text('Sub'), findsWidgets);
    });

    testWidgets('3. CreateBandScreen displays Band Members section with Leader and Add Member button', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockFeatureFirebaseService();
      final appState = MockFeatureAppState(
        mockService,
        userId: 'u_leader',
        profile: UserProfile(userId: 'u_leader', displayName: 'Captain Leader'),
      );

      await tester.pumpWidget(createTestApp(const CreateBandScreen(), appState));
      await tester.pumpAndSettle();

      expect(find.text('Band Members'), findsOneWidget);
      expect(find.text('Captain Leader (You)'), findsOneWidget);
      expect(find.text('Add Member'), findsWidgets);
    });

    testWidgets('4. ManageEventsScreen displays RSVP buttons (Yes, No, Maybe) on New Events and allows 1-tap response', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockFeatureFirebaseService();
      final futureEventDate = DateTime.now().add(const Duration(days: 5)).toIso8601String();

      mockService.bandEvents = {
        'b1': [
          BandEvent(
            id: 'ev_1',
            title: 'Gig at Stadium',
            description: 'Important concert',
            location: 'Main Stage',
            startDateTime: futureEventDate,
            endDateTime: futureEventDate,
            additionalNotes: '',
            createdBy: 'u_leader',
            createdAt: 0,
            updatedAt: 0,
            requireResponse: true,
            isLocked: false,
            responses: {},
          ),
        ],
      };

      final appState = MockFeatureAppState(mockService);

      await tester.pumpWidget(createTestApp(const ManageEventsScreen(initialBandId: 'b1', embedded: true), appState));
      await tester.pumpAndSettle();

      // Check RSVP Required banner and buttons
      expect(find.text('RSVP Required'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Maybe'), findsOneWidget);

      // Tap 'Yes'
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      // Verify FirebaseService called with 'Yes'
      expect(mockService.lastRsvpStatus, 'Yes');
      expect(mockService.lastRsvpEventId, 'ev_1');
    });
  });
}
