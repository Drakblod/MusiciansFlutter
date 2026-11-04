import 'package:intl/intl.dart';
import '../models/sub_request.dart';
import '../models/agreement.dart';

/// Formats agreement payment if present and positive (> 0).
/// E.g. "Paid · 1,500 SEK" or "Paid · 1,500" if currency is absent or malformed.
/// Returns null if payAmount is null or <= 0.
String? formatAgreementPayment(Agreement agreement) {
  final amount = agreement.payAmount;
  if (amount == null || amount <= 0) return null;
  final formattedAmount = NumberFormat('#,##0', 'en_US').format(amount);
  final rawCurr = agreement.currency?.trim();
  String? curr;
  if (rawCurr != null && rawCurr.isNotEmpty && rawCurr.toLowerCase() != 'null') {
    final cleaned = rawCurr.toUpperCase();
    if (RegExp(r'^[A-Z]{3}$').hasMatch(cleaned)) {
      curr = cleaned;
    }
  }
  if (curr != null) {
    return 'Paid · $formattedAmount $curr';
  }
  return 'Paid · $formattedAmount';
}

/// Formats a time string (e.g. '18:00', '18.00', '18:00:00') to dot notation '18.00'.
String formatSubRequestTime(String time) {
  final clean = time.trim();
  final match = RegExp(r'^(\d{1,2})[:.](\d{2})(?::\d{2})?$').firstMatch(clean);
  if (match != null) {
    final h = match.group(1)!;
    final m = match.group(2)!;
    return '$h.$m';
  }
  return clean;
}

/// Formats the date and time line according to the standard:
/// `Fri, Oct 30 · 18.00–21.30`
///
/// Returns null if date is missing or empty.
/// Does not invent event duration or fallback times.
String? formatSubRequestDateTime({
  String? date,
  String? startTime,
  String? endTime,
}) {
  if (date == null || date.trim().isEmpty) {
    return null;
  }

  String datePart;
  final parsed = DateTime.tryParse(date.trim());
  if (parsed != null) {
    datePart = DateFormat('EEE, MMM d').format(parsed.toLocal());
  } else {
    datePart = date.trim();
  }

  final hasStart = startTime != null && startTime.trim().isNotEmpty;
  final hasEnd = endTime != null && endTime.trim().isNotEmpty;

  String timePart = '';
  if (hasStart && hasEnd) {
    timePart = '${formatSubRequestTime(startTime)}–${formatSubRequestTime(endTime)}';
  } else if (hasStart) {
    timePart = formatSubRequestTime(startTime);
  } else if (hasEnd) {
    timePart = formatSubRequestTime(endTime);
  }

  if (datePart.isNotEmpty && timePart.isNotEmpty) {
    return '$datePart · $timePart';
  } else if (datePart.isNotEmpty) {
    return datePart;
  }
  return null;
}

/// Resolves user-facing request type label.
/// Canonical 'New Member' is displayed as 'New Band Member'.
String resolveRequestTypeLabel(SubRequest req) {
  final rawType = req.requestType?.trim().toLowerCase();
  final rawRole = req.role?.trim().toLowerCase();
  if (rawType == 'new member' || rawRole == 'new member') {
    return 'New Band Member';
  }
  if (rawType == 'other' || rawRole == 'other') {
    return 'Other';
  }
  return 'Substitute';
}

/// Resolves a single clean role/instrument name without event name or date/time.
String resolveSingleRole(SubRequest req) {
  if (req.voicePart != null && req.voicePart!.trim().isNotEmpty) {
    return req.voicePart!.trim();
  }
  final roleLower = req.role?.trim().toLowerCase();
  if (roleLower != null &&
      roleLower.isNotEmpty &&
      roleLower != 'substitute' &&
      roleLower != 'new member' &&
      roleLower != 'other' &&
      roleLower != 'musician') {
    return req.role!.trim();
  }
  return 'Musician';
}

/// Checks if the given user is the creator of the SubRequest.
bool isCreatorOfSubRequest(SubRequest item, String? currentUserId) {
  if (currentUserId == null || currentUserId.trim().isEmpty) return false;
  final uid = currentUserId.trim();
  return item.creatorUserId == uid ||
      item.userId == uid ||
      item.extraFields['creatorUserId'] == uid ||
      item.extraFields['CreatorUserId'] == uid;
}

