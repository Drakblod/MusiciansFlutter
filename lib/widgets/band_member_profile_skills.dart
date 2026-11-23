import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/secondary_skills_utils.dart';

class BandMemberProfileSkills extends StatelessWidget {
  final UserProfile profile;

  const BandMemberProfileSkills({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final primary = SecondarySkillsUtils.normalize([profile.primarySkill]).firstOrNull;
    final secondary = profile.secondarySkills;
    final style = GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) Text('Primary Skill: $primary', style: style),
        if (secondary.isNotEmpty)
          Text('Secondary Skills: ${secondary.join(', ')}', style: style),
      ],
    );
  }
}
