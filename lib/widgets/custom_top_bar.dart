import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'animated_tap_detector.dart';
import '../config/feature_toggles.dart';

class CustomTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final bool transparent;

  const CustomTopBar({
    super.key,
    this.title = '',
    this.showBack = false,
    this.transparent = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60.0);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final canPop = Navigator.of(context).canPop();

    return ClipRect(
      child: BackdropFilter(
        filter: transparent
            ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
            : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: transparent ? Colors.transparent : const Color(0xCC0F0C22),
            image: (FeatureToggles.useExperimentalHomeView && !transparent)
                ? const DecorationImage(
                    image: AssetImage('assets/images/header_base.png'),
                    fit: BoxFit.cover,
                  )
                : null,
            border: transparent
                ? null
                : const Border(
                    bottom: BorderSide(color: Color(0xFF231F45), width: 1.5),
                  ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  // Column 0: Back Button or Profile Avatar
                  Expanded(
                    child: _buildProfileOrBack(context, appState, canPop),
                  ),
                  // Column 1: Favorites Icon
                  Expanded(
                    child: _buildFavorites(context, appState),
                  ),
                  // Column 2: Home Logo
                  Expanded(
                    child: _buildHomeLogo(context, appState),
                  ),
                  // Column 3: Inbox / Direct Messages
                  Expanded(
                    child: _buildInbox(context, appState),
                  ),
                  // Column 4: Settings Menu
                  Expanded(
                    child: _buildSettings(context, appState),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileOrBack(BuildContext context, AppState appState, bool canPop) {
    final userProfile = appState.currentUserProfile;

    if (showBack || canPop) {
      return AnimatedTapDetector(
        onTap: () => Navigator.pop(context),
        child: const Center(
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else {
      return AnimatedTapDetector(
        onTap: () {
          Navigator.pushNamed(context, '/profile');
        },
        child: Center(
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
            backgroundImage: userProfile?.profilePictureUrl != null &&
                    userProfile!.profilePictureUrl!.isNotEmpty
                ? NetworkImage(userProfile.profilePictureUrl!)
                : null,
            child: userProfile?.profilePictureUrl == null ||
                    userProfile!.profilePictureUrl!.isEmpty
                ? Text(
                    (userProfile?.displayName != null && userProfile!.displayName!.isNotEmpty)
                        ? userProfile.displayName!.substring(0, 1).toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
      );
    }
  }

  Widget _buildFavorites(BuildContext context, AppState appState) {
    return AnimatedTapDetector(
      onTap: () {
        Navigator.pushNamed(context, '/favorites');
      },
      child: const Center(
        child: Icon(
          Icons.star_border_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildHomeLogo(BuildContext context, AppState appState) {
    return AnimatedTapDetector(
      onTap: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
        appState.setTab(0); // Switch root screen to Home tab
      },
      child: Center(
        child: FeatureToggles.useExperimentalHomeView
            ? Image.asset(
                'assets/images/header_m.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
              )
            : Text(
                'm',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                ),
              ),
      ),
    );
  }

  Widget _buildInbox(BuildContext context, AppState appState) {
    return AnimatedTapDetector(
      onTap: () {
        Navigator.pushNamed(context, '/inbox');
      },
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 24,
            ),
            if (appState.hasUnreadMessages)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, AppState appState) {
    return AnimatedTapDetector(
      onTap: () => _showSettingsMenu(context, appState),
      child: const Center(
        child: Icon(
          Icons.settings_outlined,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _showSettingsMenu(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20).withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SETTINGS',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 24),
                _buildMenuItem(
                  context,
                  icon: Icons.person_outline_rounded,
                  title: 'Edit Profile',
                  color: const Color(0xFF16C033),
                  onTap: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pushNamed(context, '/edit-profile');
                  },
                ),
                const SizedBox(height: 12),
                _buildMenuItem(
                  context,
                  icon: Icons.group_add_outlined,
                  title: 'Create Band',
                  color: const Color(0xFF3498DB),
                  onTap: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pushNamed(context, '/create-band');
                  },
                ),
                const SizedBox(height: 12),
                _buildMenuItem(
                  context,
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(context); // Close dialog
                    _showLogoutConfirmation(context, appState);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20).withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Logout',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to logout?',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2E2A4E)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'No',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          Navigator.pop(context); // Close confirmation dialog
                          await appState.logout();
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                          }
                        },
                        child: Text(
                          'Yes',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
