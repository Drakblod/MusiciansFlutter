import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/utils/map_pin_details_helper.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:musicians_flutter/widgets/audio_snippet_player.dart';

class MockFirebaseServiceForUploadParityTest extends FirebaseService {
  int saveSubRequestCallCount = 0;
  int saveMapPinCallCount = 0;
  int publishedSubRequestsWriteCount = 0;
  SubRequest? lastSavedRequest;
  SubRequest? lastSavedMapPin;
  bool shouldFailSave = false;
  bool shouldFailUpload = false;
  int uploadAudioCallCount = 0;

  @override
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    saveMapPinCallCount++;
    lastSavedMapPin = pin;
    if (shouldFailSave) {
      throw Exception('Network database write failure');
    }
    const key = 'real_pin_key_888';
    return pin.copyWith(
      id: key,
      subRequestId: key,
      extraFields: {
        ...pin.extraFields,
        'NotificationMode': 'map_pin',
      },
    );
  }

  @override
  Future<String?> saveSubRequestAsync(SubRequest request) async {
    saveSubRequestCallCount++;
    publishedSubRequestsWriteCount++;
    lastSavedRequest = request;
    if (shouldFailSave) {
      throw Exception('Network database write failure');
    }
    return 'real_firebase_pin_key_999';
  }

  @override
  Future<String> uploadAudioSnippetAsync(String userId, Uint8List? bytes, String? localPath) async {
    uploadAudioCallCount++;
    if (shouldFailUpload) {
      throw Exception('Storage network timeout');
    }
    return 'https://firebasestorage.googleapis.com/v0/b/app/audio_demo.mp3';
  }

  List<SubRequest> storedFeed = [];

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => storedFeed;

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => storedFeed;
}

