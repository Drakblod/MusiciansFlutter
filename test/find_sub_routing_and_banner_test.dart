import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/request_management_access.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';

class MockRoutingFirebaseService extends Fake implements FirebaseService {
  // This routing fixture already declares user_1 as the canonical band_1 Leader.
  @override Stream<String?> get catalogueIdentityChanges => const Stream.empty();
  @override Stream<bool> watchRequestManagementAccess(RequestManagementAccess access) => const Stream.empty();
  @override
  Future<RequestManagementAccess> authorizeRequestManagement({String? bandId,String? requestId,String? expectedCreatorId,bool Function()? isCurrent}) async {
    if(bandId!='band_1' || (isCurrent!=null && !isCurrent())) throw const PrivateDataAccessException();
    return RequestManagementAccess(userId:currentUserId!,bandId:bandId!);
  }

  final List<SubRequest> subRequests = [];
  final Map<String, String> userBands = {'band_1': 'Rock Band'};

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUserId => 'user_1';

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Stream<List<AppNotification>> subscribeToUserNotifications([String? userId]) => const Stream.empty();

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
      membersBand: {'user_1': BandMember(userId: 'user_1', role: 'Leader')},
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
    await tester.pump(const Duration(milliseconds: 200));

    // The banner action resolves its own canonical permission after the form loads.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Check that active requests banner is present
    expect(find.text('1 Active Request'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 200));

    // Check that active sub requests banner is NOT present
    expect(find.textContaining('active sub-request'), findsNothing);
  });
}
