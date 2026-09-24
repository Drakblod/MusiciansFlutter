import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band_event.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import 'event_details_page.dart';
import 'event_results_page.dart';
import 'create_event_page.dart';
import '../controllers/global_create_event_launcher.dart';

class ManageEventsScreen extends StatefulWidget {
  final String? initialBandId;

  const ManageEventsScreen({
    super.key,
    this.initialBandId,
  });

  @override
  State<ManageEventsScreen> createState() => _ManageEventsScreenState();
}

class _ManageEventsScreenState extends State<ManageEventsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  Map<String, String> _userBands = {};
  Map<String, String> _userRoles = {}; // bandId -> role
  String? _selectedBandId; // null means 'All Bands'
  bool _isLoading = true;
  String _searchQuery = '';

  // All loaded events: bandId -> List<BandEvent>
  final Map<String, List<BandEvent>> _bandEventsMap = {};
  final List<StreamSubscription<List<BandEvent>>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedBandId = widget.initialBandId;
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
          if (_selectedBandId != null && !bands.containsKey(_selectedBandId)) {
            _selectedBandId = null;
          } else if (_selectedBandId == null && appState.activeBandId != null && bands.containsKey(appState.activeBandId)) {
            _selectedBandId = appState.activeBandId;
          }
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

  List<MapEntry<String, BandEvent>> _getFilteredEvents({required bool isUpcoming}) {
    final now = DateTime.now();
    final List<MapEntry<String, BandEvent>> result = [];

    final targetBands = _selectedBandId != null
        ? {_selectedBandId!: _userBands[_selectedBandId] ?? ''}
        : _userBands;

    for (final bandId in targetBands.keys) {
      final events = _bandEventsMap[bandId] ?? [];
      for (final event in events) {
        final start = DateTime.tryParse(event.startDateTime)?.toLocal();
        final end = DateTime.tryParse(event.endDateTime)?.toLocal() ?? start;
        if (start == null) continue;

        final isEventUpcoming = end != null ? end.isAfter(now) : start.isAfter(now);

        if (isUpcoming == isEventUpcoming) {
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

    // Sort: upcoming ascending (closest first), past descending (most recent past first)
    result.sort((a, b) {
      final aDate = DateTime.tryParse(a.value.startDateTime)?.toLocal() ?? DateTime.now();
      final bDate = DateTime.tryParse(b.value.startDateTime)?.toLocal() ?? DateTime.now();
      return isUpcoming ? aDate.compareTo(bDate) : bDate.compareTo(aDate);
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

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Events',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  // Band Selector Chips (if user has bands)
                  if (_userBands.isNotEmpty) ...[
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: Text(
                              'All Bands (${_userBands.length})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _selectedBandId == null ? FontWeight.bold : FontWeight.normal,
                                color: _selectedBandId == null ? Colors.white : AppTheme.textSecondary,
                              ),
                            ),
                            selected: _selectedBandId == null,
                            selectedColor: AppTheme.primaryAccent,
                            backgroundColor: const Color(0xFF16132D),
                            side: BorderSide(
                              color: _selectedBandId == null ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedBandId = null);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ..._userBands.entries.map((entry) {
                            final isSelected = _selectedBandId == entry.key;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  entry.value,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryAccent,
                                backgroundColor: const Color(0xFF16132D),
                                side: BorderSide(
                                  color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                                ),
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedBandId = selected ? entry.key : null;
                                  });
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

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

                  // Tabs: Upcoming & Past
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.primaryAccent,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.textSecondary,
                    labelStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'UPCOMING'),
                      Tab(text: 'PAST EVENTS'),
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
                            _buildEventListView(isUpcoming: true),
                            _buildEventListView(isUpcoming: false),
                          ],
                        ),
            ),
          ],
        ),
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

  Widget _buildEventListView({required bool isUpcoming}) {
    final eventEntries = _getFilteredEvents(isUpcoming: isUpcoming);

    if (eventEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUpcoming ? Icons.event_available_outlined : Icons.history_rounded,
                size: 56,
                color: AppTheme.textSecondary.withOpacity(0.6),
              ),
              const SizedBox(height: 14),
              Text(
                isUpcoming ? 'No Upcoming Events' : 'No Past Events',
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
                    : isUpcoming
                        ? 'You have no upcoming events scheduled for the selected band(s).'
                        : 'No past event history found.',
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
          isUpcoming: isUpcoming,
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
    required bool isUpcoming,
  }) {
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? startLocal;

    final isSameDay = startLocal.year == endLocal.year &&
        startLocal.month == endLocal.month &&
        startLocal.day == endLocal.day;

    final String timeOrDateStr = isSameDay
        ? '${DateFormat('EEEE, MMM d, yyyy').format(startLocal)} • ${DateFormat('HH:mm').format(startLocal)} - ${DateFormat('HH:mm').format(endLocal)}'
        : '${DateFormat('MMM d, yyyy').format(startLocal)} – ${DateFormat('MMM d, yyyy').format(endLocal)}';

    // Count responses
    int yesCount = 0;
    int noCount = 0;
    int maybeCount = 0;
    for (final r in event.responses.values) {
      final s = r.status.toLowerCase();
      if (s == 'yes' || s == 'attending') {
        yesCount++;
      } else if (s == 'no' || s == 'declined') {
        noCount++;
      } else if (s == 'uncertain' || s == 'maybe') {
        maybeCount++;
      }
    }

    final sessionType = event.eventType.isNotEmpty ? event.eventType : 'Event';
    final iconData = _getEventTypeIcon(sessionType);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
      ),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sessionType,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              bandName,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.title,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAuthorized)
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
                    const Icon(Icons.access_time_rounded, color: AppTheme.textSecondary, size: 15),
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
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (event.rehearsals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.layers_outlined, size: 13, color: AppTheme.primaryAccent),
                            const SizedBox(width: 4),
                            Text(
                              '${event.rehearsals.length} Session${event.rehearsals.length == 1 ? '' : 's'} attached',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                            ),
                          ],
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

          // Bottom Stats & Action Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // RSVP Attendance Summary
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check, color: AppTheme.success, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            '$yesCount Yes',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (noCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.close, color: AppTheme.danger, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              '$noCount No',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.danger,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (maybeCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.help_outline, color: AppTheme.warning, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              '$maybeCount ?',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // Details Button
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
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
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'View Event',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
