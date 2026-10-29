import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../config/feature_toggles.dart';
import '../utils/sub_request_card_helper.dart';
import 'sub_request_response_details_screen.dart';

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

enum BandAdminStatus { unknown, authorized, unauthorized, failed }

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
  final Map<String, BandAdminStatus> _adminStatusCache = {}; // key: '$userId/$bandId'
  final Map<String, int> _inFlightLookups = {}; // key: '$userId/$bandId', value: generation
  int _authGeneration = 0;
  String? _activeUserId;
  List<GigGroup> _substituteGigGroups = [];
  List<GigGroup> _newMemberGigGroups = [];
  List<GigGroup> _appliedGigGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this);
    super.initState();
    _loadSubRequests();
  }

  void _resetAuth({required String? newUserId}) {
    _authGeneration++;
    _adminStatusCache.clear();
    _inFlightLookups.clear();
    _activeUserId = newUserId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    if (appState.currentUserId != _activeUserId && _activeUserId != null) {
      _resetAuth(newUserId: appState.currentUserId);
      _loadSubRequests();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adminStatusCache.clear();
    _inFlightLookups.clear();
    super.dispose();
  }

  BandAdminStatus _getBandAdminStatus(String? bandId, String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty) return BandAdminStatus.unauthorized;
    if (bandId == null ||
        bandId.isEmpty ||
        bandId == 'freelance' ||
        bandId == 'standalone' ||
        bandId == 'all') {
      return BandAdminStatus.unauthorized;
    }
    final key = '$currentUserId/$bandId';
    return _adminStatusCache[key] ?? BandAdminStatus.unknown;
  }

  List<GigGroup> _groupSubRequests(List<SubRequest> rawList) {
    final Map<String, List<SubRequest>> groupsMap = {};
    for (final req in rawList) {
      final key = (req.requestGroupId != null && req.requestGroupId!.isNotEmpty)
          ? req.requestGroupId!
          : (req.subRequestId ?? req.id ?? 'single_${rawList.indexOf(req)}');
      final loc = (req.location != null && req.location!.trim().isNotEmpty)
          ? req.location!.trim().toLowerCase()
          : '';
      final compositeKey = '${key}_$loc';
      groupsMap.putIfAbsent(compositeKey, () => []).add(req);
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

      final locCandidate = reqs.firstWhere(
        (r) => r.location != null && r.location!.trim().isNotEmpty,
        orElse: () => first,
      );
      final effectiveLocation = (locCandidate.location != null && locCandidate.location!.trim().isNotEmpty)
          ? locCandidate.location!.trim()
          : (locCandidate.city != null && locCandidate.city!.trim().isNotEmpty ? locCandidate.city!.trim() : 'Stockholm, Sweden');

      groups.add(
        GigGroup(
          groupId: entry.key,
          title: groupTitle,
          bandName: first.bandName,
          location: effectiveLocation,
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


  Future<void> _loadSubRequests() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final list = await appState.firebaseService.getUserSubRequestFeedAsync();
      final currentUserId = appState.currentUserId;
      if (currentUserId != _activeUserId) {
        _resetAuth(newUserId: currentUserId);
      }

      _appliedGigIds.addAll(appState.sessionAppliedSubRequestIds);
      if (currentUserId != null) {
        try {
          final applied = await appState.firebaseService.getUserAppliedSubRequestIdsAsync(currentUserId);
          _appliedGigIds.addAll(applied);
          appState.markSubRequestsApplied(applied, notify: false);
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
      final List<SubRequest> appliedRequests = [];

      for (final gig in list) {
        final st = gig.status.toLowerCase();
        if (st == 'cancelled' || st == 'deleted') continue;

        // Defensive exclusion for ordinary Map View pins
        if (gig.isMapOnlyPin) continue;

        final reqId = gig.subRequestId ?? gig.id ?? '';
        final hasApplied = (currentUserId != null && gig.responses.containsKey(currentUserId)) ||
            _appliedGigIds.contains(reqId);
        if (hasApplied) {
          appliedRequests.add(gig);
        }

        if (st == 'closed') continue;

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
        _appliedGigGroups = _groupSubRequests(appliedRequests);
        _isLoading = false;
      });

      _fetchAdminBands(list, currentUserId);
    } catch (e) {
      debugPrint("Error fetching sub requests: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _fetchAdminBands(List<SubRequest> list, String? currentUserId, {bool forceRetry = false}) async {
    if (currentUserId == null) return;
    final capturedUserId = currentUserId;
    final capturedGeneration = _authGeneration;
    final uniqueBandIds = list
        .map((g) => g.bandId?.trim())
        .where((b) => b != null && b.isNotEmpty && b != 'freelance' && b != 'standalone' && b != 'all')
        .cast<String>()
        .toSet();
    if (uniqueBandIds.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    for (final bId in uniqueBandIds) {
      final key = '$capturedUserId/$bId';
      if (_inFlightLookups[key] == capturedGeneration) continue;
      if (!forceRetry) {
        final cached = _adminStatusCache[key];
        if (cached != null && cached != BandAdminStatus.unknown && cached != BandAdminStatus.failed) {
          continue;
        }
      }
      _inFlightLookups[key] = capturedGeneration;
      if (forceRetry && _adminStatusCache[key] == BandAdminStatus.failed) {
        if (mounted && _activeUserId == capturedUserId && _authGeneration == capturedGeneration) {
          setState(() {
            _adminStatusCache[key] = BandAdminStatus.unknown;
          });
        }
      }
      try {
        final isAdmin = await appState.firebaseService.isBandLeaderOrAdminAsync(bId, capturedUserId);
        if (_inFlightLookups[key] == capturedGeneration) {
          _inFlightLookups.remove(key);
        }
        if (!mounted || _activeUserId != capturedUserId || _authGeneration != capturedGeneration) return;
        setState(() {
          _adminStatusCache[key] = isAdmin ? BandAdminStatus.authorized : BandAdminStatus.unauthorized;
        });
      } catch (_) {
        if (_inFlightLookups[key] == capturedGeneration) {
          _inFlightLookups.remove(key);
        }
        if (!mounted || _activeUserId != capturedUserId || _authGeneration != capturedGeneration) return;
        setState(() {
          _adminStatusCache[key] = BandAdminStatus.failed;
        });
      }
    }
  }

  void _retryBandAdminLookup(String? bandId) {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    if (currentUserId == null || bandId == null) return;
    final allRequests = [..._substituteGigGroups, ..._newMemberGigGroups, ..._appliedGigGroups]
        .expand((g) => g.requests)
        .where((r) => r.bandId == bandId)
        .toList();
    if (allRequests.isNotEmpty) {
      _fetchAdminBands(allRequests, currentUserId, forceRetry: true);
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

  void _openManageRequest(SubRequest req) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubRequestResponseDetailsScreen(subRequest: req),
        settings: const RouteSettings(name: '/sub-request-response-details'),
      ),
    );
  }

  void _openManageRequestGroup(GigGroup group) {
    if (group.requests.length == 1) {
      _openManageRequest(group.requests.first);
    } else {
      _showGigDetailsBottomSheet(group);
    }
  }

  Future<void> _applyToSingleSubRequest(SubRequest req) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    if (currentUserId == null) return;
    final reqId = req.subRequestId ?? req.id ?? '';
    try {
      await appState.firebaseService.addResponseToSubRequestAsync(
        reqId,
        currentUserId,
      );
      setState(() {
        _appliedGigIds.add(reqId);
        req.responses[currentUserId] = true;
      });
      appState.markSubRequestApplied(reqId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Applied for position!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
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
            final presentation = SubRequestCardPresentation.fromRequests(
              group.requests,
              bandNameOverride: group.bandName,
              locationOverride: group.location,
              descriptionOverride: group.description,
              payDetailsOverride: group.payDetails,
              currentUserId: currentUserId,
              isBandAdmin: group.requests.any((r) => r.bandId != null && _getBandAdminStatus(r.bandId, currentUserId) == BandAdminStatus.authorized),
              appliedIds: _appliedGigIds,
            );

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

                      // 1. Band / Project
                      Text(
                        presentation.bandName,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
                        presentation.requestType,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. Role / Instrument
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
                        final isReqCreator = isCreatorOfSubRequest(req, currentUserId);
                        final bandAdminStatus = (req.bandId != null)
                            ? _getBandAdminStatus(req.bandId, currentUserId)
                            : BandAdminStatus.unauthorized;
                        final isReqAdmin = isReqCreator || bandAdminStatus == BandAdminStatus.authorized;
                        final isReqPending = !isReqCreator && bandAdminStatus == BandAdminStatus.unknown;
                        final isReqFailed = !isReqCreator && bandAdminStatus == BandAdminStatus.failed;
                        final hasApplied = currentUserId != null &&
                            !isReqAdmin &&
                            (req.responses.containsKey(currentUserId) || _appliedGigIds.contains(reqId));
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
                                    Text(
                                      resolveSingleRole(req),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (req.replacedMemberName != null && req.replacedMemberName!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Replacing: ${req.replacedMemberName!.trim()}',
                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isAssigned)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Filled',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                )
                              else if (isReqAdmin)
                                ElevatedButton(
                                  key: ValueKey('details_manage_request_$reqId'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _openManageRequest(req);
                                  },
                                  child: Text(
                                    'Manage Request',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              else if (isReqPending)
                                SizedBox(
                                  key: ValueKey('details_auth_pending_$reqId'),
                                  height: 28,
                                  width: 60,
                                  child: Center(
                                    child: SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primaryAccent.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                )
                              else if (isReqFailed)
                                OutlinedButton.icon(
                                  key: ValueKey('details_auth_retry_$reqId'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.textSecondary,
                                    side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      _retryBandAdminLookup(req.bandId);
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded, size: 12, color: AppTheme.textSecondary),
                                  label: Tooltip(
                                    message: 'Could not verify permissions. Retry',
                                    child: Text(
                                      'Retry',
                                      semanticsLabel: 'Could not verify permissions. Retry',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                )
                              else if (hasApplied)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Applied',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white70,
                                    ),
                                  ),
                                )
                              else
                                ElevatedButton(
                                  key: ValueKey('details_apply_$reqId'),
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
                                      appState.markSubRequestApplied(reqId);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Applied for position!'),
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
                                  child: Text(
                                    'Apply',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),

                      // 4. Event Type and Paid status (omit Event Type for New Band Member)
                      if (presentation.requestType != 'New Band Member') ...[
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
                          presentation.eventType ?? 'Not provided',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (presentation.isPaid && presentation.formattedPayment != null) ...[
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
                          presentation.formattedPayment!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 5. Date & Time
                      if (presentation.requestType != 'New Band Member' || presentation.formattedDateTime != null) ...[
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
                          presentation.formattedDateTime ?? 'Not provided',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 6. Location / Venue
                      Text(
                        'Location / Venue',
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
                              (presentation.locationVenue != null && presentation.locationVenue!.trim().isNotEmpty)
                                  ? presentation.locationVenue!.trim()
                                  : 'Stockholm, Sweden',
                              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 7. Description / Details
                      Text(
                        'Description / Details',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (presentation.description != null && presentation.description!.trim().isNotEmpty)
                            ? presentation.description!.trim()
                            : 'Not provided',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 8. Payment Details, when present
                      if (presentation.payDetails != null && presentation.payDetails!.trim().isNotEmpty) ...[
                        Text(
                          'Payment Details',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          presentation.payDetails!.trim(),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 10),
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
    final appState = Provider.of<AppState>(context);
    final currentUserId = appState.currentUserId;
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
                              backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
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
                      child: Text('1. Substitute Requests', maxLines: 1),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('2. New Member Requests', maxLines: 1),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('3. Applied', maxLines: 1),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('4. Saved', maxLines: 1),
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
                            () {
                              final Map<String, GigGroup> map = {};
                              for (final g in _appliedGigGroups) {
                                map[g.groupId] = g;
                              }
                              for (final g in [..._substituteGigGroups, ..._newMemberGigGroups]) {
                                if (g.requests.any((r) => _appliedGigIds.contains(r.subRequestId) || _appliedGigIds.contains(r.id) || (currentUserId != null && r.responses.containsKey(currentUserId)))) {
                                  map[g.groupId] = g;
                                }
                              }
                              return map.values.toList();
                            }(),
                          ),
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
          final primaryReqId = group.requests.isNotEmpty
              ? (group.requests.first.subRequestId ?? group.requests.first.id ?? id)
              : id;
          final isSaved = _savedGigIds.contains(id);

          final hasDirectInvite = group.requests.any(
            (r) => r.targetUserIds != null && currentUserId != null && r.targetUserIds!.contains(currentUserId),
          );

          final isCreator = group.requests.any((r) => isCreatorOfSubRequest(r, currentUserId));
          final relevantBandIds = group.requests
              .map((r) => r.bandId?.trim())
              .where((b) => b != null && b.isNotEmpty && b != 'freelance' && b != 'standalone' && b != 'all')
              .cast<String>()
              .toSet();

          final bool isAdmin;
          final bool isAuthPending;
          final bool isAuthFailed;
          if (isCreator) {
            isAdmin = true;
            isAuthPending = false;
            isAuthFailed = false;
          } else if (relevantBandIds.isEmpty) {
            isAdmin = false;
            isAuthPending = false;
            isAuthFailed = false;
          } else {
            final statuses = relevantBandIds.map((bId) => _getBandAdminStatus(bId, currentUserId)).toList();
            if (statuses.any((s) => s == BandAdminStatus.authorized)) {
              isAdmin = true;
              isAuthPending = false;
              isAuthFailed = false;
            } else if (statuses.any((s) => s == BandAdminStatus.unknown)) {
              isAdmin = false;
              isAuthPending = true;
              isAuthFailed = false;
            } else if (statuses.any((s) => s == BandAdminStatus.failed)) {
              isAdmin = false;
              isAuthPending = false;
              isAuthFailed = true;
            } else {
              isAdmin = false;
              isAuthPending = false;
              isAuthFailed = false;
            }
          }

          final presentation = SubRequestCardPresentation.fromRequests(
            group.requests,
            bandNameOverride: group.bandName,
            locationOverride: group.location,
            descriptionOverride: group.description,
            payDetailsOverride: group.payDetails,
            currentUserId: currentUserId,
            isBandAdmin: isAdmin,
            isBandAdminPending: isAuthPending,
            isBandAdminFailed: isAuthFailed,
            appliedIds: _appliedGigIds,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Band / Project name + Bookmark icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          presentation.bandName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

                  // 5. Location / Venue
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

                  const SizedBox(height: 12),

                  // 6. Contextual Action
                  Row(
                    children: [
                      if (isCreator || isAdmin)
                        ElevatedButton(
                          key: ValueKey('find_gigs_manage_request_$primaryReqId'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openManageRequestGroup(group),
                          child: Text(
                            'Manage Request',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        )
                      else if (isAuthPending)
                        SizedBox(
                          key: ValueKey('find_gigs_auth_pending_$primaryReqId'),
                          height: 34,
                          width: 80,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryAccent.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        )
                      else if (isAuthFailed)
                        OutlinedButton.icon(
                          key: ValueKey('find_gigs_auth_retry_$primaryReqId'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            final bId = group.requests.firstWhere((r) => r.bandId != null, orElse: () => group.requests.first).bandId;
                            _retryBandAdminLookup(bId);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.textSecondary),
                          label: Tooltip(
                            message: 'Could not verify permissions. Retry',
                            child: Text(
                              'Retry',
                              semanticsLabel: 'Could not verify permissions. Retry',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else if (presentation.hasApplied)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.success.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            'Applied',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success,
                            ),
                          ),
                        )
                      else
                        ElevatedButton(
                          key: ValueKey('find_gigs_apply_$primaryReqId'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            if (group.requests.length == 1) {
                              _applyToSingleSubRequest(group.requests.first);
                            } else {
                              _showGigDetailsBottomSheet(group);
                            }
                          },
                          child: Text(
                            'Apply',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (hasDirectInvite) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.white, size: 12),
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
          );
        },
      ),
    );
  }
}