/// Checks if the given user has applied to the SubRequest.
bool hasAppliedToSubRequest(
  SubRequest item,
  String? currentUserId, {
  Set<String>? appliedIds,
}) {
  if (currentUserId == null || currentUserId.trim().isEmpty) return false;
  final uid = currentUserId.trim();
  final reqId = item.subRequestId ?? item.id ?? '';
  if (appliedIds != null && reqId.isNotEmpty && appliedIds.contains(reqId)) {
    return true;
  }
  return item.responses.containsKey(uid) && item.responses[uid] == true;
}

/// Formats a SubRequest payment amount for English UI presentation.
///
/// Returns:
/// - null when unpaid
/// - 'Paid' when paid with no amount or zero amount
/// - 'Paid · 1,500 SEK' for whole numbers (without trailing decimals)
/// - 'Paid · 1,500.50 SEK' for amounts with cents
String? formatSubRequestPaymentDisplay(SubRequest req) {
  if (!req.isPaid) return null;

  num? amount;
  if (req.payAmountMinor != null && req.payAmountMinor! > 0) {
    amount = req.payAmountMinor! / 100.0;
  } else if (req.payAmount != null && req.payAmount! > 0) {
    amount = req.payAmount;
  } else if (req.extraFields['payAmount'] != null) {
    final parsed = double.tryParse(req.extraFields['payAmount'].toString());
    if (parsed != null && parsed > 0) amount = parsed;
  } else if (req.extraFields['PayAmount'] != null) {
    final parsed = double.tryParse(req.extraFields['PayAmount'].toString());
    if (parsed != null && parsed > 0) amount = parsed;
  }

  if (amount == null || amount <= 0) {
    return 'Paid';
  }

  final String numStr;
  if (amount % 1 == 0) {
    numStr = NumberFormat('#,##0', 'en_US').format(amount.toInt());
  } else {
    numStr = NumberFormat('#,##0.00', 'en_US').format(amount);
  }

  final rawCurr = (req.currency ?? req.extraFields['currency']?.toString() ?? req.extraFields['Currency']?.toString())?.trim();
  String? curr;
  if (rawCurr != null && rawCurr.isNotEmpty && rawCurr.toLowerCase() != 'null') {
    final cleaned = rawCurr.toUpperCase();
    if (RegExp(r'^[A-Z]{3}$').hasMatch(cleaned)) {
      curr = cleaned;
    }
  }

  if (curr != null) {
    return 'Paid · $numStr $curr';
  } else {
    return 'Paid · $numStr';
  }
}

/// Presentation model representing the standard unified visual hierarchy for SubRequest cards.
class SubRequestCardPresentation {
  final String bandName;
  final String requestType; // 'New Band Member', 'Substitute', or 'Other'
  final String roleInstrument;
  final List<String> distinctRoles;
  final String? eventType;
  final bool isPaid;
  final String? formattedPayment;
  final String? eventTypeAndPaymentLine;
  final String? formattedDateTime;
  final String? locationVenue;
  final String? description;
  final String? payDetails;
  final bool isCreator;
  final bool isBandAdmin;
  final bool isCreatorOrBandAdmin;
  final bool isBandAdminPending;
  final bool isBandAdminFailed;
  final bool hasApplied;
  final bool isAssigned;

  const SubRequestCardPresentation({
    required this.bandName,
    required this.requestType,
    required this.roleInstrument,
    required this.distinctRoles,
    this.eventType,
    required this.isPaid,
    this.formattedPayment,
    this.eventTypeAndPaymentLine,
    this.formattedDateTime,
    this.locationVenue,
    this.description,
    this.payDetails,
    required this.isCreator,
    required this.isBandAdmin,
    required this.isCreatorOrBandAdmin,
    this.isBandAdminPending = false,
    this.isBandAdminFailed = false,
    required this.hasApplied,
    required this.isAssigned,
  });

