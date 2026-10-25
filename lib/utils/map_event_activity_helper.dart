import '../views/gig_map_page.dart' show MapEventType;
import '../models/sub_request.dart';
import '../models/mock_live_rehearsal.dart';
import 'date_parser.dart';

/// Helper to determine whether a map item (Gig/Concert or Rehearsal) is currently active.
///
/// Boundary rule:
/// An item is active if and only if: `start <= now < end`
/// (Strictly `< end`, not `<= end`).
///
/// Only items with [MapEventType.gigConcert] or [MapEventType.rehearsal] are eligible.
/// All other types return `false`.

bool isMapItemActive({
  required MapEventType type,
  DateTime? startDateTime,
  DateTime? endDateTime,
  String? date,
  String? startTime,
  String? endTime,
  String? timeRange,
  DateTime? now,
}) {
  // Only Gig, Concert and Rehearsal are eligible for active state.
  if (type != MapEventType.gigConcert && type != MapEventType.concert && type != MapEventType.rehearsal) {
    return false;
  }

  final current = now ?? DateTime.now();

  // 1. Direct DateTime objects
  DateTime? start = startDateTime;
  DateTime? end = endDateTime;

  // 2. Parse from date and time strings if start is not already provided
  if (start == null && date != null && date.trim().isNotEmpty) {
    final parsedDate = _parseDateOnly(date.trim());
    if (parsedDate != null) {
      final startComponents = _parseTimeComponents(startTime) ?? _parseStartTimeFromRange(timeRange);
      if (startComponents != null) {
        start = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
          startComponents.hour,
          startComponents.minute,
        );

        if (end == null) {
          final endComponents = _parseTimeComponents(endTime) ?? _parseEndTimeFromRange(timeRange);
          if (endComponents != null) {
            end = DateTime(
              parsedDate.year,
              parsedDate.month,
              parsedDate.day,
              endComponents.hour,
              endComponents.minute,
            );
          }
        }
      } else {
        // Date might be a full ISO datetime string with time component
        final fullParsed = parseDateTime(date);
        if (fullParsed != null && (fullParsed.hour != 0 || fullParsed.minute != 0 || date.contains('T'))) {
          start = fullParsed.toLocal();
        }
      }
    }
  }

  // Both a valid start and valid end MUST be resolved. Never infer or invent an event duration.
  if (start == null || end == null) {
    return false;
  }

  // Handling of midnight-crossing events:
  // If end time is numerically less than or equal to start time, add 1 day to end.
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }

  // Canonical boundary condition: start <= now < end
  return !current.isBefore(start) && current.isBefore(end);
}

/// Evaluates whether a [SubRequest] gig or rehearsal is currently active.
bool isSubRequestActive(SubRequest gig, {DateTime? now}) {
  final eventType = _resolveMapEventType(gig);
  if (eventType != MapEventType.gigConcert && eventType != MapEventType.concert && eventType != MapEventType.rehearsal) {
    return false;
  }

  DateTime? startDt;
  DateTime? endDt;

  if (gig.extraFields['startDateTime'] != null) {
    startDt = parseDateTime(gig.extraFields['startDateTime']);
  }
  if (gig.extraFields['endDateTime'] != null) {
    endDt = parseDateTime(gig.extraFields['endDateTime']);
  }

  return isMapItemActive(
    type: eventType,
    startDateTime: startDt,
    endDateTime: endDt,
    date: gig.date,
    startTime: gig.startTime,
    endTime: gig.endTime,
    timeRange: gig.formattedTimeRange,
    now: now,
  );
}

/// Evaluates whether a [MockLiveRehearsal] broadcast is currently active.
bool isMockLiveRehearsalActive(MockLiveRehearsal rehearsal, {DateTime? now}) {
  if (rehearsal.startDateTime != null) {
    return isMapItemActive(
      type: MapEventType.rehearsal,
      startDateTime: rehearsal.startDateTime,
      endDateTime: rehearsal.endDateTime,
      now: now,
    );
  }

  return isMapItemActive(
    type: MapEventType.rehearsal,
    startDateTime: rehearsal.startDateTime,
    endDateTime: rehearsal.endDateTime,
    date: rehearsal.date,
    startTime: rehearsal.startTime,
    endTime: rehearsal.endTime,
    now: now,
  );
}

