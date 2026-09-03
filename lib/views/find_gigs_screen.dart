import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../config/feature_toggles.dart';

class GigGroup {
  final String groupId;
  final String title;
  final String? bandName;
  final String? location;
  final String? description;
  final String? payDetails;
  final bool isMultiple;
  final List<SubRequest> requests;
  final DateTime earliestDate;

  GigGroup({
    required this.groupId,
    required this.title,
    this.bandName,
    this.location,
    this.description,
    this.payDetails,
    required this.isMultiple,
    required this.requests,
    required this.earliestDate,
  });

  int get totalPositions => requests.length;
  int get filledPositions => requests.where((r) => r.status == 'assigned' || r.assignedUserId != null).length;
  int get eventCount {
    final eventIds = requests.map((r) => r.eventId ?? r.date ?? '').toSet();
    return eventIds.length;
  }

  String get formattedPayment {
    final paidReq = requests.firstWhere((r) => r.isPaid, orElse: () => requests.first);
    return paidReq.formattedPayAmount;
  }
}

class FindGigsScreen extends StatefulWidget {
  const FindGigsScreen({super.key});

  @override
  State<FindGigsScreen> createState() => _FindGigsScreenState();
}

class _FindGigsScreenState extends State<FindGigsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _savedGigIds = {};
  List<GigGroup> _liveGigGroups = [];
  List<GigGroup> _inviteGigGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    _tabController = TabController(length: 3, vsync: this);
    super.initState();
    _loadSubRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<GigGroup> _groupSubRequests(List<SubRequest> rawList) {
    final Map<String, List<SubRequest>> groupsMap = {};
    for (final req in rawList) {
      final key = (req.requestGroupId != null && req.requestGroupId!.isNotEmpty)
          ? req.requestGroupId!
          : (req.subRequestId ?? req.id ?? 'single_${rawList.indexOf(req)}');
      groupsMap.putIfAbsent(key, () => []).add(req);
    }

    final List<GigGroup> groups = [];
    for (final entry in groupsMap.entries) {
      final reqs = entry.value;
      reqs.sort((a, b) {
        final seqA = a.eventSequence ?? 0;
        final seqB = b.eventSequence ?? 0;
        if (seqA != seqB) return seqA.compareTo(seqB);
        final dateA = DateTime.tryParse(a.date ?? '') ?? DateTime(3000);
        final dateB = DateTime.tryParse(b.date ?? '') ?? DateTime(3000);
        return dateA.compareTo(dateB);
      });

      final first = reqs.first;
      final isMulti = reqs.length > 1 || (first.requestGroupId != null && first.requestGroupId!.isNotEmpty);
      final groupTitle = first.bandName ?? first.eventTitle ?? first.role ?? 'Substitute Request';

      DateTime earliest = DateTime(3000);
      for (final r in reqs) {
        if (r.date != null) {
          final d = DateTime.tryParse(r.date!);
          if (d != null && d.isBefore(earliest)) earliest = d;
        }
      }
      if (earliest == DateTime(3000)) earliest = DateTime.now();

      final firstWithPayDetails = reqs.firstWhere(
        (r) => r.payDetails != null && r.payDetails!.trim().isNotEmpty,
        orElse: () => first,
      );

      groups.add(
        GigGroup(
          groupId: entry.key,
          title: groupTitle,
          bandName: first.bandName,
          location: first.location,
          description: first.description,
          payDetails: firstWithPayDetails.payDetails,
          isMultiple: isMulti,
          requests: reqs,
          earliestDate: earliest,
        ),
      );
    }

    groups.sort((a, b) => a.earliestDate.compareTo(b.earliestDate));
    return groups;
  }

  Future<void> _loadSubRequests() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final list = await appState.firebaseService.getUserSubRequestFeedAsync();
      final currentUserId = appState.currentUserId;

      final userProfile = appState.currentUserProfile;
      final userInstruments = userProfile?.instruments ?? [];

      final filteredUpcoming = list.where((gig) {
        if (gig.bandName == null || gig.bandName!.trim().isEmpty) return false;
        if (gig.voicePart == null || gig.voicePart!.trim().isEmpty) return false;
        if (gig.date == null || gig.date!.trim().isEmpty) return false;

        final gigDate = DateTime.tryParse(gig.date!);
        if (gigDate == null) return false;

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (gigDate.isBefore(today)) return false;

        if (userInstruments.isEmpty) return true;

        final voicePartLower = gig.voicePart!.toLowerCase();
        final matches = userInstruments.any((inst) {
          final instLower = inst.toLowerCase();
          return instLower == voicePartLower ||
              voicePartLower.contains(instLower) ||
              instLower.contains(voicePartLower);
        });
        return matches;
      }).toList();

      final filteredInvites = list.where((gig) {
        if (gig.bandName == null || gig.bandName!.trim().isEmpty) return false;
        if (gig.date == null || gig.date!.trim().isEmpty) return false;

        final gigDate = DateTime.tryParse(gig.date!);
        if (gigDate == null) return false;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (gigDate.isBefore(today)) return false;

        final targets = gig.targetUserIds;
        return targets != null && currentUserId != null && targets.contains(currentUserId);
      }).toList();

      setState(() {
        _liveGigGroups = _groupSubRequests(filteredUpcoming);
        _inviteGigGroups = _groupSubRequests(filteredInvites);
      });
    } catch (e) {
      debugPrint("Error fetching sub requests: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _toggleSaveGig(String id) {
    setState(() {
      if (_savedGigIds.contains(id)) {
        _savedGigIds.remove(id);
      } else {
        _savedGigIds.add(id);
      }
    });
  }

  void _showGigDetailsBottomSheet(GigGroup group) {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundEnd,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final distinctEventTitles = group.requests
                .map((r) => r.eventTitle?.trim())
                .where((t) => t != null && t.isNotEmpty)
                .cast<String>()
                .toSet();
            final bool hasMultipleDistinctEvents = distinctEventTitles.length > 1;
            final String? singleEventTitle = distinctEventTitles.length == 1
                ? distinctEventTitles.first
                : (distinctEventTitles.isEmpty
                    ? (group.requests.isNotEmpty && group.requests.first.eventTitle?.trim().isNotEmpty == true
                        ? group.requests.first.eventTitle!.trim()
                        : null)
                    : null);

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 30,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 50,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              group.title,
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              group.formattedPayment,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (group.bandName != null) ...[
                        Text(
                          group.bandName!,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Event name (for single event requests or groups where all slots share one event)
                      if (!hasMultipleDistinctEvents && singleEventTitle != null && singleEventTitle.isNotEmpty) ...[
                        Text(
                          'Event name',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          singleEventTitle,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Summary info
                      Row(
                        children: [
                          if (group.isMultiple) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.secondaryAccent.withOpacity(0.5)),
                              ),
                              child: Text(
                                'Multiple Request',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryAccent),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${group.eventCount} events · ${group.totalPositions} positions (${group.filledPositions} filled)',
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Location details
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              group.location ?? 'Stockholm, Sweden',
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Paid Gig Details
                      if (group.payDetails != null && group.payDetails!.trim().isNotEmpty) ...[
                        Text(
                          'Details',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          group.payDetails!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Description
                      if (group.description != null && group.description!.isNotEmpty) ...[
                        Text(
                          'Description',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          group.description!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Positions List
                      Text(
                        'Substitute Positions (${group.requests.length})',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),

                      ...group.requests.map((req) {
                        final reqId = req.subRequestId ?? req.id ?? '';
                        final hasApplied = currentUserId != null && req.responses.containsKey(currentUserId);
                        final isAssigned = req.status == 'assigned' || req.assignedUserId != null;
                        final dateStr = req.date != null
                            ? DateFormat('EEE, MMM d').format(DateTime.tryParse(req.date!) ?? DateTime.now())
                            : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A3A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF2E2A4E)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (req.eventSequence != null)
                                          Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryAccent.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Event #${req.eventSequence}',
                                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                                            ),
                                          ),
                                        Text(
                                          req.voicePart ?? 'Musician',
                                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$dateStr · ${req.startTime ?? "18:00"} - ${req.endTime ?? "21:00"}',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                    if (req.replacedMemberName != null)
                                      Text(
                                        'Replacing: ${req.replacedMemberName}',
                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                                      ),
                                    if (hasMultipleDistinctEvents && req.eventTitle != null && req.eventTitle!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Event name',
                                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        req.eventTitle!.trim(),
                                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isAssigned)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Filled', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                                )
                              else if (hasApplied)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Applied', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                                )
                              else
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  onPressed: () async {
                                    if (currentUserId == null) return;
                                    try {
                                      await appState.firebaseService.addResponseToSubRequestAsync(
                                        reqId,
                                        currentUserId,
                                      );
                                      await _loadSubRequests();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Applied for position!'), backgroundColor: AppTheme.success),
                                        );
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to apply: $e'), backgroundColor: AppTheme.danger),
                                        );
                                      }
                                    }
                                  },
                                  child: Text('Apply', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find Gigs',
        showBack: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Find Gigs',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        if (!FeatureToggles.showMapInTopBar) ...[
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/gig-map');
                            },
                            icon: const Icon(Icons.map_rounded, color: AppTheme.primaryAccent, size: 18),
                            label: Text(
                              'Map View',
                              style: GoogleFonts.inter(
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              backgroundColor: AppTheme.primaryAccent.withOpacity(0.12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.3)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        const Icon(Icons.filter_list_rounded, color: Colors.white, size: 24),
                      ],
                    ),
                  ],
                ),
              ),

              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primaryAccent,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(text: 'Upcoming'),
                  Tab(text: 'Invites'),
                  Tab(text: 'Saved'),
                ],
              ),
              const SizedBox(height: 16),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildGigsList(_liveGigGroups),
                          _buildGigsList(_inviteGigGroups),
                          _buildGigsList(
                            _liveGigGroups.where((g) => _savedGigIds.contains(g.groupId)).toList(),
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

  Widget _buildGigsList(List<GigGroup> groupList) {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;

    if (groupList.isEmpty) {
      return Center(
        child: Text(
          'No gigs in this list.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryAccent,
      onRefresh: _loadSubRequests,
      child: ListView.builder(
        itemCount: groupList.length,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemBuilder: (context, index) {
          final group = groupList[index];
          final id = group.groupId;
          final isSaved = _savedGigIds.contains(id);
          final date = group.earliestDate;

          final hasDirectInvite = group.requests.any(
            (r) => r.targetUserIds != null && currentUserId != null && r.targetUserIds!.contains(currentUserId),
          );

          return GestureDetector(
            onTap: () => _showGigDetailsBottomSheet(group),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF231F45), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date badge container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('MMM').format(date).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('dd').format(date),
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Gig Information
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (group.isMultiple) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondaryAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.secondaryAccent.withOpacity(0.6)),
                                      ),
                                      child: Text(
                                        'Multiple Request',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.secondaryAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    group.title,
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Bookmark icon button
                            GestureDetector(
                              onTap: () => _toggleSaveGig(id),
                              child: Icon(
                                isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                color: isSaved ? AppTheme.primaryAccent : Colors.white,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (group.bandName != null && group.bandName != group.title) ...[
                          Text(
                            group.bandName!,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          group.location ?? 'Stockholm, Sweden',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (group.isMultiple) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${group.eventCount} event${group.eventCount == 1 ? "" : "s"} · ${group.totalPositions} substitute position${group.totalPositions == 1 ? "" : "s"}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            '${group.filledPositions} of ${group.totalPositions} positions filled',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: group.filledPositions == group.totalPositions ? AppTheme.success : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Tags row
                        Row(
                          children: [
                            // Paid / Payment tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                group.formattedPayment,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: AppTheme.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Roles tag summary
                            if (!group.isMultiple && group.requests.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1A3A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  group.requests.first.voicePart ?? 'Musician',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppTheme.secondaryAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                            // Direct Invite Tag
                            if (hasDirectInvite) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Direct Invite',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
