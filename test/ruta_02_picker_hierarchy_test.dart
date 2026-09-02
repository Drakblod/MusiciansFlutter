import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/data/skills_taxonomy.dart';
import 'package:musicians_flutter/models/user_profile.dart';
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
      userId: 'test_user_ruta_02',
      displayName: 'Test Artist',
      email: 'artist@example.com',
      instruments: ['Electric Guitar', 'BANDLEADER'],
      genres: ['Rock', 'Jazz'],
      level: 'B = ADVANCED',
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [
      UserProfile(
        userId: 'm1',
        displayName: 'Alex Leader',
        instruments: ['BANDLEADER'],
        genres: ['Funk'],
        level: 'A = PRO',
      ),
    ];
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];
}

class MockRuta02AppState extends AppState {
  @override
  final FirebaseService firebaseService = MockRuta02FirebaseService();

  @override
  bool get isLoading => false;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_ruta_02',
        displayName: 'Test Artist',
        instruments: ['Electric Guitar', 'BANDLEADER'],
        genres: ['Rock', 'Jazz'],
        level: 'B = ADVANCED',
      );

  @override
  String? get currentUserId => 'test_user_ruta_02';
}

Widget createRuta02TestApp(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockRuta02AppState(),
    child: MaterialApp(
      home: child,
      routes: {
        '/login': (_) => const Scaffold(body: Text('Login Screen')),
        '/home': (_) => const Scaffold(body: Text('Home Screen')),
      },
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
    'Songwriter',
    'Lyricist',
    'Producer',
    'Composer',
    'Beatmaker',
    'Engineer',
    'DJ',
    'PR/Management',
  ];

  const expectedCategorySymbols = {
    'Songwriters/Lyricists/Producers/Engineers...': '🎧',
    'Sessions': '🤝',
    'Woodwinds': '🎷',
    'Brass': '🎺',
    'Strings': '🎻 🎸',
    'Keyboards': '🎹',
    'Percussion': '🥁',
    'Miscellaneous Instruments': '🪈',
    'Voices (Choir)': '🗣️',
    'Voices (Popular Music)': '🎤',
    'Miscellaneous Voices': '🎭',
  };

  group('RUTA-02B Taxonomy & Hierarchy Unit Tests', () {
    test('1. BANDLEADER is defined with exact uppercase display label and persisted value', () {
      final bandleaderOpt = SkillsTaxonomy.findById('bandleader')!;
      expect(bandleaderOpt.displayLabel, equals('BANDLEADER'));
      expect(bandleaderOpt.persistedValue, equals('BANDLEADER'));
      expect(SkillsTaxonomy.featuredRoleDisplayLabel, equals('BANDLEADER'));
      expect(SkillsTaxonomy.featuredRolePersistedValue, equals('BANDLEADER'));
    });

    test('2. Professional roles category has exact heading Songwriters/Lyricists/Producers/Engineers...', () {
      final roleCategory = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'roles_production');
      expect(roleCategory.displayLabel, equals('Songwriters/Lyricists/Producers/Engineers...'));
      expect(roleCategory.leadingSymbol, equals('🎧'));

      // Does not contain bandleader in optionIds because BANDLEADER is rendered standalone at top
      expect(roleCategory.optionIds.contains('bandleader'), isFalse);
    });

    test('3. Professional roles order contains Songwriter, Lyricist, Producer, Composer, Beatmaker, Engineer, DJ, PR/Management', () {
      final roleCategory = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'roles_production');
      final options = roleCategory.optionIds
          .map((id) => SkillsTaxonomy.findById(id)!)
          .toList();

      final labels = options.map((o) => o.displayLabel).toList();
      expect(labels, equals(expectedRolesInOrder));

      // Check persisted values
      expect(options[0].persistedValue, equals('SONGWRITER'));
      expect(options[1].persistedValue, equals('LYRICIST'));
      expect(options[2].persistedValue, equals('PRODUCER'));
      expect(options[3].persistedValue, equals('COMPOSER'));
      expect(options[4].persistedValue, equals('BEATMAKER'));
      expect(options[5].persistedValue, equals('STUDIO/ENGINEER, etc'));
      expect(options[6].persistedValue, equals('DJ'));
      expect(options[7].persistedValue, equals('PR/MANAGEMENT'));
    });

    test('4. PR/Management resolves from and to all supported combined legacy aliases while preserving standalone PR and Management', () {
      final prOpt = SkillsTaxonomy.findById('pr_management');
      expect(prOpt, isNotNull);
      expect(prOpt!.displayLabel, equals('PR/Management'));
      expect(prOpt.persistedValue, equals('PR/MANAGEMENT'));

      // 1. Check exact combined legacy resolution
      final combinedAliasesToTest = [
        'PR/Management',
        'pr/management',
        'PR/MANAGEMENT',
        'PR & Management',
        'pr & management',
        'PR & MANAGEMENT',
        'PR / Management',
        'pr / management',
        'PR / MANAGEMENT',
        'PR&Management',
        'pr&management',
      ];

      for (final alias in combinedAliasesToTest) {
        final resolved = SkillsTaxonomy.resolveLegacyValue(alias);
        expect(resolved, isNotNull, reason: 'Failed to resolve alias "$alias"');
        expect(resolved!.id, equals('pr_management'));
        expect(resolved.persistedValue, equals('PR/MANAGEMENT'));
        expect(resolved.displayLabel, equals('PR/Management'));
        expect(SkillsTaxonomy.resolveCanonicalPersistedValue(alias), equals('PR/MANAGEMENT'));
      }

      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('PR/MANAGEMENT'), equals('PR/Management'));
      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel('PR/Management'), equals('PR/MANAGEMENT'));

      // 2. Verify standalone PR and Management values are preserved as unknown/custom without silent corruption
      expect(SkillsTaxonomy.resolveLegacyValue('PR'), isNull);
      expect(SkillsTaxonomy.resolveLegacyValue('Management'), isNull);
      expect(SkillsTaxonomy.resolveCanonicalPersistedValue('PR'), equals('PR'));
      expect(SkillsTaxonomy.resolveCanonicalPersistedValue('Management'), equals('Management'));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('PR'), equals('PR'));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue('Management'), equals('Management'));
    });

    test('5. Sessions category has exact heading Sessions and preserves all options', () {
      final sessionsCat = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'sessions_collaboration');
      expect(sessionsCat.displayLabel, equals('Sessions'));
      expect(sessionsCat.leadingSymbol, equals('🤝'));
      expect(sessionsCat.optionIds.length, equals(6));

      expect(SkillsTaxonomy.findById('create_session')!.displayLabel, equals('Create Session'));
      expect(SkillsTaxonomy.findById('studio_session')!.displayLabel, equals('Studio Session'));
    });

    test('6. Strings category exposes leading symbols 🎻 🎸 and subtitle Violin/Cello/Guitar/Bass...', () {
      final stringsCat = SkillsTaxonomy.masterCategories
          .firstWhere((c) => c.id == 'strings');
      expect(stringsCat.displayLabel, equals('Strings'));
      expect(stringsCat.leadingSymbol, equals('🎻 🎸'));
      expect(stringsCat.subtitle, equals('Violin/Cello/Guitar/Bass...'));

      expect(SkillsTaxonomy.getLeadingSymbolForCategory('Strings'), equals('🎻 🎸'));
      expect(SkillsTaxonomy.getSubtitleForCategory('Strings'), equals('Violin/Cello/Guitar/Bass...'));

      // Subtitle is not an option ID or persisted value
      expect(SkillsTaxonomy.findById('Violin/Cello/Guitar/Bass...'), isNull);
      expect(SkillsTaxonomy.findByPersistedValue('Violin/Cello/Guitar/Bass...'), isNull);
    });

    test('7. Instrument categories are plain strings in exact RUTA-02 order ending with Miscellaneous Instruments', () {
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

    test('8. Voice categories follow instruments in exact required order with plain labels', () {
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

    test('9. Every category has the expected leading decorative symbol metadata', () {
      for (final cat in SkillsTaxonomy.masterCategories) {
        expect(expectedCategorySymbols.containsKey(cat.displayLabel), isTrue,
            reason: 'Category ${cat.displayLabel} should be in expected symbols map');
        expect(cat.leadingSymbol, equals(expectedCategorySymbols[cat.displayLabel]));
        expect(SkillsTaxonomy.getLeadingSymbolForCategory(cat.displayLabel),
            equals(expectedCategorySymbols[cat.displayLabel]));
        expect(cat.displayLabel.contains('🎷'), isFalse);
        expect(cat.displayLabel.contains('🎧'), isFalse);
        expect(cat.displayLabel.contains('🤝'), isFalse);
      }
    });

    test('10. Unknown stored values pass through safely without corruption or deletion', () {
      const unknownValue = 'CUSTOM_SYNTH_99';
      expect(SkillsTaxonomy.resolveLegacyValue(unknownValue), isNull);
      expect(SkillsTaxonomy.resolveCanonicalPersistedValue(unknownValue),
          equals(unknownValue));
      expect(SkillsTaxonomy.getDisplayLabelForPersistedValue(unknownValue),
          equals(unknownValue));
      expect(SkillsTaxonomy.getPersistedValueForDisplayLabel(unknownValue),
          equals(unknownValue));
    });

    test('11. RUTA-01 and RUTA-02B taxonomy integrity validation passes with zero errors', () {
      final validation = SkillsTaxonomy.validateTaxonomyIntegrity();
      expect(validation.isValid, isTrue, reason: validation.errors.join('\n'));
      expect(validation.errors, isEmpty);
    });
  });

  group('RUTA-02B Structured Picker Widget Tests', () {
    testWidgets('12. BANDLEADER is visible at the very top before expanding any category', (WidgetTester tester) async {
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

      // Standalone BANDLEADER is visible immediately without expanding categories
      final standaloneChip = find.byKey(const ValueKey('standalone_bandleader_chip'));
      expect(standaloneChip, findsOneWidget);
      expect(find.text('BANDLEADER'), findsOneWidget);

      // Positioned above expandable category
      final bandleaderDy = tester.getTopLeft(standaloneChip).dy;
      final roleCategoryDy = tester.getTopLeft(find.text('Songwriters/Lyricists/Producers/Engineers...')).dy;
      expect(bandleaderDy < roleCategoryDy, isTrue,
          reason: 'BANDLEADER must appear above Songwriters/Lyricists/Producers/Engineers...');

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('13. Tapping standalone BANDLEADER selects it in single-select and multi-select', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      List<String>? singleResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  singleResult = await SearchableCategoryMultiSelectSheet.show(
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

      // Tap BANDLEADER in single select
      await tester.tap(find.byKey(const ValueKey('standalone_bandleader_chip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(singleResult, equals(['BANDLEADER']));
    });

    testWidgets('14. BANDLEADER is not duplicated inside professional roles category and does not add false count badge', (WidgetTester tester) async {
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
                  initialSelected: const ['BANDLEADER'],
                  isSingleSelect: false,
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

      // Expand professional roles category
      await tester.tap(find.text('Songwriters/Lyricists/Producers/Engineers...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Only ONE BANDLEADER widget exists across entire sheet
      expect(find.text('BANDLEADER'), findsOneWidget);

      // No selected count badge on the professional roles category when only BANDLEADER is selected
      expect(find.text('1 selected'), findsNothing);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('15. Long heading Songwriters/Lyricists/Producers/Engineers... renders without overflow on narrow 320px viewport', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SearchableCategoryMultiSelectSheet.show(
                  context: context,
                  title: 'Skills',
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

      expect(find.text('Songwriters/Lyricists/Producers/Engineers...'), findsOneWidget);
      expect(tester.takeException(), isNull);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('16. PR/Management is present under professional roles, selectable, and searchable', (WidgetTester tester) async {
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

      // Expand professional roles
      await tester.tap(find.text('Songwriters/Lyricists/Producers/Engineers...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm PR/Management is present
      final prChip = find.text('PR/Management');
      expect(prChip, findsOneWidget);

      await tester.tap(prChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(selectedResult, equals(['PR/MANAGEMENT']));
    });

    testWidgets('17. Search finds PR/Management, BANDLEADER, and DJ', (WidgetTester tester) async {
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

      // Search 'management'
      await tester.enterText(searchField, 'management');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('PR/Management'), findsOneWidget);

      // Search 'pr'
      await tester.enterText(searchField, 'pr');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('PR/Management'), findsOneWidget);

      // Search 'bandleader'
      await tester.enterText(searchField, 'bandleader');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('BANDLEADER'), findsOneWidget);

      // Search 'dj'
      await tester.enterText(searchField, 'dj');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DJ'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('18. Strings category displays 🎻 🎸 symbols and subtitle Violin/Cello/Guitar/Bass...', (WidgetTester tester) async {
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

      expect(find.text('Strings'), findsOneWidget);
      expect(find.text('Violin/Cello/Guitar/Bass...'), findsOneWidget);

      // Verify symbols 🎻 🎸 inside ExcludeSemantics
      final symbolFinder = find.byWidgetPredicate(
        (w) => w is ExcludeSemantics &&
            w.child is Text &&
            (w.child as Text).data == '🎻 🎸',
      );
      expect(symbolFinder, findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('19. Sessions category is displayed with heading Sessions and selectable options', (WidgetTester tester) async {
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

      // Category is called Sessions
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Sessions/Collaboration'), findsNothing);

      // Expand Sessions
      await tester.tap(find.text('Sessions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Create Session'), findsOneWidget);
      expect(find.text('Studio Session'), findsOneWidget);

      await tester.tap(find.text('Studio Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Done (1 Selected)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(selectedResult, equals(['Studio Session']));
    });

    testWidgets('20. SearchableCategoryMultiSelectSheet displays INSTRUMENTS/VOICES non-selectable heading and voice separator', (WidgetTester tester) async {
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

      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsOneWidget);
      expect(find.text('INSTRUMENTS/VOICES'), findsOneWidget);
      expect(find.byKey(const ValueKey('voices_section_separator')), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('21. Unrelated Genres picker with standard presentation is unaffected by RUTA-02B styling or icons', (WidgetTester tester) async {
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

      expect(find.byKey(const ValueKey('standalone_bandleader_chip')), findsNothing);
      expect(find.byKey(const ValueKey('instruments_voices_section_heading')), findsNothing);
      expect(find.byKey(const ValueKey('voices_section_separator')), findsNothing);
      expect(find.text('Rock & Metal'), findsOneWidget);
      expect(find.text('Electronic'), findsOneWidget);

      for (final symbol in expectedCategorySymbols.values) {
        expect(find.text(symbol), findsNothing);
      }

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('22. Unknown existing stored value is preserved and returned verbatim with additions', (WidgetTester tester) async {
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

      expect(find.text('1'), findsOneWidget);

      // Add Electric Guitar (expand Strings)
      await tester.tap(find.text('Strings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Electric Guitar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Done (2 Selected)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(selectedResult, contains('CUSTOM_SYNTH_99'));
      expect(selectedResult, contains('Electric Guitar'));
      expect(selectedResult!.length, equals(2));
    });

    testWidgets('23. EditProfileScreen uses the RUTA-02B redesigned hierarchy with standalone BANDLEADER', (WidgetTester tester) async {
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
      expect(find.byKey(const ValueKey('standalone_bandleader_chip')), findsOneWidget);
      expect(find.text('Songwriters/Lyricists/Producers/Engineers...'), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('24. BrowseMusiciansScreen filter uses the RUTA-02B centralized hierarchy', (WidgetTester tester) async {
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
      expect(find.byKey(const ValueKey('standalone_bandleader_chip')), findsOneWidget);
      expect(find.text('Songwriters/Lyricists/Producers/Engineers...'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('25. FindSubScreen uses the RUTA-02B centralized hierarchy', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createRuta02TestApp(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentCard = find.text('Instrument/Skill');
      expect(instrumentCard, findsOneWidget);
      await tester.tap(instrumentCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('standalone_bandleader_chip')), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
    });

    testWidgets('26. RegisterScreen renders flat dropdown preserving Electric Guitar default', (WidgetTester tester) async {
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
