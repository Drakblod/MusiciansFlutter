import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/agreement.dart';
import '../models/band.dart';
import '../models/band_event.dart';
import '../models/message.dart';
import '../data/skills_taxonomy.dart';
import '../models/sub_request.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class ResponderItem {
  final String userId;
  final String name;
  final String instruments;
  final String location;

  ResponderItem({
    required this.userId,
    required this.name,
    required this.instruments,
    required this.location,
  });
}

class SubstituteSlotDraft {
  final String slotId;
  final String? eventId;
  final String? subRequestId;
  String instrument;
  String searchSource;
  Set<String> selectedFavoriteIds;
  String? replacedMemberId;
  String? replacedMemberName;
  String? rsvpStatus;
  bool isSuggested;
  bool isConfirmed;
  String status;
  String? assignedUserId;
  String? assignedUserName;
  int? assignedAt;
  List<ResponderItem> candidates;
  bool isExpanded;
  String addFavoriteQuery;

  SubstituteSlotDraft({
    required this.slotId,
    this.eventId,
    this.subRequestId,
    required this.instrument,
    this.searchSource = 'search_all',
    Set<String>? selectedFavoriteIds,
    this.replacedMemberId,
    this.replacedMemberName,
    this.rsvpStatus,
    this.isSuggested = false,
    this.isConfirmed = false,
    this.status = 'draft',
    this.assignedUserId,
    this.assignedUserName,
    this.assignedAt,
    List<ResponderItem>? candidates,
    this.isExpanded = true,
    this.addFavoriteQuery = '',
  })  : selectedFavoriteIds = selectedFavoriteIds ?? {},
        candidates = candidates ?? [];
}

class EventStaffingSection {
  final BandEvent event;
  final int sequence;
  final List<SubstituteSlotDraft> slots;
  final TextEditingController titleController;
  String? selectedEventType;
  final TextEditingController descriptionController;
  final TextEditingController locationController;
  DateTime selectedDate;
  TimeOfDay startTime;
  TimeOfDay endTime;

  EventStaffingSection({
    required this.event,
    required this.sequence,
    required this.slots,
    required this.titleController,
    this.selectedEventType,
    required this.descriptionController,
    required this.locationController,
    required this.selectedDate,
    required this.startTime,
    required this.endTime,
  });

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
  }
}

class FindSubScreen extends StatefulWidget {
  final String? eventId;
  final String? bandId;
  final SubRequest? initialRequest;

  const FindSubScreen({
    super.key,
    this.eventId,
    this.bandId,
    this.initialRequest,
  });

  @override
  State<FindSubScreen> createState() => _FindSubScreenState();
}

class _FindSubScreenState extends State<FindSubScreen> {
  final _messageController = TextEditingController();
  final _locationController = TextEditingController();
  final _amountController = TextEditingController(text: '1500');
  String? _existingRequestGroupId;
  String? _canonicalMultipleEventParentId;

