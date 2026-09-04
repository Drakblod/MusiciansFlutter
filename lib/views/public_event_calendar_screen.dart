import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/feature_toggles.dart';
import '../models/public_calendar_event.dart';
import '../repositories/public_event_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/event_category_picker_sheet.dart';
import '../widgets/gradient_scaffold.dart';

class PublicEventCalendarScreen extends StatefulWidget {
  final PublicEventRepository? repository;
  final bool enableCategoryFallback;

  const PublicEventCalendarScreen({
    super.key,
    this.repository,
    this.enableCategoryFallback = true,
  });

  @override
  State<PublicEventCalendarScreen> createState() => _PublicEventCalendarScreenState();
}

class _PublicEventCalendarScreenState extends State<PublicEventCalendarScreen> {
  late final PublicEventRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = true;
  String? _errorMessage;
  List<PublicCalendarEvent> _allEvents = [];

  String _searchQuery = '';
  String _selectedFilter = EventCalendarCategories.all;
  int _visibleCount = 2; // Initial pagination limit for 3-event prototype
  bool _isOpeningPicker = false;
  bool _hasOpenedCategoryPickerOnSearchTap = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        (FeatureToggles.useMockPublicEventCalendar
            ? MockPublicEventRepository()
            : EmptyPublicEventRepository());
    _searchFocusNode.addListener(_handleSearchFocusChange);
    _loadEvents();
  }

  void _handleSearchFocusChange() {
    if (!_searchFocusNode.hasFocus && !_isOpeningPicker) {
      _hasOpenedCategoryPickerOnSearchTap = false;
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final events = await _repository.getUpcomingEvents();
      if (mounted) {
        setState(() {
          _allEvents = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load events.';
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    try {
      final events = await _repository.getUpcomingEvents();
      if (mounted) {
        setState(() {
          _allEvents = events;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load events.';
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _visibleCount = 2; // Reset pagination
    });
  }

  Future<void> _onSearchFieldTap() async {
    if (_hasOpenedCategoryPickerOnSearchTap || _searchController.text.isNotEmpty) {
      return;
    }
    _hasOpenedCategoryPickerOnSearchTap = true;
    await _openCategoryPicker();
    if (mounted) {
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> _openCategoryPicker() async {
    if (_isOpeningPicker) return;
    _isOpeningPicker = true;
    _searchFocusNode.unfocus();

    final selected = await EventCategoryPickerSheet.show(
      context: context,
      currentSelectedCategory: _selectedFilter,
    );

    _isOpeningPicker = false;

    if (selected != null && mounted) {
      setState(() {
        _selectedFilter = selected;
        _visibleCount = 2; // Reset pagination
      });
    }
  }

  void _onFilterSelected(String filter) {
    setState(() {
      _selectedFilter = filter;
      _visibleCount = 2; // Reset pagination
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedFilter = EventCalendarCategories.all;
      _visibleCount = 2;
      _hasOpenedCategoryPickerOnSearchTap = false;
    });
  }

  void _loadMore() {
    setState(() {
      _visibleCount += 2;
    });
  }

  List<PublicCalendarEvent> _getFilteredEvents() {
    return _allEvents.where((event) {
      // Category / Type Filter
      if (!EventCalendarCategories.matches(event, _selectedFilter)) {
        return false;
      }

      // Search Query
      if (_searchQuery.isNotEmpty) {
        final matchesTitle = event.title.toLowerCase().contains(_searchQuery);
        final matchesOrganizer = event.organizerName.toLowerCase().contains(_searchQuery);
        final matchesVenue = event.venueName.toLowerCase().contains(_searchQuery);
        final matchesCity = event.city.toLowerCase().contains(_searchQuery);
        final matchesShortDesc = event.shortDescription.toLowerCase().contains(_searchQuery);
        final matchesDesc = event.description.toLowerCase().contains(_searchQuery);
        final matchesGenres = event.genres.any((g) => g.toLowerCase().contains(_searchQuery));

        if (!matchesTitle &&
            !matchesOrganizer &&
            !matchesVenue &&
            !matchesCity &&
            !matchesShortDesc &&
            !matchesDesc &&
            !matchesGenres) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = _getFilteredEvents();
    final visibleEvents = filteredEvents.take(_visibleCount).toList();
    final hasMore = filteredEvents.length > _visibleCount;
    final hasMockEvents = _allEvents.any((e) => e.isMock);

    return GradientScaffold(
      appBar: const CustomTopBar(showBack: true),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              color: AppTheme.primaryAccent,
              backgroundColor: AppTheme.cardBackground,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Header Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'EVENT CALENDAR',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (hasMockEvents) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'DEMO EVENTS',
                                style: GoogleFonts.inter(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Discover live music, sessions, workshops and music events.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Search Input
                      Semantics(
                        label: 'Search events',
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2E2452)),
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            onTap: _onSearchFieldTap,
                            onChanged: _onSearchChanged,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search events...',
                              hintStyle: GoogleFonts.inter(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                              prefixIcon: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _openCategoryPicker,
                                child: const Icon(
                                  Icons.search_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 20,
                                ),
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white70),
                                      tooltip: 'Clear search text',
                                      onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged('');
                                        _hasOpenedCategoryPickerOnSearchTap = false;
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.tune_rounded, size: 18, color: AppTheme.secondaryAccent),
                                    tooltip: 'Select Category',
                                    onPressed: _openCategoryPicker,
                                  ),
                                ],
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      if (_selectedFilter != EventCalendarCategories.all) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Active category:',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedFilter,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => _onFilterSelected(EventCalendarCategories.all),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _onFilterSelected(EventCalendarCategories.all),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(40, 24),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Clear filter',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.secondaryAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Content / Loading / Error / Empty States
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadEvents,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryAccent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_allEvents.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            color: AppTheme.textSecondary.withValues(alpha: 0.4),
                            size: 56,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No public events available yet.',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upcoming concerts, sessions and workshops will appear here.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (filteredEvents.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            color: AppTheme.textSecondary.withValues(alpha: 0.4),
                            size: 56,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No events match your search.',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your search terms or clearing the active filters.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: _clearFilters,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryAccent,
                              side: const BorderSide(color: AppTheme.primaryAccent),
                            ),
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return _buildMonthGroupedList(visibleEvents)[index];
                      },
                      childCount: _buildMonthGroupedList(visibleEvents).length,
                    ),
                  ),
                ),

              // Load More Button
              if (!_isLoading && _errorMessage == null && hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Load More events',
                        child: OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more_rounded, size: 20),
                          label: Text(
                            'Load More',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryAccent,
                            side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  List<Widget> _buildMonthGroupedList(List<PublicCalendarEvent> events) {
    final List<Widget> items = [];
    String? currentMonthHeader;

    for (final event in events) {
      final monthHeader = DateFormat('MMMM yyyy').format(event.startDateTime).toUpperCase();

      if (currentMonthHeader != monthHeader) {
        currentMonthHeader = monthHeader;
        items.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Row(
              children: [
                Text(
                  monthHeader,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    color: const Color(0xFF2E2452),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _buildEventCard(event),
        ),
      );
    }

    return items;
  }

  Widget _buildEventCard(PublicCalendarEvent event) {
    final monthShort = DateFormat('MMM').format(event.startDateTime).toUpperCase();
    final dayStr = DateFormat('dd').format(event.startDateTime);
    final timeStr =
        '${DateFormat('HH:mm').format(event.startDateTime)} – ${DateFormat('HH:mm').format(event.endDateTime)}';
    final imageWidget = _buildEventCardImage(event);

    return Semantics(
      button: true,
      label: '${event.title}, ${event.eventTypeDisplayLabel}, ${event.venueName}, $dayStr $monthShort, ${event.formattedPrice}',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
          LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => Navigator.pushNamed(
              context,
              '/public-event-details',
              arguments: event,
            ),
          ),
        },
        child: AnimatedTapDetector(
          onTap: () {
            Navigator.pushNamed(
              context,
              '/public-event-details',
              arguments: event,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2452)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageWidget != null) imageWidget,

                // Card Top Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1A3A),
                    borderRadius: imageWidget == null
                        ? const BorderRadius.vertical(top: Radius.circular(15))
                        : BorderRadius.zero,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          event.eventTypeDisplayLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                      // Price Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: event.isFree
                              ? Colors.greenAccent.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          event.formattedPrice,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: event.isFree ? Colors.greenAccent : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Card Body
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Box
                      Container(
                        width: 50,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161033),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2452)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              monthShort,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryAccent,
                              ),
                            ),
                            Text(
                              dayStr,
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Event Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.organizerName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 13,
                                  color: Color(0xFFA899E6),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${event.venueName}, ${event.city}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFFD4CEEB),
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 13,
                                  color: Color(0xFFA899E6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFFD4CEEB),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              event.shortDescription,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (event.genres.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: event.genres.map((g) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF231F45),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      g,
                                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildEventCardImage(PublicCalendarEvent event) {
    final String? imageSource = EventCalendarArtwork.resolveArtwork(
      event,
      enableCategoryFallback: widget.enableCategoryFallback,
    );

    if (imageSource == null || imageSource.isEmpty) {
      return null;
    }

    final bool isNetwork =
        imageSource.startsWith('http://') || imageSource.startsWith('https://');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: isNetwork
            ? Image.network(
                imageSource,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildImageErrorFallback(),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: const Color(0xFF161033),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  );
                },
              )
            : Image.asset(
                imageSource,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildImageErrorFallback(),
              ),
      ),
    );
  }

  Widget _buildImageErrorFallback() {
    return Container(
      color: const Color(0xFF1E1A3A),
      height: 160,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 32,
              color: AppTheme.secondaryAccent.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Event Preview',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
