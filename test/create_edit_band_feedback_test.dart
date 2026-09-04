import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:provider/provider.dart';

class MockBandFirebaseService extends FirebaseService {
  Band? createdBand;
  Band? updatedBand;

  @override
  Future<void> createBandAsync(String userId, Band band) async {
    createdBand = band;
  }

  @override
  Future<void> updateBandAsync(String bandId, Band band) async {
    updatedBand = band;
  }
}

class MockBandAppState extends AppState {
  final MockBandFirebaseService mockService;

  MockBandAppState(this.mockService);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => 'test_user_123';

  @override
  Future<void> refreshProfile() async {}

  @override
  void selectBand(String bandId, String bandName) {}
}

Widget createTestWidget(Widget child, [MockBandAppState? appState]) {
  final state = appState ?? MockBandAppState(MockBandFirebaseService());
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      key: UniqueKey(),
      home: child,
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
    testWidgets('1. About appears directly after Band Name in CreateBandScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget, reason: 'Exactly one About heading must exist in CreateBand');

      final band = Band(id: 'b1', name: 'My Band');
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget, reason: 'Exactly one About heading in EditBand');
    });

    testWidgets('3. Rehearsal schedule is disabled and hidden by default in Create Band', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);

      // Turn on
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('End Time'), findsOneWidget);

      // Turn off
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Enter band name'), 'Off Schedule Band');
      await tester.enterText(find.widgetWithText(TextFormField, 'Stockholm, Sweden'), 'Stockholm');

      // Tap Save Band (switch is off by default)
      await tester.tap(find.text('Save Band'));
      await tester.pumpAndSettle();

      expect(mockService.createdBand, isNotNull);
      expect(mockService.createdBand!.name, 'Off Schedule Band');
      expect(mockService.createdBand!.location, 'Stockholm');
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
        location: 'Stockholm',
        rehearsalDayOfWeek: 'Friday',
        rehearsalStartTime: '17:00',
        rehearsalEndTime: '20:00',
      );

      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: existingBand), appState));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Toggle off
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      final rehearsalLocFinder = find.text('Rehearsal Location (if any)');
      final scheduleFinder = find.text('Regular Rehearsal Day & Time (if any)');
      final mapViewFinder = find.text('Map view location (if other than Rehearsal Location)');

      expect(rehearsalLocFinder, findsOneWidget);
      expect(scheduleFinder, findsOneWidget);
      expect(mapViewFinder, findsOneWidget);

      final rehearsalLocY = tester.getTopLeft(rehearsalLocFinder).dy;
      final scheduleY = tester.getTopLeft(scheduleFinder).dy;
      final mapViewY = tester.getTopLeft(mapViewFinder).dy;

      expect(rehearsalLocY, lessThan(scheduleY), reason: 'Rehearsal Location must be above Schedule');
      expect(scheduleY, lessThan(mapViewY), reason: 'Schedule must be above Map view location');
    });

    testWidgets('8. Exact disclaimer heading and body are displayed in Create Band and Edit Band', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const expectedHeading = 'Location & Media disclaimer for Map View';
      const expectedBody =
          'By checking this box, you give MUSICIANS permission to display your band’s location in "Map View" and make your uploaded media available through your band’s map icon. You confirm that you have all necessary rights and permissions for the media you upload.';

      // Create Band
      await tester.pumpWidget(createTestWidget(const CreateBandScreen()));
      await tester.pumpAndSettle();

      expect(find.text(expectedHeading), findsOneWidget);
      expect(find.text(expectedBody), findsOneWidget);

      // Edit Band
      final band = Band(id: 'b1', name: 'Disclaimer Test Band');
      await tester.pumpWidget(createTestWidget(EditBandInfoScreen(band: band)));
      await tester.pumpAndSettle();

      expect(find.text(expectedHeading), findsOneWidget);
      expect(find.text(expectedBody), findsOneWidget);
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
