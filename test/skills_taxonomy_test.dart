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
import 'package:musicians_flutter/views/collabs_landing_screen.dart';
import 'package:musicians_flutter/views/create_session_screen.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/find_collabs_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/producer_search_screen.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockTaxonomyFirebaseService extends FirebaseService {
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'test_user_taxonomy',
      displayName: 'Taxonomy Tester',
      email: 'test@example.com',
      instruments: ['Electric Guitar'],
      genres: ['Rock'],
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [
      UserProfile(
        userId: 'u1',
        displayName: 'Alice Trumpet',
        userType: 'Trumpet',
        instruments: ['Trumpet'],
      ),
      UserProfile(
        userId: 'u2',
        displayName: 'Bob Piccolo Trumpet',
        userType: 'Piccolo Trumpet',
        instruments: ['Piccolo Trumpet'],
      ),
    ];
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];
}

class MockAppStateForTaxonomyTest extends AppState {
  @override
  final FirebaseService firebaseService = MockTaxonomyFirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_taxonomy',
        displayName: 'Taxonomy Tester',
        email: 'test@example.com',
        instruments: ['Electric Guitar'],
        genres: ['Rock'],
      );

  @override
  String? get currentUserId => 'test_user_taxonomy';
}

Widget createTaxonomyTestApp(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForTaxonomyTest(),
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

  // Explicit RUTA-02B golden categories fixture
  const expectedMasterCategoryLabels = [
    'Songwriters/Lyricists/Producers/Engineers...',
    'Sessions',
    'Woodwinds',
    'Brass',
    'Strings',
    'Keyboards',
    'Percussion',
    'Miscellaneous Instruments',
    'Voices (Choir)',
    'Voices (Popular Music)',
    'Miscellaneous Voices',
  ];

  const expectedFlatRegistrationItems = [
    'BANDLEADER',
    'SONGWRITER',
    'PRODUCER',
    'COMPOSER',
    'LYRICIST',
    'BEATMAKER',
    'STUDIO/ENGINEER, etc',
    'DJ',
    'INSTRUMENTS/VOICES',
    'Recorder',
    'Flute',
    'Oboe',
    'Clarinet',
    'Bassoon',
    'Soprano Sax',
    'Alto Sax',
    'Tenor Sax',
    'Bari Sax',
    'Trumpet',
    'Cornet',
    'Trombone',
    'French Horn',
    'Euphonium',
    'Tuba',
    'Violin',
    'Viola',
    'Cello',
    'Contrabass',
    'Acoustic Guitar',
    'Electric Guitar',
    'Electric Bass',
    'Harp',
    'Piano',
    'Keyboard/Synth',
    'Harpsichord',
    'Organ (Hammond)',
    'Drums',
    'Latin Percussion (congas, timbales, etc)',
    'Classical Percussion (timpani, cymbals, etc)',
    'Soprano',
    'Alto',
    'Tenor',
    'Baritone',
    'Bass',
    'Mezzo Soprano',
    'Contralto',
    'Counter Tenor',
    'Male Lead Vocals',
    'Female Lead vocals',
    'Male Backing vocals',
    'Female Backing vocals',
    'Soprano Recorder',
    'Alto Recorder',
    'Tenor Recorder',
    'Bass Recorder',
    'Piccolo Flute',
    'Alto Flute',
    'Bass Flute',
    'English Horn',
    'Eb Clarinet',
    'Alto Clarinet',
    'Bass Clarinet',
    'Contra Bassoon',
    'Piccolo Trumpet',
    'Alto Trombone',
    'Viola da Gamba',
    'Steel Guitar',
    'Steel Pan',
  ];

  const expectedCreateSessionInstruments = [
    'Electric Guitar',
    'Electric Bass',
    'Drums',
    'Keyboard/Synth',
    'Piano',
    'Acoustic Guitar',
    'Vocalist',
  ];

  const expectedProducerInstruments = [
    'All Instruments',
    'Vocalist',
    'Guitar',
    'Bass',
    'Drums',
    'Piano',
    'Keyboard',
    'Saxophone',
    'Trumpet',
    'Violin',
    'Cello',
    'Other',
  ];

  group('SkillsTaxonomy Unit & Integrity Tests', () {
    test('1. Every selectable option has a non-empty stable ID', () {
      for (final option in SkillsTaxonomy.allOptions.values) {
        expect(option.id.trim(), isNotEmpty);
      }
    });

    test('2. Every selectable option has a non-empty persisted value', () {
      for (final option in SkillsTaxonomy.allOptions.values) {
        expect(option.persistedValue.trim(), isNotEmpty);
      }
    });

    test('3. Internal IDs are unique and taxonomy passes integrity validation', () {
      final validation = SkillsTaxonomy.validateTaxonomyIntegrity();
      expect(validation.isValid, isTrue, reason: validation.errors.join('\n'));
      expect(validation.errors, isEmpty);
    });

    test('4. Category option references resolve to real options without duplicates', () {
      for (final category in SkillsTaxonomy.masterCategories) {
        final seen = <String>{};
        for (final optionId in category.optionIds) {
          expect(SkillsTaxonomy.findById(optionId), isNotNull,
              reason: 'Category ${category.id} references missing option $optionId');
          expect(seen.contains(optionId), isFalse,
              reason: 'Category ${category.id} contains duplicate option $optionId');
          seen.add(optionId);
        }
      }
    });

    test('5. Context output is deterministic across multiple calls', () {
      final call1 = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.editProfile);
      final call2 = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.editProfile);
      expect(call1, equals(call2));

      final reg1 = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.register);
      final reg2 = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.register);
      expect(reg1, equals(reg2));
    });

    test('6. Returned collections cannot mutate the source taxonomy', () {
      final categories = SkillsTaxonomy.categoriesFor(SkillTaxonomyContext.editProfile);
      expect(() => (categories as dynamic).add(categories.first), throwsUnsupportedError);

      final categoryMap = SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile);
      expect(() => (categoryMap as dynamic)['new_key'] = ['value'], throwsUnsupportedError);

      final persistedValues = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.register);
      expect(() => (persistedValues as dynamic).add('New Item'), throwsUnsupportedError);
    });

    test('7. Exact lookup resolves known canonical persisted values', () {
      final guitar = SkillsTaxonomy.findByPersistedValue('Electric Guitar');
      expect(guitar, isNotNull);
      expect(guitar!.id, equals('electric_guitar'));
      expect(guitar.kind, equals(SkillOptionKind.instrument));

      final vocals = SkillsTaxonomy.findByPersistedValue('Female Lead vocals');
      expect(vocals, isNotNull);
      expect(vocals!.id, equals('female_lead_vocals'));
      expect(vocals.kind, equals(SkillOptionKind.voice));

      final leader = SkillsTaxonomy.findByPersistedValue('BANDLEADER');
      expect(leader, isNotNull);
      expect(leader!.id, equals('bandleader'));
      expect(leader.kind, equals(SkillOptionKind.role));
    });

    test('8. Alias lookup handles casing and trims whitespace safely', () {
      final res1 = SkillsTaxonomy.resolveLegacyValue('  female lead vocals  ');
      expect(res1, isNotNull);
      expect(res1!.id, equals('female_lead_vocals'));

      final res2 = SkillsTaxonomy.resolveLegacyValue('mix engineer');
      expect(res2, isNotNull);
      expect(res2!.id, equals('studio_engineer_etc'));

      final res3 = SkillsTaxonomy.resolveLegacyValue('BANDLEADER');
      expect(res3, isNotNull);
      expect(res3!.id, equals('bandleader'));
    });

    test('9. Distinct instruments remain distinct (no false prefix merges)', () {
      final trumpet = SkillsTaxonomy.resolveLegacyValue('Trumpet');
      final piccoloTrumpet = SkillsTaxonomy.resolveLegacyValue('Piccolo Trumpet');
      expect(trumpet, isNotNull);
      expect(piccoloTrumpet, isNotNull);
      expect(trumpet!.id, isNot(equals(piccoloTrumpet!.id)));
      expect(trumpet.id, equals('trumpet'));
      expect(piccoloTrumpet.id, equals('piccolo_trumpet'));

      final alto = SkillsTaxonomy.resolveLegacyValue('Alto');
      final altoSax = SkillsTaxonomy.resolveLegacyValue('Alto Sax');
      expect(alto, isNotNull);
      expect(altoSax, isNotNull);
      expect(alto!.id, isNot(equals(altoSax!.id)));
      expect(alto.id, equals('alto'));
      expect(altoSax.id, equals('alto_sax'));
    });

    test('10. Unknown stored values are preserved safely without corruption', () {
      const unknownValue = 'Custom Rare Folk Instrument';
      final option = SkillsTaxonomy.resolveLegacyValue(unknownValue);
      expect(option, isNull);

      final canonical = SkillsTaxonomy.resolveCanonicalPersistedValue(unknownValue);
      expect(canonical, equals(unknownValue));
    });

    test('11. Category headings are not accidentally converted into real instruments', () {
      final headerOpt = SkillsTaxonomy.findById('instruments_voices_header');
      expect(headerOpt, isNotNull);
      expect(headerOpt!.kind, equals(SkillOptionKind.legacyHeader));
      expect(headerOpt.persistedValue, equals('INSTRUMENTS/VOICES'));
    });

    test('12. Edit Profile context reproduces exact pre-RUTA-01 category order and options', () {
      final categories = SkillsTaxonomy.categoriesFor(SkillTaxonomyContext.editProfile);
      final labels = categories.map((c) => c.displayLabel).toList();
      expect(labels, equals(expectedMasterCategoryLabels));

      final categoryMap = SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile);
      expect(categoryMap.keys.toList(), equals(expectedMasterCategoryLabels));
      expect(categoryMap['Songwriters/Lyricists/Producers/Engineers...']!.length, equals(8));
      expect(categoryMap['Sessions']!.length, equals(6));
      expect(categoryMap['Woodwinds']!.length, equals(9));
      expect(categoryMap['Brass']!.length, equals(6));
      expect(categoryMap['Strings']!.length, equals(8));
      expect(categoryMap['Keyboards']!.length, equals(4));
      expect(categoryMap['Percussion']!.length, equals(3));
      expect(categoryMap['Miscellaneous Instruments']!.length, equals(17));
      expect(categoryMap['Voices (Choir)']!.length, equals(5));
      expect(categoryMap['Voices (Popular Music)']!.length, equals(4));
      expect(categoryMap['Miscellaneous Voices']!.length, equals(3));
    });

    test('13. Registration context reproduces exact flat list and default', () {
      final flat = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.register);
      expect(flat, equals(expectedFlatRegistrationItems));
      expect(flat.contains('Electric Guitar'), isTrue);
    });

    test('14. Create Session context remains a reduced subset', () {
      final insts = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.createSession);
      expect(insts, equals(expectedCreateSessionInstruments));
      expect(SkillsTaxonomy.sessionRoles, equals(['songwriter', 'producer', 'engineer', 'vocalist', 'musician']));
    });

    test('15. Producer Search context retains its existing subset', () {
      final insts = SkillsTaxonomy.persistedValuesFor(SkillTaxonomyContext.producerSearch);
      expect(insts, equals(expectedProducerInstruments));
    });

    test('16. UserProfile string serialization remains 100% compatible', () {
      final profile = UserProfile(
        userId: 'u_test',
        displayName: 'Test User',
        userType: 'Electric Guitar',
        instruments: ['Electric Guitar', 'Acoustic Guitar'],
        collabRoles: ['BANDLEADER', 'PRODUCER'],
      );

      final json = profile.toJson();
      expect(json['UserType'], equals('Electric Guitar'));
      expect(json['Instruments'], equals(['Electric Guitar', 'Acoustic Guitar']));
      expect(json['CollabRoles'], equals(['BANDLEADER', 'PRODUCER']));

      final restored = UserProfile.fromJson(json);
      expect(restored.userType, equals('Electric Guitar'));
      expect(restored.instruments, equals(['Electric Guitar', 'Acoustic Guitar']));
      expect(restored.collabRoles, equals(['BANDLEADER', 'PRODUCER']));
    });
  });

  group('SkillsTaxonomy UI & Widget Consumer Tests', () {
    testWidgets('17. EditProfileScreen opens picker with master categories', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final primaryField = find.text('Primary Skill/Talent (Select 1)');
      expect(primaryField, findsOneWidget);

      await tester.tap(primaryField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      for (final cat in expectedMasterCategoryLabels) {
        if (cat.contains('(') && cat.contains('Voices')) {
          expect(
            find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText() == cat),
            findsOneWidget,
          );
        } else {
          expect(find.text(cat), findsOneWidget);
        }
      }

      // Single select sheet closes via pop or item tap
      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('18. RegisterScreen renders flat dropdown with exact default and user types', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const RegisterScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Electric Guitar'), findsOneWidget);
    });

    testWidgets('19. BrowseMusiciansScreen opens filter picker with master categories', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const BrowseMusiciansScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final filterCard = find.text('Filter by Skills & Instruments...');
      expect(filterCard, findsOneWidget);
      await tester.tap(filterCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('Woodwinds'), findsOneWidget);
      expect(find.text('Brass'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('20. CollabsLandingScreen opens collaboration area picker with Sessions category', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const CollabsLandingScreen()));
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
    });

    testWidgets('21. FindCollabsScreen opens category picker with master categories', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const FindCollabsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final collabBox = find.text('COLLABORATION AREA');
      expect(collabBox, findsOneWidget);

      await tester.tap(collabBox);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('Songwriters/Lyricists/Producers/Engineers...'), findsOneWidget);
      expect(find.text('Woodwinds'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('22. FindSubScreen opens instrument picker with master categories', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final instrumentTitle = find.text('INSTRUMENT/SKILLS');
      expect(instrumentTitle, findsOneWidget);

      await tester.tap(instrumentTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('Brass'), findsOneWidget);

      // Single select sheet closes via pop or option selection
      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    testWidgets('23. CreateSessionScreen displays reduced instruments when musician role is selected', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const CreateSessionScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final musicianRoleChip = find.text('Musician');
      expect(musicianRoleChip, findsOneWidget);

      await tester.tap(musicianRoleChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Electric Guitar'), findsOneWidget);
      expect(find.text('Electric Bass'), findsOneWidget);
      expect(find.text('Drums'), findsOneWidget);
      expect(find.text('Keyboard/Synth'), findsOneWidget);
      expect(find.text('Piano'), findsOneWidget);
      expect(find.text('Acoustic Guitar'), findsOneWidget);
      expect(find.text('Vocalist'), findsAtLeastNWidgets(1));
    });

    testWidgets('24. ProducerSearchScreen displays target instruments after loading', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTaxonomyTestApp(const ProducerSearchScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Vocalist'), findsAtLeastNWidgets(1));
    });
  });
}
