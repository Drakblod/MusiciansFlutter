import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';
import 'package:musicians_flutter/services/live_broadcast_service.dart';

void main() {
  group('LiveBroadcastSessionToken & Service Contract Tests', () {
    test('1. LiveBroadcastSessionToken deserialization and toMap round-trip', () {
      final tokenData = {
        'token': 'mock_jwt_publisher_token',
        'serverUrl': 'wss://livekit.musicians.app',
        'roomName': 'room_broadcast_123',
        'role': 'publisher',
        'broadcastId': 'broadcast_123',
      };

      final session = LiveBroadcastSessionToken.fromMap(tokenData);

      expect(session.token, 'mock_jwt_publisher_token');
      expect(session.serverUrl, 'wss://livekit.musicians.app');
      expect(session.roomName, 'room_broadcast_123');
      expect(session.role, LiveBroadcastParticipantRole.publisher);
      expect(session.broadcastId, 'broadcast_123');

      final serialized = session.toMap();
      expect(serialized['token'], session.token);
      expect(serialized['role'], 'publisher');
    });

    test('2. LiveBroadcastSessionToken handles listener role cleanly', () {
      final tokenData = {
        'token': 'mock_jwt_listener_token',
        'serverUrl': 'wss://livekit.musicians.app',
        'roomName': 'room_broadcast_456',
        'role': 'listener',
        'broadcastId': 'broadcast_456',
      };

      final session = LiveBroadcastSessionToken.fromMap(tokenData);
      expect(session.role, LiveBroadcastParticipantRole.listener);
    });
  });
}
