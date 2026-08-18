import '../models/band_event.dart';

/// Pure Dart utility for resolving RSVP deadlines and calculating remaining hours.
class RsvpDeadlineUtils {
  /// Resolves the effective RSVP deadline timestamp in epoch milliseconds.
  ///
  /// Precedence rules:
  /// 1. If [event.requireResponse] is false, returns null.
  /// 2. If [event.reminderIntervalHours] == 0, returns null (no automatic deadline).
  /// 3. If [event.createdAt] > 0 and [event.reminderIntervalHours] > 0, calculates:
  ///    `createdAt + (reminderIntervalHours * 3600 * 1000)`.
  ///    (This takes precedence over any legacy persisted rsvpDeadline calculated from event start).
  /// 4. If publication metadata is missing/invalid, but a valid persisted
  ///    [event.rsvpDeadline] (> 0) exists, uses rsvpDeadline as compatibility fallback.
  /// 5. Otherwise returns null (never calculates from startDateTime).
  static int? calculateEffectiveRsvpDeadlineMs(BandEvent event) {
    if (!event.requireResponse) return null;

    final interval = event.reminderIntervalHours;
    if (interval == 0) return null;

    final createdAt = event.createdAt;
    if (createdAt != null &&
        createdAt > 0 &&
        interval != null &&
        interval > 0) {
      return createdAt + (interval * 3600 * 1000);
    }

    final persistedDeadline = event.rsvpDeadline;
    if (persistedDeadline != null && persistedDeadline > 0) {
      return persistedDeadline;
    }

    return null;
  }

  /// Calculates remaining hours until the RSVP response deadline.
  ///
  /// Parameters:
  /// - [event]: the target BandEvent.
  /// - [nowMs]: optional current epoch milliseconds for deterministic testing
  ///   (defaults to system DateTime.now().millisecondsSinceEpoch).
  ///
  /// Returns:
  /// - null if no legitimate/automatic deadline can be calculated.
  /// - 0 if at or past the deadline (never returns negative numbers).
  /// - Positive integer rounded UP (ceil) to the nearest hour.
  static int? calculateRemainingRsvpHours(BandEvent event, {int? nowMs}) {
    final effectiveDeadlineMs = calculateEffectiveRsvpDeadlineMs(event);
    if (effectiveDeadlineMs == null) return null;

    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final remainingMs = effectiveDeadlineMs - currentMs;

    if (remainingMs <= 0) {
      return 0;
    }

    const msPerHour = 3600 * 1000;
    return (remainingMs / msPerHour).ceil();
  }
}
