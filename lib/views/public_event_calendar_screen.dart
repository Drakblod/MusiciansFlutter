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
import '../widgets/gradient_scaffold.dart';

class PublicEventCalendarScreen extends StatefulWidget {
  final PublicEventRepository? repository;

  const PublicEventCalendarScreen({super.key, this.repository});

  @override
  State<PublicEventCalendarScreen> createState() => _PublicEventCalendarScreenState();
}

class _PublicEventCalendarScreenState extends State<PublicEventCalendarScreen> {
  late final PublicEventRepository _repository;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<PublicCalendarEvent> _allEvents = [];

  String _searchQuery = '';
  String _selectedFilter = 'All';
  int _visibleCount = 2; // Initial pagination limit for 3-event prototype

  static const List<String> _filters = [
    'All',
    'Live/Gigs',
    'Open Sessions',
    'Workshops',
  ];

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        (FeatureToggles.useMockPublicEventCalendar
            ? MockPublicEventRepository()
            : EmptyPublicEventRepository());
    _loadEvents();
  }

  @override
  void dispose() {
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
      _selectedFilter = 'All';
      _visibleCount = 2;
    });
  }

  void _loadMore() {
    setState(() {
      _visibleCount += 2;
    });
  }

  List<PublicCalendarEvent> _getFilteredEvents() {
    return _allEvents.where((event) {
      // Type Filter
      if (_selectedFilter != 'All' && event.typeFilterCategory != _selectedFilter) {
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
                          Text(
                            'EVENT CALENDAR',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          if (hasMockEvents)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.withOpacity(0.4)),
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
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Discover live music, open sessions, workshops and music events.',
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
                            onChanged: _onSearchChanged,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search events, artists, venues or cities...',
                              hintStyle: GoogleFonts.inter(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white70),
                                      onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged('');
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Type Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _filters.map((filter) {
                            final isSelected = _selectedFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Semantics(
                                button: true,
                                selected: isSelected,
                                label: 'Filter by $filter',
                                child: FocusableActionDetector(
                                  mouseCursor: SystemMouseCursors.click,
                                  shortcuts: {
                                    LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
                                    LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
                                  },
                                  actions: {
                                    ActivateIntent: CallbackAction<ActivateIntent>(
                                      onInvoke: (_) => _onFilterSelected(filter),
                                    ),
                                  },
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _onFilterSelected(filter),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.primaryAccent : const Color(0xFF1E1A3A),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppTheme.primaryAccent
                                              : const Color(0xFF2E2452),
                                        ),
                                      ),
                                      child: Text(
                                        filter,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? Colors.white : Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
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
                            color: AppTheme.textSecondary.withOpacity(0.4),
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
                            'Upcoming concerts, open sessions and workshops will appear here.',
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
                            color: AppTheme.textSecondary.withOpacity(0.4),
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
                // Card Top Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1A3A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withOpacity(0.2),
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
                              ? Colors.greenAccent.withOpacity(0.15)
                              : Colors.white.withOpacity(0.1),
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
                                const Icon(Icons.location_on_outlined, size: 13, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${event.venueName}, ${event.city}',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 13, color: AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
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
}
