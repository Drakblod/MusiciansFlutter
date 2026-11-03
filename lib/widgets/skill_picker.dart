import 'package:flutter/material.dart';
import '../data/skills_taxonomy.dart';
import 'searchable_category_multi_select_sheet.dart';

class SkillPicker {
  SkillPicker._();

  static Map<String, List<String>> categories(
    SkillTaxonomyContext taxonomyContext, {String? excludedSkill}
  ) {
    final excluded = excludedSkill?.trim().toLowerCase();
    final allowed = SkillsTaxonomy.optionsFor(taxonomyContext)
        .where((option) => option.kind != SkillOptionKind.action &&
            option.kind != SkillOptionKind.legacyHeader)
        .map((option) => option.persistedValue).toSet();
    final result = <String, List<String>>{};
    SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.editProfile).forEach((category, items) {
      final available = items.where((label) {
        final value = SkillsTaxonomy.getPersistedValueForDisplayLabel(label);
        return allowed.contains(value) && value.toLowerCase() != excluded;
      }).toList();
      if (available.isNotEmpty) result[category] = available;
    });
    return result;
  }

  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required SkillTaxonomyContext taxonomyContext,
    required List<String> selected,
    bool singleSelect = false,
    String? excludedSkill,
  }) => SearchableCategoryMultiSelectSheet.show(
    context: context,
    title: title,
    categoryMap: categories(taxonomyContext, excludedSkill: excludedSkill),
    initialSelected: selected,
    isSingleSelect: singleSelect,
    maxSelection: singleSelect ? 1 : null,
    presentation: CategoryPickerPresentation.skillsHierarchy,
  );
}

class PrimarySkillEditor extends StatelessWidget {
  final String? selected;
  final SkillTaxonomyContext taxonomyContext;
  final ValueChanged<String> onChanged;

  const PrimarySkillEditor({super.key, required this.selected,
    required this.taxonomyContext, required this.onChanged});

  Future<void> _open(BuildContext context) async {
    final result = await SkillPicker.show(context,
      title: 'Primary Skill/Talent (Select 1)',
      taxonomyContext: taxonomyContext,
      selected: [if (selected != null) selected!], singleSelect: true);
    if (!context.mounted || result == null || result.isEmpty) return;
    onChanged(result.single);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () => _open(context), icon: const Icon(Icons.music_note_outlined),
        label: const Text('Primary Skill/Talent (Select 1)'),
      ),
      if (selected != null) LayoutBuilder(builder: (context, constraints) =>
        ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: ActionChip(label: Text(SkillsTaxonomy.getDisplayLabelForPersistedValue(selected!),
            overflow: TextOverflow.ellipsis), onPressed: () => _open(context)))),
    ],
  );
}
