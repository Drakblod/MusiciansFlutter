import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band_event.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import 'event_details_page.dart';
import 'event_results_page.dart';
import 'create_event_page.dart';
import '../utils/date_parser.dart';
import '../controllers/global_create_event_launcher.dart';

enum EventTabType { newEvents, upcoming, past }

class ManageEventsScreen extends StatefulWidget {
  final String? initialBandId;
  final bool embedded;

  const ManageEventsScreen({
    super.key,
    this.initialBandId,
    this.embedded = false,
  });

  @override
  State<ManageEventsScreen> createState() => _ManageEventsScreenState();
}

class _ManageEventsScreenState extends State<ManageEventsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  Map<String, String> _userBands = {};
  Map<String, String> _userRoles = {}; // bandId -> role
  bool _isLoading = true;
  String _searchQuery = '';

  // All loaded events: bandId -> List<BandEvent>
  final Map<String, List<BandEvent>> _bandEventsMap = {};
  final List<StreamSubscription<List<BandEvent>>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBandsAndEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadBandsAndEvents() async {
    setState(() => _isLoading = true);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final bands = await appState.firebaseService.getUserBandsAsync(userId);
      final Map<String, String> roles = {};

      for (final bandId in bands.keys) {
        try {
          final role = await appState.firebaseService.getUserBandRoleAsync(bandId, userId);
          roles[bandId] = (role ?? '').trim().toLowerCase();
        } catch (_) {
          roles[bandId] = 'member';
        }
      }

      if (mounted) {
        setState(() {
          _userBands = bands;
          _userRoles = roles;
        });
      }

      // Subscribe to events for each band
      for (final bandId in bands.keys) {
        final sub = appState.firebaseService.subscribeToBandEvents(bandId).listen((events) {
          if (mounted) {
            setState(() {
              _bandEventsMap[bandId] = events;
              _isLoading = false;
            });
          }
        });
        _subscriptions.add(sub);
      }

      if (bands.isEmpty && mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading manage events data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getEventTypeIcon(String type) {
    if (type == 'Soundcheck') return Icons.tune_rounded;
    if (type == 'Club gig') return Icons.nightlife_rounded;
    if (type == 'Concert') return Icons.stadium_rounded;
    if (type == 'Show') return Icons.theater_comedy_rounded;
    if (type == 'Private Event') return Icons.celebration_rounded;
    if (type == 'Load-in / Setup') return Icons.local_shipping_outlined;
    if (type == 'Meeting') return Icons.groups_outlined;
    if (type == 'Other') return Icons.more_horiz_rounded;
    return Icons.music_note_rounded;
  }

  bool _isLeaderOrAdmin(String bandId) {
    final role = _userRoles[bandId] ?? '';
    return role == 'leader' || role == 'admin' || role == 'mod';
  }

  List<MapEntry<String, BandEvent>> _getFilteredEvents({required EventTabType tabType}) {
    final now = DateTime.now();
    final List<MapEntry<String, BandEvent>> result = [];

    for (final bandId in _userBands.keys) {
      final events = _bandEventsMap[bandId] ?? [];
      for (final event in events) {
        final start = DateTime.tryParse(event.startDateTime)?.toLocal();
        final end = DateTime.tryParse(event.endDateTime)?.toLocal() ?? start;
        if (start == null) continue;

        final isEventUpcoming = end != null ? end.isAfter(now) : start.isAfter(now);

        bool matchesTab = false;
        switch (tabType) {
          case EventTabType.newEvents:
            matchesTab = isEventUpcoming && event.requireResponse && !event.isLocked;
            break;
          case EventTabType.upcoming:
            matchesTab = isEventUpcoming && (!event.requireResponse || event.isLocked);
            break;
          case EventTabType.past:
            matchesTab = !isEventUpcoming;
            break;
        }

        if (matchesTab) {
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final titleMatch = event.title.toLowerCase().contains(q);
            final descMatch = event.description.toLowerCase().contains(q);
            final locMatch = event.location.toLowerCase().contains(q);
            final typeMatch = event.eventType.toLowerCase().contains(q);
            final bandName = (_userBands[bandId] ?? '').toLowerCase();
            final bandMatch = bandName.contains(q);

            if (!titleMatch && !descMatch && !locMatch && !typeMatch && !bandMatch) {
              continue;
            }
          }
          result.add(MapEntry(bandId, event));
        }
      }
    }

    // Sort: newEvents & upcoming ascending (closest first), past descending (most recent past first)
    result.sort((a, b) {
      final aDate = a.value.parsedStartDateTime;
      final bDate = b.value.parsedStartDateTime;
      return tabType == EventTabType.past ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });

    return result;
  }

  Future<void> _confirmDeleteEvent(String bandId, BandEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141029),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E)),
        ),
        title: Text(
          'Delete Event',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${event.title}"? This action cannot be undone and will remove all RSVPs.',
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final appState = Provider.of<AppState>(context, listen: false);
        if (event.id != null) {
          await appState.firebaseService.deleteBandEventAsync(bandId, event.id!);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Event deleted successfully.'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete event: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          // Page Header Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.event_note_rounded, color: AppTheme.primaryAccent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'EVENTS',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],

            // Search & Filter Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0C20),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF231F45), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search events by name, location, or type...',
                      hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primaryAccent, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: AppTheme.textSecondary, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFF141029),
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
                    onChanged: (val) {
                      setState(() => _searchQuery = val.trim());
                    },
                  ),
                  const SizedBox(height: 10),

                  // Tabs: New Events, Upcoming & Past
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primaryAccent,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.textSecondary,
                    labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: '1. NEW EVENTS (Needs RSVP)'),
                      Tab(text: '2. UPCOMING (Finalized)'),
                      Tab(text: '3. PAST EVENTS'),
                    ],
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : _userBands.isEmpty
                      ? _buildNoBandsView(context, appState)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildEventListView(tabType: EventTabType.newEvents),
                            _buildEventListView(tabType: EventTabType.upcoming),
                            _buildEventListView(tabType: EventTabType.past),
                          ],
                        ),
            ),
          ],
        );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: content,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppTheme.primaryAccent,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(
            'Create Event',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          onPressed: () => GlobalCreateEventLauncher.handleCreateBandEvent(context, appState),
        ),
      );
    }

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Events',
        showBack: true,
      ),
      body: SafeArea(
        child: content,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryAccent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Create Event',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        onPressed: () => GlobalCreateEventLauncher.handleCreateBandEvent(context, appState),
      ),
    );
  }

  Widget _buildNoBandsView(BuildContext context, AppState appState) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryAccent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 56,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Bands Found',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You need to be part of a band to create and manage band events.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Create a Band',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              onPressed: () => Navigator.pushNamed(context, '/create-band'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventListView({required EventTabType tabType}) {
    final eventEntries = _getFilteredEvents(tabType: tabType);

    if (eventEntries.isEmpty) {
      IconData emptyIcon;
      String emptyTitle;
      String emptyMessage;

      switch (tabType) {
        case EventTabType.newEvents:
          emptyIcon = Icons.mark_email_unread_outlined;
          emptyTitle = 'No New Events';
          emptyMessage = 'You have no events waiting for RSVP.';
          break;
        case EventTabType.upcoming:
          emptyIcon = Icons.event_available_outlined;
          emptyTitle = 'No Upcoming Events';
          emptyMessage = 'You have no finalized upcoming events scheduled for the selected band(s).';
          break;
        case EventTabType.past:
          emptyIcon = Icons.history_rounded;
          emptyTitle = 'No Past Events';
          emptyMessage = 'No past event history found.';
          break;
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                emptyIcon,
                size: 56,
                color: AppTheme.textSecondary.withOpacity(0.6),
              ),
              const SizedBox(height: 14),
              Text(
                emptyTitle,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No events match "$_searchQuery".'
                    : emptyMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: eventEntries.length,
      itemBuilder: (context, index) {
        final entry = eventEntries[index];
        final bandId = entry.key;
        final event = entry.value;
        final bandName = _userBands[bandId] ?? 'Band';
        final isAuthorized = _isLeaderOrAdmin(bandId);

        return _buildEventCard(
          context: context,
          bandId: bandId,
          bandName: bandName,
          event: event,
          isAuthorized: isAuthorized,
          tabType: tabType,
        );
      },
    );
  }

  Widget _buildEventCard({
    required BuildContext context,
    required String bandId,
    required String bandName,
    required BandEvent event,
    required bool isAuthorized,
    required EventTabType tabType,
  }) {
    final String timeOrDateStr = formatBandEventDateRange(event);

    final sessionType = event.eventType.isNotEmpty ? event.eventType : 'Event';
    final iconData = _getEventTypeIcon(sessionType);

    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    final isCreator = currentUserId != null && currentUserId == event.createdBy;
    final canEdit = isCreator;
    final canDelete = isCreator || isAuthorized;

    void openEvent() {
      if (event.id != null) {
        if (event.isLocked || tabType == EventTabType.past) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventResultsPage(
                bandId: bandId,
                eventId: event.id!,
                initialEvent: event,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailsPage(
                bandId: bandId,
                eventId: event.id!,
                initialEvent: event,
                isFromNewEvents: tabType == EventTabType.newEvents,
              ),
            ),
          );
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: openEvent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row with Type, Band Name & Options
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(iconData, color: AppTheme.primaryAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bandName,
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '”${event.title}”',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryAccent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sessionType.isNotEmpty && sessionType.toLowerCase() != 'event') ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                sessionType,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: AppTheme.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canEdit || canDelete)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                        color: const Color(0xFF1A1635),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (action) {
                          if (action == 'edit') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateEventPage(
                                  bandId: bandId,
                                  existingEvent: event,
                                ),
                              ),
                            );
                          } else if (action == 'delete') {
                            _confirmDeleteEvent(bandId, event);
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (canEdit)
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined, color: AppTheme.primaryAccent, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Edit Event', style: GoogleFonts.inter(color: Colors.white)),
                                ],
                              ),
                            ),
                          if (canDelete)
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Delete Event', style: GoogleFonts.inter(color: AppTheme.danger)),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              // Date & Location Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            timeOrDateStr,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (event.location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.location,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_rounded, color: AppTheme.textSecondary, size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.description,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF231F45)),

              // Bottom Action Bar: Only RSVPs and Event Details buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.analytics_outlined, size: 15),
                      label: Text(
                        'RSVPs',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        if (event.id != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventResultsPage(
                                bandId: bandId,
                                eventId: event.id!,
                                initialEvent: event,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (event.id != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventDetailsPage(
                                bandId: bandId,
                                eventId: event.id!,
                                initialEvent: event,
                                isFromNewEvents: tabType == EventTabType.newEvents,
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'Event Details',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
