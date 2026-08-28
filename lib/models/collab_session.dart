import 'band_event.dart' show EventResponse;

class CollabSession {
  /// Authoritative active choices for Session Category in owner-approved order.
  static const List<String> standardCategories = [
    'Songwriting',
    'Recording',
    'Production',
    'Jam',
    'Workshop',
    'Other',
  ];

  /// Authoritative choices for Session Type.
  static const List<String> standardTypes = [
    'In person',
    'Remote',
    'Hybrid',
  ];

  final String? id;
  final String title;
  final String description;
  final String sessionType; // 'In person', 'Remote', 'Hybrid'
  final String sessionCategory; // 'Songwriting', 'Recording', 'Production', 'Jam', 'Workshop', 'Other'
  final bool isDateFlexible;
  final String? startDateTime; // ISO 8601 string, nullable
  final String? endDateTime; // ISO 8601 string, nullable
  final String? location; // nullable for remote
  final List<String> genres;
  final List<String> lookingForRoles;
  final List<String> lookingForInstruments;
  final String creatorId;
  final int createdAt;
  final int updatedAt;
  final String status; // 'active', 'closed'

  // RSVP fields (SESSION-01)
  final bool requireResponse;
  final int? rsvpDeadline; // epoch millis
  final int? reminderIntervalHours; // e.g. 48, 24, 12, 0, or custom
  final Map<String, EventResponse> responses;

  // Multiple Sessions grouping (SESSION-01)
  final String? parentSessionId;
  final int? subSessionSequence;

  // Session Chat (SESSION-01)
  final String? sessionChatId;

  CollabSession({
    this.id,
    required this.title,
    required this.description,
    required this.sessionType,
    required this.sessionCategory,
    required this.isDateFlexible,
    this.startDateTime,
    this.endDateTime,
    this.location,
    this.genres = const [],
    this.lookingForRoles = const [],
    this.lookingForInstruments = const [],
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    this.status = 'active',
    this.requireResponse = true,
    this.rsvpDeadline,
    this.reminderIntervalHours,
    this.responses = const {},
    this.parentSessionId,
    this.subSessionSequence,
    this.sessionChatId,
  });

  factory CollabSession.fromJson(Map<dynamic, dynamic> json, String keyId) {
    final Map<String, EventResponse> parsedResponses = {};
    final responsesRaw = json['Responses'] ?? json['responses'];
    if (responsesRaw is Map) {
      responsesRaw.forEach((k, v) {
        if (v is Map) {
          parsedResponses[k.toString()] = EventResponse.fromJson(v);
        }
      });
    }

    return CollabSession(
      id: keyId,
      title: json['Title']?.toString() ?? json['title']?.toString() ?? '',
      description: json['Description']?.toString() ?? json['description']?.toString() ?? '',
      sessionType: json['SessionType']?.toString() ?? json['sessionType']?.toString() ?? 'Remote',
      sessionCategory: json['SessionCategory']?.toString() ?? json['sessionCategory']?.toString() ?? 'Other',
      isDateFlexible: (json['IsDateFlexible'] ?? json['isDateFlexible']) == true,
      startDateTime: json['StartDateTime']?.toString() ?? json['startDateTime']?.toString(),
      endDateTime: json['EndDateTime']?.toString() ?? json['endDateTime']?.toString(),
      location: json['Location']?.toString() ?? json['location']?.toString(),
      genres: _toList(json['Genres'] ?? json['genres']),
      lookingForRoles: _toList(json['LookingForRoles'] ?? json['lookingForRoles']),
      lookingForInstruments: _toList(json['LookingForInstruments'] ?? json['lookingForInstruments']),
      creatorId: json['CreatorId']?.toString() ?? json['creatorId']?.toString() ?? '',
      createdAt: json['CreatedAt'] is int
          ? json['CreatedAt'] as int
          : int.tryParse(json['CreatedAt']?.toString() ?? json['createdAt']?.toString() ?? '') ?? 0,
      updatedAt: json['UpdatedAt'] is int
          ? json['UpdatedAt'] as int
          : int.tryParse(json['UpdatedAt']?.toString() ?? json['updatedAt']?.toString() ?? '') ?? 0,
      status: json['Status']?.toString() ?? json['status']?.toString() ?? 'active',
      requireResponse: (json['RequireResponse'] ?? json['requireResponse']) != false,
      rsvpDeadline: json['RsvpDeadline'] is int
          ? json['RsvpDeadline'] as int
          : int.tryParse(json['RsvpDeadline']?.toString() ?? json['rsvpDeadline']?.toString() ?? ''),
      reminderIntervalHours: json['ReminderIntervalHours'] is int
          ? json['ReminderIntervalHours'] as int
          : int.tryParse(json['ReminderIntervalHours']?.toString() ?? json['reminderIntervalHours']?.toString() ?? ''),
      responses: parsedResponses,
      parentSessionId: json['ParentSessionId']?.toString() ?? json['parentSessionId']?.toString(),
      subSessionSequence: json['SubSessionSequence'] is int
          ? json['SubSessionSequence'] as int
          : int.tryParse(json['SubSessionSequence']?.toString() ?? json['subSessionSequence']?.toString() ?? ''),
      sessionChatId: json['SessionChatId']?.toString() ?? json['sessionChatId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> responsesMap = {};
    responses.forEach((k, v) {
      responsesMap[k] = v.toJson();
    });

    return {
      'Title': title,
      'Description': description,
      'SessionType': sessionType,
      'SessionCategory': sessionCategory,
      'IsDateFlexible': isDateFlexible,
      'StartDateTime': startDateTime,
      'Location': location,
      'Genres': genres,
      'LookingForRoles': lookingForRoles,
      'LookingForInstruments': lookingForInstruments,
      'CreatorId': creatorId,
      'CreatedAt': createdAt,
      'UpdatedAt': updatedAt,
      'Status': status,
      if (endDateTime != null) 'EndDateTime': endDateTime,
      'RequireResponse': requireResponse,
      if (rsvpDeadline != null) 'RsvpDeadline': rsvpDeadline,
      if (reminderIntervalHours != null) 'ReminderIntervalHours': reminderIntervalHours,
      if (responsesMap.isNotEmpty) 'Responses': responsesMap,
      if (parentSessionId != null) 'ParentSessionId': parentSessionId,
      if (subSessionSequence != null) 'SubSessionSequence': subSessionSequence,
      if (sessionChatId != null) 'SessionChatId': sessionChatId,
    };
  }

  static List<String> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map) return val.values.map((e) => e.toString()).toList();
    return [val.toString()];
  }
}

class CollabSessionApplication {
  final String userId;
  final String sessionId;
  final String creatorId;
  final int timestamp;
  final String status; // 'pending', 'accepted', 'declined'

  CollabSessionApplication({
    required this.userId,
    required this.sessionId,
    required this.creatorId,
    required this.timestamp,
    this.status = 'pending',
  });

  factory CollabSessionApplication.fromJson(Map<dynamic, dynamic> json, String userId) {
    return CollabSessionApplication(
      userId: userId,
      sessionId: json['SessionId']?.toString() ?? json['sessionId']?.toString() ?? '',
      creatorId: json['CreatorId']?.toString() ?? json['creatorId']?.toString() ?? '',
      timestamp: json['Timestamp'] is int
          ? json['Timestamp'] as int
          : int.tryParse(json['Timestamp']?.toString() ?? json['timestamp']?.toString() ?? '') ?? 0,
      status: json['Status']?.toString() ?? json['status']?.toString() ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'SessionId': sessionId,
      'CreatorId': creatorId,
      'Timestamp': timestamp,
      'Status': status,
    };
  }
}
