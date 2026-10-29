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
    final assigned = req.status == 'assigned' || req.assignedUserId != null;

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
    final assigned = requests.every((r) => r.status == 'assigned' || r.assignedUserId != null);

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
