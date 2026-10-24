import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../data/mock_live_rehearsals.dart';
import '../utils/geo_distance.dart';
import '../utils/map_crosshair_targeting.dart';

class MockRehearsalAudioController {
  /// Singleton / active instance tracker for global lifecycle & navigation audio stops.
  static MockRehearsalAudioController? activeInstance;

  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _currentVolumes = {};
  final Map<String, double> _targetVolumes = {};
  final Map<String, double> _distancesKm = {};

  Timer? _throttleTimer;
  Timer? _fadeTimer;
  LatLng? _pendingCameraTarget;
  double _currentZoom = 12.0;
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

  /// Helper to immediately pause map audio from anywhere in the app (e.g. navigation / top bar).
  static void pauseActiveAudio() {
    activeInstance?.pauseAudio();
  }

  /// Helper to immediately stop map audio from anywhere in the app.
  static void stopActiveAudio() {
    activeInstance?.stopAudio();
  }

  /// Initializes audio players for all mock live rehearsals.
  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;
    activeInstance = this;

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

        // Start playback in loop with initial volume 0.0
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

    _evaluateDistancesAndVolumes(
      _pendingCameraTarget ?? const LatLng(59.3293, 18.0686),
      _currentZoom,
    );
  }

  /// Sets the currently focused crosshair target ID.
  /// If the target is a rehearsal pin, audio focuses on it and scales with distance.
  /// Passing null or an ID of a non-rehearsal target smoothly evaluates proximity to nearest rehearsal.
  void setFocusedTargetId(String? targetId) {
    if (_isDisposed) return;
    if (_focusedTargetId == targetId) return;
    _focusedTargetId = targetId;
    if (_pendingCameraTarget != null) {
      _evaluateDistancesAndVolumes(_pendingCameraTarget!, _currentZoom);
    }
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
      _evaluateDistancesAndVolumes(_pendingCameraTarget!, _currentZoom);
    }
  }

  /// Receives updated map camera center LatLng and zoom to keep distances and proximity volume updated.
  void updateCameraTarget(LatLng cameraTarget, {bool immediate = false, double? zoom}) {
    if (_isDisposed) return;
    _pendingCameraTarget = cameraTarget;
    if (zoom != null && zoom.isFinite) {
      _currentZoom = zoom;
    }
    if (!_isInitialized) return;

    if (immediate) {
      _throttleTimer?.cancel();
      _evaluateDistancesAndVolumes(cameraTarget, _currentZoom);
      return;
    }

    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 150), () {
      if (_isDisposed || _pendingCameraTarget == null) return;
      _evaluateDistancesAndVolumes(_pendingCameraTarget!, _currentZoom);
    });
  }

  /// Calculates distance from camera to each rehearsal and evaluates organic, linear proximity volume.
  void _evaluateDistancesAndVolumes(LatLng cameraTarget, double zoom) {
    if (_isDisposed || _isAudioStopped) return;

    // 1. Calculate geographical distance to all rehearsals
    String? nearestId;
    double minDistanceKm = double.infinity;

    for (final rehearsal in mockLiveRehearsals) {
      final distKm = calculateHaversineDistanceKm(cameraTarget, rehearsal.position);
      _distancesKm[rehearsal.id] = distKm;
      if (distKm < minDistanceKm) {
        minDistanceKm = distKm;
        nearestId = rehearsal.id;
      }
    }

    // 2. Compute zoom-aware audible radius in meters
    // MapCrosshairTargeting.metersPerPixel provides accurate mercator ground resolution
    final mpp = MapCrosshairTargeting.metersPerPixel(cameraTarget.latitude, zoom);
    // 600 display pixels represents ~1.5x mobile viewport radius
    // Clamped between 1.5 km (street zoom) and 80 km (country/overview zoom)
    final double audibleRadiusMeters = (mpp * 600.0).clamp(1500.0, 80000.0);
    final double audibleRadiusKm = audibleRadiusMeters / 1000.0;

    // 3. Determine active rehearsal:
    // If a specific rehearsal is focused in the crosshair, it takes precedence.
    // Otherwise, the geographically closest rehearsal within the audible radius is active.
    String? activeRehearsalId;
    if (_focusedTargetId != null) {
      final isFocusedRehearsal = mockLiveRehearsals.any((r) => r.id == _focusedTargetId);
      if (isFocusedRehearsal) {
        activeRehearsalId = _focusedTargetId;
      }
    }
    activeRehearsalId ??= (minDistanceKm <= audibleRadiusKm ? nearestId : null);

    // 4. Calculate target volumes (organic linear decay with distance)
    for (final rehearsal in mockLiveRehearsals) {
      double targetVol = 0.0;

      if (!_isAudioStopped && !_isMuted && rehearsal.id == activeRehearsalId) {
        final distKm = _distancesKm[rehearsal.id] ?? double.infinity;
        if (distKm <= audibleRadiusKm) {
          // Strictly linear decay: 1.0 at pin center (0km) down to 0.0 at audibleRadiusKm
          final double normalized = (1.0 - (distKm / audibleRadiusKm)).clamp(0.0, 1.0);
          targetVol = normalized;
        }
      }

      _targetVolumes[rehearsal.id] = targetVol;

      final player = _players[rehearsal.id];
      if (player != null && targetVol > 0.01 && !_isMuted && !_isAudioStopped && player.state != PlayerState.playing) {
        player.resume();
      }
    }

    _startSmoothVolumeTransition();
  }

  /// Smoothly interpolates current volumes towards target volumes over ~250ms.
  void _startSmoothVolumeTransition() {
    _fadeTimer?.cancel();

    const int steps = 10;
    const Duration stepDuration = Duration(milliseconds: 25);
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
          } else if (effectiveVolume <= 0.005 && player.state == PlayerState.playing) {
            player.pause();
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
          await player.setVolume(0.0);
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
      _evaluateDistancesAndVolumes(_pendingCameraTarget!, _currentZoom);
    }
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

  /// Called on AppLifecycleState pause/inactive or when navigating away from Map View.
  void pauseAudio() {
    if (_isDisposed) return;
    _fadeTimer?.cancel();
    for (final id in _players.keys) {
      _currentVolumes[id] = 0.0;
      _targetVolumes[id] = 0.0;
      final player = _players[id];
      if (player != null) {
        try {
          player.setVolume(0.0);
          player.pause();
        } catch (e) {
          debugPrint("[MockRehearsalAudio] Error pausing player: $e");
        }
      }
    }
  }

  /// Called on AppLifecycleState resume or when returning to Map View.
  void resumeAudio() {
    if (_isDisposed || _isWebAutoplayBlocked || _isAudioStopped) return;
    if (_pendingCameraTarget != null) {
      _evaluateDistancesAndVolumes(_pendingCameraTarget!, _currentZoom);
    }
  }

  /// Cleans up and disposes all players and timers.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (identical(activeInstance, this)) {
      activeInstance = null;
    }

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
