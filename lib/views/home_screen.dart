import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../config/feature_toggles.dart';

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
    if (FeatureToggles.useExperimentalHomeView) {
      return const ExperimentalHomeViewContent();
    }

    final appState = Provider.of<AppState>(context);
    final profile = appState.currentUserProfile;
    final userName = profile?.displayName ?? profile?.nickname ?? 'AlexHill';

    // 1. Define all possible action items on the home screen
    final List<HomeActionItem> actionItems = [
      HomeActionItem(
        id: 'find_musicians',
        icon: Icons.people_outline_rounded,
        title: 'Find Musicians',
        subtitle: 'Find and connect with talented musicians near you',
        onTap: () {
          appState.trackButtonClick('find_musicians');
          final isProducer = profile?.instruments.contains('PRODUCER') == true ||
              profile?.userType == 'PRODUCER';
          if (isProducer) {
            Navigator.pushNamed(context, '/producer-search');
          } else {
            _handleBandNavigation(context, appState, '/find-sub');
          }
        },
      ),
      HomeActionItem(
        id: 'browse_musicians',
        icon: Icons.search_rounded,
        title: 'Browse Musicians',
        subtitle: 'Explore profiles and discover new collaborators',
        onTap: () {
          appState.trackButtonClick('browse_musicians');
          Navigator.pushNamed(context, '/browse-musicians');
        },
      ),
      HomeActionItem(
        id: 'find_gigs',
        icon: Icons.local_activity_outlined,
        title: 'Gigs list',
        subtitle: 'Find gigs and opportunities in your area',
        onTap: () {
          appState.trackButtonClick('find_gigs');
          Navigator.pushNamed(context, '/find-gigs');
        },
      ),
      HomeActionItem(
        id: 'band_room',
        icon: Icons.groups_outlined,
        title: 'Band Room',
        subtitle: 'Manage your band, chat and organize everything',
        onTap: () {
          appState.trackButtonClick('band_room');
          _handleBandNavigation(context, appState, '/band-room');
        },
      ),
      HomeActionItem(
        id: 'marketplace',
        icon: Icons.storefront_outlined,
        title: 'Marketplace',
        subtitle: 'Buy, sell, or rent gear and spaces, or offer music services',
        onTap: () {
          appState.trackButtonClick('marketplace');
          Navigator.pushNamed(context, '/marketplace');
        },
      ),
    ];

    // 2. Sort the action items based on user's click metrics
    final clicks = appState.buttonClicks;
    final Map<String, int> defaultOrder = {
      'find_musicians': 0,
      'browse_musicians': 1,
      'find_gigs': 2,
      'band_room': 3,
      'marketplace': 4,
    };

    actionItems.sort((a, b) {
      final clicksA = clicks[a.id] ?? 0;
      final clicksB = clicks[b.id] ?? 0;
      if (clicksA != clicksB) {
        return clicksB.compareTo(clicksA); // Descending (most clicked first)
      }
      return (defaultOrder[a.id] ?? 0).compareTo(defaultOrder[b.id] ?? 0); // Stable default order
    });

    return SafeArea(
      child: SingleChildScrollView(
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

            // Action Cards List (Dynamically sorted)
            ...actionItems.expand((item) => [
              _buildActionCard(
                context,
                icon: item.icon,
                title: item.title,
                subtitle: item.subtitle,
                onTap: item.onTap,
              ),
              const SizedBox(height: 16),
            ]).toList(),
            const SizedBox(height: 24), // Extra spacing to reach total height 40 before Logout

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
                  '1.87',
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

/// Helper model for home screen action items representation
class HomeActionItem {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  HomeActionItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// =========================================================================
// EXPERIMENTAL DYNAMIC HOME SCREEN WIDGETS
// To rollback, set "useExperimentalHomeView = false" in HomeScreen above.
// =========================================================================

class ExperimentalHomeViewContent extends StatefulWidget {
  const ExperimentalHomeViewContent({super.key});

  @override
  State<ExperimentalHomeViewContent> createState() => _ExperimentalHomeViewContentState();
}

class _ExperimentalHomeViewContentState extends State<ExperimentalHomeViewContent> {
  Map<String, int> _localClicks = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    final clicks = await HomeUsageTracker.getClicks();
    if (mounted) {
      setState(() {
        _localClicks = clicks;
        _isLoading = false;
      });
    }
  }

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
          await Navigator.pushNamed(context, routeName);
        }
      } else if (bands.length == 1) {
        appState.selectBand(bands.keys.first, bands.values.first);
        if (context.mounted) {
          await Navigator.pushNamed(context, routeName);
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

  String _getShortLabel(String id, String fullTitle) {
    switch (id) {
      case 'find_musicians':
        return 'Find\nMusician/Vocalist';
      case 'browse_musicians':
        return 'Profiles';
      case 'find_gigs':
        return 'Gigs list';
      case 'band_room':
        return 'Band Room';
      case 'marketplace':
        return 'Market';
      case 'collabs':
        return 'Collabs';
      case 'event_calendar':
        return 'Event Calendar';
      default:
        return fullTitle;
    }
  }

  Widget _buildCustomBubble(BuildContext context, HomeActionItem item, {required bool isCenter}) {
    final double size = 114;
    final double iconSize = 32;
    final double fontSize = 10;

    return AnimatedTapDetector(
      onTap: item.onTap,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          borderRadius: BorderRadius.circular(size / 2),
          gradient: const RadialGradient(
            colors: [
              Color(0xFF2E1756), // Dark purple center
              Color(0xFF0D0822), // Deep black-purple edge
            ],
            center: Alignment.center,
            radius: 0.85,
          ),
          border: Border.all(
            color: const Color(0xFFE5A9FF).withOpacity(0.9), // Bright glowing edge border
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC066F6).withOpacity(0.55),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(4), // Space between outer and inner ring
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular((size - 8) / 2),
            border: Border.all(
              color: const Color(0xFFC066F6).withOpacity(0.25), // Subtle inner ring
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  color: Colors.white,
                  size: iconSize,
                ),
                const SizedBox(height: 6),
                Text(
                  _getShortLabel(item.id, item.title),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      );
    }

    final appState = Provider.of<AppState>(context);
    final profile = appState.currentUserProfile;
    final userName = profile?.displayName ?? profile?.nickname ?? 'AlexHill';

    final List<HomeActionItem> allActions = [
      HomeActionItem(
        id: 'find_musicians',
        icon: Icons.people_outline_rounded,
        title: 'Find Musicians',
        subtitle: 'Find and connect with talented musicians near you',
        onTap: () async {
          await HomeUsageTracker.incrementClick('find_musicians');
          final isProducer = profile?.instruments.contains('PRODUCER') == true ||
              profile?.userType == 'PRODUCER';
          if (isProducer) {
            await Navigator.pushNamed(context, '/producer-search');
          } else {
            await _handleBandNavigation(context, appState, '/find-sub');
          }
          _loadUsageData();
        },
      ),
      HomeActionItem(
        id: 'browse_musicians',
        icon: Icons.search_rounded,
        title: 'Browse Musicians',
        subtitle: 'Explore profiles and discover new collaborators',
        onTap: () async {
          await HomeUsageTracker.incrementClick('browse_musicians');
          await Navigator.pushNamed(context, '/browse-musicians');
          _loadUsageData();
        },
      ),
      HomeActionItem(
        id: 'find_gigs',
        icon: Icons.local_activity_outlined,
        title: 'Gigs list',
        subtitle: 'Find gigs and opportunities in your area',
        onTap: () async {
          await HomeUsageTracker.incrementClick('find_gigs');
          await Navigator.pushNamed(context, '/find-gigs');
          _loadUsageData();
        },
      ),
      HomeActionItem(
        id: 'collabs',
        icon: Icons.handshake_outlined,
        title: 'Collabs',
        subtitle: 'Collaborate with other musicians on projects',
        onTap: () async {
          await HomeUsageTracker.incrementClick('collabs');
          await Navigator.pushNamed(context, '/collabs');
          _loadUsageData();
        },
      ),
      HomeActionItem(
        id: 'event_calendar',
        icon: Icons.calendar_today_outlined,
        title: 'Event Calendar',
        subtitle: 'View your upcoming events and schedule',
        onTap: () {},
      ),
      HomeActionItem(
        id: 'band_room',
        icon: Icons.groups_outlined,
        title: 'Band Room',
        subtitle: 'Manage your band, chat and organize everything',
        onTap: () async {
          await HomeUsageTracker.incrementClick('band_room');
          await _handleBandNavigation(context, appState, '/band-room');
          _loadUsageData();
        },
      ),
      HomeActionItem(
        id: 'marketplace',
        icon: Icons.storefront_outlined,
        title: 'Marketplace',
        subtitle: 'Buy, sell, or rent gear and spaces, or offer music services',
        onTap: () async {
          await HomeUsageTracker.incrementClick('marketplace');
          await Navigator.pushNamed(context, '/marketplace');
          _loadUsageData();
        },
      ),
    ];

    final Map<String, int> defaultOrder = {
      'find_musicians': 0,
      'browse_musicians': 1,
      'find_gigs': 2,
      'collabs': 3,
      'event_calendar': 4,
      'band_room': 5,
      'marketplace': 6,
    };

    allActions.sort((a, b) {
      // Paused dynamic click-based sorting temporarily to prevent shifting buttons during testing
      // final clicksA = _localClicks[a.id] ?? 0;
      // final clicksB = _localClicks[b.id] ?? 0;
      // if (clicksA != clicksB) {
      //   return clicksB.compareTo(clicksA);
      // }
      return (defaultOrder[a.id] ?? 0).compareTo(defaultOrder[b.id] ?? 0);
    });

    final selectedIds = appState.selectedBubbles;
    final List<String> bubbleIds = selectedIds.length == 3 ? selectedIds : [
      'browse_musicians',
      'find_gigs',
      'find_musicians',
    ];

    final topBubbleActions = bubbleIds.map((id) => allActions.firstWhere((item) => item.id == id)).toList();
    final remainingCardActions = allActions.where((item) => !topBubbleActions.contains(item)).toList();

    return Stack(
      children: [
        // 1. Full-width Branded Header background extending behind the toolbar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 140, // Height is perfect to cover the CustomTopBar + safe status area
            child: Image.asset(
              'assets/images/header_base.png',
              fit: BoxFit.cover,
            ),
          ),
        ),

        // 2. Scrollable layout content safely underneath the toolbar
        SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top margin to offset content below the transparent CustomTopBar (app bar is 60px height)
                const SizedBox(height: 60),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Curved/glow background behind the bubble row (FULL WIDTH BLEED)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: NeonArcPainter(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none, // Prevent clipping of neon glow/shadows
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20), // Align content edges with page borders
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildCustomBubble(context, topBubbleActions[0], isCenter: false),
                              const SizedBox(width: 18),
                              _buildCustomBubble(context, topBubbleActions[1], isCenter: true),
                              const SizedBox(width: 18),
                              _buildCustomBubble(context, topBubbleActions[2], isCenter: false),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Remaining Cards List
                      ...remainingCardActions.expand((item) => [
                        _buildActionCard(
                          context,
                          icon: item.icon,
                          title: item.title,
                          subtitle: item.subtitle,
                          onTap: item.onTap,
                        ),
                        const SizedBox(height: 16),
                      ]).toList(),
                      const SizedBox(height: 24),

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
                          child: GestureDetector(
                            onLongPress: () async {
                              await HomeUsageTracker.resetClicks();
                              _loadUsageData();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Quick Access metrics reset successfully!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              '1.87',
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary.withOpacity(0.5),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. Transparent Top Bar layered on top of the glowing header background
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CustomTopBar(
            showBack: false,
            transparent: true,
          ),
        ),
      ],
    );
  }
}

class HomeUsageTracker {
  static const String _prefix = 'home_action_click_count_';

  static Future<Map<String, int>> getClicks() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, int> counts = {};
    for (final id in ['find_musicians', 'browse_musicians', 'find_gigs', 'band_room', 'marketplace']) {
      counts[id] = prefs.getInt('$_prefix$id') ?? 0;
    }
    return counts;
  }

  static Future<void> incrementClick(String actionId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('$_prefix$actionId') ?? 0;
    await prefs.setInt('$_prefix$actionId', current + 1);
  }

  static Future<void> resetClicks() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in ['find_musicians', 'browse_musicians', 'find_gigs', 'band_room', 'marketplace']) {
      await prefs.remove('$_prefix$id');
    }
  }
}

class NeonArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC066F6).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3); // Blur for neon glow

    final shadowPaint = Paint()
      ..color = const Color(0xFFC066F6).withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width / 2,
        size.height * 0.98,
        size.width,
        size.height * 0.65,
      );

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
