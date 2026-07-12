import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band_event.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import 'find_sub_screen.dart';

class EventDetailsPage extends StatefulWidget {
  final String bandId;
  final String eventId;
  final BandEvent initialEvent;

  const EventDetailsPage({
    super.key,
    required this.bandId,
    required this.eventId,
    required this.initialEvent,
  });

  @override
  State<EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<EventDetailsPage> {
  BandEvent? _event;
  StreamSubscription<BandEvent?>? _eventSubscription;
  List<BandMember> _members = [];
  Map<String, UserProfile> _cachedProfiles = {};
  bool _isLoadingMembers = true;
  String? _currentUserRole;

  String? _localSelectedResponse;
  final _commentController = TextEditingController();
  bool _hasInitializedLocalResponse = false;
  bool _isSavingResponse = false;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _subscribeToEvent();
    _loadMembersAndProfiles();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _subscribeToEvent() {
    final appState = Provider.of<AppState>(context, listen: false);
    _eventSubscription = appState.firebaseService
        .subscribeToBandEvent(widget.bandId, widget.eventId)
        .listen((updatedEvent) {
      if (updatedEvent != null && mounted) {
        setState(() {
          _event = updatedEvent;
        });
      }
    });
  }

  Future<void> _loadMembersAndProfiles() async {
    if (!mounted) return;
    setState(() => _isLoadingMembers = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final members = await appState.firebaseService.getBandMembersAsync(widget.bandId);
      
      // Cache profiles in parallel
      final Map<String, UserProfile> profiles = {};
      await Future.wait(members.map((m) async {
        final userId = m.userId;
        if (userId != null) {
          final profile = await appState.firebaseService.getUserProfileAsync(userId);
          if (profile != null) {
            profiles[userId] = profile;
          }
        }
      }));

      // Cache external invitee profiles
      final extUserIds = _event?.externalInvitees.keys.toList() ?? [];
      await Future.wait(extUserIds.map((userId) async {
        if (!profiles.containsKey(userId)) {
          final profile = await appState.firebaseService.getUserProfileAsync(userId);
          if (profile != null) {
            profiles[userId] = profile;
          }
        }
      }));

      // Cache locker profile
      final lockedBy = _event?.lockedBy;
      if (lockedBy != null && !profiles.containsKey(lockedBy)) {
        final profile = await appState.firebaseService.getUserProfileAsync(lockedBy);
        if (profile != null) {
          profiles[lockedBy] = profile;
        }
      }

      // Determine current user's role
      final currentUserId = appState.currentUserId;
      final currentMember = members.firstWhere(
        (m) => m.userId == currentUserId,
        orElse: () => BandMember(role: 'Member'),
      );

      if (mounted) {
        setState(() {
          _members = members;
          _cachedProfiles = profiles;
          _currentUserRole = currentMember.role;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading event member profiles: $e");
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  bool get _isAdmin {
    return _currentUserRole == 'Leader' || _currentUserRole == 'Admin';
  }

  Widget _getEventIcon(String type) {
    String emoji = '📅';
    switch (type) {
      case 'Rehearsal':
        emoji = '🎼';
        break;
      case 'Concert':
        emoji = '🎺';
        break;
      case 'Gig':
        emoji = '🎸';
        break;
      case 'Recording Session':
        emoji = '🎙️';
        break;
      case 'Meeting':
        emoji = '👥';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryAccent.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 28),
      ),
    );
  }

  void _respond(String status, String comment) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;
    if (userId == null || _event == null) return;

    if (_event!.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This event is locked and responses can no longer be changed."),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSavingResponse = true);

    try {
      final isExternal = _event!.externalInvitees.containsKey(userId);
      final cleanComment = comment.trim().isEmpty ? null : comment.trim();

      if (isExternal) {
        await appState.firebaseService.updateExternalInviteeResponseAsync(
          widget.bandId,
          widget.eventId,
          userId,
          status,
          comment: cleanComment,
        );
      } else {
        await appState.firebaseService.updateEventResponseAsync(
          widget.bandId,
          widget.eventId,
          userId,
          status,
          comment: cleanComment,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("RSVP saved: ${status.toUpperCase()}"),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint("Error responding to event: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to update RSVP"),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingResponse = false);
      }
    }
  }

  void _deleteEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0C20),
        title: Text(
          "Delete Event",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to permanently delete this event? This cannot be undone.",
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      try {
        await appState.firebaseService.deleteBandEventAsync(widget.bandId, widget.eventId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Event deleted"), backgroundColor: AppTheme.success),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint("Error deleting event: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to delete event"), backgroundColor: AppTheme.danger),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_event == null) {
      return const GradientScaffold(
        appBar: CustomTopBar(title: 'Event Details', showBack: true),
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent)),
      );
    }

    final event = _event!;
    final appState = Provider.of<AppState>(context);
    final currentUserId = appState.currentUserId;

    // Parse dates
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? DateTime.now();

    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(startLocal);
    final timeStr = '${DateFormat('HH:mm').format(startLocal)} - ${DateFormat('HH:mm').format(endLocal)}';

    // Calculate response counts
    final attendingList = <String>[];
    final maybeList = <String>[];
    final declinedList = <String>[];
    final noResponseList = <String>[];

    for (var member in _members) {
      final userId = member.userId;
      if (userId == null) continue;

      final name = _cachedProfiles[userId]?.displayName ?? _cachedProfiles[userId]?.nickname ?? member.nickname ?? 'Unknown Member';
      final response = event.responses[userId]?.status;
      final comment = event.responses[userId]?.comment;
      final displayName = comment != null && comment.isNotEmpty ? '$name\n"$comment"' : name;

      if (response == 'attending') {
        attendingList.add(displayName);
      } else if (response == 'maybe') {
        maybeList.add(displayName);
      } else if (response == 'declined') {
        declinedList.add(displayName);
      } else {
        noResponseList.add(name);
      }
    }

    final extAttendingList = <String>[];
    final extMaybeList = <String>[];
    final extDeclinedList = <String>[];
    final extPendingList = <String>[];

    // Process external invitees attending for instrument coverage and response groups
    event.externalInvitees.forEach((userId, invitee) {
      final name = invitee.displayName ?? _cachedProfiles[userId]?.displayName ?? _cachedProfiles[userId]?.nickname ?? 'Unknown Guest';
      final status = invitee.status;
      final comment = invitee.comment;
      final displayName = comment != null && comment.isNotEmpty ? '$name\n"$comment"' : name;

      if (status == 'attending') {
        extAttendingList.add(displayName);
      } else if (status == 'maybe') {
        extMaybeList.add(displayName);
      } else if (status == 'declined') {
        extDeclinedList.add(displayName);
      } else {
        extPendingList.add(name);
      }
    });

    final userResponse = currentUserId != null
        ? (event.responses.containsKey(currentUserId)
            ? event.responses[currentUserId]?.status
            : event.externalInvitees[currentUserId]?.status)
        : null;

    return GradientScaffold(
      appBar: CustomTopBar(
        title: event.title,
        showBack: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (event.isLocked) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.danger.withOpacity(0.5), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: AppTheme.danger, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Event Locked',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            event.lockedAt != null
                                ? 'Locked by ${_cachedProfiles[event.lockedBy]?.displayName ?? _cachedProfiles[event.lockedBy]?.nickname ?? "Organizer"} on ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(event.lockedAt!))}'
                                : 'Responses can no longer be modified.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 1. Header Information Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _getEventIcon(event.eventType),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.eventType,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateStr,
                                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.access_time_outlined, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              timeStr,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.location,
                                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
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
            const SizedBox(height: 20),

            // 2. RSVP Buttons (Only if requireResponse is true)
            if (event.requireResponse) ...[
              Builder(builder: (context) {
                final dbResponse = currentUserId != null
                    ? (event.responses.containsKey(currentUserId)
                        ? event.responses[currentUserId]?.status
                        : event.externalInvitees[currentUserId]?.status)
                    : null;

                final dbComment = currentUserId != null
                    ? (event.responses.containsKey(currentUserId)
                        ? event.responses[currentUserId]?.comment
                        : event.externalInvitees[currentUserId]?.comment)
                    : null;

                if (!_hasInitializedLocalResponse && currentUserId != null) {
                  _localSelectedResponse = dbResponse;
                  _commentController.text = dbComment ?? '';
                  _hasInitializedLocalResponse = true;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR RESPONSE',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Attending
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'attending';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _localSelectedResponse == 'attending'
                                    ? AppTheme.success.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _localSelectedResponse == 'attending' ? AppTheme.success : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: _localSelectedResponse == 'attending' ? AppTheme.success : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Attending',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _localSelectedResponse == 'attending' ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Declined
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'declined';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _localSelectedResponse == 'declined'
                                    ? AppTheme.danger.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _localSelectedResponse == 'declined' ? AppTheme.danger : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: _localSelectedResponse == 'declined' ? AppTheme.danger : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Declined',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _localSelectedResponse == 'declined' ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Maybe
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'maybe';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _localSelectedResponse == 'maybe'
                                    ? AppTheme.textSecondary.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _localSelectedResponse == 'maybe' ? AppTheme.textSecondary : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.help_outline_rounded,
                                    color: _localSelectedResponse == 'maybe' ? AppTheme.textSecondary : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Maybe',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _localSelectedResponse == 'maybe' ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_localSelectedResponse == 'maybe') ...[
                      const SizedBox(height: 16),
                      Text(
                        'WHY ARE YOU UNCERTAIN? (OPTIONAL)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        maxLines: 2,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'e.g. Depends on work travel schedules...',
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _isSavingResponse
                        ? const Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _localSelectedResponse == null
                                  ? null
                                  : () => _respond(_localSelectedResponse!, _commentController.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                'Save RSVP',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                  ],
                );
              }),
              const SizedBox(height: 20),
            ],

            // 3. Description & Additional Notes Section
            if (event.description.isNotEmpty || event.additionalNotes.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.description.isNotEmpty) ...[
                      Text(
                        'DESCRIPTION',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.description,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white, height: 1.4),
                      ),
                    ],
                    if (event.description.isNotEmpty && event.additionalNotes.isNotEmpty)
                      const Divider(height: 24, color: Color(0xFF2E2A4E)),
                    if (event.additionalNotes.isNotEmpty) ...[
                      Text(
                        'ADDITIONAL NOTES',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.additionalNotes,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],



            if (event.requireResponse) ...[
              // 5. Attendance Detail Lists
              Text(
                'ATTENDANCE RESPONSES',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: Column(
                  children: [
                    _buildResponseGroup('Attending (${attendingList.length})', attendingList, AppTheme.success),
                    _buildResponseGroup('Declined (${declinedList.length})', declinedList, AppTheme.danger),
                    _buildResponseGroup('Maybe (${maybeList.length})', maybeList, AppTheme.textSecondary),
                    _buildResponseGroup('No Response (${noResponseList.length})', noResponseList, AppTheme.textSecondary),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // External Invitees Summary List
              if (event.externalInvitees.isNotEmpty) ...[
                Text(
                  'EXTERNAL INVITEES',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Column(
                    children: [
                      _buildResponseGroup('Guest Attending (${extAttendingList.length})', extAttendingList, AppTheme.success),
                      _buildResponseGroup('Guest Maybe (${extMaybeList.length})', extMaybeList, AppTheme.textSecondary),
                      _buildResponseGroup('Guest Declined (${extDeclinedList.length})', extDeclinedList, AppTheme.danger),
                      _buildResponseGroup('Guest Pending (${extPendingList.length})', extPendingList, Colors.grey),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const SizedBox(height: 12),
            ],

            // Creator Actions Section
            if (currentUserId == event.createdBy || _isAdmin) ...[
              const SizedBox(height: 20),
              Text(
                'CREATOR ACTIONS',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              if (!event.isLocked)
                AnimatedTapDetector(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF0F0C20),
                        title: Text("Lock Event", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text("Are you sure you want to lock this event? Once locked, members can no longer change their RSVP status.", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Lock", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      try {
                        await appState.firebaseService.lockBandEventAsync(widget.bandId, widget.eventId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Event locked successfully"), backgroundColor: AppTheme.success),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to lock event: $e"), backgroundColor: AppTheme.danger),
                        );
                      }
                    }
                  },
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, color: AppTheme.primaryAccent),
                          const SizedBox(width: 8),
                          Text(
                            "Lock Event Responses",
                            style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedTapDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FindSubScreen(
                        eventId: widget.eventId,
                        bandId: widget.bandId,
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 50,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          "Find Substitute Musician",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // 6. Delete Event Button for Admins
            if (_isAdmin)
              Center(
                child: AnimatedTapDetector(
                  onTap: _deleteEvent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.danger.withOpacity(0.8), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Delete Event",
                          style: GoogleFonts.inter(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseGroup(String title, List<String> names, Color color) {
    if (names.isEmpty) {
      return const SizedBox.shrink();
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        iconColor: color,
        collapsedIconColor: color.withOpacity(0.7),
        children: names.map((name) {
          final parts = name.split('\n');
          final displayName = parts[0];
          final comment = parts.length > 1 ? parts[1] : null;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'M',
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      if (comment != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          comment,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
