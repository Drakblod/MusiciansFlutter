class SubRequest {
  final String? id;
  final String? subRequestId;
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

  SubRequest({
    this.id,
    this.subRequestId,
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

    return SubRequest(
      id: keyId,
      subRequestId: json['SubRequestId']?.toString() ?? keyId,
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
      isSelected: json['IsSelected'] == true,
      responseCount: json['ResponseCount'] is int ? json['ResponseCount'] as int : 0,
      formattedTimeRange: json['FormattedTimeRange']?.toString(),
      dateLabel: json['DateLabel']?.toString(),
      level: json['Level']?.toString(),
      style: json['Style']?.toString(),
      responses: parsedResponses,
      latitude: parsedLat,
      longitude: parsedLng,
      targetUserIds: parsedTargetUserIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'SubRequestId': subRequestId,
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
    };
  }
}
