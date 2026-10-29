import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../utils/sub_request_card_helper.dart';

class SubRequestResponsesScreen extends StatefulWidget {
  final String bandId;

  const SubRequestResponsesScreen({
    super.key,
    required this.bandId,
  });

  @override
  State<SubRequestResponsesScreen> createState() => _SubRequestResponsesScreenState();
}

class _SubRequestResponsesScreenState extends State<SubRequestResponsesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SubRequest> _substituteRequests = [];
  List<SubRequest> _memberRequests = [];
  Map<String, int> _responseCounts = {};
  Map<String, int> _viewedResponseCounts = {};
  bool _isBandAdmin = false;
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
      final list = await appState.firebaseService.getUserSubRequestsAsync(userId);
      final seenIds = list.map((r) => r.subRequestId ?? r.id ?? '').where((id) => id.isNotEmpty).toSet();

      // If a specific bandId is requested and the current user is an admin/leader of that band,
      // also include open requests belonging to that band so band admins can manage requests created by co-leaders.
      if (widget.bandId.isNotEmpty && widget.bandId != 'all') {
        try {
          final isBandAdmin = await appState.firebaseService.isBandLeaderOrAdminAsync(widget.bandId, userId);
          _isBandAdmin = isBandAdmin;
          if (isBandAdmin) {
            final allRequests = await appState.firebaseService.getAllSubRequestsAsync();
            for (final req in allRequests) {
              final reqId = req.subRequestId ?? req.id ?? '';
              if (reqId.isEmpty || seenIds.contains(reqId)) continue;
              final matchesBand = (req.bandId != null && req.bandId == widget.bandId) ||
                  (req.bandName != null &&
                      (req.bandName!.replaceAll(' ', '_') == widget.bandId || req.bandName == widget.bandId));
              if (matchesBand) {
                seenIds.add(reqId);
                list.add(req);
              }
            }
          }
        } catch (_) {}
      }
      
      // 2. Filter requests matching the selected band (or show all if bandId is empty or 'all')
      final bandRequests = (widget.bandId.isEmpty || widget.bandId == 'all')
          ? list
          : list.where((req) {
              if (req.bandId != null && req.bandId == widget.bandId) return true;
              if (req.bandName == null) return false;
              final cleanBandName = req.bandName!.replaceAll(' ', '_');
              return cleanBandName == widget.bandId || req.bandName == widget.bandId;
            }).toList();

      // 3. Concurrently fetch responses count for each request
      final Map<String, int> counts = {};
      await Future.wait(bandRequests.map((req) async {
        final reqId = req.subRequestId ?? req.id;
        if (reqId != null) {
          final count = await appState.firebaseService.getSubRequestResponseCountAsync(reqId);
          counts[reqId] = count;
        }
      }));

      // 4. Categorize requests
      final List<SubRequest> subs = [];
      final List<SubRequest> members = [];
      for (final req in bandRequests) {
        if (req.role == 'Substitute') {
          subs.add(req);
        } else if (req.role == 'Member' || req.role == 'New Member') {
          members.add(req);
        } else {
          // Default fallback
          subs.add(req);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final Map<String, int> viewedMap = {};
      for (final req in bandRequests) {
        final reqId = req.subRequestId ?? req.id;
        if (reqId != null) {
          viewedMap[reqId] = prefs.getInt('viewed_resp_$reqId') ?? 0;
        }
      }

      setState(() {
        _substituteRequests = subs;
        _memberRequests = members;
        _responseCounts = counts;
        _viewedResponseCounts = viewedMap;
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
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Yes', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      final requestId = request.subRequestId ?? request.id;
      
      if (userId != null && requestId != null) {
        final success = await appState.firebaseService.deleteSubRequestAsync(userId, requestId);
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



  bool _requestHasActivity(SubRequest req) {
    final reqId = req.subRequestId ?? req.id ?? '';
    final count = _responseCounts[reqId] ?? 0;
    final viewed = _viewedResponseCounts[reqId] ?? 0;
    return count > 0 && count > viewed;
  }

  bool get _hasSubstituteActivity => _substituteRequests.any(_requestHasActivity);
  bool get _hasMemberActivity => _memberRequests.any(_requestHasActivity);

  Future<void> _openRequestDetails(SubRequest req) async {
    final reqId = req.subRequestId ?? req.id;
    if (reqId != null) {
      final currentCount = _responseCounts[reqId] ?? 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('viewed_resp_$reqId', currentCount);
      if (mounted) {
        setState(() {
          _viewedResponseCounts[reqId] = currentCount;
        });
      }

      // Mark matching unread response notifications as read
      if (!mounted) return;
      try {
        final appState = Provider.of<AppState>(context, listen: false);
        for (final notif in appState.userNotifications) {
          if (!notif.isRead &&
              (notif.type == 'sub_request_response' || notif.type == 'sub_response') &&
              (notif.data['subRequestId'] == reqId || notif.id.contains(reqId))) {
            appState.firebaseService.markNotificationReadAsync(notif.id);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      '/sub-request-response-details',
      arguments: {'subRequest': req},
    );
    await _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Active Requests',
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
                    Expanded(
                      child: Text(
                        'Manage Requests',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
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
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('1. Substitutes'),
                          if (_hasSubstituteActivity) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE11D48),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('2. Members'),
                          if (_hasMemberActivity) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE11D48),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
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
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemBuilder: (context, index) {
          final req = list[index];
          final reqId = req.subRequestId ?? req.id ?? '';
          final responseCount = _responseCounts[reqId] ?? 0;
          final appState = Provider.of<AppState>(context, listen: false);
          final currentUserId = appState.currentUserId;
          final presentation = SubRequestCardPresentation.fromSubRequest(
            req,
            currentUserId: currentUserId,
            isBandAdmin: _isBandAdmin,
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF231F45), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Band / Project
                Text(
                  presentation.bandName,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // 2. Request Type + Role / Instrument
                Text(
                  '${presentation.requestType} · ${presentation.roleInstrument}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: presentation.requestType == 'New Band Member'
                        ? AppTheme.primaryAccent
                        : const Color(0xFF90CAF9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // 3. Event Type + Paid status/payment amount
                if (presentation.eventTypeAndPaymentLine != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    presentation.eventTypeAndPaymentLine!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: presentation.isPaid ? AppTheme.primaryAccent : Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // 4. Weekday, date and time
                if (presentation.formattedDateTime != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    presentation.formattedDateTime!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Location / Venue when available
                if (presentation.locationVenue != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          presentation.locationVenue!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // 5. Contextual action: View Responses + Secondary Delete action
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: ValueKey('view_responses_$reqId'),
                        onTap: () => _openRequestDetails(req),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    'View Responses ($responseCount)',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (_requestHasActivity(req)) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE11D48),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: ValueKey('delete_request_$reqId'),
                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                      tooltip: 'Delete request',
                      onPressed: () => _deleteRequest(req),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
