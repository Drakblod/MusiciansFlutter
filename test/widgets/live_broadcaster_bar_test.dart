import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';
import 'package:musicians_flutter/widgets/live_broadcaster_bar.dart';

void main() {
  group('LiveBroadcasterBar Widget Tests', () {
    late LiveBroadcast testBroadcast;
    late LiveKitAudioController audioController;

    setUp(() {
      testBroadcast = LiveBroadcast(
        id: 'bc_test_1',
        bandId: 'band_1',
        bandName: 'The Rolling Beats',
        creatorUserId: 'user_1',
        title: 'Sunset Studio Jam',
        latitude: 59.3293,
        longitude: 18.0686,
        status: LiveBroadcastStatus.active,
        startedAt: DateTime.now().subtract(const Duration(minutes: 5, seconds: 20)),
        livekitRoomName: 'room_bc_test_1',
        listenerCount: 8,
      );
      audioController = LiveKitAudioController();
    });

    tearDown(() async {
      await audioController.dispose();
    });

    testWidgets('1. Renders LIVE badge, band name, listener count, and action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveBroadcasterBar(
              broadcast: testBroadcast,
              audioController: audioController,
              onStopBroadcast: () async {},
            ),
          ),
        ),
      );

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('The Rolling Beats'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('2. Tapping mic button toggles mute state reactive icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveBroadcasterBar(
              broadcast: testBroadcast,
              audioController: audioController,
              onStopBroadcast: () async {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(audioController.isMuted, isFalse);

      // Tap mic button to mute
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();

      expect(audioController.isMuted, isTrue);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    });

    testWidgets('3. Tapping End button opens confirmation dialog', (tester) async {
      bool stopCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveBroadcasterBar(
              broadcast: testBroadcast,
              audioController: audioController,
              onStopBroadcast: () async {
                stopCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('End'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('End Live Broadcast?'), findsOneWidget);
      expect(find.text('This will stop the stream for all active listeners.'), findsOneWidget);

      // Confirm stop
      await tester.tap(find.text('End Stream'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(stopCalled, isTrue);
    });
  });
}
