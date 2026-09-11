import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/push_sound_admin_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';

class MockPushSoundFirebaseService extends FirebaseService {
  List<String> sentSoundTypes = [];
  Map<String, dynamic> lastResponse = {'success': true, 'messageId': 'test_mock_msg_123'};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: 'test_admin_user', displayName: 'Admin Tester', email: 'admin@example.com');
  }

  @override
  Future<Map<String, dynamic>> sendTestPushNotificationAsync({
    required String soundType,
    String? customToken,
    bool broadcastToAll = false,
  }) async {
    sentSoundTypes.add(soundType);
    return {
      'success': true,
      'messageId': 'mock_msg_$soundType',
      'soundType': soundType,
    };
  }
}

class MockAppStateForPushTest extends AppState {
  final MockPushSoundFirebaseService mockFirebase = MockPushSoundFirebaseService();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_admin_user',
        displayName: 'Admin Tester',
        email: 'admin@example.com',
      );

  @override
  String? get currentUserId => 'test_admin_user';
}

Widget createTestWrapper({
  required MockAppStateForPushTest appState,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
    ],
    child: MaterialApp(
      home: child,
      routes: {
        '/admin-push-sounds': (context) => const PushSoundAdminScreen(),
      },
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

  group('PushSoundAdminScreen Widget Tests', () {
    testWidgets('1. Admin screen renders all 4 sound cards with exact titles and channels', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPushTest();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const PushSoundAdminScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check Top Bar title
      expect(find.text('Push Sound Tester'), findsOneWidget);

      // Check Device Push Token card
      expect(find.text('Device Push Token'), findsOneWidget);

      // Check all 4 Sound Card titles
      expect(find.text('Gig Request'), findsOneWidget);
      expect(find.text('Gig Response'), findsOneWidget);
      expect(find.text('RSVP Reminder'), findsOneWidget);
      expect(find.text('Finalized Gig'), findsOneWidget);

      // Check channel IDs
      expect(find.textContaining('gig_request_channel'), findsOneWidget);
      expect(find.textContaining('gig_response_channel'), findsOneWidget);
      expect(find.textContaining('rsvp_reminder_channel'), findsOneWidget);
      expect(find.textContaining('finalized_gig_channel'), findsOneWidget);

      // Check format mappings for Android & iOS
      expect(find.textContaining('Android: gig_rquest.mp3  •  iOS: gig_rquest.wav'), findsOneWidget);
      expect(find.textContaining('Android: gig_rquest_response.mp3  •  iOS: gig_rquest_response.wav'), findsOneWidget);
      expect(find.textContaining('Android: reminder_rsvp.mp3  •  iOS: reminder_rsvp.wav'), findsOneWidget);
      expect(find.textContaining('Android: finalized_gig.mp3  •  iOS: finalized_gig.wav'), findsOneWidget);

      // Check Preview and Send Push buttons exist for all 4 cards
      expect(find.text('Preview'), findsNWidgets(4));
      expect(find.text('Send Push'), findsNWidgets(4));
    });

    testWidgets('2. Tapping Send Push dispatches correct soundType to service contract', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPushTest();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const PushSoundAdminScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Send Push for Gig Request (first Send Push button)
      final sendPushButtons = find.text('Send Push');
      await tester.tap(sendPushButtons.at(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.sentSoundTypes.length, equals(1));
      expect(appState.mockFirebase.sentSoundTypes.first, equals('gig_rquest'));

      // Tap Send Push for Gig Response (second button)
      await tester.tap(sendPushButtons.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.sentSoundTypes.length, equals(2));
      expect(appState.mockFirebase.sentSoundTypes[1], equals('gig_rquest_response'));

      // Check Activity Log updated
      expect(find.textContaining('Dispatched "Gig Request" test push'), findsOneWidget);
      expect(find.textContaining('Dispatched "Gig Response" test push'), findsOneWidget);
    });

    testWidgets('3. Home screen footer link navigates to PushSoundAdminScreen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPushTest();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const HomeScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final adminLink = find.text('Push Sounds Admin');
      expect(adminLink, findsOneWidget);

      await tester.ensureVisible(adminLink);
      await tester.tap(adminLink);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Push Sound Tester'), findsOneWidget);
      expect(find.text('NOTIFICATION SOUNDS (4)'), findsOneWidget);
    });

    testWidgets('4. Enabling Broadcast switch changes buttons to Broadcast Push and sends broadcastToAll', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForPushTest();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const PushSoundAdminScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Target: Single Device Only'), findsOneWidget);
      expect(find.text('Send Push'), findsNWidgets(4));

      // Toggle Broadcast switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Broadcast to ALL Users'), findsOneWidget);
      expect(find.text('Broadcast Push'), findsNWidgets(4));

      // Tap Broadcast Push
      await tester.tap(find.text('Broadcast Push').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.sentSoundTypes.length, equals(1));
      expect(appState.mockFirebase.sentSoundTypes.first, equals('gig_rquest'));
    });
  });
}
