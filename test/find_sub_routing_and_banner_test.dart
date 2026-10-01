import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';

class MockRoutingFirebaseService extends Fake implements FirebaseService {
  final List<SubRequest> subRequests = [];
  final Map<String, String> userBands = {'band_1': 'Rock Band'};

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUserId => 'user_1';

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) => Stream.value(0);

  @override
  Future<void> initializePushNotifications() async {}

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      displayName: 'Test User',
      email: 'test@example.com',
    );
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return userBands;
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    return subRequests;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return [];
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return [];
  }

  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async {
    return {};
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: 'Rock Band',
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [];
  }
}

class MockAppStateForRoutingTest extends AppState {
  final MockRoutingFirebaseService mockService;
  MockAppStateForRoutingTest(this.mockService);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => 'user_1';

  @override
  String? get activeBandId => 'band_1';

  @override
  String? get activeBandName => 'Rock Band';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('FindSubScreen displays top banner when active sub-requests exist for band', (WidgetTester tester) async {
    final mockService = MockRoutingFirebaseService();
    mockService.subRequests.add(SubRequest(
      id: 'req_1',
      bandId: 'band_1',
      bandName: 'Rock Band',
      role: 'Guitar',
      status: 'pending',
      userId: 'user_1',
    ));

    final appState = MockAppStateForRoutingTest(mockService);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindSubScreen(bandId: 'band_1'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    // Check that active sub requests banner is present
    expect(find.text('1 Active Sub Request'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
  });

  testWidgets('FindSubScreen does not display top banner when no active sub-requests exist', (WidgetTester tester) async {
    final mockService = MockRoutingFirebaseService();
    final appState = MockAppStateForRoutingTest(mockService);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: FindSubScreen(bandId: 'band_1'),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    // Check that active sub requests banner is NOT present
    expect(find.textContaining('active sub-request'), findsNothing);
  });
}
