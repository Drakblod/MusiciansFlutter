import 'package:flutter/material.dart';
import '../data/skills_taxonomy.dart';
import '../utils/secondary_skills_utils.dart';
import 'searchable_category_multi_select_sheet.dart';

/// Local draft editor; only the parent form's save persists selections.
class SecondarySkillsEditor extends StatelessWidget {
  final String? primarySkill;
  final List<String> selected;
  final SkillTaxonomyContext taxonomyContext;
  final ValueChanged<List<String>> onChanged;

  const SecondarySkillsEditor({
    super.key,
    required this.primarySkill,
    required this.selected,
    required this.taxonomyContext,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final primary = primarySkill?.trim().toLowerCase();
    final allowed = SkillsTaxonomy.optionsFor(taxonomyContext)
        .where((option) => option.kind != SkillOptionKind.action &&
            option.kind != SkillOptionKind.legacyHeader)
        .map((option) => option.persistedValue).toSet();
    final categories = <String, List<String>>{};
    SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile).forEach((category, items) {
      final available = items.where((label) {
        final value = SkillsTaxonomy.getPersistedValueForDisplayLabel(label);
        return allowed.contains(value) && value.toLowerCase() != primary;
      }).toList();
      if (available.isNotEmpty) categories[category] = available;
    });
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Secondary Skills (optional)',
      categoryMap: categories,
      initialSelected: selected,
      presentation: CategoryPickerPresentation.skillsHierarchy,
    );
    if (!context.mounted || result == null) return;
    onChanged(SecondarySkillsUtils.normalize(result, primarySkill: primarySkill));
  }

  @override
  Widget build(BuildContext context) {
    final skills = SecondarySkillsUtils.normalize(selected, primarySkill: primarySkill);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => _openPicker(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Secondary Skills (optional)'),
        ),
        if (skills.isNotEmpty)
          LayoutBuilder(builder: (context, constraints) {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skills.map((skill) => ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: InputChip(
                  label: Text(skill, overflow: TextOverflow.ellipsis),
                  tooltip: skill,
                  onDeleted: () => onChanged(skills.where((s) => s != skill).toList()),
                ),
              )).toList(),
            );
          }),
      ],
    );
  }
}
