import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockGen01FirebaseService extends FirebaseService {
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'test_user_1',
      displayName: 'Test Musician',
      email: 'test@example.com',
      genres: ['Rock', 'Jazz'],
      instruments: ['Guitar', 'Vocals'],
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => [];

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];

  @override
  Future<List<Band>> getAllBandsAsync() async => [];
}

class MockAppStateForGen01 extends AppState {
  @override
  final FirebaseService firebaseService = MockGen01FirebaseService();

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
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('GEN-01 Selection Field Tap Interaction & Accessibility Tests', () {
    testWidgets('1. EditProfileScreen: Primary Skill/Talent opens picker on tap without redundant "+ Select"', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('2. EditProfileScreen: Secondary Skills opens picker', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final secondaryLabel = find.text('Secondary Skills (Optional)');
      expect(secondaryLabel, findsOneWidget);
      await tester.tap(secondaryLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('3. EditProfileScreen: Other Skills opens picker', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final otherLabel = find.text('Other Skills (Optional)');
      expect(otherLabel, findsOneWidget);
      await tester.tap(otherLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('4. EditProfileScreen: Genres/Band Types opens picker on tap and redundant "+ Add" is absent', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresLabel = find.text('GENRES/BAND TYPES');
      expect(genresLabel, findsOneWidget);
      expect(find.text('+ Add'), findsNothing);

      await tester.tap(genresLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('5. CreateBandScreen: Genres/Band Types opens picker on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresTitle = find.text('GENRES/BAND TYPES');
      expect(genresTitle, findsOneWidget);

      await tester.tap(genresTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('6. EditBandInfoScreen: Genres/Band Types opens picker and values persist upon dismiss', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final band = Band(id: 'b1', name: 'Cool Band', genres: const ['Rock', 'Pop']);
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

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rock'), findsOneWidget);
    });

    testWidgets('7. FindSubScreen: Instrument/Skills opens picker on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentTitle = find.text('Instrument/Skill');
      expect(instrumentTitle, findsOneWidget);
      expect(find.text('+ Select'), findsNothing);

      await tester.tap(instrumentTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('8. Chip delete/remove control only removes chip and DOES NOT open selection picker', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final band = Band(id: 'b1', name: 'Cool Band', genres: const ['Rock']);
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
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final genresTitle = find.text('GENRES/BAND TYPES');
      await tester.tap(genresTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('10. GEN-02..GEN-05 Canonical labels verification', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('GENRES/BAND TYPES'), findsOneWidget);
    });
  });
}
