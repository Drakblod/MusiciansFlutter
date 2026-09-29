import 'package:intl/intl.dart';
import '../models/band_event.dart';

/// Safe parser for legacy, index, and model timestamps.
///
/// Supports:
/// - `null` or missing values
/// - `DateTime` instances
/// - Epoch milliseconds (`int` or `double`)
/// - Numeric epoch strings (`"1786650000000"`)
/// - Valid ISO-8601 strings (`"2026-08-14T12:00:00Z"`)
/// - Malformed string values (returns `null` without throwing)
DateTime? parseDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final numericMs = int.tryParse(trimmed);
    if (numericMs != null) {
      return DateTime.fromMillisecondsSinceEpoch(numericMs);
    }

    final doubleMs = double.tryParse(trimmed);
    if (doubleMs != null) {
      return DateTime.fromMillisecondsSinceEpoch(doubleMs.toInt());
    }

    try {
      return DateTime.parse(trimmed);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Formats a parent Main Event date range according to design guidelines:
/// - Same day: "September 27, 2026"
/// - Same month: "September 27–29, 2026" (en-dash)
/// - Different months, same year: "September 30 – October 2, 2026"
/// - Different years: "December 30, 2026 – January 2, 2027"
///
/// Never includes clock times or weekday names.
String formatMainEventDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return '';
  if (start == null) return DateFormat('MMMM d, yyyy').format(end!.toLocal());
  if (end == null) return DateFormat('MMMM d, yyyy').format(start.toLocal());

  final startLocal = start.toLocal();
  final endLocal = end.toLocal();

  // Same day
  if (startLocal.year == endLocal.year &&
      startLocal.month == endLocal.month &&
      startLocal.day == endLocal.day) {
    return DateFormat('MMMM d, yyyy').format(startLocal);
  }

  // Same month, same year
  if (startLocal.year == endLocal.year &&
      startLocal.month == endLocal.month) {
    return '${DateFormat('MMMM d').format(startLocal)}–${DateFormat('d, yyyy').format(endLocal)}';
  }

  // Different months, same year
  if (startLocal.year == endLocal.year) {
    return '${DateFormat('MMMM d').format(startLocal)} – ${DateFormat('MMMM d, yyyy').format(endLocal)}';
  }

  // Different years
  return '${DateFormat('MMMM d, yyyy').format(startLocal)} – ${DateFormat('MMMM d, yyyy').format(endLocal)}';
}

/// Helper that extracts start and end from a [BandEvent] (encompassing attached rehearsals if present)
/// and formats the parent Main Event date range.
String formatBandEventDateRange(BandEvent event) {
  DateTime? start = DateTime.tryParse(event.startDateTime)?.toLocal();
  DateTime? end = DateTime.tryParse(event.endDateTime)?.toLocal() ?? start;

  if (event.rehearsals.isNotEmpty) {
    for (final r in event.rehearsals) {
      if (r.date.isNotEmpty) {
        final rDate = DateTime.tryParse(r.date)?.toLocal();
        if (rDate != null) {
          final rDayOnly = DateTime(rDate.year, rDate.month, rDate.day);
          if (start == null || rDayOnly.isBefore(DateTime(start.year, start.month, start.day))) {
            start = rDayOnly;
          }
          if (end == null || rDayOnly.isAfter(DateTime(end.year, end.month, end.day))) {
            end = rDayOnly;
          }
        }
      }
    }
  }

  return formatMainEventDateRange(start, end);
}
