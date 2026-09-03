import 'package:intl/intl.dart';

class SubRequest {
  final String? id;
  final String? subRequestId;
  final String? slotId;
  final String? creatorUserId;
  final String? userId;
  final String? voicePart;
  final String? location;
  final String? startTime;
  final String? endTime;
  final String? description;
  final String? date;
  final String? role;
  final bool isPaid;
  final String? bandName;
  final String? rehearsalDayOfWeek;
  final bool isSelected;
  final int responseCount;
  final String? formattedTimeRange;
  final String? dateLabel;
  final String? level;
  final String? style;
  final Map<String, bool> responses;
  final double? latitude;
  final double? longitude;
  final List<String>? targetUserIds;
  final String? eventId;
  final String? bandId;
  final String? replacedMemberId;
  final String? replacedMemberName;
  final String status; // 'draft', 'published', 'assigned', 'closed', 'cancelled'
  final String? assignedUserId;
  final String? assignedUserName;
  final int? assignedAt;
  final int? createdAt;
  final String? searchSource; // 'favorites' or 'search_all'
  final String? requestGroupId;
  final int? eventSequence;
  final String? eventTitle;
  final int? payAmount; // Exact integer whole currency units (e.g. 1500 for SEK 1,500)
  final int? payAmountMinor; // Exact integer minor currency units (e.g. 150000 öre)
  final String? currency; // ISO currency code, e.g. 'SEK'
  final String? payDetails; // Payment-related information/details
  final Map<String, dynamic> extraFields;

  SubRequest({
    this.id,
    this.subRequestId,
    this.slotId,
    this.creatorUserId,
    this.userId,
    this.voicePart,
    this.location,
    this.startTime,
    this.endTime,
    this.description,
    this.date,
    this.role,
    this.isPaid = false,
    this.bandName,
    this.rehearsalDayOfWeek,
    this.isSelected = false,
    this.responseCount = 0,
    this.formattedTimeRange,
    this.dateLabel,
    this.level,
    this.style,
    this.responses = const {},
    this.latitude,
    this.longitude,
    this.targetUserIds,
    this.eventId,
    this.bandId,
    this.replacedMemberId,
    this.replacedMemberName,
    this.status = 'published',
    this.assignedUserId,
    this.assignedUserName,
    this.assignedAt,
    this.createdAt,
    this.searchSource,
    this.requestGroupId,
    this.eventSequence,
    this.eventTitle,
    int? payAmount,
    int? payAmountMinor,
    this.currency,
    this.payDetails,
    this.extraFields = const {},
  })  : payAmount = payAmount ?? (payAmountMinor != null ? payAmountMinor ~/ 100 : null),
        payAmountMinor = payAmountMinor ?? (payAmount != null ? payAmount * 100 : null);

