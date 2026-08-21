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
