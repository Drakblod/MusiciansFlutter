import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../data/skills_taxonomy.dart';
import 'animated_tap_detector.dart';

/// Presentation mode for category multi-select sheets.
enum CategoryPickerPresentation {
  standard,
  skillsHierarchy,
}

class SearchableCategoryMultiSelectSheet extends StatefulWidget {
  final String title;
  final Map<String, List<String>> categoryMap;
  final List<String> initialSelected;
  final bool isSingleSelect;
  final int? maxSelection;
  final CategoryPickerPresentation presentation;

  const SearchableCategoryMultiSelectSheet({
    super.key,
    required this.title,
    required this.categoryMap,
    required this.initialSelected,
    this.isSingleSelect = false,
    this.maxSelection,
    this.presentation = CategoryPickerPresentation.standard,
  });

  static Future<List<String>?> show({
    required BuildContext context,
    required String title,
    required Map<String, List<String>> categoryMap,
    required List<String> initialSelected,
    bool isSingleSelect = false,
    int? maxSelection,
    CategoryPickerPresentation presentation =
        CategoryPickerPresentation.standard,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchableCategoryMultiSelectSheet(
        title: title,
        categoryMap: categoryMap,
        initialSelected: initialSelected,
        isSingleSelect: isSingleSelect,
        maxSelection: maxSelection,
        presentation: presentation,
      ),
    );
  }

  @override
  State<SearchableCategoryMultiSelectSheet> createState() =>
      _SearchableCategoryMultiSelectSheetState();
}

