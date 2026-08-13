import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/audio_snippet_player.dart';

class MusicianProfileScreen extends StatefulWidget {
  final UserProfile musician;
  final bool isTab;

  const MusicianProfileScreen({
    super.key,
    required this.musician,
    this.isTab = false,
  });

  @override
  State<MusicianProfileScreen> createState() => _MusicianProfileScreenState();
}

class _MusicianProfileScreenState extends State<MusicianProfileScreen> {
  bool _isFavorite = false;
  bool _isCheckingFav = true;

  @override
  void initState() {
    _checkFavorite();
    super.initState();
  }

  Future<void> _checkFavorite() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final fav = await appState.firebaseService.isFavoriteAsync(
      widget.musician.userId ?? '',
    );
    if (mounted) {
      setState(() {
        _isFavorite = fav;
        _isCheckingFav = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final appState = Provider.of<AppState>(context, listen: false);
    setState(() {
      _isFavorite = !_isFavorite;
    });
    await appState.firebaseService.toggleFavoriteAsync(
      widget.musician.userId ?? '',
      _isFavorite,
    );
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString.trim());
      final success = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
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

  Future<void> _openChat() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    final otherId = widget.musician.userId;

    if (selfId == null || otherId == null) return;

    // Create or retrieve conversation UID
    final convId = await appState.firebaseService
        .getOrCreateDirectConversationAsync(selfId, otherId);

    if (mounted) {
      Navigator.pushNamed(
        context,
        '/chat-detail',
        arguments: {
          'conversationId': convId,
          'receiverId': otherId,
          'receiverName': widget.musician.displayName ?? 'Musician',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultAbout =
        "Passionate musician looking to collaborate. Love playing live gigs and creating fresh arrangements in the studio.";
    final skills = widget.musician.instruments.isEmpty
        ? ['Studio Recording', 'Live Performance', 'Songwriting']
        : [...widget.musician.instruments, 'Live Performance', 'Songwriting'];

    final appState = Provider.of<AppState>(context);
    final isMe = widget.musician.userId == appState.currentUserId;

    return GradientScaffold(
      appBar: CustomTopBar(
        showBack: !widget.isTab,
        title: widget.isTab ? 'My Profile' : '',
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0C22),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Profile Photo / Visual Hero
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryAccent,
                        width: 2,
                      ),
                      color: AppTheme.inputBackground,
                    ),
                    child: Center(
                      child:
                          widget.musician.profilePictureUrl != null &&
                              widget.musician.profilePictureUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                widget.musician.profilePictureUrl!,
                                width: 106,
                                height: 106,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Text(
                              (widget.musician.displayName != null &&
                                      widget.musician.displayName!.isNotEmpty)
                                  ? widget.musician.displayName!
                                        .substring(0, 1)
                                        .toUpperCase()
                                  : 'U',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name & Verified Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.musician.displayName ?? 'Unknown Artist',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.blue,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Role / Primary Skills
                  Text(
                    widget.musician.mainSkillsSubtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppTheme.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Location & Level Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.musician.location ?? 'Stockholm, Sweden',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (widget.musician.level != null &&
                          widget.musician.level!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.primaryAccent.withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            widget.musician.level!,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.musician.genres.isNotEmpty) ...[
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
                            widget.musician.genres.join(' • '),
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
                  if (widget.musician.spotifyUrl != null ||
                      widget.musician.youtubeUrl != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.musician.spotifyUrl != null &&
                            widget.musician.spotifyUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.music_note,
                                color: Colors.green,
                                size: 24,
                              ),
                              onPressed: () =>
                                  _launchUrl(widget.musician.spotifyUrl!),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.inputBackground,
                                side: const BorderSide(
                                  color: Color(0xFF2E2A4E),
                                ),
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ),
                        if (widget.musician.youtubeUrl != null &&
                            widget.musician.youtubeUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.play_circle_fill,
                                color: Colors.red,
                                size: 24,
                              ),
                              onPressed: () =>
                                  _launchUrl(widget.musician.youtubeUrl!),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.inputBackground,
                                side: const BorderSide(
                                  color: Color(0xFF2E2A4E),
                                ),
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Genres
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children:
                        (widget.musician.genres.isEmpty
                                ? ['Rock', 'Pop', 'Indie']
                                : widget.musician.genres)
                            .map(
                              (genre) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.inputBackground,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF2E2A4E),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  genre,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.secondaryAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Profile Details Body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. PRIMARY Skills/Talents
                  if (widget.musician.mainSkills.isNotEmpty) ...[
                    Text(
                      'PRIMARY Skills/Talents',
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
                      children: widget.musician.mainSkills.map((skill) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryAccent.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: AppTheme.primaryAccent,
                                size: 16,
                              ),
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

                  // 2. SECONDARY Skills/Talents
                  if (widget.musician.secondarySkills.isNotEmpty) ...[
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
                      children: widget.musician.secondarySkills.map((skill) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A3A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF2E2A4E),
                              width: 1,
                            ),
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

                  // 3. Genres/Band Types
                  if (widget.musician.genres.isNotEmpty) ...[
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
                      children: widget.musician.genres.map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.primaryAccent.withOpacity(0.4),
                              width: 1,
                            ),
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

                  // 4. About Section
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
                      border: Border.all(
                        color: const Color(0xFF231F45),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      widget.musician.about != null &&
                              widget.musician.about!.isNotEmpty
                          ? widget.musician.about!
                          : defaultAbout,
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
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF231F45),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      widget.musician.collabBio != null &&
                              widget.musician.collabBio!.isNotEmpty
                          ? widget.musician.collabBio!
                          : "I'm looking for musical collaborations!",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 6. SOCIAL LINKS
                  if ((widget.musician.spotifyUrl != null &&
                          widget.musician.spotifyUrl!.isNotEmpty) ||
                      (widget.musician.youtubeUrl != null &&
                          widget.musician.youtubeUrl!.isNotEmpty)) ...[
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
                        if (widget.musician.spotifyUrl != null &&
                            widget.musician.spotifyUrl!.isNotEmpty)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _launchUrl(widget.musician.spotifyUrl!),
                              icon: const Icon(
                                Icons.music_note,
                                color: Colors.green,
                              ),
                              label: Text(
                                'Spotify',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.green),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        if (widget.musician.spotifyUrl != null &&
                            widget.musician.spotifyUrl!.isNotEmpty &&
                            widget.musician.youtubeUrl != null &&
                            widget.musician.youtubeUrl!.isNotEmpty)
                          const SizedBox(width: 12),
                        if (widget.musician.youtubeUrl != null &&
                            widget.musician.youtubeUrl!.isNotEmpty)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _launchUrl(widget.musician.youtubeUrl!),
                              icon: const Icon(
                                Icons.play_circle_fill,
                                color: Colors.red,
                              ),
                              label: Text(
                                'YouTube',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 7. TRACKS
                  if (widget.musician.audioSnippetUrl != null &&
                      widget.musician.audioSnippetUrl!.isNotEmpty) ...[
                    Text(
                      'TRACKS',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AudioSnippetPlayer(
                      audioUrl: widget.musician.audioSnippetUrl!,
                    ),
                    const SizedBox(height: 24),
                  ],
                  const SizedBox(height: 20),
                  // Bottom Action Buttons (Message & Add, or Edit & Logout if isMe)
                  Row(
                    children: [
                      // Primary Button (Message or Edit Profile)
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: isMe
                              ? () => Navigator.pushNamed(
                                  context,
                                  '/edit-profile',
                                )
                              : _openChat,
                          child: Container(
                            height: 55,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryAccent.withOpacity(
                                    0.3,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isMe
                                      ? Icons.edit_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isMe ? 'Edit Profile' : 'Message',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
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

                      // Secondary Button (Favorite, or Logout if isMe)
                      AnimatedTapDetector(
                        onTap: isMe
                            ? () => _showLogoutConfirmation(context, appState)
                            : _toggleFavorite,
                        child: Container(
                          width: 55,
                          height: 55,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF231F45),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: isMe
                                ? const Icon(
                                    Icons.logout_rounded,
                                    color: Colors.redAccent,
                                    size: 24,
                                  )
                                : (_isCheckingFav
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.primaryAccent,
                                          ),
                                        )
                                      : Icon(
                                          _isFavorite
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          color: _isFavorite
                                              ? AppTheme.primaryAccent
                                              : Colors.white,
                                          size: 26,
                                        )),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Logout',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to logout?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
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
                          Navigator.pop(context); // Close dialog
                          await appState.logout();
                          if (context.mounted) {
                            Navigator.of(
                              context,
                            ).pushReplacementNamed('/login');
                          }
                        },
                        child: Text(
                          'Logout',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