  /// Factory creating presentation from a single SubRequest.
  factory SubRequestCardPresentation.fromSubRequest(
    SubRequest req, {
    String? currentUserId,
    bool isBandAdmin = false,
    bool isBandAdminPending = false,
    bool isBandAdminFailed = false,
    Set<String>? appliedIds,
  }) {
    final typeLabel = resolveRequestTypeLabel(req);
    final isNewMember = typeLabel == 'New Band Member';

    final band = (req.bandName != null && req.bandName!.trim().isNotEmpty)
        ? req.bandName!.trim()
        : (req.eventTitle != null && req.eventTitle!.trim().isNotEmpty)
            ? req.eventTitle!.trim()
            : 'Band';

    final role = resolveSingleRole(req);

    // Event Type: omit for New Band Member
    final rawEventType = isNewMember ? null : req.resolvedEventType?.trim();
    final effectiveEventType = (rawEventType != null && rawEventType.isNotEmpty) ? rawEventType : null;

    // Payment:
    final paid = req.isPaid;
    final paymentStr = paid ? formatSubRequestPaymentDisplay(req) : null;

    // Line 3: Event Type + Paid status/payment amount
    String? line3;
    if (effectiveEventType != null && paymentStr != null) {
      line3 = '$effectiveEventType · $paymentStr';
    } else if (effectiveEventType != null) {
      line3 = effectiveEventType;
    } else if (paymentStr != null) {
      line3 = paymentStr;
    }

    // Line 4: Weekday, date and time (omitted if no date or if New Band Member without date)
    final dateTimeLine = isNewMember
        ? null
        : formatSubRequestDateTime(
            date: req.date,
            startTime: req.startTime,
            endTime: req.endTime,
          );

    // Line 5: Location / Venue
    final loc = (req.location != null && req.location!.trim().isNotEmpty)
        ? req.location!.trim()
        : (req.city != null && req.city!.trim().isNotEmpty)
            ? req.city!.trim()
            : null;

    final creator = isCreatorOfSubRequest(req, currentUserId);
    final applied = hasAppliedToSubRequest(req, currentUserId, appliedIds: appliedIds);
    final assigned = req.status == 'assigned' || (req.assignedUserId != null && req.assignedUserId!.trim().isNotEmpty);

    final desc = (req.description != null && req.description!.trim().isNotEmpty)
        ? req.description!.trim()
        : null;

    final details = (req.payDetails != null && req.payDetails!.trim().isNotEmpty)
        ? req.payDetails!.trim()
        : null;

    return SubRequestCardPresentation(
      bandName: band,
      requestType: typeLabel,
      roleInstrument: role,
      distinctRoles: [role],
      eventType: effectiveEventType,
      isPaid: paid,
      formattedPayment: paymentStr,
      eventTypeAndPaymentLine: line3,
      formattedDateTime: dateTimeLine,
      locationVenue: loc,
      description: desc,
      payDetails: details,
      isCreator: creator,
      isBandAdmin: isBandAdmin,
      isCreatorOrBandAdmin: creator || isBandAdmin,
      isBandAdminPending: !creator && isBandAdminPending,
      isBandAdminFailed: !creator && isBandAdminFailed,
      hasApplied: applied,
      isAssigned: assigned,
    );
  }

