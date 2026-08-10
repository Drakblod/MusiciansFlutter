import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/band_event.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'animated_tap_detector.dart';

/// Animated RSVP Reminder Popup Modal matching designer mockups
class RsvpReminderDialog extends StatefulWidget {
  final BandEvent event;
  final String bandId;
  final String currentUserId;
  final VoidCallback? onResponded;

  const RsvpReminderDialog({
    super.key,
    required this.event,
    required this.bandId,
    required this.currentUserId,
    this.onResponded,
  });

  static Future<void> show({
    required BuildContext context,
    required BandEvent event,
    required String bandId,
    required String currentUserId,
    VoidCallback? onResponded,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'RSVP Reminder',
      barrierColor: Colors.black.withOpacity(0.75),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return RsvpReminderDialog(
          event: event,
          bandId: bandId,
          currentUserId: currentUserId,
          onResponded: onResponded,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedAnim = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curvedAnim,
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<RsvpReminderDialog> createState() => _RsvpReminderDialogState();
}

class _RsvpReminderDialogState extends State<RsvpReminderDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isSubmitting = false;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();

    // Set initial user status if previously responded
    final userResp = widget.event.responses[widget.currentUserId];
    if (userResp != null) {
      _selectedStatus = userResp.status;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitRsvp(String status) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _selectedStatus = status;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.firebaseService.updateEventResponseAsync(
        widget.bandId,
        widget.event.id ?? '',
        widget.currentUserId,
        status,
      );

      if (widget.onResponded != null) {
        widget.onResponded!();
      }

      if (mounted) {
        // Quick visual confirmation then animate out
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update response: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  int _getCount(String targetStatus) {
    int count = 0;
    widget.event.responses.forEach((key, resp) {
      if (resp.status.toLowerCase() == targetStatus.toLowerCase()) {
        count++;
      }
    });
    // Dynamically adjust count if user selects in real time locally
    final initialResp = widget.event.responses[widget.currentUserId]?.status;
    if (_selectedStatus != null && _selectedStatus != initialResp) {
      if (initialResp?.toLowerCase() == targetStatus.toLowerCase()) count--;
      if (_selectedStatus?.toLowerCase() == targetStatus.toLowerCase()) count++;
    }
    return count < 0 ? 0 : count;
  }

  String _formatEventDate(String dateIso) {
    final dt = DateTime.tryParse(dateIso)?.toLocal();
    if (dt == null) return dateIso;
    try {
      return DateFormat('EEEE d MMMM, HH:mm').format(dt);
    } catch (_) {
      return DateFormat('EEE, MMM d HH:mm').format(dt);
    }
  }

  int _calculateTimeLeftHours() {
    final start = DateTime.tryParse(widget.event.startDateTime)?.toLocal();
    if (start != null) {
      final diff = start.difference(DateTime.now()).inHours;
      if (diff > 0 && diff <= 72) {
        return diff;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final yesCount = _getCount('Yes');
    final noCount = _getCount('No');
    final uncertainCount = _getCount('Uncertain');

    final timeLeftHours = _calculateTimeLeftHours();
    final dateFormatted = _formatEventDate(widget.event.startDateTime);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.35),
                blurRadius: 25,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Top Header Banner matching mockup
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF8E24AA), Color(0xFFAB47BC), Color(0xFF6A1B9A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'm',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'MUSICIANS',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Main Content Card (Light Peach / Coral Gradient)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFFFF0F2),
                        Color(0xFFFFE4E6),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Reminder header text: REMINDER(24h) Time left for your answer: (X)h
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            const TextSpan(text: 'REMINDER(24h) Time left for your answer: '),
                            TextSpan(
                              text: '($timeLeftHours)h',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: const Color(0xFFE53935),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Event Title
                      Text(
                        widget.event.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Event Date & Time
                      Text(
                        dateFormatted,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Subtitle / Location / Info
                      Text(
                        widget.event.description.isNotEmpty ? widget.event.description : (widget.event.location.isNotEmpty ? widget.event.location : 'info..'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Interactive RSVP Option Buttons Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // YES Button
                          _buildRsvpButton(
                            label: 'YES',
                            count: yesCount,
                            bgColor: const Color(0xFF2ECC71),
                            statusKey: 'Yes',
                            isSelected: _selectedStatus?.toLowerCase() == 'yes',
                          ),
                          const SizedBox(width: 8),

                          // NO Button
                          _buildRsvpButton(
                            label: 'NO',
                            count: noCount,
                            bgColor: const Color(0xFFE74C3C),
                            statusKey: 'No',
                            isSelected: _selectedStatus?.toLowerCase() == 'no',
                          ),
                          const SizedBox(width: 8),

                          // UNCERTAIN Button
                          _buildRsvpButton(
                            label: 'UNCERTAIN',
                            count: uncertainCount,
                            bgColor: const Color(0xFF7F8C8D),
                            statusKey: 'Uncertain',
                            isSelected: _selectedStatus?.toLowerCase() == 'uncertain' || _selectedStatus?.toLowerCase() == 'maybe',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRsvpButton({
    required String label,
    required int count,
    required Color bgColor,
    required String statusKey,
    required bool isSelected,
  }) {
    return Expanded(
      child: AnimatedTapDetector(
        onTap: () => _submitRsvp(statusKey),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: Colors.black, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: bgColor.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
