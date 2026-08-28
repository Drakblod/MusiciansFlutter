import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';
import '../views/create_event_page.dart';

class GlobalCreateEventLauncher {
  static bool _isNavigating = false;

  static Future<void> showLauncherSheet(
    BuildContext context,
    AppState appState,
  ) async {
    if (_isNavigating) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C22).withOpacity(0.98),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(sheetContext).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'WHAT WOULD YOU LIKE TO CREATE?',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              // Option 1: Create Event (Band Event)
              AnimatedTapDetector(
                enableFocus: true,
                semanticLabel: 'Create Event for a band',
                onTap: () async {
                  if (_isNavigating) return;
                  _isNavigating = true;
                  Navigator.pop(sheetContext);
                  await handleCreateBandEvent(context, appState);
                  _isNavigating = false;
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            color: AppTheme.primaryAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Event',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create rehearsal, gig, tour, show...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Option 2: Create Session (Collab Session)
              AnimatedTapDetector(
                enableFocus: true,
                semanticLabel: 'Create Session or collaboration',
                onTap: () async {
                  if (_isNavigating) return;
                  _isNavigating = true;
                  Navigator.pop(sheetContext);
                  if (context.mounted) {
                    await Navigator.pushNamed(context, '/create-session');
                  }
                  _isNavigating = false;
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mic_external_on_rounded,
                            color: AppTheme.primaryAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Session',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Create songwriting session, jam, recording, workshop...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> handleCreateBandEvent(
    BuildContext context,
    AppState appState,
  ) async {
    final userId = appState.currentUserId;
    if (userId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to create an event.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    bool dialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      ),
    );

    void dismissLoadingDialog() {
      if (dialogShown && context.mounted) {
        dialogShown = false;
        Navigator.pop(context);
      }
    }

    try {
      final userBands = await appState.firebaseService.getUserBandsAsync(userId);
      final Map<String, String> authorizedBands = {};

      for (final entry in userBands.entries) {
        try {
          final role = await appState.firebaseService.getUserBandRoleAsync(entry.key, userId);
          final r = (role ?? '').trim().toLowerCase();
          if (r == 'leader' || r == 'admin' || r == 'mod') {
            authorizedBands[entry.key] = entry.value;
          }
        } catch (_) {
          // Fail closed for unverified roles
        }
      }

      dismissLoadingDialog();

      if (authorizedBands.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You need to be a Leader, Admin, or MOD of a band to create a Band Event. You can create a Session without a band.',
              ),
              backgroundColor: AppTheme.warning,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else if (authorizedBands.length == 1) {
        final bandId = authorizedBands.keys.first;
        final bandName = authorizedBands.values.first;
        appState.selectBand(bandId, bandName);
        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateEventPage(bandId: bandId),
            ),
          );
        }
      } else {
        if (context.mounted) {
          _showAuthorizedBandSelectorSheet(context, appState, authorizedBands);
        }
      }
    } catch (e) {
      dismissLoadingDialog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission check failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  static void _showAuthorizedBandSelectorSheet(
    BuildContext context,
    AppState appState,
    Map<String, String> authorizedBands,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C22).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(sheetContext).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'SELECT A BAND',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which authorized band to create an event for.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: authorizedBands.length,
                  itemBuilder: (itemContext, index) {
                    final bandId = authorizedBands.keys.elementAt(index);
                    final bandName = authorizedBands[bandId]!;
                    final isSelected = appState.activeBandId == bandId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedTapDetector(
                        enableFocus: true,
                        semanticLabel: 'Select band $bandName',
                        onTap: () {
                          appState.selectBand(bandId, bandName);
                          Navigator.pop(sheetContext);
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateEventPage(bandId: bandId),
                              ),
                            );
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryAccent.withOpacity(0.12)
                                  : AppTheme.cardBackground,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFF2E2A4E),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryAccent.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.groups_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    bandName,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppTheme.primaryAccent,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
