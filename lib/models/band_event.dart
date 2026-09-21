class EventResponse {
  final String
  status; // 'YES', 'NO', 'UNCERTAIN' (legacy: 'attending', 'declined', 'maybe')
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
          : int.tryParse(json['invitedAt']?.toString() ?? '') ??
                DateTime.now().millisecondsSinceEpoch,
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
}enum EventResponseStatus {
  yes,
  no,
  uncertain,
  noAnswer,
}

EventResponseStatus classifyEventResponse(String? rawStatus) {
  if (rawStatus == null || rawStatus.trim().isEmpty) {
    return EventResponseStatus.noAnswer;
  }
  final s = rawStatus.trim().toLowerCase();
  if (s == 'yes' || s == 'attending') {
    return EventResponseStatus.yes;
  }
  if (s == 'no' || s == 'declined') {
    return EventResponseStatus.no;
  }
  if (s == 'uncertain' || s == 'maybe') {
    return EventResponseStatus.uncertain;
  }
  return EventResponseStatus.noAnswer;
}

class SubstituteAssignment {
  final String slotId;
  final String? subRequestId;
  final String assignedUserId;
  final String? assignedUserName;
  final String? instrument;
  final String? replacedMemberId;
  final String? replacedMemberName;
  final String status;
  final int? assignedAt;
  final String? assignedBy;

  SubstituteAssignment({
    required this.slotId,
    this.subRequestId,
    required this.assignedUserId,
    this.assignedUserName,
    this.instrument,
    this.replacedMemberId,
    this.replacedMemberName,
    required this.status,
    this.assignedAt,
    this.assignedBy,
  });

  factory SubstituteAssignment.fromJson(Map<dynamic, dynamic> json, String slotId) {
    return SubstituteAssignment(
      slotId: json['slotId']?.toString() ?? slotId,
      subRequestId: json['subRequestId']?.toString(),
      assignedUserId: json['assignedUserId']?.toString() ?? '',
      assignedUserName: json['assignedUserName']?.toString(),
      instrument: json['instrument']?.toString(),
      replacedMemberId: json['replacedMemberId']?.toString(),
      replacedMemberName: json['replacedMemberName']?.toString(),
      status: json['status']?.toString() ?? 'assigned',
      assignedAt: json['assignedAt'] is int
          ? json['assignedAt'] as int
          : int.tryParse(json['assignedAt']?.toString() ?? ''),
      assignedBy: json['assignedBy']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotId': slotId,
      if (subRequestId != null) 'subRequestId': subRequestId,
      'assignedUserId': assignedUserId,
      if (assignedUserName != null) 'assignedUserName': assignedUserName,
      if (instrument != null) 'instrument': instrument,
      if (replacedMemberId != null) 'replacedMemberId': replacedMemberId,
      if (replacedMemberName != null) 'replacedMemberName': replacedMemberName,
      'status': status,
      if (assignedAt != null) 'assignedAt': assignedAt,
      if (assignedBy != null) 'assignedBy': assignedBy,
    };
  }

  bool get isConfirmedAssignment {
    final uid = assignedUserId.trim();
    if (uid.isEmpty) return false;
    final s = status.trim().toLowerCase();
    if (s == 'revoked' ||
        s == 'cancelled' ||
        s == 'canceled' ||
        s == 'unassigned' ||
        s == 'published' ||
        s == 'draft' ||
        s == 'open' ||
        s == 'accepted' ||
        s == 'selected' ||
        s == 'favorite' ||
        s == 'applicant') {
      return false;
    }
    return s == 'assigned' || s == 'filled';
  }
}

class EventRehearsal {
  static const List<String> gigTypes = [
    'Club gig',
    'Concert',
    'Show',
    'Private Event',
  ];

  static const List<String> sessionTypes = [
    'Rehearsal',
    'Soundcheck',
    'Load-in / Setup',
    'Meeting',
    'Other',
  ];

  static const List<String> standardSessionTypes = [
    'Rehearsal',
    'Soundcheck',
    'Club gig',
    'Concert',
    'Show',
    'Private Event',
    'Load-in / Setup',
    'Meeting',
    'Other',
  ];

  final String id;
  final String date; // 'YYYY-MM-DD' or ISO-8601 string
  final String startTime; // 'HH:mm'
  final String endTime; // 'HH:mm'
  final String location;
  final String description;
  final String type; // e.g. 'Rehearsal', 'Soundcheck', 'Club gig', etc.

  EventRehearsal({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.location = '',
    this.description = '',
    this.type = 'Rehearsal',
  });

  factory EventRehearsal.fromJson(Map<dynamic, dynamic> json, [String? id]) {
    return EventRehearsal(
      id: json['id']?.toString() ?? id ?? '',
      date: json['date']?.toString() ?? '',
      startTime: json['startTime']?.toString() ?? '',
      endTime: json['endTime']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Rehearsal',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'type': type,
      if (location.isNotEmpty) 'location': location,
      if (description.isNotEmpty) 'description': description,
    };
  }

