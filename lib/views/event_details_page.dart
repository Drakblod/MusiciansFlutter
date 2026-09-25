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

class _EventScheduleItemModel {
  final int sequenceIndex; // 0 for main, 1..N for attached
  final bool isMain;
  final String? scheduleItemId;
  final String type;
  final String title;
  final String description;
  final String dateStr;
  final String timeStr;
  final String location;
  final String? status;
  final String? comment;

  _EventScheduleItemModel({
    required this.sequenceIndex,
    required this.isMain,
    this.scheduleItemId,
    required this.type,
    required this.title,
    required this.description,
    required this.dateStr,
    required this.timeStr,
    required this.location,
    this.status,
    this.comment,
  });
}

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
  final ScrollController _scrollController = ScrollController();
  BandEvent? _event;
  StreamSubscription<BandEvent?>? _eventSubscription;
  List<BandMember> _members = [];
  Map<String, UserProfile> _cachedProfiles = {};
  bool _isLoadingMembers = true;
  String? _currentUserRole;

  // Sequential RSVP state
  int? _expandedEventIndex;
  final Map<int, String?> _draftSelectedStatus = {};
  final Map<int, TextEditingController> _draftCommentControllers = {};
  final Set<int> _savingIndices = {};
  bool _hasInitializedExpansion = false;

  // Attendance details expansion state (e.g. '0_YES', '1_UNCERTAIN')
  String? _activeAttendanceGroupKey;

  List<BandEvent> _linkedSubEvents = [];

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
    _scrollController.dispose();
    for (final controller in _draftCommentControllers.values) {
      controller.dispose();
    }
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
          _syncDraftState(updatedEvent);
        });
      }
    });
  }

  void _syncDraftState(BandEvent event) {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    if (currentUserId == null) return;

    final items = _buildScheduleItems(event, currentUserId);

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (!_draftSelectedStatus.containsKey(i) || _draftSelectedStatus[i] == null) {
        if (item.status != null) {
          _draftSelectedStatus[i] = item.status;
        }
      }
      if (!_draftCommentControllers.containsKey(i)) {
        _draftCommentControllers[i] = TextEditingController(text: item.comment ?? '');
      } else if (_draftCommentControllers[i]!.text.isEmpty && item.comment != null) {
        _draftCommentControllers[i]!.text = item.comment!;
      }
    }

    if (!_hasInitializedExpansion) {
      _hasInitializedExpansion = true;
      int? firstUnanswered;
      for (int i = 0; i < items.length; i++) {
        if (classifyEventResponse(items[i].status) == EventResponseStatus.noAnswer) {
          firstUnanswered = i;
          break;
        }
      }
      _expandedEventIndex = firstUnanswered;
    }
  }

  Future<void> _loadMembersAndProfiles() async {
    if (!mounted) return;
    setState(() => _isLoadingMembers = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final members = await appState.firebaseService.getBandMembersAsync(widget.bandId);

      if (_event != null) {
        final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);

        String normalizeTitle(String rawTitle) {
          return rawTitle
              .replaceAll(RegExp(r'\s*[\-\(]?\s*(Part|Date|Day)\s*\d+[\)]?', caseSensitive: false), '')
              .trim()
              .toLowerCase();
        }

        if (_event!.parentEventId != null && _event!.parentEventId!.isNotEmpty) {
          _linkedSubEvents = allEvents.where((e) => e.parentEventId == _event!.parentEventId).toList();
        } else {
          final normTarget = normalizeTitle(_event!.title);
          _linkedSubEvents = allEvents.where((e) => normalizeTitle(e.title) == normTarget).toList();
        }

        _linkedSubEvents.sort((a, b) {
          final seqA = a.subEventSequence ?? 0;
          final seqB = b.subEventSequence ?? 0;
          if (seqA != seqB) return seqA.compareTo(seqB);
          final aTime = DateTime.tryParse(a.startDateTime) ?? DateTime.now();
          final bTime = DateTime.tryParse(b.startDateTime) ?? DateTime.now();
          return aTime.compareTo(bTime);
        });
      }

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

      final extUserIds = _event?.externalInvitees.keys.toList() ?? [];
      await Future.wait(extUserIds.map((userId) async {
        if (!profiles.containsKey(userId)) {
          final profile = await appState.firebaseService.getUserProfileAsync(userId);
          if (profile != null) {
            profiles[userId] = profile;
          }
        }
      }));

      final lockedBy = _event?.lockedBy;
      if (lockedBy != null && !profiles.containsKey(lockedBy)) {
        final profile = await appState.firebaseService.getUserProfileAsync(lockedBy);
        if (profile != null) {
          profiles[lockedBy] = profile;
        }
      }

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
          if (_event != null) {
            _syncDraftState(_event!);
          }
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

  List<_EventScheduleItemModel> _buildScheduleItems(BandEvent event, String? currentUserId) {
    final List<_EventScheduleItemModel> list = [];

    // 1. Main Event (Item 0)
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? DateTime.now();
    final mainDateStr = DateFormat('EEEE, MMMM d, yyyy').format(startLocal);
    final mainTimeStr = '${DateFormat('HH:mm').format(startLocal)} - ${DateFormat('HH:mm').format(endLocal)}';

    String? mainStatus;
    String? mainComment;
    if (currentUserId != null) {
      if (event.responses.containsKey(currentUserId)) {
        mainStatus = event.responses[currentUserId]?.status;
        mainComment = event.responses[currentUserId]?.uncertainReason ?? event.responses[currentUserId]?.comment;
      } else if (event.externalInvitees.containsKey(currentUserId)) {
        mainStatus = event.externalInvitees[currentUserId]?.status;
        mainComment = event.externalInvitees[currentUserId]?.comment;
      }
    }

    list.add(_EventScheduleItemModel(
      sequenceIndex: 0,
      isMain: true,
      scheduleItemId: null,
      type: event.eventType.isNotEmpty && event.eventType.toLowerCase() != 'event' ? event.eventType : 'Main Event',
      title: event.title,
      description: event.description,
      dateStr: mainDateStr,
      timeStr: mainTimeStr,
      location: event.location,
      status: mainStatus,
      comment: mainComment,
    ));

    // 2. Attached Schedule Items (Items 1..N)
    for (int i = 0; i < event.rehearsals.length; i++) {
      final rehearsal = event.rehearsals[i];
      final parsedDate = DateTime.tryParse(rehearsal.date);
      final dateFormatted = parsedDate != null
          ? DateFormat('EEEE, MMMM d, yyyy').format(parsedDate)
          : rehearsal.date;
      final timeFormatted = '${rehearsal.startTime} - ${rehearsal.endTime}';
      final titleFormatted = rehearsal.title.isNotEmpty ? rehearsal.title : event.title;
      final typeFormatted = rehearsal.type.isNotEmpty ? rehearsal.type : 'Rehearsal';
      final locationFormatted = rehearsal.location.isNotEmpty ? rehearsal.location : event.location;

      String? schedStatus;
      String? schedComment;
      if (currentUserId != null && event.scheduleResponses.containsKey(rehearsal.id)) {
        final userResp = event.scheduleResponses[rehearsal.id]?[currentUserId];
        schedStatus = userResp?.status;
        schedComment = userResp?.uncertainReason ?? userResp?.comment;
      }

      list.add(_EventScheduleItemModel(
        sequenceIndex: i + 1,
        isMain: false,
        scheduleItemId: rehearsal.id,
        type: typeFormatted,
        title: titleFormatted,
        description: rehearsal.description,
        dateStr: dateFormatted,
        timeStr: timeFormatted,
        location: locationFormatted,
        status: schedStatus,
        comment: schedComment,
      ));
    }

    return list;
  }

  Future<void> _saveRsvpForIndex(int itemIndex, _EventScheduleItemModel item) async {
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

    final selectedStatus = _draftSelectedStatus[itemIndex];
    if (selectedStatus == null) return;

    final statusEnum = classifyEventResponse(selectedStatus);
    final comment = _draftCommentControllers[itemIndex]?.text ?? '';

    if (statusEnum == EventResponseStatus.uncertain && comment.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Why are you uncertain? (mandatory)"),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    if (_savingIndices.contains(itemIndex)) return; // Prevent duplicate saves

    setState(() {
      _savingIndices.add(itemIndex);
    });

    try {
      final cleanComment = comment.trim().isEmpty ? null : comment.trim();
      final normalizedStatus = statusEnum == EventResponseStatus.yes
          ? 'Yes'
          : (statusEnum == EventResponseStatus.no
              ? 'No'
              : (statusEnum == EventResponseStatus.uncertain ? 'Uncertain' : selectedStatus));

      if (item.isMain) {
        final isExternal = _event!.externalInvitees.containsKey(userId);
        if (isExternal) {
          await appState.firebaseService.updateExternalInviteeResponseAsync(
            widget.bandId,
            widget.eventId,
            userId,
            normalizedStatus,
            comment: cleanComment,
          );
        } else {
          await appState.firebaseService.updateEventResponseAsync(
            widget.bandId,
            widget.eventId,
            userId,
            normalizedStatus,
            comment: cleanComment,
          );
        }

        if (statusEnum == EventResponseStatus.yes &&
            _event?.temporaryRoomId != null &&
            _event!.temporaryRoomId!.isNotEmpty) {
          await appState.firebaseService.addMemberToEventRoomAsync(
            widget.bandId,
            _event!.temporaryRoomId!,
            userId,
            'attending',
          );
        }
      } else {
        await appState.firebaseService.updateScheduleItemResponseAsync(
          widget.bandId,
          widget.eventId,
          item.scheduleItemId!,
          userId,
          normalizedStatus,
          uncertainReason: cleanComment,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("RSVP saved: $normalizedStatus"),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 1),
        ),
      );

      // Determine next unanswered item after itemIndex
      final items = _buildScheduleItems(_event!, userId);
      int? nextUnanswered;
      for (int i = 0; i < items.length; i++) {
        if (i != itemIndex) {
          final isAnswered = i < itemIndex
              ? classifyEventResponse(items[i].status) != EventResponseStatus.noAnswer
              : (classifyEventResponse(items[i].status) != EventResponseStatus.noAnswer);
          if (!isAnswered) {
            nextUnanswered = i;
            break;
          }
        }
      }

      setState(() {
        _savingIndices.remove(itemIndex);
        _expandedEventIndex = nextUnanswered;
      });
    } catch (e) {
      debugPrint("Error saving RSVP: $e");
      if (mounted) {
        setState(() {
          _savingIndices.remove(itemIndex);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to update RSVP"),
            backgroundColor: AppTheme.danger,
          ),
        );
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
            child: Text("Cancel", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text("Delete", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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

    final scheduleItems = _buildScheduleItems(event, currentUserId);
    final hasMultipleEvents = event.rehearsals.isNotEmpty;

    final allEventsAnswered = scheduleItems.every(
      (item) => classifyEventResponse(item.status) != EventResponseStatus.noAnswer,
    );

    return GradientScaffold(
      appBar: CustomTopBar(
        title: event.title,
        showBack: true,
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Finalized / Locked Banner
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

            // Main Header Overview Box
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                            if (event.eventType.isNotEmpty && event.eventType.toLowerCase() != 'event') ...[
                              const SizedBox(height: 4),
                              Text(
                                event.eventType,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppTheme.primaryAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasMultipleEvents)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5)),
                          ),
                          child: Text(
                            'EVENT SCHEDULE (${scheduleItems.length} Events)',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scheduleItems[0].dateStr,
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
                        scheduleItems[0].timeStr,
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                  if (event.location.isNotEmpty) ...[
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
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      event.description,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),

            // RSVP Section (If requireResponse is true)
            if (event.requireResponse) ...[
              if (!hasMultipleEvents) ...[
                // Single-Event Direct RSVP Controls
                Builder(builder: (context) {
                  final item = scheduleItems[0];
                  final isSaving = _savingIndices.contains(0);
                  final draftStatus = _draftSelectedStatus[0] ?? item.status;
                  final draftEnum = classifyEventResponse(draftStatus);
                  final isDraftYes = draftEnum == EventResponseStatus.yes;
                  final isDraftNo = draftEnum == EventResponseStatus.no;
                  final isDraftUncertain = draftEnum == EventResponseStatus.uncertain;

                  final commentController = _draftCommentControllers[0] ?? TextEditingController();
                  _draftCommentControllers[0] = commentController;

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
                              onTap: event.isLocked
                                  ? null
                                  : () {
                                      setState(() {
                                        _draftSelectedStatus[0] = 'Yes';
                                      });
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isDraftYes
                                      ? AppTheme.success.withOpacity(0.2)
                                      : AppTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDraftYes ? AppTheme.success : const Color(0xFF2E2A4E),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 17,
                                      color: isDraftYes ? AppTheme.success : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'YES',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: isDraftYes ? Colors.white : AppTheme.textSecondary,
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
                              onTap: event.isLocked
                                  ? null
                                  : () {
                                      setState(() {
                                        _draftSelectedStatus[0] = 'No';
                                      });
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: isDraftNo
                                      ? AppTheme.danger.withOpacity(0.2)
                                      : AppTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDraftNo ? AppTheme.danger : const Color(0xFF2E2A4E),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cancel_outlined,
                                      size: 17,
                                      color: isDraftNo ? AppTheme.danger : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'NO',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: isDraftNo ? Colors.white : AppTheme.textSecondary,
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
                              onTap: event.isLocked
                                  ? null
                                  : () {
                                      setState(() {
                                        _draftSelectedStatus[0] = 'Uncertain';
                                      });
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                decoration: BoxDecoration(
                                  color: isDraftUncertain
                                      ? AppTheme.warning.withOpacity(0.2)
                                      : AppTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDraftUncertain ? AppTheme.warning : const Color(0xFF2E2A4E),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.help_outline_rounded,
                                      size: 17,
                                      color: isDraftUncertain ? AppTheme.warning : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'UNCERTAIN',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: isDraftUncertain ? Colors.white : AppTheme.textSecondary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isDraftUncertain) ...[
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
                          controller: commentController,
                          maxLines: 2,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Why are you uncertain? (mandatory)',
                          ),
                        ),
                      ],
                      if (!event.isLocked) ...[
                        const SizedBox(height: 20),
                        isSaving
                            ? const Center(
                                child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: draftStatus == null
                                      ? null
                                      : () => _saveRsvpForIndex(0, item),
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
                      const SizedBox(height: 20),
                    ],
                  );
                }),
              ] else ...[
                // Multi-Event Sequential RSVP Accordion
                if (allEventsAnswered) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.success.withOpacity(0.5), width: 1.2),
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
                                "✓ All events answered",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Your RSVP responses have been saved.",
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
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

                // Sequential RSVP Cards for Each Event in Schedule
                ...List.generate(scheduleItems.length, (index) {
                  final item = scheduleItems[index];
                  final isExpanded = _expandedEventIndex == index;
                  final isSaving = _savingIndices.contains(index);

                  final savedStatusEnum = classifyEventResponse(item.status);
                  final draftStatus = _draftSelectedStatus[index] ?? item.status;
                  final draftEnum = classifyEventResponse(draftStatus);
                  final isDraftYes = draftEnum == EventResponseStatus.yes;
                  final isDraftNo = draftEnum == EventResponseStatus.no;
                  final isDraftUncertain = draftEnum == EventResponseStatus.uncertain;

                  final commentController = _draftCommentControllers[index] ?? TextEditingController();
                  _draftCommentControllers[index] = commentController;

                  final eventHeaderPrefix = 'EVENT ${index + 1}';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isExpanded
                            ? AppTheme.primaryAccent
                            : (savedStatusEnum != EventResponseStatus.noAnswer
                                ? const Color(0xFF2E2A4E)
                                : Colors.amber.withOpacity(0.6)),
                        width: isExpanded ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header (Always visible, tap to toggle when unlocked)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: event.isLocked
                              ? null
                              : () {
                                  setState(() {
                                    _expandedEventIndex = isExpanded ? null : index;
                                  });
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryAccent.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              eventHeaderPrefix,
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.primaryAccent,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            item.type,
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.title,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (item.description.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.description,
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            color: Colors.white70,
                                          ),
                                          maxLines: isExpanded ? null : 2,
                                          overflow: isExpanded ? null : TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.dateStr} • ${item.timeStr}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      if (item.location.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.location,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Saved Status Badge / Toggle Indicator
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _buildSavedStatusBadge(savedStatusEnum),
                                    if (!event.isLocked) ...[
                                      const SizedBox(height: 6),
                                      Icon(
                                        isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                        size: 18,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Expanded RSVP Controls Area
                        if (isExpanded && !event.isLocked) ...[
                          const Divider(height: 1, color: Color(0xFF2E2A4E)),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR RESPONSE',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryAccent,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Responsive Single Row RSVP Buttons
                                Row(
                                  children: [
                                    // YES
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _draftSelectedStatus[index] = 'Yes';
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                          decoration: BoxDecoration(
                                            color: isDraftYes
                                                ? AppTheme.success.withOpacity(0.2)
                                                : const Color(0xFF16132D),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDraftYes ? AppTheme.success : const Color(0xFF2E2A4E),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.check_circle_outline_rounded,
                                                size: 15,
                                                color: isDraftYes ? AppTheme.success : AppTheme.textSecondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'YES',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: isDraftYes ? Colors.white : AppTheme.textSecondary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // NO
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _draftSelectedStatus[index] = 'No';
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                          decoration: BoxDecoration(
                                            color: isDraftNo
                                                ? AppTheme.danger.withOpacity(0.2)
                                                : const Color(0xFF16132D),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDraftNo ? AppTheme.danger : const Color(0xFF2E2A4E),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.cancel_outlined,
                                                size: 15,
                                                color: isDraftNo ? AppTheme.danger : AppTheme.textSecondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'NO',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: isDraftNo ? Colors.white : AppTheme.textSecondary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // UNCERTAIN
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _draftSelectedStatus[index] = 'Uncertain';
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                          decoration: BoxDecoration(
                                            color: isDraftUncertain
                                                ? AppTheme.warning.withOpacity(0.2)
                                                : const Color(0xFF16132D),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDraftUncertain ? AppTheme.warning : const Color(0xFF2E2A4E),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.help_outline_rounded,
                                                size: 15,
                                                color: isDraftUncertain ? AppTheme.warning : AppTheme.textSecondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'UNCERTAIN',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: isDraftUncertain ? Colors.white : AppTheme.textSecondary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Mandatory reason input for UNCERTAIN
                                if (isDraftUncertain) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'WHY ARE YOU UNCERTAIN? (mandatory)',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.warning,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: commentController,
                                    maxLines: 2,
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      hintText: 'Why are you uncertain? (mandatory)',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),

                                // Save RSVP Button
                                isSaving
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(vertical: 8),
                                          child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                                        ),
                                      )
                                    : SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: draftStatus == null
                                              ? null
                                              : () => _saveRsvpForIndex(index, item),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          child: Text(
                                            'Save RSVP',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
            ],

            // Additional Notes Section (if main event has additional notes)
            if (event.additionalNotes.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                ),
              ),
            ],

            // Attendance Responses Section (Placed at the bottom below all RSVP event cards)
            if (event.requireResponse) ...[
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

              ...List.generate(scheduleItems.length, (itemIndex) {
                final item = scheduleItems[itemIndex];
                final countsAndLists = _calculateAttendanceForScheduleItem(event, item);
                final yesList = countsAndLists['yes'] ?? [];
                final noList = countsAndLists['no'] ?? [];
                final uncertainList = countsAndLists['uncertain'] ?? [];

                final itemLabel = hasMultipleEvents
                    ? 'EVENT ${itemIndex + 1} · ${item.type.toUpperCase()} · "${item.title}"'
                    : '${item.type.toUpperCase()} · "${item.title}"';

                final yesKey = '${itemIndex}_YES';
                final noKey = '${itemIndex}_NO';
                final uncertainKey = '${itemIndex}_UNCERTAIN';

                final isYesActive = _activeAttendanceGroupKey == yesKey;
                final isNoActive = _activeAttendanceGroupKey == noKey;
                final isUncertainActive = _activeAttendanceGroupKey == uncertainKey;

                List<_RespondentEntry>? activeList;
                Color activeColor = Colors.white;
                String activeTitle = '';

                if (isYesActive) {
                  activeList = yesList;
                  activeColor = AppTheme.success;
                  activeTitle = 'YES Respondents (${yesList.length})';
                } else if (isNoActive) {
                  activeList = noList;
                  activeColor = AppTheme.danger;
                  activeTitle = 'NO Respondents (${noList.length})';
                } else if (isUncertainActive) {
                  activeList = uncertainList;
                  activeColor = AppTheme.warning;
                  activeTitle = 'UNCERTAIN Respondents (${uncertainList.length})';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Compact Single Row Counts
                      Row(
                        children: [
                          _buildAttendanceCountPill(
                            icon: Icons.check_circle_outline_rounded,
                            label: 'YES (${yesList.length})',
                            color: AppTheme.success,
                            isSelected: isYesActive,
                            onTap: () {
                              setState(() {
                                _activeAttendanceGroupKey = isYesActive ? null : yesKey;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildAttendanceCountPill(
                            icon: Icons.cancel_outlined,
                            label: 'NO (${noList.length})',
                            color: AppTheme.danger,
                            isSelected: isNoActive,
                            onTap: () {
                              setState(() {
                                _activeAttendanceGroupKey = isNoActive ? null : noKey;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildAttendanceCountPill(
                            icon: Icons.help_outline_rounded,
                            label: 'UNCERTAIN (${uncertainList.length})',
                            color: AppTheme.warning,
                            isSelected: isUncertainActive,
                            onTap: () {
                              setState(() {
                                _activeAttendanceGroupKey = isUncertainActive ? null : uncertainKey;
                              });
                            },
                          ),
                        ],
                      ),

                      // Expandable Member Name List for Active Group
                      if (activeList != null && activeList.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16132D),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: activeColor.withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeTitle,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: activeColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...activeList.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 10,
                                        backgroundColor: activeColor.withOpacity(0.2),
                                        child: Text(
                                          entry.name.isNotEmpty ? entry.name[0].toUpperCase() : 'M',
                                          style: GoogleFonts.inter(
                                            color: activeColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                entry.reason!,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: AppTheme.textSecondary,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // Event Creator Actions (Only for Event Creator or Leader/Admin)
            if (currentUserId == event.createdBy || _isAdmin) ...[
              Text(
                'EVENT CREATOR ACTIONS',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),

              // Edit Event
              AnimatedTapDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateEventPage(
                        bandId: widget.bandId,
                        existingEvent: _event,
                        existingGroupEvents: _linkedSubEvents.isNotEmpty
                            ? _linkedSubEvents
                            : (_event != null ? [_event!] : null),
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 48,
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
                        const Icon(Icons.edit_calendar_outlined, color: AppTheme.primaryAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _linkedSubEvents.length > 1 ? "Edit Event Series" : "Edit Event",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Finalize or Unlock
              if (!event.isLocked)
                AnimatedTapDetector(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF0F0C20),
                        title: Text("Finalize Event?", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text("Are you sure all subs and members are confirmed and everything is a go? Finalizing locks RSVPs for all schedule items and sets the event status to Finalized.", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel", style: GoogleFonts.inter(color: AppTheme.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text("Finalize Event", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      try {
                        await appState.firebaseService.lockBandEventAsync(widget.bandId, widget.eventId);

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
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("No thanks", style: GoogleFonts.inter(color: AppTheme.textSecondary))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text("Create Chat", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    height: 48,
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
                          const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Finalize Event & Lock RSVPs",
                            style: GoogleFonts.inter(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 14),
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
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel", style: GoogleFonts.inter(color: AppTheme.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text("Re-open RSVPs", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    height: 48,
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
                          const Icon(Icons.lock_open_rounded, color: AppTheme.primaryAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Re-open RSVPs / Unlock",
                            style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Find Substitute(s)
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
                  height: 48,
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
                        const Icon(Icons.person_search_outlined, color: AppTheme.primaryAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Find Substitute(s)",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Open Event Chat (Single Button Near Bottom)
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
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
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

            // Delete Event Button for Admins
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

  Widget _buildSavedStatusBadge(EventResponseStatus status) {
    String text;
    Color color;
    IconData icon;

    switch (status) {
      case EventResponseStatus.yes:
        text = 'YES';
        color = AppTheme.success;
        icon = Icons.check_circle_rounded;
        break;
      case EventResponseStatus.no:
        text = 'NO';
        color = AppTheme.danger;
        icon = Icons.cancel_rounded;
        break;
      case EventResponseStatus.uncertain:
        text = 'UNCERTAIN';
        color = AppTheme.warning;
        icon = Icons.help_rounded;
        break;
      case EventResponseStatus.noAnswer:
      default:
        text = 'Unanswered';
        color = AppTheme.textSecondary;
        icon = Icons.radio_button_unchecked_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCountPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.25) : const Color(0xFF16132D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF2E2A4E),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSelected ? color : color.withOpacity(0.8)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<_RespondentEntry>> _calculateAttendanceForScheduleItem(
    BandEvent event,
    _EventScheduleItemModel item,
  ) {
    final yesList = <_RespondentEntry>[];
    final noList = <_RespondentEntry>[];
    final uncertainList = <_RespondentEntry>[];

    if (item.isMain) {
      // Main event attendance
      for (final member in _members) {
        final uid = member.userId;
        if (uid == null || uid.isEmpty) continue;

        final profile = _cachedProfiles[uid];
        final name = profile?.displayName ??
            profile?.nickname ??
            ((member.nickname != null && member.nickname!.trim().toLowerCase() != 'leader') ? member.nickname : null) ??
            'Unknown Member';

        final resp = event.responses[uid];
        final status = classifyEventResponse(resp?.status);
        final reason = resp?.uncertainReason ?? resp?.comment;

        if (status == EventResponseStatus.yes) {
          yesList.add(_RespondentEntry(name: name, reason: reason));
        } else if (status == EventResponseStatus.no) {
          noList.add(_RespondentEntry(name: name, reason: reason));
        } else if (status == EventResponseStatus.uncertain) {
          uncertainList.add(_RespondentEntry(name: name, reason: reason));
        }
      }

      event.externalInvitees.forEach((uid, invitee) {
        final profile = _cachedProfiles[uid];
        final name = invitee.displayName ?? profile?.displayName ?? profile?.nickname ?? 'Unknown Guest';
        final status = classifyEventResponse(invitee.status);
        final reason = invitee.comment;

        if (status == EventResponseStatus.yes) {
          yesList.add(_RespondentEntry(name: '$name (Guest)', reason: reason));
        } else if (status == EventResponseStatus.no) {
          noList.add(_RespondentEntry(name: '$name (Guest)', reason: reason));
        } else if (status == EventResponseStatus.uncertain) {
          uncertainList.add(_RespondentEntry(name: '$name (Guest)', reason: reason));
        }
      });
    } else {
      // Attached Schedule item attendance
      final scheduleId = item.scheduleItemId;
      final scheduleMap = scheduleId != null ? (event.scheduleResponses[scheduleId] ?? {}) : <String, EventResponse>{};

      for (final member in _members) {
        final uid = member.userId;
        if (uid == null || uid.isEmpty) continue;

        final profile = _cachedProfiles[uid];
        final name = profile?.displayName ??
            profile?.nickname ??
            ((member.nickname != null && member.nickname!.trim().toLowerCase() != 'leader') ? member.nickname : null) ??
            'Unknown Member';

        final resp = scheduleMap[uid];
        final status = classifyEventResponse(resp?.status);
        final reason = resp?.uncertainReason ?? resp?.comment;

        if (status == EventResponseStatus.yes) {
          yesList.add(_RespondentEntry(name: name, reason: reason));
        } else if (status == EventResponseStatus.no) {
          noList.add(_RespondentEntry(name: name, reason: reason));
        } else if (status == EventResponseStatus.uncertain) {
          uncertainList.add(_RespondentEntry(name: name, reason: reason));
        }
      }
    }

    return {
      'yes': yesList,
      'no': noList,
      'uncertain': uncertainList,
    };
  }
}

class _RespondentEntry {
  final String name;
  final String? reason;

  _RespondentEntry({
    required this.name,
    this.reason,
  });
}
