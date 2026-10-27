// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/services/live_broadcast_service.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';
import 'package:musicians_flutter/services/mock_rehearsal_audio_controller.dart';
import 'package:musicians_flutter/services/route_observer.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';

class MockFirebaseServiceForLifecycle extends FirebaseService {
  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => [];

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};
}

class MockAppStateForLifecycle extends AppState {
  final MockFirebaseServiceForLifecycle mockFirebase = MockFirebaseServiceForLifecycle();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'u_tester', displayName: 'Tester');

  @override
  String? get currentUserId => 'u_tester';

  @override
  String? get activeBandId => 'band_1';
}

class FakeLiveBroadcastService implements ILiveBroadcastService {
  final List<String> stopCalls = [];
  final List<String> leaveCalls = [];
  final StreamController<List<LiveBroadcast>> _broadcastsController =
      StreamController<List<LiveBroadcast>>.broadcast();

  @override
  Future<LiveBroadcastSessionToken> startLiveBroadcast({
    required String bandId,
    required String title,
    required LatLng location,
    String? description,
    String? genre,
  }) async {
    return const LiveBroadcastSessionToken(
      broadcastId: 'broadcast_123',
      roomName: 'room_123',
      token: 'token_123',
      serverUrl: 'wss://fake.livekit.cloud',
      role: LiveBroadcastParticipantRole.publisher,
    );
  }

  @override
  Future<LiveBroadcastSessionToken> joinLiveBroadcast({
    required String broadcastId,
  }) async {
    return LiveBroadcastSessionToken(
      broadcastId: broadcastId,
      roomName: 'room_$broadcastId',
      token: 'listener_token_$broadcastId',
      serverUrl: 'wss://fake.livekit.cloud',
      role: LiveBroadcastParticipantRole.listener,
    );
  }

  @override
  Future<void> leaveLiveBroadcast({required String broadcastId}) async {
    leaveCalls.add(broadcastId);
  }

  @override
  Future<void> stopLiveBroadcast({required String broadcastId}) async {
    stopCalls.add(broadcastId);
  }

  @override
  Stream<List<LiveBroadcast>> streamActiveBroadcasts() {
    return _broadcastsController.stream;
  }

  @override
  Stream<LiveBroadcast?> streamBroadcast(String broadcastId) {
    return Stream.value(null);
  }

  void dispose() {
    _broadcastsController.close();
  }
}

class FakeLiveKitAudioController extends LiveKitAudioController {
  int disconnectCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<void> disconnect() async {
    disconnectCallCount++;
    await super.disconnect();
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await super.dispose();
  }
}

class FakeMockRehearsalAudioController extends MockRehearsalAudioController {
  int pauseAudioCallCount = 0;
  int disposeCallCount = 0;

  @override
  void pauseAudio() {
    pauseAudioCallCount++;
    super.pauseAudio();
  }