  /// Factory creating presentation from a list of SubRequests (e.g. GigGroup).
  factory SubRequestCardPresentation.fromRequests(
    List<SubRequest> requests, {
    String? bandNameOverride,
    String? locationOverride,
    String? descriptionOverride,
    String? payDetailsOverride,
    String? currentUserId,
    bool isBandAdmin = false,
    bool isBandAdminPending = false,
    bool isBandAdminFailed = false,
    Set<String>? appliedIds,
  }) {
    if (requests.isEmpty) {
      return SubRequestCardPresentation(
        bandName: bandNameOverride ?? 'Band',
        requestType: 'Substitute',
        roleInstrument: 'Musician',
        distinctRoles: const ['Musician'],
        isPaid: false,
        isCreator: false,
        isBandAdmin: isBandAdmin,
        isCreatorOrBandAdmin: isBandAdmin,
        hasApplied: false,
        isAssigned: false,
      );
    }

    final first = requests.first;
    final isNewMember = requests.any((r) {
      final t = r.requestType?.trim().toLowerCase();
      final ro = r.role?.trim().toLowerCase();
      return t == 'new member' || ro == 'new member';
    });
    final isOther = requests.any((r) {
      final t = r.requestType?.trim().toLowerCase();
      final ro = r.role?.trim().toLowerCase();
      return t == 'other' || ro == 'other';
    });

    final typeLabel = isNewMember ? 'New Band Member' : (isOther ? 'Other' : 'Substitute');

    final band = (bandNameOverride != null && bandNameOverride.trim().isNotEmpty)
        ? bandNameOverride.trim()
        : (first.bandName != null && first.bandName!.trim().isNotEmpty)
            ? first.bandName!.trim()
            : (first.eventTitle != null && first.eventTitle!.trim().isNotEmpty)
                ? first.eventTitle!.trim()
                : 'Band';

    final distinctRolesList = <String>[];
    for (final r in requests) {
      final single = resolveSingleRole(r);
      if (!distinctRolesList.contains(single)) {
        distinctRolesList.add(single);
      }
    }
    if (distinctRolesList.isEmpty) {
      distinctRolesList.add('Musician');
    }

    final roleDisplay = distinctRolesList.length > 1
        ? '${distinctRolesList.first} (+${distinctRolesList.length - 1})'
        : distinctRolesList.first;

    // Event Type: omit for New Band Member
    String? effectiveEventType;
    if (!isNewMember) {
      for (final r in requests) {
        final ev = r.resolvedEventType?.trim();
        if (ev != null && ev.isNotEmpty) {
          effectiveEventType = ev;
          break;
        }
      }
    }

    final paid = requests.any((r) => r.isPaid);
    String? paymentStr;
    if (paid) {
      final paidReq = requests.firstWhere((r) => r.isPaid, orElse: () => first);
      paymentStr = formatSubRequestPaymentDisplay(paidReq);
    }

    String? line3;
    if (effectiveEventType != null && paymentStr != null) {
      line3 = '$effectiveEventType · $paymentStr';
    } else if (effectiveEventType != null) {
      line3 = effectiveEventType;
    } else if (paymentStr != null) {
      line3 = paymentStr;
    }

    // Line 4: Date & Time (earliest date)
    String? dateTimeLine;
    if (!isNewMember) {
      dateTimeLine = formatSubRequestDateTime(
        date: first.date,
        startTime: first.startTime,
        endTime: first.endTime,
      );
    }

    final loc = (locationOverride != null && locationOverride.trim().isNotEmpty)
        ? locationOverride.trim()
        : (first.location != null && first.location!.trim().isNotEmpty)
            ? first.location!.trim()
            : (first.city != null && first.city!.trim().isNotEmpty)
                ? first.city!.trim()
                : null;

    final creator = requests.any((r) => isCreatorOfSubRequest(r, currentUserId));
    final applied = requests.any((r) => hasAppliedToSubRequest(r, currentUserId, appliedIds: appliedIds));
    final assigned = requests.every((r) => r.status == 'assigned' || (r.assignedUserId != null && r.assignedUserId!.trim().isNotEmpty));

    final desc = (descriptionOverride != null && descriptionOverride.trim().isNotEmpty)
        ? descriptionOverride.trim()
        : (first.description != null && first.description!.trim().isNotEmpty)
            ? first.description!.trim()
            : null;

    final details = (payDetailsOverride != null && payDetailsOverride.trim().isNotEmpty)
        ? payDetailsOverride.trim()
        : (first.payDetails != null && first.payDetails!.trim().isNotEmpty)
            ? first.payDetails!.trim()
            : null;

    return SubRequestCardPresentation(
      bandName: band,
      requestType: typeLabel,
      roleInstrument: roleDisplay,
      distinctRoles: distinctRolesList,
      eventType: effectiveEventType,
      isPaid: paid,
      formattedPayment: paymentStr,
      eventTypeAndPaymentLine: line3,
      formattedDateTime: dateTimeLine,
      locationVenue: loc,
      description: desc,
      payDetails: details,
      isCreator: creator,
      isBandAdmin: isBandAdmin,
      isCreatorOrBandAdmin: creator || isBandAdmin,
      isBandAdminPending: !creator && isBandAdminPending,
      isBandAdminFailed: !creator && isBandAdminFailed,
      hasApplied: applied,
      isAssigned: assigned,
    );
  }
}

/// Internal helper for time-of-day parsing.
class SubRequestTimeOfDay {
  final int hour;
  final int minute;
  const SubRequestTimeOfDay(this.hour, this.minute);
}

