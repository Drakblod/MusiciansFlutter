import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockAppStateForInstrumentTest extends AppState {
  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_inst',
        displayName: 'Test Musician',
        email: 'test@example.com',
        genres: ['Rock'],
        instruments: ['Guitar'],
      );

  @override
  String? get currentUserId => 'test_user_inst';
}

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<AppState>.value(
    value: MockAppStateForInstrumentTest(),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Master Instrument and Skills List Verification Tests', () {
    final expectedCategories = [
      '🎧 Roles / Production',
      '🎷 Woodwinds',
      '🎺 Brass',
      '🎻 Strings',
      '🎹 Keyboards',
      '🥁 Percussion',
      '🗣️ Voices (Choir)',
      '🎭 Miscellaneous Voices (Classical, Choir)',
      '🎤 Voices (Popular Music)',
      '🪈 Miscellaneous Instruments',
    ];

    testWidgets('EditProfileScreen picker opens and contains updated categories and items', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final primaryField = find.text('Primary Skill/Talent (Select 1)');
      await tester.tap(primaryField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      for (final cat in expectedCategories) {
        expect(find.text(cat), findsOneWidget);
      }

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('FindSubScreen picker opens and displays updated master category structure', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentTitle = find.text('INSTRUMENT/SKILLS');
      expect(instrumentTitle, findsOneWidget);

      await tester.tap(instrumentTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      expect(find.text('🎧 Roles / Production'), findsOneWidget);
      expect(find.text('🗣️ Voices (Choir)'), findsOneWidget);
      expect(find.text('🎭 Miscellaneous Voices (Classical, Choir)'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
