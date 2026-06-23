import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _handleBandNavigation(
    BuildContext context,
    AppState appState,
    String routeName,
  ) async {
    final userId = appState.currentUserId;
    if (userId == null) return;

    // Show loading spinner dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      ),
    );

    try {
      final bands = await appState.firebaseService.getUserBandsAsync(userId);
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
      }

      if (bands.isEmpty) {
        if (context.mounted) {
          Navigator.pushNamed(context, routeName);
        }
      } else if (bands.length == 1) {
        appState.selectBand(bands.keys.first, bands.values.first);
        if (context.mounted) {
          Navigator.pushNamed(context, routeName);
        }
      } else {
        if (context.mounted) {
          _showBandSelectorBottomSheet(context, appState, bands, routeName);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking band memberships: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showBandSelectorBottomSheet(
    BuildContext context,
    AppState appState,
    Map<String, String> bands,
    String routeName,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
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
            bottom: MediaQuery.of(context).padding.bottom + 24,
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
                'Choose which band you are acting on behalf of.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bands.length,
                  itemBuilder: (context, index) {
                    final bandId = bands.keys.elementAt(index);
                    final bandName = bands[bandId]!;
                    final isSelected = appState.activeBandId == bandId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedTapDetector(
                        onTap: () {
                          appState.selectBand(bandId, bandName);
                          Navigator.pop(context); // Close bottom sheet
                          Navigator.pushNamed(context, routeName);
                        },
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

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final profile = appState.currentUserProfile;
    final userName = profile?.displayName ?? profile?.nickname ?? 'AlexHill';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Good evening,',
            style: GoogleFonts.inter(
              fontSize: 18,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            userName,
            style: GoogleFonts.outfit(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Let's make some music happen.",
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 30),

          // Action Cards List
          _buildActionCard(
            context,
            icon: Icons.people_outline_rounded,
            title: 'Find Musicians',
            subtitle: 'Find and connect with talented musicians near you',
            onTap: () {
              final isProducer = profile?.instruments.contains('PRODUCER') == true ||
                  profile?.userType == 'PRODUCER';
              if (isProducer) {
                Navigator.pushNamed(context, '/producer-search');
              } else {
                _handleBandNavigation(context, appState, '/find-sub');
              }
            },
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            icon: Icons.search_rounded,
            title: 'Browse Musicians',
            subtitle: 'Explore profiles and discover new collaborators',
            onTap: () {
              Navigator.pushNamed(context, '/browse-musicians');
            },
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            icon: Icons.local_activity_outlined,
            title: 'Find Gigs',
            subtitle: 'Find gigs and opportunities in your area',
            onTap: () {
              Navigator.pushNamed(context, '/find-gigs');
            },
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            icon: Icons.groups_outlined,
            title: 'Band Room',
            subtitle: 'Manage your band, chat and organize everything',
            onTap: () => _handleBandNavigation(context, appState, '/band-room'),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context,
            icon: Icons.storefront_outlined,
            title: 'Marketplace',
            subtitle: 'Buy, sell, or rent gear and spaces, or offer music services',
            onTap: () {
              Navigator.pushNamed(context, '/marketplace');
            },
          ),
          const SizedBox(height: 40),

          // Logout Button
          Center(
            child: AnimatedTapDetector(
              onTap: () async {
                await appState.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Text(
                  'Logout',
                  style: GoogleFonts.inter(
                    color: AppTheme.primaryAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 10),
              child: Text(
                '1.60',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AnimatedTapDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF231F45),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryAccent,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
