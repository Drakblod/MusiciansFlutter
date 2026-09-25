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

class MemberResultItem {
  final String userId;
  final String displayName;
  final String? primarySkill;
  final String? reason;
  final EventResponseStatus responseStatus;

  MemberResultItem({
    required this.userId,
    required this.displayName,
    this.primarySkill,
    this.reason,
    required this.responseStatus,
  });
}

class SubstituteResultItem {
  final String slotId;
  final String assignedUserId;
  final String substituteName;
  final String primarySkill;
  final String? replacedMemberName;
  final bool isFromLegacyExternalInvitee;

  SubstituteResultItem({
    required this.slotId,
    required this.assignedUserId,
    required this.substituteName,
    required this.primarySkill,
    this.replacedMemberName,
    this.isFromLegacyExternalInvitee = false,
  });
}

class _EventResultScheduleItem {
  final int index;
  final bool isMain;
  final String? scheduleItemId;
  final String type;
  final String title;
  final String dateStr;
  final String timeStr;
  final String location;
  final List<MemberResultItem> yesMembers;
  final List<MemberResultItem> noMembers;
  final List<MemberResultItem> uncertainMembers;
  final List<MemberResultItem> noAnswerMembers;
  final List<SubstituteResultItem> substitutes;

  _EventResultScheduleItem({
    required this.index,
    required this.isMain,
    this.scheduleItemId,
    required this.type,
    required this.title,
    required this.dateStr,
    required this.timeStr,
    required this.location,
    required this.yesMembers,
    required this.noMembers,
    required this.uncertainMembers,
    required this.noAnswerMembers,
    required this.substitutes,
  });
}

class EventResultsPage extends StatefulWidget {
  final String bandId;
  final String eventId;
  final BandEvent? initialEvent;

  const EventResultsPage({
    super.key,
    required this.bandId,
    required this.eventId,
    this.initialEvent,
  });

  @override
  State<EventResultsPage> createState() => _EventResultsPageState();
}

