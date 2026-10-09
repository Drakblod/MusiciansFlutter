import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
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
  final bool? _isMultiple;
  final List<SubRequest> requests;
  final DateTime earliestDate;

  GigGroup({
    required this.groupId,
    required this.title,
    this.bandName,
    this.location,
    this.description,
    this.payDetails,
    bool? isMultiple,
    required this.requests,
    required this.earliestDate,
  }) : _isMultiple = isMultiple;

  int get totalPositions => requests.length;
  int get filledPositions => requests.where((r) => r.status == 'assigned' || r.assignedUserId != null).length;
  int get eventCount {
    final eventIds = requests.map((r) => r.eventId ?? r.date ?? '').where((s) => s.isNotEmpty).toSet();
    return eventIds.isEmpty ? 1 : eventIds.length;
  }

  bool get isMultiple => _isMultiple ?? (requests.length > 1 || eventCount > 1);

  bool get isPaid => requests.any((r) => r.isPaid);

  String get formattedPayment {
    final paidReq = requests.firstWhere((r) => r.isPaid, orElse: () => requests.first);
    return paidReq.formattedPayAmount;
  }

  bool get isNewMember => requests.any((r) {
    final type = r.requestType?.trim().toLowerCase();
    if (type != null && type.isNotEmpty) {
      return type == 'new member';
    }
    return r.role?.trim().toLowerCase() == 'new member';
  });

  bool get isOther => requests.any((r) {
    final type = r.requestType?.trim().toLowerCase();
    if (type != null && type.isNotEmpty) {
      return type == 'other';
    }
    return r.role?.trim().toLowerCase() == 'other';
  });

  String get requestTypeLabel {
    if (isNewMember) return 'New Member Request';
    if (isOther) return 'Other Request';
    return 'Substitute Request';
  }

  List<String> get distinctRoles {
    final roles = <String>{};
    for (final r in requests) {
      if (r.voicePart != null && r.voicePart!.trim().isNotEmpty) {
        roles.add(r.voicePart!.trim());
      } else {
        final roleLower = r.role?.trim().toLowerCase();
        if (roleLower != null &&
            roleLower.isNotEmpty &&
            roleLower != 'substitute' &&
            roleLower != 'new member' &&
            roleLower != 'other') {
          roles.add(r.role!.trim());
        } else {
          roles.add('Musician');
        }
      }
    }
    return roles.toList();
  }

  String get roleInstrumentDisplay => distinctRoles.join(', ');
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
  final Set<String> _appliedGigIds = {};
  List<GigGroup> _substituteGigGroups = [];
  List<GigGroup> _newMemberGigGroups = [];
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
      final isFirstNewMember = first.role?.trim().toLowerCase() == 'new member';
      final defaultFallback = (first.requestType == 'New Member' || isFirstNewMember)
          ? 'New Member Request'
          : (first.requestType == 'Other' ? 'Other Request' : 'Substitute Request');

      final titleCandidate = first.eventTitle?.trim();
      final hasMeaningfulEventTitle = titleCandidate != null &&
          titleCandidate.isNotEmpty &&
          titleCandidate.toLowerCase() != 'event' &&
          titleCandidate.toLowerCase() != 'name of event';

      final groupTitle = (first.bandName != null && first.bandName!.trim().isNotEmpty)
          ? first.bandName!.trim()
          : (hasMeaningfulEventTitle
              ? titleCandidate
              : (first.role != null &&
                      first.role!.trim().isNotEmpty &&
                      first.role!.trim().toLowerCase() != 'substitute' &&
                      first.role!.trim().toLowerCase() != 'new member' &&
                      first.role!.trim().toLowerCase() != 'other'
                  ? first.role!.trim()
                  : (first.voicePart != null && first.voicePart!.trim().isNotEmpty
                      ? '${first.voicePart!.trim()} Needed'
                      : defaultFallback)));

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
          requests: reqs,
          earliestDate: earliest,
        ),
      );
    }

    groups.sort((a, b) => a.earliestDate.compareTo(b.earliestDate));
    return groups;
  }

  DateTime? _parseGigDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final str = raw.trim();
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return parsed.toLocal();
    try {
      if (str.contains('/')) {
        final parts = str.split('/');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          } else if (parts[2].length == 4) {
            final p0 = int.parse(parts[0]);
            final p1 = int.parse(parts[1]);
            final p2 = int.parse(parts[2]);
            if (p0 > 12) {
              return DateTime(p2, p1, p0);
            } else {
              return DateTime(p2, p0, p1);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isInstrumentMatch(String? requestedInstrument, List<String> userSkills) {
    final nonGenericSkills = userSkills.where((s) {
      final l = s.trim().toLowerCase();
      return l.isNotEmpty &&
          l != 'musician' &&
          l != 'browse musicians' &&
          l != 'browse profiles' &&
          l != 'browse_musicians' &&
          l != 'artist' &&
          l != 'band member';
    }).toList();

    if (nonGenericSkills.isEmpty) return true;
    if (requestedInstrument == null || requestedInstrument.trim().isEmpty) return true;

    final reqClean = requestedInstrument.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    final reqLower = requestedInstrument.trim().toLowerCase();

    for (final skill in nonGenericSkills) {
      final skillLower = skill.trim().toLowerCase();
      final skillClean = skillLower.replaceAll(RegExp(r'[\s\-_]'), '');
      if (skillLower.isEmpty) continue;

      if (skillLower == reqLower || skillClean == reqClean) return true;
      if (skillLower.contains(reqLower) || reqLower.contains(skillLower)) return true;
      if (skillClean.contains(reqClean) || reqClean.contains(skillClean)) return true;

      // Stem / instrument family matching
      if ((reqLower.contains('guitar') || reqLower.contains('gitarr')) &&
          (skillLower.contains('guitar') || skillLower.contains('gitarr'))) {
        return true;
      }
      if ((reqLower.contains('bass') || reqLower.contains('bas')) &&
          (skillLower.contains('bass') || skillLower.contains('bas'))) {
        return true;
      }
      if ((reqLower.contains('drum') || reqLower.contains('slagverk') || reqLower.contains('percussion') || reqLower.contains('trumm')) &&
          (skillLower.contains('drum') || skillLower.contains('slagverk') || skillLower.contains('percussion') || skillLower.contains('trumm'))) {
        return true;
      }
      if ((reqLower.contains('vocal') || reqLower.contains('sing') || reqLower.contains('sång') || reqLower.contains('sang') || reqLower.contains('voice') || reqLower.contains('kör')) &&
          (skillLower.contains('vocal') || skillLower.contains('sing') || skillLower.contains('sång') || skillLower.contains('sang') || skillLower.contains('voice') || skillLower.contains('kör'))) {
        return true;
      }
      if ((reqLower.contains('key') || reqLower.contains('piano') || reqLower.contains('synth') || reqLower.contains('klaviatur') || reqLower.contains('orgel')) &&
          (skillLower.contains('key') || skillLower.contains('piano') || skillLower.contains('synth') || skillLower.contains('klaviatur') || skillLower.contains('orgel'))) {
        return true;
      }
      if ((reqLower.contains('sax') || reqLower.contains('horn') || reqLower.contains('brass') || reqLower.contains('trumpet') || reqLower.contains('trombone') || reqLower.contains('blås')) &&
          (skillLower.contains('sax') || skillLower.contains('horn') || skillLower.contains('brass') || skillLower.contains('trumpet') || skillLower.contains('trombone') || skillLower.contains('blås'))) {
        return true;
      }
    }
    return false;
  }

  String _formatReqDateTime(SubRequest r) {
    String dStr = '';
    if (r.date != null && r.date!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(r.date!.trim());
      if (parsed != null) {
        dStr = DateFormat('EEE, MMM d').format(parsed);
      } else {
        dStr = r.date!.trim();
      }
    }
    final hasStart = r.startTime != null && r.startTime!.trim().isNotEmpty;
    final hasEnd = r.endTime != null && r.endTime!.trim().isNotEmpty;
    String tStr = '';
    if (hasStart && hasEnd) {
      tStr = '${r.startTime!.trim()} - ${r.endTime!.trim()}';
    } else if (hasStart) {
      tStr = r.startTime!.trim();
    } else if (hasEnd) {
      tStr = r.endTime!.trim();
    }

    if (dStr.isNotEmpty && tStr.isNotEmpty) {
      return '$dStr · $tStr';
    } else if (dStr.isNotEmpty) {
      return dStr;
    } else if (tStr.isNotEmpty) {
      return tStr;
    } else {
      return 'Not provided';
    }
  }

  Future<void> _loadSubRequests() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final list = await appState.firebaseService.getUserSubRequestFeedAsync();
      final currentUserId = appState.currentUserId;

      if (currentUserId != null) {
        try {
          final applied = await appState.firebaseService.getUserAppliedSubRequestIdsAsync(currentUserId);
          _appliedGigIds.addAll(applied);
        } catch (e) {
          debugPrint("Error fetching applied gig IDs: $e");
        }
      }

      final userProfile = appState.currentUserProfile;
      final List<String> userInstruments = [];
      if (userProfile != null) {
        userInstruments.addAll(userProfile.instruments);
        if (userProfile.mainInstrument != null && userProfile.mainInstrument!.trim().isNotEmpty) {
          userInstruments.addAll(userProfile.mainInstrument!.split(',').map((s) => s.trim()));
        }
        if (userProfile.userType != null && userProfile.userType!.trim().isNotEmpty) {
          userInstruments.add(userProfile.userType!.trim());
        }
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final List<SubRequest> upcomingSubstituteRequests = [];
      final List<SubRequest> upcomingNewMemberRequests = [];

      for (final gig in list) {
        final st = gig.status.toLowerCase();
        if (st == 'cancelled' || st == 'deleted' || st == 'closed') continue;

        if (gig.date != null && gig.date!.trim().isNotEmpty) {
          final gigDate = _parseGigDate(gig.date);
          if (gigDate != null) {
            final gigDay = DateTime(gigDate.year, gigDate.month, gigDate.day);
            if (gigDay.isBefore(today)) continue;
          }
        }

        final reqTypeLower = gig.requestType?.trim().toLowerCase();
        final roleLower = gig.role?.trim().toLowerCase();
        final isNewMember = reqTypeLower == 'new member' || (reqTypeLower == null && roleLower == 'new member');

        final instToCheck = (gig.voicePart != null && gig.voicePart!.trim().isNotEmpty)
            ? gig.voicePart
            : ((gig.role != null &&
                    gig.role!.trim().isNotEmpty &&
                    roleLower != 'substitute' &&
                    roleLower != 'new member' &&
                    roleLower != 'other')
                ? gig.role
                : gig.extraFields['instrument']?.toString());

        if (instToCheck != null && instToCheck.trim().isNotEmpty) {
          if (!_isInstrumentMatch(instToCheck, userInstruments)) continue;
        }

        if (isNewMember) {
          upcomingNewMemberRequests.add(gig);
        } else {
          // Substitute and Other belong under Substitute Requests tab
          upcomingSubstituteRequests.add(gig);
        }
      }

      setState(() {
        _substituteGigGroups = _groupSubRequests(upcomingSubstituteRequests);
        _newMemberGigGroups = _groupSubRequests(upcomingNewMemberRequests);
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
            final distinctSequences = group.requests.map((r) => r.eventSequence).whereType<int>().toSet();
            final distinctDates = group.requests.map((r) => r.date).where((d) => d != null && d.trim().isNotEmpty).toSet();
            final distinctEventIds = group.requests.map((r) => r.eventId).where((e) => e != null && e.trim().isNotEmpty).toSet();
            final distinctEventTitles = group.requests
                .map((r) => r.eventTitle?.trim())
                .where((t) => t != null && t.isNotEmpty)
                .cast<String>()
                .toSet();
            final bool hasMultipleDistinctEvents = group.eventCount > 1 ||
                distinctSequences.length > 1 ||
                distinctDates.length > 1 ||
                distinctEventIds.length > 1 ||
                distinctEventTitles.length > 1;

            String? resolvedEventType;
            for (final r in group.requests) {
              final ev = r.resolvedEventType;
              if (ev != null && ev.trim().isNotEmpty) {
                resolvedEventType = ev.trim();
                break;
              }
            }

            final groupDateTimeDisplay = group.requests.isNotEmpty
                ? _formatReqDateTime(group.requests.first)
                : 'Not provided';

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
                          if (group.isPaid && group.formattedPayment.isNotEmpty)
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
                      if (group.bandName != null && group.bandName != group.title) ...[
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

                      if (group.isMultiple) ...[
                        Text(
                          '${group.eventCount} events · ${group.totalPositions} positions (${group.filledPositions} filled)',
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                      ],

                      const SizedBox(height: 8),

                      // 1. Event Type
                      Text(
                        'Event Type',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        resolvedEventType ?? 'Not provided',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Request Type
                      Text(
                        'Request Type',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        group.requestTypeLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Location
                      Text(
                        'Location',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (group.location != null && group.location!.trim().isNotEmpty)
                                  ? group.location!.trim()
                                  : 'Stockholm, Sweden',
                              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4. Date & Time
                      Text(
                        'Date & Time',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        groupDateTimeDisplay,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. Description (optional)
                      Text(
                        'Description (optional)',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (group.description != null && group.description!.trim().isNotEmpty)
                            ? group.description!.trim()
                            : 'Not provided',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 6. Role / Instrument
                      Text(
                        'Role / Instrument',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),

                      ...group.requests.map((req) {
                        final reqId = req.subRequestId ?? req.id ?? '';
                        final isCreator = currentUserId != null && (req.creatorUserId == currentUserId || req.userId == currentUserId);
                        final hasApplied = currentUserId != null && !isCreator && (req.responses.containsKey(currentUserId) || _appliedGigIds.contains(reqId));
                        final isAssigned = req.status == 'assigned' || req.assignedUserId != null;

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
                                        if (hasMultipleDistinctEvents && req.eventSequence != null)
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
                                          req.voicePart ??
                                              ((req.role != null &&
                                                      req.role!.trim().toLowerCase() != 'substitute' &&
                                                      req.role!.trim().toLowerCase() != 'new member' &&
                                                      req.role!.trim().toLowerCase() != 'other')
                                                  ? req.role!
                                                  : 'Musician'),
                                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatReqDateTime(req),
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
                              else if (isCreator)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.4)),
                                  ),
                                  child: Text('Your Request', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
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
                                      setModalState(() {
                                        _appliedGigIds.add(reqId);
                                        req.responses[currentUserId] = true;
                                      });
                                      setState(() {
                                        _appliedGigIds.add(reqId);
                                        req.responses[currentUserId] = true;
                                      });
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

                      // Paid amount & Details placed after the six requested fields
                      if (group.isPaid || (group.payDetails != null && group.payDetails!.trim().isNotEmpty)) ...[
                        const SizedBox(height: 10),
                        if (group.formattedPayment.isNotEmpty) ...[
                          Text(
                            'Payment',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group.formattedPayment,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (group.payDetails != null && group.payDetails!.trim().isNotEmpty) ...[
                          Text(
                            'Details',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group.payDetails!.trim(),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

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
                    Expanded(
                      child: Text(
                        'Find Gigs',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!FeatureToggles.showMapInTopBar) ...[
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/gig-map');
                            },
                            icon: const Icon(Icons.map_rounded, color: AppTheme.primaryAccent, size: 16),
                            label: Text(
                              'Map View',
                              style: GoogleFonts.inter(
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              backgroundColor: AppTheme.primaryAccent.withOpacity(0.12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.3)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Icon(Icons.filter_list_rounded, color: Colors.white, size: 22),
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
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Substitute Requests', maxLines: 1),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('New Member Requests', maxLines: 1),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Saved', maxLines: 1),
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
                          _buildGigsList(_substituteGigGroups),
                          _buildGigsList(_newMemberGigGroups),
                          _buildGigsList(
                            [..._substituteGigGroups, ..._newMemberGigGroups]
                                .where((g) => _savedGigIds.contains(g.groupId))
                                .toList(),
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
                        Text(
                          group.requestTypeLabel,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: group.isNewMember ? AppTheme.primaryAccent : const Color(0xFF90CAF9),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (group.bandName != null && group.bandName != group.title) ...[
                          Text(
                            group.bandName!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
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
                            '${group.eventCount} event${group.eventCount == 1 ? "" : "s"} · ${group.totalPositions} position${group.totalPositions == 1 ? "" : "s"}',
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            // Paid / Payment tag
                            if (group.isPaid && group.formattedPayment.isNotEmpty)
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

                            // Roles tag summary
                            if (group.roleInstrumentDisplay.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1A3A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF2E2A4E)),
                                ),
                                child: Text(
                                  group.roleInstrumentDisplay,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppTheme.secondaryAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                            // Direct Invite Tag
                            if (hasDirectInvite)
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
