import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/user_profile.dart';
import '../models/band.dart';
import '../models/band_event.dart';
import '../models/agreement.dart';
import '../models/message.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../data/skills_taxonomy.dart';

class ResponderItem {
  final String userId;
  final String name;
  final String instruments;
  final String location;
  final String level;
  final String about;

  ResponderItem({
    required this.userId,
    required this.name,
    required this.instruments,
    required this.location,
    required this.level,
    required this.about,
  });
}

class SubstituteSlotDraft {
  final String slotId;
  String? subRequestId;
  String? replacedMemberId;
  String? replacedMemberName;
  String instrument;
  String searchSource; // 'favorites' or 'search_all'
  Set<String> selectedFavoriteIds;
  String status; // 'draft', 'published', 'assigned', 'closed', 'cancelled'
  String? assignedUserId;
  String? assignedUserName;
  int? assignedAt;
  List<ResponderItem> candidates;
  bool isExpanded;
  bool isSuggested;
  bool isConfirmed;
  String? rsvpStatus;

  SubstituteSlotDraft({
    required this.slotId,
    this.subRequestId,
    this.replacedMemberId,
    this.replacedMemberName,
    required this.instrument,
    this.searchSource = 'search_all',
    Set<String>? selectedFavoriteIds,
    this.status = 'draft',
    this.assignedUserId,
    this.assignedUserName,
    this.assignedAt,
    List<ResponderItem>? candidates,
    this.isExpanded = true,
    this.isSuggested = false,
    this.isConfirmed = true,
    this.rsvpStatus,
  })  : selectedFavoriteIds = selectedFavoriteIds ?? {},
        candidates = candidates ?? [];
}

class FindSubScreen extends StatefulWidget {
  final String? eventId;
  final String? bandId;

  const FindSubScreen({super.key, this.eventId, this.bandId});

  @override
  State<FindSubScreen> createState() => _FindSubScreenState();
}