  factory SubRequest.fromJson(Map<dynamic, dynamic> json, String keyId) {
    final responsesRaw = json['Responses'];
    final Map<String, bool> parsedResponses = {};
    if (responsesRaw is Map) {
      responsesRaw.forEach((k, v) {
        parsedResponses[k.toString()] = v == true;
      });
    }

    final latRaw = json['Latitude'];
    final lngRaw = json['Longitude'];
    double? parsedLat;
    double? parsedLng;
    if (latRaw is num) parsedLat = latRaw.toDouble();
    if (lngRaw is num) parsedLng = lngRaw.toDouble();

    final targetUserIdsRaw = json['TargetUserIds'];
    List<String>? parsedTargetUserIds;
    if (targetUserIdsRaw is List) {
      parsedTargetUserIds = targetUserIdsRaw.map((e) => e.toString()).toList();
    } else if (targetUserIdsRaw is Map) {
      parsedTargetUserIds = targetUserIdsRaw.values.map((e) => e.toString()).toList();
    }

    final isSelected = json['IsSelected'] == true;
    final explicitStatus = json['Status']?.toString();
    final derivedStatus = explicitStatus ?? (isSelected ? 'assigned' : 'published');

    final explicitSource = json['SearchSource']?.toString();
    final derivedSource = explicitSource ??
        (parsedTargetUserIds != null && parsedTargetUserIds.isNotEmpty
            ? 'favorites'
            : 'search_all');

    const knownKeys = {
      'id',
      'SubRequestId',
      'SlotId',
      'CreatorUserId',
      'UserId',
      'VoicePart',
      'Location',
      'StartTime',
      'EndTime',
      'Description',
      'Date',
      'Role',
      'IsPaid',
      'BandName',
      'RehearsalDayOfWeek',
      'IsSelected',
      'ResponseCount',
      'FormattedTimeRange',
      'DateLabel',
      'Level',
      'Style',
      'Responses',
      'Latitude',
      'Longitude',
      'TargetUserIds',
      'eventId',
      'bandId',
      'EventId',
      'BandId',
      'ReplacedMemberId',
      'ReplacedMemberName',
      'Status',
      'AssignedUserId',
      'AssignedUserName',
      'AssignedAt',
      'CreatedAt',
      'SearchSource',
      'RequestGroupId',
      'requestGroupId',
      'EventSequence',
      'eventSequence',
      'EventTitle',
      'eventTitle',
      'PayAmount',
      'payAmount',
      'Currency',
      'currency',
      'PayDetails',
      'payDetails',
    };

    final Map<String, dynamic> extra = {};
    json.forEach((k, v) {
      final keyStr = k.toString();
      if (!knownKeys.contains(keyStr)) {
        extra[keyStr] = v;
      }
    });

    final rawPayAmountMinor = json['PayAmountMinor'] ?? json['payAmountMinor'];
    final parsedPayAmountMinor = rawPayAmountMinor is int
        ? rawPayAmountMinor
        : int.tryParse(rawPayAmountMinor?.toString() ?? '');

    final rawPayAmount = json['PayAmount'] ?? json['payAmount'];
    final parsedLegacyPayAmount = rawPayAmount is int
        ? rawPayAmount
        : int.tryParse(rawPayAmount?.toString() ?? '');

    // Canonical PayAmountMinor wins if both exist; fallback to legacy PayAmount * 100
    final effectiveMinor = parsedPayAmountMinor ?? (parsedLegacyPayAmount != null ? parsedLegacyPayAmount * 100 : null);

    return SubRequest(
      id: keyId,
      subRequestId: json['SubRequestId']?.toString() ?? keyId,
      slotId: json['SlotId']?.toString() ?? json['SubRequestId']?.toString() ?? keyId,
      creatorUserId: json['CreatorUserId']?.toString(),
      userId: json['UserId']?.toString(),
      voicePart: json['VoicePart']?.toString(),
      location: json['Location']?.toString(),
      startTime: json['StartTime']?.toString(),
      endTime: json['EndTime']?.toString(),
      description: json['Description']?.toString(),
      date: json['Date']?.toString(),
      role: json['Role']?.toString(),
      isPaid: json['IsPaid'] == true,
      bandName: json['BandName']?.toString(),
      rehearsalDayOfWeek: json['RehearsalDayOfWeek']?.toString(),
      isSelected: isSelected,
      responseCount: json['ResponseCount'] is int
          ? json['ResponseCount'] as int
          : parsedResponses.length,
      formattedTimeRange: json['FormattedTimeRange']?.toString(),
      dateLabel: json['DateLabel']?.toString(),
      level: json['Level']?.toString(),
      style: json['Style']?.toString(),
      responses: parsedResponses,
      latitude: parsedLat,
      longitude: parsedLng,
      targetUserIds: parsedTargetUserIds,
      eventId: json['eventId']?.toString() ?? json['EventId']?.toString(),
      bandId: json['bandId']?.toString() ?? json['BandId']?.toString(),
      replacedMemberId: json['ReplacedMemberId']?.toString(),
      replacedMemberName: json['ReplacedMemberName']?.toString(),
      status: derivedStatus,
      assignedUserId: json['AssignedUserId']?.toString(),
      assignedUserName: json['AssignedUserName']?.toString(),
      assignedAt: json['AssignedAt'] is int
          ? json['AssignedAt'] as int
          : int.tryParse(json['AssignedAt']?.toString() ?? ''),
      createdAt: json['CreatedAt'] is int
          ? json['CreatedAt'] as int
          : int.tryParse(json['CreatedAt']?.toString() ?? ''),
      searchSource: derivedSource,
      requestGroupId: json['RequestGroupId']?.toString() ?? json['requestGroupId']?.toString(),
      eventSequence: json['EventSequence'] is int
          ? json['EventSequence'] as int
          : int.tryParse(json['EventSequence']?.toString() ?? ''),
      eventTitle: json['EventTitle']?.toString() ?? json['eventTitle']?.toString(),
      payAmountMinor: effectiveMinor,
      currency: json['Currency']?.toString() ?? json['currency']?.toString() ?? (json['IsPaid'] == true ? 'SEK' : null),
      payDetails: json['PayDetails']?.toString() ?? json['payDetails']?.toString(),
      extraFields: extra,
    );
  }

