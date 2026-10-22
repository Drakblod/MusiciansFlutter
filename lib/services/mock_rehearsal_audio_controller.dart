import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../data/mock_live_rehearsals.dart';
import '../utils/geo_distance.dart';

class MockRehearsalAudioController {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _currentVolumes = {};
  final Map<String, double> _targetVolumes = {};
  final Map<String, double> _distancesKm = {};

  Timer? _throttleTimer;
  Timer? _fadeTimer;
  LatLng? _pendingCameraTarget;
  String? _focusedTargetId;

  bool _isMuted = false;
  bool _isAudioStopped = false;
  bool _isDisposed = false;
  bool _isWebAutoplayBlocked = false;
  bool _isInitialized = false;

  bool get isMuted => _isMuted;
  bool get isAudioStopped => _isAudioStopped;
  bool get isWebAutoplayBlocked => _isWebAutoplayBlocked;
  bool get isInitialized => _isInitialized;
  String? get focusedTargetId => _focusedTargetId;
  Map<String, double> get distancesKm => Map.unmodifiable(_distancesKm);

  final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isAudioStoppedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> webAutoplayBlockedNotifier = ValueNotifier<bool>(false);

  /// Initializes audio players for all mock live rehearsals.
  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;

    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
          respectSilence: false,
        ).build(),
      );
    } catch (e) {
      debugPrint("[MockRehearsalAudio] Error setting global audio context: $e");
    }

    for (final rehearsal in mockLiveRehearsals) {
      final player = AudioPlayer();
      _players[rehearsal.id] = player;
      _currentVolumes[rehearsal.id] = 0.0;
      _targetVolumes[rehearsal.id] = 0.0;
      _distancesKm[rehearsal.id] = double.infinity;

      try {
        await player.setAudioContext(
          AudioContextConfig(
            focus: AudioContextConfigFocus.mixWithOthers,
            respectSilence: false,
          ).build(),
        );
        await player.setReleaseMode(ReleaseMode.loop);

        // Start playback in loop
        await player.play(
          AssetSource(rehearsal.audioAssetPath),
          volume: 0.0,
        );
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Playback initialization error for ${rehearsal.id}: $e");
        if (kIsWeb) {
          _isWebAutoplayBlocked = true;
          webAutoplayBlockedNotifier.value = true;
        }
      }
    }

    _updateDistances(_pendingCameraTarget ?? const LatLng(59.3293, 18.0686));
    _evaluateFocusedTargetVolumes();
  }

  /// Sets the currently focused crosshair target ID.
  /// Only the targeted rehearsal will have audible volume (>0).
  /// Passing null or an ID of another target fades all rehearsal audio to 0.
  void setFocusedTargetId(String? targetId) {
    if (_isDisposed) return;
    if (_focusedTargetId == targetId) return;
    _focusedTargetId = targetId;
    _evaluateFocusedTargetVolumes();
  }

  /// Called when user explicitly taps "Enable rehearsal audio" on Flutter Web if autoplay was blocked.
  Future<void> enableWebAudio() async {
    if (_isDisposed) return;
    _isWebAutoplayBlocked = false;
    webAutoplayBlockedNotifier.value = false;

    for (final rehearsal in mockLiveRehearsals) {
      final player = _players[rehearsal.id];
      if (player != null) {
        try {
          await player.resume();
        } catch (e) {
          debugPrint("[MockRehearsalAudio] Error resuming ${rehearsal.id} on web: $e");
        }
      }
    }

    if (_pendingCameraTarget != null) {
      _updateDistances(_pendingCameraTarget!);
    }
    _evaluateFocusedTargetVolumes();
  }

  /// Receives updated map camera center LatLng to keep distances updated. Throttled to ~150ms.
  void updateCameraTarget(LatLng cameraTarget, {bool immediate = false}) {
    if (_isDisposed) return;
    _pendingCameraTarget = cameraTarget;
    if (!_isInitialized) return;

    if (immediate) {
      _throttleTimer?.cancel();
      _updateDistances(cameraTarget);
      return;
    }

    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 150), () {
      if (_isDisposed || _pendingCameraTarget == null) return;
      _updateDistances(_pendingCameraTarget!);
    });
  }

  void _updateDistances(LatLng cameraTarget) {
    if (_isDisposed) return;
    for (final rehearsal in mockLiveRehearsals) {
      _distancesKm[rehearsal.id] = calculateHaversineDistanceKm(cameraTarget, rehearsal.position);
    }
  }

  /// Sets target volume to 1.0 strictly for the focused crosshair target and 0.0 for all others, then triggers smooth fade.
  void _evaluateFocusedTargetVolumes() {
    if (_isDisposed || _isAudioStopped) return;

    for (final rehearsal in mockLiveRehearsals) {
      final isFocused = rehearsal.id == _focusedTargetId;
      final double targetVol = isFocused ? 1.0 : 0.0;
      _targetVolumes[rehearsal.id] = targetVol;

      final player = _players[rehearsal.id];
      if (player != null && isFocused && targetVol > 0.01 && !_isMuted && !_isAudioStopped && player.state != PlayerState.playing) {
        player.resume();
      }
    }

    _startSmoothVolumeTransition();
  }

  /// Smoothly interpolates current volumes towards target volumes over ~300ms.
  void _startSmoothVolumeTransition() {
    _fadeTimer?.cancel();

    const int steps = 10;
    const Duration stepDuration = Duration(milliseconds: 30);
    int currentStep = 0;

    final Map<String, double> startVolumes = Map.from(_currentVolumes);

    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      if (_isDisposed || _isAudioStopped) {
        timer.cancel();
        return;
      }

      currentStep++;
      final double progress = (currentStep / steps).clamp(0.0, 1.0);

      for (final id in _players.keys) {
        final double start = startVolumes[id] ?? 0.0;
        final double target = _targetVolumes[id] ?? 0.0;
        final double interpolated = start + (target - start) * progress;
        _currentVolumes[id] = interpolated;

        final double effectiveVolume = _isMuted ? 0.0 : interpolated.clamp(0.0, 1.0);
        final player = _players[id];
        if (player != null) {
          player.setVolume(effectiveVolume);
          if (effectiveVolume > 0.01 && player.state != PlayerState.playing) {
            player.resume();
          }
        }
      }

      if (currentStep >= steps) {
        timer.cancel();
      }
    });
  }

  /// Explicitly turns off / stops all audio playback (not just mute).
  Future<void> stopAudio() async {
    _isAudioStopped = true;
    isAudioStoppedNotifier.value = true;
    _fadeTimer?.cancel();
    _throttleTimer?.cancel();

    for (final id in _players.keys) {
      _currentVolumes[id] = 0.0;
      _targetVolumes[id] = 0.0;
      final player = _players[id];
      if (player != null) {
        try {
          await player.stop();
        } catch (e) {
          debugPrint("[MockRehearsalAudio] Error stopping player $id: $e");
        }
      }
    }
  }

  /// Turns audio playback back on.
  Future<void> startAudio() async {
    _isAudioStopped = false;
    isAudioStoppedNotifier.value = false;

    for (final rehearsal in mockLiveRehearsals) {
      final player = _players[rehearsal.id];
      if (player != null) {
        try {
          await player.setReleaseMode(ReleaseMode.loop);
          await player.play(
            AssetSource(rehearsal.audioAssetPath),
            volume: 0.0,
          );
        } catch (e) {
          debugPrint("[MockRehearsalAudio] Error restarting player ${rehearsal.id}: $e");
        }
      }
    }

    if (_pendingCameraTarget != null) {
      _updateDistances(_pendingCameraTarget!);
    }
    _evaluateFocusedTargetVolumes();
  }

  /// Toggles between audio playing and completely stopped.
  void toggleAudioPower() {
    if (_isAudioStopped) {
      startAudio();
    } else {
      stopAudio();
    }
  }

  /// Toggles mute state.
  void toggleMute() {
    if (_isDisposed) return;
    _isMuted = !_isMuted;
    isMutedNotifier.value = _isMuted;

    for (final id in _players.keys) {
      final double effectiveVolume = _isMuted ? 0.0 : (_currentVolumes[id] ?? 0.0).clamp(0.0, 1.0);
      _players[id]?.setVolume(effectiveVolume);
    }
  }

  /// Called on AppLifecycleState pause/inactive.
  void pauseAudio() {
    if (_isDisposed) return;
    _fadeTimer?.cancel();
    for (final player in _players.values) {
      try {
        player.pause();
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Error pausing player: $e");
      }
    }
  }

  /// Called on AppLifecycleState resume. Only resumes if a focused target exists and audio is enabled.
  void resumeAudio() {
    if (_isDisposed || _isWebAutoplayBlocked || _isAudioStopped || _focusedTargetId == null) return;
    final player = _players[_focusedTargetId!];
    if (player != null && !_isMuted) {
      try {
        player.resume();
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Error resuming player: $e");
      }
    }
    _evaluateFocusedTargetVolumes();
  }

  /// Cleans up and disposes all players and timers.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _throttleTimer?.cancel();
    _fadeTimer?.cancel();

    for (final player in _players.values) {
      try {
        player.stop();
        player.dispose();
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Error disposing player: $e");
      }
    }

    _players.clear();
    _currentVolumes.clear();
    _targetVolumes.clear();
    _distancesKm.clear();

    isMutedNotifier.dispose();
    isAudioStoppedNotifier.dispose();
    webAutoplayBlockedNotifier.dispose();
  }
}