/// Parses time strings (e.g. '18:00', '18.00', '18:00:00', '02:30', '24:00').
/// Returns null if string is missing, malformed or out of bounds.
SubRequestTimeOfDay? parseSubRequestTimeOfDay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final clean = raw.trim();
  final match = RegExp(r'^(\d{1,2})[:.](\d{2})(?::\d{2})?$').firstMatch(clean);
  if (match == null) return null;
  final h = int.tryParse(match.group(1)!);
  final m = int.tryParse(match.group(2)!);
  if (h == null || m == null) return null;
  if (h == 24 && m == 0) {
    return const SubRequestTimeOfDay(24, 0);
  }
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return SubRequestTimeOfDay(h, m);
}

/// Parses calendar dates in ISO (YYYY-MM-DD), YYYY/MM/DD, or DD/MM/YYYY formats.
/// Returns a [DateTime] normalized to local midnight (year, month, day), or null if invalid.
DateTime? parseSubRequestCalendarDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final str = raw.trim();
  final parsed = DateTime.tryParse(str);
  if (parsed != null) {
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  if (str.contains('/')) {
    final parts = str.split('/');
    if (parts.length == 3) {
      try {
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
      } catch (_) {}
    }
  }
  return null;
}

/// Normalizes a raw status string to a lowercase canonical value.
String normalizeSubRequestStatus(String? status) {
  if (status == null) return '';
  final s = status.trim().toLowerCase();
  if (s == 'canceled') return 'cancelled';
  return s;
}

/// Checks whether a normalized status represents an explicitly active/open request.
/// Returns true ONLY for: 'published', 'open', 'active'.
/// Unknown, empty, or other status values return false without mutation.
bool isSubRequestStatusActive(String? status) {
  final s = normalizeSubRequestStatus(status);
  return s == 'published' || s == 'open' || s == 'active';
}

/// Checks whether a SubRequest has reached or passed its end boundary.
///
/// For dated staffing requests:
/// - Future request: not expired (returns false).
/// - Current request before its end boundary: not expired (returns false).
/// - At exact end boundary: expired (returns true).
/// - Past request: expired (returns true).
///
/// If valid end time exists:
/// - boundary is on event date at endTime.
/// - If endTime is earlier than startTime (midnight-crossing), boundary is on the
///   next local calendar day at endTime.
///
/// If date exists but end time is missing or unparsable:
/// - boundary is next local calendar day at 00:00 (end of event calendar date).
///
/// If date is missing or unparsable:
/// - does not expire by date (returns false).
bool isSubRequestExpired(
  SubRequest req, {
  DateTime? now,
}) {
  final boundary = subRequestExpirationBoundary(req);
  return boundary != null && !(now ?? DateTime.now()).isBefore(boundary);
}

/// Shared local expiration boundary, also used for read-only UI timers.
/// Missing or malformed legacy dates have no known boundary.
DateTime? subRequestExpirationBoundary(SubRequest req) {
  final rawDate = req.date?.trim();
  if (rawDate == null || rawDate.isEmpty) {
    return null;
  }

  final parsedDate = parseSubRequestCalendarDate(rawDate);
  if (parsedDate == null) {
    return null;
  }

  final parsedEndTime = parseSubRequestTimeOfDay(req.endTime);
  if (parsedEndTime != null) {
    final parsedStartTime = parseSubRequestTimeOfDay(req.startTime);
    final crossesMidnight = parsedStartTime != null &&
        (parsedEndTime.hour < parsedStartTime.hour ||
            (parsedEndTime.hour == parsedStartTime.hour && parsedEndTime.minute <= parsedStartTime.minute));

    final endCalendarDay = crossesMidnight
        ? DateTime(parsedDate.year, parsedDate.month, parsedDate.day + 1)
        : parsedDate;

    final boundary = parsedEndTime.hour == 24
        ? DateTime(endCalendarDay.year, endCalendarDay.month, endCalendarDay.day + 1, 0, 0)
        : DateTime(
            endCalendarDay.year,
            endCalendarDay.month,
            endCalendarDay.day,
            parsedEndTime.hour,
            parsedEndTime.minute,
          );

    return boundary;
  }

  // Exact no-end boundary: next local calendar day at 00:00 (absent beginning at next local midnight)
  final nextDayMidnight = DateTime(
    parsedDate.year,
    parsedDate.month,
    parsedDate.day + 1,
    0,
    0,
    0,
  );
  return nextDayMidnight;
}

