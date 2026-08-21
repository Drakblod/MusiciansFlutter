import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/browse_musicians_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockProfilesFirebaseService extends FirebaseService {
  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [
      UserProfile(
        userId: 'm1',
        displayName: 'Alice Sax',
        userType: 'Woodwinds',
        instruments: ['Alto Sax'],
        genres: ['Jazz'],
      ),
      UserProfile(
        userId: 'm2',
        displayName: 'Bob Drummer',
        userType: 'Drums',
        instruments: ['Drums'],
        genres: ['Rock'],
      ),
    ];
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return [];
  }
}

class MockAppStateForProfilesTest extends AppState {
  @override
  final FirebaseService firebaseService = MockProfilesFirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'self_user',
        displayName: 'Self User',
        email: 'self@example.com',
      );

  @override
  String? get currentUserId => 'self_user';
}

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForProfilesTest(),
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

  group('Profiles Page Interactive Picker Popup Tests', () {
    testWidgets('Tapping search/selection card on PROFILES page opens popup window sheet', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const BrowseMusiciansScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final cardFinder = find.text('Search musicians, vocalists, songwriters, producers...');
      expect(cardFinder, findsOneWidget);

      await tester.tap(cardFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });
  });
}
