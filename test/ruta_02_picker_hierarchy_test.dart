import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/data/skills_taxonomy.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/browse_musicians_screen.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockRuta02FirebaseService extends FirebaseService {
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'test_ruta02_user',
      displayName: 'Ruta02 Tester',
      email: 'test@example.com',
      userType: 'SONGWRITER',
      instruments: ['SONGWRITER', 'Electric Guitar', 'STUDIO/ENGINEER, etc'],
      genres: ['Rock'],
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => [];

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];

  @override
  Future<List<Band>> getAllBandsAsync() async => [];
}

class MockAppStateForRuta02Test extends AppState {
  @override
  final FirebaseService firebaseService = MockRuta02FirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_ruta02_user',
        displayName: 'Ruta02 Tester',
        email: 'test@example.com',
        userType: 'SONGWRITER',
        instruments: ['SONGWRITER', 'Electric Guitar', 'STUDIO/ENGINEER, etc'],
        genres: ['Rock'],
      );

  @override
  String? get currentUserId => 'test_ruta02_user';
}

Widget createRuta02TestApp(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForRuta02Test(),
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

  const expectedInstrumentOrder = [
    'Woodwinds',
    'Brass',
    'Strings',
    'Keyboards',
    'Percussion',
    'Miscellaneous Instruments',
  ];

  const expectedRolesInOrder = [
    'BANDLEADER',
    'Songwriter',
    'Producer',
    'Composer',
    'Lyricist',
    'Beatmaker',
    'Engineer',
    'DJ',
  ];

  const expectedCategorySymbols = {
    'Sessions/Collaboration': '🤝',
    'Roles/Production': '🎧',
    'Woodwinds': '🎷',
    'Brass': '🎺',
    'Strings': '🎻',
    'Keyboards': '🎹',
    'Percussion': '🥁',
    'Miscellaneous Instruments': '🪈',
    'Voices (Choir)': '🗣️',
    'Voices (Popular Music)': '🎤',
    'Miscellaneous Voices': '🎭',
  };

  group('RUTA-02 Taxonomy & Hierarchy Unit Tests', () {
    test('1. BANDLEADER is the featured first role option with exact uppercase label', () {
      final roleCategory = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'roles_production');
      expect(roleCategory.optionIds.first, equals('bandleader'));

      final bandleaderOpt = SkillsTaxonomy.findById('bandleader')!;
      expect(bandleaderOpt.displayLabel, equals('BANDLEADER'));
      expect(bandleaderOpt.persistedValue, equals('BANDLEADER'));
    });

    test('2. Role order begins with Songwriter, Producer, Composer, Lyricist, Beatmaker, Engineer, DJ', () {
      final roleCategory = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'roles_production');
      final options = roleCategory.optionIds
          .map((id) => SkillsTaxonomy.findById(id)!)
          .toList();

      final labels = options.map((o) => o.displayLabel).toList();
      expect(labels, equals(expectedRolesInOrder));

      // Persisted values mapping
      expect(options[1].persistedValue, equals('SONGWRITER'));
      expect(options[2].persistedValue, equals('PRODUCER'));
      expect(options[3].persistedValue, equals('COMPOSER'));
      expect(options[4].persistedValue, equals('LYRICIST'));
      expect(options[5].persistedValue, equals('BEATMAKER'));
      expect(options[6].persistedValue, equals('STUDIO/ENGINEER, etc'));
      expect(options[7].persistedValue, equals('DJ'));
    });

    test('3. DJ exists and resolves to persisted value DJ', () {
      final djOpt = SkillsTaxonomy.findById('dj');
      expect(djOpt, isNotNull);
      expect(djOpt!.displayLabel, equals('DJ'));
      expect(djOpt.persistedValue, equals('DJ'));
      expect(djOpt.kind, equals(SkillOptionKind.role));

      final resolved = SkillsTaxonomy.resolveLegacyValue('dj');
      expect(resolved, isNotNull);
      expect(resolved!.persistedValue, equals('DJ'));

      final canonical = SkillsTaxonomy.resolveCanonicalPersistedValue('DJ');
      expect(canonical, equals('DJ'));
    });

    test('4. Instrument categories are plain strings in exact RUTA-02 order ending with Miscellaneous Instruments', () {
      final allCategoryLabels = SkillsTaxonomy.masterCategories
          .map((c) => c.displayLabel)
          .toList();

      final instrumentIndices = expectedInstrumentOrder
          .map((c) => allCategoryLabels.indexOf(c))
          .toList();

      for (int i = 0; i < instrumentIndices.length - 1; i++) {
        expect(instrumentIndices[i] < instrumentIndices[i + 1], isTrue,
            reason: '${expectedInstrumentOrder[i]} must precede ${expectedInstrumentOrder[i + 1]}');
      }
    });

    test('5. Voice categories follow instruments in exact required order with plain labels', () {
      final allCategoryLabels = SkillsTaxonomy.masterCategories
          .map((c) => c.displayLabel)
          .toList();

      final miscInstIdx = allCategoryLabels.indexOf('Miscellaneous Instruments');
      final voicesChoirIdx = allCategoryLabels.indexOf('Voices (Choir)');
      final voicesPopIdx = allCategoryLabels.indexOf('Voices (Popular Music)');
      final miscVoicesIdx = allCategoryLabels.indexOf('Miscellaneous Voices');

      expect(miscInstIdx < voicesChoirIdx, isTrue);
      expect(voicesChoirIdx < voicesPopIdx, isTrue);
      expect(voicesPopIdx < miscVoicesIdx, isTrue);
    });

    test('6. Category display label is Miscellaneous Voices without parenthetical text or emojis', () {
      final miscVoices = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'misc_voices');
      expect(miscVoices.displayLabel, equals('Miscellaneous Voices'));
      expect(miscVoices.displayLabel.contains('Classical, Choir'), isFalse);
      expect(miscVoices.displayLabel.contains('🎭'), isFalse);
    });

    test('7. Every RUTA-02 category has the expected separate leading visual symbol', () {
      for (final cat in SkillsTaxonomy.masterCategories) {
        expect(expectedCategorySymbols.containsKey(cat.displayLabel), isTrue,
            reason: 'Category ${cat.displayLabel} should be in expected symbols map');
        expect(cat.leadingSymbol, equals(expectedCategorySymbols[cat.displayLabel]));
        expect(SkillsTaxonomy.getLeadingSymbolForCategory(cat.displayLabel),
            equals(expectedCategorySymbols[cat.displayLabel]));
        // Verify displayLabel does NOT contain the symbol
        expect(cat.displayLabel.contains(cat.leadingSymbol!), isFalse);
      }
    });

    test('8. Central lookup functions resolve legacy values to display labels and vice versa', () {
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('SONGWRITER'),
          equals('Songwriter'));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('STUDIO/ENGINEER, etc'),
          equals('Engineer'));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('BANDLEADER'),
          equals('BANDLEADER'));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('DJ'), equals('DJ'));

      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel('Songwriter'),
          equals('SONGWRITER'));
      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel('Engineer'),
          equals('STUDIO/ENGINEER, etc'));
      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel('DJ'), equals('DJ'));
    });

    test('9. Unknown stored values pass through safely without corruption or deletion', () {
      const unknownValue = 'CUSTOM_SYNTH_99';
      expect(SkillsTaxonomy.resolveLegacyValue(unknownValue), isNull);
      expect(SkillsTaxonomy.resolveCanonicalPersistedValue(unknownValue),
          equals(unknownValue));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue(unknownValue),
          equals(unknownValue));
      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel(unknownValue),
          equals(unknownValue));
    });

    test('10. RUTA-01 taxonomy integrity validation passes with zero errors', () {
      final validation = SkillsTaxonomy.validateTaxonomyIntegrity();
      expect(validation.isValid, isTrue, reason: validation.errors.join('\n'));
      expect(validation.errors, isEmpty);
    });
  });

  group('RUTA-02 Structured Picker Widget Tests', () {
    testWidgets('11. SearchableCategoryMultiSelectSheet displays BANDLEADER with visual separation when opted into skillsHierarchy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Skill',
                  categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.skillsHierarchy,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      // Expand Roles category
      await tester.tap(find.text('Roles/Production'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Featured BANDLEADER option
      final bandleaderChip = find.byKey(const ValueKey('role_bandleader_chip'));
      expect(bandleaderChip, findsOneWidget);
      expect(find.text('BANDLEADER'), findsOneWidget);

      // Title case roles
      expect(find.text('Songwriter'), findsOneWidget);
      expect(find.text('Producer'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('DJ'), findsOneWidget);

      // Dismiss
      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('12. Category leading visual symbols are rendered with ExcludeSemantics', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Skill',
                  categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.skillsHierarchy,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check visual symbols are rendered inside ExcludeSemantics
      for (final entry in expectedCategorySymbols.entries) {
        final symbolFinder = find.byWidgetPredicate(
          (w) => w is ExcludeSemantics &&
              w.child is Text &&
              (w.child as Text).data == entry.value,
        );
        expect(symbolFinder, findsOneWidget,
            reason: 'Leading symbol ${entry.value} for ${entry.key} must be wrapped in ExcludeSemantics');
      }

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('13. SearchableCategoryMultiSelectSheet displays INSTRUMENTS/VOICES non-selectable heading', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Skill',
                  categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.skillsHierarchy,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final headingFinder = find.byKey(const ValueKey('instruments_voices_section_heading'));
      expect(headingFinder, findsOneWidget);
      expect(find.text('INSTRUMENTS/VOICES'), findsOneWidget);

      // Tapping heading does not select anything or dismiss
      await tester.tap(headingFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('14. SearchableCategoryMultiSelectSheet displays voice separator and plain category labels', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Skill',
                  categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.skillsHierarchy,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final separatorFinder = find.byKey(const ValueKey('voices_section_separator'));
      expect(separatorFinder, findsOneWidget);

      expect(find.text('Miscellaneous Voices'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('15. Selecting title-case UI option returns compatible persisted value', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<String>? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SearchableCategoryMultiSelectSheet.show(
                    context: context,
                    title: 'Select Skill',
                    categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                    initialSelected: const [],
                    isSingleSelect: true,
                    presentation: CategoryPickerPresentation.skillsHierarchy,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expand Roles category
      await tester.tap(find.text('Roles/Production'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap 'Engineer'
      await tester.tap(find.text('Engineer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify single-select popped and returned the canonical persisted value
      expect(selectedResult, equals(['STUDIO/ENGINEER, etc']));
    });

    testWidgets('16. Selecting DJ returns persisted value DJ in multi-select', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<String>? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SearchableCategoryMultiSelectSheet.show(
                    context: context,
                    title: 'Select Skills',
                    categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                    initialSelected: const [],
                    isSingleSelect: false,
                    presentation: CategoryPickerPresentation.skillsHierarchy,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expand Roles category
      await tester.tap(find.text('Roles/Production'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Select BANDLEADER and DJ
      await tester.tap(find.text('BANDLEADER'));
      await tester.pump();
      await tester.tap(find.text('DJ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Done
      await tester.tap(find.text('Done (2 Selected)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(selectedResult, equals(['BANDLEADER', 'DJ']));
    });

    testWidgets('17. Search finds options by display label and legacy alias in skillsHierarchy without emoji requirement', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Skills',
                  categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.skillsHierarchy,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Search 'woodwinds' -> finds Woodwinds category
      await tester.enterText(searchField, 'woodwinds');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Woodwinds'), findsOneWidget);

      // Search 'engineer' -> finds Engineer
      await tester.enterText(searchField, 'engineer');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Engineer'), findsOneWidget);

      // Search 'dj' -> finds DJ
      await tester.enterText(searchField, 'dj');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DJ'), findsOneWidget);

      // Search 'piccolo' -> finds Piccolo Flute and Piccolo Trumpet
      await tester.enterText(searchField, 'piccolo');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Piccolo Flute'), findsOneWidget);
      expect(find.text('Piccolo Trumpet'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('18. Unrelated Genres picker with standard presentation is unaffected by RUTA-02 styling or icons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleGenresMap = {
        'Rock & Metal': ['Classic Rock', 'Hard Rock', 'Heavy Metal'],
        'Electronic': ['House', 'Techno', 'Synthwave'],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Select Genres',
                  categoryMap: sampleGenresMap,
                  initialSelected: const ['Classic Rock'],
                  presentation: CategoryPickerPresentation.standard,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm no INSTRUMENTS/VOICES heading or voice separator in standard mode
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsNothing);
      expect(find.byKey(const ValueKey('voices_section_separator')), findsNothing);
      expect(find.text('Rock & Metal'), findsOneWidget);
      expect(find.text('Electronic'), findsOneWidget);

      // Confirm no category emoji symbols rendered for standard genres
      for (final symbol in expectedCategorySymbols.values) {
        expect(find.text(symbol), findsNothing,
            reason: 'Leading visual symbol $symbol should not be present in standard presentation');
      }

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('19. Structurally similar arbitrary map does not receive RUTA-02 styling under standard presentation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const arbitraryMap = {
        'Woodwinds': ['Custom Pipe', 'Bamboo Whistle'],
        'Roles/Production': ['BANDLEADER', 'Supervisor'],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Arbitrary Map',
                  categoryMap: arbitraryMap,
                  initialSelected: const [],
                  presentation: CategoryPickerPresentation.standard,
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Under standard presentation, even with 'Woodwinds' key, section heading is NOT rendered
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsNothing);
      expect(find.byKey(const ValueKey('role_bandleader_chip')), findsNothing);

      for (final symbol in expectedCategorySymbols.values) {
        expect(find.text(symbol), findsNothing,
            reason: 'Leading visual symbol $symbol should not be present in standard presentation');
      }

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('20. Sessions/Collaboration remains visible, selectable, and functional in UI pending RUTA-03', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<String>? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SearchableCategoryMultiSelectSheet.show(
                    context: context,
                    title: 'Select Skills',
                    categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                    initialSelected: const [],
                    presentation: CategoryPickerPresentation.skillsHierarchy,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm Sessions/Collaboration category exists
      final sessionsCat = find.text('Sessions/Collaboration');
      expect(sessionsCat, findsOneWidget);

      // Expand Sessions category
      await tester.tap(sessionsCat);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm options render and are selectable
      expect(find.text('Create Session'), findsOneWidget);
      expect(find.text('Studio Session'), findsOneWidget);
      expect(find.text('Co-Writing Session'), findsOneWidget);

      await tester.tap(find.text('Studio Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Done (1 Selected)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(selectedResult, equals(['Studio Session']));
    });

    testWidgets('21. Unknown existing stored value is preserved and returned verbatim with additions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<String>? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SearchableCategoryMultiSelectSheet.show(
                    context: context,
                    title: 'Select Skills',
                    categoryMap: SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile),
                    initialSelected: const ['CUSTOM_SYNTH_99'],
                    presentation: CategoryPickerPresentation.skillsHierarchy,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check count indicator includes the unknown stored value
      expect(find.text('1'), findsOneWidget);

      // Add Electric Guitar (expand Strings)
      await tester.tap(find.text('Strings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Electric Guitar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Done
      await tester.tap(find.text('Done (2 Selected)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify CUSTOM_SYNTH_99 is preserved verbatim alongside new selection
      expect(selectedResult, contains('CUSTOM_SYNTH_99'));
      expect(selectedResult, contains('Electric Guitar'));
      expect(selectedResult!.length, equals(2));
    });

    testWidgets('22. EditProfileScreen uses the RUTA-02 redesigned hierarchy with Sessions preserved', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRuta02TestApp(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final primaryField = find.text('Primary Skill/Talent (Select 1)');
      expect(primaryField, findsOneWidget);
      await tester.tap(primaryField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsOneWidget);
      expect(find.text('Sessions/Collaboration'), findsOneWidget); // Preserved for RUTA-03
      expect(find.text('Miscellaneous Voices'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('23. BrowseMusiciansScreen filter uses the RUTA-02 centralized hierarchy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRuta02TestApp(const BrowseMusiciansScreen()));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final filterCard = find.text('Filter by Skills & Instruments...');
      expect(filterCard, findsOneWidget);
      await tester.tap(filterCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsOneWidget);
      expect(find.text('Roles/Production'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('24. FindSubScreen uses the RUTA-02 centralized hierarchy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRuta02TestApp(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentCard = find.text('INSTRUMENT/SKILLS');
      expect(instrumentCard, findsOneWidget);
      await tester.tap(instrumentCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('25. RegisterScreen renders flat dropdown preserving Electric Guitar default', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRuta02TestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Electric Guitar'), findsOneWidget);
    });
  });
}