/// Central pure policy determining whether a SubRequest is an active application
/// for the current musician under Find Gigs -> Applied.
///
/// Conditions for active Applied status:
/// 1. [currentUserId] is non-empty.
/// 2. Current user has actually applied to this exact [subRequestId].
/// 3. Request is not a map-only pin.
/// 4. Normalized status is explicitly active ('published', 'open', 'active').
/// 5. Request has not been cancelled, deleted, closed, archived, filled, or assigned.
/// 6. Request has not been assigned to anyone (assigned status, assignedUserId present, or isSelected).
/// 7. New Band Member requests (identified via [SubRequest.isNewMemberRecord]):
///    remain active while status is active; do not expire merely because date is absent.
/// 8. Dated staffing requests: have not reached or passed their deterministic lifecycle boundary.
bool isActiveAppliedRequest(
  SubRequest request, {
  required String? currentUserId,
  DateTime? now,
  Set<String>? appliedIds,
}) {
  if (currentUserId == null || currentUserId.trim().isEmpty) return false;
  final uid = currentUserId.trim();

  // 1. Verify user applied to this exact subRequestId
  if (!hasAppliedToSubRequest(request, uid, appliedIds: appliedIds)) {
    return false;
  }

  // 2. Defensive exclusion for map pins
  if (request.isMapOnlyPin) return false;

  // 3. Status checking & normalization
  final normStatus = normalizeSubRequestStatus(request.status);

  // Inactive / terminal statuses
  if (normStatus == 'cancelled' ||
      normStatus == 'deleted' ||
      normStatus == 'closed' ||
      normStatus == 'archived' ||
      normStatus == 'filled' ||
      normStatus == 'assigned' ||
      normStatus == 'draft' ||
      normStatus == 'expired') {
    return false;
  }

  // Must be explicitly recognized active status
  if (!isSubRequestStatusActive(normStatus)) {
    return false;
  }

  // 4. Assignment checking (whether assigned to current user or someone else)
  if (request.isSelected == true) return false;
  final assignedTo = request.assignedUserId?.trim() ??
      request.extraFields['assignedUserId']?.toString().trim() ??
      request.extraFields['AssignedUserId']?.toString().trim();
  if (assignedTo != null && assignedTo.isNotEmpty) {
    return false;
  }

  // 5. New Band Member vs Dated requests:
  // Use existing centralized New Member classifier from SubRequest model
  if (request.isNewMember) {
    // New Band Member does not expire by date; if date is absent, remains visible while status is active.
    // If a date is explicitly provided, verify it has not expired.
    if (request.date != null && request.date!.trim().isNotEmpty) {
      if (isSubRequestExpired(request, now: now)) {
        return false;
      }
    }
    return true;
  }

  // 6. Dated staffing request: verify deterministic lifecycle boundary
  if (isSubRequestExpired(request, now: now)) {
    return false;
  }

  return true;
}

/// Read-only active management policy. Uses the same status and expiration
/// rules as Applied, without requiring an application by the manager.
bool isActiveManageRequest(SubRequest request, {DateTime? now}) {
  if (!isSubRequestStatusActive(request.status) ||
      request.isMapOnlyPin ||
      request.isSelected) {
    return false;
  }
  final assignedTo = request.assignedUserId?.trim() ??
      request.extraFields['assignedUserId']?.toString().trim() ??
      request.extraFields['AssignedUserId']?.toString().trim();
  if (assignedTo != null && assignedTo.isNotEmpty) return false;
  return !isSubRequestExpired(request, now: now);
}

/// Retains the first authorized feed copy for each exact request ID. Positions
/// sharing an event/group remain independent. Records without IDs are not cards.
List<SubRequest> filterActiveManageRequests(
  Iterable<SubRequest> requests, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final seen = <String>{};
  return requests.where((request) {
    final id = request.subRequestId ?? request.id ?? '';
    if (id.isEmpty || !seen.add(id)) return false;
    return isActiveManageRequest(request, now: clock);
  }).toList();
}
