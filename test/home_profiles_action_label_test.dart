// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/home_screen.dart';

class MockFirebaseServiceForHomeActionTest extends FirebaseService {
  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => {};
}

class MockAppStateForHomeActionTest extends AppState {
  final MockFirebaseServiceForHomeActionTest _mockService = MockFirebaseServiceForHomeActionTest();
  List<String> _bubbles;

  MockAppStateForHomeActionTest({List<String>? bubbles})
      : _bubbles = bubbles ?? ['find_musicians', 'band_room', 'create_event'];

  @override
  FirebaseService get firebaseService => _mockService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user',
        displayName: 'Test User',
      );

  @override
  String? get currentUserId => 'test_user';

  @override
  List<String> get selectedBubbles => _bubbles;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('HomeView "Profiles" vs "Explore musician/collaborator" Label Tests', () {
    testWidgets(
      'When Profiles is NOT a shortcut, it renders as "Explore musician/collaborator" with helptext underneath',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Default bubbles: 'find_musicians', 'band_room', 'create_event' -> browse_musicians is in remaining cards
        final appState = MockAppStateForHomeActionTest(
          bubbles: ['find_musicians', 'band_room', 'create_event'],
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const MaterialApp(
              home: Scaffold(body: HomeScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // The card title is "Explore musician/collaborator"
        expect(find.text('Explore musician/collaborator'), findsOneWidget);
        // And has the helptext underneath
        expect(
          find.text('Explore profiles and discover new collaborators'),
          findsOneWidget,
        );
        // "Profiles" is NOT rendered as an action card title or bubble
        expect(find.text('Profiles'), findsNothing);
      },
    );

    testWidgets(
      'When Profiles IS a shortcut, the bubble renders "Profiles"',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Set browse_musicians as one of the 3 top bubbles
        final appState = MockAppStateForHomeActionTest(
          bubbles: ['browse_musicians', 'band_room', 'create_event'],
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const MaterialApp(
              home: Scaffold(body: HomeScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // The bubble displays "Profiles"
        expect(find.text('Profiles'), findsOneWidget);
        // Since it's in the top bubbles, "Explore musician/collaborator" card is not in remaining cards
        expect(find.text('Explore musician/collaborator'), findsNothing);
      },
    );
  });
}
