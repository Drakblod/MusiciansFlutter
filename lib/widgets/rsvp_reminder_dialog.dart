import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/band_event.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/rsvp_deadline_utils.dart';
import 'animated_tap_detector.dart';

/// Animated RSVP Reminder Popup Modal matching designer mockups with Receipt state and custom Uncertain text input
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
  bool _showUncertainInput = false;
  final TextEditingController _uncertainController = TextEditingController();

  // Receipt state
  bool _isReceiptState = false;
  String? _submittedStatus;
  String? _submittedComment;
  DateTime? _submittedAt;

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
      if (userResp.comment != null && userResp.comment!.isNotEmpty) {
        _uncertainController.text = userResp.comment!;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _uncertainController.dispose();
    super.dispose();
  }

  Future<void> _submitRsvp(String status, {String? comment}) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _selectedStatus = status;
    });

    final cleanComment = (comment != null && comment.trim().isNotEmpty) ? comment.trim() : null;

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.firebaseService.updateEventResponseAsync(
        widget.bandId,
        widget.event.id ?? '',
        widget.currentUserId,
        status,
        comment: cleanComment,
      );

      if (widget.onResponded != null) {
        widget.onResponded!();
      }

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isReceiptState = true;
          _submittedStatus = status;
          _submittedComment = cleanComment;
          _submittedAt = DateTime.now();
        });
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

  int? _calculateTimeLeftHours() {
    return RsvpDeadlineUtils.calculateRemainingRsvpHours(widget.event);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 440),
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Top Header Banner
                  _buildHeaderBanner(),

                  // 2. Main Content: Either Prompt / Form or Receipt Card
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isReceiptState
                        ? KeyedSubtree(
                            key: const ValueKey('receipt_state'),
                            child: _buildReceiptContent(),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('prompt_state'),
                            child: _buildPromptContent(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
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
    );
  }

  Widget _buildPromptContent() {
    final yesCount = _getCount('Yes');
    final noCount = _getCount('No');
    final uncertainCount = _getCount('Uncertain');

    final timeLeftHours = _calculateTimeLeftHours();
    final dateFormatted = _formatEventDate(widget.event.startDateTime);

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reminder header text
          timeLeftHours != null
              ? RichText(
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
                )
              : Text(
                  'Response requested — no automatic deadline.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
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
            widget.event.description.isNotEmpty
                ? widget.event.description
                : (widget.event.location.isNotEmpty ? widget.event.location : 'info..'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 20),

          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E24AA)),
                ),
              ),
            )
          else ...[
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
                  onTap: () {
                    setState(() => _showUncertainInput = false);
                    _submitRsvp('Yes');
                  },
                ),
                const SizedBox(width: 8),

                // NO Button
                _buildRsvpButton(
                  label: 'NO',
                  count: noCount,
                  bgColor: const Color(0xFFE74C3C),
                  statusKey: 'No',
                  isSelected: _selectedStatus?.toLowerCase() == 'no',
                  onTap: () {
                    setState(() => _showUncertainInput = false);
                    _submitRsvp('No');
                  },
                ),
                const SizedBox(width: 8),

                // UNCERTAIN Button
                _buildRsvpButton(
                  label: 'UNCERTAIN',
                  count: uncertainCount,
                  bgColor: const Color(0xFF7F8C8D),
                  statusKey: 'Uncertain',
                  isSelected: _showUncertainInput ||
                      _selectedStatus?.toLowerCase() == 'uncertain' ||
                      _selectedStatus?.toLowerCase() == 'maybe',
                  onTap: () {
                    setState(() {
                      _showUncertainInput = true;
                      _selectedStatus = 'Uncertain';
                    });
                  },
                ),
              ],
            ),

            // Expandable Uncertain custom note section
            if (_showUncertainInput) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF7F8C8D).withOpacity(0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.edit_note_rounded,
                          size: 18,
                          color: Color(0xFF7F8C8D),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Reason / Note for bandleader:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _uncertainController,
                      maxLines: 2,
                      minLines: 1,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., Checking schedule, might be late...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.black38,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF8E24AA), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showUncertainInput = false;
                            });
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            _submitRsvp(
                              'Uncertain',
                              comment: _uncertainController.text,
                            );
                          },
                          icon: const Icon(Icons.check, size: 14, color: Colors.white),
                          label: Text(
                            'CONFIRM UNCERTAIN',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F8C8D),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildReceiptContent() {
    final status = _submittedStatus ?? _selectedStatus ?? 'Yes';
    final isYes = status.toLowerCase() == 'yes';
    final isNo = status.toLowerCase() == 'no';

    final Color accentColor = isYes
        ? const Color(0xFF2ECC71)
        : (isNo ? const Color(0xFFE74C3C) : const Color(0xFF7F8C8D));

    final IconData statusIcon = isYes
        ? Icons.check_circle_rounded
        : (isNo ? Icons.cancel_rounded : Icons.help_outline_rounded);

    final String statusLabel = isYes
        ? 'ATTENDING (YES)'
        : (isNo ? 'NOT ATTENDING (NO)' : 'UNCERTAIN');

    final String statusSubtitle = isYes
        ? 'Your attendance has been confirmed.'
        : (isNo
            ? 'Your decline has been recorded.'
            : 'Your tentative status has been noted.');

    final dateFormatted = _formatEventDate(widget.event.startDateTime);
    final recordedTimeStr = _submittedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(_submittedAt!)
        : DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF9FAFB),
            Color(0xFFF3F4F6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Receipt Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF8E24AA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF8E24AA).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 14,
                    color: Color(0xFF8E24AA),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'RSVP RECEIPT',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF8E24AA),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Primary Status Card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(statusIcon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusSubtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Custom Note Callout (if entered)
          if (_submittedComment != null && _submittedComment!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 14,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Note to bandleader:',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '"$_submittedComment"',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Event Summary Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.event.title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 13,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dateFormatted,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.event.location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.event.location,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Timestamp footer
          Text(
            'Recorded: $recordedTimeStr',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.black45,
            ),
          ),

          const SizedBox(height: 16),

          // Done Button
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E24AA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            child: Text(
              'DONE',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Change Response Link
          TextButton(
            onPressed: () {
              setState(() {
                _isReceiptState = false;
                _showUncertainInput = false;
              });
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Change response',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF8E24AA),
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRsvpButton({
    required String label,
    required int count,
    required Color bgColor,
    required String statusKey,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: AnimatedTapDetector(
        onTap: onTap,
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
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
        ),
      ),
    );
  }
}

