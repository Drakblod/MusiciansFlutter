import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sub_request.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/map_pin_details_helper.dart';
import 'audio_snippet_player.dart';

/// Card widget displaying the details of a focused or selected Map View pin.
/// Strictly follows the approved 6-item information order and labels.
class MapPinDetailsCard extends StatelessWidget {
  final SubRequest gig;
  final List<SubRequest>? groupedGigs;
  final AppState appState;
  final VoidCallback? onClose;
  final String? focusedTargetId;
  final void Function(BuildContext context, String bandId)? onOpenBandProfile;
  final void Function(SubRequest gig)? onEditPin;
  final void Function(SubRequest gig)? onDeletePin;

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
  });

  @override
  Widget build(BuildContext context) {
    final details = resolveMapPinDetails(gig, groupedGigs: groupedGigs);
    final currentUserId = appState.currentUserId;
    final isOwner = currentUserId != null &&
        (gig.creatorUserId == currentUserId ||
            gig.userId == currentUserId ||
            gig.extraFields['creatorUserId'] == currentUserId ||
            gig.extraFields['CreatorUserId'] == currentUserId);

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
                      if (gig.bandId != null && gig.bandId!.trim().isNotEmpty)
                        InkWell(
                          onTap: () {
                            if (onOpenBandProfile != null) {
                              onOpenBandProfile!(context, gig.bandId!.trim());
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
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
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

            // Positions Needed (cleanly listed for single or multi-slot requests)
            if (details.positionsNeeded.isNotEmpty) ...[
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
                autoPlay: details.id.isNotEmpty && focusedTargetId == details.id,
              ),
            ],

            // 7. Owner actions: Edit & Delete Pin
            if (isOwner && (onEditPin != null || onDeletePin != null)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onEditPin != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onEditPin!(gig),
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
                  if (onEditPin != null && onDeletePin != null)
                    const SizedBox(width: 8),
                  if (onDeletePin != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onDeletePin!(gig),
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
