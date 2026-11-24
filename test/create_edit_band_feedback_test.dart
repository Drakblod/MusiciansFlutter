import 'package:musicians_flutter/config/feature_toggles.dart';
import 'package:musicians_flutter/widgets/custom_top_bar.dart';
import 'package:musicians_flutter/widgets/city_location_picker_field.dart';
import 'package:musicians_flutter/models/city_location.dart';
import 'package:musicians_flutter/utils/catalogue_profiles.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';
import 'international_city_picker_01_test.dart' as picker;
import 'international_city_forms_01_test.dart' show chooseBerlin;
import 'support/bounded_ui_pump.dart';
import 'band_musical_role_test.dart' show chooseMusicalRole, inMusicalRolePicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:provider/provider.dart';

class MockBandFirebaseService extends FirebaseService {
  @override
  Stream<bool> subscribeToBandProfileAccess(String bandId) => Stream.value(true);

  List<BandMember> members = [];
  Band? createdBand;
  Band? updatedBand;
  List<UserProfile> availableMembers = [];

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => availableMembers;

  @override
  Future<void> createBandAsync(String userId, Band band) async {
    createdBand = band;
  }

  @override
  Future<void> updateBandAsync(String bandId, Band band) async {
    updatedBand = band;
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return members;
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return null;
  }
}

class MockBandAppState extends AppState {
  final MockBandFirebaseService mockService;

  MockBandAppState(this.mockService);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => 'test_user_123';
  String? selectedBand;
  @override
  String? get activeBandId => selectedBand;

  @override
  Future<void> refreshProfile() async {}

  @override
  void selectBand(String bandId, String bandName) {selectedBand = bandId;}
}

