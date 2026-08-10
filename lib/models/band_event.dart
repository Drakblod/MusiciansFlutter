class EventResponse {
  final String status; // 'YES', 'NO', 'UNCERTAIN' (legacy: 'attending', 'declined', 'maybe')
  final DateTime timestamp;
  final String? comment;
  final String? uncertainReason;

  EventResponse({
    required this.status,
    required this.timestamp,
    this.comment,
    this.uncertainReason,
  });

  factory EventResponse.fromJson(Map<dynamic, dynamic> json) {
    return EventResponse(
      status: json['status']?.toString() ?? 'NO',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      comment: json['comment']?.toString(),
      uncertainReason: json['uncertainReason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (comment != null) 'comment': comment,
      if (uncertainReason != null) 'uncertainReason': uncertainReason,
    };
  }
}

class ExternalInvitee {
  final String userId;
  final String status; // 'pending', 'attending', 'maybe', 'declined'
  final String? instrument;
  final int invitedAt; // epoch millis
  final String? source; // e.g. 'subRequest'
  final String? subRequestId;
  final String? displayName;
  final String? comment;

  ExternalInvitee({
    required this.userId,
    required this.status,
    this.instrument,
    required this.invitedAt,
    this.source,
    this.subRequestId,
    this.displayName,
    this.comment,
  });

  factory ExternalInvitee.fromJson(Map<dynamic, dynamic> json, String userId) {
    return ExternalInvitee(
      userId: userId,
      status: json['status']?.toString() ?? 'pending',
      instrument: json['instrument']?.toString(),
      invitedAt: json['invitedAt'] is int
          ? json['invitedAt'] as int
          : int.tryParse(json['invitedAt']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      source: json['source']?.toString(),
      subRequestId: json['subRequestId']?.toString(),
      displayName: json['displayName']?.toString(),
      comment: json['comment']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'instrument': instrument,
      'invitedAt': invitedAt,
      'source': source,
      'subRequestId': subRequestId,
      'displayName': displayName,
      if (comment != null) 'comment': comment,
    };
  }
}

class BandEvent {
  final String? id;
  final String title;
  final String description;
  final String eventType; // 'Rehearsal', 'Concert', 'Gig', 'Recording Session', 'Meeting', 'Other'
  final String location;
  final String startDateTime; // ISO 8601 string
  final String endDateTime; // ISO 8601 string
  final String additionalNotes;
  final String createdBy;
  final int createdAt; // epoch millis
  final int updatedAt; // epoch millis
  final bool requireResponse;
  final Map<String, EventResponse> responses;
  final bool isLocked;
  final int? lockedAt;
  final String? lockedBy;
  final bool creatorThresholdNotified;
  final bool sentReminder48h;
  final bool sentReminder72h;
  final bool sentReminder84h;
  final Map<String, ExternalInvitee> externalInvitees;
  final int? rsvpDeadline; // epoch millis
  final int? reminderIntervalHours; // e.g. 24, 48, 72
  final String? temporaryRoomId;
  final String? parentEventId;
  final int? subEventSequence;

  BandEvent({
    this.id,
    required this.title,
    required this.description,
    required this.eventType,
    required this.location,
    required this.startDateTime,
    required this.endDateTime,
    required this.additionalNotes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.requireResponse,
    this.responses = const {},
    this.isLocked = false,
    this.lockedAt,
    this.lockedBy,
    this.creatorThresholdNotified = false,
    this.sentReminder48h = false,
    this.sentReminder72h = false,
    this.sentReminder84h = false,
    this.externalInvitees = const {},
    this.rsvpDeadline,
    this.reminderIntervalHours,
    this.temporaryRoomId,
    this.parentEventId,
    this.subEventSequence,
  });

  factory BandEvent.fromJson(Map<dynamic, dynamic> json, String keyId) {
    final Map<String, EventResponse> parsedResponses = {};
    final responsesRaw = json['Responses'];
    if (responsesRaw is Map) {
      responsesRaw.forEach((k, v) {
        if (v is Map) {
          parsedResponses[k.toString()] = EventResponse.fromJson(v);
        }
      });
    }

    final Map<String, ExternalInvitee> parsedExternalInvitees = {};
    final externalInviteesRaw = json['externalInvitees'];
    if (externalInviteesRaw is Map) {
      externalInviteesRaw.forEach((k, v) {
        if (v is Map) {
          parsedExternalInvitees[k.toString()] = ExternalInvitee.fromJson(v, k.toString());
        }
      });
    }

    return BandEvent(
      id: keyId,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'Other',
      location: json['location']?.toString() ?? '',
      startDateTime: json['startDateTime']?.toString() ?? '',
      endDateTime: json['endDateTime']?.toString() ?? '',
      additionalNotes: json['additionalNotes']?.toString() ?? '',
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      requireResponse: json['requireResponse'] == true,
      responses: parsedResponses,
      isLocked: json['isLocked'] == true,
      lockedAt: json['lockedAt'] is int
          ? json['lockedAt'] as int
          : int.tryParse(json['lockedAt']?.toString() ?? ''),
      lockedBy: json['lockedBy']?.toString(),
      creatorThresholdNotified: json['creatorThresholdNotified'] == true,
      sentReminder48h: json['sentReminder48h'] == true,
      sentReminder72h: json['sentReminder72h'] == true,
      sentReminder84h: json['sentReminder84h'] == true,
      externalInvitees: parsedExternalInvitees,
      rsvpDeadline: json['rsvpDeadline'] is int
          ? json['rsvpDeadline'] as int
          : int.tryParse(json['rsvpDeadline']?.toString() ?? ''),
      reminderIntervalHours: json['reminderIntervalHours'] is int
          ? json['reminderIntervalHours'] as int
          : int.tryParse(json['reminderIntervalHours']?.toString() ?? ''),
      temporaryRoomId: json['temporaryRoomId']?.toString(),
      parentEventId: json['parentEventId']?.toString(),
      subEventSequence: json['subEventSequence'] is int
          ? json['subEventSequence'] as int
          : int.tryParse(json['subEventSequence']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> responsesMap = {};
    responses.forEach((k, v) {
      responsesMap[k] = v.toJson();
    });

    final Map<String, dynamic> externalInviteesMap = {};
    externalInvitees.forEach((k, v) {
      externalInviteesMap[k] = v.toJson();
    });

    return {
      'title': title,
      'description': description,
      'eventType': eventType,
      'location': location,
      'startDateTime': startDateTime,
      'endDateTime': endDateTime,
      'additionalNotes': additionalNotes,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'requireResponse': requireResponse,
      'Responses': responsesMap,
      'isLocked': isLocked,
      'lockedAt': lockedAt,
      'lockedBy': lockedBy,
      'creatorThresholdNotified': creatorThresholdNotified,
      'sentReminder48h': sentReminder48h,
      'sentReminder72h': sentReminder72h,
      'sentReminder84h': sentReminder84h,
      'externalInvitees': externalInviteesMap,
      if (rsvpDeadline != null) 'rsvpDeadline': rsvpDeadline,
      if (reminderIntervalHours != null) 'reminderIntervalHours': reminderIntervalHours,
      if (temporaryRoomId != null) 'temporaryRoomId': temporaryRoomId,
      if (parentEventId != null) 'parentEventId': parentEventId,
      if (subEventSequence != null) 'subEventSequence': subEventSequence,
    };
  }
}