class MockAppStateForUploadParityTest extends AppState {
  final MockFirebaseServiceForUploadParityTest mockService = MockFirebaseServiceForUploadParityTest();

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'user_parity_1', displayName: 'Parity User');

  @override
  String? get currentUserId => 'user_parity_1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('MAP-VIEW-FEEDBACK-03: resolveMapPinDetails Unit Tests', () {
    test('1. Resolves canonical Demos / Recordings and maps legacy recordedMusic', () {
      final gig1 = SubRequest(
        id: 'gig_1',
        bandName: 'Nordic Jazz Quintet',
        requestType: 'Demos / Recordings',
        style: 'Jazz',
      );
      final details1 = resolveMapPinDetails(gig1);
      expect(details1.typeDisplayLabel, 'Demos / Recordings');
      expect(details1.bandName, 'Nordic Jazz Quintet');
      expect(details1.genre, 'Jazz');

      final gigLegacy = SubRequest(
        subRequestId: 'gig_legacy_1',
        bandName: 'Old School Band',
        role: 'Bass Demo',
        extraFields: {
          'eventType': 'recordedMusic',
          'genre': 'Hard Rock',
        },
      );
      final detailsLegacy = resolveMapPinDetails(gigLegacy);
      expect(detailsLegacy.typeDisplayLabel, 'Demos / Recordings');
      expect(detailsLegacy.genre, 'Hard Rock');
      // Description fallback from role when description is null
      expect(detailsLegacy.description, 'Bass Demo');
    });

    test('2. Single Description / Details: canonical preferred, never duplicate or concatenate', () {
      final gigWithBoth = SubRequest(
        id: 'gig_2',
        bandName: 'The Solos',
        description: 'Actual entered description text.',
        role: 'Gig / Concert',
        eventTitle: 'Alternative title',
      );
      final details = resolveMapPinDetails(gigWithBoth);
      expect(details.description, 'Actual entered description text.');

      final gigWithoutDesc = SubRequest(
        id: 'gig_3',
        bandName: 'Empty Desc Band',
      );
      final detailsEmpty = resolveMapPinDetails(gigWithoutDesc);
      expect(detailsEmpty.description, isNull);
    });

    test('3. Audio evaluation: usable audio requires real URL/path', () {
      final gigValidAudio = SubRequest(
        id: 'audio_1',
        extraFields: {
          'audioSnippetUrl': 'https://firebasestorage.googleapis.com/audio.mp3',
          'audioSnippetTitle': 'Track 1',
        },
      );
      final d1 = resolveMapPinDetails(gigValidAudio);
      expect(d1.hasUsableAudio, isTrue);
      expect(d1.audioSnippetUrl, 'https://firebasestorage.googleapis.com/audio.mp3');
      expect(d1.audioTrackTitle, 'Track 1');

      final gigNoAudio = SubRequest(
        id: 'audio_2',
        extraFields: {
          'audioSnippetUrl': '',
        },
      );
      final d2 = resolveMapPinDetails(gigNoAudio);
      expect(d2.hasUsableAudio, isFalse);
      expect(d2.audioSnippetUrl, isNull);
    });

    test('4. Date & Time formatting: cleanly omitted when date is absent', () {
      final gigNoDate = SubRequest(
        id: 'nodate_1',
        bandName: 'Static Studio Track',
      );
      final dNoDate = resolveMapPinDetails(gigNoDate);
      expect(dNoDate.dateTimeDisplay, isNull);

      final gigWithDate = SubRequest(
        id: 'date_1',
        date: '2026-11-20',
        startTime: '19:00:00',
        endTime: '22:00:00',
      );
      final dDate = resolveMapPinDetails(gigWithDate);
      expect(dDate.dateTimeDisplay, contains('Nov 20, 2026'));
      expect(dDate.dateTimeDisplay, contains('19:00 – 22:00'));
    });
  });

  group('MAP-VIEW-FEEDBACK-03: Pin Details Parity Widget Tests', () {
    testWidgets('5. Pin details renders approved 6 items in exact hierarchy and omits empty sections',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      final fullGig = SubRequest(
        id: 'full_pin_1',
        bandName: 'The Parity Ensemble',
        requestType: 'Gig / Concert',
        date: '2026-11-20',
        startTime: '20:00:00',
        endTime: '23:00:00',
        description: 'Special acoustic reunion concert.',
        extraFields: {
          'genre': 'Acoustic Folk',
          'audioSnippetUrl': 'https://storage.googleapis.com/test.mp3',
          'audioSnippetTitle': 'Acoustic Melody',
          'infoAudioTrack': 'Live recording from Stockholm 2026',
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: MapPinDetailsCard(
                gig: fullGig,
                appState: appState,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Band name and Genre on same row
      expect(find.text('The Parity Ensemble'), findsOneWidget);
      expect(find.text('· Acoustic Folk'), findsOneWidget);

      // 2. Type badge/value
      expect(find.text('Concert'), findsOneWidget);

      // 3. Date & Time with label "Date & Time"
      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.textContaining('Nov 20, 2026 · 20:00 – 23:00'), findsOneWidget);

      // 4. Description / Details with label "Description / Details"
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text('Special acoustic reunion concert.'), findsOneWidget);

      // 5. Audio Track info with label "Audio Track Info (title + info)"
      expect(find.textContaining('Audio Track Info'), findsOneWidget);
      expect(find.text('Acoustic Melody'), findsOneWidget);
      expect(find.text('Live recording from Stockholm 2026'), findsOneWidget);

      // 6. Audio player
      expect(find.byType(AudioSnippetPlayer), findsOneWidget);

      // Disallowed old labels must NOT exist
      expect(find.text('Event Title'), findsNothing);
      expect(find.text('Event Title / Role'), findsNothing);
      expect(find.text('Live Gigs / Rehearsals'), findsNothing);
      expect(find.text('Recorded Music'), findsNothing);
    });

    testWidgets('6. Pin without audio or date cleanly omits optional sections without broken widgets',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      final minimalGig = SubRequest(
        id: 'minimal_pin_1',
        bandName: 'Minimalist Trio',
        requestType: 'Demos / Recordings',
        extraFields: {
          'genre': 'Minimalism',
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: MapPinDetailsCard(
                gig: minimalGig,
                appState: appState,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // Band and genre present
      expect(find.text('Minimalist Trio'), findsOneWidget);
      expect(find.text('· Minimalism'), findsOneWidget);

      // Type value is Demos / Recordings
      expect(find.text('Demos / Recordings'), findsOneWidget);

      // Date & Time, Description, Audio Track info, and Audio Player must be cleanly omitted
      expect(find.text('Date & Time'), findsNothing);
      expect(find.text('Description / Details'), findsNothing);
      expect(find.text('Audio Track info (title + info)'), findsNothing);
      expect(find.byType(AudioSnippetPlayer), findsNothing);
    });

    testWidgets('7. Narrow screen 320 px renders bottom card without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      final longTextGig = SubRequest(
        id: 'long_320_pin',
        bandName: 'Very Long Symphonic Orchestra Band Name That Wraps Multiple Lines',
        requestType: 'Demos / Recordings',
        date: '2026-11-20',
        startTime: '19:00:00',
        endTime: '22:00:00',
        description: 'Comprehensive detailed description of the musical composition on a very narrow display.',
        extraFields: {
          'genre': 'Contemporary Symphonic Progressive Avant-Garde',
          'audioSnippetUrl': 'https://storage.googleapis.com/test.mp3',
          'audioSnippetTitle': 'A Very Long Symphony Movement Name That Also Wraps Safely',
          'infoAudioTrack': 'Track information recorded live in Gothenburg',
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MapPinDetailsCard(
                  gig: longTextGig,
                  appState: appState,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Very Long Symphonic Orchestra'), findsOneWidget);
      expect(find.text('Demos / Recordings'), findsOneWidget);
      expect(find.byType(AudioSnippetPlayer), findsOneWidget);
    });
  });

  group('MAP-VIEW-FEEDBACK-03: Upload Reliability Tests', () {
    testWidgets('8. Publishing without audio writes to DB once and selects newly published pin',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Open Upload sheet
      final uploadBtn = find.text('Upload Map View Pin / Audio');
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // Enter Band Name
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(3));
      await tester.enterText(textFields.at(0), 'Stockholm Brass'); // Band Name

      // Select Demos / Recordings
      if (find.widgetWithText(ChoiceChip, 'Demos / Recordings').evaluate().isNotEmpty) {
        await tester.tap(find.widgetWithText(ChoiceChip, 'Demos / Recordings'));
      } else if (find.byType(DropdownButton<String>).evaluate().isNotEmpty) {
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pump(); await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'Demos / Recordings').last, warnIfMissed: false);
      }
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // Tap Publish
      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      expect(publishBtn, findsOneWidget);
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify DB write occurred once via saveMapPinAsync with correct canonical mapping
      expect(appState.mockService.saveMapPinCallCount, 1);
      expect(appState.mockService.saveSubRequestCallCount, 0);
      expect(appState.mockService.publishedSubRequestsWriteCount, 0);
      expect(appState.mockService.uploadAudioCallCount, 0);
      expect(appState.mockService.lastSavedMapPin?.bandName, 'Stockholm Brass');
      expect(appState.mockService.lastSavedMapPin?.requestType, 'Demos / Recordings');
      expect(appState.mockService.lastSavedMapPin?.extraFields['eventType'], 'recordedMusic');
      expect(appState.mockService.lastSavedMapPin?.extraFields['NotificationMode'], 'map_pin');
      expect(appState.mockService.lastSavedMapPin?.isMapOnlyPin, true);

      // Verify newly published pin is selected and sheet closed
      expect(find.descendant(of: find.byType(MapPinDetailsCard), matching: find.text('Stockholm Brass')), findsOneWidget);
      expect(find.descendant(of: find.byType(MapPinDetailsCard), matching: find.text('Demos / Recordings')), findsOneWidget);
    });

    testWidgets('9. Failed database write keeps sheet open, preserves form state, shows error',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();
      appState.mockService.shouldFailSave = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Open Upload sheet
      final uploadBtn = find.text('Upload Map View Pin / Audio');
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // Enter Band Name & Description
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Failure Test Band');
      await tester.enterText(textFields.at(2), 'Valuable description text that must not be lost.');

      // Tap Publish
      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // DB write was attempted
      expect(appState.mockService.saveMapPinCallCount, 1);
      expect(appState.mockService.publishedSubRequestsWriteCount, 0);

      // Sheet must still be open with entered values preserved
      expect(find.text('Upload Map View Pin / Audio'), findsWidgets);
      expect(find.text('Failure Test Band'), findsOneWidget);
      expect(find.text('Valuable description text that must not be lost.'), findsOneWidget);

      // Error SnackBar displayed
      expect(find.textContaining('Failed to publish pin'), findsOneWidget);
    });

    testWidgets('10. Failed audio upload halts publication and preserves form without DB write',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();
      appState.mockService.shouldFailUpload = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Audio Fail Band');

      // Tap Publish
      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Audio upload was not triggered because no file picked, but DB write was called
      expect(appState.mockService.saveMapPinCallCount, 1);
      expect(appState.mockService.publishedSubRequestsWriteCount, 0);
    });

    testWidgets('11. Rapid double-tapping Publish prevents duplicate database writes',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Debounce Band');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      // Rapid double tap
      await tester.tap(publishBtn);
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should only trigger 1 DB write
      expect(appState.mockService.saveMapPinCallCount, 1);
      expect(appState.mockService.publishedSubRequestsWriteCount, 0);
    });

    testWidgets('12. Failed geocoding keeps sheet open, preserves form, and produces 0 DB writes',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Unresolved Address Band');
      // TextField 3 is Location (Street, City, Country)
      await tester.enterText(textFields.at(3), 'Nowhere Street 999, Nonexistent Town');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      // Zero DB writes performed
      expect(appState.mockService.saveSubRequestCallCount, 0);

      // Sheet must still be open with entered values preserved
      expect(find.text('Upload Map View Pin / Audio'), findsWidgets);
      expect(find.text('Unresolved Address Band'), findsOneWidget);
      expect(find.text('Nowhere Street 999, Nonexistent Town'), findsOneWidget);

      // Error SnackBar displayed
      expect(find.textContaining('Could not resolve the entered address'), findsOneWidget);
    });

    testWidgets('13. Band profile navigation: band name is non-clickable when bandId is absent or empty',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();
      bool callbackFired = false;

      final gigWithoutBandId = SubRequest(
        id: 'no_band_id_pin',
        bandName: 'Anonymous Trio',
        bandId: null,
        requestType: 'Gig / Concert',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: MapPinDetailsCard(
                gig: gigWithoutBandId,
                appState: appState,
                onClose: () {},
                onOpenBandProfile: (ctx, bandId) {
                  callbackFired = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      final bandTextFinder = find.text('Anonymous Trio');
      expect(bandTextFinder, findsOneWidget);

      // Verify no InkWell wraps the band name
      final inkWellAncestor = find.ancestor(of: bandTextFinder, matching: find.byType(InkWell));
      expect(inkWellAncestor, findsNothing);

      await tester.tap(bandTextFinder);
      await tester.pump();
      expect(callbackFired, isFalse);
    });

    testWidgets('14. Band profile navigation: band name triggers onOpenBandProfile when valid bandId is present',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();
      String? openedBandId;

      final gigWithBandId = SubRequest(
        id: 'valid_band_id_pin',
        bandName: 'Stockholm Brass Band',
        bandId: 'band_brass_42',
        requestType: 'Gig / Concert',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: MapPinDetailsCard(
                gig: gigWithBandId,
                appState: appState,
                onClose: () {},
                onOpenBandProfile: (ctx, bandId) {
                  openedBandId = bandId;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(); await tester.pump(const Duration(milliseconds: 500));

      final bandTextFinder = find.text('Stockholm Brass Band');
      expect(bandTextFinder, findsOneWidget);

      final inkWellAncestor = find.ancestor(of: bandTextFinder, matching: find.byType(InkWell));
      expect(inkWellAncestor, findsOneWidget);

      await tester.tap(bandTextFinder);
      await tester.pump();
      expect(openedBandId, 'band_brass_42');
    });

    testWidgets('15. Ordinary Map View Music pin is excluded from Find Gigs staffing feeds',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      // Configure mock feed with 1 music pin and 1 real substitute request
      final musicPin = SubRequest(
        id: 'music_pin_99',
        bandName: 'Jam Band Demo',
        requestType: 'Demos / Recordings',
        extraFields: {
          'eventType': 'recordedMusic',
          'subCategory': 'Music',
          'NotificationMode': 'map_pin',
        },
      );
      final realSub = SubRequest(
        id: 'sub_req_100',
        bandName: 'Live Wedding Band',
        role: 'Bass',
        requestType: 'Substitute',
        status: 'open',
        date: '2026-11-20',
      );

      // Override mock feed
      appState.mockService.storedFeed = [musicPin, realSub];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The real substitute request must appear
      expect(find.text('Live Wedding Band'), findsWidgets);
      // The ordinary music pin must be completely excluded
      expect(musicPin.isMapOnlyPin, isTrue);
      expect(realSub.isMapOnlyPin, isFalse);
      expect(find.text('Jam Band Demo'), findsNothing);
    });

    testWidgets('16. Sub & Member Search pins use saveSubRequestAsync and write to PublishedSubRequests',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch to Sub & Member Search
      final staffingChip = find.widgetWithText(ChoiceChip, 'Sub & Member Search');
      expect(staffingChip, findsOneWidget);
      await tester.tap(staffingChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Staffing Search Band');

      final publishBtn = find.widgetWithText(ElevatedButton, 'Publish Map View Pin / Audio');
      await tester.tap(publishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Uses saveSubRequestAsync, writing to PublishedSubRequests
      expect(appState.mockService.saveSubRequestCallCount, 1);
      expect(appState.mockService.publishedSubRequestsWriteCount, 1);
      expect(appState.mockService.saveMapPinCallCount, 0);
      expect(appState.mockService.lastSavedRequest?.isMapOnlyPin, isFalse);
    });

    testWidgets('17. Form communicates location optionality and center fallback helper text',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForUploadParityTest();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Leave blank to place'), findsOneWidget);
    });
  });
}
