import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band_event.dart';
import '../models/event_room.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import 'find_sub_screen.dart';
import 'event_room_chat_screen.dart';
import 'create_event_page.dart';

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

  List<BandEvent> _linkedSubEvents = [];

  Future<void> _loadMembersAndProfiles() async {
    if (!mounted) return;
    setState(() => _isLoadingMembers = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final members = await appState.firebaseService.getBandMembersAsync(widget.bandId);

      if (_event?.parentEventId != null && _event!.parentEventId!.isNotEmpty) {
        final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);
        _linkedSubEvents = allEvents.where((e) => e.parentEventId == _event!.parentEventId).toList();
        _linkedSubEvents.sort((a, b) {
          final seqA = a.subEventSequence ?? 0;
          final seqB = b.subEventSequence ?? 0;
          if (seqA != seqB) return seqA.compareTo(seqB);
          final aTime = DateTime.tryParse(a.startDateTime) ?? DateTime.now();
          final bTime = DateTime.tryParse(b.startDateTime) ?? DateTime.now();
          return aTime.compareTo(bTime);
        });
      }
      
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

  Future<void> _triggerReminder(String reminderType) async {
    final appState = Provider.of<AppState>(context, listen: false);
    try {
      final count = await appState.firebaseService.triggerEventReminderAsync(
        widget.bandId,
        widget.eventId,
        reminderType,
      );
      if (mounted) {
        final label = reminderType == 'last' ? 'Final' : reminderType.toUpperCase();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚡ [GOD MODE] Sent $label RSVP reminder to $count pending members!"),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to trigger reminder: $e"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Widget _buildGodModeButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AnimatedTapDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
    if (status == 'UNCERTAIN' && (comment.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Why are you uncertain? (mandatory)"),
          backgroundColor: AppTheme.warning,
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

      if ((status == 'YES' || status == 'attending') && _event?.temporaryRoomId != null && _event!.temporaryRoomId!.isNotEmpty) {
        await appState.firebaseService.addMemberToEventRoomAsync(
          widget.bandId,
          _event!.temporaryRoomId!,
          userId,
          'attending',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("RSVP saved: $status"),
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

    // Calculate response counts (YES, NO, UNCERTAIN)
    final yesList = <String>[];
    final uncertainList = <String>[];
    final noList = <String>[];
    final noResponseList = <String>[];

    for (var member in _members) {
      final userId = member.userId;
      if (userId == null) continue;

      final name = _cachedProfiles[userId]?.displayName ?? _cachedProfiles[userId]?.nickname ?? member.nickname ?? 'Unknown Member';
      final response = event.responses[userId]?.status;
      final comment = event.responses[userId]?.uncertainReason ?? event.responses[userId]?.comment;
      final displayName = comment != null && comment.isNotEmpty ? '$name\n"$comment"' : name;

      if (response == 'YES' || response == 'attending') {
        yesList.add(displayName);
      } else if (response == 'UNCERTAIN' || response == 'maybe') {
        uncertainList.add(displayName);
      } else if (response == 'NO' || response == 'declined') {
        noList.add(displayName);
      } else {
        noResponseList.add(name);
      }
    }

    final extYesList = <String>[];
    final extUncertainList = <String>[];
    final extNoList = <String>[];
    final extPendingList = <String>[];

    // Process external invitees attending for instrument coverage and response groups
    event.externalInvitees.forEach((userId, invitee) {
      final name = invitee.displayName ?? _cachedProfiles[userId]?.displayName ?? _cachedProfiles[userId]?.nickname ?? 'Unknown Guest';
      final status = invitee.status;
      final comment = invitee.comment;
      final displayName = comment != null && comment.isNotEmpty ? '$name\n"$comment"' : name;

      if (status == 'YES' || status == 'attending') {
        extYesList.add(displayName);
      } else if (status == 'UNCERTAIN' || status == 'maybe') {
        extUncertainList.add(displayName);
      } else if (status == 'NO' || status == 'declined') {
        extNoList.add(displayName);
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
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.success.withOpacity(0.5), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Event Finalized & Confirmed',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            event.lockedAt != null
                                ? 'Finalized by ${_cachedProfiles[event.lockedBy]?.displayName ?? _cachedProfiles[event.lockedBy]?.nickname ?? "Organizer"} on ${DateFormat('MMM d, yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(event.lockedAt!))}'
                                : 'All subs and members confirmed. RSVPs locked.',
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

                        // Quick Sub-Event / Part Switcher Buttons inside the Header Box
                        if (_linkedSubEvents.length > 1) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16132D),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "SWITCH EVENT DATES (${_linkedSubEvents.length} PARTS):",
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purpleAccent,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _linkedSubEvents.map((sub) {
                                      final isCurrent = sub.id == _event?.id;
                                      final subStart = DateTime.tryParse(sub.startDateTime)?.toLocal() ?? DateTime.now();
                                      final dateLabel = DateFormat('EEE, MMM d').format(subStart);
                                      final seqStr = sub.subEventSequence != null ? 'Part ${sub.subEventSequence}' : sub.title;

                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: AnimatedTapDetector(
                                          onTap: () {
                                            setState(() {
                                              _event = sub;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              gradient: isCurrent ? AppTheme.primaryGradient : null,
                                              color: isCurrent ? null : const Color(0xFF231F45),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isCurrent ? Colors.white : Colors.transparent,
                                                width: isCurrent ? 1.5 : 0,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isCurrent ? Icons.check_circle_rounded : Icons.calendar_today_rounded,
                                                  size: 13,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$seqStr: $dateLabel',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                                  ),
                                                ),
                                              ],
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
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Event Series Schedule (If grouped multi-part event)
            if (_linkedSubEvents.length > 1) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "EVENT SERIES SCHEDULE",
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_linkedSubEvents.length} Parts',
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: _linkedSubEvents.map((sub) {
                        final isCurrent = sub.id == _event?.id;
                        final subStart = DateTime.tryParse(sub.startDateTime)?.toLocal() ?? DateTime.now();
                        final subTimeStr = DateFormat('EEE, MMM d • HH:mm').format(subStart);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCurrent ? AppTheme.primaryAccent.withOpacity(0.15) : const Color(0xFF16132D),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCurrent ? Icons.play_circle_fill_rounded : Icons.radio_button_unchecked_rounded,
                                size: 16,
                                color: isCurrent ? AppTheme.primaryAccent : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub.title,
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$subTimeStr • ${sub.location}',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isCurrent)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _event = sub;
                                    });
                                  },
                                  child: const Text('View', style: TextStyle(color: AppTheme.primaryAccent, fontSize: 12)),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            // Open Event Chat (Prominent Top Placement)
            if (event.temporaryRoomId != null && event.temporaryRoomId!.isNotEmpty) ...[
              AnimatedTapDetector(
                onTap: () {
                  final eventRoom = EventRoom(
                    roomId: event.temporaryRoomId!,
                    eventId: widget.eventId,
                    bandId: widget.bandId,
                    name: '${event.title} Chat',
                    createdAt: event.createdAt,
                    createdBy: event.createdBy,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EventRoomChatScreen(
                        bandId: widget.bandId,
                        eventRoom: eventRoom,
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 48,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.forum_outlined, color: AppTheme.primaryAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Open Event Chat",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'CHAT',
                          style: GoogleFonts.inter(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),

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
                        // YES
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'YES';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: (_localSelectedResponse == 'YES' || _localSelectedResponse == 'attending')
                                    ? AppTheme.success.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (_localSelectedResponse == 'YES' || _localSelectedResponse == 'attending') ? AppTheme.success : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: (_localSelectedResponse == 'YES' || _localSelectedResponse == 'attending') ? AppTheme.success : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'YES',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: (_localSelectedResponse == 'YES' || _localSelectedResponse == 'attending') ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // NO
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'NO';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: (_localSelectedResponse == 'NO' || _localSelectedResponse == 'declined')
                                    ? AppTheme.danger.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (_localSelectedResponse == 'NO' || _localSelectedResponse == 'declined') ? AppTheme.danger : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: (_localSelectedResponse == 'NO' || _localSelectedResponse == 'declined') ? AppTheme.danger : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'NO',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: (_localSelectedResponse == 'NO' || _localSelectedResponse == 'declined') ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // UNCERTAIN
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localSelectedResponse = 'UNCERTAIN';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: (_localSelectedResponse == 'UNCERTAIN' || _localSelectedResponse == 'maybe')
                                    ? AppTheme.warning.withOpacity(0.2)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (_localSelectedResponse == 'UNCERTAIN' || _localSelectedResponse == 'maybe') ? AppTheme.warning : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.help_outline_rounded,
                                    color: (_localSelectedResponse == 'UNCERTAIN' || _localSelectedResponse == 'maybe') ? AppTheme.warning : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'UNCERTAIN',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: (_localSelectedResponse == 'UNCERTAIN' || _localSelectedResponse == 'maybe') ? Colors.white : AppTheme.textSecondary,
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
                    if (_localSelectedResponse == 'UNCERTAIN' || _localSelectedResponse == 'maybe') ...[
                      const SizedBox(height: 16),
                      Text(
                        'WHY ARE YOU UNCERTAIN? (mandatory)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.warning,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        maxLines: 2,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Why are you uncertain? (mandatory)',
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
              // 5. Attendance Detail Lists (CEO Page 3)
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
                    _buildResponseGroup('YES (${yesList.length})', yesList, AppTheme.success),
                    _buildResponseGroup('NO (${noList.length})', noList, AppTheme.danger),
                    _buildResponseGroup('UNCERTAIN (${uncertainList.length})', uncertainList, AppTheme.warning),
                    _buildResponseGroup('Unanswered (${noResponseList.length})', noResponseList, AppTheme.textSecondary),
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
                      _buildResponseGroup('Guest YES (${extYesList.length})', extYesList, AppTheme.success),
                      _buildResponseGroup('Guest UNCERTAIN (${extUncertainList.length})', extUncertainList, AppTheme.warning),
                      _buildResponseGroup('Guest NO (${extNoList.length})', extNoList, AppTheme.danger),
                      _buildResponseGroup('Guest Pending (${extPendingList.length})', extPendingList, Colors.grey),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const SizedBox(height: 12),
            ],

            // ⚡ REMINDER SETTINGS (CEO Page 3)
            if (currentUserId == event.createdBy || _isAdmin) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1535),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.15),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Colors.amber, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'REMINDER SETTINGS',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Automated reminders count down from when the event is published. Tap below to send manual override reminders.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.3),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildGodModeButton(
                          label: 'Trigger 24h Reminder',
                          icon: Icons.notifications_active_outlined,
                          color: AppTheme.primaryAccent,
                          onTap: () => _triggerReminder('24h'),
                        ),
                        _buildGodModeButton(
                          label: 'Trigger 48h Reminder',
                          icon: Icons.notifications_active_outlined,
                          color: Colors.deepPurpleAccent,
                          onTap: () => _triggerReminder('48h'),
                        ),
                        _buildGodModeButton(
                          label: 'Trigger 72h Reminder',
                          icon: Icons.notifications_active_outlined,
                          color: Colors.blueAccent,
                          onTap: () => _triggerReminder('72h'),
                        ),
                        _buildGodModeButton(
                          label: 'Trigger Final Reminder',
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orangeAccent,
                          onTap: () => _triggerReminder('last'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Creator Actions Section
            if (currentUserId == event.createdBy || _isAdmin) ...[
              const SizedBox(height: 10),
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
              if (_linkedSubEvents.length > 1)
                AnimatedTapDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateEventPage(
                          bandId: widget.bandId,
                          existingGroupEvents: _linkedSubEvents,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit_calendar_outlined, color: AppTheme.primaryAccent),
                          const SizedBox(width: 8),
                          Text(
                            "Edit Event Series",
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!event.isLocked)
                AnimatedTapDetector(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF0F0C20),
                        title: Text("Finalize Event?", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text("Are you sure all subs and members are confirmed and everything is a go? Finalizing locks RSVPs and sets the event status to Finalized.", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Finalize Event", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      try {
                        await appState.firebaseService.lockBandEventAsync(widget.bandId, widget.eventId);
                        
                        // Ask creator if they want to create an event room if none exists yet
                        if (event.temporaryRoomId == null || event.temporaryRoomId!.isEmpty) {
                          if (!mounted) return;
                          final createRoom = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF0F0C20),
                              title: Text("Create Event Chat?", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                              content: Text(
                                "The event is finalized! Would you like to create a temporary event chat for attending members & subs?",
                                style: GoogleFonts.inter(color: AppTheme.textSecondary),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No thanks", style: TextStyle(color: AppTheme.textSecondary))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("Create Chat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );

                          if (createRoom == true && mounted) {
                            await appState.firebaseService.createTemporaryEventRoomAsync(
                              bandId: widget.bandId,
                              eventId: widget.eventId,
                              roomName: '${event.title} Chat',
                              createdBy: currentUserId ?? '',
                            );
                          }
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Event finalized successfully! All subs/members confirmed."), backgroundColor: AppTheme.success),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Failed to finalize event: $e"), backgroundColor: AppTheme.danger),
                          );
                        }
                      }
                    }
                  },
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.success, width: 1.5),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, color: AppTheme.success),
                          const SizedBox(width: 8),
                          Text(
                            "Finalize Event & Lock RSVPs",
                            style: GoogleFonts.inter(color: AppTheme.success, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                AnimatedTapDetector(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF0F0C20),
                        title: Text("Re-open RSVPs?", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text("Do you want to unlock this event and allow members/subs to modify their RSVP status again?", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Re-open RSVPs", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      try {
                        await appState.firebaseService.unlockBandEventAsync(widget.bandId, widget.eventId);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Event unlocked. RSVPs re-opened."), backgroundColor: AppTheme.success),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Failed to unlock event: $e"), backgroundColor: AppTheme.danger),
                          );
                        }
                      }
                    }
                  },
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.6), width: 1.5),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_open_rounded, color: AppTheme.primaryAccent),
                          const SizedBox(width: 8),
                          Text(
                            "Re-open RSVPs / Unlock",
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
                          "FIND SUBSTITUTE(S)",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1),
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