  @override
  void dispose() {
    disposeCallCount++;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'has_seen_map_intro': true,
      'is_white_map_style': false,
    });
    GigMapPage.resetSessionGuideBannerDismissalForTesting();
  });

  LiveBroadcast createTestBroadcast({
    String id = 'b_123',
    String title = 'Neon Stream',
    String creatorId = 'u_broadcaster',
  }) {
    return LiveBroadcast(
      id: id,
      bandId: 'band_1',
      bandName: 'Neon Wave',
      creatorUserId: creatorId,
      title: title,
      genre: 'Synthwave',
      description: 'Live Rehearsal Test',
      latitude: 59.3293,
      longitude: 18.0686,
      status: LiveBroadcastStatus.active,
      startedAt: DateTime.now(),
      livekitRoomName: 'room_$id',
      listenerCount: 4,
    );
  }

  Widget createTestWidget({
    required FakeLiveBroadcastService liveService,
    required FakeLiveKitAudioController liveKitController,
    required FakeMockRehearsalAudioController rehearsalController,
    AppState? appState,
  }) {
    final state = appState ?? MockAppStateForLifecycle();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
      ],
      child: MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: GigMapPage(
          liveBroadcastService: liveService,
          liveKitAudioController: liveKitController,
          mockRehearsalAudioController: rehearsalController,
        ),
      ),
    );
  }

  group('GigMapPage Direct Lifecycle Tests', () {
    testWidgets('A. Broadcaster + didPushNext: stops broadcast on server, disconnects audio, and pauses local audio',
        (tester) async {
      final liveService = FakeLiveBroadcastService();
      final liveKitController = FakeLiveKitAudioController();
      final rehearsalController = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService,
        liveKitController: liveKitController,
        rehearsalController: rehearsalController,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state<GigMapPageState>(find.byType(GigMapPage));
      final testBroadcast = createTestBroadcast(id: 'broadcast_alpha', creatorId: 'u_tester');

      // Set broadcaster state
      state.setPublishingBroadcastForTesting(testBroadcast);
      expect(state.currentPublishingBroadcastForTesting, isNotNull);

      // Simulate route pushed on top (didPushNext)
      state.didPushNext();
      await tester.pump();

      // Verify exactly one call to stopLiveBroadcast
      expect(liveService.stopCalls, equals(['broadcast_alpha']));
      expect(liveService.leaveCalls, isEmpty);

      // Verify LiveKit disconnect and local rehearsal pause
      expect(liveKitController.disconnectCallCount, equals(1));
      expect(rehearsalController.pauseAudioCallCount, equals(1));

      // Verify internal broadcaster state reset
      expect(state.currentPublishingBroadcastForTesting, isNull);
      expect(state.liveBlinkTimerForTesting, isNull);
    });

    testWidgets('B. Listener + didPushNext: leaves broadcast, disconnects audio, and NEVER stops broadcaster broadcast',
        (tester) async {
      final liveService = FakeLiveBroadcastService();
      final liveKitController = FakeLiveKitAudioController();
      final rehearsalController = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService,
        liveKitController: liveKitController,
        rehearsalController: rehearsalController,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state<GigMapPageState>(find.byType(GigMapPage));
      final testBroadcast = createTestBroadcast(id: 'broadcast_beta', creatorId: 'u_other_musician');

      // Set listener state
      state.setListeningBroadcastForTesting(testBroadcast);
      expect(state.currentlyListeningBroadcastForTesting, isNotNull);

      // Simulate route pushed on top (didPushNext)
      state.didPushNext();
      await tester.pump();

      // Verify leaveLiveBroadcast called
      expect(liveService.leaveCalls, equals(['broadcast_beta']));

      // Verify stopLiveBroadcast was NEVER called
      expect(liveService.stopCalls, isEmpty);

      // Verify disconnect and pause
      expect(liveKitController.disconnectCallCount, equals(1));
      expect(rehearsalController.pauseAudioCallCount, equals(1));

      // Verify internal listener state reset
      expect(state.currentlyListeningBroadcastForTesting, isNull);
    });

    testWidgets('C. Broadcaster + dispose: pops page, cleans up broadcaster, disposes audio and timers',
        (tester) async {
      final liveService = FakeLiveBroadcastService();
      final liveKitController = FakeLiveKitAudioController();
      final rehearsalController = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService,
        liveKitController: liveKitController,
        rehearsalController: rehearsalController,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state<GigMapPageState>(find.byType(GigMapPage));
      final testBroadcast = createTestBroadcast(id: 'broadcast_gamma', creatorId: 'u_tester');
      state.setPublishingBroadcastForTesting(testBroadcast);

      // Pop / dispose the page by replacing with a blank Container
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Map closed'))));
      await tester.pump();

      // Verify broadcaster stop call
      expect(liveService.stopCalls, equals(['broadcast_gamma']));
      expect(liveService.leaveCalls, isEmpty);

      // Verify controllers disposed
      expect(liveKitController.disposeCallCount, equals(1));
      expect(rehearsalController.disposeCallCount, equals(1));
    });

    testWidgets('D. Listener + dispose: leaves broadcast and cleans up without stopping server broadcast',
        (tester) async {
      final liveService = FakeLiveBroadcastService();
      final liveKitController = FakeLiveKitAudioController();
      final rehearsalController = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService,
        liveKitController: liveKitController,
        rehearsalController: rehearsalController,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state<GigMapPageState>(find.byType(GigMapPage));
      final testBroadcast = createTestBroadcast(id: 'broadcast_delta', creatorId: 'u_host');
      state.setListeningBroadcastForTesting(testBroadcast);

      // Pop / dispose page
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Map closed'))));
      await tester.pump();

      // Verify listener leave call
      expect(liveService.leaveCalls, equals(['broadcast_delta']));

      // Verify broadcaster session was NOT stopped
      expect(liveService.stopCalls, isEmpty);

      // Verify controllers disposed
      expect(liveKitController.disposeCallCount, equals(1));
      expect(rehearsalController.disposeCallCount, equals(1));
    });

    testWidgets('E. Inactive User: leaving/closing Map View makes NO live broadcast server calls',
        (tester) async {
      final liveService = FakeLiveBroadcastService();
      final liveKitController = FakeLiveKitAudioController();
      final rehearsalController = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService,
        liveKitController: liveKitController,
        rehearsalController: rehearsalController,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state<GigMapPageState>(find.byType(GigMapPage));

      // User has neither broadcasting nor listening active
      expect(state.currentPublishingBroadcastForTesting, isNull);
      expect(state.currentlyListeningBroadcastForTesting, isNull);

      // Navigate away
      state.didPushNext();
      await tester.pump();

      // No network/callable requests
      expect(liveService.stopCalls, isEmpty);
      expect(liveService.leaveCalls, isEmpty);
      expect(rehearsalController.pauseAudioCallCount, equals(1));

      // Close page
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Map closed'))));
      await tester.pump();

      // Still no invalid live server requests
      expect(liveService.stopCalls, isEmpty);
      expect(liveService.leaveCalls, isEmpty);
      expect(liveKitController.disposeCallCount, equals(1));
      expect(rehearsalController.disposeCallCount, equals(1));
    });

    testWidgets('F. Idempotency: didPushNext followed by dispose NEVER executes duplicate stop or leave calls',
        (tester) async {
      // 1. Broadcaster idempotency check
      final liveService1 = FakeLiveBroadcastService();
      final liveKitController1 = FakeLiveKitAudioController();
      final rehearsalController1 = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService1,
        liveKitController: liveKitController1,
        rehearsalController: rehearsalController1,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state1 = tester.state<GigMapPageState>(find.byType(GigMapPage));
      state1.setPublishingBroadcastForTesting(createTestBroadcast(id: 'broadcast_idem_pub'));

      // Step 1: didPushNext called first
      state1.didPushNext();
      await tester.pump();
      expect(liveService1.stopCalls.length, equals(1));

      // Step 2: dispose called afterwards
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Map closed'))));
      await tester.pump();

      // Verify stopLiveBroadcast was NOT called a second time!
      expect(liveService1.stopCalls.length, equals(1));

      // 2. Listener idempotency check
      final liveService2 = FakeLiveBroadcastService();
      final liveKitController2 = FakeLiveKitAudioController();
      final rehearsalController2 = FakeMockRehearsalAudioController();

      await tester.pumpWidget(createTestWidget(
        liveService: liveService2,
        liveKitController: liveKitController2,
        rehearsalController: rehearsalController2,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state2 = tester.state<GigMapPageState>(find.byType(GigMapPage));
      state2.setListeningBroadcastForTesting(createTestBroadcast(id: 'broadcast_idem_sub'));

      // Step 1: didPushNext called first
      state2.didPushNext();
      await tester.pump();
      expect(liveService2.leaveCalls.length, equals(1));

      // Step 2: dispose called afterwards
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Map closed'))));
      await tester.pump();

      // Verify leaveLiveBroadcast was NOT called a second time!
      expect(liveService2.leaveCalls.length, equals(1));
    });
  });
}
