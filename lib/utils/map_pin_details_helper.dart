import 'package:flutter/material.dart';
import '../models/sub_request.dart';
import '../views/gig_map_page.dart' show MapEventType, MapEventTypeHelper;

/// Presentation data model for displaying a Map View pin / note details card.
class MapPinDetails {
  final String id;
  final String bandName;
  final String? genre;
  final String typeDisplayLabel;
  final Color typeColor;
  final IconData typeIcon;
  final String? dateTimeDisplay;
  final String? description;
  final String? audioTrackTitle;
  final String? audioTrackInfo;
  final String? audioSnippetUrl;
  final bool hasUsableAudio;

  const MapPinDetails({
    required this.id,
    required this.bandName,
    this.genre,
    required this.typeDisplayLabel,
    required this.typeColor,
    required this.typeIcon,
    this.dateTimeDisplay,
    this.description,
    this.audioTrackTitle,
    this.audioTrackInfo,
    this.audioSnippetUrl,
    required this.hasUsableAudio,
  });
}

/// Canonical presentation resolver for Map View pins.
/// Ensures consistent field resolution and strict backward compatibility with legacy records.
MapPinDetails resolveMapPinDetails(SubRequest gig) {
  final id = gig.canonicalTargetId ?? '';

  // 1. Band Name: Prefer canonical bandName, then legacy extraFields, fallback to 'Band'
  String resolvedBandName = gig.bandName?.trim() ?? '';
  if (resolvedBandName.isEmpty) {
    resolvedBandName = gig.extraFields['bandName']?.toString().trim() ??
        gig.extraFields['BandName']?.toString().trim() ??
        '';
  }
  if (resolvedBandName.isEmpty) {
    resolvedBandName = 'Band';
  }

  // 2. Genres / Band Types: Prefer canonical genre in extraFields, then style, fallback to null
  String? resolvedGenre = gig.extraFields['genre']?.toString().trim() ??
      gig.extraFields['Genre']?.toString().trim() ??
      gig.extraFields['genres']?.toString().trim() ??
      gig.style?.trim();
  if (resolvedGenre != null && resolvedGenre.isEmpty) {
    resolvedGenre = null;
  }

  // 3. Type resolution and display mapping
  final eventType = MapEventTypeHelper.getEventType(gig);
  final typeColor = MapEventTypeHelper.getColor(eventType);
  final typeIcon = MapEventTypeHelper.getIcon(eventType);

  final rawType = gig.requestType?.trim() ?? gig.extraFields['eventType']?.toString().trim() ?? '';
  final String typeDisplayLabel;
  if (rawType.toLowerCase() == 'demos / recordings' ||
      rawType.toLowerCase() == 'recorded music' ||
      eventType == MapEventType.recordedMusic) {
    typeDisplayLabel = 'Demos / Recordings';
  } else if (rawType.toLowerCase() == 'concert' || eventType == MapEventType.concert) {
    typeDisplayLabel = 'Concert';
  } else if (rawType.toLowerCase() == 'live gigs / rehearsals' ||
      rawType.toLowerCase() == 'gigs / rehearsals' ||
      rawType.toLowerCase() == 'gig / concert' ||
      rawType.toLowerCase() == 'gig' ||
      eventType == MapEventType.gigConcert) {
    typeDisplayLabel = 'Gig';
  } else if (rawType.toLowerCase() == 'rehearsal' || eventType == MapEventType.rehearsal) {
    typeDisplayLabel = 'Rehearsal';
  } else if (rawType.toLowerCase() == 'jam session' || eventType == MapEventType.jamSession) {
    typeDisplayLabel = 'Jam Session';
  } else if (rawType.toLowerCase() == 'gig promo' || eventType == MapEventType.gigPromo) {
    typeDisplayLabel = 'Gig Promo';
  } else if (rawType.toLowerCase() == 'new member' || eventType == MapEventType.newMember) {
    typeDisplayLabel = 'New Member';
  } else if (rawType.toLowerCase() == 'subs' || rawType.toLowerCase() == 'substitute' || eventType == MapEventType.subs) {
    typeDisplayLabel = 'Substitute';
  } else if (rawType.toLowerCase() == 'paid gigs' || rawType.toLowerCase() == 'paid' || eventType == MapEventType.paid) {
    typeDisplayLabel = 'Paid Gigs';
  } else {
    typeDisplayLabel = MapEventTypeHelper.getShortLabel(eventType);
  }

  // 4. Date & Time formatting: Omit if not applicable or unavailable
  String? dateTimeDisplay = _formatPinDateTime(gig);
  if (dateTimeDisplay != null && dateTimeDisplay.trim().isEmpty) {
    dateTimeDisplay = null;
  }

  // 5. Description / Details: Prefer canonical description.
  // Use legacy fallback (role/eventTitle/details) ONLY if canonical description is empty.
  // Never concatenate them.
  String? resolvedDescription = gig.description?.trim();
  if (resolvedDescription == null || resolvedDescription.isEmpty) {
    final legacyText = gig.extraFields['details']?.toString().trim() ??
        gig.eventTitle?.trim() ??
        gig.role?.trim();
    if (legacyText != null &&
        legacyText.isNotEmpty &&
        legacyText.toLowerCase() != typeDisplayLabel.toLowerCase() &&
        legacyText.toLowerCase() != 'substitute' &&
        legacyText.toLowerCase() != 'new member') {
      resolvedDescription = legacyText;
    }
  }
  if (resolvedDescription != null && resolvedDescription.isEmpty) {
    resolvedDescription = null;
  }

  // 6. Audio Track Info (Title + Info)
  String? audioTrackTitle = gig.audioSnippetTitle?.trim() ??
      gig.extraFields['audioSnippetTitle']?.toString().trim() ??
      gig.extraFields['audioTitle']?.toString().trim() ??
      gig.extraFields['audioTrack']?.toString().trim();
  if (audioTrackTitle != null && audioTrackTitle.isEmpty) {
    audioTrackTitle = null;
  }

  String? audioTrackInfo = gig.extraFields['infoAudioTrack']?.toString().trim() ??
      gig.extraFields['audioInfo']?.toString().trim() ??
      gig.extraFields['infoAudio']?.toString().trim() ??
      gig.extraFields['audioTrackInfo']?.toString().trim();
  if (audioTrackInfo != null && audioTrackInfo.isEmpty) {
    audioTrackInfo = null;
  }

  // 7. Usable Audio URL
  String? audioUrl = gig.audioSnippetUrl?.trim() ??
      gig.extraFields['audioSnippetUrl']?.toString().trim() ??
      gig.extraFields['audioUrl']?.toString().trim() ??
      gig.extraFields['audioAssetPath']?.toString().trim();
  if (audioUrl != null && audioUrl.isEmpty) {
    audioUrl = null;
  }

  final bool hasUsableAudio = audioUrl != null &&
      (audioUrl.startsWith('http://') ||
          audioUrl.startsWith('https://') ||
          audioUrl.startsWith('assets/') ||
          audioUrl.startsWith('audio/') ||
          audioUrl.startsWith('blob:') ||
          audioUrl.startsWith('/') ||
          audioUrl.contains('.'));

  return MapPinDetails(
    id: id,
    bandName: resolvedBandName,
    genre: resolvedGenre,
    typeDisplayLabel: typeDisplayLabel,
    typeColor: typeColor,
    typeIcon: typeIcon,
    dateTimeDisplay: dateTimeDisplay,
    description: resolvedDescription,
    audioTrackTitle: audioTrackTitle,
    audioTrackInfo: audioTrackInfo,
    audioSnippetUrl: audioUrl,
    hasUsableAudio: hasUsableAudio,
  );
}