MapEventType _resolveMapEventType(SubRequest gig) {
  final explicitType = gig.extraFields["eventType"]?.toString().toLowerCase();
  if (explicitType == 'concert') return MapEventType.concert;
  if (explicitType == 'gig' || explicitType == 'gigconcert' || explicitType == 'gig_concert') return MapEventType.gigConcert;
  if (explicitType == 'rehearsal') return MapEventType.rehearsal;
  if (explicitType == 'jamsession' || explicitType == 'jam_session') return MapEventType.jamSession;
  if (explicitType == 'recordedmusic' || explicitType == 'recorded_music' || explicitType == 'studio') return MapEventType.recordedMusic;
  if (explicitType == 'gigpromo' || explicitType == 'gig_promo') return MapEventType.gigPromo;
  if (explicitType == 'newmember' || explicitType == 'new_member') return MapEventType.newMember;
  if (explicitType == 'subs' || explicitType == 'sub') return MapEventType.subs;
  if (explicitType == 'paid') return MapEventType.paid;

  final text = '${gig.requestType ?? ""} ${gig.role ?? ""} ${gig.eventTitle ?? ""} ${gig.description ?? ""}'.toLowerCase();

  if (text.contains('gig promo') || text.contains('promo')) return MapEventType.gigPromo;
  if (text.contains('concert') || text.contains('konsert')) return MapEventType.concert;
  if (text.contains('new member') || text.contains('ny medlem') || text.contains('audition') || text.contains('permanent') || text.contains('join the band') || text.contains('söker musiker')) {
    return MapEventType.newMember;
  }
  if (gig.isPaid && (text.contains('paid') || text.contains('betalt') || (gig.payAmount != null && gig.payAmount! > 0 && text.contains('gig')))) {
    if (!text.contains('concert') && !text.contains('rehearsal')) return MapEventType.paid;
  }
  if (text.contains('sub') || text.contains('vikarie') || (gig.requestType?.toLowerCase() == 'sub')) {
    if (!text.contains('rehearsal') && !text.contains('concert')) return MapEventType.subs;
  }
  if ((gig.rehearsalDayOfWeek != null && gig.rehearsalDayOfWeek!.isNotEmpty) ||
      gig.requestType?.toLowerCase() == 'rehearsal' ||
      text.contains('rehearsal') ||
      text.contains('repetition') ||
      text.contains('repa') ||
      text.contains('rep ')) {
    return MapEventType.rehearsal;
  }
  if (text.contains('jam') || text.contains('öppen scen') || text.contains('open mic')) return MapEventType.jamSession;
  if (text.contains('demo') || text.contains('inspelning') || text.contains('studio') || text.contains('release') || text.contains('album') || text.contains('ep') || text.contains('singel') || text.contains('single') || text.contains('recorded music')) {
    return MapEventType.recordedMusic;
  }
  return MapEventType.gigConcert;
}

/// Parses date string into year, month, day.
DateTime? _parseDateOnly(String raw) {
  try {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  } catch (_) {}

  // Try common Swedish / European format YYYY-MM-DD or DD/MM/YYYY
  final ymd = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(raw);
  if (ymd != null) {
    final y = int.tryParse(ymd.group(1)!);
    final m = int.tryParse(ymd.group(2)!);
    final d = int.tryParse(ymd.group(3)!);
    if (y != null && m != null && d != null) {
      try {
        return DateTime(y, m, d);
      } catch (_) {}
    }
  }

  return null;
}

class _TimeComponents {
  final int hour;
  final int minute;
  const _TimeComponents(this.hour, this.minute);
}

/// Parses time strings such as "18:00", "18.00", "6:00 PM", "6.00 PM", "6pm", "18:30:00" safely.
_TimeComponents? _parseTimeComponents(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // 12-hour format with AM/PM: e.g. "6:00 PM", "6.00 PM", "6:30pm", "6pm"
  final amPmMatch = RegExp(r'^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)$', caseSensitive: false).firstMatch(trimmed);
  if (amPmMatch != null) {
    int h = int.tryParse(amPmMatch.group(1)!) ?? 0;
    final int m = int.tryParse(amPmMatch.group(2) ?? '0') ?? 0;
    final isPm = amPmMatch.group(3)!.toLowerCase() == 'pm';

    if (h == 12) {
      h = isPm ? 12 : 0;
    } else if (isPm) {
      h += 12;
    }
    if (h >= 0 && h < 24 && m >= 0 && m < 60) {
      return _TimeComponents(h, m);
    }
  }

  // 24-hour format: e.g. "18:00", "18.00", "9:30", "18:00:00"
  final standardMatch = RegExp(r'^(\d{1,2})[:.](\d{2})(?::\d{2})?$').firstMatch(trimmed);
  if (standardMatch != null) {
    final h = int.tryParse(standardMatch.group(1)!);
    final m = int.tryParse(standardMatch.group(2)!);
    if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
      return _TimeComponents(h, m);
    }
  }

  return null;
}

/// Parses time range like "18:00 - 21:00" or "6.00 PM 9.00 PM"
_TimeComponents? _parseStartTimeFromRange(String? timeRange) {
  if (timeRange == null || timeRange.trim().isEmpty) return null;
  final parts = timeRange.split(RegExp(r'[-–—]'));
  if (parts.isNotEmpty) {
    return _parseTimeComponents(parts.first.trim());
  }
  return null;
}

_TimeComponents? _parseEndTimeFromRange(String? timeRange) {
  if (timeRange == null || timeRange.trim().isEmpty) return null;
  final parts = timeRange.split(RegExp(r'[-–—]'));
  if (parts.length >= 2) {
    return _parseTimeComponents(parts[1].trim());
  }
  return null;
}