  String get formattedPayAmount {
    if (!isPaid) return 'Unpaid';
    if (payAmount == null || payAmount! <= 0) return 'Paid · Amount not specified';
    final curr = currency ?? 'SEK';
    final formatted = NumberFormat('#,##0').format(payAmount);
    return 'Paid · $curr $formatted';
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{...extraFields};
    map.addAll({
      'SubRequestId': subRequestId,
      'SlotId': slotId ?? subRequestId,
      'CreatorUserId': creatorUserId,
      'UserId': userId,
      'VoicePart': voicePart,
      'Location': location,
      'StartTime': startTime,
      'EndTime': endTime,
      'Description': description,
      'Date': date,
      'Role': role,
      'IsPaid': isPaid,
      if (payAmountMinor != null) 'PayAmountMinor': payAmountMinor,
      if (currency != null) 'Currency': currency,
      'BandName': bandName,
      'RehearsalDayOfWeek': rehearsalDayOfWeek,
      'IsSelected': isSelected,
      'ResponseCount': responseCount,
      'FormattedTimeRange': formattedTimeRange,
      'DateLabel': dateLabel,
      'Level': level,
      'Style': style,
      'Responses': responses,
      'Latitude': latitude,
      'Longitude': longitude,
      'TargetUserIds': targetUserIds,
      'eventId': eventId,
      'bandId': bandId,
      if (replacedMemberId != null) 'ReplacedMemberId': replacedMemberId,
      if (replacedMemberName != null) 'ReplacedMemberName': replacedMemberName,
      'Status': status,
      if (assignedUserId != null) 'AssignedUserId': assignedUserId,
      if (assignedUserName != null) 'AssignedUserName': assignedUserName,
      if (assignedAt != null) 'AssignedAt': assignedAt,
      if (createdAt != null) 'CreatedAt': createdAt,
      if (searchSource != null) 'SearchSource': searchSource,
      if (requestGroupId != null) 'RequestGroupId': requestGroupId,
      if (eventSequence != null) 'EventSequence': eventSequence,
      if (eventTitle != null) 'EventTitle': eventTitle,
      if (payAmount != null) 'PayAmount': payAmount,
      if (currency != null) 'Currency': currency,
      if (payDetails != null && payDetails!.trim().isNotEmpty) 'PayDetails': payDetails,
    });
    return map;
  }

  SubRequest copyWith({
    String? id,
    String? subRequestId,
    String? slotId,
    String? creatorUserId,
    String? userId,
    String? voicePart,
    String? location,
    String? startTime,
    String? endTime,
    String? description,
    String? date,
    String? role,
    bool? isPaid,
    String? bandName,
    String? rehearsalDayOfWeek,
    bool? isSelected,
    int? responseCount,
    String? formattedTimeRange,
    String? dateLabel,
    String? level,
    String? style,
    Map<String, bool>? responses,
    double? latitude,
    double? longitude,
    List<String>? targetUserIds,
    String? eventId,
    String? bandId,
    String? replacedMemberId,
    String? replacedMemberName,
    String? status,
    String? assignedUserId,
    String? assignedUserName,
    int? assignedAt,
    int? createdAt,
    String? searchSource,
    String? requestGroupId,
    int? eventSequence,
    String? eventTitle,
    int? payAmount,
    String? currency,
    String? payDetails,
    Map<String, dynamic>? extraFields,
  }) {
    return SubRequest(
      id: id ?? this.id,
      subRequestId: subRequestId ?? this.subRequestId,
      slotId: slotId ?? this.slotId,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      userId: userId ?? this.userId,
      voicePart: voicePart ?? this.voicePart,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      date: date ?? this.date,
      role: role ?? this.role,
      isPaid: isPaid ?? this.isPaid,
      bandName: bandName ?? this.bandName,
      rehearsalDayOfWeek: rehearsalDayOfWeek ?? this.rehearsalDayOfWeek,
      isSelected: isSelected ?? this.isSelected,
      responseCount: responseCount ?? this.responseCount,
      formattedTimeRange: formattedTimeRange ?? this.formattedTimeRange,
      dateLabel: dateLabel ?? this.dateLabel,
      level: level ?? this.level,
      style: style ?? this.style,
      responses: responses ?? this.responses,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      targetUserIds: targetUserIds ?? this.targetUserIds,
      eventId: eventId ?? this.eventId,
      bandId: bandId ?? this.bandId,
      replacedMemberId: replacedMemberId ?? this.replacedMemberId,
      replacedMemberName: replacedMemberName ?? this.replacedMemberName,
      status: status ?? this.status,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      assignedUserName: assignedUserName ?? this.assignedUserName,
      assignedAt: assignedAt ?? this.assignedAt,
      createdAt: createdAt ?? this.createdAt,
      searchSource: searchSource ?? this.searchSource,
      requestGroupId: requestGroupId ?? this.requestGroupId,
      eventSequence: eventSequence ?? this.eventSequence,
      eventTitle: eventTitle ?? this.eventTitle,
      payAmount: payAmount ?? this.payAmount,
      currency: currency ?? this.currency,
      payDetails: payDetails ?? this.payDetails,
      extraFields: extraFields ?? this.extraFields,
    );
  }
}
