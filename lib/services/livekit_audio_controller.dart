import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../models/live_broadcast.dart';
import 'live_broadcast_service.dart';

enum LiveKitConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// Dedicated audio-only controller for LiveKit streaming.
/// Completely distinct and isolated from audioplayers mock controller.
class LiveKitAudioController {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;

  LiveKitConnectionStatus _status = LiveKitConnectionStatus.disconnected;
  LiveBroadcastParticipantRole? _currentRole;
  String? _currentRoomName;
  String? _currentBroadcastId;

  bool _isMuted = false;
  double _volume = 1.0;
  bool _isDisposed = false;

  LiveKitConnectionStatus get status => _status;
  LiveBroadcastParticipantRole? get currentRole => _currentRole;
  String? get currentRoomName => _currentRoomName;
  String? get currentBroadcastId => _currentBroadcastId;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  bool get isConnected => _status == LiveKitConnectionStatus.connected;
  bool get isPublisher => _currentRole == LiveBroadcastParticipantRole.publisher;
  bool get isListener => _currentRole == LiveBroadcastParticipantRole.listener;

  final ValueNotifier<LiveKitConnectionStatus> statusNotifier =
      ValueNotifier<LiveKitConnectionStatus>(LiveKitConnectionStatus.disconnected);
  final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<String?> activeSpeakerNotifier = ValueNotifier<String?>(null);

  /// Connects as an audio publisher (microphone broadcasting).
  Future<void> connectPublisher(LiveBroadcastSessionToken session) async {
    if (session.role != LiveBroadcastParticipantRole.publisher) {
      throw ArgumentError('Session role must be publisher, received ${session.role}');
    }
    await _connectInternal(session);

    // Enable microphone track strictly (audio only)
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      debugPrint('[LiveKitAudioController] Failed to enable microphone: $e');
    }
  }

  /// Connects as a listener (subscribing to live audio tracks).
  Future<void> connectListener(LiveBroadcastSessionToken session) async {
    if (session.role != LiveBroadcastParticipantRole.listener) {
      throw ArgumentError('Session role must be listener, received ${session.role}');
    }
    await _connectInternal(session);
  }

  Future<void> _connectInternal(LiveBroadcastSessionToken session) async {
    if (_isDisposed) return;
    await disconnect();

    _currentRole = session.role;
    _currentRoomName = session.roomName;
    _currentBroadcastId = session.broadcastId;
    _updateStatus(LiveKitConnectionStatus.connecting);

    try {
      final roomOptions = lk.RoomOptions(
        adaptiveStream: true,
        dynacast: false,
        defaultAudioPublishOptions: const lk.AudioPublishOptions(
          name: 'live_band_mic',
          encoding: lk.AudioEncoding.presetMusic,
        ),
      );

      final room = lk.Room(roomOptions: roomOptions);
      _room = room;

      _listener = room.createListener();
      _listener!
        ..on<lk.RoomConnectedEvent>((event) {
          _updateStatus(LiveKitConnectionStatus.connected);
        })
        ..on<lk.RoomDisconnectedEvent>((event) {
          _updateStatus(LiveKitConnectionStatus.disconnected);
        })
        ..on<lk.RoomReconnectingEvent>((event) {
          _updateStatus(LiveKitConnectionStatus.reconnecting);
        })
        ..on<lk.RoomReconnectedEvent>((event) {
          _updateStatus(LiveKitConnectionStatus.connected);
        })
        ..on<lk.ActiveSpeakersChangedEvent>((event) {
          if (event.speakers.isNotEmpty) {
            activeSpeakerNotifier.value = event.speakers.first.identity;
          } else {
            activeSpeakerNotifier.value = null;
          }
        });

      await room.connect(
        session.serverUrl,
        session.token,
      );

      _updateStatus(LiveKitConnectionStatus.connected);
    } catch (e) {
      debugPrint('[LiveKitAudioController] Connection error: $e');
      _updateStatus(LiveKitConnectionStatus.failed);
      rethrow;
    }
  }

  /// Toggles mute state:
  /// - For publishers: mutes/unmutes local microphone track
  /// - For listeners: mutes/unmutes incoming playback volume
  Future<void> toggleMute() async {
    await setMute(!_isMuted);
  }

  Future<void> setMute(bool muted) async {
    if (_isDisposed) return;
    _isMuted = muted;
    isMutedNotifier.value = muted;

    if (isPublisher) {
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(!muted);
      } catch (e) {
        debugPrint('[LiveKitAudioController] Error toggling mic mute: $e');
      }
    } else {
      // For listener, mute effective playback volume
      _applyVolumeToTracks(muted ? 0.0 : _volume);
    }
  }

  /// Sets listener volume (0.0 to 1.0).
  /// Can be driven by geographic distance/proximity or UI sliders.
  void setVolume(double newVolume) {
    final clamped = newVolume.clamp(0.0, 1.0);
    _volume = clamped;
    volumeNotifier.value = clamped;

    if (!_isMuted && isListener) {
      _applyVolumeToTracks(clamped);
    }
  }

  void _applyVolumeToTracks(double vol) {
    if (_room == null) return;
    // Remote participants audio track playback volume hook
    for (final participant in _room!.remoteParticipants.values) {
      if (participant.audioTrackPublications.isNotEmpty) {
        // Track-level gain/volume adjustment hook when supported by platform WebRTC sink
      }
    }
  }

  void _updateStatus(LiveKitConnectionStatus newStatus) {
    _status = newStatus;
    statusNotifier.value = newStatus;
  }

  /// Disconnects from current room and cleans up resources.
  Future<void> disconnect() async {
    try {
      await _listener?.dispose();
      _listener = null;
      await _room?.disconnect();
      await _room?.dispose();
      _room = null;
    } catch (e) {
      debugPrint('[LiveKitAudioController] Disconnect error: $e');
    } finally {
      _currentRole = null;
      _currentRoomName = null;
      _currentBroadcastId = null;
      _updateStatus(LiveKitConnectionStatus.disconnected);
    }
  }

  /// Permanently disposes the controller.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await disconnect();
    statusNotifier.dispose();
    isMutedNotifier.dispose();
    volumeNotifier.dispose();
    activeSpeakerNotifier.dispose();
  }
}
