import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sub_request.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/map_pin_details_helper.dart';
import '../utils/map_view_unified_feed_helper.dart';
import '../utils/map_event_activity_helper.dart';
import 'audio_snippet_player.dart';
import '../views/event_details_page.dart';
import '../views/public_event_details_screen.dart';
import '../views/sub_request_responses_screen.dart';
import '../models/public_calendar_event.dart';
import '../models/band_event.dart';

/// Card widget displaying the details of a focused or selected Map View pin.
/// Strictly follows the approved 6-item information order and labels, plus
/// role-specific staffing application & management actions (MAP-VIEW-APPLY-01).
class MapPinDetailsCard extends StatefulWidget {
  final SubRequest gig;
  final List<SubRequest>? groupedGigs;
  final AppState appState;
  final VoidCallback? onClose;
  final String? focusedTargetId;
  final void Function(BuildContext context, String bandId)? onOpenBandProfile;
  final void Function(SubRequest gig)? onEditPin;
  final void Function(SubRequest gig)? onDeletePin;
  final void Function(BuildContext context, SubRequest gig)? onManageRequest;
  final void Function(String subRequestId)? onAppliedSuccess;

  const MapPinDetailsCard({
    super.key,
    required this.gig,
    this.groupedGigs,
    required this.appState,
    this.onClose,
    this.focusedTargetId,
    this.onOpenBandProfile,
    this.onEditPin,
    this.onDeletePin,
    this.onManageRequest,
    this.onAppliedSuccess,
  });

  @override
  State<MapPinDetailsCard> createState() => _MapPinDetailsCardState();
}