  String _currentMode = 'substitute';
  String _selectedNewMemberInstrument = 'Electric Guitar';
  String _newMemberSource = 'search_all';
  Set<String> _selectedNewMemberFavorites = {};

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 4));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isPaid = true;
  bool _isSubmitting = false;
  bool _isLoading = true;

  BandEvent? _primaryEvent;
  String? _bandName;
  List<UserProfile> _favorites = [];
  List<UserProfile> _allMusicianProfiles = [];
  List<EventStaffingSection> _eventSections = [];

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

  String _shortenTitle(String title, {int maxLength = 24}) {
    if (title.length <= maxLength) return title;
    return title.substring(0, maxLength - 3) + '...';
  }

  Future<void> _loadFavoritesAndProfiles() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();

      final List<UserProfile> loadedFavs = [];
      for (final id in favIds) {
        final profile = await appState.firebaseService.getUserProfileAsync(id);
        if (profile != null) {
          loadedFavs.add(profile);
        }
      }

      List<UserProfile> allProfiles = [];
      try {
        allProfiles = await appState.firebaseService.getAllUsersAsync();
      } catch (e) {
        debugPrint('Note: getAllUsersAsync not available or empty: ' + e.toString());
      }

      if (mounted) {
        setState(() {
          _favorites = loadedFavs;
          _allMusicianProfiles = allProfiles;
        });
      }
    } catch (e) {
      debugPrint('Error loading favorites or profiles: ' + e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialRequest != null) {
      final init = widget.initialRequest!;
      if (init.role == 'New Member') {
        _currentMode = 'new_member';
        _selectedNewMemberInstrument = (init.voicePart != null && init.voicePart!.isNotEmpty) ? init.voicePart! : 'Electric Guitar';
        _messageController.text = init.description ?? '';
        _newMemberSource = init.searchSource ?? 'search_all';
        if (init.targetUserIds != null) {
          _selectedNewMemberFavorites = init.targetUserIds!.toSet();
        }
      } else {
        _currentMode = 'substitute';
        _messageController.text = init.description ?? '';
        _isPaid = init.isPaid;
        if (init.payAmount != null) {
          _amountController.text = init.payAmount.toString();
        }
      }
    }
    _loadDataAsync();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _locationController.dispose();
    _amountController.dispose();
    for (final section in _eventSections) {
      section.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDataAsync() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);

    await _loadFavoritesAndProfiles();

    final effectiveBandId = widget.bandId ?? appState.activeBandId;
    final effectiveEventId = widget.eventId;

    if (_locationController.text.isEmpty) {
      _locationController.text = appState.currentUserProfile?.location ?? 'Stockholm, Sweden';
    }

    if (effectiveBandId != null && effectiveBandId.isNotEmpty) {
      try {
        final band = await appState.firebaseService.getBandInfoAsync(effectiveBandId);
        if (band != null) {
          _bandName = band.name;
        }
      } catch (e) {
        debugPrint('Error loading band info: ' + e.toString());
      }
    }

    if (effectiveBandId != null && effectiveBandId.isNotEmpty && effectiveEventId != null && effectiveEventId.isNotEmpty) {
      try {
        var event = await appState.firebaseService.getBandEventOnceAsync(effectiveBandId, effectiveEventId);
        _primaryEvent = event;

        event ??= BandEvent(
          id: effectiveEventId,
          title: _bandName ?? appState.activeBandName ?? 'Freelance Gig',
          description: 'Single Gig',
          additionalNotes: '',
          eventType: 'Gig',
          location: _locationController.text.isNotEmpty ? _locationController.text : (appState.currentUserProfile?.location ?? 'Stockholm, Sweden'),
          startDateTime: _selectedDate.toIso8601String(),
          endDateTime: _selectedDate.add(const Duration(hours: 3)).toIso8601String(),
          createdBy: appState.currentUserId ?? 'user',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          requireResponse: true,
        );

        if (event.startDateTime.isNotEmpty) {
            final parsedDate = DateTime.tryParse(event.startDateTime);
            if (parsedDate != null) {
              _selectedDate = parsedDate.toLocal();
              _startTime = TimeOfDay(hour: _selectedDate.hour, minute: _selectedDate.minute);
            }
          }
          if (event.endDateTime.isNotEmpty) {
            final parsedEnd = DateTime.tryParse(event.endDateTime);
            if (parsedEnd != null) {
              _endTime = TimeOfDay(hour: parsedEnd.toLocal().hour, minute: parsedEnd.toLocal().minute);
            }
          }
          if (event.location.isNotEmpty) {
            _locationController.text = event.location;
          }

          List<BandEvent> relatedEvents = [];
          final allBandEvents = await appState.firebaseService.getBandEventsListAsync(effectiveBandId);
          final parentId = event.parentEventId;
          final currentId = event.id ?? effectiveEventId;
          final hasChildEvents = allBandEvents.any((e) => e.parentEventId == currentId);
          final isMulti = event.eventType.toLowerCase().contains('multiple') ||
              hasChildEvents ||
              (parentId != null && parentId.isNotEmpty);

          final effectiveParentId = (parentId != null && parentId.isNotEmpty)
              ? parentId
              : (isMulti ? currentId : null);

          _canonicalMultipleEventParentId = effectiveParentId;

          if (effectiveParentId != null && effectiveParentId.isNotEmpty) {
            final explicitChildren = allBandEvents
                .where((e) => e.parentEventId == effectiveParentId)
                .toList();

            if (explicitChildren.isNotEmpty) {
              // The parent BandEvent is a group/header. Render only real playable child occurrences.
              relatedEvents = explicitChildren;
            } else {
              relatedEvents = allBandEvents
                  .where((e) => e.parentEventId == effectiveParentId || e.id == effectiveParentId)
                  .toList();
            }

            relatedEvents.sort((a, b) {
              final seqA = a.subEventSequence ?? 1;
              final seqB = b.subEventSequence ?? 1;
              return seqA.compareTo(seqB);
            });
          }

          if (relatedEvents.isEmpty) {
            relatedEvents = [event];
          }

          final List<EventStaffingSection> sections = [];
          for (int i = 0; i < relatedEvents.length; i++) {
            final ev = relatedEvents[i];
            final seq = ev.subEventSequence ?? (i + 1);
            final evId = ev.id ?? effectiveEventId;

            final existingSubRequests = await appState.firebaseService.getSubRequestsForEventAsync(effectiveBandId, evId);

            final List<SubstituteSlotDraft> slots = [];
            for (int sIdx = 0; sIdx < existingSubRequests.length; sIdx++) {
              final subReq = existingSubRequests[sIdx];
              if (_existingRequestGroupId == null && subReq.requestGroupId != null && subReq.requestGroupId!.isNotEmpty) {
                _existingRequestGroupId = subReq.requestGroupId;
              }

              final subVoicePart = (subReq.voicePart != null && subReq.voicePart!.isNotEmpty) ? subReq.voicePart! : 'Electric Guitar';
              final subSlotId = (subReq.slotId != null && subReq.slotId!.isNotEmpty) ? subReq.slotId! : ('slot_' + evId + '_' + sIdx.toString());

              final candidates = await _loadCandidatesForSubRequest(subReq);
              final matchingFavs = _getFilteredFavoritesForInstrument(subVoicePart);
              final targetFavIds = subReq.targetUserIds != null && subReq.targetUserIds!.isNotEmpty
                  ? subReq.targetUserIds!.toSet()
                  : matchingFavs.map((f) => f.userId!).toSet();

              slots.add(
                SubstituteSlotDraft(
                  slotId: subSlotId,
                  eventId: evId,
                  subRequestId: subReq.id ?? subReq.subRequestId,
                  instrument: subVoicePart,
                  replacedMemberId: subReq.replacedMemberId,
                  replacedMemberName: subReq.replacedMemberName,
                  searchSource: subReq.searchSource ?? 'search_all',
                  selectedFavoriteIds: targetFavIds,
                  status: subReq.status,
                  assignedUserId: subReq.assignedUserId,
                  assignedUserName: subReq.assignedUserName,
                  assignedAt: subReq.assignedAt,
                  candidates: candidates,
                  isExpanded: true,
                ),
              );
            }

            if (slots.isEmpty) {
              final bandMembers = await appState.firebaseService.getBandMembersAsync(effectiveBandId);
              final rsvpResponses = ev.responses;

              if (bandMembers.isNotEmpty && rsvpResponses.isNotEmpty) {
                for (final member in bandMembers) {
                  final memberUserId = member.userId ?? '';
                  if (memberUserId.isEmpty) continue;
                  final resp = rsvpResponses[memberUserId];
                  final status = resp?.status.toUpperCase() ?? 'NO ANSWER';
                  if (status == 'YES') continue;

                  final memberProf = await appState.firebaseService.getUserProfileAsync(memberUserId);
                  final roleStr = member.role ?? '';
                  final nicknameStr = member.nickname ?? '';
                  final String instrument = (memberProf?.instruments.isNotEmpty ?? false)
                      ? memberProf!.instruments.first
                      : ((memberProf?.userType != null && memberProf!.userType!.isNotEmpty)
                          ? memberProf.userType!
                          : (roleStr.isNotEmpty && roleStr != 'Member' && roleStr != 'Leader' ? roleStr : 'Electric Guitar'));
                  final matchingFavs = _getFilteredFavoritesForInstrument(instrument);

                  final bool isNo = (status == 'NO');
                  slots.add(
                    SubstituteSlotDraft(
                      slotId: 'draft_' + evId + '_' + memberUserId,
                      eventId: evId,
                      instrument: instrument,
                      replacedMemberId: memberUserId,
                      replacedMemberName: (memberProf?.displayName != null && memberProf!.displayName!.isNotEmpty)
                          ? memberProf.displayName
                          : (nicknameStr.isNotEmpty ? nicknameStr : ('Musician ' + memberUserId)),
                      searchSource: 'search_all',
                      selectedFavoriteIds: matchingFavs.map((f) => f.userId!).toSet(),
                      status: 'draft',
                      rsvpStatus: isNo ? null : status,
                      isSuggested: !isNo,
                      isConfirmed: isNo,
                      isExpanded: true,
                    ),
                  );
                }
              }

              if (slots.isEmpty) {
                final defaultInstrument = _suggestDefaultInstrument(ev, seq);
                final matchingFavs = _getFilteredFavoritesForInstrument(defaultInstrument);
                slots.add(
                  SubstituteSlotDraft(
                    slotId: 'draft_' + evId + '_0',
                    eventId: evId,
                    instrument: defaultInstrument,
                    searchSource: 'search_all',
                    selectedFavoriteIds: matchingFavs.map((f) => f.userId!).toSet(),
                    status: 'draft',
                    isConfirmed: true,
                    isExpanded: true,
                  ),
                );
              }
            }

            DateTime secDate = _selectedDate;
            TimeOfDay secStartTime = _startTime;
            TimeOfDay secEndTime = _endTime;
            if (ev.startDateTime.isNotEmpty) {
              final parsed = DateTime.tryParse(ev.startDateTime)?.toLocal();
              if (parsed != null) {
                secDate = parsed;
                secStartTime = TimeOfDay(hour: parsed.hour, minute: parsed.minute);
              }
            }
            if (ev.endDateTime.isNotEmpty) {
              final parsedEnd = DateTime.tryParse(ev.endDateTime)?.toLocal();
              if (parsedEnd != null) {
                secEndTime = TimeOfDay(hour: parsedEnd.hour, minute: parsedEnd.minute);
              }
            }

            sections.add(
              EventStaffingSection(
                event: ev,
                sequence: seq,
                slots: slots,
                titleController: TextEditingController(text: ev.title),
                selectedEventType: ev.eventType.isNotEmpty ? ev.eventType : null,
                descriptionController: TextEditingController(text: ev.description.isNotEmpty ? ev.description : ev.additionalNotes),
                locationController: TextEditingController(text: ev.location),
                selectedDate: secDate,
                startTime: secStartTime,
                endTime: secEndTime,
              ),
            );
          }

          _eventSections = sections;
      } catch (e) {
        debugPrint('Error loading event staffing structure: ' + e.toString());
      }
    }

    if (_eventSections.isEmpty) {
      final isStandalone = (widget.eventId == null || widget.eventId!.isEmpty);
      final dummyEvent = BandEvent(
        id: widget.eventId,
        title: isStandalone ? '' : (_bandName ?? appState.activeBandName ?? ''),
        description: '',
        additionalNotes: '',
        eventType: isStandalone ? '' : 'Gig',
        location: isStandalone ? '' : (_locationController.text.isNotEmpty ? _locationController.text : (appState.currentUserProfile?.location ?? 'Stockholm, Sweden')),
        startDateTime: _selectedDate.toIso8601String(),
        endDateTime: _selectedDate.add(const Duration(hours: 3)).toIso8601String(),
        createdBy: appState.currentUserId ?? 'user',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        requireResponse: true,
      );

      final matchingFavs = _getFilteredFavoritesForInstrument('Electric Guitar');
      final initialSlot = SubstituteSlotDraft(
        slotId: (widget.initialRequest?.slotId != null && widget.initialRequest!.slotId!.isNotEmpty) ? widget.initialRequest!.slotId! : 'draft_initial_0',
        eventId: widget.eventId,
        subRequestId: widget.initialRequest?.id ?? widget.initialRequest?.subRequestId,
        instrument: (widget.initialRequest?.voicePart != null && widget.initialRequest!.voicePart!.isNotEmpty) ? widget.initialRequest!.voicePart! : 'Electric Guitar',
        searchSource: widget.initialRequest?.searchSource ?? 'search_all',
        selectedFavoriteIds: widget.initialRequest?.targetUserIds != null
            ? widget.initialRequest!.targetUserIds!.toSet()
            : matchingFavs.map((f) => f.userId!).toSet(),
        status: widget.initialRequest?.status ?? 'draft',
        assignedUserId: widget.initialRequest?.assignedUserId,
        assignedUserName: widget.initialRequest?.assignedUserName,
        assignedAt: widget.initialRequest?.assignedAt,
        isExpanded: true,
      );

      _eventSections = [
        EventStaffingSection(
          event: dummyEvent,
          sequence: 1,
          slots: [initialSlot],
          titleController: TextEditingController(text: dummyEvent.title),
          selectedEventType: isStandalone ? null : (dummyEvent.eventType.isNotEmpty ? dummyEvent.eventType : null),
          descriptionController: TextEditingController(text: isStandalone ? '' : _messageController.text),
          locationController: TextEditingController(text: dummyEvent.location),
          selectedDate: _selectedDate,
          startTime: _startTime,
          endTime: _endTime,
        ),
      ];
    }

    if (mounted) setState(() => _isLoading = false);
  }

  String _suggestDefaultInstrument(BandEvent ev, int sequence) {
    return 'Electric Guitar';
  }

  Future<List<ResponderItem>> _loadCandidatesForSubRequest(SubRequest subReq) async {
    final subRequestId = subReq.id ?? subReq.subRequestId ?? '';
    if (subRequestId.isEmpty) return [];
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      Map<String, dynamic> rawResponses = Map<String, dynamic>.from(subReq.responses);
      if (rawResponses.isEmpty) {
        rawResponses = await appState.firebaseService.getSubRequestResponsesAsync(subRequestId);
      }
      final List<ResponderItem> list = [];
      for (final entry in rawResponses.entries) {
        if (entry.value != true && entry.value != 1 && entry.value != 'true') continue;
        final userId = entry.key;
        final profile = await appState.firebaseService.getUserProfileAsync(userId);
        list.add(
          ResponderItem(
            userId: userId,
            name: profile?.displayName ?? profile?.nickname ?? 'Musician',
            instruments: profile?.instruments.join(', ') ?? 'Vocalist / Musician',
            location: profile?.location ?? 'Stockholm, Sweden',
          ),
        );
      }
      return list;
    } catch (e) {
      debugPrint('Error loading candidates: ' + e.toString());
      return [];
    }
  }

  void _addSubstituteToEvent(EventStaffingSection section) {
    setState(() {
      final newSlotIndex = section.slots.length;
      final defaultInstrument = 'Electric Guitar';
      final matchingFavs = _getFilteredFavoritesForInstrument(defaultInstrument);

      section.slots.add(
        SubstituteSlotDraft(
          slotId: 'draft_' + (section.event.id ?? widget.eventId ?? 'event') + '_' + newSlotIndex.toString(),
          eventId: section.event.id ?? widget.eventId,
          instrument: defaultInstrument,
          searchSource: 'search_all',
          selectedFavoriteIds: matchingFavs.map((f) => f.userId!).toSet(),
          status: 'draft',
          isExpanded: true,
        ),
      );
    });
  }

  void _removeSlot(EventStaffingSection section, SubstituteSlotDraft slot) {
    setState(() {
      section.slots.remove(slot);
      if (section.slots.isEmpty && _eventSections.length == 1) {
        final matchingFavs = _getFilteredFavoritesForInstrument('Electric Guitar');
        section.slots.add(
          SubstituteSlotDraft(
            slotId: 'draft_0',
            eventId: section.event.id,
            instrument: 'Electric Guitar',
            searchSource: 'search_all',
            selectedFavoriteIds: matchingFavs.map((f) => f.userId!).toSet(),
            status: 'draft',
          ),
        );
      }
    });
  }

  Future<void> _cancelPublishedSlot(EventStaffingSection section, SubstituteSlotDraft slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2A4E), width: 1),
        ),
        title: Text('Cancel Substitute Request?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to cancel this published substitute slot?', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Keep', style: GoogleFonts.inter(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel Request', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId ?? '';
      final subRequestId = slot.subRequestId ?? slot.slotId;

      setState(() => _isLoading = true);
      try {
        await appState.firebaseService.deleteSubRequestAsync(currentUserId, subRequestId);
        if (!mounted) return;
        setState(() {
          section.slots.remove(slot);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Substitute request cancelled.'), backgroundColor: AppTheme.success),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel request: ' + e.toString()), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openInstrumentPicker(SubstituteSlotDraft slot) async {
    final selectedList = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Select Instrument / Role',
      categoryMap: _allSkillsCategoryMap,
      initialSelected: [slot.instrument],
      isSingleSelect: true,
      presentation: CategoryPickerPresentation.skillsHierarchy,
    );
    if (selectedList != null && selectedList.isNotEmpty) {
      setState(() {
        slot.instrument = selectedList.first;
        if (slot.searchSource == 'favorites') {
          final matchingFavs = _getFilteredFavoritesForInstrument(slot.instrument);
          slot.selectedFavoriteIds = matchingFavs.map((f) => f.userId!).toSet();
        }
      });
    }
  }

  Future<void> _publishAllDraftRequests() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final profile = appState.currentUserProfile;
    final effectiveBandId = widget.bandId ?? appState.activeBandId;

    final isStandalone = (widget.eventId == null || widget.eventId!.isEmpty);
    if (isStandalone && _eventSections.isNotEmpty) {
      final sec = _eventSections.first;
      if (sec.titleController.text.trim().isEmpty || sec.selectedEventType == null || sec.selectedEventType!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Name of Event and select an Event Type before publishing.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
    }

    final List<SubstituteSlotDraft> draftSlots = [];
    for (final section in _eventSections) {
      for (final slot in section.slots) {
        if (slot.status == 'draft' && (!slot.isSuggested || slot.isConfirmed)) {
          if (slot.searchSource == 'favorites' && slot.selectedFavoriteIds.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No favorited musicians play ' + slot.instrument + '. Please select favorites or switch to Search All.'),
                backgroundColor: AppTheme.danger,
              ),
            );
            return;
          }
          draftSlots.add(slot);
        }
      }
    }

    if (draftSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No draft substitute positions to publish.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final safeBandId = (effectiveBandId ?? 'freelance').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final parentOrEventId = _canonicalMultipleEventParentId ?? widget.eventId ?? 'event';
      final safeEventId = parentOrEventId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final groupId = _existingRequestGroupId ?? ('group_${safeBandId}_${safeEventId}');
      final payAmount = _isPaid ? (int.tryParse(_amountController.text.trim()) ?? 0) : 0;
      final bandName = _bandName ?? appState.activeBandName ?? 'Freelance Gig';
      final pubId = 'pub_${groupId}_${now.millisecondsSinceEpoch}';

      final List<SubRequest> requestsToSave = [];

      for (final section in _eventSections) {
        final evId = section.event.id ?? widget.eventId ?? 'freelance_event';
        final evTitle = section.titleController.text.trim().isNotEmpty
            ? section.titleController.text.trim()
            : (section.event.title.isNotEmpty ? section.event.title : bandName);
        final evType = (section.selectedEventType != null && section.selectedEventType!.trim().isNotEmpty)
            ? section.selectedEventType!.trim()
            : (section.event.eventType.isNotEmpty ? section.event.eventType : 'Gig');
        final descStr = section.descriptionController.text.trim();
        final locStr = section.locationController.text.trim().isNotEmpty
            ? section.locationController.text.trim()
            : (section.event.location.isNotEmpty ? section.event.location : (profile?.location ?? 'Stockholm, Sweden'));
        final dateStr = section.selectedDate.toIso8601String();
        final startTimeStr = (section.startTime.hour.toString().padLeft(2, '0') + ':' + section.startTime.minute.toString().padLeft(2, '0'));
        final endTimeStr = (section.endTime.hour.toString().padLeft(2, '0') + ':' + section.endTime.minute.toString().padLeft(2, '0'));

        for (final slot in section.slots) {
          if (slot.status != 'draft') continue;

          final req = SubRequest(
            id: slot.subRequestId,
            subRequestId: slot.subRequestId,
            slotId: slot.slotId,
            eventId: evId,
            bandId: effectiveBandId,
            bandName: bandName,
            role: 'Substitute',
            voicePart: slot.instrument,
            description: descStr,
            date: dateStr,
            startTime: startTimeStr,
            endTime: endTimeStr,
            location: locStr,
            isPaid: _isPaid,
            payAmount: _isPaid ? payAmount : null,
            currency: 'SEK',
            searchSource: slot.searchSource,
            targetUserIds: slot.searchSource == 'favorites' ? slot.selectedFavoriteIds.toList() : null,
            status: 'published',
            replacedMemberId: slot.replacedMemberId,
            replacedMemberName: slot.replacedMemberName,
            requestGroupId: groupId,
            eventSequence: section.sequence,
            eventTitle: evTitle,
            createdAt: now.millisecondsSinceEpoch,
            extraFields: {'PublicationId': pubId, 'eventType': evType},
          );

          requestsToSave.add(req);
        }
      }

      await appState.firebaseService.publishSubRequestGroupAsync(
        bandId: effectiveBandId,
        requestGroupId: groupId,
        requests: requestsToSave,
        bandName: bandName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(requestsToSave.length.toString() + ' substitute position(s) published successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );

      await _loadDataAsync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish requests: ' + e.toString()), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _assignCandidate(
    EventStaffingSection section,
    SubstituteSlotDraft slot,
    ResponderItem candidate,
  ) async {
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
          'Assign ' + candidate.name + ' as substitute for ' + slot.instrument + '? This will mark them as attending for this event position.',
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
      final eventId = slot.eventId ?? widget.eventId ?? '';
      final subRequestId = slot.subRequestId ?? slot.slotId;
      final authorName = appState.currentUserProfile?.displayName ?? 'Organizer';
      final bandName = _bandName ?? appState.activeBandName ?? 'Freelance Gig';

      setState(() => _isLoading = true);
      try {
        if (currentUserId != null && subRequestId.isNotEmpty) {
          await appState.firebaseService.assignSubstituteCandidateAsync(
            subRequestId: subRequestId,
            candidateUserId: candidate.userId,
            bandId: bandId,
            eventId: eventId,
            roleOrInstrument: slot.instrument,
            candidateName: candidate.name,
            slotId: slot.slotId,
            replacedMemberId: slot.replacedMemberId,
            replacedMemberName: slot.replacedMemberName,
          );

          try {
            final agreement = Agreement(
              choirLeaderId: currentUserId,
              vocalistId: candidate.userId,
              voicePart: slot.instrument,
              date: _selectedDate.toIso8601String(),
              startTime: (_startTime.hour.toString().padLeft(2, '0') + ':' + _startTime.minute.toString().padLeft(2, '0')),
              endTime: (_endTime.hour.toString().padLeft(2, '0') + ':' + _endTime.minute.toString().padLeft(2, '0')),
              location: _locationController.text.trim(),
              additionalTerms: 'Substitute staffing assignment.',
              bandName: bandName,
            );

            final message = Message(
              id: '',
              senderId: currentUserId,
              receiverId: candidate.userId,
              text: candidate.name + ' has been chosen as substitute for ' + slot.instrument + '.',
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
            setState(() {
              slot.status = 'assigned';
              slot.assignedUserId = candidate.userId;
              slot.assignedUserName = candidate.name;
              slot.assignedAt = DateTime.now().millisecondsSinceEpoch;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(candidate.name + ' successfully assigned as substitute!'),
                backgroundColor: AppTheme.success,
              ),
            );
          } catch (chatError) {
            debugPrint('Warning: Agreement chat creation deferred/failed: ' + chatError.toString());
            if (!mounted) return;
            setState(() {
              slot.status = 'assigned';
              slot.assignedUserId = candidate.userId;
              slot.assignedUserName = candidate.name;
              slot.assignedAt = DateTime.now().millisecondsSinceEpoch;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(candidate.name + ' assigned successfully (chat notification deferred).'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to assign candidate: ' + e.toString()), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _revokeAssignment(
    EventStaffingSection section,
    SubstituteSlotDraft slot,
  ) async {
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
          'Reopen this position for other candidates? ' + (slot.assignedUserName ?? 'Musician') + ' will no longer be marked as assigned.',
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
      final currentUserId = appState.currentUserId ?? '';
      final subRequestId = slot.subRequestId ?? slot.slotId;

      setState(() => _isLoading = true);
      try {
        await appState.firebaseService.revokeSubstituteAssignmentAsync(
          subRequestId: subRequestId,
          candidateUserId: candidateId,
          bandId: widget.bandId ?? appState.activeBandId ?? '',
          eventId: slot.eventId ?? widget.eventId ?? '',
          slotId: slot.slotId,
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
            SnackBar(content: Text('Failed to revoke assignment: ' + e.toString()), backgroundColor: AppTheme.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final activeDraftSlots = _eventSections.expand((s) => s.slots).where((slot) => slot.status == 'draft' && (!slot.isSuggested || slot.isConfirmed)).toList();
    final isMultipleEvents = _eventSections.length > 1;

    final String publishButtonLabel;
    if (isMultipleEvents) {
      publishButtonLabel = 'PUBLISH MULTIPLE REQUEST';
    } else if (activeDraftSlots.length > 1) {
      publishButtonLabel = 'PUBLISH SUBSTITUTE REQUESTS (' + activeDraftSlots.length.toString() + ')';
    } else if (activeDraftSlots.length == 1) {
      publishButtonLabel = 'PUBLISH SUBSTITUTE REQUESTS (1)';
    } else {
      publishButtonLabel = 'PUBLISH SUBSTITUTE REQUESTS';
    }

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Find Musician',
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
                    Text(
                      'FIND MUSICIAN/VOCALIST',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_bandName != null || appState.activeBandName != null) ...[
                      Text(
                        _bandName ?? appState.activeBandName!,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Event information block (rendered once per occurrence before mode selector)
                    ..._eventSections.map((sec) => _buildEventInformationCard(sec, context)),

                    const SizedBox(height: 8),

                    // Global Mode Selector (rendered exactly once after all event info)
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedTapDetector(
                            onTap: () {
                              setState(() {
                                _currentMode = 'substitute';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _currentMode == 'substitute'
                                    ? AppTheme.primaryAccent.withOpacity(0.18)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _currentMode == 'substitute'
                                      ? AppTheme.primaryAccent
                                      : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Find Substitute(s)',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _currentMode == 'substitute'
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AnimatedTapDetector(
                            onTap: () {
                              setState(() {
                                _currentMode = 'new_member';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _currentMode == 'new_member'
                                    ? AppTheme.primaryAccent.withOpacity(0.18)
                                    : AppTheme.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _currentMode == 'new_member'
                                      ? AppTheme.primaryAccent
                                      : const Color(0xFF2E2A4E),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Find New Band Member(s)',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _currentMode == 'new_member'
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_currentMode == 'new_member')
                      _buildNewMemberView(context, appState)
                    else ...[
                      ..._eventSections.map((sec) => _buildSubstituteSectionCard(sec)),
                      _buildPaidGigSection(),
                      const SizedBox(height: 24),
                      _buildPublishButton(publishButtonLabel),
                      const SizedBox(height: 30),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  String _buildEventHeaderLabel(EventStaffingSection section) {
    final title = section.titleController.text.trim();
    final eventType = section.selectedEventType?.trim() ?? '';
    if (title.isEmpty && eventType.isEmpty) {
      return 'EVENT ' + section.sequence.toString();
    }
    final displayTitle = title.isNotEmpty ? title : (section.event.title.isNotEmpty ? section.event.title : 'Event');
    final displayType = eventType.isNotEmpty ? eventType : (section.event.eventType.isNotEmpty ? section.event.eventType : 'Gig');
    return 'EVENT ' + section.sequence.toString() + ' · ' + displayTitle + ' · ' + displayType;
  }

  Future<void> _pickDateForSection(EventStaffingSection section) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: section.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1A3A),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF16122B),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        section.selectedDate = picked;
      });
    }
  }

  Future<void> _pickTimeForSection(EventStaffingSection section, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? section.startTime : section.endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1A3A),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF16122B),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          section.startTime = picked;
        } else {
          section.endTime = picked;
        }
      });
    }
  }

  Widget _buildEventInformationCard(EventStaffingSection section, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1635),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _buildEventHeaderLabel(section),
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Name of Event
                Text(
                  'Name of Event',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: section.titleController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Enter event name',
                    hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1E1A3A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // 2. Event Type
                Text(
                  'Event Type',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: (section.selectedEventType != null && section.selectedEventType!.isNotEmpty) ? section.selectedEventType : null,
                  dropdownColor: const Color(0xFF1E1A3A),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  hint: Text('Select Event Type', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1A3A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                  ),
                  items: () {
                    final types = List<String>.from(BandEvent.standardEventTypes);
                    if (section.selectedEventType != null &&
                        section.selectedEventType!.isNotEmpty &&
                        !types.contains(section.selectedEventType)) {
                      types.add(section.selectedEventType!);
                    }
                    return types.map((t) => DropdownMenuItem<String>(
                      value: t,
                      child: Text(t, style: GoogleFonts.inter(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
                    )).toList();
                  }(),
                  onChanged: (val) {
                    setState(() {
                      section.selectedEventType = val;
                    });
                  },
                ),
                const SizedBox(height: 14),

                // 3. Description
                Text(
                  'Description',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: section.descriptionController,
                  maxLines: 2,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add description',
                    hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1E1A3A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Location
                Text(
                  'Location',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: section.locationController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.location_on_outlined, color: AppTheme.primaryAccent, size: 20),
                    hintText: 'Enter location',
                    hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1E1A3A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Date & Time
                Text(
                  'Date & Time',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Column(
                  children: [
                    InkWell(
                      onTap: () => _pickDateForSection(section),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryAccent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, MMMM d, yyyy').format(section.selectedDate),
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickTimeForSection(section, true),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, color: AppTheme.primaryAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      section.startTime.format(context),
                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickTimeForSection(section, false),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, color: AppTheme.primaryAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      section.endTime.format(context),
                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubstituteSectionCard(EventStaffingSection section) {
    final addLabel = _eventSections.length > 1
        ? ('ADD SUBSTITUTE TO EVENT ' + section.sequence.toString())
        : 'ADD ANOTHER SUBSTITUTE';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1635),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _buildEventHeaderLabel(section),
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                ...section.slots.asMap().entries.map((entry) {
                  final slotIdx = entry.key;
                  final slot = entry.value;
                  return _buildSlotCard(section, slot, slotIdx);
                }),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryAccent,
                      side: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _addSubstituteToEvent(section),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      addLabel,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(EventStaffingSection section, SubstituteSlotDraft slot, int slotIndex) {
    final eligibleFavorites = _getFilteredFavoritesForInstrument(slot.instrument);
    final isDraft = slot.status == 'draft';
    final bool isAssigned = slot.assignedUserId != null && slot.assignedUserId!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16122C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssigned
              ? AppTheme.success.withValues(alpha: 0.4)
              : (slot.isSuggested && !slot.isConfirmed
                  ? Colors.amber.withValues(alpha: 0.4)
                  : const Color(0xFF231F45)),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slot Header
          InkWell(
            onTap: () {
              setState(() {
                slot.isExpanded = !slot.isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SUBSTITUTE ' + (slotIndex + 1).toString(),
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  _buildStatusBadge(slot),
                  const SizedBox(width: 6),
                  Icon(
                    slot.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),

          if (slot.isExpanded) ...[
            const Divider(color: Color(0xFF231F45), height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Assigned substitute (Render ONLY when a substitute is actually assigned)
                  if (isAssigned) ...[
                    Text(
                      'Assigned substitute',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Assigned: ' + (slot.assignedUserName ?? 'Musician'),
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => _revokeAssignment(section, slot),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Revoke',
                              style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 2. Replacing (Show only when replacedMemberName is present)
                  if (slot.replacedMemberName != null && slot.replacedMemberName!.trim().isNotEmpty) ...[
                    Text(
                      'Replacing',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1A3A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2E2A4E)),
                      ),
                      child: Text(
                        slot.replacedMemberName!,
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 3. Instrument/Skill (Singular)
                  InkWell(
                    onTap: isDraft ? () => _openInstrumentPicker(slot) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Instrument/Skill',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A3A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2E2A4E)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  slot.instrument,
                                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDraft)
                                const Icon(Icons.arrow_drop_down, color: AppTheme.primaryAccent, size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 4. Source Selector (Favorites List / Search All)
                  if (isDraft) ...[
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                slot.searchSource = 'favorites';
                                if (slot.selectedFavoriteIds.isEmpty) {
                                  final matching = _getFilteredFavoritesForInstrument(slot.instrument);
                                  slot.selectedFavoriteIds = matching.map((f) => f.userId!).toSet();
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: slot.searchSource == 'favorites'
                                    ? AppTheme.primaryAccent.withOpacity(0.2)
                                    : const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: slot.searchSource == 'favorites'
                                      ? AppTheme.primaryAccent
                                      : const Color(0xFF2E2A4E),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Favorites List',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: slot.searchSource == 'favorites' ? Colors.white : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                slot.searchSource = 'search_all';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: slot.searchSource == 'search_all'
                                    ? AppTheme.primaryAccent.withOpacity(0.2)
                                    : const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: slot.searchSource == 'search_all'
                                      ? AppTheme.primaryAccent
                                      : const Color(0xFF2E2A4E),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Search All',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: slot.searchSource == 'search_all' ? Colors.white : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (slot.searchSource == 'favorites') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Favorites List',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 8),

                            TextField(
                              onChanged: (val) {
                                setState(() {
                                  slot.addFavoriteQuery = val;
                                });
                              },
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Add Favorites',
                                hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryAccent, size: 18),
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFF16122C),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF2E2A4E)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                                ),
                              ),
                            ),

                            if (slot.addFavoriteQuery.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final appState = Provider.of<AppState>(context, listen: false);
                                  final currentUserId = appState.currentUserId;
                                  final existingFavIds = _favorites.map((f) => f.userId).toSet();
                                  final query = slot.addFavoriteQuery.trim().toLowerCase();

                                  final results = _allMusicianProfiles.where((p) {
                                    if (p.userId == null || p.userId == currentUserId) return false;
                                    if (existingFavIds.contains(p.userId)) return false;
                                    final name = (p.displayName ?? p.nickname ?? '').toLowerCase();
                                    final uType = (p.userType ?? '').toLowerCase();
                                    final insts = p.instruments.map((i) => i.toLowerCase()).toList();
                                    return name.contains(query) || uType.contains(query) || insts.any((i) => i.contains(query));
                                  }).toList();

                                  if (results.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        'No matching musicians to add.',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                    );
                                  }

                                  return Container(
                                    constraints: const BoxConstraints(maxHeight: 140),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16122C),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF2E2A4E)),
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: results.length,
                                      itemBuilder: (context, idx) {
                                        final prof = results[idx];
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            prof.displayName ?? prof.nickname ?? 'Musician',
                                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: Text(
                                            prof.instruments.join(', '),
                                            style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.star_border_rounded, color: AppTheme.primaryAccent, size: 20),
                                            onPressed: () async {
                                              try {
                                                await appState.firebaseService.toggleFavoriteAsync(prof.userId!, true);
                                                setState(() {
                                                  _favorites.add(prof);
                                                  slot.selectedFavoriteIds.add(prof.userId!);
                                                  slot.addFavoriteQuery = '';
                                                });
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text((prof.displayName ?? 'Musician') + ' added to Favorites.'),
                                                    backgroundColor: AppTheme.success,
                                                  ),
                                                );
                                              } catch (e) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Failed to add favorite: ' + e.toString()), backgroundColor: AppTheme.danger),
                                                );
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ],

                            const SizedBox(height: 8),

                            Row(
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                                  onPressed: () {
                                    setState(() {
                                      final eligible = _getFilteredFavoritesForInstrument(slot.instrument);
                                      slot.selectedFavoriteIds.addAll(eligible.map((m) => m.userId!).where((id) => id.isNotEmpty));
                                    });
                                  },
                                  child: Text('SELECT ALL', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                                  onPressed: () {
                                    setState(() {
                                      slot.selectedFavoriteIds.clear();
                                    });
                                  },
                                  child: Text('CLEAR ALL', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60)),
                                ),
                                const Spacer(),
                                Text(
                                  slot.selectedFavoriteIds.length.toString() + ' of ' + eligibleFavorites.length.toString() + ' favorites selected',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),

                            if (eligibleFavorites.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'No favorited ' + slot.instrument + ' players found.',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.amberAccent),
                                ),
                              )
                            else
                              ...eligibleFavorites.map((fav) {
                                final uid = fav.userId ?? '';
                                final isChecked = slot.selectedFavoriteIds.contains(uid);
                                return CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: isChecked,
                                  activeColor: AppTheme.primaryAccent,
                                  checkColor: Colors.white,
                                  title: Text(
                                    fav.displayName ?? fav.nickname ?? 'Musician',
                                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    fav.instruments.join(', '),
                                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        slot.selectedFavoriteIds.add(uid);
                                      } else {
                                        slot.selectedFavoriteIds.remove(uid);
                                      }
                                    });
                                  },
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ],

                  if (slot.isSuggested && !slot.isConfirmed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'RSVP: ' + (slot.rsvpStatus ?? 'Uncertain') + '. Explicitly confirm to publish this slot.',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber[700],
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () {
                              setState(() {
                                slot.isConfirmed = true;
                              });
                            },
                            child: Text('CONFIRM & INCLUDE POSITION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (slot.candidates.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'CANDIDATES (' + slot.candidates.length.toString() + ')',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                    ),
                    const SizedBox(height: 6),
                    ...slot.candidates.map((cand) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cand.name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(cand.instruments + ' · ' + cand.location, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              onPressed: () => _assignCandidate(section, slot, cand),
                              child: Text('Assign', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: isDraft
                        ? TextButton.icon(
                            onPressed: () => _removeSlot(section, slot),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 16),
                            label: Text('Remove Slot', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 12)),
                          )
                        : TextButton.icon(
                            onPressed: () => _cancelPublishedSlot(section, slot),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 16),
                            label: Text('Cancel Slot Request', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 12)),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SubstituteSlotDraft slot) {
    final bool isAssigned = slot.assignedUserId != null && slot.assignedUserId!.trim().isNotEmpty;
    if (isAssigned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
        ),
        child: Text(
          slot.assignedUserName != null ? (slot.assignedUserName! + ' assigned') : 'Assigned',
          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold),
        ),
      );
    } else if (slot.status == 'published' || slot.status == 'assigned') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primaryAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5)),
        ),
        child: Text(
          'Waiting for answers',
          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
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
            'Suggested (' + (slot.rsvpStatus ?? 'Uncertain') + ')',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
          ),
        );
      }
      return const SizedBox.shrink();
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildPaidGigSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paid Gig',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Switch(
                value: _isPaid,
                activeColor: AppTheme.primaryAccent,
                onChanged: (val) {
                  setState(() {
                    _isPaid = val;
                  });
                },
              ),
            ],
          ),
          if (_isPaid) ...[
            const SizedBox(height: 12),
            Text(
              'Amount',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                prefixText: 'SEK ',
                prefixStyle: GoogleFonts.inter(
                  color: AppTheme.primaryAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                hintText: '1500',
                hintStyle: GoogleFonts.inter(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1E1A3A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  borderSide: const BorderSide(color: AppTheme.primaryAccent, width: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPublishButton(String publishButtonLabel) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        onPressed: _isSubmitting ? null : _publishAllDraftRequests,
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                publishButtonLabel,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildNewMemberView(BuildContext context, AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permanent Band Recruitment',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Publish an open position to find a permanent band member.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              Text(
                'Instrument / Role',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _openNewMemberInstrumentPicker,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1A3A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E2A4E)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _selectedNewMemberInstrument,
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: AppTheme.primaryAccent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Search Source',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _newMemberSource = 'search_all';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _newMemberSource == 'search_all'
                              ? AppTheme.primaryAccent.withOpacity(0.2)
                              : const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _newMemberSource == 'search_all'
                                ? AppTheme.primaryAccent
                                : const Color(0xFF2E2A4E),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Search All',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _newMemberSource == 'search_all' ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _newMemberSource = 'favorites';
                          if (_selectedNewMemberFavorites.isEmpty) {
                            final matchingFavs = _getFilteredFavoritesForInstrument(_selectedNewMemberInstrument);
                            _selectedNewMemberFavorites = matchingFavs.map((f) => f.userId!).toSet();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _newMemberSource == 'favorites'
                              ? AppTheme.primaryAccent.withOpacity(0.2)
                              : const Color(0xFF1E1A3A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _newMemberSource == 'favorites'
                                ? AppTheme.primaryAccent
                                : const Color(0xFF2E2A4E),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Favorites List',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _newMemberSource == 'favorites' ? Colors.white : AppTheme.textSecondary,
                            ),
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
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSubmitting ? null : _submitNewMemberRequest,
            child: _isSubmitting
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    'PUBLISH NEW MEMBER SEARCH',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openNewMemberInstrumentPicker() async {
    final selectedList = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Select Instrument / Role',
      categoryMap: _allSkillsCategoryMap,
      initialSelected: [_selectedNewMemberInstrument],
      isSingleSelect: true,
    );
    if (selectedList != null && selectedList.isNotEmpty) {
      setState(() {
        _selectedNewMemberInstrument = selectedList.first;
      });
    }
  }

  Future<void> _submitNewMemberRequest() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final profile = appState.currentUserProfile;
    final effectiveBandId = widget.bandId ?? appState.activeBandId;

    final isStandalone = (widget.eventId == null || widget.eventId!.isEmpty);
    if (isStandalone && _eventSections.isNotEmpty) {
      final sec = _eventSections.first;
      if (sec.titleController.text.trim().isEmpty || sec.selectedEventType == null || sec.selectedEventType!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Name of Event and select an Event Type before publishing.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      String newMemberDesc = '';
      String newMemberLoc = profile?.location ?? 'Stockholm, Sweden';
      String newMemberType = 'Gig';
      String newMemberTitle = _bandName ?? appState.activeBandName ?? 'Freelance Band';

      if (_eventSections.isNotEmpty) {
        final sec = _eventSections.first;
        if (sec.descriptionController.text.trim().isNotEmpty) {
          newMemberDesc = sec.descriptionController.text.trim();
        }
        if (sec.locationController.text.trim().isNotEmpty) {
          newMemberLoc = sec.locationController.text.trim();
        }
        if (sec.selectedEventType != null && sec.selectedEventType!.trim().isNotEmpty) {
          newMemberType = sec.selectedEventType!.trim();
        }
        if (sec.titleController.text.trim().isNotEmpty) {
          newMemberTitle = sec.titleController.text.trim();
        }
      }

      final req = SubRequest(
        role: 'New Member',
        voicePart: _selectedNewMemberInstrument,
        description: newMemberDesc,
        location: newMemberLoc,
        bandId: effectiveBandId,
        bandName: _bandName ?? appState.activeBandName ?? 'Freelance Band',
        searchSource: _newMemberSource,
        targetUserIds: _newMemberSource == 'favorites' ? _selectedNewMemberFavorites.toList() : null,
        status: 'published',
        eventTitle: newMemberTitle,
        extraFields: {'eventType': newMemberType},
      );

      await appState.firebaseService.saveSubRequestsBatchAsync([req]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New band member request published!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: ' + e.toString()), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
