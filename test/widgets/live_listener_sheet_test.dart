import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';
import 'package:musicians_flutter/widgets/live_listener_sheet.dart';

void main() {
  group('LiveListenerSheet Widget Tests', () {
    late LiveBroadcast testBroadcast;
    late LiveKitAudioController audioController;

    setUp(() {
      testBroadcast = LiveBroadcast(
        id: 'bc_listener_1',
        bandId: 'band_alpha',
        bandName: 'Nordic Jazz',
        creatorUserId: 'user_jazz',
        title: 'Fasching Soundcheck',
        genre: 'Jazz',
        location: 'Stockholm, Sweden',
        latitude: 59.334,
        longitude: 18.056,
        status: LiveBroadcastStatus.active,
        startedAt: DateTime.now(),
        livekitRoomName: 'room_bc_listener_1',
        listenerCount: 12,
      );
      audioController = LiveKitAudioController();
    });

    tearDown(() async {
      await audioController.dispose();
    });

    testWidgets('1. Renders broadcast info, LIVE STREAM badge, and Listen Live button', (tester) async {
      bool startCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveListenerSheet(
              broadcast: testBroadcast,
              audioController: audioController,
              isCurrentlyListening: false,
              onStartListening: () {
                startCalled = true;
              },
              onStopListening: () {},
            ),
          ),
        ),
      );

      expect(find.text('LIVE STREAM'), findsOneWidget);
      expect(find.text('Nordic Jazz'), findsOneWidget);
      expect(find.text('Fasching Soundcheck'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('12 listeners'), findsOneWidget);
      expect(find.text('Listen Live'), findsOneWidget);

      await tester.tap(find.text('Listen Live'));
      expect(startCalled, isTrue);
    });

    testWidgets('2. Renders volume slider and Leave Live Stream button when listening', (tester) async {
      bool stopCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveListenerSheet(
              broadcast: testBroadcast,
              audioController: audioController,
              isCurrentlyListening: true,
              onStartListening: () {},
              onStopListening: () {
                stopCalled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Leave Live Stream'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.text('Leave Live Stream'));
      expect(stopCalled, isTrue);
    });
  });
}
