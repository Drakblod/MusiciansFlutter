import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/live_broadcast.dart';
import '../services/livekit_audio_controller.dart';
import '../theme/app_theme.dart';

class LiveListenerBar extends StatelessWidget {
  final LiveBroadcast broadcast;
  final LiveKitAudioController audioController;
  final VoidCallback onLeave;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? margin;

  const LiveListenerBar({
    super.key,
    required this.broadcast,
    required this.audioController,
    required this.onLeave,
    required this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.7), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryAccent.withOpacity(0.25),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            // Live badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.headphones_rounded, color: Colors.white, size: 10),
                  const SizedBox(width: 4),
                  Text(
                    'LISTENING',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Band and track status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    broadcast.bandName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: audioController.audioPlaybackBlockedNotifier,
                    builder: (context, isBlocked, _) {
                      if (isBlocked) {
                        return GestureDetector(
                          onTap: () => audioController.unlockAudioPlayback(),
                          child: Text(
                            'Tap to Unmute Audio',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.warningYellow,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: audioController.hasRemoteAudioTrackNotifier,
                        builder: (context, hasAudio, _) {
                          return Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: hasAudio ? AppTheme.success : Colors.white38,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasAudio ? 'Audio Connected' : 'Connecting Audio...',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: hasAudio ? AppTheme.success : Colors.white60,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // Mute / Unmute
            ValueListenableBuilder<bool>(
              valueListenable: audioController.isMutedNotifier,
              builder: (context, isMuted, child) {
                return IconButton(
                  icon: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: isMuted ? AppTheme.warningYellow : Colors.white,
                    size: 20,
                  ),
                  tooltip: isMuted ? 'Unmute' : 'Mute',
                  onPressed: () => audioController.toggleMute(),
                );
              },
            ),

            // Leave button
            IconButton(
              icon: Icon(Icons.close_rounded, color: AppTheme.dangerRed, size: 20),
              tooltip: 'Leave Stream',
              onPressed: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}
