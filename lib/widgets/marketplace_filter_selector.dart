import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/marketplace_taxonomy.dart';
import 'marketplace_category_sheet.dart';

class MarketplaceFilterSelector extends StatelessWidget {
  final String? selectedIntent;
  final String? selectedCategoryId;
  final ValueChanged<({String? intent, String? categoryId})> onFilterChanged;

  const MarketplaceFilterSelector({
    super.key,
    required this.selectedIntent,
    required this.selectedCategoryId,
    required this.onFilterChanged,
  });

  Future<void> _openSelector(BuildContext context, String intent) async {
    final currentCat = selectedIntent == intent ? selectedCategoryId : null;
    final chosenCategoryId = await MarketplaceCategorySheet.show(
      context: context,
      intent: intent,
      currentSelectedCategoryId: currentCat,
    );

    if (chosenCategoryId != null) {
      onFilterChanged((intent: intent, categoryId: chosenCategoryId));
    }
  }

  void _clearFilter() {
    onFilterChanged((intent: null, categoryId: null));
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedIntent != null && selectedCategoryId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // If a filter is active, optionally show a subtle active filter banner with reset option
          if (hasFilter) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACTIVE FILTER',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                  InkWell(
                    onTap: _clearFilter,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.close_rounded, size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Reset Filter',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // First Entry: I'M LOOKING FOR
          _buildSelectorCard(
            context: context,
            intent: MarketplaceTaxonomy.intentLookingFor,
            title: MarketplaceTaxonomy.labelLookingFor,
            subtitle: MarketplaceTaxonomy.subtitleLookingFor,
            icon: Icons.search_rounded,
          ),

          const SizedBox(height: 10),

          // Second Entry: I'M OFFERING
          _buildSelectorCard(
            context: context,
            intent: MarketplaceTaxonomy.intentOffering,
            title: MarketplaceTaxonomy.labelOffering,
            subtitle: MarketplaceTaxonomy.subtitleOffering,
            icon: Icons.storefront_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorCard({
    required BuildContext context,
    required String intent,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isThisIntentSelected = selectedIntent == intent && selectedCategoryId != null;
    final selectedCategoryLabel = isThisIntentSelected
        ? MarketplaceTaxonomy.getCategoryLabel(intent, selectedCategoryId)
        : null;

    return Semantics(
      button: true,
      label: isThisIntentSelected
          ? '$title. Selected category: $selectedCategoryLabel. Tap to change.'
          : '$title. $subtitle. Tap to select category.',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _openSelector(context, intent),
          ),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        child: InkWell(
          onTap: () => _openSelector(context, intent),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isThisIntentSelected
                  ? AppTheme.primaryAccent.withOpacity(0.08)
                  : AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isThisIntentSelected
                    ? AppTheme.primaryAccent
                    : const Color(0xFF2E2A4E),
                width: isThisIntentSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Leading Icon Container
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isThisIntentSelected
                        ? AppTheme.primaryAccent.withOpacity(0.2)
                        : const Color(0xFF1E1A3A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isThisIntentSelected
                        ? AppTheme.primaryAccent
                        : Colors.white70,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Subtitle / Selected Category
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Selected Category Badge & Reset Button or Chevron
                if (isThisIntentSelected) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      selectedCategoryLabel ?? '',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                    tooltip: 'Reset category',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _clearFilter,
                  ),
                ] else ...[
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