String? _formatPinDateTime(SubRequest gig) {
  // If formattedTimeRange or explicit DateLabel is provided
  if (gig.formattedTimeRange != null && gig.formattedTimeRange!.trim().isNotEmpty) {
    if (gig.date != null && gig.date!.trim().isNotEmpty) {
      final parsedDate = DateTime.tryParse(gig.date!.trim());
      if (parsedDate != null) {
        return '${_formatDate(parsedDate)} · ${gig.formattedTimeRange!.trim()}';
      }
    }
    return gig.formattedTimeRange!.trim();
  }

  if (gig.date == null || gig.date!.trim().isEmpty) {
    return null;
  }

  final dt = DateTime.tryParse(gig.date!.trim());
  if (dt == null) {
    return gig.date!.trim();
  }

  final datePart = _formatDate(dt);
  final start = gig.startTime?.trim();
  final end = gig.endTime?.trim();

  if (start != null && start.isNotEmpty && end != null && end.isNotEmpty) {
    return '$datePart · ${_formatTime(start)} – ${_formatTime(end)}';
  } else if (start != null && start.isNotEmpty) {
    return '$datePart · ${_formatTime(start)}';
  }

  return datePart;
}

String _formatDate(DateTime dt) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _formatTime(String rawTime) {
  final match = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(rawTime);
  if (match != null) {
    final h = match.group(1)!.padLeft(2, '0');
    final m = match.group(2)!;
    return '$h:$m';
  }
  return rawTime;
}
