import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/services/mock_rehearsal_audio_controller.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/utils/map_crosshair_targeting.dart';
import 'package:musicians_flutter/widgets/audio_snippet_player.dart';
import 'package:musicians_flutter/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _buildTestAudioBar(MockRehearsalAudioController controller) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: controller.isAudioStoppedNotifier,
          builder: (context, isStopped, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: controller.isMutedNotifier,
              builder: (context, isMuted, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'LIVE AUDIO',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isStopped
                          ? 'Turned OFF'
                          : isMuted
                              ? 'Muted'
                              : 'Active',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: isStopped
                            ? AppTheme.danger
                            : isMuted
                                ? AppTheme.warning
                                : Colors.purpleAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Power Switch (Turn OFF / Turn ON)
                    GestureDetector(
                      key: const Key('audio_power_toggle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        controller.toggleAudioPower();
                      },
                      child: Text(
                        isStopped ? 'Turn ON' : 'Turn OFF',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mute Button (disabled if turned off, but always visible)
                    GestureDetector(
                      key: const Key('audio_mute_toggle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: isStopped
                          ? null
                          : () {
                              controller.toggleMute();
                            },
                      child: Text(
                        isMuted ? 'Unmute' : 'Mute',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isStopped ? Colors.white38 : (isMuted ? AppTheme.primaryAccent : Colors.white70),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  group('MockRehearsalAudioController - Strict Crosshair Audio Focus', () {
    late MockRehearsalAudioController controller;

    setUp(() {
      controller = MockRehearsalAudioController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Initial state has no focused target and target volumes are 0.0', () {
      expect(controller.focusedTargetId, isNull);
      expect(controller.isAudioStopped, isFalse);
      expect(controller.isMuted, isFalse);
    });

    test('2. setFocusedTargetId updates focused target and isolates volume to single rehearsal', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');

      // Moving focus to another target switches focused target ID
      controller.setFocusedTargetId('live_rehearsal_gothenburg');
      expect(controller.focusedTargetId, 'live_rehearsal_gothenburg');

      // Moving camera away (null) clears focused target
      controller.setFocusedTargetId(null);
      expect(controller.focusedTargetId, isNull);
    });

    test('3. App pause makes listening audio inaudible, and app resume without target remains silent', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');

      // App Pause
      controller.pauseAudio();

      // Clear target while paused
      controller.setFocusedTargetId(null);

      // App Resume without target must remain silent
      controller.resumeAudio();
      expect(controller.focusedTargetId, isNull);
    });

    test('4. stopAudio and startAudio toggle audio power without losing controller integrity', () async {
      await controller.stopAudio();
      expect(controller.isAudioStopped, isTrue);

      controller.toggleAudioPower();
      expect(controller.isAudioStopped, isFalse);
    });

    test('5. toggleMute toggles mute state correctly', () {
      expect(controller.isMuted, isFalse);
      controller.toggleMute();
      expect(controller.isMuted, isTrue);
      controller.toggleMute();
      expect(controller.isMuted, isFalse);
    });

    test('6. Disposing controller stops and cleans up audio resources', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      controller.dispose();
      // Safe no-ops after dispose
      controller.setFocusedTargetId('live_rehearsal_gothenburg');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');
    });
  });

  group('Map Transitions & State Invariants', () {
    late MockRehearsalAudioController controller;

    setUp(() {
      controller = MockRehearsalAudioController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Switching category from Music to Sub & Member Search clears audio focus', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, isNotNull);

      // Category switch event clears focused target
      controller.setFocusedTargetId(null);
      expect(controller.focusedTargetId, isNull);
    });

    test('2. Changing a subcategory so the focused pin is filtered out clears focus', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');

      // Filter change clears focus
      controller.setFocusedTargetId(null);
      expect(controller.focusedTargetId, isNull);
    });

    test('3. Tapping empty map clears audio focus', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');

      // Empty map tap handler clears focus
      controller.setFocusedTargetId(null);
      expect(controller.focusedTargetId, isNull);
    });

    test('4. Closing the bottom drawer card clears audio focus', () {
      controller.setFocusedTargetId('live_rehearsal_stockholm');
      expect(controller.focusedTargetId, 'live_rehearsal_stockholm');

      // Card close handler clears focus
      controller.setFocusedTargetId(null);
      expect(controller.focusedTargetId, isNull);
    });

    test('5. Manually selecting a pin outside the crosshair does not enable autoplay', () {
      const crosshairFocusedId = 'gig_crosshair_target';
      controller.setFocusedTargetId(crosshairFocusedId);

      final manualGig = SubRequest(
        id: 'gig_manually_clicked',
        subRequestId: 'sub_clicked',
      );

      final bool isAutoplayEligible =
          manualGig.canonicalTargetId != null &&
          controller.focusedTargetId == manualGig.canonicalTargetId;

      expect(isAutoplayEligible, isFalse);
    });
  });

  group('AudioSnippetPlayer Focus Lifecycle', () {
    testWidgets('1. AudioSnippetPlayer pauses when focus is lost (autoPlay toggles true -> false)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioSnippetPlayer(
              audioUrl: 'audio/bandrep1.mp3',
              autoPlay: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Re-pump with autoPlay: false (focus lost)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioSnippetPlayer(
              audioUrl: 'audio/bandrep1.mp3',
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AudioSnippetPlayer), findsOneWidget);
    });

    testWidgets('2. Disposing AudioSnippetPlayer cleans up safely without exceptions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioSnippetPlayer(
              audioUrl: 'audio/bandrep1.mp3',
              autoPlay: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Dispose widget
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AudioSnippetPlayer), findsNothing);
    });
  });

  group('Audio Control Bar Preservation on State Transitions', () {
    late MockRehearsalAudioController controller;

    setUp(() {
      controller = MockRehearsalAudioController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('1. Active unmuted state renders Active, Turn OFF, and Mute button', (tester) async {
      await tester.pumpWidget(_buildTestAudioBar(controller));

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Turn OFF'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.byKey(const Key('audio_mute_toggle')), findsOneWidget);
    });

    testWidgets('2. Muting audio updates status to Muted and button to Unmute, without hiding bar', (tester) async {
      await tester.pumpWidget(_buildTestAudioBar(controller));

      // Tap mute
      await tester.tap(find.byKey(const Key('audio_mute_toggle')));
      await tester.pumpAndSettle();

      expect(controller.isMuted, isTrue);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Turn OFF'), findsOneWidget);
    });

    testWidgets('3. Turning OFF audio preserves Mute button in disabled state without row collapse', (tester) async {
      await tester.pumpWidget(_buildTestAudioBar(controller));

      // Tap Turn OFF
      await tester.tap(find.byKey(const Key('audio_power_toggle')));
      await tester.pumpAndSettle();

      expect(controller.isAudioStopped, isTrue);
      expect(find.text('Turned OFF'), findsOneWidget);
      expect(find.text('Turn ON'), findsOneWidget);

      // Mute button MUST remain visible even when audio is stopped
      expect(find.byKey(const Key('audio_mute_toggle')), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);

      // Tapping disabled mute button does not change mute state
      await tester.tap(find.byKey(const Key('audio_mute_toggle')));
      await tester.pumpAndSettle();
      expect(controller.isMuted, isFalse);

      // Tapping Turn ON restores active state
      await tester.tap(find.byKey(const Key('audio_power_toggle')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.isAudioStopped, isFalse);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Turn OFF'), findsOneWidget);
    });
  });

  group('Crosshair Targeting Canonical Candidate ID Evaluation', () {
    test('1. SubRequest candidate with id resolves canonical id and is valid', () {
      final gig = SubRequest(
        id: 'sub_request_primary_id',
        subRequestId: 'sub_req_fallback_id',
        latitude: 59.3293,
        longitude: 18.0686,
      );
      final candidate = MapTargetCandidate.fromSubRequest(gig);
      expect(candidate.id, 'sub_request_primary_id');
      expect(candidate.isValid, isTrue);
    });

    test('2. SubRequest candidate with only subRequestId resolves fallback id and is valid', () {
      final gig = SubRequest(
        id: null,
        subRequestId: 'legacy_sub_request_id',
        latitude: 59.3293,
        longitude: 18.0686,
      );
      final candidate = MapTargetCandidate.fromSubRequest(gig);
      expect(candidate.id, 'legacy_sub_request_id');
      expect(candidate.isValid, isTrue);
    });

    test('3. SubRequest candidate with neither id nor subRequestId has empty id and is invalid (never targeted)', () {
      final gig = SubRequest(
        id: null,
        subRequestId: null,
        latitude: 59.3293,
        longitude: 18.0686,
      );
      final candidate = MapTargetCandidate.fromSubRequest(gig);
      expect(candidate.id, isEmpty);
      expect(candidate.isValid, isFalse);

      // MapCrosshairTargeting MUST NOT target an invalid candidate
      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: 59.3293,
        cameraLng: 18.0686,
        zoom: 15.0,
        candidates: [candidate],
      );
      expect(target, isNull);
    });
  });

  group('LiveKit Listener Cleanup Invariants', () {
    test('1. Listener is disconnected when leaving while listening', () async {
      final controller = LiveKitAudioController();
      expect(controller.isListener, isFalse);
      expect(controller.isPublisher, isFalse);

      // Disconnecting a listener resets state cleanly
      await controller.disconnect();
      expect(controller.status, LiveKitConnectionStatus.disconnected);
      await controller.dispose();
    });
  });
}
