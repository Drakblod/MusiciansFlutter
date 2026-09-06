import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AudioSnippetPlayer extends StatefulWidget {
  final String audioUrl;

  const AudioSnippetPlayer({
    super.key,
    required this.audioUrl,
  });

  @override
  State<AudioSnippetPlayer> createState() => _AudioSnippetPlayerState();
}

class _AudioSnippetPlayerState extends State<AudioSnippetPlayer> {
  AudioPlayer? _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = true;
  String? _errorMessage;

  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerCompleteSubscription;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant AudioSnippetPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _durationSubscription?.cancel();
      _positionSubscription?.cancel();
      _playerStateSubscription?.cancel();
      _playerCompleteSubscription?.cancel();
      try {
        _audioPlayer?.dispose();
      } catch (_) {}
      _audioPlayer = null;
      _isLoading = true;
      _errorMessage = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _playerState = PlayerState.stopped;
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    try {
      final player = AudioPlayer();
      _audioPlayer = player;
      
      // Set release mode to keep resource
      await player.setReleaseMode(ReleaseMode.stop);

      // Listen to changes
      _durationSubscription = player.onDurationChanged.listen((d) {
        if (mounted) {
          setState(() {
            _duration = d;
            _isLoading = false;
          });
        }
      });

      _positionSubscription = player.onPositionChanged.listen((p) {
        if (mounted) {
          setState(() {
            _position = p;
          });
        }
      });

      _playerStateSubscription = player.onPlayerStateChanged.listen((s) {
        if (mounted) {
          setState(() {
            _playerState = s;
          });
        }
      });

      _playerCompleteSubscription = player.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _playerState = PlayerState.completed;
          });
        }
      });

      try {
        await player.setSource(UrlSource(widget.audioUrl));
      } catch (e) {
        debugPrint("[AudioSnippetPlayer] Non-fatal notice: Preloading audio source deferred: $e");
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint("[AudioSnippetPlayer] Error initializing AudioPlayer: $e\n$stack");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Audio playback initialization error. Tap play to try.";
        });
      }
    }
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    try {
      _audioPlayer?.dispose();
    } catch (e) {
      debugPrint("[AudioSnippetPlayer] Error disposing AudioPlayer: $e");
    }
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_audioPlayer == null) {
      await _initPlayer();
      if (_audioPlayer == null) return;
    }
    try {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer!.pause();
      } else if (_playerState == PlayerState.paused) {
        await _audioPlayer!.resume();
      } else {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
        await _audioPlayer!.play(UrlSource(widget.audioUrl));
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e, stack) {
      debugPrint("[AudioSnippetPlayer] Playback error: $e\n$stack");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Playback error. Tap to retry.";
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.audiotrack_rounded,
                  color: AppTheme.primaryAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MUSIC SNIPPET',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (_isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.danger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() => _errorMessage = null);
                      _togglePlayback();
                    },
                    child: Text(
                      'Retry',
                      style: GoogleFonts.inter(
                        color: AppTheme.primaryAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Play/Pause Button
              IconButton(
                padding: EdgeInsets.zero,
                iconSize: 36,
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: _isLoading ? null : _togglePlayback,
              ),
              const SizedBox(width: 8),
              // Time Progress and Slider
              Expanded(
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: AppTheme.primaryAccent,
                        inactiveTrackColor: const Color(0xFF2E2A4E),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayColor: AppTheme.primaryAccent.withOpacity(0.2),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        min: 0.0,
                        max: _duration.inMilliseconds.toDouble() > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 1.0,
                        value: _position.inMilliseconds.toDouble().clamp(
                              0.0,
                              _duration.inMilliseconds.toDouble() > 0
                                  ? _duration.inMilliseconds.toDouble()
                                  : 1.0,
                            ),
                        onChanged: _isLoading || _audioPlayer == null
                            ? null
                            : (value) async {
                                final duration = Duration(milliseconds: value.toInt());
                                await _audioPlayer!.seek(duration);
                              },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
