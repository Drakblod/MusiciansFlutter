import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/live_broadcast.dart';
import '../services/livekit_audio_controller.dart';
import '../theme/app_theme.dart';

class LiveListenerSheet extends StatelessWidget {
  final LiveBroadcast broadcast;
  final LiveKitAudioController audioController;
  final bool isCurrentlyListening;
  final VoidCallback onStartListening;
  final VoidCallback onStopListening;

  const LiveListenerSheet({
    super.key,
    required this.broadcast,
    required this.audioController,
    required this.isCurrentlyListening,
    required this.onStartListening,
    required this.onStopListening,
  });

  static Future<void> show(
    BuildContext context, {
    required LiveBroadcast broadcast,
    required LiveKitAudioController audioController,
    required bool isCurrentlyListening,
    required VoidCallback onStartListening,
    required VoidCallback onStopListening,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: LiveListenerSheet(
          broadcast: broadcast,
          audioController: audioController,
          isCurrentlyListening: isCurrentlyListening,
          onStartListening: onStartListening,
          onStopListening: onStopListening,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.dangerRed, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header with LIVE badge
          Row(
            children: [
              Container(
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
                      'LIVE STREAM',
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
              const SizedBox(width: 8),
              if (broadcast.genre != null && broadcast.genre!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    broadcast.genre!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.headset_rounded, color: Colors.white60, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${broadcast.listenerCount} listeners',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Band and Title
          Text(
            broadcast.bandName,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            broadcast.title,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          if (broadcast.location != null && broadcast.location!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                Text(
                  broadcast.location!,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // Player controls
          if (isCurrentlyListening) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: audioController.isMutedNotifier,
                        builder: (context, isMuted, child) {
                          return IconButton(
                            icon: Icon(
                              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: isMuted ? AppTheme.warningYellow : AppTheme.primaryAccent,
                            ),
                            onPressed: () => audioController.toggleMute(),
                          );
                        },
                      ),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: audioController.volumeNotifier,
                          builder: (context, vol, child) {
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppTheme.primaryAccent,
                                inactiveTrackColor: Colors.white12,
                                thumbColor: Colors.white,
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: vol,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (v) => audioController.setVolume(v),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  onStopListening();
                  Navigator.pop(context);
                },
                icon: Icon(Icons.stop_rounded, color: AppTheme.dangerRed),
                label: Text(
                  'Leave Live Stream',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.dangerRed,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.dangerRed.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  onStartListening();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.headphones_rounded, color: Colors.white),
                label: Text(
                  'Listen Live',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  ),
);
  }
}
