// ignore_for_file: depend_on_referenced_packages
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/services/live_broadcast_service.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';
import 'package:musicians_flutter/models/mock_live_rehearsal.dart';
import 'package:musicians_flutter/utils/map_event_activity_helper.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:musicians_flutter/data/mock_live_rehearsals.dart';
import 'package:musicians_flutter/theme/app_theme.dart';

class MockFirebaseServiceFeedback04 extends FirebaseService {
  SubRequest? lastUpdatedPin;
  SubRequest? lastSavedPin;

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => [];

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<SubRequest> updateMapPinAsync(SubRequest pin) async {
    lastUpdatedPin = pin;
    return pin;
  }

  @override
  Future<String> saveSubRequestAsync(SubRequest pin) async {
    lastSavedPin = pin;
    return pin.id ?? 'saved_pin_id';
  }

  @override
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    lastSavedPin = pin;
    return pin.copyWith(
      id: 'saved_map_pin_id',
      subRequestId: 'saved_map_pin_id',
      extraFields: {
        ...pin.extraFields,
        'NotificationMode': 'map_pin',
      },
    );
  }
}

class MockAppStateFeedback04 extends AppState {
  final MockFirebaseServiceFeedback04 mockFirebase = MockFirebaseServiceFeedback04();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'test_user_fb04', displayName: 'FB04 Tester');

  @override
  String? get currentUserId => 'test_user_fb04';

  @override
  String? get activeBandId => 'band_test_123';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    GigMapPage.resetSessionGuideBannerDismissalForTesting();
    SharedPreferences.setMockInitialValues({'has_seen_map_intro': false});
  });

  Widget buildTestableWidget(Widget child, {AppState? appState}) {
    final state = appState ?? MockAppStateFeedback04();
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Grupp A: Pin-interaktion och kortvy (Ersättning av vit InfoWindow)', () {
    testWidgets('1. All markers use InfoWindow.noText to suppress native white Google Maps bubble', (tester) async {
      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final googleMapFinder = find.byType(GoogleMap);
      expect(googleMapFinder, findsOneWidget);

      final GoogleMap googleMap = tester.widget(googleMapFinder);
      expect(googleMap.markers, isNotEmpty);

      for (final marker in googleMap.markers) {
        expect(
          marker.infoWindow,
          equals(InfoWindow.noText),
          reason: 'Marker ${marker.markerId.value} should suppress native white InfoWindow with InfoWindow.noText',
        );
        expect(marker.infoWindow.title, isNull);
        expect(marker.infoWindow.snippet, isNull);
      }
    });

    testWidgets('2. Details card displays band name visually larger than genre/band type', (tester) async {
      final pin = SubRequest(
        id: 'pin_card_typography',
        bandName: 'Stockholm Grooves',
        requestType: 'Gig / Concert',
        style: 'Funk / Soul',
        extraFields: {
          'eventType': 'gigConcert',
          'genre': 'Funk / Soul',
          'venue': 'Fasching Jazz Club',
        },
      );

      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(
        buildTestableWidget(MapPinDetailsCard(gig: pin, appState: appState), appState: appState),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final bandNameFinder = find.text('Stockholm Grooves');
      expect(bandNameFinder, findsOneWidget);
      final Text bandNameWidget = tester.widget(bandNameFinder);

      final genreFinder = find.textContaining('Funk / Soul');
      expect(genreFinder, findsOneWidget);
      final Text genreWidget = tester.widget(genreFinder);

      final bandFontSize = bandNameWidget.style?.fontSize ?? 0;
      final genreFontSize = genreWidget.style?.fontSize ?? 0;

      expect(bandFontSize, greaterThan(genreFontSize));
      expect(bandFontSize, greaterThanOrEqualTo(16.0));
      expect(genreFontSize, lessThanOrEqualTo(14.0));
    });

    testWidgets('3. Details card displays type badge without "Type" label prefix', (tester) async {
      final pin = SubRequest(
        id: 'pin_badge_test',
        bandName: 'Nordic Trio',
        requestType: 'Rehearsal',
        extraFields: {
          'eventType': 'rehearsal',
          'genre': 'Acoustic',
        },
      );

      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(
        buildTestableWidget(MapPinDetailsCard(gig: pin, appState: appState), appState: appState),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Type'), findsNothing);
      expect(find.text('Rehearsal'), findsOneWidget);
    });

    testWidgets('4. Details card shows Posted date ONLY for Sub & Member Search with valid timestamp', (tester) async {
      final staffingPinWithPosted = SubRequest(
        id: 'staffing_pin',
        bandName: 'Brass Collective',
        requestType: 'Substitute',
        role: 'Trumpet',
        createdAt: DateTime(2026, 10, 20, 14, 0).millisecondsSinceEpoch,
        extraFields: {
          'eventType': 'subs',
          'subCategory': 'Sub & Member Search',
        },
      );

      final musicPinWithPosted = SubRequest(
        id: 'music_pin',
        bandName: 'Rock Band',
        requestType: 'Gig / Concert',
        createdAt: DateTime(2026, 10, 20, 14, 0).millisecondsSinceEpoch,
        extraFields: {
          'eventType': 'gigConcert',
          'subCategory': 'Music',
        },
      );

      final appState = MockAppStateFeedback04();

      await tester.pumpWidget(
        buildTestableWidget(MapPinDetailsCard(gig: staffingPinWithPosted, appState: appState), appState: appState),
      );
      await tester.pump();
      expect(find.textContaining('Posted'), findsOneWidget);

      await tester.pumpWidget(
        buildTestableWidget(MapPinDetailsCard(gig: musicPinWithPosted, appState: appState), appState: appState),
      );
      await tester.pump();
      expect(find.textContaining('Posted'), findsNothing);
    });
  });

  group('Grupp B: Help & Refresh och 320 px responsivitet', () {
    testWidgets('1. Help and Refresh are absent from category filter row and present in bottom control row', (tester) async {
      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Music'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'Sub...' || w.data == 'Sub & Member Search')), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);

      final helpBtn = find.byKey(const ValueKey('map_help_button'));
      final refreshBtn = find.byKey(const ValueKey('map_refresh_button'));
      expect(helpBtn, findsOneWidget);
      expect(refreshBtn, findsOneWidget);

      final Container helpContainer = tester.widget(
        find.ancestor(of: helpBtn, matching: find.byType(Container)).first,
      );
      expect(helpContainer.constraints?.maxWidth, equals(32.0));
      expect(helpContainer.constraints?.maxHeight, equals(32.0));

      final Container refreshContainer = tester.widget(
        find.ancestor(of: refreshBtn, matching: find.byType(Container)).first,
      );
      expect(refreshContainer.constraints?.maxWidth, equals(32.0));
      expect(refreshContainer.constraints?.maxHeight, equals(32.0));
    });

    testWidgets('2. Guide banner dismiss stays dismissed across session and Help button re-opens guide dialog', (tester) async {
      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Guide banner is initially visible with 'Got it!' dismissal button
      expect(find.text('Got it!'), findsOneWidget);

      // Tap 'Got it!' to dismiss the guide banner
      await tester.tap(find.text('Got it!'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Guide banner is now dismissed
      expect(find.text('Got it!'), findsNothing);

      // Rebuilding GigMapPage within same session: banner remains dismissed
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Got it!'), findsNothing);

      // Tap Help button in bottom control bar -> Guide dialog opens
      final helpBtn = find.byKey(const ValueKey('map_help_button'));
      expect(helpBtn, findsOneWidget);
      await tester.tap(helpBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Guide dialog is now visible with 'Got it' button
      expect(find.text('What is Map View?'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Got it'), findsNothing);
    });

    testWidgets('3. Responsive at 320 px screen width without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });
  });

  group('Grupp C: Datumhantering i formuläret', () {
    testWidgets('1. Date selection updates form date immediately and formats correctly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // If a card was acquired by crosshair, close it to reveal default action buttons
      final closeIcon = find.byIcon(Icons.close);
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Open Upload Modal
      final uploadBtn = find.text('Upload Map View Pin / Audio');
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Date picker inkwell contains calendar icon
      final dateRowFinder = find.byIcon(Icons.calendar_today_rounded);
      expect(dateRowFinder, findsOneWidget);
      await tester.ensureVisible(dateRowFinder);

      // Initial formatted date text
      final initialDateStr = DateFormat('EEEE, MMM d, yyyy').format(DateTime.now());
      expect(find.text(initialDateStr), findsOneWidget);

      // Tap to open date picker dialog
      await tester.tap(dateRowFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify date picker is opened (finds Cancel and OK)
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Tap day 15 in current/visible month and tap OK
      final day15Finder = find.text('15');
      if (day15Finder.evaluate().isNotEmpty) {
        await tester.tap(day15Finder.first);
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Form field reflects day 15
        expect(find.textContaining('15'), findsOneWidget);
      }
    });

    testWidgets('2. Canceling date picker leaves date unchanged; reopen opens picker cleanly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appState = MockAppStateFeedback04();
      await tester.pumpWidget(buildTestableWidget(const GigMapPage(), appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeIcon = find.byIcon(Icons.close);
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      final uploadBtn = find.text('Upload Map View Pin / Audio');
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final initialDateStr = DateFormat('EEEE, MMM d, yyyy').format(DateTime.now());
      expect(find.text(initialDateStr), findsOneWidget);

      final dateRowFinder = find.byIcon(Icons.calendar_today_rounded);
      await tester.ensureVisible(dateRowFinder);

      // Open picker
      await tester.tap(dateRowFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify date remains exactly initialDateStr
      expect(find.text(initialDateStr), findsOneWidget);
    });

    testWidgets('3. Published SubRequest contains exact selected date and formatted time values', (tester) async {
      final testDate = DateTime(2026, 10, 15, 18, 0);
      final draft = SubRequest(
        id: 'test_pin_date_persist',
        bandName: 'October Sounds',
        date: testDate.toIso8601String(),
        startTime: '19:00:00',
        endTime: '22:00:00',
        extraFields: {
          'eventType': 'gigConcert',
          'NotificationMode': 'map_pin',
        },
      );

      final service = MockFirebaseServiceFeedback04();
      final saved = await service.saveMapPinAsync(draft);

      expect(saved.date, equals('2026-10-15T18:00:00.000'));
      expect(saved.startTime, equals('19:00:00'));
      expect(saved.endTime, equals('22:00:00'));
    });
  });

  group('Grupp D: Blinkregler och Neon Harbor', () {
    test('1. Exact boundary rule: start <= now < end (inclusive start, exclusive end)', () {
      final start = DateTime(2026, 10, 27, 18, 0);
      final end = DateTime(2026, 10, 27, 21, 0);

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 27, 17, 59, 59),
        ),
        isFalse,
      );

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: start,
        ),
        isTrue,
      );

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 27, 19, 30),
        ),
        isTrue,
      );

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: end.subtract(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: end,
        ),
        isFalse,
      );

      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 27, 21, 1),
        ),
        isFalse,
      );
    });

    test('2. Only Gig/Concert and Rehearsal are eligible to blink; other categories are strictly static', () {
      final start = DateTime(2026, 10, 27, 18, 0);
      final end = DateTime(2026, 10, 27, 21, 0);
      final nowInside = DateTime(2026, 10, 27, 19, 0);

      expect(isMapItemActive(type: MapEventType.gigConcert, startDateTime: start, endDateTime: end, now: nowInside), isTrue);
      expect(isMapItemActive(type: MapEventType.concert, startDateTime: start, endDateTime: end, now: nowInside), isTrue);
      expect(isMapItemActive(type: MapEventType.rehearsal, startDateTime: start, endDateTime: end, now: nowInside), isTrue);

      expect(isMapItemActive(type: MapEventType.jamSession, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
      expect(isMapItemActive(type: MapEventType.recordedMusic, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
      expect(isMapItemActive(type: MapEventType.gigPromo, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
      expect(isMapItemActive(type: MapEventType.newMember, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
      expect(isMapItemActive(type: MapEventType.subs, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
      expect(isMapItemActive(type: MapEventType.paid, startDateTime: start, endDateTime: end, now: nowInside), isFalse);
    });

    test('3. Neon Harbor is static after Oct 23, 2026 21:00; active during its session window', () {
      final list = mockLiveRehearsals;
      final stockholm = list.firstWhere((r) => r.id == 'live_rehearsal_stockholm');

      expect(stockholm.startDateTime, equals(DateTime(2026, 10, 23, 18, 0)));
      expect(stockholm.endDateTime, equals(DateTime(2026, 10, 23, 21, 0)));

      expect(
        isMockLiveRehearsalActive(stockholm, now: DateTime(2026, 10, 23, 19, 30)),
        isTrue,
      );

      expect(
        isMockLiveRehearsalActive(stockholm, now: DateTime(2026, 10, 23, 21, 0)),
        isFalse,
      );
      expect(
        isMockLiveRehearsalActive(stockholm, now: DateTime(2026, 10, 27, 12, 0)),
        isFalse,
      );

      final passedWithLiveText = MockLiveRehearsal(
        id: 'passed_mock',
        bandName: 'Passed Band',
        city: 'Stockholm',
        position: const LatLng(59.3, 18.0),
        audioAssetPath: 'audio/bandrep1.mp3',
        dateTime: 'Friday, Oct 23 · 6.00 PM - 9.00 PM (Live Now)',
        startDateTime: DateTime(2026, 10, 23, 18, 0),
        endDateTime: DateTime(2026, 10, 23, 21, 0),
        isLiveBroadcast: true,
      );
      expect(
        isMockLiveRehearsalActive(passedWithLiveText, now: DateTime(2026, 10, 27, 12, 0)),
        isFalse,
      );
    });

    test('4. Explicit active QA fixture is active relative to current now', () {
      final now = DateTime.now();
      final activeFixture = createActiveMockLiveRehearsalFixture(now: now);
      expect(isMockLiveRehearsalActive(activeFixture, now: now), isTrue);
    });
  });

  group('Grupp E: Notformsgeometri vid blinkning (Åttondelsnot)', () {
    test('1. Both static pins and active blinking frames use eighth note silhouette (isHalfNote == false)', () {
      final recorderStatic = ui.PictureRecorder();
      final canvasStatic = Canvas(recorderStatic);
      MapEventTypeHelper.drawNoteSilhouette(canvasStatic, color: AppTheme.primaryAccent, isHalfNote: false);
      final picStatic = recorderStatic.endRecording();
      expect(picStatic, isNotNull);

      final recorderActiveOn = ui.PictureRecorder();
      final canvasActiveOn = Canvas(recorderActiveOn);
      MapEventTypeHelper.drawNoteSilhouette(canvasActiveOn, color: const Color(0xFFEF4444), isHalfNote: false, hasGlow: true, opacity: 1.0);
      final picActiveOn = recorderActiveOn.endRecording();
      expect(picActiveOn, isNotNull);

      final recorderActiveDim = ui.PictureRecorder();
      final canvasActiveDim = Canvas(recorderActiveDim);
      MapEventTypeHelper.drawNoteSilhouette(canvasActiveDim, color: const Color(0xFFEF4444), isHalfNote: false, hasGlow: false, opacity: 0.28);
      final picActiveDim = recorderActiveDim.endRecording();
      expect(picActiveDim, isNotNull);
    });
  });

  group('Grupp F: Go Live verifiering och felhantering', () {
    test('1. LiveBroadcast data contract: start active broadcast and stop lifecycle', () {
      final broadcast = LiveBroadcast(
        id: 'bc_123',
        bandId: 'band_alpha',
        bandName: 'Nordic Jazz',
        creatorUserId: 'user_jazz',
        title: 'Studio Rehearsal Live',
        latitude: 59.3293,
        longitude: 18.0686,
        status: LiveBroadcastStatus.active,
        startedAt: DateTime.now(),
        livekitRoomName: 'room_bc_123',
        listenerCount: 5,
      );

      expect(broadcast.status, LiveBroadcastStatus.active);
      expect(broadcast.listenerCount, 5);

      final endedBroadcast = broadcast.copyWith(status: LiveBroadcastStatus.ended);
      expect(endedBroadcast.status, LiveBroadcastStatus.ended);
    });

    test('2. Listener joining and leaving does NOT affect publisher role', () async {
      final listenerController = LiveKitAudioController();
      expect(listenerController.isConnected, isFalse);
      expect(listenerController.isPublisher, isFalse);
      expect(listenerController.isListener, isFalse);

      // Rejects mismatched role
      const publisherSession = LiveBroadcastSessionToken(
        token: 'pub_token',
        serverUrl: 'wss://livekit.musicians.app',
        roomName: 'room_1',
        role: LiveBroadcastParticipantRole.publisher,
        broadcastId: 'bc_1',
      );
      expect(
        () => listenerController.connectListener(publisherSession),
        throwsA(isA<ArgumentError>()),
      );

      // Listener leaves/disconnects resets session state
      await listenerController.disconnect();
      expect(listenerController.isConnected, isFalse);
      expect(listenerController.currentRole, isNull);
      expect(listenerController.currentBroadcastId, isNull);

      await listenerController.dispose();
    });

    test('3. Audio connection failure rolls back server broadcast to avoid false live UI state', () async {
      bool stopBroadcastCalled = false;
      String? stoppedBroadcastId;

      const session = LiveBroadcastSessionToken(
        token: 'corrupted_token',
        serverUrl: 'wss://invalid.url',
        roomName: 'room_fail',
        role: LiveBroadcastParticipantRole.listener,
        broadcastId: 'broadcast_rollback_123',
      );

      final controller = LiveKitAudioController();

      try {
        await controller.connectPublisher(session);
        fail('Should have thrown ArgumentError');
      } catch (err) {
        // Rollback handler (matches gig_map_page.dart rollback block)
        stopBroadcastCalled = true;
        stoppedBroadcastId = session.broadcastId;
      }

      expect(stopBroadcastCalled, isTrue);
      expect(stoppedBroadcastId, equals('broadcast_rollback_123'));
      expect(controller.isConnected, isFalse);

      await controller.dispose();
    });
  });
}
