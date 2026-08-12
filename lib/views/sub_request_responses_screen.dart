import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class SubRequestResponsesScreen extends StatefulWidget {
  final String bandId;

  const SubRequestResponsesScreen({super.key, required this.bandId});

  @override
  State<SubRequestResponsesScreen> createState() =>
      _SubRequestResponsesScreenState();
}

class _SubRequestResponsesScreenState extends State<SubRequestResponsesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SubRequest> _substituteRequests = [];
  List<SubRequest> _memberRequests = [];
  Map<String, int> _responseCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      if (userId == null) return;

      // 1. Fetch user's sub requests
      final list = await appState.firebaseService.getUserSubRequestsAsync(
        userId,
      );

      // 2. Filter requests matching the selected band
      final bandRequests = list.where((req) {
        if (req.bandName == null) return false;
        final cleanBandName = req.bandName!.replaceAll(' ', '_');
        return cleanBandName == widget.bandId;
      }).toList();

      // 3. Concurrently fetch responses count for each request
      final Map<String, int> counts = {};
      await Future.wait(
        bandRequests.map((req) async {
          final reqId = req.subRequestId ?? req.id;
          if (reqId != null) {
            final count = await appState.firebaseService
                .getSubRequestResponseCountAsync(reqId);
            counts[reqId] = count;
          }
        }),
      );

      // 4. Categorize requests
      final List<SubRequest> subs = [];
      final List<SubRequest> members = [];
      for (final req in bandRequests) {
        if (req.role == 'Substitute') {
          subs.add(req);
        } else if (req.role == 'Member') {
          members.add(req);
        } else {
          // Default fallback
          subs.add(req);
        }
      }

      setState(() {
        _substituteRequests = subs;
        _memberRequests = members;
        _responseCounts = counts;
      });
    } catch (e) {
      debugPrint("Error loading sub requests: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load requests: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRequest(SubRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        title: Text(
          'Confirm Delete',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this request?',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.inter(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Yes', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      final requestId = request.subRequestId ?? request.id;

      if (userId != null && requestId != null) {
        final success = await appState.firebaseService.deleteSubRequestAsync(
          userId,
          requestId,
        );
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Request deleted successfully.'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
          await _loadRequests();
        } else {
          throw Exception("Delete operation returned false");
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  DateTime _getGigDate(SubRequest req) {
    if (req.date == null) return DateTime.now();
    return DateTime.tryParse(req.date!) ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(title: 'Active Requests', showBack: true),
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
                      'Manage Requests',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _loadRequests,
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primaryAccent,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Substitutes'),
                  Tab(text: 'Members'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRequestsList(_substituteRequests),
                          _buildRequestsList(_memberRequests),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsList(List<SubRequest> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No active requests found.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryAccent,
      onRefresh: _loadRequests,
      child: ListView.builder(
        itemCount: list.length,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemBuilder: (context, index) {
          final req = list[index];
          final reqId = req.subRequestId ?? req.id ?? '';
          final responseCount = _responseCounts[reqId] ?? 0;
          final date = _getGigDate(req);

          return Container(
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
                // Date badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.role ?? req.voicePart ?? 'Substitute Request',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        req.bandName ?? 'Unknown Band',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Location: ${req.location ?? "N/A"}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (req.startTime != null && req.endTime != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Time: ${req.startTime} - ${req.endTime}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedTapDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/sub-request-response-details',
                                  arguments: {'subRequest': req},
                                ).then(
                                  (_) => _loadRequests(),
                                ); // reload when returning
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    'View Responses ($responseCount)',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          AnimatedTapDetector(
                            onTap: () => _deleteRequest(req),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.danger.withOpacity(0.3),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'DELETE',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
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
        },
      ),
    );
  }
}
