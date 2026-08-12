import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../data/mock_live_rehearsals.dart';
import '../models/mock_live_rehearsal.dart';
import '../utils/geo_distance.dart';

class MockRehearsalAudioController {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _currentVolumes = {};
  final Map<String, double> _targetVolumes = {};
  final Map<String, double> _distancesKm = {};

  Timer? _throttleTimer;
  Timer? _fadeTimer;
  LatLng? _pendingCameraTarget;

  bool _isMuted = false;
  bool _isDisposed = false;
  bool _isWebAutoplayBlocked = false;
  bool _isInitialized = false;

  bool get isMuted => _isMuted;
  bool get isWebAutoplayBlocked => _isWebAutoplayBlocked;
  bool get isInitialized => _isInitialized;
  Map<String, double> get distancesKm => Map.unmodifiable(_distancesKm);

  final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> webAutoplayBlockedNotifier = ValueNotifier<bool>(
    false,
  );

  /// Initializes audio players for all mock live rehearsals.
  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;

    for (final rehearsal in mockLiveRehearsals) {
      final player = AudioPlayer();
      _players[rehearsal.id] = player;
      _currentVolumes[rehearsal.id] = 0.0;
      _targetVolumes[rehearsal.id] = 0.0;
      _distancesKm[rehearsal.id] = double.infinity;

      try {
        await player.setReleaseMode(ReleaseMode.loop);

        // Try playing at 0 volume
        await player.play(AssetSource(rehearsal.audioAssetPath), volume: 0.0);
      } catch (e) {
        debugPrint(
          "[MockRehearsalAudio] Playback initialization error for ${rehearsal.id}: $e",
        );
        if (kIsWeb) {
          _isWebAutoplayBlocked = true;
          webAutoplayBlockedNotifier.value = true;
        }
      }
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
          debugPrint(
            "[MockRehearsalAudio] Error resuming ${rehearsal.id} on web: $e",
          );
        }
      }
    }

    if (_pendingCameraTarget != null) {
      _evaluateDistancesAndVolumes(_pendingCameraTarget!);
    }
  }

  /// Receives updated map camera center LatLng. Throttled to ~150ms.
  void updateCameraTarget(LatLng cameraTarget, {bool immediate = false}) {
    if (_isDisposed || !_isInitialized) return;
    _pendingCameraTarget = cameraTarget;

    if (immediate) {
      _throttleTimer?.cancel();
      _evaluateDistancesAndVolumes(cameraTarget);
      return;
    }

    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 150), () {
      if (_isDisposed || _pendingCameraTarget == null) return;
      _evaluateDistancesAndVolumes(_pendingCameraTarget!);
    });
  }

  /// Calculates distance from map center to each rehearsal, computes target volume, and triggers smooth fade.
  void _evaluateDistancesAndVolumes(LatLng cameraTarget) {
    if (_isDisposed) return;

    String? nearestId;
    double minDistance = double.infinity;

    for (final rehearsal in mockLiveRehearsals) {
      final dist = calculateHaversineDistanceKm(
        cameraTarget,
        rehearsal.position,
      );
      _distancesKm[rehearsal.id] = dist;

      if (dist < audibleRadiusKm && dist < minDistance) {
        minDistance = dist;
        nearestId = rehearsal.id;
      }
    }

    for (final rehearsal in mockLiveRehearsals) {
      final dist = _distancesKm[rehearsal.id] ?? double.infinity;
      final isNearest = rehearsal.id == nearestId;
      final targetVol = calculateRehearsalVolume(dist, isNearest: isNearest);
      _targetVolumes[rehearsal.id] = targetVol;
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
      if (_isDisposed) {
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

        final double effectiveVolume = _isMuted
            ? 0.0
            : interpolated.clamp(0.0, 1.0);
        _players[id]?.setVolume(effectiveVolume);
      }

      if (currentStep >= steps) {
        timer.cancel();
      }
    });
  }

  /// Toggles mute state.
  void toggleMute() {
    if (_isDisposed) return;
    _isMuted = !_isMuted;
    isMutedNotifier.value = _isMuted;

    for (final id in _players.keys) {
      final double effectiveVolume = _isMuted
          ? 0.0
          : (_currentVolumes[id] ?? 0.0).clamp(0.0, 1.0);
      _players[id]?.setVolume(effectiveVolume);
    }
  }

  /// Called on AppLifecycleState pause/inactive.
  void pauseAudio() {
    if (_isDisposed) return;
    for (final player in _players.values) {
      try {
        player.pause();
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Error pausing player: $e");
      }
    }
  }

  /// Called on AppLifecycleState resume.
  void resumeAudio() {
    if (_isDisposed || _isWebAutoplayBlocked) return;
    for (final player in _players.values) {
      try {
        player.resume();
      } catch (e) {
        debugPrint("[MockRehearsalAudio] Error resuming player: $e");
      }
    }
    if (_pendingCameraTarget != null) {
      _evaluateDistancesAndVolumes(_pendingCameraTarget!);
    }
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
    webAutoplayBlockedNotifier.dispose();
  }
}