class _SearchableCategoryMultiSelectSheetState
    extends State<SearchableCategoryMultiSelectSheet> {
  late Set<String> _tempSelectedPersistedValues;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isSkillsHierarchy =>
      widget.presentation == CategoryPickerPresentation.skillsHierarchy;

  @override
  void initState() {
    super.initState();
    if (_isSkillsHierarchy) {
      _tempSelectedPersistedValues = widget.initialSelected
          .map((s) => SkillsTaxonomy.resolveCanonicalPersistedValue(s))
          .toSet();
    } else {
      _tempSelectedPersistedValues = widget.initialSelected.toSet();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleItem(String displayOrPersistedItem) {
    final persistedValue = _isSkillsHierarchy
        ? SkillsTaxonomy.getPersistedValueForDisplayLabel(
            displayOrPersistedItem)
        : displayOrPersistedItem;

    if (widget.isSingleSelect) {
      Navigator.pop(context, [persistedValue]);
      return;
    }

    setState(() {
      if (_tempSelectedPersistedValues.contains(persistedValue)) {
        _tempSelectedPersistedValues.remove(persistedValue);
      } else {
        if (widget.maxSelection != null &&
            _tempSelectedPersistedValues.length >= widget.maxSelection!) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'You can select a maximum of ${widget.maxSelection} items.'),
              backgroundColor: AppTheme.warning,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        _tempSelectedPersistedValues.add(persistedValue);
      }
    });
  }

  bool _isItemSelected(String displayOrPersistedItem) {
    if (_isSkillsHierarchy) {
      final persistedValue =
          SkillsTaxonomy.getPersistedValueForDisplayLabel(
              displayOrPersistedItem);
      return _tempSelectedPersistedValues.contains(persistedValue) ||
          _tempSelectedPersistedValues.contains(displayOrPersistedItem);
    }
    return _tempSelectedPersistedValues.contains(displayOrPersistedItem);
  }

  Widget _buildCategoryTitleWidget(String categoryName) {
    final leadingSymbol = _isSkillsHierarchy
        ? SkillsTaxonomy.getLeadingSymbolForCategory(categoryName)
        : null;

    final Widget textWidget;
    if (_isSkillsHierarchy &&
        categoryName.contains('(') &&
        categoryName.contains('Voices')) {
      final parts = categoryName.split('(');
      final mainTitle = parts.first.trim();
      final suffix = '(${parts.last}';

      textWidget = RichText(
        text: TextSpan(
          style: GoogleFonts.outfit(
            fontSize: 15,
            color: Colors.white,
          ),
          children: [
            TextSpan(
              text: mainTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: suffix,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
      );
    } else {
      textWidget = Text(
        categoryName,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }

    if (leadingSymbol != null && leadingSymbol.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              leadingSymbol,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: textWidget),
        ],
      );
    }

    return textWidget;
  }

  Widget _buildRoleOptions(List<String> items) {
    final featuredLabel = SkillsTaxonomy.featuredRoleDisplayLabel;
    final hasFeatured = items.contains(featuredLabel);
    final otherItems = items.where((item) => item != featuredLabel).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasFeatured) ...[
          ChoiceChip(
            key: const ValueKey('role_bandleader_chip'),
            label: Text(
              featuredLabel,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
            ),
            selected: _isItemSelected(featuredLabel),
            onSelected: (_) => _toggleItem(featuredLabel),
            selectedColor: AppTheme.primaryAccent,
            backgroundColor: AppTheme.inputBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: BorderSide(
              color: _isItemSelected(featuredLabel)
                  ? AppTheme.primaryAccent
                  : const Color(0xFF3F396B),
              width: 1.5,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              color: Color(0xFF2E2A4E),
              height: 12,
              thickness: 1,
            ),
          ),
        ],
        if (otherItems.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: otherItems.map((item) {
              final isSelected = _isItemSelected(item);
              return ChoiceChip(
                label: Text(item),
                selected: isSelected,
                onSelected: (_) => _toggleItem(item),
                selectedColor: AppTheme.primaryAccent,
                backgroundColor: AppTheme.inputBackground,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  color: Colors.white,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryAccent
                      : const Color(0xFF2E2A4E),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxSheetHeight = mediaQuery.size.height * 0.85;
    final isSkillsMode = _isSkillsHierarchy;

    // Filter categories based on search query
    final Map<String, List<String>> filteredCategories = {};
    widget.categoryMap.forEach((category, items) {
      if (_searchQuery.isEmpty) {
        filteredCategories[category] = items;
      } else {
        final queryLower = _searchQuery.toLowerCase();
        final categoryMatches = category.toLowerCase().contains(queryLower);
        final matchingItems = items.where((item) {
          if (item.toLowerCase().contains(queryLower)) return true;
          final opt = SkillsTaxonomy.findByDisplayLabel(item) ??
              SkillsTaxonomy.findByPersistedValue(item) ??
              SkillsTaxonomy.resolveLegacyValue(item);
          if (opt != null) {
            if (opt.persistedValue.toLowerCase().contains(queryLower)) {
              return true;
            }
            for (final alias in opt.aliases) {
              if (alias.toLowerCase().contains(queryLower)) {
                return true;
              }
            }
          }
          return false;
        }).toList();

        if (categoryMatches || matchingItems.isNotEmpty) {
          filteredCategories[category] =
              categoryMatches ? items : matchingItems;
        }
      }
    });

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C22).withOpacity(0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle & top bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      if (_tempSelectedPersistedValues.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppTheme.primaryAccent.withOpacity(0.5)),
                          ),
                          child: Text(
                            '${_tempSelectedPersistedValues.length}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search options...',
                hintStyle: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.primaryAccent, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: Colors.white54, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: AppTheme.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryAccent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Expandable Accordion List with RUTA-02 Structured Hierarchy
          Expanded(
            child: filteredCategories.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'No matching options found.',
                        style: GoogleFonts.inter(
                            color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    physics: const BouncingScrollPhysics(),
                    children: () {
                      final widgets = <Widget>[];
                      final categoryEntries = filteredCategories.entries.toList();

                      for (int i = 0; i < categoryEntries.length; i++) {
                        final entry = categoryEntries[i];
                        final categoryName = entry.key;
                        final items = entry.value;
                        final selectedInCategoryCount = items
                            .where((item) => _isItemSelected(item))
                            .length;
                        final isSearching = _searchQuery.isNotEmpty;

                        // RUTA-02: Non-selectable INSTRUMENTS/VOICES Section Heading
                        if (isSkillsMode && categoryName == 'Woodwinds') {
                          widgets.add(
                            Container(
                              key: const ValueKey(
                                  'instruments_voices_section_heading'),
                              margin: const EdgeInsets.only(
                                  top: 14, bottom: 10, left: 4, right: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1A3C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.primaryAccent.withOpacity(0.35),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.music_note_rounded,
                                    color: AppTheme.primaryAccent,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    SkillsTaxonomy.instrumentsVoicesSectionHeader,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // RUTA-02: Visual Separator before Voice Categories
                        if (isSkillsMode && categoryName == 'Voices (Choir)') {
                          widgets.add(
                            const Padding(
                              key: ValueKey('voices_section_separator'),
                              padding: EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 8),
                              child: Divider(
                                color: Color(0xFF2E2A4E),
                                thickness: 1.2,
                              ),
                            ),
                          );
                        }

                        // Category Expansion Card
                        widgets.add(
                          Theme(
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selectedInCategoryCount > 0
                                      ? AppTheme.primaryAccent.withOpacity(0.4)
                                      : const Color(0xFF231F45),
                                  width: 1,
                                ),
                              ),
                              child: ExpansionTile(
                                key: PageStorageKey<String>(categoryName),
                                initiallyExpanded: isSearching ||
                                    selectedInCategoryCount > 0,
                                iconColor: AppTheme.primaryAccent,
                                collapsedIconColor: AppTheme.textSecondary,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: _buildCategoryTitleWidget(
                                          categoryName),
                                    ),
                                    if (selectedInCategoryCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryAccent
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$selectedInCategoryCount selected',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryAccent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 12, right: 12, bottom: 12),
                                    child: isSkillsMode &&
                                            (categoryName == 'Roles/Production' ||
                                                categoryName ==
                                                    'Roles / Production')
                                        ? _buildRoleOptions(items)
                                        : Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: items.map((item) {
                                              final isSelected =
                                                  _isItemSelected(item);
                                              return ChoiceChip(
                                                label: Text(item),
                                                selected: isSelected,
                                                onSelected: (_) =>
                                                    _toggleItem(item),
                                                selectedColor:
                                                    AppTheme.primaryAccent,
                                                backgroundColor:
                                                    AppTheme.inputBackground,
                                                labelStyle: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: Colors.white,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                side: BorderSide(
                                                  color: isSelected
                                                      ? AppTheme.primaryAccent
                                                      : const Color(
                                                          0xFF2E2A4E),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return widgets;
                    }(),
                  ),
          ),

          // Bottom Action Bar
          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: mediaQuery.padding.bottom + 14,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0F0C22),
              border: Border(
                top: BorderSide(color: Color(0xFF231F45), width: 1),
              ),
            ),
            child: Row(
              children: [
                if (_tempSelectedPersistedValues.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _tempSelectedPersistedValues.clear();
                      });
                    },
                    child: Text(
                      'Clear All',
                      style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_tempSelectedPersistedValues.isNotEmpty)
                  const SizedBox(width: 12),
                Expanded(
                  child: AnimatedTapDetector(
                    onTap: () {
                      Navigator.pop(
                          context, _tempSelectedPersistedValues.toList());
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryAccent.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _tempSelectedPersistedValues.isEmpty
                              ? 'Done'
                              : 'Done (${_tempSelectedPersistedValues.length} Selected)',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
