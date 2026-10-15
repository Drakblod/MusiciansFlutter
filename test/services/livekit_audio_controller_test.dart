import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';
import 'package:musicians_flutter/services/live_broadcast_service.dart';
import 'package:musicians_flutter/services/livekit_audio_controller.dart';

void main() {
  group('LiveKitAudioController Audio-Only Lifecycle & State Tests', () {
    late LiveKitAudioController controller;

    setUp(() {
      controller = LiveKitAudioController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('1. Initializes in clean disconnected audio-only default state', () {
      expect(controller.status, LiveKitConnectionStatus.disconnected);
      expect(controller.statusNotifier.value, LiveKitConnectionStatus.disconnected);
      expect(controller.isMuted, isFalse);
      expect(controller.isMutedNotifier.value, isFalse);
      expect(controller.volume, 1.0);
      expect(controller.volumeNotifier.value, 1.0);
      expect(controller.isConnected, isFalse);
      expect(controller.isPublisher, isFalse);
      expect(controller.isListener, isFalse);
      expect(controller.currentRole, isNull);
      expect(controller.currentRoomName, isNull);
      expect(controller.currentBroadcastId, isNull);
    });

    test('2. Role protection rejects mismatched publisher token in connectPublisher', () async {
      const listenerSession = LiveBroadcastSessionToken(
        token: 'mock_listener_token',
        serverUrl: 'wss://livekit.musicians.app',
        roomName: 'room_123',
        role: LiveBroadcastParticipantRole.listener,
        broadcastId: 'broadcast_123',
      );

      expect(
        () => controller.connectPublisher(listenerSession),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('3. Role protection rejects mismatched publisher token in connectListener', () async {
      const publisherSession = LiveBroadcastSessionToken(
        token: 'mock_publisher_token',
        serverUrl: 'wss://livekit.musicians.app',
        roomName: 'room_456',
        role: LiveBroadcastParticipantRole.publisher,
        broadcastId: 'broadcast_456',
      );

      expect(
        () => controller.connectListener(publisherSession),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('4. Volume controller enforces strict clamping between 0.0 and 1.0', () {
      controller.setVolume(0.75);
      expect(controller.volume, 0.75);
      expect(controller.volumeNotifier.value, 0.75);

      controller.setVolume(1.8);
      expect(controller.volume, 1.0);
      expect(controller.volumeNotifier.value, 1.0);

      controller.setVolume(-0.25);
      expect(controller.volume, 0.0);
      expect(controller.volumeNotifier.value, 0.0);
    });

    test('5. Mute toggling updates state and notifies reactive listeners', () async {
      expect(controller.isMuted, isFalse);

      await controller.setMute(true);
      expect(controller.isMuted, isTrue);
      expect(controller.isMutedNotifier.value, isTrue);

      await controller.toggleMute();
      expect(controller.isMuted, isFalse);
      expect(controller.isMutedNotifier.value, isFalse);
    });

    test('6. Disconnect resets current session metadata cleanly', () async {
      await controller.disconnect();
      expect(controller.status, LiveKitConnectionStatus.disconnected);
      expect(controller.currentRole, isNull);
      expect(controller.currentRoomName, isNull);
      expect(controller.currentBroadcastId, isNull);
    });
  });
}
