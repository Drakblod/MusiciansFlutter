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

class FindGigsScreen extends StatefulWidget {
  const FindGigsScreen({super.key});

  @override
  State<FindGigsScreen> createState() => _FindGigsScreenState();
}

class _FindGigsScreenState extends State<FindGigsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _savedGigIds = {};
  List<SubRequest> _liveGigs = [];
  bool _isLoading = true;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();
    _loadSubRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSubRequests() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final list = await appState.firebaseService.getAllSubRequestsAsync();
      
      final userProfile = appState.currentUserProfile;
      final userInstruments = userProfile?.instruments ?? [];

      final filtered = list.where((gig) {
        // 1. Filter out corrupt / un-named / empty gigs
        if (gig.bandName == null || gig.bandName!.trim().isEmpty) return false;
        if (gig.voicePart == null || gig.voicePart!.trim().isEmpty) return false;
        if (gig.date == null || gig.date!.trim().isEmpty) return false;

        // 2. Filter out past gigs
        final gigDate = DateTime.tryParse(gig.date!);
        if (gigDate == null) return false;
        
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (gigDate.isBefore(today)) return false;

        // 3. Filter by user instruments (with fallback to show all if profile instruments are empty)
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

      setState(() {
        _liveGigs = filtered;
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

  DateTime _getGigDate(SubRequest req) {
    if (req.date == null) return DateTime.now();
    return DateTime.tryParse(req.date!) ?? DateTime.now();
  }

  void _showGigDetailsBottomSheet(SubRequest gig) {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    final hasApplied = currentUserId != null && gig.responses.containsKey(currentUserId);
    final date = _getGigDate(gig);

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
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30,
              ),
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
                          gig.role ?? gig.voicePart ?? 'Substitute Request',
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
                          color: gig.isPaid
                              ? AppTheme.primaryAccent.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          gig.isPaid ? 'Paid' : 'Unpaid',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: gig.isPaid ? AppTheme.primaryAccent : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    gig.bandName ?? 'Unknown Band',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppTheme.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Location details
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gig.location ?? 'Stockholm, Sweden',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Time details
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${DateFormat('EEEE, MMMM d, yyyy').format(date)} | ${gig.startTime ?? "18:00"} - ${gig.endTime ?? "21:00"}',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Description
                  Text(
                    'About this Request',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    gig.description ?? 'No description provided for this request.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Apply Button
                  hasApplied
                      ? Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Center(
                            child: Text(
                              'Applied',
                              style: TextStyle(
                                color: Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      : AnimatedTapDetector(
                          onTap: () async {
                            if (currentUserId == null) return;
                            try {
                              await appState.firebaseService.addResponseToSubRequestAsync(
                                gig.subRequestId ?? gig.id!,
                                currentUserId,
                              );
                              // Refresh live list
                              await _loadSubRequests();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Successfully applied for gig!'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to apply: $e'),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Apply for Gig',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
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
          // Header / Title row
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
                const Icon(Icons.filter_list_rounded, color: Colors.white, size: 24),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.primaryAccent,
            labelColor: Colors.white,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(text: 'Upcoming'),
              Tab(text: 'Saved'),
            ],
          ),
          const SizedBox(height: 16),

          // Tab Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGigsList(_liveGigs),
                      _buildGigsList(
                        _liveGigs.where((g) => _savedGigIds.contains(g.id ?? g.subRequestId)).toList(),
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

  Widget _buildGigsList(List<SubRequest> gigList) {
    if (gigList.isEmpty) {
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
        itemCount: gigList.length,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemBuilder: (context, index) {
          final gig = gigList[index];
          final id = gig.id ?? gig.subRequestId ?? index.toString();
          final isSaved = _savedGigIds.contains(id);
          final date = _getGigDate(gig);

          return GestureDetector(
            onTap: () => _showGigDetailsBottomSheet(gig),
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
                              child: Text(
                                gig.role ?? gig.voicePart ?? 'Substitute Request',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
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
                        Text(
                          gig.bandName ?? 'Unknown Band',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          gig.location ?? 'Stockholm, Sweden',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (gig.description != null && gig.description!.isNotEmpty)
                          Text(
                            gig.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Tags row
                        Row(
                          children: [
                            // Paid / Unpaid tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: gig.isPaid
                                    ? AppTheme.primaryAccent.withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                gig.isPaid ? 'Paid' : 'Unpaid',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: gig.isPaid
                                      ? AppTheme.primaryAccent
                                      : AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Genre Tag / VoicePart tag
                            if (gig.style != null || gig.voicePart != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1A3A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  gig.style ?? gig.voicePart ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppTheme.secondaryAccent,
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
            ),
          );
        },
      ),
    );
  }
}
