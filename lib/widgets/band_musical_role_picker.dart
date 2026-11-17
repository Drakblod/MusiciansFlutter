import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/skills_taxonomy.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../utils/band_membership_policy.dart';
import '../utils/membership_mutation_feedback.dart';
import 'searchable_category_multi_select_sheet.dart';
import 'skill_picker.dart';

class BandMusicalRolePicker {
  static Map<String, List<String>> get categories {
    final categories = SkillPicker.categories(SkillTaxonomyContext.editProfile);
    final vocalist = SkillsTaxonomy.findById('generic_vocalist')!.displayLabel;
    final voices = categories['Voices (Popular Music)']!;
    categories['Voices (Popular Music)'] = {vocalist, ...voices}.toList();
    return categories;
  }

  static Future<String?> show(
    BuildContext context,
    String name, {
    String? selected,
  }) async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Musical role',
      prompt:
          'Which instrument or role would you like $name to take on in this particular band?',
      categoryMap: categories,
      initialSelected: [if (selected != null) selected],
      isSingleSelect: true,
      presentation: CategoryPickerPresentation.skillsHierarchy,
    );
    return result?.singleOrNull;
  }

  static String label(String role) =>
      SkillsTaxonomy.getDisplayLabelForPersistedValue(role);

  static bool canEdit(BandMember manager, BandMember member) {
    final targetRole = member.role?.trim().toLowerCase();
    return member.userId != null &&
        BandMembershipPolicy.canManageMember(manager) &&
        (manager.role?.trim().toLowerCase() == 'leader' ||
            (targetRole != 'leader' &&
                (targetRole != 'admin' || member.userId == manager.userId)));
  }

  static String memberLabel(BandMember? member, UserProfile? profile) {
    final role = member?.musicalRole?.trim();
    if (role != null && role.isNotEmpty) return label(role);
    return profile?.primarySkill.nonEmpty ??
        profile?.mainInstrument?.split(',').first.trim().nonEmpty ??
        profile?.instruments.firstOrNull?.trim().nonEmpty ??
        '';
  }

  static Future<bool> edit(
    BuildContext context,
    String bandId,
    BandMember member,
    String name,
  ) async {
    final state = context.read<AppState>();
    final uid = state.currentUserId;
    final target = member.userId;
    if (uid == null || target == null || state.activeBandId != bandId) {
      return false;
    }
    final role = await show(context, name, selected: member.musicalRole);
    if (!context.mounted ||
        role == null ||
        uid != state.currentUserId ||
        state.activeBandId != bandId ||
        role == member.musicalRole) {
      return false;
    }
    final saved = await MembershipMutationFeedback.run(
      context,
      bandId,
      () => state.firebaseService.updateBandMemberMusicalRoleAsync(
        bandId,
        target,
        role,
      ),
    );
    if (!context.mounted || !saved) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$name's musical role: ${label(role)}")),
    );
    return true;
  }
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}
