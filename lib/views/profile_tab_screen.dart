import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/audio_snippet_player.dart';

class ProfileTabScreen extends StatefulWidget {
  const ProfileTabScreen({super.key});

  @override
  State<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends State<ProfileTabScreen> {
  List<UserProfile> _favoriteMusicians = [];
  bool _isLoadingFavorites = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFavorites();
    });
  }



  Future<void> _loadFavorites() async {
    setState(() => _isLoadingFavorites = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final favoriteUserIds = await appState.firebaseService.getFavoriteUserIdsAsync();
      final setOfFavorites = favoriteUserIds.toSet();
      
      final allUsers = await appState.firebaseService.getAllUsersAsync();
      
      final List<UserProfile> favList = allUsers
          .where((user) => user.userId != null && setOfFavorites.contains(user.userId))
          .toList();

      if (mounted) {
        setState(() {
          _favoriteMusicians = favList;
        });
      }
    } catch (e) {
      debugPrint("Error loading favorites: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingFavorites = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUserProfile;
    const defaultAbout = "Passionate musician looking to collaborate. Love playing live gigs and creating fresh arrangements in the studio.";

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Profile',
        showBack: true,
      ),
      body: SafeArea(
        child: user == null
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Standardized Centered Profile Header
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          // Profile Photo
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.primaryAccent, width: 2),
                              color: AppTheme.inputBackground,
                            ),
                            child: Center(
                              child: user.profilePictureUrl != null && user.profilePictureUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        user.profilePictureUrl!,
                                        width: 106,
                                        height: 106,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Text(
                                      (user.displayName != null && user.displayName!.isNotEmpty)
                                          ? user.displayName!.substring(0, 1).toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 44,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Name & Verified badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                user.displayName ?? 'Alex Hill',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Role / Instrument
                          Text(
                            user.userType ?? 'Musician',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Location
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: AppTheme.textSecondary,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user.location ?? 'Stockholm, Sweden',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Edit Profile & Logout Row
                          Row(
                            children: [
                              Expanded(
                                child: AnimatedTapDetector(
                                  onTap: () async {
                                    await Navigator.pushNamed(context, '/edit-profile');
                                    appState.refreshProfile();
                                  },
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.primaryGradient,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryAccent.withOpacity(0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Edit Profile',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              AnimatedTapDetector(
                                onTap: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: AppTheme.cardBackground,
                                      title: const Text('Logout?'),
                                      content: const Text('Are you sure you want to logout?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await appState.logout();
                                    if (context.mounted) {
                                      Navigator.pushReplacementNamed(context, '/login');
                                    }
                                  }
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF231F45), width: 1),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.logout_rounded,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

          // 2. About Info section
          Text(
            'About Me',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF231F45), width: 1),
            ),
            child: Text(
              user.about != null && user.about!.isNotEmpty ? user.about! : defaultAbout,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          if (user.audioSnippetUrl != null && user.audioSnippetUrl!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Tracks',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            AudioSnippetPlayer(audioUrl: user.audioSnippetUrl!),
          ],
          const SizedBox(height: 24),

          // 3. Bands / Rehearsals section
          Text(
            'Active Band',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF231F45), width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.groups_rounded, color: AppTheme.primaryAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appState.activeBandName ?? 'Deku Tree Bongo',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          appState.activeBandId != null ? 'Active' : 'Default Mock Band',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 4. Favorites / Followed musicians
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Favorite Musicians',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: _loadFavorites,
                child: const Icon(Icons.refresh_rounded, color: AppTheme.primaryAccent, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _isLoadingFavorites
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                ))
              : _favoriteMusicians.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF231F45), width: 1),
                      ),
                      child: Center(
                        child: Text(
                          'No favorited musicians yet.',
                          style: GoogleFonts.inter(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _favoriteMusicians.length,
                      itemBuilder: (context, index) {
                        final musician = _favoriteMusicians[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF231F45), width: 1),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryAccent.withOpacity(0.1),
                              backgroundImage: musician.profilePictureUrl != null && musician.profilePictureUrl!.isNotEmpty
                                  ? NetworkImage(musician.profilePictureUrl!)
                                  : null,
                              child: musician.profilePictureUrl == null || musician.profilePictureUrl!.isEmpty
                                  ? Text(
                                      (musician.displayName != null && musician.displayName!.isNotEmpty)
                                          ? musician.displayName!.substring(0, 1).toUpperCase()
                                          : 'U',
                                      style: const TextStyle(color: Colors.white),
                                    )
                                  : null,
                            ),
                            title: Text(
                              musician.displayName ?? 'Unknown',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            subtitle: Text(
                              musician.userType ?? 'Musician',
                              style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontSize: 12),
                            ),
                            trailing: GestureDetector(
                              onTap: () async {
                                await appState.firebaseService.toggleFavoriteAsync(musician.userId ?? '', false);
                                _loadFavorites();
                              },
                              child: const Icon(Icons.star_rounded, color: AppTheme.primaryAccent, size: 24),
                            ),
                            onTap: () {
                              Navigator.pushNamed(context, '/profile-detail', arguments: musician);
                            },
                          ),
                        );
                      },
                    ),
          const SizedBox(height: 40),
          ],
        ),
      ),
    ),
  );
}
}
