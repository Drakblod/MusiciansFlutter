import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class SubRequestDetailsScreen extends StatefulWidget {
  final SubRequest subRequest;

  const SubRequestDetailsScreen({super.key, required this.subRequest});

  @override
  State<SubRequestDetailsScreen> createState() =>
      _SubRequestDetailsScreenState();
}

class _SubRequestDetailsScreenState extends State<SubRequestDetailsScreen> {
  bool _isApplying = false;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentUserId = appState.currentUserId;
    final gig = widget.subRequest;
    final hasApplied =
        currentUserId != null && gig.responses.containsKey(currentUserId);

    final date = gig.date != null
        ? DateTime.tryParse(gig.date!) ?? DateTime.now()
        : DateTime.now();
    final formattedDate = DateFormat('EEEE, MMMM dd, yyyy').format(date);

    return GradientScaffold(
      appBar: const CustomTopBar(title: 'Gig Details', showBack: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Band name & Instrument/Role Title Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          gig.role ?? gig.voicePart ?? 'Substitute Request',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: gig.isPaid
                              ? AppTheme.primaryAccent.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          gig.isPaid ? 'Paid' : 'Unpaid',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: gig.isPaid
                                ? AppTheme.primaryAccent
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gig.bandName ?? 'Freelance Gig',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppTheme.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (gig.eventTitle != null && gig.eventTitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Event name',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gig.eventTitle!.trim(),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  if (gig.payDetails != null && gig.payDetails!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Details',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gig.payDetails!.trim(),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Gig Logistics Section
            Text(
              'LOGISTICS',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Column(
                children: [
                  // Location row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              gig.location ?? 'Stockholm, Sweden',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(color: Color(0xFF2E2A4E), height: 1),
                  ),
                  // Date row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: AppTheme.primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(color: Color(0xFF2E2A4E), height: 1),
                  ),
                  // Time row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: AppTheme.primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Time',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${gig.startTime ?? "18:00"} - ${gig.endTime ?? "21:00"}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Description Section
            Text(
              'Description',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Text(
                gig.description ??
                    'No description has been provided for this substitute request.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Action Apply Button
            _isApplying
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryAccent,
                    ),
                  )
                : hasApplied
                ? Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Center(
                      child: Text(
                        'Applied',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : AnimatedTapDetector(
                    onTap: () async {
                      if (currentUserId == null) return;
                      setState(() => _isApplying = true);
                      try {
                        if ((gig.id ?? '').startsWith('mock_')) {
                          // Simulate apply for mock gig
                          await Future.delayed(
                            const Duration(milliseconds: 300),
                          );
                        } else {
                          await appState.firebaseService
                              .addResponseToSubRequestAsync(
                                gig.subRequestId ?? gig.id!,
                                currentUserId,
                              );
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Successfully applied for gig!'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                          setState(() {
                            gig.responses[currentUserId] = true;
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to apply: $e'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isApplying = false);
                      }
                    },
                    child: Container(
                      height: 55,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryAccent.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Apply for Gig',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
