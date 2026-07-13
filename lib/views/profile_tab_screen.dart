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

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString.trim());
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch link: $urlString'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
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
                    Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF231F45), width: 1),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                  backgroundImage: user.profilePictureUrl != null && user.profilePictureUrl!.isNotEmpty
                      ? NetworkImage(user.profilePictureUrl!)
                      : null,
                  child: user.profilePictureUrl == null || user.profilePictureUrl!.isEmpty
                      ? Text(
                          (user.displayName != null && user.displayName!.isNotEmpty)
                              ? user.displayName!.substring(0, 1).toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'Alex Hill',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.userType ?? 'Musician',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
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
                      if (user.spotifyUrl != null || user.youtubeUrl != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (user.spotifyUrl != null && user.spotifyUrl!.isNotEmpty)
                              GestureDetector(
                                onTap: () => _launchUrl(user.spotifyUrl!),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.music_note, color: Colors.green, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Spotify',
                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (user.youtubeUrl != null && user.youtubeUrl!.isNotEmpty)
                              GestureDetector(
                                onTap: () => _launchUrl(user.youtubeUrl!),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.play_circle_fill, color: Colors.red, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'YouTube',
                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Edit Profile Icon Button
                AnimatedTapDetector(
                  onTap: () async {
                    await Navigator.pushNamed(context, '/edit-profile');
                    // Reload profile details upon returning
                    appState.refreshProfile();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                    ),
                    child: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                  ),
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
          const SizedBox(height: 30),

          // 5. Logout Button
          AnimatedTapDetector(
            onTap: () async {
              await appState.logout();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: Container(
              height: 55,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF2C101B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF5D1226), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      fontSize: 16,
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
      ),
    ),
  );
}
}
