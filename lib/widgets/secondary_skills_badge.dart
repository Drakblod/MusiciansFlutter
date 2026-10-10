import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// A reusable badge/box that represents secondary skills for a member/musician.
/// Clearly clickable and pops open a dialog showing all secondary skills.
class SecondarySkillsBadge extends StatelessWidget {
  final String memberName;
  final List<String> secondarySkills;
  final bool isCompact;

  const SecondarySkillsBadge({
    super.key,
    required this.memberName,
    required this.secondarySkills,
    this.isCompact = false,
  });

  static void showSecondarySkillsDialog(
    BuildContext context, {
    required String memberName,
    required List<String> secondarySkills,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0C22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.stars_rounded, color: AppTheme.secondaryAccent, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Secondary Skills',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memberName.isNotEmpty) ...[
              Text(
                memberName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (secondarySkills.isEmpty)
              Text(
                'No secondary skills specified.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: secondarySkills.map((skill) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1A3A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2A4E)),
                    ),
                    child: Text(
                      skill,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Close',
              style: GoogleFonts.inter(
                color: AppTheme.primaryAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (secondarySkills.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showSecondarySkillsDialog(
          context,
          memberName: memberName,
          secondarySkills: secondarySkills,
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 6 : 9,
            vertical: isCompact ? 2 : 4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A3A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.secondaryAccent.withValues(alpha: 0.65),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.secondaryAccent.withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: isCompact ? 11 : 13,
                color: AppTheme.secondaryAccent,
              ),
              const SizedBox(width: 4),
              Text(
                'SECONDARY SKILLS',
                style: GoogleFonts.outfit(
                  fontSize: isCompact ? 8.5 : 10.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryAccent,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
