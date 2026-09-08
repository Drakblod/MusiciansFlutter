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

class MemberResultItem {
  final String userId;
  final String displayName;
  final String? instrument;
  final String? reason;
  final EventResponseStatus responseStatus;

  MemberResultItem({
    required this.userId,
    required this.displayName,
    this.instrument,
    this.reason,
    required this.responseStatus,
  });
}

class SubstituteResultItem {
  final String slotId;
  final String assignedUserId;
  final String substituteName;
  final String instrument;
  final String? replacedMemberName;
  final bool isFromLegacyExternalInvitee;

  SubstituteResultItem({
    required this.slotId,
    required this.assignedUserId,
    required this.substituteName,
    required this.instrument,
    this.replacedMemberName,
    this.isFromLegacyExternalInvitee = false,
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
  bool _isLoading = true;
  String? _errorMessage;
  List<BandEvent> _linkedSubEvents = [];

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

  void _subscribeToEvent([String? eventId]) {
    _eventSubscription?.cancel();
    final targetId = eventId ?? _event?.id ?? widget.eventId;
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

  void _selectOccurrence(BandEvent occurrence) {
    if (_event?.id == occurrence.id) return;
    setState(() {
      _event = occurrence;
    });
    if (occurrence.id != null) {
      _subscribeToEvent(occurrence.id!);
    }
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

      // If _event is null, fetch it from band events list
      if (_event == null) {
        final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);
        final found = allEvents.where((e) => e.id == widget.eventId);
        if (found.isNotEmpty) {
          _event = found.first;
        }
      }

      // Check linked sub events for grouped/multi-part events
      if (_event != null) {
        final allEvents = await appState.firebaseService.getBandEventsListAsync(widget.bandId);
        String normalizeTitle(String rawTitle) {
          return rawTitle
              .replaceAll(RegExp(r'\s*[\-\(]?\s*(Part|Date|Day)\s*\d+[\)]?', caseSensitive: false), '')
              .trim()
              .toLowerCase();
        }

        final parentId = _event!.parentEventId;
        final currentId = _event!.id ?? widget.eventId;
        final hasChildEvents = allEvents.any((e) => e.parentEventId == currentId);
        final isMulti = _event!.eventType.toLowerCase().contains('multiple') ||
            hasChildEvents ||
            (parentId != null && parentId.isNotEmpty);

        final effectiveParentId = (parentId != null && parentId.isNotEmpty)
            ? parentId
            : (isMulti ? currentId : null);

        if (effectiveParentId != null && effectiveParentId.isNotEmpty) {
          final explicitChildren = allEvents
              .where((e) => e.parentEventId == effectiveParentId && e.id != effectiveParentId)
              .toList();

          if (explicitChildren.isNotEmpty) {
            // The parent BandEvent is a group/header. Render only real playable child occurrences.
            _linkedSubEvents = explicitChildren;
          } else {
            _linkedSubEvents = allEvents
                .where((e) => e.parentEventId == effectiveParentId || e.id == effectiveParentId)
                .toList();
          }
        } else {
          final normTarget = normalizeTitle(_event!.title);
          _linkedSubEvents = allEvents.where((e) {
            final isParentHeader = allEvents.any((child) => child.parentEventId == e.id);
            if (isParentHeader) return false;
            return normalizeTitle(e.title) == normTarget;
          }).toList();
        }

        _linkedSubEvents.sort((a, b) {
          final seqA = a.subEventSequence ?? 0;
          final seqB = b.subEventSequence ?? 0;
          if (seqA != seqB) return seqA.compareTo(seqB);
          final aTime = DateTime.tryParse(a.startDateTime) ?? DateTime.now();
          final bTime = DateTime.tryParse(b.startDateTime) ?? DateTime.now();
          return aTime.compareTo(bTime);
        });

        // If current _event is the synthetic parent header, default to the first real child occurrence
        if (_linkedSubEvents.isNotEmpty &&
            !_linkedSubEvents.any((e) => e.id == _event!.id)) {
          _event = _linkedSubEvents.first;
          if (_event!.id != null) {
            _subscribeToEvent(_event!.id!);
          }
        }
      }

      // Collect user IDs for profile caching across all occurrences
      final Set<String> userIdsToFetch = {};
      for (final m in _members) {
        if (m.userId != null && m.userId!.isNotEmpty) {
          userIdsToFetch.add(m.userId!);
        }
      }
      final eventsToCache = _linkedSubEvents.isNotEmpty
          ? _linkedSubEvents
          : (_event != null ? [_event!] : <BandEvent>[]);
      for (final ev in eventsToCache) {
        for (final k in ev.responses.keys) {
          if (k.isNotEmpty) userIdsToFetch.add(k);
        }
        for (final k in ev.externalInvitees.keys) {
          if (k.isNotEmpty) userIdsToFetch.add(k);
        }
        for (final sub in ev.substituteAssignments.values) {
          if (sub.assignedUserId.isNotEmpty) userIdsToFetch.add(sub.assignedUserId);
          if (sub.replacedMemberId != null && sub.replacedMemberId!.isNotEmpty) {
            userIdsToFetch.add(sub.replacedMemberId!);
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

    // 1. Process regular band members
    final regularMemberResults = <EventResponseStatus, List<MemberResultItem>>{
      EventResponseStatus.yes: [],
      EventResponseStatus.no: [],
      EventResponseStatus.uncertain: [],
      EventResponseStatus.noAnswer: [],
    };

    final Set<String> regularUserIds = {};
    for (final member in _members) {
      final userId = member.userId;
      if (userId == null || userId.isEmpty) continue;
      regularUserIds.add(userId);

      final profile = _cachedProfiles[userId];
      final displayName = profile?.displayName ?? profile?.nickname ?? member.nickname ?? 'Unknown Member';
      final instrument = profile?.mainInstrument ?? member.role;

      final response = event.responses[userId];
      final status = classifyEventResponse(response?.status);
      final reason = (response?.uncertainReason != null && response!.uncertainReason!.trim().isNotEmpty)
          ? response.uncertainReason!.trim()
          : (response?.comment != null && response!.comment!.trim().isNotEmpty)
              ? response.comment!.trim()
              : null;

      regularMemberResults[status]!.add(
        MemberResultItem(
          userId: userId,
          displayName: displayName,
          instrument: instrument,
          reason: status == EventResponseStatus.uncertain ? reason : null,
          responseStatus: status,
        ),
      );
    }

    // 2. Identify additional/former unclassified responses
    final unclassifiedResponses = <MemberResultItem>[];
    for (final entry in event.responses.entries) {
      final userId = entry.key;
      if (regularUserIds.contains(userId)) continue;
      if (event.externalInvitees.containsKey(userId)) continue;

      final profile = _cachedProfiles[userId];
      final displayName = profile?.displayName ?? profile?.nickname ?? 'Recorded User ($userId)';
      final status = classifyEventResponse(entry.value.status);
      final reason = entry.value.uncertainReason ?? entry.value.comment;

      unclassifiedResponses.add(
        MemberResultItem(
          userId: userId,
          displayName: displayName,
          reason: reason,
          responseStatus: status,
        ),
      );
    }

    // 3. Process confirmed substitutes
    final confirmedSubs = <SubstituteResultItem>[];
    final Set<String> revokedSlotOrRequestIds = {};
    final Set<String> revokedUserSlotKeys = {};
    final Set<String> claimedSlotOrRequestIds = {};

    for (final entry in event.substituteAssignments.entries) {
      final slotId = entry.key;
      final sub = entry.value;
      final s = sub.status.trim().toLowerCase();
      final isRevokedOrCancelled = s == 'revoked' ||
          s == 'cancelled' ||
          s == 'canceled' ||
          s == 'unassigned' ||
          s == 'published' ||
          s == 'draft' ||
          s == 'open';

      if (isRevokedOrCancelled) {
        revokedSlotOrRequestIds.add(slotId);
        if (sub.subRequestId != null && sub.subRequestId!.trim().isNotEmpty) {
          revokedSlotOrRequestIds.add(sub.subRequestId!.trim());
        }
        if (sub.assignedUserId.trim().isNotEmpty) {
          final uid = sub.assignedUserId.trim();
          revokedUserSlotKeys.add('$uid|$slotId');
          if (sub.subRequestId != null && sub.subRequestId!.trim().isNotEmpty) {
            revokedUserSlotKeys.add('$uid|${sub.subRequestId!.trim()}');
          }
          revokedUserSlotKeys.add('$uid|');
        }
      }
    }

    // 3a. Explicit canonical substituteAssignments
    for (final entry in event.substituteAssignments.entries) {
      final slotId = entry.key;
      final sub = entry.value;
      if (!sub.isConfirmedAssignment) continue;

      final profile = _cachedProfiles[sub.assignedUserId];
      final name = (sub.assignedUserName != null && sub.assignedUserName!.trim().isNotEmpty)
          ? sub.assignedUserName!.trim()
          : (profile?.displayName ?? profile?.nickname ?? 'Substitute');
      final instrument = (sub.instrument != null && sub.instrument!.trim().isNotEmpty)
          ? sub.instrument!.trim()
          : (profile?.mainInstrument ?? 'Musician');

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
      if (sub.subRequestId != null && sub.subRequestId!.trim().isNotEmpty) {
        claimedSlotOrRequestIds.add('${sub.assignedUserId.trim()}|${sub.subRequestId!.trim()}');
      }

      confirmedSubs.add(
        SubstituteResultItem(
          slotId: slotId,
          assignedUserId: sub.assignedUserId.trim(),
          substituteName: name,
          instrument: instrument,
          replacedMemberName: replacedName,
          isFromLegacyExternalInvitee: false,
        ),
      );
    }

    // 3b. Legacy fallback from externalInvitees
    for (final entry in event.externalInvitees.entries) {
      final userId = entry.key.trim();
      final invitee = entry.value;

      final isSubSource = invitee.source == 'subRequest' ||
          (invitee.subRequestId != null && invitee.subRequestId!.trim().isNotEmpty);
      final isAttending = classifyEventResponse(invitee.status) == EventResponseStatus.yes;

      if (!isSubSource || !isAttending) continue;

      final subReqId = invitee.subRequestId?.trim();

      // Check if this externalInvitee corresponds to an already claimed canonical slot
      final isAlreadyClaimed = (subReqId != null && claimedSlotOrRequestIds.contains(subReqId)) ||
          claimedSlotOrRequestIds.contains('$userId|$subReqId') ||
          (subReqId == null && claimedSlotOrRequestIds.any((k) => k.startsWith('$userId|')));
      if (isAlreadyClaimed) continue;

      // Check if this externalInvitee corresponds to an authoritative revoked / cancelled slot
      final isRevoked = (subReqId != null && revokedSlotOrRequestIds.contains(subReqId)) ||
          revokedUserSlotKeys.contains('$userId|$subReqId') ||
          revokedUserSlotKeys.contains('$userId|');
      if (isRevoked) {
        // Authoritative revoked/cancelled record takes precedence over stale external-invitee record!
        continue;
      }

      final profile = _cachedProfiles[userId];
      final name = (invitee.displayName != null && invitee.displayName!.trim().isNotEmpty)
          ? invitee.displayName!.trim()
          : (profile?.displayName ?? profile?.nickname ?? 'Substitute');
      final instrument = (invitee.instrument != null && invitee.instrument!.trim().isNotEmpty)
          ? invitee.instrument!.trim()
          : (profile?.mainInstrument ?? 'Musician');

      final effectiveSlotId = (subReqId != null && subReqId.isNotEmpty) ? subReqId : 'legacy_$userId';
      claimedSlotOrRequestIds.add(effectiveSlotId);
      claimedSlotOrRequestIds.add('$userId|$effectiveSlotId');

      confirmedSubs.add(
        SubstituteResultItem(
          slotId: effectiveSlotId,
          assignedUserId: userId,
          substituteName: name,
          instrument: instrument,
          replacedMemberName: null,
          isFromLegacyExternalInvitee: true,
        ),
      );
    }

    // 4. Non-substitute external guests (if any)
    final nonSubExternalGuests = <MemberResultItem>[];
    for (final entry in event.externalInvitees.entries) {
      final userId = entry.key.trim();
      final invitee = entry.value;
      final isSubSource = invitee.source == 'subRequest' ||
          (invitee.subRequestId != null && invitee.subRequestId!.trim().isNotEmpty);

      // Exclude ALL sub-request invitees from external guests
      if (isSubSource) continue;

      final profile = _cachedProfiles[userId];
      final name = invitee.displayName ?? profile?.displayName ?? profile?.nickname ?? 'Guest';
      final status = classifyEventResponse(invitee.status);

      nonSubExternalGuests.add(
        MemberResultItem(
          userId: userId,
          displayName: name,
          instrument: invitee.instrument,
          reason: invitee.comment,
          responseStatus: status,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        // Multi-Part / Date Switcher (for grouped events)
        if (_linkedSubEvents.length > 1) ...[
          _buildDateSwitcher(event),
          const SizedBox(height: 12),
        ],

        // Event Header & Details Card
        _buildEventHeaderCard(event),
        const SizedBox(height: 20),

        // Section: REGULAR BAND MEMBERS
        _buildRegularBandMembersSection(regularMemberResults),
        const SizedBox(height: 20),

        // Section: ADDITIONAL RECORDED RESPONSES (if any former/unclassified users responded)
        if (unclassifiedResponses.isNotEmpty) ...[
          _buildUnclassifiedResponsesSection(unclassifiedResponses),
          const SizedBox(height: 20),
        ],

        // Section: SUBSTITUTES
        _buildSubstitutesSection(confirmedSubs),
        const SizedBox(height: 20),

        // Section: EXTERNAL GUESTS (if any non-substitute invitees exist)
        if (nonSubExternalGuests.isNotEmpty) ...[
          _buildExternalGuestsSection(nonSubExternalGuests),
          const SizedBox(height: 20),
        ],

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildDateSwitcher(BandEvent currentEvent) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF16132D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat_rounded, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 6),
              Text(
                "SWITCH EVENT OCCURRENCE (${_linkedSubEvents.length} PARTS):",
                style: GoogleFonts.outfit(
                  fontSize: 10.5,
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
                final isCurrent = sub.id == currentEvent.id;
                final subStart = DateTime.tryParse(sub.startDateTime)?.toLocal() ?? DateTime.now();
                final dateLabel = DateFormat('EEE, MMM d').format(subStart);
                final seqStr = sub.subEventSequence != null ? 'Part ${sub.subEventSequence}' : sub.title;

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: AnimatedTapDetector(
                    onTap: () {
                      _selectOccurrence(sub);
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
                            color: isCurrent ? Colors.white : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "$seqStr ($dateLabel)",
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? Colors.white : AppTheme.textSecondary,
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
    );
  }

  Widget _buildEventHeaderCard(BandEvent event) {
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? DateTime.now();

    final isSameDay = startLocal.year == endLocal.year &&
        startLocal.month == endLocal.month &&
        startLocal.day == endLocal.day;

    String dateStr;
    if (isSameDay) {
      dateStr = '${DateFormat('EEEE, MMM d, yyyy').format(startLocal)} • ${DateFormat('HH:mm').format(startLocal)} – ${DateFormat('HH:mm').format(endLocal)}';
    } else {
      dateStr = '${DateFormat('EEE, MMM d, yyyy HH:mm').format(startLocal)} – ${DateFormat('EEE, MMM d, yyyy HH:mm').format(endLocal)}';
    }

    IconData eventIcon;
    switch (event.eventType.toLowerCase()) {
      case 'rehearsal':
        eventIcon = Icons.music_note_rounded;
        break;
      case 'concert':
      case 'gig':
      case 'club gig':
        eventIcon = Icons.campaign_rounded;
        break;
      case 'recording session':
        eventIcon = Icons.mic_rounded;
        break;
      case 'meeting':
        eventIcon = Icons.forum_rounded;
        break;
      default:
        eventIcon = Icons.event_available_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge & status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(eventIcon, color: AppTheme.primaryAccent, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      event.eventType.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (event.isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'FINALIZED',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            event.title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          // Date and Time
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: AppTheme.textSecondary, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dateStr,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                ),
              ),
            ],
          ),

          // Location
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.location,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],

          // Description
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                event.description,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegularBandMembersSection(
    Map<EventResponseStatus, List<MemberResultItem>> groups,
  ) {
    final yesList = groups[EventResponseStatus.yes]!;
    final noList = groups[EventResponseStatus.no]!;
    final uncertainList = groups[EventResponseStatus.uncertain]!;
    final noAnswerList = groups[EventResponseStatus.noAnswer]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'REGULAR BAND MEMBERS',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryAccent,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${_members.length} members',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Based on current band roster',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
          ),
          child: Column(
            children: [
              // Exact order: 1. YES, 2. NO, 3. UNCERTAIN, 4. NO ANSWER
              _buildResponseGroupTile(
                title: 'YES',
                items: yesList,
                color: AppTheme.success,
                icon: Icons.check_circle_rounded,
              ),
              const Divider(color: Color(0xFF231F45), height: 1),
              _buildResponseGroupTile(
                title: 'NO',
                items: noList,
                color: AppTheme.danger,
                icon: Icons.cancel_rounded,
              ),
              const Divider(color: Color(0xFF231F45), height: 1),
              _buildResponseGroupTile(
                title: 'UNCERTAIN',
                items: uncertainList,
                color: AppTheme.warning,
                icon: Icons.help_rounded,
                isUncertain: true,
              ),
              const Divider(color: Color(0xFF231F45), height: 1),
              _buildResponseGroupTile(
                title: 'NO ANSWER',
                items: noAnswerList,
                color: AppTheme.textSecondary,
                icon: Icons.remove_circle_outline_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResponseGroupTile({
    required String title,
    required List<MemberResultItem> items,
    required Color color,
    required IconData icon,
    bool isUncertain = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Heading (ALWAYS visible, including 0 count)
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                '$title (${items.length})',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Member list or None
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 4),
              child: Text(
                'None',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Text(
                        item.displayName.isNotEmpty ? item.displayName[0].toUpperCase() : 'M',
                        style: GoogleFonts.inter(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.displayName,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.instrument != null && item.instrument!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '•  ${item.instrument}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // For UNCERTAIN: display the reason underneath the name
                          if (isUncertain && item.reason != null && item.reason!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              '"${item.reason}"',
                              style: GoogleFonts.inter(
                                fontSize: 12,
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

  Widget _buildUnclassifiedResponsesSection(List<MemberResultItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADDITIONAL RECORDED RESPONSES',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryAccent,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Responses from former or unlisted accounts not in current band roster',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
          ),
          child: Column(
            children: items.map((item) {
              Color statusColor;
              String statusLabel;
              switch (item.responseStatus) {
                case EventResponseStatus.yes:
                  statusColor = AppTheme.success;
                  statusLabel = 'YES';
                  break;
                case EventResponseStatus.no:
                  statusColor = AppTheme.danger;
                  statusLabel = 'NO';
                  break;
                case EventResponseStatus.uncertain:
                  statusColor = AppTheme.warning;
                  statusLabel = 'UNCERTAIN';
                  break;
                case EventResponseStatus.noAnswer:
                  statusColor = AppTheme.textSecondary;
                  statusLabel = 'NO ANSWER';
                  break;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (item.reason != null && item.reason!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '"${item.reason}"',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSubstitutesSection(List<SubstituteResultItem> confirmedSubs) {
    final distinctPeopleCount = confirmedSubs.map((s) => s.assignedUserId).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SUBSTITUTES',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryAccent,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${confirmedSubs.length} ${confirmedSubs.length == 1 ? 'slot' : 'slots'} ($distinctPeopleCount ${distinctPeopleCount == 1 ? 'person' : 'people'})',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Confirmed substitute slot assignments for this event',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),

        if (confirmedSubs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
            ),
            child: Text(
              'No substitutes assigned',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
            ),
            child: Column(
              children: confirmedSubs.asMap().entries.map((entry) {
                final index = entry.key;
                final sub = entry.value;
                final isLast = index == confirmedSubs.length - 1;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.18),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        sub.substituteName,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Assigned',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  sub.instrument,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppTheme.primaryAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (sub.replacedMemberName != null && sub.replacedMemberName!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Replacing ${sub.replacedMemberName}',
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
                    ),
                    if (!isLast)
                      const Divider(color: Color(0xFF231F45), height: 1),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildExternalGuestsSection(List<MemberResultItem> guests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXTERNAL GUESTS',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryAccent,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
          ),
          child: Column(
            children: guests.map((guest) {
              Color statusColor;
              String statusLabel;
              switch (guest.responseStatus) {
                case EventResponseStatus.yes:
                  statusColor = AppTheme.success;
                  statusLabel = 'Attending';
                  break;
                case EventResponseStatus.no:
                  statusColor = AppTheme.danger;
                  statusLabel = 'Declined';
                  break;
                case EventResponseStatus.uncertain:
                  statusColor = AppTheme.warning;
                  statusLabel = 'Maybe';
                  break;
                case EventResponseStatus.noAnswer:
                  statusColor = Colors.grey;
                  statusLabel = 'Pending';
                  break;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guest.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (guest.instrument != null && guest.instrument!.isNotEmpty)
                            Text(
                              guest.instrument!,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
