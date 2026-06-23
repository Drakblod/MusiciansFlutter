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

  const MusicianProfileScreen({
    super.key,
    required this.musician,
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
    final fav = await appState.firebaseService.isFavoriteAsync(widget.musician.userId ?? '');
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
    await appState.firebaseService.toggleFavoriteAsync(widget.musician.userId ?? '', _isFavorite);
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

  Future<void> _openChat() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    final otherId = widget.musician.userId;

    if (selfId == null || otherId == null) return;

    // Create or retrieve conversation UID
    final convId = await appState.firebaseService.getOrCreateDirectConversationAsync(selfId, otherId);

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

    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
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
                      border: Border.all(color: AppTheme.primaryAccent, width: 2),
                      color: AppTheme.inputBackground,
                    ),
                    child: Center(
                      child: widget.musician.profilePictureUrl != null &&
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
                              (widget.musician.displayName ?? 'U').substring(0, 1).toUpperCase(),
                              style: const TextStyle(
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

                  // Role / Instrument
                  Text(
                    widget.musician.userType ?? 'Instrumentalist',
                    style: GoogleFonts.inter(
                      fontSize: 15,
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
                    ],
                  ),
                  if (widget.musician.spotifyUrl != null || widget.musician.youtubeUrl != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.musician.spotifyUrl != null && widget.musician.spotifyUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: IconButton(
                              icon: const Icon(Icons.music_note, color: Colors.green, size: 24),
                              onPressed: () => _launchUrl(widget.musician.spotifyUrl!),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.inputBackground,
                                side: const BorderSide(color: Color(0xFF2E2A4E)),
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ),
                        if (widget.musician.youtubeUrl != null && widget.musician.youtubeUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 24),
                              onPressed: () => _launchUrl(widget.musician.youtubeUrl!),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.inputBackground,
                                side: const BorderSide(color: Color(0xFF2E2A4E)),
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
                    children: (widget.musician.genres.isEmpty
                            ? ['Rock', 'Pop', 'Indie']
                            : widget.musician.genres)
                        .map((genre) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.inputBackground,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                              ),
                              child: Text(
                                genre,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.secondaryAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ))
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
                  // About Section
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
                      widget.musician.about != null && widget.musician.about!.isNotEmpty
                          ? widget.musician.about!
                          : defaultAbout,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (widget.musician.audioSnippetUrl != null && widget.musician.audioSnippetUrl!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Audio Snippet',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AudioSnippetPlayer(audioUrl: widget.musician.audioSnippetUrl!),
                  ],
                  const SizedBox(height: 24),

                  // Skills Section
                  Text(
                    'Skills',
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
                    children: skills
                        .map((skill) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF231F45), width: 1),
                              ),
                              child: Text(
                                skill,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 24),

                  // Availability Section
                  Text(
                    'Availability',
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekdays after 18:00',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Weekends: Anytime',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Bottom Action Buttons (Message & Add)
                  Row(
                    children: [
                      // Message Button
                      Expanded(
                        child: AnimatedTapDetector(
                          onTap: _openChat,
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
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Message',
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

                      // Follow/Favorite Button
                      AnimatedTapDetector(
                        onTap: _toggleFavorite,
                        child: Container(
                          width: 55,
                          height: 55,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF231F45), width: 1),
                          ),
                          child: Center(
                            child: _isCheckingFav
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primaryAccent,
                                    ),
                                  )
                                : Icon(
                                    _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                    color: _isFavorite ? AppTheme.primaryAccent : Colors.white,
                                    size: 26,
                                  ),
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
}