  EventRehearsal copyWith({
    String? id,
    String? date,
    String? startTime,
    String? endTime,
    String? location,
    String? description,
    String? type,
  }) {
    return EventRehearsal(
      id: id ?? this.id,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      description: description ?? this.description,
      type: type ?? this.type,
    );
  }
}

typedef EventSession = EventRehearsal;


class BandEvent {
  /// Standard active creation choices for newly created events in owner-approved order.
  static const List<String> standardEventTypes = [
    'Rehearsal',
    'Concert',
    'Club gig',
    'Private Event',
    'Tour',
    'Show',
    'Other',
  ];

  final String? id;
  final String title;
  final String description;
  /// Active creation choices: 'Rehearsal', 'Concert', 'Club gig', 'Private Event', 'Tour', 'Show', 'Other'.
  /// Legacy values: 'Recording Session', 'Meeting', 'Gig', 'Event'.
  final String eventType;
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
  final bool sentReminder24h;
  final bool sentReminder48h;
  final bool sentReminder72h;
  final bool sentReminder84h;
  final Map<String, ExternalInvitee> externalInvitees;
  final Map<String, SubstituteAssignment> substituteAssignments;
  final int? rsvpDeadline; // epoch millis
  final int? reminderIntervalHours; // e.g. 24, 48, 72
  final String? temporaryRoomId;
  final String? parentEventId;
  final int? subEventSequence;
  final List<EventRehearsal> rehearsals;

  BandEvent({
    this.id,
    required this.title,
    required this.description,
    this.eventType = 'Event',
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
    this.sentReminder24h = false,
    this.sentReminder48h = false,
    this.sentReminder72h = false,
    this.sentReminder84h = false,
    this.externalInvitees = const {},
    this.substituteAssignments = const {},
    this.rsvpDeadline,
    this.reminderIntervalHours,
    this.temporaryRoomId,
    this.parentEventId,
    this.subEventSequence,
    this.rehearsals = const [],
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
          parsedExternalInvitees[k.toString()] = ExternalInvitee.fromJson(
            v,
            k.toString(),
          );
        }
      });
    }

    final Map<String, SubstituteAssignment> parsedSubstituteAssignments = {};
    final subAssignmentsRaw = json['substituteAssignments'];
    if (subAssignmentsRaw is Map) {
      subAssignmentsRaw.forEach((k, v) {
        if (v is Map) {
          parsedSubstituteAssignments[k.toString()] = SubstituteAssignment.fromJson(
            v,
            k.toString(),
          );
        }
      });
    }

    final List<EventRehearsal> parsedRehearsals = [];
    final rehearsalsRaw = json['rehearsals'];
    if (rehearsalsRaw is List) {
      for (final item in rehearsalsRaw) {
        if (item is Map) {
          parsedRehearsals.add(EventRehearsal.fromJson(item));
        }
      }
    } else if (rehearsalsRaw is Map) {
      rehearsalsRaw.forEach((k, v) {
        if (v is Map) {
          parsedRehearsals.add(EventRehearsal.fromJson(v, k.toString()));
        }
      });
    }

    return BandEvent(
      id: keyId,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'Event',
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
      sentReminder24h: json['sentReminder24h'] == true,
      sentReminder48h: json['sentReminder48h'] == true,
      sentReminder72h: json['sentReminder72h'] == true,
      sentReminder84h: json['sentReminder84h'] == true,
      externalInvitees: parsedExternalInvitees,
      substituteAssignments: parsedSubstituteAssignments,
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
      rehearsals: parsedRehearsals,
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

    final Map<String, dynamic> subAssignmentsMap = {};
    substituteAssignments.forEach((k, v) {
      subAssignmentsMap[k] = v.toJson();
    });

    final List<Map<String, dynamic>> rehearsalsList =
        rehearsals.map((r) => r.toJson()).toList();

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
      'sentReminder24h': sentReminder24h,
      'sentReminder48h': sentReminder48h,
      'sentReminder72h': sentReminder72h,
      'sentReminder84h': sentReminder84h,
      'externalInvitees': externalInviteesMap,
      if (subAssignmentsMap.isNotEmpty) 'substituteAssignments': subAssignmentsMap,
      if (rehearsalsList.isNotEmpty) 'rehearsals': rehearsalsList,
      if (rsvpDeadline != null) 'rsvpDeadline': rsvpDeadline,
      if (reminderIntervalHours != null)
        'reminderIntervalHours': reminderIntervalHours,
      if (temporaryRoomId != null) 'temporaryRoomId': temporaryRoomId,
      if (parentEventId != null) 'parentEventId': parentEventId,
      if (subEventSequence != null) 'subEventSequence': subEventSequence,
    };
  }
}
