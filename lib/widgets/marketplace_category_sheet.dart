import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/marketplace_taxonomy.dart';

class MarketplaceCategorySheet extends StatelessWidget {
  final String intent;
  final String? currentSelectedCategoryId;

  const MarketplaceCategorySheet({
    super.key,
    required this.intent,
    this.currentSelectedCategoryId,
  });

  static Future<String?> show({
    required BuildContext context,
    required String intent,
    String? currentSelectedCategoryId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MarketplaceCategorySheet(
        intent: intent,
        currentSelectedCategoryId: currentSelectedCategoryId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = MarketplaceTaxonomy.getIntentLabel(intent);
    final categories = MarketplaceTaxonomy.getCategoriesForIntent(intent);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.8;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C22).withOpacity(0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF2E2A4E), height: 1),

            // Options List
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: categories.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Color(0xFF1E1A3A), height: 1),
                itemBuilder: (context, index) {
                  final item = categories[index];
                  final isSelected = item.id == currentSelectedCategoryId;

                  return Focus(
                    child: Builder(
                      builder: (focusContext) {
                        return Material(
                          color: isSelected
                              ? AppTheme.primaryAccent.withOpacity(0.12)
                              : Colors.transparent,
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () {
                              Navigator.pop(context, item.id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? AppTheme.primaryAccent
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppTheme.primaryAccent,
                                      size: 20,
                                    )
                                  else
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.white30,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
