import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/widgets/custom_top_bar.dart';

class MockDeletionFirebaseService extends FirebaseService {
  String _mockUserId = 'user_leader_1';
  bool deleteAccountCalled = false;
  String? deletedBandId;

  void setMockUserId(String uid) {
    _mockUserId = uid;
  }

  @override
  String? get currentUserId => _mockUserId;

  @override
  bool get isLoggedIn => true;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: _mockUserId,
      displayName: 'Test Musician',
      email: 'test@example.com',
      nickname: 'Test Musician',
      instruments: ['Vocals'],
      level: 'A = PRO',
    );
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {'band_1': 'The Rockers'};
  }

  @override
  Stream<bool> subscribeToUnreadNotifications() {
    return Stream.value(false);
  }

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) {
    return Stream.value(0);
  }

  @override
  Future<void> deleteUserAccountAsync() async {
    deleteAccountCalled = true;
  }

  @override
  Future<void> deleteBandAsync(String bandId) async {
    deletedBandId = bandId;
  }
}

class MockDeletionAppState extends AppState {
  final MockDeletionFirebaseService mockFirebase;
  String? _customUserId;

  MockDeletionAppState(this.mockFirebase, {String? userId}) {
    _customUserId = userId ?? mockFirebase.currentUserId;
  }

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => _customUserId ?? mockFirebase.currentUserId;

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('Band Model isUserLeader Tests', () {
    test('1. Accurately identifies leader from membersBand map with Role Leader', () {
      final band = Band(
        id: 'band_rock',
        name: 'The Rockers',
        membersBand: {
          'user_1': BandMember(userId: 'user_1', role: 'Leader', nickname: 'Alex'),
          'user_2': BandMember(userId: 'user_2', role: 'Member', nickname: 'Bob'),
        },
      );

      expect(band.isUserLeader('user_1'), isTrue);
      expect(band.isUserLeader('user_2'), isFalse);
      expect(band.isUserLeader('user_unknown'), isFalse);
      expect(band.isUserLeader(null), isFalse);
    });

    test('2. Accurately identifies leader case-insensitively or via nickname', () {
      final band = Band(
        id: 'band_jazz',
        name: 'Jazz Quintet',
        membersBand: {
          'user_3': BandMember(userId: 'user_3', role: 'leader', nickname: 'Sarah'),
        },
      );

      expect(band.isUserLeader('user_3'), isTrue);
    });
  });

  group('EditBandInfoScreen Delete Band Tests', () {
    testWidgets('1. Shows "Delete Band" button when current user is Leader', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDeletionFirebaseService();
      mockService.setMockUserId('user_leader_1');
      final appState = MockDeletionAppState(mockService, userId: 'user_leader_1');

      final band = Band(
        id: 'band_1',
        name: 'The Rockers',
        location: 'Stockholm',
        genres: ['Rock'],
        membersBand: {
          'user_leader_1': BandMember(userId: 'user_leader_1', role: 'Leader', nickname: 'Boss'),
          'user_member_2': BandMember(userId: 'user_member_2', role: 'Member', nickname: 'Guitarist'),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: EditBandInfoScreen(band: band),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BAND LEADER ACTIONS'), findsOneWidget);
      expect(find.text('Delete Band'), findsOneWidget);
    });

    testWidgets('2. Hides "Delete Band" button when current user is NOT Leader', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDeletionFirebaseService();
      mockService.setMockUserId('user_member_2'); // Regular member
      final appState = MockDeletionAppState(mockService, userId: 'user_member_2');

      final band = Band(
        id: 'band_1',
        name: 'The Rockers',
        location: 'Stockholm',
        genres: ['Rock'],
        membersBand: {
          'user_leader_1': BandMember(userId: 'user_leader_1', role: 'Leader', nickname: 'Boss'),
          'user_member_2': BandMember(userId: 'user_member_2', role: 'Member', nickname: 'Guitarist'),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: EditBandInfoScreen(band: band),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BAND LEADER ACTIONS'), findsNothing);
      expect(find.text('Delete Band'), findsNothing);
    });

    testWidgets('3. Tapping "Delete Band" displays confirmation dialog and calls deleteBand on confirm', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDeletionFirebaseService();
      mockService.setMockUserId('user_leader_1');
      final appState = MockDeletionAppState(mockService, userId: 'user_leader_1');

      final band = Band(
        id: 'band_1',
        name: 'The Rockers',
        location: 'Stockholm',
        genres: ['Rock'],
        membersBand: {
          'user_leader_1': BandMember(userId: 'user_leader_1', role: 'Leader', nickname: 'Boss'),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (context) => ChangeNotifierProvider<AppState>.value(
                  value: appState,
                  child: EditBandInfoScreen(band: band),
                ),
          },
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to bottom and tap Delete Band
      await tester.scrollUntilVisible(
        find.text('Delete Band'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Band'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible
      expect(find.text('Are you sure you want to permanently delete "The Rockers"? This will remove the band, its events, and chat rooms for all band members.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deletedBandId, equals('band_1'));
    });
  });

  group('Delete Account UI Tests', () {
    testWidgets('1. CustomTopBar settings menu displays "Delete Account" and opens confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDeletionFirebaseService();
      final appState = MockDeletionAppState(mockService, userId: 'user_leader_1');

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (context) => ChangeNotifierProvider<AppState>.value(
                  value: appState,
                  child: const Scaffold(
                    appBar: CustomTopBar(),
                  ),
                ),
            '/login': (context) => const Scaffold(body: Text('Login Screen')),
          },
        ),
      );
      await tester.pumpAndSettle();

      // Tap settings cog icon in top bar
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);

      // Tap Delete Account
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to permanently delete your account? This action cannot be undone and will delete all your profile data, notification feeds, and band memberships.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Delete in confirmation dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deleteAccountCalled, isTrue);
      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('2. EditProfileScreen displays Danger Zone with "Delete Account" button and opens confirmation', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockDeletionFirebaseService();
      final appState = MockDeletionAppState(mockService, userId: 'user_leader_1');

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (context) => ChangeNotifierProvider<AppState>.value(
                  value: appState,
                  child: const EditProfileScreen(),
                ),
            '/login': (context) => const Scaffold(body: Text('Login Screen')),
          },
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to bottom
      await tester.scrollUntilVisible(
        find.text('DANGER ZONE'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to permanently delete your account? This action cannot be undone and will delete all your profile data, notification feeds, and band memberships.'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(mockService.deleteAccountCalled, isTrue);
      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
