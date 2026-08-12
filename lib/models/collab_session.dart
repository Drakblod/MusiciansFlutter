class CollabSession {
  final String? id;
  final String title;
  final String description;
  final String sessionType; // 'In person', 'Remote', 'Hybrid'
  final String
  sessionCategory; // 'Songwriting', 'Recording', 'Production', 'Jam', 'Other'
  final bool isDateFlexible;
  final String? startDateTime; // ISO 8601 string, nullable
  final String? location; // nullable for remote
  final List<String> genres;
  final List<String> lookingForRoles;
  final List<String> lookingForInstruments;
  final String creatorId;
  final int createdAt;
  final int updatedAt;
  final String status; // 'active', 'closed'

  CollabSession({
    this.id,
    required this.title,
    required this.description,
    required this.sessionType,
    required this.sessionCategory,
    required this.isDateFlexible,
    this.startDateTime,
    this.location,
    this.genres = const [],
    this.lookingForRoles = const [],
    this.lookingForInstruments = const [],
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    this.status = 'active',
  });

  factory CollabSession.fromJson(Map<dynamic, dynamic> json, String keyId) {
    return CollabSession(
      id: keyId,
      title: json['Title']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      sessionType: json['SessionType']?.toString() ?? 'Remote',
      sessionCategory: json['SessionCategory']?.toString() ?? 'Other',
      isDateFlexible: json['IsDateFlexible'] == true,
      startDateTime: json['StartDateTime']?.toString(),
      location: json['Location']?.toString(),
      genres: _toList(json['Genres']),
      lookingForRoles: _toList(json['LookingForRoles']),
      lookingForInstruments: _toList(json['LookingForInstruments']),
      creatorId: json['CreatorId']?.toString() ?? '',
      createdAt: json['CreatedAt'] is int ? json['CreatedAt'] as int : 0,
      updatedAt: json['UpdatedAt'] is int ? json['UpdatedAt'] as int : 0,
      status: json['Status']?.toString() ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
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

  factory CollabSessionApplication.fromJson(
    Map<dynamic, dynamic> json,
    String userId,
  ) {
    return CollabSessionApplication(
      userId: userId,
      sessionId: json['SessionId']?.toString() ?? '',
      creatorId: json['CreatorId']?.toString() ?? '',
      timestamp: json['Timestamp'] is int ? json['Timestamp'] as int : 0,
      status: json['Status']?.toString() ?? 'pending',
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
