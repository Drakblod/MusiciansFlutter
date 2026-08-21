import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'command_line_mock_app_state.dart' if (dart.library.html) '';
import 'package:musicians_flutter/views/collabs_landing_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockCollabsFirebaseService extends FirebaseService {
  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return [];
  }
}

class MockAppStateForCollabsTest extends AppState {
  @override
  final FirebaseService firebaseService = MockCollabsFirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'collab_user',
        displayName: 'Collab Creator',
        email: 'creator@example.com',
      );

  @override
  String? get currentUserId => 'collab_user';
}

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForCollabsTest(),
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
    testWidgets('CollabsLandingScreen opens popup sheet with Sessions / Collaboration category', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const CollabsLandingScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final collabBox = find.text('COLLABORATION AREA');
      expect(collabBox, findsOneWidget);

      await tester.tap(collabBox);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('🎛️ Sessions / Collaboration'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });
  });
}
