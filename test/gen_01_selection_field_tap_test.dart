import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockAppStateForGen01 extends AppState {
  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_1',
        displayName: 'Test Musician',
        email: 'test@example.com',
        genres: ['Rock', 'Jazz'],
        instruments: ['Guitar', 'Vocals'],
      );

  @override
  String? get currentUserId => 'test_user_1';
}

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForGen01(),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GEN-01 Selection Field Tap Interaction & Accessibility Tests', () {
    testWidgets('1. EditProfileScreen: Primary Skill/Talent opens picker on tap without redundant "+ Select"', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Primary Skill/Talent (Select 1)'), findsOneWidget);
      expect(find.text('+ Select'), findsNothing);

      final primaryField = find.text('Primary Skill/Talent (Select 1)');
      await tester.tap(primaryField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('2. EditProfileScreen: Secondary Skills opens picker', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final secondaryLabel = find.text('Secondary Skills (Optional)');
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(secondaryLabel, findsOneWidget);
      await tester.tap(secondaryLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('3. EditProfileScreen: Other Skills opens picker', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final otherLabel = find.text('Other Skills (Optional)');
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(otherLabel, findsOneWidget);
      await tester.tap(otherLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('4. EditProfileScreen: Genres/Band Types opens picker on tap and redundant "+ Add" is absent', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresLabel = find.text('GENRES/BAND TYPES');
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(genresLabel, findsOneWidget);
      expect(find.text('+ Add'), findsNothing);

      await tester.tap(genresLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('5. CreateBandScreen: Genres/Band Types opens picker on tap', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresTitle = find.text('GENRES/BAND TYPES');
      expect(genresTitle, findsOneWidget);

      await tester.tap(genresTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('6. EditBandInfoScreen: Genres/Band Types opens picker and values persist upon dismiss', (WidgetTester tester) async {
      final band = Band(id: 'b1', name: 'Cool Band', styleBand: ['Rock', 'Pop']);
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresTitle = find.text('GENRES/BAND TYPES');
      expect(genresTitle, findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);

      await tester.tap(genresTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rock'), findsOneWidget);
    });

    testWidgets('7. FindSubScreen: Instrument/Skills opens picker on tap', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentTitle = find.text('INSTRUMENT/SKILLS');
      expect(instrumentTitle, findsOneWidget);
      expect(find.text('+ Select'), findsNothing);

      await tester.tap(instrumentTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('8. Chip delete/remove control only removes chip and DOES NOT open selection picker', (WidgetTester tester) async {
      final band = Band(id: 'b1', name: 'Cool Band', styleBand: ['Rock']);
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rock'), findsOneWidget);

      final chipDeleteIcon = find.byIcon(Icons.close_rounded);
      expect(chipDeleteIcon, findsOneWidget);
      await tester.tap(chipDeleteIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rock'), findsNothing);
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('9. Picker opens exactly once per activation trigger', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresTitle = find.text('GENRES/BAND TYPES');
      await tester.tap(genresTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('10. GEN-02..GEN-05 Canonical labels verification', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('GENRES/BAND TYPES'), findsOneWidget);
    });
  });
}
