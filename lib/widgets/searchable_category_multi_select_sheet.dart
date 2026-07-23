import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'animated_tap_detector.dart';

class SearchableCategoryMultiSelectSheet extends StatefulWidget {
  final String title;
  final Map<String, List<String>> categoryMap;
  final List<String> initialSelected;

  const SearchableCategoryMultiSelectSheet({
    super.key,
    required this.title,
    required this.categoryMap,
    required this.initialSelected,
  });

  static Future<List<String>?> show({
    required BuildContext context,
    required String title,
    required Map<String, List<String>> categoryMap,
    required List<String> initialSelected,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchableCategoryMultiSelectSheet(
        title: title,
        categoryMap: categoryMap,
        initialSelected: initialSelected,
      ),
    );
  }

  @override
  State<SearchableCategoryMultiSelectSheet> createState() =>
      _SearchableCategoryMultiSelectSheetState();
}

class _SearchableCategoryMultiSelectSheetState
    extends State<SearchableCategoryMultiSelectSheet> {
  late Set<String> _tempSelected;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tempSelected = Set<String>.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleItem(String item) {
    setState(() {
      if (_tempSelected.contains(item)) {
        _tempSelected.remove(item);
      } else {
        _tempSelected.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxSheetHeight = mediaQuery.size.height * 0.85;

    // Filter categories based on search query
    final Map<String, List<String>> filteredCategories = {};
    widget.categoryMap.forEach((category, items) {
      if (_searchQuery.isEmpty) {
        filteredCategories[category] = items;
      } else {
        final categoryMatches =
            category.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchingItems = items.where((item) {
          return item.toLowerCase().contains(_searchQuery.toLowerCase());
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
                Row(
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (_tempSelected.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppTheme.primaryAccent.withOpacity(0.5)),
                        ),
                        child: Text(
                          '${_tempSelected.length}',
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
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
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

          // Expandable Accordion List
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
                    children: filteredCategories.entries.map((entry) {
                      final categoryName = entry.key;
                      final items = entry.value;
                      final selectedInCategoryCount = items
                          .where((item) => _tempSelected.contains(item))
                          .length;

                      final isSearching = _searchQuery.isNotEmpty;

                      return Theme(
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
                                  child: Text(
                                    categoryName,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (selectedInCategoryCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryAccent
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
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
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: items.map((item) {
                                    final isSelected =
                                        _tempSelected.contains(item);
                                    return ChoiceChip(
                                      label: Text(item),
                                      selected: isSelected,
                                      onSelected: (_) => _toggleItem(item),
                                      selectedColor: AppTheme.primaryAccent,
                                      backgroundColor: AppTheme.inputBackground,
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
                                            : const Color(0xFF2E2A4E),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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
                if (_tempSelected.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _tempSelected.clear();
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
                if (_tempSelected.isNotEmpty) const SizedBox(width: 12),
                Expanded(
                  child: AnimatedTapDetector(
                    onTap: () {
                      Navigator.pop(context, _tempSelected.toList());
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
                          _tempSelected.isEmpty
                              ? 'Done'
                              : 'Done (${_tempSelected.length} Selected)',
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
