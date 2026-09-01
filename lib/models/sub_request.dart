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
  });

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
      eventId: json['eventId']?.toString(),
      bandId: json['bandId']?.toString(),
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
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
    );
  }
}
