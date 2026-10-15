import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/live_broadcast.dart';

void main() {
  group('LiveBroadcast Model & State Transition Tests', () {
    test('1. Deserializes valid RTDB map into LiveBroadcast model', () {
      final now = DateTime.now();
      final map = {
        'bandId': 'band_123',
        'bandName': 'The Echoes',
        'creatorUserId': 'user_abc',
        'title': 'Live Studio Session',
        'description': 'Rehearsing new tracks',
        'genre': 'Rock',
        'location': 'Stockholm',
        'latitude': 59.3293,
        'longitude': 18.0686,
        'status': 'active',
        'startedAt': now.millisecondsSinceEpoch,
        'livekitRoomName': 'room_broadcast_band_123',
        'listenerCount': 5,
        'audioOnly': true,
        'hasActiveAudioTrack': true,
      };

      final broadcast = LiveBroadcast.fromMap('broadcast_123', map);

      expect(broadcast.id, 'broadcast_123');
      expect(broadcast.bandId, 'band_123');
      expect(broadcast.bandName, 'The Echoes');
      expect(broadcast.creatorUserId, 'user_abc');
      expect(broadcast.title, 'Live Studio Session');
      expect(broadcast.description, 'Rehearsing new tracks');
      expect(broadcast.genre, 'Rock');
      expect(broadcast.location, 'Stockholm');
      expect(broadcast.latitude, 59.3293);
      expect(broadcast.longitude, 18.0686);
      expect(broadcast.status, LiveBroadcastStatus.active);
      expect(broadcast.isActive, isTrue);
      expect(broadcast.isEnded, isFalse);
      expect(broadcast.isPaused, isFalse);
      expect(broadcast.livekitRoomName, 'room_broadcast_band_123');
      expect(broadcast.listenerCount, 5);
      expect(broadcast.audioOnly, isTrue);
      expect(broadcast.hasActiveAudioTrack, isTrue);
    });

    test('2. Round-trip serialization preserves all broadcast fields', () {
      final started = DateTime.utc(2026, 10, 15, 14, 0);
      final ended = DateTime.utc(2026, 10, 15, 16, 0);

      final original = LiveBroadcast(
        id: 'bc_999',
        bandId: 'band_777',
        bandName: 'Nordic Jazz Quartet',
        creatorUserId: 'user_leader',
        title: 'Fasching Soundcheck',
        description: 'Testing live mix',
        genre: 'Jazz',
        location: 'Kungsgatan 63',
        latitude: 59.334,
        longitude: 18.056,
        status: LiveBroadcastStatus.ended,
        startedAt: started,
        endedAt: ended,
        livekitRoomName: 'room_bc_999',
        listenerCount: 14,
        audioOnly: true,
        hasActiveAudioTrack: false,
      );

      final map = original.toMap();
      final reconstructed = LiveBroadcast.fromMap('bc_999', map);

      expect(reconstructed.id, original.id);
      expect(reconstructed.bandId, original.bandId);
      expect(reconstructed.bandName, original.bandName);
      expect(reconstructed.creatorUserId, original.creatorUserId);
      expect(reconstructed.title, original.title);
      expect(reconstructed.status, LiveBroadcastStatus.ended);
      expect(reconstructed.isActive, isFalse);
      expect(reconstructed.isEnded, isTrue);
      expect(reconstructed.listenerCount, 14);
      expect(reconstructed.endedAt?.millisecondsSinceEpoch, ended.millisecondsSinceEpoch);
    });

    test('3. Status parsing handles varied casing and aliases gracefully', () {
      expect(LiveBroadcastStatus.fromString('active'), LiveBroadcastStatus.active);
      expect(LiveBroadcastStatus.fromString('ACTIVE'), LiveBroadcastStatus.active);
      expect(LiveBroadcastStatus.fromString('live'), LiveBroadcastStatus.active);
      expect(LiveBroadcastStatus.fromString('paused'), LiveBroadcastStatus.paused);
      expect(LiveBroadcastStatus.fromString('ended'), LiveBroadcastStatus.ended);
      expect(LiveBroadcastStatus.fromString('stopped'), LiveBroadcastStatus.ended);
      expect(LiveBroadcastStatus.fromString('unknown_val'), LiveBroadcastStatus.ended);
      expect(LiveBroadcastStatus.fromString(null), LiveBroadcastStatus.ended);
    });

    test('4. Participant role parsing handles publisher and listener', () {
      expect(LiveBroadcastParticipantRole.fromString('publisher'), LiveBroadcastParticipantRole.publisher);
      expect(LiveBroadcastParticipantRole.fromString('PUBLISHER'), LiveBroadcastParticipantRole.publisher);
      expect(LiveBroadcastParticipantRole.fromString('listener'), LiveBroadcastParticipantRole.listener);
      expect(LiveBroadcastParticipantRole.fromString('anything_else'), LiveBroadcastParticipantRole.listener);
      expect(LiveBroadcastParticipantRole.fromString(null), LiveBroadcastParticipantRole.listener);
    });

    test('5. canStop enforces strict authority rules', () {
      final broadcast = LiveBroadcast(
        id: 'bc_auth',
        bandId: 'band_alpha',
        bandName: 'Alpha Band',
        creatorUserId: 'user_creator',
        title: 'Rehearsal',
        latitude: 59.0,
        longitude: 18.0,
        status: LiveBroadcastStatus.active,
        startedAt: DateTime.now(),
        livekitRoomName: 'room_bc_auth',
      );

      // Creator is always permitted
      expect(broadcast.canStop('user_creator'), isTrue);
      expect(broadcast.canStop('user_creator', isBandLeaderOrAdmin: false), isTrue);

      // Band leader or admin is permitted even if not creator
      expect(broadcast.canStop('user_leader', isBandLeaderOrAdmin: true), isTrue);

      // Random user is rejected
      expect(broadcast.canStop('random_listener', isBandLeaderOrAdmin: false), isFalse);

      // Null user is rejected
      expect(broadcast.canStop(null, isBandLeaderOrAdmin: true), isFalse);
    });
  });
}
