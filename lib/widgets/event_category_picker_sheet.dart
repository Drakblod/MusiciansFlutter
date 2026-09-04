import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/public_calendar_event.dart';
import '../theme/app_theme.dart';

class EventCategoryPickerSheet extends StatelessWidget {
  final String currentSelectedCategory;

  const EventCategoryPickerSheet({
    super.key,
    required this.currentSelectedCategory,
  });

  static Future<String?> show({
    required BuildContext context,
    required String currentSelectedCategory,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventCategoryPickerSheet(
        currentSelectedCategory: currentSelectedCategory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.75;

    final List<_CategoryOption> options = [
      const _CategoryOption(
        id: EventCalendarCategories.all,
        label: 'All Events',
        subtitle: 'Discover all upcoming concerts, sessions & workshops',
        icon: Icons.calendar_month_rounded,
      ),
      const _CategoryOption(
        id: EventCalendarCategories.liveGigs,
        label: EventCalendarCategories.liveGigs,
        subtitle: 'Concerts, live gigs, and showcase performances',
        icon: Icons.mic_external_on_rounded,
      ),
      const _CategoryOption(
        id: EventCalendarCategories.sessions,
        label: EventCalendarCategories.sessions,
        subtitle: 'Collaborative jam sessions & co-writing circles',
        icon: Icons.queue_music_rounded,
      ),
      const _CategoryOption(
        id: EventCalendarCategories.workshops,
        label: EventCalendarCategories.workshops,
        subtitle: 'Masterclasses, production courses & music clinics',
        icon: Icons.school_rounded,
      ),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C22).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EVENT CATEGORIES',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select a category to filter upcoming events',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
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
                itemCount: options.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Color(0xFF1E1A3A), height: 1),
                itemBuilder: (context, index) {
                  final item = options[index];
                  final isSelected = item.id == currentSelectedCategory ||
                      (item.id == EventCalendarCategories.all &&
                          (currentSelectedCategory.isEmpty ||
                              currentSelectedCategory == EventCalendarCategories.all));

                  return Material(
                    color: isSelected
                        ? AppTheme.primaryAccent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () {
                        Navigator.pop(context, item.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryAccent.withValues(alpha: 0.2)
                                    : const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                item.icon,
                                size: 20,
                                color: isSelected
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFFA899E6),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
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
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.primaryAccent,
                                size: 22,
                              ),
                          ],
                        ),
                      ),
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

class _CategoryOption {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;

  const _CategoryOption({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
  });
}
