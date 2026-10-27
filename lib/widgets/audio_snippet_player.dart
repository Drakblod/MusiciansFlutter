import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AudioSnippetPlayer extends StatefulWidget {
  final String audioUrl;
  final bool autoPlay;

  const AudioSnippetPlayer({
    super.key,
    required this.audioUrl,
    this.autoPlay = false,
  });

  @override
  State<AudioSnippetPlayer> createState() => _AudioSnippetPlayerState();
}

class _AudioSnippetPlayerState extends State<AudioSnippetPlayer> {
  static const double _comfortableSnippetVolume = 0.70;

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
    } else if (oldWidget.autoPlay && !widget.autoPlay && _playerState == PlayerState.playing) {
      _audioPlayer?.pause();
    }
  }

  Future<void> _initPlayer() async {
    try {
      final player = AudioPlayer();
      _audioPlayer = player;

      // Set release mode to keep resource
      await player.setReleaseMode(ReleaseMode.stop);
      // Set volume with headroom to avoid DAC clipping / distortion on hot audio
      await player.setVolume(_comfortableSnippetVolume);

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

      if (widget.autoPlay) {
        try {
          await player.setVolume(_comfortableSnippetVolume);
          await player.play(_getSource(widget.audioUrl));
          if (mounted) {
            setState(() {
              _playerState = PlayerState.playing;
              _isLoading = false;
            });
          }
        } catch (e) {
          debugPrint("[AudioSnippetPlayer] Autoplay notice (e.g. browser policy): $e");
          try {
            await player.setSource(_getSource(widget.audioUrl));
          } catch (_) {}
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        try {
          await player.setSource(_getSource(widget.audioUrl));
        } catch (e) {
          debugPrint("[AudioSnippetPlayer] Non-fatal notice: Preloading audio source deferred: $e");
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
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

  Source _getSource(String path) {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:') || path.startsWith('data:')) {
      return UrlSource(path);
    }
    if (path.startsWith('assets/') || path.startsWith('audio/')) {
      final cleanPath = path.startsWith('assets/') ? path.substring(7) : path;
      return AssetSource(cleanPath);
    }
    // Device local file path
    return DeviceFileSource(path);
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    try {
      _audioPlayer?.stop();
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
        await _audioPlayer!.setVolume(_comfortableSnippetVolume);
        await _audioPlayer!.resume();
      } else {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
        await _audioPlayer!.setVolume(_comfortableSnippetVolume);
        await _audioPlayer!.play(_getSource(widget.audioUrl));
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C20).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.danger, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 11),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Sleek compact Play/Pause Button
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 24,
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: AppTheme.primaryAccent,
                  ),
                  onPressed: _isLoading ? null : _togglePlayback,
                ),
              ),
              const SizedBox(width: 6),
              // Current elapsed time
              Text(
                _formatDuration(_position),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              // Time Progress Slider (clean, slim & responsive)
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    trackShape: const RectangularSliderTrackShape(),
                    activeTrackColor: AppTheme.primaryAccent,
                    inactiveTrackColor: const Color(0xFF2E2A4E),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                    overlayColor: AppTheme.primaryAccent.withOpacity(0.15),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
              ),
              const SizedBox(width: 4),
              // Total track duration
              Text(
                _formatDuration(_duration),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