class _EventResultsPageState extends State<EventResultsPage> {
  BandEvent? _event;
  StreamSubscription<BandEvent?>? _eventSubscription;
  List<BandMember> _members = [];
  Map<String, UserProfile> _cachedProfiles = {};
  List<BandEvent> _linkedSubEvents = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Active expanded group key across schedule items (e.g. '0_YES', '1_UNCERTAIN')
  String? _activeGroupKey;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _subscribeToEvent();
    _loadData();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToEvent() {
    _eventSubscription?.cancel();
    final targetId = _event?.id ?? widget.eventId;
    final appState = Provider.of<AppState>(context, listen: false);
    _eventSubscription = appState.firebaseService
        .subscribeToBandEvent(widget.bandId, targetId)
        .listen((updatedEvent) {
      if (updatedEvent != null && mounted) {
        setState(() {
          _event = updatedEvent;
        });
      }
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _event == null;
      _errorMessage = null;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);

      // Load band members (current roster)
      final members = await appState.firebaseService.getBandMembersAsync(widget.bandId);
      _members = members;

      // Load band events for occurrence switcher & event fallback
      final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);
      if (_event == null) {
        final found = allEvents.where((e) => e.id == widget.eventId);
        if (found.isNotEmpty) {
          _event = found.first;
        }
      }

      // Check linked occurrences
      final current = _event;
      if (current != null) {
        final parentId = current.parentEventId;
        if (parentId != null && parentId.isNotEmpty) {
          final linked = allEvents.where((e) => e.parentEventId == parentId && e.id != parentId).toList();
          linked.sort((a, b) => (a.subEventSequence ?? 0).compareTo(b.subEventSequence ?? 0));
          _linkedSubEvents = linked;
        } else {
          final children = allEvents.where((e) => e.parentEventId == current.id).toList();
          if (children.isNotEmpty) {
            final linked = children;
            linked.sort((a, b) => (a.subEventSequence ?? 0).compareTo(b.subEventSequence ?? 0));
            _linkedSubEvents = linked;
          } else {
            _linkedSubEvents = [];
          }
        }
      }

      // Collect user IDs for profile caching
      final Set<String> userIdsToFetch = {};
      for (final m in _members) {
        if (m.userId != null && m.userId!.isNotEmpty) {
          userIdsToFetch.add(m.userId!);
        }
      }

      if (_event != null) {
        for (final k in _event!.responses.keys) {
          if (k.isNotEmpty) userIdsToFetch.add(k);
        }
        for (final k in _event!.externalInvitees.keys) {
          if (k.isNotEmpty) userIdsToFetch.add(k);
        }
        for (final sub in _event!.substituteAssignments.values) {
          if (sub.assignedUserId.isNotEmpty) userIdsToFetch.add(sub.assignedUserId);
          if (sub.replacedMemberId != null && sub.replacedMemberId!.isNotEmpty) {
            userIdsToFetch.add(sub.replacedMemberId!);
          }
        }
        for (final userMap in _event!.scheduleResponses.values) {
          for (final uid in userMap.keys) {
            if (uid.isNotEmpty) userIdsToFetch.add(uid);
          }
        }
      }

      final Map<String, UserProfile> profiles = {};
      await Future.wait(userIdsToFetch.map((userId) async {
        try {
          final profile = await appState.firebaseService.getUserProfileAsync(userId);
          if (profile != null) {
            profiles[userId] = profile;
          }
        } catch (_) {}
      }));

      if (mounted) {
        setState(() {
          _cachedProfiles = profiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[EventResultsPage] Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load event results. Please try again.';
        });
      }
    }
  }

  String _getPrimarySkill(String userId, [String? fallbackRole]) {
    final profile = _cachedProfiles[userId];
    if (profile != null) {
      if (profile.mainInstrument != null && profile.mainInstrument!.trim().isNotEmpty) {
        return profile.mainInstrument!.trim();
      }
      if (profile.instruments.isNotEmpty && profile.instruments.first.trim().isNotEmpty) {
        return profile.instruments.first.trim();
      }
      if (profile.collabRoles.isNotEmpty && profile.collabRoles.first.trim().isNotEmpty) {
        return profile.collabRoles.first.trim();
      }
    }
    if (fallbackRole != null &&
        fallbackRole.trim().isNotEmpty &&
        fallbackRole.trim().toLowerCase() != 'member' &&
        fallbackRole.trim().toLowerCase() != 'leader' &&
        fallbackRole.trim().toLowerCase() != 'admin') {
      return fallbackRole.trim();
    }
    return '';
  }

  String _formatDateRange(String? startStr, String? endStr) {
    if (startStr == null || startStr.isEmpty) return 'Date TBA';
    final start = DateTime.tryParse(startStr)?.toLocal();
    final end = (endStr != null && endStr.isNotEmpty) ? DateTime.tryParse(endStr)?.toLocal() : null;
    if (start == null) return 'Date TBA';

    if (end == null || (start.year == end.year && start.month == end.month && start.day == end.day)) {
      return DateFormat('EEEE, MMMM d, yyyy').format(start);
    } else {
      return '${DateFormat('EEE, MMM d, yyyy').format(start)} – ${DateFormat('EEE, MMM d, yyyy').format(end)}';
    }
  }

  List<_EventResultScheduleItem> _buildResultScheduleItems(BandEvent event) {
    final List<_EventResultScheduleItem> items = [];

    // Confirmed substitutes for the event
    final confirmedSubs = <SubstituteResultItem>[];
    final Set<String> claimedSlotOrRequestIds = {};
    final Set<String> revokedOrCancelledIds = {};

    for (final entry in event.substituteAssignments.entries) {
      final slotId = entry.key;
      final sub = entry.value;

      if (sub.status == 'revoked' || sub.status == 'cancelled') {
        if (sub.assignedUserId.trim().isNotEmpty) revokedOrCancelledIds.add(sub.assignedUserId.trim());
        if (sub.subRequestId != null && sub.subRequestId!.trim().isNotEmpty) {
          revokedOrCancelledIds.add(sub.subRequestId!.trim());
        }
        revokedOrCancelledIds.add(slotId);
        continue;
      }

      if (!sub.isConfirmedAssignment) continue;

      final profile = _cachedProfiles[sub.assignedUserId];
      final name = (sub.assignedUserName != null && sub.assignedUserName!.trim().isNotEmpty)
          ? sub.assignedUserName!.trim()
          : (profile?.displayName ?? profile?.nickname ?? 'Substitute');
      final primarySkill = (sub.instrument != null && sub.instrument!.trim().isNotEmpty)
          ? sub.instrument!.trim()
          : _getPrimarySkill(sub.assignedUserId);

      String? replacedName = sub.replacedMemberName;
      if ((replacedName == null || replacedName.trim().isEmpty) && sub.replacedMemberId != null) {
        final repProfile = _cachedProfiles[sub.replacedMemberId];
        replacedName = repProfile?.displayName ?? repProfile?.nickname;
      }

      claimedSlotOrRequestIds.add(slotId);
      if (sub.subRequestId != null && sub.subRequestId!.trim().isNotEmpty) {
        claimedSlotOrRequestIds.add(sub.subRequestId!.trim());
      }
      claimedSlotOrRequestIds.add('${sub.assignedUserId.trim()}|$slotId');

      confirmedSubs.add(
        SubstituteResultItem(
          slotId: slotId,
          assignedUserId: sub.assignedUserId.trim(),
          substituteName: name,
          primarySkill: primarySkill,
          replacedMemberName: replacedName,
          isFromLegacyExternalInvitee: false,
        ),
      );
    }

    for (final entry in event.externalInvitees.entries) {
      final userId = entry.key.trim();
      final invitee = entry.value;
      final isSubSource = invitee.source == 'subRequest' ||
          (invitee.subRequestId != null && invitee.subRequestId!.trim().isNotEmpty);
      final isAttending = classifyEventResponse(invitee.status) == EventResponseStatus.yes;

      if (isSubSource && isAttending) {
        final isRevoked = revokedOrCancelledIds.contains(userId) ||
            (invitee.subRequestId != null && revokedOrCancelledIds.contains(invitee.subRequestId!.trim()));
        if (isRevoked) continue;

        final isAlreadyClaimed = claimedSlotOrRequestIds.contains(userId) ||
            (invitee.subRequestId != null && claimedSlotOrRequestIds.contains(invitee.subRequestId!.trim())) ||
            claimedSlotOrRequestIds.contains('$userId|${invitee.subRequestId ?? ''}');

        if (!isAlreadyClaimed) {
          final profile = _cachedProfiles[userId];
          final name = invitee.displayName ?? profile?.displayName ?? profile?.nickname ?? 'Substitute';
          final primarySkill = (invitee.instrument != null && invitee.instrument!.trim().isNotEmpty)
              ? invitee.instrument!.trim()
              : _getPrimarySkill(userId);

          confirmedSubs.add(
            SubstituteResultItem(
              slotId: invitee.subRequestId ?? userId,
              assignedUserId: userId,
              substituteName: name,
              primarySkill: primarySkill,
              isFromLegacyExternalInvitee: true,
            ),
          );
        }
      }
    }

    if (event.rehearsals.isEmpty) {
      // 1. Process Single Event (No attached schedule items)
      final mainYes = <MemberResultItem>[];
      final mainNo = <MemberResultItem>[];
      final mainUncertain = <MemberResultItem>[];
      final mainNoAnswer = <MemberResultItem>[];

      final Set<String> processedUserIds = {};

      for (final member in _members) {
        final uid = member.userId;
        if (uid == null || uid.isEmpty) continue;
        processedUserIds.add(uid);

        final profile = _cachedProfiles[uid];
        final name = profile?.displayName ??
            profile?.nickname ??
            ((member.nickname != null && member.nickname!.trim().toLowerCase() != 'leader') ? member.nickname : null) ??
            'Unknown Member';
        final primarySkill = _getPrimarySkill(uid, member.role);

        final resp = event.responses[uid];
        final status = classifyEventResponse(resp?.status);
        final reason = resp?.uncertainReason ?? resp?.comment;

        final item = MemberResultItem(
          userId: uid,
          displayName: name,
          primarySkill: primarySkill.isNotEmpty ? primarySkill : null,
          reason: status == EventResponseStatus.uncertain ? reason : null,
          responseStatus: status,
        );

        if (status == EventResponseStatus.yes) {
          mainYes.add(item);
        } else if (status == EventResponseStatus.no) {
          mainNo.add(item);
        } else if (status == EventResponseStatus.uncertain) {
          mainUncertain.add(item);
        } else {
          mainNoAnswer.add(item);
        }
      }

      // External invitees who are not substitutes
      for (final entry in event.externalInvitees.entries) {
        final uid = entry.key;
        if (processedUserIds.contains(uid)) continue;
        final invitee = entry.value;
        final isSub = invitee.source == 'subRequest' || (invitee.subRequestId != null && invitee.subRequestId!.isNotEmpty);
        if (isSub) continue;

        final profile = _cachedProfiles[uid];
        final name = invitee.displayName ?? profile?.displayName ?? profile?.nickname ?? 'Guest';
        final primarySkill = (invitee.instrument != null && invitee.instrument!.isNotEmpty)
            ? invitee.instrument!
            : _getPrimarySkill(uid);
        final status = classifyEventResponse(invitee.status);
        final reason = invitee.comment;

        final item = MemberResultItem(
          userId: uid,
          displayName: name,
          primarySkill: primarySkill.isNotEmpty ? primarySkill : null,
          reason: status == EventResponseStatus.uncertain ? reason : null,
          responseStatus: status,
        );

        if (status == EventResponseStatus.yes) {
          mainYes.add(item);
        } else if (status == EventResponseStatus.no) {
          mainNo.add(item);
        } else if (status == EventResponseStatus.uncertain) {
          mainUncertain.add(item);
        } else {
          mainNoAnswer.add(item);
        }
      }

      final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
      final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? DateTime.now();
      final mainDateStr = DateFormat('EEEE, MMMM d, yyyy').format(startLocal);
      final mainTimeStr = '${DateFormat('HH:mm').format(startLocal)} - ${DateFormat('HH:mm').format(endLocal)}';

      items.add(
        _EventResultScheduleItem(
          index: 0,
          isMain: true,
          scheduleItemId: null,
          type: event.eventType.isNotEmpty && event.eventType.toLowerCase() != 'event' ? event.eventType : 'Main Event',
          title: event.title,
          dateStr: mainDateStr,
          timeStr: mainTimeStr,
          location: event.location,
          yesMembers: mainYes,
          noMembers: mainNo,
          uncertainMembers: mainUncertain,
          noAnswerMembers: mainNoAnswer,
          substitutes: confirmedSubs,
        ),
      );
    } else {
      // 2. Process Attached Schedule Items (1..N) — parent container is NOT Event 1
      for (int i = 0; i < event.rehearsals.length; i++) {
        final rehearsal = event.rehearsals[i];
        final schedYes = <MemberResultItem>[];
        final schedNo = <MemberResultItem>[];
        final schedUncertain = <MemberResultItem>[];
        final schedNoAnswer = <MemberResultItem>[];

        final scheduleResponses = event.scheduleResponses[rehearsal.id] ?? {};

        for (final member in _members) {
          final uid = member.userId;
          if (uid == null || uid.isEmpty) continue;

          final profile = _cachedProfiles[uid];
          final name = profile?.displayName ??
              profile?.nickname ??
              ((member.nickname != null && member.nickname!.trim().toLowerCase() != 'leader') ? member.nickname : null) ??
              'Unknown Member';
          final primarySkill = _getPrimarySkill(uid, member.role);

          final resp = scheduleResponses[uid];
          final status = classifyEventResponse(resp?.status);
          final reason = resp?.uncertainReason ?? resp?.comment;

          final item = MemberResultItem(
            userId: uid,
            displayName: name,
            primarySkill: primarySkill.isNotEmpty ? primarySkill : null,
            reason: status == EventResponseStatus.uncertain ? reason : null,
            responseStatus: status,
          );

          if (status == EventResponseStatus.yes) {
            schedYes.add(item);
          } else if (status == EventResponseStatus.no) {
            schedNo.add(item);
          } else if (status == EventResponseStatus.uncertain) {
            schedUncertain.add(item);
          } else {
            schedNoAnswer.add(item);
          }
        }

        final parsedDate = DateTime.tryParse(rehearsal.date);
        final dateFormatted = parsedDate != null
            ? DateFormat('EEEE, MMMM d, yyyy').format(parsedDate)
            : rehearsal.date;
        final timeFormatted = (rehearsal.startTime.isNotEmpty && rehearsal.endTime.isNotEmpty)
            ? '${rehearsal.startTime} - ${rehearsal.endTime}'
            : (rehearsal.startTime.isNotEmpty ? rehearsal.startTime : '');
        final titleFormatted = rehearsal.title.isNotEmpty ? rehearsal.title : event.title;
        final typeFormatted = rehearsal.type.isNotEmpty ? rehearsal.type : 'Rehearsal';
        final locationFormatted = rehearsal.location.isNotEmpty ? rehearsal.location : event.location;

        items.add(
          _EventResultScheduleItem(
            index: i + 1,
            isMain: false,
            scheduleItemId: rehearsal.id,
            type: typeFormatted,
            title: titleFormatted,
            dateStr: dateFormatted,
            timeStr: timeFormatted,
            location: locationFormatted,
            yesMembers: schedYes,
            noMembers: schedNo,
            uncertainMembers: schedUncertain,
            noAnswerMembers: schedNoAnswer,
            substitutes: confirmedSubs,
          ),
        );
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Event Results',
        showBack: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _event == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      );
    }

    if (_errorMessage != null && _event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    final event = _event;
    if (event == null) {
      return Center(
        child: Text(
          'Event not found.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
        ),
      );
    }

    final scheduleItems = _buildResultScheduleItems(event);
    final hasMultipleEvents = event.rehearsals.isNotEmpty;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Linked Occurrences Switcher if multiple parts exist
          if (_linkedSubEvents.length > 1)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SWITCH EVENT OCCURRENCE (${_linkedSubEvents.length} PARTS)',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _linkedSubEvents.map((subEvent) {
                      final isSelected = subEvent.id == _event?.id;
                      final seq = subEvent.subEventSequence ?? (_linkedSubEvents.indexOf(subEvent) + 1);
                      return ChoiceChip(
                        label: Text('Part $seq (${subEvent.title})'),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryAccent.withOpacity(0.3),
                        backgroundColor: const Color(0xFF16132D),
                        labelStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected && mounted) {
                            setState(() {
                              _event = subEvent;
                              _activeGroupKey = null;
                            });
                            _subscribeToEvent();
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Event Title & Overview Header
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
                    if (event.isLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.success.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 12, color: AppTheme.success),
                            const SizedBox(width: 4),
                            Text(
                              'Finalized',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatDateRange(event.startDateTime, event.endDateTime),
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
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
                  const SizedBox(height: 8),
                  Text(
                    event.description,
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),

          // Render Results for Schedule Items (Single Event or Multi-Schedule)
          ...List.generate(scheduleItems.length, (itemIndex) {
            final item = scheduleItems[itemIndex];
            final itemHeader = hasMultipleEvents
                ? 'EVENT ${item.index} · ${item.type.toUpperCase()} · "${item.title}"'
                : 'ATTENDANCE RESPONSES';

            final yesKey = '${itemIndex}_YES';
            final noKey = '${itemIndex}_NO';
            final uncertainKey = '${itemIndex}_UNCERTAIN';
            final noAnswerKey = '${itemIndex}_NO_ANSWER';
            final subsKey = '${itemIndex}_SUBSTITUTES';

            final isYesActive = _activeGroupKey == yesKey;
            final isNoActive = _activeGroupKey == noKey;
            final isUncertainActive = _activeGroupKey == uncertainKey;
            final isNoAnswerActive = _activeGroupKey == noAnswerKey;
            final isSubsActive = _activeGroupKey == subsKey;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemHeader,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (hasMultipleEvents) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.timeStr.isNotEmpty
                          ? '${item.dateStr} • ${item.timeStr}'
                          : item.dateStr,
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Compact Single Row of Clickable Filter Pills (Scrollable for narrow screens)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildResultFilterPill(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'YES (${item.yesMembers.length})',
                          color: AppTheme.success,
                          isSelected: isYesActive,
                          onTap: () {
                            setState(() {
                              _activeGroupKey = isYesActive ? null : yesKey;
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildResultFilterPill(
                          icon: Icons.cancel_outlined,
                          label: 'NO (${item.noMembers.length})',
                          color: AppTheme.danger,
                          isSelected: isNoActive,
                          onTap: () {
                            setState(() {
                              _activeGroupKey = isNoActive ? null : noKey;
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildResultFilterPill(
                          icon: Icons.help_outline_rounded,
                          label: 'UNCERTAIN (${item.uncertainMembers.length})',
                          color: AppTheme.warning,
                          isSelected: isUncertainActive,
                          onTap: () {
                            setState(() {
                              _activeGroupKey = isUncertainActive ? null : uncertainKey;
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildResultFilterPill(
                          icon: Icons.radio_button_unchecked_rounded,
                          label: 'NO ANSWER (${item.noAnswerMembers.length})',
                          color: AppTheme.textSecondary,
                          isSelected: isNoAnswerActive,
                          onTap: () {
                            setState(() {
                              _activeGroupKey = isNoAnswerActive ? null : noAnswerKey;
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildResultFilterPill(
                          icon: Icons.person_search_outlined,
                          label: 'SUBSTITUTES (${item.substitutes.length})',
                          color: Colors.purpleAccent,
                          isSelected: isSubsActive,
                          onTap: () {
                            setState(() {
                              _activeGroupKey = isSubsActive ? null : subsKey;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // Expanded Member / Substitute List
                  if (isYesActive)
                    _buildMemberListContainer('YES Respondents (${item.yesMembers.length})', item.yesMembers, AppTheme.success),
                  if (isNoActive)
                    _buildMemberListContainer('NO Respondents (${item.noMembers.length})', item.noMembers, AppTheme.danger),
                  if (isUncertainActive)
                    _buildMemberListContainer('UNCERTAIN Respondents (${item.uncertainMembers.length})', item.uncertainMembers, AppTheme.warning),
                  if (isNoAnswerActive)
                    _buildMemberListContainer('NO ANSWER (${item.noAnswerMembers.length})', item.noAnswerMembers, AppTheme.textSecondary),
                  if (isSubsActive)
                    _buildSubstituteListContainer('Confirmed Substitutes (${item.substitutes.length})', item.substitutes, Colors.purpleAccent),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildResultFilterPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.25) : const Color(0xFF16132D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF2E2A4E),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? color : color.withOpacity(0.8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberListContainer(String title, List<MemberResultItem> list, Color color) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('No members in this category.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16132D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 8),
          ...list.map((m) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: color.withOpacity(0.2),
                    child: Text(
                      m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : 'M',
                      style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.displayName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (m.primarySkill != null && m.primarySkill!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  m.primarySkill!,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppTheme.primaryAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (m.reason != null && m.reason!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '"${m.reason!}"',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
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
    );
  }

  Widget _buildSubstituteListContainer(String title, List<SubstituteResultItem> list, Color color) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('No substitutes assigned.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16132D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 8),
          ...list.map((sub) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: color.withOpacity(0.2),
                    child: Text(
                      sub.substituteName.isNotEmpty ? sub.substituteName[0].toUpperCase() : 'S',
                      style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sub.substituteName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (sub.primarySkill.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sub.primarySkill,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.purpleAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (sub.replacedMemberName != null && sub.replacedMemberName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Replacing ${sub.replacedMemberName!}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
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
    );
  }
}
