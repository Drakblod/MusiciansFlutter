import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Shows the standardized "What is Map View?" guide and explanation dialog.
void showWhatIsMapViewDialog(BuildContext context) {
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
              'Explore Map View to discover audio snippets from gigs, rehearsals, recordings and gig promos, as well as requests for band members, subs and paid gigs.\n',
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
              'Move pins towards the centre of the screen (telescopic sight) to hear different bands and their recordings, band info, gig promo, etc.\n\n'
              '• Audio Snippets: Tap any pin or target with crosshair to preview attached recordings, band demos, and gig promos.\n'
              '• City Jumpers: Tap quick city buttons (Stockholm, Göteborg, Malmö, etc.) to immediately fly across Sweden.\n'
              '• Filters: Filter by Music, Gig Promo, Sub & Member Search, or "This Week".\n',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            Text(
              'PIN EVENT TYPE COLORS:',
              style: GoogleFonts.outfit(
                color: AppTheme.primaryAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            _buildDialogColorItem('Gig / Concert / Live Performance', const Color(0xFFF97316), Icons.stadium_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Rehearsal', const Color(0xFFEF4444), Icons.music_note_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Jam Session', const Color(0xFF06B6D4), Icons.groups_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Recorded Music', const Color(0xFF2563EB), Icons.album_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Gig Promo', const Color(0xFFA855F7), Icons.campaign_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('New Member', const Color(0xFF047857), Icons.person_add_alt_1_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Subs', const Color(0xFF84CC16), Icons.swap_horiz_rounded),
            const SizedBox(height: 6),
            _buildDialogColorItem('Paid (All types of paid gigs)', const Color(0xFFEAB308), Icons.payments_rounded),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Got it',
            style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDialogColorItem(String label, Color color, IconData icon) {
  return Row(
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: Colors.black.withOpacity(0.7), size: 9),
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