class _FindSubScreenState extends State<FindSubScreen> {
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 4));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  final bool _isPaid = true;
  bool _isSubmitting = false;
  bool _isLoading = true;

  BandEvent? _event;
  List<UserProfile> _favorites = [];
  List<SubstituteSlotDraft> _slots = [];

  static Map<String, List<String>> get _allSkillsCategoryMap =>
      SkillsTaxonomy.categoryMapFor(SkillTaxonomyContext.findSub);

  List<UserProfile> _getFilteredFavoritesForInstrument(String instrument) {
    final instrumentLower = instrument.toLowerCase();
    return _favorites.where((m) {
      final matchesInstrument = (m.userType?.toLowerCase() == instrumentLower) ||
          m.instruments.any((i) => i.toLowerCase() == instrumentLower);
      return matchesInstrument;
    }).toList();
  }

  Future<void> _loadFavorites() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();

      final List<UserProfile> loaded = [];
      for (final id in favIds) {
        final profile = await appState.firebaseService.getUserProfileAsync(id);
        if (profile != null) {
          loaded.add(profile);
        }
      }
      if (mounted) {
        setState(() {
          _favorites = loaded;
        });
      }
    } catch (e) {
      debugPrint("Error loading favorites: $e");
    }
  }

  TimeOfDay _parseTime(String? timeStr, TimeOfDay defaultTime) {
    if (timeStr == null || timeStr.isEmpty) return defaultTime;
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint("Error parsing time string $timeStr: $e");
    }
    return defaultTime;
  }

  Future<void> _loadBandInfo() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final effectiveBandId = widget.bandId ?? appState.activeBandId;
    if (effectiveBandId != null) {
      try {
        final Band? band = await appState.firebaseService.getBandInfoAsync(effectiveBandId);
        if (band != null && mounted) {
          setState(() {
            if (band.rehearsalLocation != null && band.rehearsalLocation!.isNotEmpty) {
              _locationController.text = band.rehearsalLocation!;
            } else if (band.location != null && band.location!.isNotEmpty) {
              _locationController.text = band.location!;
            }

            if (band.rehearsalStartTime != null && band.rehearsalStartTime!.isNotEmpty) {
              _startTime = _parseTime(band.rehearsalStartTime, _startTime);
            }
            if (band.rehearsalEndTime != null && band.rehearsalEndTime!.isNotEmpty) {
              _endTime = _parseTime(band.rehearsalEndTime, _endTime);
            }
          });
        }
      } catch (e) {
        debugPrint("Error loading band info: $e");
      }
    }
  }

  Future<void> _loadEventAndSlots() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);

    try {
      if (widget.eventId != null && widget.bandId != null) {
        // 1. Fetch Band Event
        final event = await appState.firebaseService.getBandEventOnceAsync(
          widget.bandId!,
          widget.eventId!,
        );
        _event = event;

        if (event != null) {
          _locationController.text = event.location;
          final start = DateTime.tryParse(event.startDateTime) ?? DateTime.now();
          _selectedDate = start;
          _startTime = TimeOfDay.fromDateTime(start);
          final end = DateTime.tryParse(event.endDateTime) ?? start.add(const Duration(hours: 2));
          _endTime = TimeOfDay.fromDateTime(end);
          _messageController.text = "Need substitute for event: ${event.title}\nDescription: ${event.description}";
        }

        // 2. Fetch existing published sub requests for this event
        final existingRequests = await appState.firebaseService.getSubRequestsForEventAsync(
          widget.bandId!,
          widget.eventId!,
        );

        // 3. Load candidate profiles for existing published requests
        final List<SubstituteSlotDraft> loadedSlots = [];
        for (final req in existingRequests) {
          final reqId = req.subRequestId ?? req.id;
          final candidateItems = <ResponderItem>[];

          if (req.responses.isNotEmpty) {
            for (final uid in req.responses.keys) {
              final prof = await appState.firebaseService.getUserProfileAsync(uid);
              if (prof != null) {
                candidateItems.add(
                  ResponderItem(
                    userId: uid,
                    name: prof.displayName ?? prof.nickname ?? 'Musician',
                    instruments: prof.instruments.join(', '),
                    location: prof.location ?? 'Unknown location',
                    level: prof.level ?? 'Intermediate',
                    about: prof.about ?? '',
                  ),
                );
              }
            }
          }

          final source = req.searchSource ??
              (req.targetUserIds != null && req.targetUserIds!.isNotEmpty
                  ? 'favorites'
                  : 'search_all');

          final favIds = req.targetUserIds != null ? req.targetUserIds!.toSet() : <String>{};

          loadedSlots.add(
            SubstituteSlotDraft(
              slotId: req.slotId ?? reqId ?? 'slot_${loadedSlots.length + 1}',
              subRequestId: reqId,
              replacedMemberId: req.replacedMemberId,
              replacedMemberName: req.replacedMemberName,
              instrument: req.voicePart ?? 'Electric Guitar',
              searchSource: source,
              selectedFavoriteIds: favIds,
              status: req.status,
              assignedUserId: req.assignedUserId,
              assignedUserName: req.assignedUserName,
              assignedAt: req.assignedAt,
              candidates: candidateItems,
              isExpanded: true,
            ),
          );
        }

        // 4. Prepopulate missing band members who do not yet have an active/published sub request
        final bandMembers = await appState.firebaseService.getBandMembersAsync(widget.bandId!);
        if (event != null && bandMembers.isNotEmpty) {
          for (final member in bandMembers) {
            final uid = member.userId;
            if (uid == null) continue;

            final resp = event.responses[uid]?.status;
            // YES: never treated as needing a substitute
            final isAttending = resp == 'YES' || resp == 'attending';
            if (!isAttending) {
              // Check if a sub request slot already covers this member
              final alreadyCovered = loadedSlots.any(
                (s) => s.replacedMemberId == uid && s.status != 'cancelled' && s.status != 'closed',
              );

              if (!alreadyCovered) {
                final memberProfile = await appState.firebaseService.getUserProfileAsync(uid);
                final memberName = memberProfile?.displayName ?? memberProfile?.nickname ?? member.nickname ?? 'Band Member';
                final primaryInstrument = memberProfile?.instruments.isNotEmpty == true
                    ? memberProfile!.instruments.first
                    : (memberProfile?.userType ?? 'Electric Guitar');

                // Default auto-selected matching favorites
                final matchingFavs = _getFilteredFavoritesForInstrument(primaryInstrument);
                final favIds = matchingFavs.map((f) => f.userId!).toSet();

                final isNo = resp == 'NO' || resp == 'declined';
                final isUncertain = resp == 'UNCERTAIN' || resp == 'maybe';
                final rsvpLabel = isNo ? 'NO' : (isUncertain ? 'UNCERTAIN' : 'NO ANSWER');

                loadedSlots.add(
                  SubstituteSlotDraft(
                    slotId: 'slot_member_$uid',
                    replacedMemberId: uid,
                    replacedMemberName: memberName,
                    instrument: primaryInstrument,
                    searchSource: matchingFavs.isNotEmpty ? 'favorites' : 'search_all',
                    selectedFavoriteIds: favIds,
                    status: 'draft',
                    isSuggested: !isNo, // UNCERTAIN and NO ANSWER are suggested only
                    isConfirmed: isNo,  // NO is confirmed draft by default; UNCERTAIN/NO ANSWER require explicit confirmation
                    rsvpStatus: rsvpLabel,
                  ),
                );
              }
            }
          }
        }

        // If still no slots found at all, create 1 initial draft slot
        if (loadedSlots.isEmpty) {
          final defaultFavs = _getFilteredFavoritesForInstrument('Electric Guitar');
          loadedSlots.add(
            SubstituteSlotDraft(
              slotId: 'slot_${DateTime.now().millisecondsSinceEpoch}',
              instrument: 'Electric Guitar',
              searchSource: defaultFavs.isNotEmpty ? 'favorites' : 'search_all',
              selectedFavoriteIds: defaultFavs.map((f) => f.userId!).toSet(),
              status: 'draft',
            ),
          );
        }

        if (mounted) {
          setState(() {
            _slots = loadedSlots;
          });
        }
      } else {
        // Standalone mode without eventId
        final defaultFavs = _getFilteredFavoritesForInstrument('Electric Guitar');
        if (mounted) {
          setState(() {
            _slots = [
              SubstituteSlotDraft(
                slotId: 'slot_${DateTime.now().millisecondsSinceEpoch}',
                instrument: 'Electric Guitar',
                searchSource: defaultFavs.isNotEmpty ? 'favorites' : 'search_all',
                selectedFavoriteIds: defaultFavs.map((f) => f.userId!).toSet(),
                status: 'draft',
              ),
            ];
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading event and slots: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.currentUserProfile?.location != null) {
        _locationController.text = appState.currentUserProfile!.location!;
      } else {
        _locationController.text = 'Stockholm, Sweden';
      }
      _loadBandInfo();
      _loadFavorites().then((_) {
        _loadEventAndSlots();
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              surface: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Map<String, double>? _resolveCoordinates(String location) {
    final loc = location.toLowerCase();
    if (loc.contains('stockholm')) {
      return {'latitude': 59.3293, 'longitude': 18.0686};
    } else if (loc.contains('gothenburg') || loc.contains('göteborg')) {
      return {'latitude': 57.7089, 'longitude': 11.9746};
    } else if (loc.contains('malmö') || loc.contains('malmo')) {
      return {'latitude': 55.6050, 'longitude': 13.0038};
    } else if (loc.contains('uppsala')) {
      return {'latitude': 59.8586, 'longitude': 17.6389};
    }
    return null;
  }

  Future<void> _openInstrumentPicker(SubstituteSlotDraft slot) async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Instrument/Skills',
      categoryMap: _allSkillsCategoryMap,
      initialSelected: [slot.instrument],
      maxSelection: 1,
      presentation: CategoryPickerPresentation.skillsHierarchy,
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        slot.instrument = result.first;
        // Auto update matching favorites for this slot
        final matchingFavs = _getFilteredFavoritesForInstrument(slot.instrument);
        slot.selectedFavoriteIds = matchingFavs.map((f) => f.userId!).toSet();
      });
    }
  }

  void _addAnotherSubstitute() {
    final defaultFavs = _getFilteredFavoritesForInstrument('Electric Guitar');
    setState(() {
      _slots.add(
        SubstituteSlotDraft(
          slotId: 'slot_${DateTime.now().millisecondsSinceEpoch}_${_slots.length + 1}',
          instrument: 'Electric Guitar',
          searchSource: defaultFavs.isNotEmpty ? 'favorites' : 'search_all',
          selectedFavoriteIds: defaultFavs.map((f) => f.userId!).toSet(),
          status: 'draft',
          isExpanded: true,
        ),
      );
    });
  }

  void _removeDraftSlot(SubstituteSlotDraft slot) {
    setState(() {
      _slots.remove(slot);
      if (_slots.isEmpty) {
        _addAnotherSubstitute();
      }
    });
  }

  Future<void> _cancelPublishedSlot(SubstituteSlotDraft slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        title: Text(
          'Cancel Substitute Request?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to cancel the request for ${slot.instrument}? Remaining slots will stay active.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Request', style: GoogleFonts.inter(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel Request', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId;

      setState(() => _isLoading = true);
      try {
        if (currentUserId != null && slot.subRequestId != null) {
          await appState.firebaseService.deleteSubRequestAsync(currentUserId, slot.subRequestId!);
        }
        if (!mounted) return;
        setState(() {
          _slots.remove(slot);
          if (_slots.isEmpty) {
            _addAnotherSubstitute();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Substitute request cancelled.'), backgroundColor: AppTheme.success),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel request: $e'), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _publishAllDraftRequests() async {
    final draftSlots = _slots.where((s) => s.status == 'draft' && (!s.isSuggested || s.isConfirmed)).toList();
    if (draftSlots.isEmpty) return;

    // Validate favorites for any slot using Favorites
    for (final slot in draftSlots) {
      if (slot.searchSource == 'favorites') {
        if (slot.selectedFavoriteIds.isEmpty) {
          final matchingFavs = _getFilteredFavoritesForInstrument(slot.instrument);
          if (matchingFavs.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No favorited musicians play ${slot.instrument}. Please select Search All for this position or add favorites in Browse.',
                ),
                backgroundColor: AppTheme.danger,
                duration: const Duration(seconds: 4),
              ),
            );
            return;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Please select at least one favorite musician for ${slot.instrument}.'),
                backgroundColor: AppTheme.danger,
              ),
            );
            return;
          }
        }
      }
    }

    setState(() => _isSubmitting = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final profile = appState.currentUserProfile;

    final resolvedLoc = _locationController.text.trim().isNotEmpty
        ? _locationController.text.trim()
        : (profile?.location ?? 'Stockholm, Sweden');
    final coords = _resolveCoordinates(resolvedLoc);

    try {
      final List<SubRequest> requestsToSave = [];

      for (final slot in draftSlots) {
        final targetIds = slot.searchSource == 'favorites'
            ? slot.selectedFavoriteIds.toList()
            : null;

        requestsToSave.add(
          SubRequest(
            slotId: slot.slotId,
            voicePart: slot.instrument,
            location: resolvedLoc,
            startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00',
            endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00',
            description: _messageController.text.trim(),
            date: _selectedDate.toIso8601String(),
            role: 'Substitute',
            isPaid: _isPaid,
            bandName: appState.activeBandName ?? 'Freelance Gig',
            rehearsalDayOfWeek: DateFormat('EEEE').format(_selectedDate),
            latitude: coords?['latitude'],
            longitude: coords?['longitude'],
            targetUserIds: targetIds,
            eventId: widget.eventId,
            bandId: widget.bandId ?? appState.activeBandId,
            replacedMemberId: slot.replacedMemberId,
            replacedMemberName: slot.replacedMemberName,
            status: 'published',
            searchSource: slot.searchSource,
          ),
        );
      }

      final createdIds = await appState.firebaseService.saveSubRequestsBatchAsync(requestsToSave);

      // Refresh slot references with generated IDs
      for (int i = 0; i < draftSlots.length && i < createdIds.length; i++) {
        draftSlots[i].subRequestId = createdIds[i];
        draftSlots[i].status = 'published';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully published ${draftSlots.length} substitute request${draftSlots.length > 1 ? "s" : ""}!',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish requests: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _assignCandidate(SubstituteSlotDraft slot, ResponderItem candidate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        title: Text(
          'Confirm Assignment',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Assign ${candidate.name} as substitute for ${slot.instrument}? This will mark them as attending for this event position.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Assign Substitute', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId;
      final bandId = widget.bandId ?? appState.activeBandId ?? '';
      final eventId = widget.eventId ?? '';
      final subRequestId = slot.subRequestId ?? slot.slotId;
      final authorName = appState.currentUserProfile?.displayName ?? 'Organizer';
      final bandName = appState.activeBandName ?? 'Freelance Gig';

      setState(() => _isLoading = true);
      try {
        if (currentUserId != null && subRequestId.isNotEmpty) {
          // 1. Assign in Firebase
          await appState.firebaseService.assignSubstituteCandidateAsync(
            subRequestId: subRequestId,
            candidateUserId: candidate.userId,
            bandId: bandId,
            eventId: eventId,
            roleOrInstrument: slot.instrument,
            candidateName: candidate.name,
          );

          // 2. Create Agreement and chat
          final agreement = Agreement(
            choirLeaderId: currentUserId,
            vocalistId: candidate.userId,
            voicePart: slot.instrument,
            date: _selectedDate.toIso8601String(),
            startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
            endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
            location: _locationController.text.trim(),
            additionalTerms: 'Substitute staffing assignment.',
            bandName: bandName,
          );

          final message = Message(
            id: '',
            senderId: currentUserId,
            receiverId: candidate.userId,
            text: '${candidate.name} has been assigned as substitute (${slot.instrument}).',
            timestamp: DateTime.now(),
            isRead: false,
            senderName: authorName,
          );

          await appState.firebaseService.createAgreementChatAsync(
            currentUserId,
            candidate.userId,
            agreement,
            message,
          );

          if (!mounted) return;
          // 3. Update local slot state
          setState(() {
            slot.status = 'assigned';
            slot.assignedUserId = candidate.userId;
            slot.assignedUserName = candidate.name;
            slot.assignedAt = DateTime.now().millisecondsSinceEpoch;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${candidate.name} assigned successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to assign substitute: $e'), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _revokeAssignment(SubstituteSlotDraft slot) async {
    final candidateId = slot.assignedUserId;
    if (candidateId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        title: Text(
          'Revoke Assignment?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Reopen this position for other candidates? ${slot.assignedUserName ?? "Musician"} will no longer be marked as assigned.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Revoke', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      final bandId = widget.bandId ?? appState.activeBandId ?? '';
      final eventId = widget.eventId ?? '';
      final subRequestId = slot.subRequestId ?? slot.slotId;

      setState(() => _isLoading = true);
      try {
        await appState.firebaseService.revokeSubstituteAssignmentAsync(
          subRequestId: subRequestId,
          candidateUserId: candidateId,
          bandId: bandId,
          eventId: eventId,
        );

        if (!mounted) return;
        setState(() {
          slot.status = 'published';
          slot.assignedUserId = null;
          slot.assignedUserName = null;
          slot.assignedAt = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment revoked.'), backgroundColor: AppTheme.success),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to revoke assignment: $e'), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _openFavoritesSelectionSheet(SubstituteSlotDraft slot) {
    final matchingFavs = _getFilteredFavoritesForInstrument(slot.instrument);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select Favorites (${slot.instrument})',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose which favorited musicians will receive this request.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (matchingFavs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                        ),
                        child: Text(
                          'No favorited musicians play ${slot.instrument}. Please switch this slot to Search All or add favorites from the Browse tab.',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: matchingFavs.length,
                          itemBuilder: (context, index) {
                            final fav = matchingFavs[index];
                            final uid = fav.userId ?? '';
                            final isChecked = slot.selectedFavoriteIds.contains(uid);

                            return CheckboxListTile(
                              value: isChecked,
                              activeColor: AppTheme.primaryAccent,
                              checkColor: Colors.white,
                              title: Text(
                                fav.displayName ?? fav.nickname ?? 'Musician',
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                fav.instruments.join(', '),
                                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              secondary: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                                child: Text(
                                  (fav.displayName ?? fav.nickname ?? 'M').substring(0, 1).toUpperCase(),
                                  style: GoogleFonts.outfit(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                                ),
                              ),
                              onChanged: (val) {
                                setModalState(() {
                                  if (val == true) {
                                    slot.selectedFavoriteIds.add(uid);
                                  } else {
                                    slot.selectedFavoriteIds.remove(uid);
                                  }
                                });
                                setState(() {});
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Done (${slot.selectedFavoriteIds.length} selected)',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
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
    final isMobile = MediaQuery.of(context).size.width < 600;

    final totalSlots = _slots.length;
    final filledSlots = _slots.where((s) => s.status == 'assigned').length;
    final draftSlots = _slots.where((s) => s.status == 'draft' && (!s.isSuggested || s.isConfirmed)).length;

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find Substitute(s)',
        showBack: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Heading
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FIND SUBSTITUTE(S)',
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _event != null
                                    ? 'Staffing for ${_event!.title} (${DateFormat('EEE, MMM d').format(DateTime.tryParse(_event!.startDateTime)?.toLocal() ?? _selectedDate)})'
                                    : 'Staffing for ${appState.activeBandName ?? "Band Event"}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Staffing Summary Bar
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: filledSlots == totalSlots && totalSlots > 0
                              ? AppTheme.success.withOpacity(0.6)
                              : const Color(0xFF2E2A4E),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            filledSlots == totalSlots && totalSlots > 0
                                ? Icons.check_circle_rounded
                                : Icons.people_outline_rounded,
                            color: filledSlots == totalSlots && totalSlots > 0
                                ? AppTheme.success
                                : AppTheme.primaryAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$filledSlots of $totalSlots substitute position${totalSlots == 1 ? "" : "s"} filled',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  draftSlots > 0
                                      ? '$draftSlots draft position${draftSlots == 1 ? "" : "s"} ready to publish'
                                      : 'All positions published',
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
                    const SizedBox(height: 16),

                    // Gig / Event Details (Logistics & Schedule - Fully Editable)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event_note_rounded, size: 18, color: AppTheme.primaryAccent),
                              const SizedBox(width: 8),
                              Text(
                                'Gig/Event Details',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryAccent,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Date Selector Button
                          Text(
                            'Event Date',
                            style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          AnimatedTapDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0C20),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryAccent),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  const Icon(Icons.edit_calendar_rounded, size: 16, color: AppTheme.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Time Selectors Row
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Start Time',
                                      style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    AnimatedTapDetector(
                                      onTap: () => _pickTime(true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F0C20),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF2E2A4E)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.access_time_rounded, size: 15, color: AppTheme.primaryAccent),
                                            const SizedBox(width: 8),
                                            Text(
                                              _startTime.format(context),
                                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'End Time',
                                      style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    AnimatedTapDetector(
                                      onTap: () => _pickTime(false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F0C20),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF2E2A4E)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.access_time_filled_rounded, size: 15, color: AppTheme.primaryAccent),
                                            const SizedBox(width: 8),
                                            Text(
                                              _endTime.format(context),
                                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Location Input Field
                          Text(
                            'Location',
                            style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _locationController,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'e.g. Stockholm, Sweden',
                              hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                              prefixIcon: const Icon(Icons.location_on_rounded, size: 18, color: AppTheme.primaryAccent),
                              filled: true,
                              fillColor: const Color(0xFF0F0C20),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.primaryAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Gig / Event Details (Message / Notes Input)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 18, color: AppTheme.primaryAccent),
                              const SizedBox(width: 8),
                              Text(
                                'Gig/Event Details',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryAccent,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _messageController,
                            maxLines: 3,
                            maxLength: 250,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Describe what the gig or rehearsal is about, setlist, requirements...',
                              hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                              counterStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                              filled: true,
                              fillColor: const Color(0xFF0F0C20),
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.primaryAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Positions Header
                    Text(
                      'REQUIRED POSITIONS',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // List of Slot Cards
                    ..._slots.asMap().entries.map((entry) {
                      final index = entry.key;
                      final slot = entry.value;
                      return _buildSlotCard(index, slot, isMobile);
                    }),

                    const SizedBox(height: 12),

                    // Add Another Position Button
                    AnimatedTapDetector(
                      onTap: _addAnotherSubstitute,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryAccent.withOpacity(0.6),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'ADD ANOTHER SUBSTITUTE',
                              style: GoogleFonts.inter(
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Primary Publish Action
                    if (draftSlots > 0)
                      _isSubmitting
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                          : AnimatedTapDetector(
                              onTap: _publishAllDraftRequests,
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryAccent.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Text(
                                        'PUBLISH SUBSTITUTE REQUESTS ($draftSlots)',
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSlotCard(int index, SubstituteSlotDraft slot, bool isMobile) {
    final slotNumber = index + 1;
    final isDraft = slot.status == 'draft';
    final isAssigned = slot.status == 'assigned';
    final matchingFavs = _getFilteredFavoritesForInstrument(slot.instrument);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAssigned
              ? AppTheme.success.withOpacity(0.6)
              : (isDraft ? const Color(0xFF2E2A4E) : AppTheme.primaryAccent.withOpacity(0.5)),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slot Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16132D),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: const Color(0xFF2E2A4E).withOpacity(0.6))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Substitute $slotNumber',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(slot),
                        ],
                      ),
                      if (slot.replacedMemberName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Replacing: ${slot.replacedMemberName}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isDraft)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Remove position',
                    onPressed: () => _removeDraftSlot(slot),
                  )
                else if (!isAssigned)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                    tooltip: 'Cancel request',
                    onPressed: () => _cancelPublishedSlot(slot),
                  ),
              ],
            ),
          ),

          // Slot Body
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Instrument / Role Selector (Preserves 'INSTRUMENT/SKILLS' for existing tests)
                InkWell(
                  onTap: isDraft ? () => _openInstrumentPicker(slot) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INSTRUMENT/SKILLS',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0C20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                slot.instrument,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isDraft)
                              const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Search Source Selector (Favorites vs Search All)
                Text(
                  'Search in:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedTapDetector(
                        onTap: () {
                          if (isDraft) {
                            setState(() {
                              slot.searchSource = 'favorites';
                              slot.selectedFavoriteIds =
                                  matchingFavs.map((f) => f.userId!).toSet();
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: slot.searchSource == 'favorites'
                                ? AppTheme.primaryAccent.withOpacity(0.18)
                                : const Color(0xFF0F0C20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: slot.searchSource == 'favorites'
                                  ? AppTheme.primaryAccent
                                  : const Color(0xFF2E2A4E),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: slot.searchSource == 'favorites'
                                    ? AppTheme.primaryAccent
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Favorites',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: slot.searchSource == 'favorites'
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AnimatedTapDetector(
                        onTap: () {
                          if (isDraft) {
                            setState(() {
                              slot.searchSource = 'search_all';
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: slot.searchSource == 'search_all'
                                ? AppTheme.primaryAccent.withOpacity(0.18)
                                : const Color(0xFF0F0C20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: slot.searchSource == 'search_all'
                                  ? AppTheme.primaryAccent
                                  : const Color(0xFF2E2A4E),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.public_rounded,
                                size: 16,
                                color: slot.searchSource == 'search_all'
                                    ? AppTheme.primaryAccent
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Search All',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: slot.searchSource == 'search_all'
                                      ? Colors.white
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Source Details Context Box
                if (slot.searchSource == 'favorites') ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0C20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2A4E)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            matchingFavs.isEmpty
                                ? 'No favorited ${slot.instrument} players found.'
                                : '${slot.selectedFavoriteIds.length} of ${matchingFavs.length} favorites selected',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: matchingFavs.isEmpty ? AppTheme.danger : Colors.white70,
                            ),
                          ),
                        ),
                        if (matchingFavs.isNotEmpty && isDraft)
                          TextButton(
                            onPressed: () => _openFavoritesSelectionSheet(slot),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Edit Selection',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0C20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2A4E)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Will be broadcast to all eligible ${slot.instrument} musicians.',
                            style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // 2.5 Suggested Slot Confirmation Banner
                if (slot.status == 'draft' && slot.isSuggested && !slot.isConfirmed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.help_outline_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Suggested (${slot.rsvpStatus ?? "Uncertain RSVP"})',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Suggested based on RSVP status (${slot.rsvpStatus ?? "Uncertain"}). You must confirm this position to include it when publishing substitute requests.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70, height: 1.3),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              slot.isConfirmed = true;
                            });
                          },
                          icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                          label: Text(
                            'CONFIRM & INCLUDE POSITION',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 3. Assigned State Section
                if (isAssigned) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.success.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                slot.assignedUserName ?? 'Assigned Musician',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Confirmed substitute for ${slot.instrument}',
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _revokeAssignment(slot),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          child: Text(
                            'Change',
                            style: GoogleFonts.inter(
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 4. Candidate List Section (If Published & Has Responders)
                if (slot.status == 'published' && !isAssigned && slot.candidates.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'CANDIDATES (${slot.candidates.length})',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...slot.candidates.map((candidate) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0C20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                            child: Text(
                              candidate.name.substring(0, 1).toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  candidate.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${candidate.instruments} • ${candidate.location}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.success,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () => _assignCandidate(slot, candidate),
                            child: Text(
                              'Assign',
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
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SubstituteSlotDraft slot) {
    if (slot.status == 'assigned') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.success.withOpacity(0.5)),
        ),
        child: Text(
          slot.assignedUserName != null ? '${slot.assignedUserName} assigned' : 'Assigned',
          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold),
        ),
      );
    } else if (slot.status == 'draft') {
      if (slot.isSuggested && !slot.isConfirmed) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.withOpacity(0.5)),
          ),
          child: Text(
            'Suggested (${slot.rsvpStatus ?? "Uncertain"})',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Draft',
          style: GoogleFonts.inter(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      if (slot.candidates.isNotEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
          ),
          child: Text(
            '${slot.candidates.length} candidate${slot.candidates.length == 1 ? "" : "s"}',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold),
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
        ),
        child: Text(
          'Waiting for answers',
          style: GoogleFonts.inter(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
        ),
      );
    }
  }
}
