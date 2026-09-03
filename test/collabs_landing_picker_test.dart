import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/views/collabs_landing_screen.dart';
import 'package:musicians_flutter/views/find_collabs_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockCollabsFirebaseService extends FirebaseService {
  List<String> favoriteIds = [];
  Map<String, UserProfile> profiles = {};
  SubRequest? savedRequest;

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return favoriteIds;
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? uid]) async {
    return profiles[uid];
  }

  @override
  Future<String?> saveSubRequestAsync(SubRequest request) async {
    savedRequest = request;
    return 'req_collab_test_id';
  }
}

class MockAppStateForCollabsTest extends AppState {
  @override
  final MockCollabsFirebaseService firebaseService;

  MockAppStateForCollabsTest({MockCollabsFirebaseService? service})
      : firebaseService = service ?? MockCollabsFirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'collab_user',
        displayName: 'Collab Creator',
        email: 'creator@example.com',
      );

  @override
  String? get currentUserId => 'collab_user';
}

Widget createTestWidget(Widget child, {MockCollabsFirebaseService? service}) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForCollabsTest(service: service),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Collabs Landing Screen & Master Category Verification Tests', () {
    testWidgets('CollabsLandingScreen opens popup sheet with Sessions category', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const CollabsLandingScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final collabBox = find.text('COLLABORATION AREA');
      expect(collabBox, findsOneWidget);

      await tester.tap(collabBox);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('CollabsLandingScreen Select Favorites: Select all, Clear all, deselection, duplicate avoidance, and publishing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = MockCollabsFirebaseService();
      service.favoriteIds = ['fav_1', 'fav_2', 'fav_3'];
      service.profiles = {
        'fav_1': UserProfile(userId: 'fav_1', displayName: 'Alice Wonder', email: 'alice@test.com'),
        'fav_2': UserProfile(userId: 'fav_2', displayName: 'Bob Drummer', email: 'bob@test.com'),
        'fav_3': UserProfile(userId: 'fav_3', displayName: 'Charlie Bass', email: 'charlie@test.com'),
      };

      await tester.pumpWidget(createTestWidget(const CollabsLandingScreen(), service: service));
      await tester.pumpAndSettle();

      // Enter Description / Details
      await tester.enterText(
        find.widgetWithText(TextFormField, "Describe what the collaboration is about (e.g. 'I am looking for a co-writer to compose acoustic tracks on weekends')"),
        'Looking for acoustic track co-writer',
      );
      await tester.pumpAndSettle();

      // Open Favorites List panel
      await tester.tap(find.text('FAVORITES LIST'));
      await tester.pumpAndSettle();

      // Initial state: starts unselected with "Select all" button and "0 selected"
      expect(find.text('0 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);

      // Verify all checkboxes are initially false
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Wonder')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Bob Drummer')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Charlie Bass')).value, isFalse);

      // 1. "Select all" selects every Favorite
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(find.text('3 selected'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);
      expect(find.text('Select all'), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Wonder')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Bob Drummer')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Charlie Bass')).value, isTrue);

      // 3. Individual deselection still works
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Bob Drummer'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Wonder')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Bob Drummer')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Charlie Bass')).value, isTrue);

      // Tap Select all again to select Bob back
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);

      // 4. "Clear all" removes all selections
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Wonder')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Bob Drummer')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Charlie Bass')).value, isFalse);

      // Re-select all with "Select all" and publish
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      // 5. Publishing uses the selected Favorite IDs and 2. No duplicate IDs are created
      await tester.tap(find.text('Send Collaboration Request'));
      await tester.pumpAndSettle();

      expect(service.savedRequest, isNotNull);
      final published = service.savedRequest!;
      expect(published.targetUserIds, isNotNull);
      // Verify no duplicates
      expect(published.targetUserIds!.toSet().length, equals(published.targetUserIds!.length));
      expect(published.targetUserIds, unorderedEquals(['fav_1', 'fav_2', 'fav_3']));
      expect(published.description, equals('Looking for acoustic track co-writer'));
    });

    testWidgets('FindCollabsScreen Select Favorites: Select all and Clear all functionality', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = MockCollabsFirebaseService();
      service.favoriteIds = ['fav_1', 'fav_2'];
      service.profiles = {
        'fav_1': UserProfile(userId: 'fav_1', displayName: 'Alice Wonder', email: 'alice@test.com'),
        'fav_2': UserProfile(userId: 'fav_2', displayName: 'Bob Drummer', email: 'bob@test.com'),
      };

      await tester.pumpWidget(createTestWidget(const FindCollabsScreen(), service: service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FAVORITES LIST'));
      await tester.pumpAndSettle();

      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
    });
  });
}