class _MapPinDetailsCardState extends State<MapPinDetailsCard> {
  final Set<String> _appliedSlotIds = {};
  bool _isBandAdmin = false;
  bool _isLoadingRoleOrStatus = false;
  bool _isSubmitting = false;
  bool _isDialogOpen = false;
  String? _selectedSlotId;
  String? _applicationError;
  int _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initCardState();
  }

  @override
  void didUpdateWidget(covariant MapPinDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = _getAllCandidateSlots(oldWidget.gig, oldWidget.groupedGigs)
        .map((r) => _slotIdOf(r))
        .join('|');
    final newIds = _getAllCandidateSlots(widget.gig, widget.groupedGigs)
        .map((r) => _slotIdOf(r))
        .join('|');
    final oldStatuses = _getAllCandidateSlots(oldWidget.gig, oldWidget.groupedGigs)
        .map((r) => '${r.status}:${r.assignedUserId ?? ""}')
        .join('|');
    final newStatuses = _getAllCandidateSlots(widget.gig, widget.groupedGigs)
        .map((r) => '${r.status}:${r.assignedUserId ?? ""}')
        .join('|');

    if (oldIds != newIds ||
        oldStatuses != newStatuses ||
        !identical(oldWidget.appState, widget.appState) ||
        oldWidget.appState.currentUserId != widget.appState.currentUserId) {
      _initCardState();
    } else {
      _syncFromSessionCache();
    }
  }

  @override
  void dispose() {
    _lookupGeneration++;
    super.dispose();
  }

  String _slotIdOf(SubRequest r) {
    final sId = r.subRequestId?.trim();
    if (sId != null && sId.isNotEmpty) return sId;
    return (r.id ?? '').trim();
  }

  bool _isSlotApplied(String? slotId) {
    if (slotId == null || slotId.trim().isEmpty) return false;
    return _appliedSlotIds.contains(slotId.trim());
  }

  List<SubRequest> _getAllCandidateSlots(SubRequest primary, List<SubRequest>? grouped) {
    if (grouped != null && grouped.isNotEmpty) {
      final seen = <String>{};
      final result = <SubRequest>[];
      for (final g in grouped) {
        final id = _slotIdOf(g);
        if (id.isNotEmpty && seen.add(id)) {
          result.add(g);
        }
      }
      if (result.isNotEmpty) return result;
    }
    return [primary];
  }

  bool _isGenuineStaffingItem(SubRequest item) {
    final id = _slotIdOf(item);
    if (id.isEmpty) return false;
    if (id.startsWith('mock_') ||
        id.startsWith('demo_sthlm_') ||
        item.extraFields['isDemoStockholm'] == true ||
        item.extraFields['isMock'] == true) {
      return false;
    }
    if (item.extraFields['isEventProjection'] == true ||
        id.startsWith('event:') ||
        item.extraFields['eventSource'] != null) {
      return false;
    }
    if (item.isMapOnlyPin) {
      return false;
    }
    final kind = classifyMapItem(item);
    return kind == MapItemKind.staffingRequest || kind == MapItemKind.newMemberRequest;
  }

  bool _isCreatorOf(SubRequest item, String? currentUserId) {
    if (currentUserId == null || currentUserId.trim().isEmpty) return false;
    final uid = currentUserId.trim();
    return item.creatorUserId == uid ||
        item.userId == uid ||
        item.extraFields['creatorUserId'] == uid ||
        item.extraFields['CreatorUserId'] == uid;
  }

  bool _isSlotOpenAndEligibleForMusician(SubRequest slot, String? currentUserId) {
    if (!_isGenuineStaffingItem(slot)) return false;
    if (_isCreatorOf(slot, currentUserId)) return false;

    final st = slot.status.trim().toLowerCase();
    if (st == 'assigned' ||
        st == 'cancelled' ||
        st == 'deleted' ||
        st == 'closed' ||
        st == 'archived') {
      return false;
    }
    if (st != 'published' && st != 'open' && st != 'active') {
      return false;
    }
    if (slot.assignedUserId != null && slot.assignedUserId!.trim().isNotEmpty) {
      return false;
    }
    if (slot.isSelected == true) {
      return false;
    }
    if (!isMapEventVisible(slot, now: DateTime.now())) {
      return false;
    }

    // Check private audience restrictions if targetUserIds is explicitly populated
    final rawType = (slot.extraFields['Type'] ?? slot.extraFields['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isFavoritesOnly = slot.extraFields['isFavoritesOnly'] == true ||
        slot.extraFields['IsFavoritesOnly'] == true ||
        (slot.searchSource ?? '').trim().toLowerCase() == 'favorites';
    final isPrivate = rawType == 'direct_invitation' ||
        rawType == 'direct' ||
        isFavoritesOnly ||
        (slot.targetUserIds != null && slot.targetUserIds!.isNotEmpty);

    if (isPrivate && slot.targetUserIds != null && slot.targetUserIds!.isNotEmpty) {
      if (currentUserId == null || !slot.targetUserIds!.contains(currentUserId)) {
        return false;
      }
    }

    return true;
  }

  void _syncFromSessionCache() {
    final currentUserId = widget.appState.currentUserId;
    final slots = _getAllCandidateSlots(widget.gig, widget.groupedGigs);
    for (final s in slots) {
      final sId = _slotIdOf(s);
      if (sId.isEmpty) continue;
      if (widget.appState.hasAppliedToSubRequest(sId)) {
        _appliedSlotIds.add(sId);
      }
      if (currentUserId != null &&
          currentUserId.isNotEmpty &&
          s.responses[currentUserId] == true) {
        _appliedSlotIds.add(sId);
        widget.appState.markSubRequestsApplied([sId], notify: false);
      }
    }
  }

  Future<void> _initCardState() async {
    final gen = ++_lookupGeneration;
    _applicationError = null;
    _isSubmitting = false;
    _appliedSlotIds.clear();
    _isBandAdmin = false;

    _syncFromSessionCache();

    final slots = _getAllCandidateSlots(widget.gig, widget.groupedGigs);
    final hasAnyStaffing = slots.any(_isGenuineStaffingItem);
    if (!hasAnyStaffing) {
      _selectedSlotId = null;
      if (mounted) setState(() {});
      return;
    }

    final currentUserId = widget.appState.currentUserId;
    final openSlots = slots
        .where((s) => _isSlotOpenAndEligibleForMusician(s, currentUserId))
        .toList();

    // Default selection if exactly 1 open unapplied slot exists
    final unappliedOpen = openSlots
        .where((s) => !_isSlotApplied(_slotIdOf(s)))
        .toList();
    if (unappliedOpen.length == 1) {
      _selectedSlotId = _slotIdOf(unappliedOpen.first);
    } else if (_selectedSlotId != null &&
        !unappliedOpen.any((s) => _slotIdOf(s) == _selectedSlotId)) {
      _selectedSlotId = null;
    }

    if (currentUserId == null || currentUserId.trim().isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final isCreator = slots.any((s) => _isCreatorOf(s, currentUserId));
    if (isCreator) {
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _isLoadingRoleOrStatus = true;
    });

    final bandId = (widget.gig.bandId ?? '').trim();
    final slotIds = slots.map(_slotIdOf).where((id) => id.isNotEmpty).toList();

    try {
      final results = await Future.wait<dynamic>([
        if (bandId.isNotEmpty && bandId != 'freelance' && bandId != 'standalone')
          widget.appState.firebaseService.isBandLeaderOrAdminAsync(bandId, currentUserId)
        else
          Future<bool>.value(false),
        if (slotIds.isNotEmpty)
          widget.appState.firebaseService.resolveAppliedSubRequestIdsForCardAsync(
            userId: currentUserId,
            subRequestIds: slotIds,
          )
        else
          Future<Set<String>>.value(<String>{}),
      ]);

      if (!mounted || gen != _lookupGeneration) return;

      final resolvedAdmin = results[0] as bool;
      final resolvedApplied = results[1] as Set<String>;

      if (resolvedApplied.isNotEmpty) {
        widget.appState.markSubRequestsApplied(resolvedApplied, notify: false);
      }

      setState(() {
        _isBandAdmin = resolvedAdmin;
        _appliedSlotIds.addAll(resolvedApplied);
        _isLoadingRoleOrStatus = false;

        final stillUnapplied = openSlots
            .where((s) => !_isSlotApplied(_slotIdOf(s)))
            .toList();
        if (stillUnapplied.length == 1) {
          _selectedSlotId = _slotIdOf(stillUnapplied.first);
        } else if (_selectedSlotId != null &&
            _isSlotApplied(_selectedSlotId)) {
          _selectedSlotId = null;
        }
      });
    } catch (_) {
      if (!mounted || gen != _lookupGeneration) return;
      setState(() {
        _isLoadingRoleOrStatus = false;
      });
    }
  }

  String _positionLabelForSlot(SubRequest slot) {
    final vp = slot.voicePart?.trim();
    if (vp != null && vp.isNotEmpty) return vp;
    final r = slot.role?.trim();
    if (r != null &&
        r.isNotEmpty &&
        r.toLowerCase() != 'substitute' &&
        r.toLowerCase() != 'new member') {
      return r;
    }
    return slot.isNewMember ? 'New Member' : 'Substitute';
  }

  bool _isSlotPaid(SubRequest slot) {
    return slot.isPaid || (slot.payAmount != null && slot.payAmount! > 0);
  }

  String _resolvePrimaryApplyButtonLabel(List<SubRequest> openSlots) {
    SubRequest target = widget.gig;
    if (_selectedSlotId != null) {
      final match = openSlots.where((s) => _slotIdOf(s) == _selectedSlotId);
      if (match.isNotEmpty) {
        target = match.first;
      }
    } else if (openSlots.isNotEmpty) {
      target = openSlots.first;
    }

    final anyPaid = _selectedSlotId != null
        ? _isSlotPaid(target)
        : openSlots.any(_isSlotPaid) || _isSlotPaid(widget.gig);
    if (anyPaid) {
      return 'Apply for paid gig';
    }

    final isNewMember = target.isNewMember ||
        widget.gig.isNewMember ||
        classifyMapItem(target) == MapItemKind.newMemberRequest;
    if (isNewMember) {
      return 'Apply to join';
    }

    return 'Apply for this gig';
  }

  Future<void> _handleApplyButtonTap(
    BuildContext context,
    MapPinDetails details,
    List<SubRequest> openSlots,
  ) async {
    if (_isSubmitting || _isDialogOpen) return;

    final currentUserId = widget.appState.currentUserId;
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      setState(() {
        _applicationError = 'Please sign in to apply for this request.';
      });
      return;
    }

    final unappliedOpenSlots = openSlots
        .where((s) => !_isSlotApplied(_slotIdOf(s)))
        .toList();
    if (unappliedOpenSlots.isEmpty) return;

    SubRequest? initialCandidate;
    if (unappliedOpenSlots.length == 1) {
      initialCandidate = unappliedOpenSlots.first;
    } else if (_selectedSlotId != null) {
      final matching = unappliedOpenSlots.where((s) => _slotIdOf(s) == _selectedSlotId);
      if (matching.isNotEmpty) {
        initialCandidate = matching.first;
      }
    }

    _isDialogOpen = true;
    SubRequest? confirmedSlot;
    try {
      confirmedSlot = await showDialog<SubRequest>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) {
          SubRequest? dialogSelectedSlot = initialCandidate;
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              final bandName = details.bandName;
              final posLabel = dialogSelectedSlot != null
                  ? _positionLabelForSlot(dialogSelectedSlot!)
                  : null;
              final promptText = posLabel != null
                  ? 'Apply as $posLabel for $bandName?'
                  : 'Select a position to apply for $bandName:';

              return AlertDialog(
                backgroundColor: const Color(0xFF151226),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: details.typeColor.withOpacity(0.55), width: 1.2),
                ),
                title: Text(
                  'Confirm Application',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promptText,
                      key: const ValueKey('map_apply_confirmation_prompt'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.92),
                        height: 1.35,
                      ),
                    ),
                    if (unappliedOpenSlots.length > 1) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Available positions:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: openSlots.map((slot) {
                          final sId = _slotIdOf(slot);
                          final isApplied = _isSlotApplied(sId);
                          final isSelected = dialogSelectedSlot != null &&
                              _slotIdOf(dialogSelectedSlot!) == sId;
                          final label = _positionLabelForSlot(slot);

                          return ChoiceChip(
                            key: ValueKey('dialog_position_chip_$sId'),
                            label: Text(
                              isApplied ? '✓ $label (Applied)' : label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isApplied
                                    ? Colors.white38
                                    : (isSelected ? Colors.white : Colors.white70),
                              ),
                            ),
                            selected: isSelected,
                            onSelected: isApplied
                                ? null
                                : (_) {
                                    setDialogState(() {
                                      dialogSelectedSlot = slot;
                                    });
                                  },
                            selectedColor: details.typeColor.withOpacity(0.45),
                            backgroundColor: const Color(0xFF221E3A),
                            disabledColor: Colors.white10,
                            side: BorderSide(
                              color: isSelected
                                  ? details.typeColor
                                  : Colors.white24,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    key: const ValueKey('map_apply_dialog_cancel'),
                    onPressed: () => Navigator.of(dialogCtx).pop(null),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    key: const ValueKey('map_apply_dialog_confirm'),
                    onPressed: dialogSelectedSlot == null
                        ? null
                        : () => Navigator.of(dialogCtx).pop(dialogSelectedSlot),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      disabledBackgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Apply',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _isDialogOpen = false;
    }

    if (confirmedSlot == null || !mounted) return;
    await _submitApplication(confirmedSlot);
  }

  Future<void> _submitApplication(SubRequest slot) async {
    if (_isSubmitting) return;
    final subRequestId = _slotIdOf(slot);
    final currentUserId = widget.appState.currentUserId;
    if (subRequestId.isEmpty || currentUserId == null || currentUserId.trim().isEmpty) {
      return;
    }
    if (_isSlotApplied(subRequestId)) {
      return;
    }

    final gen = _lookupGeneration;
    setState(() {
      _isSubmitting = true;
      _selectedSlotId = subRequestId;
      _applicationError = null;
    });

    try {
      await widget.appState.firebaseService.addResponseToSubRequestAsync(
        subRequestId,
        currentUserId.trim(),
      );

      if (!mounted || gen != _lookupGeneration) return;

      widget.appState.markSubRequestApplied(subRequestId);
      widget.onAppliedSuccess?.call(subRequestId);

      setState(() {
        _appliedSlotIds.add(subRequestId);
        _isSubmitting = false;
        _applicationError = null;

        final allSlots = _getAllCandidateSlots(widget.gig, widget.groupedGigs);
        final remainingOpen = allSlots
            .where((s) =>
                _isSlotOpenAndEligibleForMusician(s, currentUserId) &&
                !_isSlotApplied(_slotIdOf(s)))
            .toList();
        if (remainingOpen.length == 1) {
          _selectedSlotId = _slotIdOf(remainingOpen.first);
        } else {
          _selectedSlotId = null;
        }
      });
    } catch (e) {
      if (!mounted || gen != _lookupGeneration) return;

      final errLower = e.toString().toLowerCase();
      if (errLower.contains('already-exists') ||
          errLower.contains('alreadyapplied') ||
          errLower.contains('already applied')) {
        widget.appState.markSubRequestApplied(subRequestId);
        widget.onAppliedSuccess?.call(subRequestId);
        setState(() {
          _appliedSlotIds.add(subRequestId);
          _isSubmitting = false;
          _applicationError = null;
        });
        return;
      }

      final friendlyError = _formatUserFriendlyError(e);
      setState(() {
        _isSubmitting = false;
        _applicationError = friendlyError;
      });

      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(friendlyError),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    }
  }

  String _formatUserFriendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('cannot respond to your own substitute request')) {
      return 'You cannot apply to your own request.';
    }
    if (msg.contains('no longer open') || msg.contains('failed-precondition')) {
      return 'This request is no longer open for applications.';
    }
    if (msg.contains('permission-denied') || msg.contains('not authorized')) {
      return 'You do not have permission to apply to this request.';
    }
    if (msg.contains('unauthenticated')) {
      return 'Please sign in to apply for this request.';
    }
    return 'Could not submit application. Please try again.';
  }

  void _handleManageRequest(BuildContext context) {
    if (widget.onManageRequest != null) {
      widget.onManageRequest!(context, widget.gig);
      return;
    }
    final rawBandId = widget.gig.bandId?.trim();
    final effectiveBandId = (rawBandId != null &&
            rawBandId.isNotEmpty &&
            rawBandId != 'freelance' &&
            rawBandId != 'standalone')
        ? rawBandId
        : 'all';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubRequestResponsesScreen(bandId: effectiveBandId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = resolveMapPinDetails(widget.gig, groupedGigs: widget.groupedGigs);
    final currentUserId = widget.appState.currentUserId;
    final isEventProjection = widget.gig.extraFields['isEventProjection'] == true;

    final allCandidateSlots = _getAllCandidateSlots(widget.gig, widget.groupedGigs);
    final isStaffingCard = allCandidateSlots.any(_isGenuineStaffingItem);

    final isCreator = !isEventProjection &&
        allCandidateSlots.any((s) => _isCreatorOf(s, currentUserId));
    final isCreatorOrBandAdmin = isCreator || _isBandAdmin;

    final isPromoOwner = !isEventProjection &&
        !isStaffingCard &&
        _isCreatorOf(widget.gig, currentUserId);

    final openEligibleSlots = isStaffingCard && !isCreatorOrBandAdmin
        ? allCandidateSlots
            .where((s) => _isSlotOpenAndEligibleForMusician(s, currentUserId))
            .toList()
        : <SubRequest>[];

    final allStaffingSlotIds = allCandidateSlots
        .where(_isGenuineStaffingItem)
        .map(_slotIdOf)
        .where((id) => id.isNotEmpty)
        .toList();

    final hasAppliedToAllOpenSlots = openEligibleSlots.isNotEmpty &&
        openEligibleSlots.every((s) => _isSlotApplied(_slotIdOf(s)));

    // Also show ✓ Applied if the musician already applied to a slot on this card
    // and no other unapplied open slots remain.
    final hasAnyAppliedOnCard =
        allStaffingSlotIds.any((id) => _isSlotApplied(id));
    final unappliedOpenSlots = openEligibleSlots
        .where((s) => !_isSlotApplied(_slotIdOf(s)))
        .toList();
    final showAppliedBadgeButton = isStaffingCard &&
        !isCreatorOrBandAdmin &&
        (hasAppliedToAllOpenSlots ||
            (hasAnyAppliedOnCard && unappliedOpenSlots.isEmpty));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: details.typeColor.withOpacity(0.55), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Band name and Genres / Band Types on same row (wrapping cleanly) + Close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.gig.bandId != null && widget.gig.bandId!.trim().isNotEmpty)
                        InkWell(
                          onTap: () {
                            if (widget.onOpenBandProfile != null) {
                              widget.onOpenBandProfile!(context, widget.gig.bandId!.trim());
                            }
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Text(
                            details.bandName,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white38,
                              height: 1.25,
                            ),
                          ),
                        )
                      else
                        Text(
                          details.bandName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.25,
                          ),
                        ),
                      if (details.genre != null && details.genre!.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '· ${details.genre!}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onClose != null)
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white70),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 2. Type badge (category / type display without redundant "Type" text label) & optional Posted date
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: details.typeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: details.typeColor.withOpacity(0.6), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(details.typeIcon, color: details.typeColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        details.typeDisplayLabel,
                        style: GoogleFonts.inter(
                          color: details.typeColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (details.postedDateDisplay != null)
                  Text(
                    details.postedDateDisplay!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white60,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),

            // Positions Needed (interactive selection when multiple open staffing positions exist)
            if (isStaffingCard && !isCreatorOrBandAdmin && openEligibleSlots.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text(
                    'Positions Needed (${openEligibleSlots.length}):',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                    ),
                  ),
                  ...openEligibleSlots.map((slot) {
                    final sId = _slotIdOf(slot);
                    final isSlotApplied = _isSlotApplied(sId);
                    final isSelected = _selectedSlotId == sId;
                    final posLabel = _positionLabelForSlot(slot);

                    return GestureDetector(
                      key: ValueKey('card_position_chip_$sId'),
                      onTap: (isSlotApplied || _isSubmitting)
                          ? null
                          : () {
                              setState(() {
                                _selectedSlotId = isSelected ? null : sId;
                                _applicationError = null;
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isSlotApplied
                              ? AppTheme.success.withOpacity(0.22)
                              : (isSelected
                                  ? details.typeColor.withOpacity(0.38)
                                  : details.typeColor.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSlotApplied
                                ? AppTheme.success.withOpacity(0.75)
                                : (isSelected
                                    ? Colors.white
                                    : details.typeColor.withOpacity(0.5)),
                            width: isSelected ? 1.4 : 1.0,
                          ),
                        ),
                        child: Text(
                          isSlotApplied ? '✓ $posLabel' : posLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isSlotApplied ? AppTheme.success : Colors.white,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ] else if (details.positionsNeeded.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    details.positionsNeeded.length > 1
                        ? 'Positions Needed (${details.positionsNeeded.length}):'
                        : 'Position Needed:',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                    ),
                  ),
                  ...details.positionsNeeded.map(
                    (pos) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: details.typeColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: details.typeColor.withOpacity(0.5), width: 1),
                      ),
                      child: Text(
                        pos,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // 3. Date & Time (visible label: "Date & Time", cleanly omitted if not available)
            if (details.dateTimeDisplay != null) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'Date & Time',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                    ),
                  ),
                  Text(
                    details.dateTimeDisplay!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],

            // Location display: displays city label for New Member, exact venue for others
            if (details.locationDisplay != null && details.locationDisplay!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.white60),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      details.locationDisplay!,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // 4. Description / Details (visible label: "Description / Details", appears only once, cleanly omitted if empty)
            if (details.description != null) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Description / Details',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details.description!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.35,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],

            // 5. Audio Track info (title + info) (visible label: "Audio Track info (title + info)", cleanly omitted if not present)
            if (details.audioTrackTitle != null || details.audioTrackInfo != null) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: 'Audio Track Info ',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white60,
                      ),
                      children: [
                        TextSpan(
                          text: '(title + info)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.normal,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (details.audioTrackTitle != null)
                    Text(
                      details.audioTrackTitle!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  if (details.audioTrackInfo != null)
                    Padding(
                      padding: EdgeInsets.only(top: details.audioTrackTitle != null ? 2.0 : 0.0),
                      child: Text(
                        details.audioTrackInfo!,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ],

            // 6. Audio player / control (rendered ONLY when usable audio is present)
            if (details.hasUsableAudio) ...[
              const SizedBox(height: 10),
              AudioSnippetPlayer(
                audioUrl: details.audioSnippetUrl!,
                autoPlay: details.id.isNotEmpty && widget.focusedTargetId == details.id,
              ),
            ],

            // Inline error display if submission failed
            if (_applicationError != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('map_apply_error_banner'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dangerRed.withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppTheme.dangerRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _applicationError!,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 7. Staffing Request Primary Action Area (MAP-VIEW-APPLY-01)
            if (isStaffingCard) ...[
              if (isCreatorOrBandAdmin) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('map_pin_manage_request_button'),
                    onPressed: () => _handleManageRequest(context),
                    icon: const Icon(Icons.manage_accounts_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Manage Request',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else if (showAppliedBadgeButton) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const ValueKey('map_pin_applied_button'),
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: AppTheme.success.withOpacity(0.22),
                      disabledForegroundColor: AppTheme.success,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: AppTheme.success.withOpacity(0.6)),
                      ),
                    ),
                    child: Text(
                      'Already applied',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
                ),
              ] else if (unappliedOpenSlots.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const ValueKey('map_pin_apply_button'),
                    onPressed: (_isSubmitting || _isLoadingRoleOrStatus)
                        ? null
                        : () => _handleApplyButtonTap(context, details, openEligibleSlots),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      disabledBackgroundColor: AppTheme.primaryAccent.withOpacity(0.45),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSubmitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Applying...',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _resolvePrimaryApplyButtonLabel(unappliedOpenSlots),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ],

            // 8. Event projection navigation action
            if (isEventProjection) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final source = widget.gig.extraFields['eventSource']?.toString();
                    if (source == 'public_calendar') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicEventDetailsScreen(
                            event: PublicCalendarEvent(
                              id: widget.gig.eventId ?? widget.gig.id ?? '',
                              title: widget.gig.eventTitle ?? widget.gig.eventTitle ?? '',
                              shortDescription: '',
                              description: widget.gig.description ?? '',
                              eventType: PublicEventType.liveGig,
                              organizerName: widget.gig.bandName ?? '',
                              venueName: widget.gig.location ?? '',
                              city: widget.gig.city ?? '',
                              address: '',
                              startDateTime: DateTime.tryParse(widget.gig.extraFields['startDateTime']?.toString() ?? '') ?? DateTime.now(),
                              endDateTime: DateTime.tryParse(widget.gig.extraFields['endDateTime']?.toString() ?? '') ?? DateTime.now(),
                            ),
                          ),
                        ),
                      );
                    } else if (widget.gig.bandId != null && widget.gig.eventId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventDetailsPage(
                            bandId: widget.gig.bandId!,
                            eventId: widget.gig.eventId!,
                            initialEvent: BandEvent(
                              id: widget.gig.eventId!,
                              title: widget.gig.eventTitle ?? widget.gig.eventTitle ?? '',
                              description: widget.gig.description ?? '',
                              eventType: widget.gig.requestType ?? 'Event',
                              location: widget.gig.location ?? '',
                              startDateTime: widget.gig.extraFields['startDateTime']?.toString() ?? '',
                              endDateTime: widget.gig.extraFields['endDateTime']?.toString() ?? '',
                              additionalNotes: '',
                              createdBy: widget.gig.creatorUserId ?? '',
                              createdAt: widget.gig.createdAt ?? 0,
                              updatedAt: widget.gig.createdAt ?? 0,
                              requireResponse: true,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.event_available_rounded, size: 16, color: Colors.white),
                  label: Text(
                    widget.gig.extraFields['eventSource'] == 'public_calendar'
                        ? 'View Public Event'
                        : 'View Event Details',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],

            // 9. Promotional Music Pin Owner actions: Edit & Delete Pin
            if (isPromoOwner && (widget.onEditPin != null || widget.onDeletePin != null)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (widget.onEditPin != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onEditPin!(widget.gig),
                        icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF60A5FA)),
                        label: Text(
                          'Edit Pin',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF60A5FA),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF60A5FA), width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  if (widget.onEditPin != null && widget.onDeletePin != null)
                    const SizedBox(width: 8),
                  if (widget.onDeletePin != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onDeletePin!(widget.gig),
                        icon: const Icon(Icons.delete_outline_rounded, size: 14, color: AppTheme.dangerRed),
                        label: Text(
                          'Delete Pin',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.dangerRed,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.dangerRed.withOpacity(0.7), width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
