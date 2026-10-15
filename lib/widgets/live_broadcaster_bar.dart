import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/live_broadcast.dart';
import '../services/livekit_audio_controller.dart';
import '../theme/app_theme.dart';

class LiveBroadcasterBar extends StatefulWidget {
  final LiveBroadcast broadcast;
  final LiveKitAudioController audioController;
  final Future<void> Function() onStopBroadcast;
  final EdgeInsetsGeometry? margin;

  const LiveBroadcasterBar({
    super.key,
    required this.broadcast,
    required this.audioController,
    required this.onStopBroadcast,
    this.margin,
  });

  @override
  State<LiveBroadcasterBar> createState() => _LiveBroadcasterBarState();
}

class _LiveBroadcasterBarState extends State<LiveBroadcasterBar> with SingleTickerProviderStateMixin {
  late Timer _durationTimer;
  Duration _elapsed = Duration.zero;
  late AnimationController _pulseController;
  bool _isStopping = false;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.broadcast.startedAt);
    if (_elapsed.isNegative) _elapsed = Duration.zero;

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.broadcast.startedAt);
        });
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _durationTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<void> _confirmEndBroadcast() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'End Live Broadcast?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will stop the stream for all active listeners.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              'End Stream',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isStopping = true);
      try {
        await widget.onStopBroadcast();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error ending broadcast: $e')),
          );
          setState(() => _isStopping = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerRed.withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.dangerRed.withOpacity(0.25),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing red live badge
          FadeTransition(
            opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_pulseController),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, color: Colors.white, size: 8),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Band and timer info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.broadcast.bandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(_elapsed),
                      style: GoogleFonts.robotoMono(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.headset_rounded, color: Colors.white38, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${widget.broadcast.listenerCount}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Mute mic button
          ValueListenableBuilder<bool>(
            valueListenable: widget.audioController.isMutedNotifier,
            builder: (context, isMuted, child) {
              return IconButton(
                icon: Icon(
                  isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: isMuted ? AppTheme.warningYellow : Colors.white,
                  size: 20,
                ),
                tooltip: isMuted ? 'Unmute microphone' : 'Mute microphone',
                onPressed: () => widget.audioController.toggleMute(),
              );
            },
          ),

          // End Stream button
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _isStopping ? null : _confirmEndBroadcast,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRed,
                disabledBackgroundColor: AppTheme.dangerRed.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: _isStopping
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'End',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
