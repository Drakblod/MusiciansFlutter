import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/audio_snippet_player.dart';
import 'edit_band_info_screen.dart';

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
                                      style: GoogleFonts.inter(
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

                          // Role / Main Skills
                          Text(
                            user.mainSkillsSubtitle,
                            textAlign: TextAlign.center,
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
                          if (user.genres.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.music_note_rounded,
                                  color: AppTheme.primaryAccent,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    user.genres.join(' • '),
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.primaryAccent.withOpacity(0.9),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Settings Action Row: Edit Profile, Edit Band & Logout
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: AnimatedTapDetector(
                                      onTap: () async {
                                        await Navigator.pushNamed(context, '/edit-profile');
                                        appState.refreshProfile();
                                      },
                                      child: Container(
                                        height: 44,
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
                                            const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Edit Profile',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: AnimatedTapDetector(
                                      onTap: () async {
                                        final activeBandId = appState.activeBandId;
                                        if (activeBandId != null) {
                                          final band = await appState.firebaseService.getBandInfoAsync(activeBandId);
                                          if (band != null && context.mounted) {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => EditBandInfoScreen(band: band),
                                              ),
                                            );
                                          }
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('No active band selected to edit.'),
                                              backgroundColor: AppTheme.warning,
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: AppTheme.cardBackground,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.groups_outlined, color: AppTheme.primaryAccent, size: 18),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Edit Band',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
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
                                          child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: Text('Logout', style: GoogleFonts.inter(color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    await appState.logout();
                                    Navigator.pushReplacementNamed(context, '/login');
                                  }
                                },
                                child: Container(
                                  width: double.infinity,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Logout',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

          // 1. PRIMARY SKILL/TALENT
          if (user.mainSkills.isNotEmpty) ...[
            Text(
              'PRIMARY SKILL/TALENT',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.mainSkills.map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: AppTheme.primaryAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        skill,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 2. Genres/Band Types
          if (user.genres.isNotEmpty) ...[
            Text(
              'Genres/Band Types',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.genres.map((genre) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(
                    genre,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 3. SECONDARY Skills/Talents
          if (user.secondarySkills.isNotEmpty) ...[
            Text(
              'SECONDARY Skills/Talents',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.secondarySkills.map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1A3A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Text(
                    skill,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 4. Level
          if (user.level != null && user.level!.isNotEmpty) ...[
            Text(
              'Level',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4), width: 1),
              ),
              child: Text(
                user.level!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 4. About Info section
          Text(
            'About',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 24),

          // 5. Collaborations
          Text(
            'Collaborations',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Specify what types of collaborations you are open to (if any)',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF231F45), width: 1),
            ),
            child: Text(
              user.collabBio != null && user.collabBio!.trim().isNotEmpty
                  ? user.collabBio!.trim()
                  : 'None specified',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: user.collabBio != null && user.collabBio!.trim().isNotEmpty
                    ? AppTheme.textSecondary
                    : AppTheme.textMuted,
                fontStyle: user.collabBio != null && user.collabBio!.trim().isNotEmpty
                    ? FontStyle.normal
                    : FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 6. SOCIAL LINKS
          if ((user.spotifyUrl != null && user.spotifyUrl!.isNotEmpty) ||
              (user.youtubeUrl != null && user.youtubeUrl!.isNotEmpty)) ...[
            Text(
              'SOCIAL LINKS',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (user.spotifyUrl != null && user.spotifyUrl!.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.music_note, color: Colors.green),
                      label: Text('Spotify', style: GoogleFonts.inter(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (user.spotifyUrl != null && user.spotifyUrl!.isNotEmpty &&
                    user.youtubeUrl != null && user.youtubeUrl!.isNotEmpty)
                  const SizedBox(width: 12),
                if (user.youtubeUrl != null && user.youtubeUrl!.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.play_circle_fill, color: Colors.red),
                      label: Text('YouTube', style: GoogleFonts.inter(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // 7. TRACKS
          if (user.audioSnippetUrl != null && user.audioSnippetUrl!.isNotEmpty) ...[
            Text(
              'TRACKS',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            AudioSnippetPlayer(audioUrl: user.audioSnippetUrl!),
            const SizedBox(height: 24),
          ],
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
                                      style: GoogleFonts.inter(color: Colors.white),
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
