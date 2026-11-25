import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/secondary_skills_utils.dart';

class BandMemberProfileSkills extends StatefulWidget {
  final UserProfile profile;

  const BandMemberProfileSkills({super.key, required this.profile});

  @override
  State<BandMemberProfileSkills> createState() => _BandMemberProfileSkillsState();
}

class _BandMemberProfileSkillsState extends State<BandMemberProfileSkills> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final primary = SecondarySkillsUtils.normalize([profile.primarySkill]).firstOrNull;
    final secondary = profile.secondarySkills;
    final style = GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) Text('Primary Skill: $primary', style: style),
        if (secondary.isNotEmpty) ...[
          Semantics(
            expanded: _expanded,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryAccent,
                minimumSize: const Size(0, 48),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('Secondary Skills', style: style)),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final skill in secondary) Text(skill, style: style),
        ],
      ],
    );
  }
}
