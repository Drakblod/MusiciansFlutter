import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Shows the standardized "What is Map View?" guide and explanation dialog.
void showWhatIsMapViewDialog(BuildContext context, {String? description}) {
  final introText = description ??
      'Move pins towards the centre of the screen (telescopic sight) to hear different bands and their recordings, band info, gig promo, etc.\n';
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF0F0C20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E2A4E)),
      ),
      title: Row(
        children: [
          const Icon(Icons.help_outline_rounded, color: AppTheme.primaryAccent, size: 22),
          const SizedBox(width: 8),
          Text(
            'What is Map View?',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              introText.endsWith('\n') ? introText : '$introText\n',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'HOW TO EXPLORE & LISTEN:',
              style: GoogleFonts.outfit(
                color: AppTheme.primaryAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '• Crosshair / Centre: Move pins towards the centre of the screen (telescopic sight) to hear different bands and preview attached audio, band info, gig promo, etc.\n'
              '• Audio Snippets: Tap any pin or target with crosshair to preview attached recordings, band demos, and gig promos.\n'
              '• City Jumpers: Tap quick city buttons (Stockholm, Göteborg, Malmö, etc.) to immediately fly across Sweden.\n'
              '• Filters: Filter by Music, Sub & Member Search, or "This Week".\n',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            Text(
              'PIN NOTER & FÄRGER:',
              style: GoogleFonts.outfit(
                color: AppTheme.primaryAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            _buildDialogColorItem('Live Gig / Concert (Blinkande halvnot)', const Color(0xFFF97316), isHalfNote: true),
            const SizedBox(height: 6),
            _buildDialogColorItem('Live Rehearsal (Blinkande halvnot)', const Color(0xFFEF4444), isHalfNote: true),
            const SizedBox(height: 6),
            _buildDialogColorItem('Jam Session (Turkos not)', const Color(0xFF06B6D4)),
            const SizedBox(height: 6),
            _buildDialogColorItem('Demos / Recordings (Mörkblå not)', const Color(0xFF2563EB)),
            const SizedBox(height: 6),
            _buildDialogColorItem('Gig Promo (Lila not)', const Color(0xFFA855F7)),
            const SizedBox(height: 6),
            _buildDialogColorItem('New Member (Mörkgrön not)', const Color(0xFF047857)),
            const SizedBox(height: 6),
            _buildDialogColorItem('Subs (Limegrön not)', const Color(0xFF84CC16)),
            const SizedBox(height: 6),
            _buildDialogColorItem('Paid Gigs (Gul not)', const Color(0xFFEAB308)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('has_seen_map_intro', true);
            } catch (_) {}
          },
          child: Text(
            'Got it',
            style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDialogColorItem(String label, Color color, {bool isHalfNote = false}) {
  return Row(
    children: [
      Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: isHalfNote ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: isHalfNote ? Border.all(color: color, width: 2.5) : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: isHalfNote
              ? null
              : Icon(Icons.music_note_rounded, color: Colors.black.withOpacity(0.7), size: 10),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}