Widget createTestWidget(Widget child, [MockBandAppState? appState]) {
  final state = appState ?? MockBandAppState(MockBandFirebaseService());
  if (child is EditBandInfoScreen) {state.selectBand(child.band.id!, child.band.name!);state.mockService.members = child.band.membersBand.values.toList();}
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      key: UniqueKey(),
      home: CitySearchProviderScope(provider: picker.FakeCities(), child: child),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('Create and Edit Band Focused Owner-Feedback Tests', () {
    testWidgets('a custom band genre saves, reopens, changes and can be removed',
        (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = MockBandFirebaseService();
      final state = MockBandAppState(service);
      final genreField = find.text('GENRES/BAND TYPES');
      final sheet = find.byType(SearchableCategoryMultiSelectSheet);
      final dialog = find.byType(AlertDialog);
      final customInput =
          find.descendant(of: dialog, matching: find.byType(TextFormField));
      final saveCustom =
          find.descendant(of: dialog, matching: find.text('Save'));

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await pumpUiTransitions(tester);
      }

      Future<void> reopen(Band saved) async {
        // The server assigns the creator's membership when creating the band.
        final stored = saved.toJson()
          ..['Members_band'] = {
            'test_user_123': {'Role': 'Leader', 'Status': 'active'},
          };
        final band = Band.fromJson(stored, 'genre_band');
        await tester.pumpWidget(
          createTestWidget(EditBandInfoScreen(band: band), state),
        );
        await pumpUiTransitions(tester);
      }

      await tester.pumpWidget(createTestWidget(const CreateBandScreen(), state));
      await pumpUiTransitions(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter band name'),
        'Genre Band',
      );
      await chooseBerlin(tester);
      await tap(genreField);
      await tap(find.text('Other'));

      for (final input in ['   ', ' Other ']) {
        await tester.enterText(customInput, input);
        await tap(saveCustom);
        expect(find.text('Enter a name.'), findsOneWidget);
      }
      await tester.enterText(customInput, 'x' * 201);
      await tap(saveCustom);
      expect(find.text('Use at most 200 characters.'), findsOneWidget);
      await tester.enterText(customInput, '  bLuEs  ');
      await tap(saveCustom);
      expect(find.text('Choose this option from the list.'), findsOneWidget);

      const original = 'Nordic Folk, Jazz';
      await tester.enterText(customInput, '  $original  ');
      await tap(saveCustom);
      expect(dialog, findsNothing);
      await tap(find.text('Other'));
      await tester.enterText(customInput, '  nordic folk, jazz  ');
      await tap(saveCustom);
      expect(find.text('This option is already selected.'), findsOneWidget);
      await tap(find.descendant(of: dialog, matching: find.text('Cancel')));
      await tap(find.descendant(of: sheet, matching: find.text('Done (1 Selected)')));

      await selectBlues(tester, genreField);
      await tap(find.text('Save Band'));
      final created = service.createdBand!;
      expect(created.toJson()['Genres'], [original, 'Blues']);
      expect(created.toJson()['Style_band'], [original, 'Blues']);
      expect(created.toJson()['EnsembleType'], original);

      await reopen(created);
      await tap(genreField);
      await tap(find.descendant(of: sheet, matching: find.text(original)));
      expect(tester.widget<TextFormField>(customInput).initialValue, original);
      const updated = 'Nordic Chamber Jazz';
      await tester.enterText(customInput, updated);
      await tap(saveCustom);
      await tap(find.descendant(of: sheet, matching: find.text('Done (2 Selected)')));
      await tap(find.text('Save Changes'));
      final edited = service.updatedBand!;
      expect(edited.toJson()['Genres'], [updated, 'Blues']);
      expect(edited.toJson()['Style_band'], [updated, 'Blues']);
      expect(edited.toJson()['EnsembleType'], updated);

      await reopen(edited);
      await tap(genreField);
      await tap(find.byTooltip('Remove $updated'));
      await tap(find.descendant(of: sheet, matching: find.text('Done (1 Selected)')));
      await tap(find.text('Save Changes'));
      expect(service.updatedBand!.toJson()['Genres'], ['Blues']);
      expect(service.updatedBand!.toJson()['Style_band'], ['Blues']);
      expect(service.updatedBand!.toJson()['EnsembleType'], 'Blues');
    });

    testWidgets('removing the only custom genre clears its derived band type',
        (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const custom = 'Northern Chamber Folk';
      final service = MockBandFirebaseService();
      final band = Band(
        id: 'genre_band',
        name: 'Genre Band',
        genres: [custom],
        styleBand: [custom],
        ensembleType: custom,
        membersBand: {
          'test_user_123':
              BandMember(userId: 'test_user_123', role: 'Leader', status: 'active'),
        },
      );
      await tester.pumpWidget(
        createTestWidget(EditBandInfoScreen(band: band), MockBandAppState(service)),
      );
      await pumpUiTransitions(tester);

      final field = find.text('GENRES/BAND TYPES');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await pumpUiTransitions(tester);
      await tester.tap(find.byTooltip('Remove $custom'));
      await pumpUiTransitions(tester);
      await tester.tap(find.text('Done'));
      await pumpUiTransitions(tester);
      await tester.tap(find.text('Save Changes'));
      await pumpUiTransitions(tester);

      final saved = service.updatedBand!;
      expect(saved.toJson()['Genres'], isEmpty);
      expect(saved.toJson()['Style_band'], isEmpty);
      expect(saved.toJson()['EnsembleType'], 'Band');
    });

    testWidgets('changing or removing a custom genre preserves a separate band type',
        (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const original = 'Northern Chamber Folk';
      const updated = 'Nordic Chamber Jazz';
      const separateType = 'Choir';
      final service = MockBandFirebaseService();
      final state = MockBandAppState(service);

      Future<void> openPicker(List<String> genres) async {
        final band = Band(
          id: 'genre_band',
          name: 'Genre Band',
          genres: genres,
          ensembleType: separateType,
          membersBand: {
            'test_user_123':
                BandMember(userId: 'test_user_123', role: 'Leader', status: 'active'),
          },
        );
        await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band), state));
        await pumpUiTransitions(tester);
        final field = find.text('GENRES/BAND TYPES');
        await tester.ensureVisible(field);
        await tester.tap(field);
        await pumpUiTransitions(tester);
      }

      Future<void> saveChanges(String doneLabel) async {
        await tester.tap(find.text(doneLabel));
        await pumpUiTransitions(tester);
        await tester.tap(find.text('Save Changes'));
        await pumpUiTransitions(tester);
        expect(service.updatedBand!.ensembleType, separateType);
      }

      await openPicker([original, 'Blues']);
      await tester.tap(find.descendant(
        of: find.byType(SearchableCategoryMultiSelectSheet),
        matching: find.text(original),
      ));
      await pumpUiTransitions(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        updated,
      );
      await tester.tap(find.text('Save'));
      await pumpUiTransitions(tester);
      await saveChanges('Done (2 Selected)');
      expect(service.updatedBand!.genres, [updated, 'Blues']);

      await openPicker(service.updatedBand!.genres);
      await tester.tap(find.byTooltip('Remove $updated'));
      await pumpUiTransitions(tester);
      await saveChanges('Done (1 Selected)');
      expect(service.updatedBand!.genres, ['Blues']);
    });

    testWidgets('Create Band prompts separately and saves both selected musical roles', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = MockBandFirebaseService()..availableMembers = CatalogueProfiles.users({
        'one': {
          'DisplayName': 'Alex Trumpet',
          'Nickname': 'Different nickname',
          'MainInstrument': 'Drums',
          'Instruments': ['Drums', 'Keyboard/Synth', 'Vocalist'],
        },
        'two': {'DisplayName': 'Kim Vocalist'},
      });
      await tester.pumpWidget(createTestWidget(const CreateBandScreen(), MockBandAppState(service)));
      await pumpUiTransitions(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Enter band name'), 'Two Parts');
      await chooseBerlin(tester);
      await tester.tap(find.text('Add Member'));
      await pumpUiTransitions(tester);
      expect(find.text('Alex Trumpet'), findsOneWidget);
      expect(find.text('Kim Vocalist'), findsOneWidget);
      expect(find.text('Different nickname'), findsNothing);
      expect(find.text('Primary Skill: Drums'), findsOneWidget);
      expect(find.text('Secondary Skills: Keyboard/Synth, Vocalist'), findsOneWidget);
      expect(find.textContaining('Primary Skill:'), findsOneWidget);
      expect(find.textContaining('Secondary Skills:'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle).first);
      await pumpUiTransitions(tester);
      expect(find.text('Which instrument or role would you like Alex Trumpet to take on in this particular band?'), findsOneWidget);
      expect(inMusicalRolePicker(find.text('Primary Skill: Drums')), findsOneWidget);
      expect(inMusicalRolePicker(find.text('Secondary Skills: Keyboard/Synth, Vocalist')), findsOneWidget);
      expect(tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet)).initialSelected, isEmpty);
      await chooseMusicalRole(tester, 'Trumpet');
      await pumpUiTransitions(tester);
      expect(find.text('Added'), findsOneWidget);

      expect(find.byIcon(Icons.add_circle), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_circle));
      await pumpUiTransitions(tester);
      expect(find.text('Which instrument or role would you like Kim Vocalist to take on in this particular band?'), findsOneWidget);
      expect(inMusicalRolePicker(find.textContaining('Primary Skill:')), findsNothing);
      expect(inMusicalRolePicker(find.textContaining('Secondary Skills:')), findsNothing);
      await chooseMusicalRole(tester, 'BANDLEADER');
      await pumpUiTransitions(tester);
      expect(find.text('Added'), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await pumpUiTransitions(tester);
      await tester.ensureVisible(find.text('Save Band'));
      await tester.tap(find.text('Save Band'));
      await pumpUiTransitions(tester);

      final members = service.createdBand!.membersBand;
      expect(members.keys, unorderedEquals(['one','two']));
      expect(members['one']!.musicalRole, 'Trumpet');
      expect(members['two']!.musicalRole, 'BANDLEADER');
      expect(members.values.map((member) => member.role), everyElement('Member'));
    });

    testWidgets('Create Band shows profile skills on a narrow screen without inventing a name', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      final service = MockBandFirebaseService()..availableMembers = CatalogueProfiles.users({
        'narrow': {
          'DisplayName': 'Robin Parker',
          'UserType': 'Drums',
          'Instruments': ['Drums', 'Keyboard/Synth', 'Music Production', 'Electric Guitar'],
        },
        'unnamed': {'UserType': 'Bass'},
      });
      await tester.pumpWidget(createTestWidget(const CreateBandScreen(), MockBandAppState(service)));
      await pumpUiTransitions(tester);
      final addMember = find.text('Add Member');
      await tester.ensureVisible(addMember);
      await tester.tap(addMember);
      await pumpUiTransitions(tester);

      const secondary = 'Secondary Skills: Keyboard/Synth, Music Production, Electric Guitar';
      expect(find.text('Robin Parker').hitTestable(), findsOneWidget);
      expect(find.text('Primary Skill: Drums').hitTestable(), findsOneWidget);
      expect(find.text(secondary).hitTestable(), findsOneWidget);
      expect(find.text('Unknown'), findsNothing);

      await tester.tap(find.byTooltip('Select musical role').first);
      await pumpUiTransitions(tester);
      expect(inMusicalRolePicker(find.textContaining('Robin Parker')).hitTestable(), findsOneWidget);
      expect(inMusicalRolePicker(find.text('Primary Skill: Drums')).hitTestable(), findsOneWidget);
      expect(inMusicalRolePicker(find.text(secondary)).hitTestable(), findsOneWidget);

      await tester.tap(inMusicalRolePicker(find.byType(TextField)));
      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      await chooseMusicalRole(tester, 'Trumpet');
      tester.view.resetViewInsets();
      await pumpUiTransitions(tester);
      expect(find.text('Added'), findsOneWidget);

      final selectRemaining = find.byTooltip('Select musical role');
      final bass = find.text('Primary Skill: Bass');
      final memberList = find.descendant(of: find.byType(Dialog), matching: find.byType(ListView));
      await tester.scrollUntilVisible(
        bass,
        60,
        scrollable: find.descendant(of: memberList, matching: find.byType(Scrollable)),
      );
      await tester.pump();
      expect(bass.hitTestable(), findsOneWidget);
      await tester.tap(selectRemaining);
      await pumpUiTransitions(tester);
      expect(find.text('Which instrument or role should this person take on in this band?'), findsOneWidget);
      expect(inMusicalRolePicker(find.text('Primary Skill: Bass')), findsOneWidget);
      expect(inMusicalRolePicker(find.textContaining('Secondary Skills:')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1. About appears directly after Band Name in CreateBandScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      final bandNameFinder = find.text('Band Name');
      final aboutFinder = find.text('About');
      final genresFinder = find.text('GENRES/BAND TYPES');

      expect(bandNameFinder, findsOneWidget);
      expect(aboutFinder, findsOneWidget);
      expect(genresFinder, findsOneWidget);

      final bandNameY = tester.getTopLeft(bandNameFinder).dy;
      final aboutY = tester.getTopLeft(aboutFinder).dy;
      final genresY = tester.getTopLeft(genresFinder).dy;

      expect(bandNameY, lessThan(aboutY), reason: 'Band Name must appear before About');
      expect(aboutY, lessThan(genresY), reason: 'About must appear before GENRES/BAND TYPES');
    });

    testWidgets('1b. About appears directly after Band Name in EditBandInfoScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final band = Band(id: 'b1', name: 'My Band', about: 'Our band bio');
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await pumpUiTransitions(tester);

      final bandNameFinder = find.text('Band Name');
      final aboutFinder = find.text('About');
      final genresFinder = find.text('GENRES/BAND TYPES');

      expect(bandNameFinder, findsOneWidget);
      expect(aboutFinder, findsOneWidget);
      expect(genresFinder, findsOneWidget);

      final bandNameY = tester.getTopLeft(bandNameFinder).dy;
      final aboutY = tester.getTopLeft(aboutFinder).dy;
      final genresY = tester.getTopLeft(genresFinder).dy;

      expect(bandNameY, lessThan(aboutY));
      expect(aboutY, lessThan(genresY));
    });

    testWidgets('2. No duplicate About field remains in Create and Edit Band', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      expect(find.text('About'), findsOneWidget, reason: 'Exactly one About heading must exist in CreateBand');

      final band = Band(id: 'b1', name: 'My Band');
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await pumpUiTransitions(tester);

      expect(find.text('About'), findsOneWidget, reason: 'Exactly one About heading in EditBand');
    });

    testWidgets('3. Rehearsal schedule is disabled and hidden by default in Create Band', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<Switch>(switchFinder).value, isFalse);

      expect(find.text('Day'), findsNothing);
      expect(find.text('Start Time'), findsNothing);
      expect(find.text('End Time'), findsNothing);
    });

    testWidgets('4. Enabling switch displays Day, Start Time, and End Time; toggling off hides them', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      final switchFinder = find.byType(Switch);

      // Turn on
      await tester.tap(switchFinder);
      await pumpUiTransitions(tester);

      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('End Time'), findsOneWidget);

      // Turn off
      await tester.tap(switchFinder);
      await pumpUiTransitions(tester);

      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      expect(find.text('Day'), findsNothing);
      expect(find.text('Start Time'), findsNothing);
      expect(find.text('End Time'), findsNothing);
    });

    testWidgets('5. A saved schedule reopens correctly in Edit Band; bands without schedule open off', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // With saved schedule
      final bandWithSchedule = Band(
        id: 'b1',
        name: 'The Scheduled Band',
        rehearsalDayOfWeek: 'Wednesday',
        rehearsalStartTime: '19:30',
        rehearsalEndTime: '22:00',
      );

      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: bandWithSchedule)));
      await pumpUiTransitions(tester);

      final switchFinder = find.byType(Switch);
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('19:30'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);

      // Without saved schedule
      final bandWithoutSchedule = Band(
        id: 'b2',
        name: 'Unscheduled Band',
      );

      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: bandWithoutSchedule)));
      await pumpUiTransitions(tester);

      final switchFinder2 = find.byType(Switch);
      expect(tester.widget<Switch>(switchFinder2).value, isFalse);
      expect(find.text('Day'), findsNothing);
      expect(find.text('Start Time'), findsNothing);
      expect(find.text('End Time'), findsNothing);
    });

    testWidgets('6a. Saving with switch off does not store default values in CreateBandScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockBandFirebaseService();
      final appState = MockBandAppState(mockService);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen(), appState));
      await pumpUiTransitions(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Enter band name'), 'Off Schedule Band');
      await chooseBerlin(tester);

      // Tap Save Band (switch is off by default)
      await tester.tap(find.text('Save Band'));
      await pumpUiTransitions(tester);

      expect(mockService.createdBand, isNotNull);
      expect(mockService.createdBand!.name, 'Off Schedule Band');
      expect(mockService.createdBand!.location, 'Berlin, Germany');
      expect(mockService.createdBand!.publicLocation?.city, 'Berlin');
      expect(mockService.createdBand!.rehearsalDayOfWeek, isNull);
      expect(mockService.createdBand!.rehearsalStartTime, isNull);
      expect(mockService.createdBand!.rehearsalEndTime, isNull);
    });

    testWidgets('6b. Saving with switch off does not store default values in EditBandInfoScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockBandFirebaseService();
      final appState = MockBandAppState(mockService);

      final existingBand = Band(
        id: 'b_edit',
        name: 'Edit Band',
        publicLocation: CityLocation.confirmed(city: 'Stockholm', country: 'Sweden'),
        membersBand: {'test_user_123': BandMember(userId: 'test_user_123', role: 'Leader', status: 'active')},
        location: 'Stockholm',
        rehearsalDayOfWeek: 'Friday',
        rehearsalStartTime: '17:00',
        rehearsalEndTime: '20:00',
      );

      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: existingBand), appState));
      await pumpUiTransitions(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Toggle off
      await tester.tap(find.byType(Switch));
      await pumpUiTransitions(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Save Changes'));
      await pumpUiTransitions(tester);

      expect(mockService.updatedBand, isNotNull);
      expect(mockService.updatedBand!.name, 'Edit Band');
      expect(mockService.updatedBand!.rehearsalDayOfWeek, isNull);
      expect(mockService.updatedBand!.rehearsalStartTime, isNull);
      expect(mockService.updatedBand!.rehearsalEndTime, isNull);
    });

    testWidgets('7. Schedule appears below Rehearsal Location and above Map View location', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      final rehearsalLocFinder = find.text('Rehearsal Location (if any)');
      final scheduleFinder = find.text('Regular Rehearsal Day & Time (if any)');
      final mapViewFinder = find.text('Map View Location (if other than Rehearsal Location)');

      expect(rehearsalLocFinder, findsOneWidget);
      expect(scheduleFinder, findsOneWidget);
      expect(mapViewFinder,
          FeatureToggles.enableMapView ? findsOneWidget : findsNothing);
      expect(find.byType(SpinningGlobeIcon),
          FeatureToggles.enableMapView && FeatureToggles.showMapInTopBar
              ? findsOneWidget
              : findsNothing);

      final rehearsalLocY = tester.getTopLeft(rehearsalLocFinder).dy;
      final scheduleY = tester.getTopLeft(scheduleFinder).dy;

      expect(rehearsalLocY, lessThan(scheduleY), reason: 'Rehearsal Location must be above Schedule');
      if (FeatureToggles.enableMapView) {
        final mapViewY = tester.getTopLeft(mapViewFinder).dy;
        expect(scheduleY, lessThan(mapViewY),
            reason: 'Schedule must be above Map View location');
      }
    });

    testWidgets('8. Both band forms show the exact disclaimer only when Map View is enabled', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const expectedHeading = 'Location & Media disclaimer for Map View';
      const expectedBody =
          'By checking this box, you give MUSICIANS permission to display your band’s location in "Map View" and make your uploaded media available through your band’s map icon. You confirm that you have all necessary rights and permissions for the media you upload.';

      // Create Band
      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await pumpUiTransitions(tester);

      final disclaimerMatcher =
          FeatureToggles.enableMapView ? findsOneWidget : findsNothing;
      expect(find.text(expectedHeading), disclaimerMatcher);
      expect(find.text(expectedBody), disclaimerMatcher);

      // Edit Band
      final band = Band(id: 'b1', name: 'Disclaimer Test Band');
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await pumpUiTransitions(tester);

      expect(find.text(expectedHeading), disclaimerMatcher);
      expect(find.text(expectedBody), disclaimerMatcher);
    });

    test('9. Existing Band serialization remains backward compatible', () {
      // Legacy JSON without rehearsal schedule fields or about
      final legacyJson = {
        'Name': 'Classic Rockers',
        'Genres': ['Rock', 'Blues'],
        'Level': 'C = INTERMEDIATE',
        'Location': 'Stockholm',
      };

      final band = Band.fromJson(legacyJson, 'legacy_1');
      expect(band.name, 'Classic Rockers');
      expect(band.genres, ['Rock', 'Blues']);
      expect(band.rehearsalDayOfWeek, isNull);
      expect(band.rehearsalStartTime, isNull);
      expect(band.rehearsalEndTime, isNull);
      expect(band.about, isNull);

      // Full JSON with new & existing fields
      final fullJson = {
        'Name': 'Modern Band',
        'About': 'Detailed band description',
        'RehearsalLocation': 'Studio A',
        'RehearsalDayOfWeek': 'Tuesday',
        'RehearsalStartTime': '18:00',
        'RehearsalEndTime': '21:00',
        'Location': 'Gothenburg',
        'Address': 'Map Pin Address',
      };

      final fullBand = Band.fromJson(fullJson, 'full_1');
      expect(fullBand.name, 'Modern Band');
      expect(fullBand.about, 'Detailed band description');
      expect(fullBand.rehearsalDayOfWeek, 'Tuesday');
      expect(fullBand.rehearsalStartTime, '18:00');
      expect(fullBand.rehearsalEndTime, '21:00');

      // Round trip toJson()
      final serialized = fullBand.toJson();
      expect(serialized['Name'], 'Modern Band');
      expect(serialized['About'], 'Detailed band description');
      expect(serialized['RehearsalDayOfWeek'], 'Tuesday');
      expect(serialized['RehearsalStartTime'], '18:00');
      expect(serialized['RehearsalEndTime'], '21:00');
      expect(serialized['Address'], 'Map Pin Address');
    });
  });
}
