import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/band.dart';
import '../theme/app_theme.dart';

class StartLiveBroadcastDialog extends StatefulWidget {
  final Future<void> Function({
    required String bandId,
    required String bandName,
    required String title,
    String? genre,
    String? description,
  }) onStartBroadcast;

  const StartLiveBroadcastDialog({
    super.key,
    required this.onStartBroadcast,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function({
      required String bandId,
      required String bandName,
      required String title,
      String? genre,
      String? description,
    }) onStartBroadcast,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StartLiveBroadcastDialog(
          onStartBroadcast: onStartBroadcast,
        ),
      ),
    );
  }

  @override
  State<StartLiveBroadcastDialog> createState() => _StartLiveBroadcastDialogState();
}

class _StartLiveBroadcastDialogState extends State<StartLiveBroadcastDialog> {
  final TextEditingController _titleController = TextEditingController(text: 'Live Rehearsal');
  final TextEditingController _genreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isLoadingBands = true;
  bool _isStarting = false;
  String? _errorMessage;

  List<Band> _leaderBands = [];
  Band? _selectedBand;

  @override
  void initState() {
    super.initState();
    _loadLeaderBands();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _genreController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderBands() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      setState(() {
        _isLoadingBands = false;
        _errorMessage = 'Please sign in to broadcast live.';
      });
      return;
    }

    try {
      final userBandsMap = await appState.firebaseService.getUserBandsAsync(userId);
      final List<Band> leaderBands = [];

      for (final bandId in userBandsMap.keys) {
        final band = await appState.firebaseService.getBandInfoAsync(bandId);
        if (band != null && (band.canUserEdit(userId) || band.isUserLeader(userId))) {
          leaderBands.add(band);
        }
      }

      setState(() {
        _leaderBands = leaderBands;
        if (leaderBands.isNotEmpty) {
          _selectedBand = leaderBands.first;
          if (_selectedBand!.genres.isNotEmpty) {
            _genreController.text = _selectedBand!.genres.first;
          }
        }
        _isLoadingBands = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBands = false;
        _errorMessage = 'Could not load your bands: $e';
      });
    }
  }

  Future<void> _handleStart() async {
    if (_selectedBand == null || _selectedBand!.id == null) {
      setState(() {
        _errorMessage = 'Please select a band to broadcast for.';
      });
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a broadcast title.';
      });
      return;
    }

    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      await widget.onStartBroadcast(
        bandId: _selectedBand!.id!,
        bandName: _selectedBand!.name ?? 'Live Band',
        title: title,
        genre: _genreController.text.trim().isNotEmpty ? _genreController.text.trim() : null,
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.dangerRed, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRed.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.podcasts_rounded, color: AppTheme.dangerRed, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Go Live on Map',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Audio-only live stream for rehearsals & gigs',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dangerRed.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.dangerRed),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isLoadingBands) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(color: AppTheme.dangerRed),
                ),
              ),
            ] else if (_leaderBands.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.security_rounded, color: Colors.white38, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'Leader / Admin Access Required',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Only band leaders and admins can start live band broadcasts. Create a band or ask your band leader for admin access.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white60,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              // Band Selector Dropdown
              Text(
                'BROADCASTING AS',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Band>(
                    value: _selectedBand,
                    isExpanded: true,
                    dropdownColor: AppTheme.cardDark,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
                    items: _leaderBands.map((band) {
                      return DropdownMenuItem<Band>(
                        value: band,
                        child: Row(
                          children: [
                            Icon(Icons.groups_rounded, color: AppTheme.primaryAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                band.name ?? 'Band',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (Band? newBand) {
                      setState(() {
                        _selectedBand = newBand;
                        if (newBand != null && newBand.genres.isNotEmpty) {
                          _genreController.text = newBand.genres.first;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title input
              Text(
                'BROADCAST TITLE',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Live Rehearsal, Gig at Anchor, Soundcheck',
                  hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.cardDark,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.dangerRed, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Genre input
              Text(
                'GENRE / STYLE',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _genreController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Rock, Jazz, Blues, Metal',
                  hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.cardDark,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.dangerRed, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Start button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isStarting ? null : _handleStart,
                  icon: _isStarting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.radio_button_checked_rounded, color: Colors.white, size: 20),
                  label: Text(
                    _isStarting ? 'Starting Broadcast...' : 'Go Live Now',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dangerRed,
                    disabledBackgroundColor: AppTheme.dangerRed.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
}
