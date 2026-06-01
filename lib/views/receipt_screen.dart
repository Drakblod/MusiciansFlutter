import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class ReceiptScreen extends StatelessWidget {
  final String name;
  final String voicePart;
  final String date;
  final String startTime;
  final String endTime;
  final String conversationId;
  final String receiverUserId;

  const ReceiptScreen({
    super.key,
    required this.name,
    required this.voicePart,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.conversationId,
    required this.receiverUserId,
  });

  String _formatDate(String dateString) {
    final parsed = DateTime.tryParse(dateString);
    if (parsed != null) {
      return '${DateFormat('EEE, MMM dd').format(parsed)},';
    }
    return 'Invalid Date';
  }

  String _formatTime(String time) {
    if (time.length > 5) {
      return time.substring(0, 5); // strip seconds if present: hh:mm:ss -> hh:mm
    }
    return time;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Receipt',
        showBack: false, // Don't show back on receipt screen
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              // Centered Confirmation Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF2E2A4E),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryAccent.withOpacity(0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Verified Handshake Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.handshake_rounded,
                        color: AppTheme.success,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'CONFIRMED',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.success,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'will join the rehearsal',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatDate(date),
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatTime(startTime)} - ${_formatTime(endTime)}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'on $voicePart',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.secondaryAccent,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    // Write Message Button
                    AnimatedTapDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(
                          context,
                          '/chat-detail',
                          arguments: {
                            'conversationId': conversationId,
                            'receiverId': receiverUserId,
                            'receiverName': name,
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryAccent.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.forum_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Write Message',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Back to Home Button
              AnimatedTapDetector(
                onTap: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/main-nav',
                    (route) => false,
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Center(
                    child: Text(
                      'Back to Home',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
