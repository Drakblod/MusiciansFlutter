import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class CollabsLandingScreen extends StatelessWidget {
  const CollabsLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COLLABS',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Collaborate on songwriting, production, recording, and sessions.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Songwriters & Producers Card
              _buildCategoryCard(
                context,
                title: 'Songwriters & Producers',
                description: 'Connect with composers and music producers to create fresh songs and beats.',
                actions: [
                  _CategoryAction(
                    label: 'Find Songwriters',
                    icon: Icons.edit_note_rounded,
                    onTap: () => Navigator.pushNamed(context, '/find-collabs', arguments: 'songwriter'),
                  ),
                  _CategoryAction(
                    label: 'Find Producers',
                    icon: Icons.album_rounded,
                    onTap: () => Navigator.pushNamed(context, '/find-collabs', arguments: 'producer'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Studios & Engineers Card
              _buildCategoryCard(
                context,
                title: 'Studios & Engineers',
                description: 'Rent professional recording studios or hire mixing/mastering engineers.',
                actions: [
                  _CategoryAction(
                    label: 'Find Studios',
                    icon: Icons.business_rounded,
                    onTap: () => Navigator.pushNamed(context, '/find-studios'),
                  ),
                  _CategoryAction(
                    label: 'Find Engineers',
                    icon: Icons.equalizer_rounded,
                    onTap: () => Navigator.pushNamed(context, '/find-collabs', arguments: 'engineer'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Sessions Card
              _buildCategoryCard(
                context,
                title: 'Sessions & Projects',
                description: 'Join existing songwriting circles, recording projects, or create a session.',
                actions: [
                  _CategoryAction(
                    label: 'Find Sessions',
                    icon: Icons.explore_rounded,
                    onTap: () => Navigator.pushNamed(context, '/find-sessions'),
                  ),
                  _CategoryAction(
                    label: 'Create Session',
                    icon: Icons.add_circle_outline_rounded,
                    onTap: () => Navigator.pushNamed(context, '/create-session'),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Edit Profile Button
              AnimatedTapDetector(
                onTap: () => Navigator.pushNamed(context, '/edit-profile'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primaryAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.manage_accounts_rounded, color: AppTheme.primaryAccent, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Update Collabs Profile',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String title,
    required String description,
    required List<_CategoryAction> actions,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF231F45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: actions.map((act) {
              final isLast = actions.indexOf(act) == actions.length - 1;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0.0 : 12.0),
                  child: AnimatedTapDetector(
                    onTap: act.onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(act.icon, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              act.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CategoryAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  _CategoryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}
