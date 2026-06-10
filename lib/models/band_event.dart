class EventResponse {
  final String status; // 'attending', 'maybe', 'declined'
  final DateTime timestamp;

  EventResponse({
    required this.status,
    required this.timestamp,
  });

  factory EventResponse.fromJson(Map<dynamic, dynamic> json) {
    return EventResponse(
      status: json['status']?.toString() ?? 'declined',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp.toUtc().toIso8601String(),
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
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> responsesMap = {};
    responses.forEach((k, v) {
      responsesMap[k] = v.toJson();
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
    };
  }
}
