enum LiveBroadcastStatus {
  active,
  ended,
  paused;

  static LiveBroadcastStatus fromString(String? value) {
    switch ((value ?? '').toLowerCase().trim()) {
      case 'active':
      case 'live':
        return LiveBroadcastStatus.active;
      case 'paused':
        return LiveBroadcastStatus.paused;
      case 'ended':
      case 'stopped':
      case 'completed':
      default:
        return LiveBroadcastStatus.ended;
    }
  }

  String toDbValue() {
    switch (this) {
      case LiveBroadcastStatus.active:
        return 'active';
      case LiveBroadcastStatus.paused:
        return 'paused';
      case LiveBroadcastStatus.ended:
        return 'ended';
    }
  }
}

enum LiveBroadcastParticipantRole {
  publisher,
  listener;

  static LiveBroadcastParticipantRole fromString(String? value) {
    if ((value ?? '').toLowerCase().trim() == 'publisher') {
      return LiveBroadcastParticipantRole.publisher;
    }
    return LiveBroadcastParticipantRole.listener;
  }

  String toDbValue() => this == LiveBroadcastParticipantRole.publisher ? 'publisher' : 'listener';
}

/// Domain model representing an audio-only live broadcast session of a band.
class LiveBroadcast {
  final String id;
  final String bandId;
  final String bandName;
  final String creatorUserId;
  final String title;
  final String? description;
  final String? genre;
  final String? location;
  final double latitude;
  final double longitude;
  final LiveBroadcastStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String livekitRoomName;
  final int listenerCount;
  final bool audioOnly;
  final bool hasActiveAudioTrack;

  const LiveBroadcast({
    required this.id,
    required this.bandId,
    required this.bandName,
    required this.creatorUserId,
    required this.title,
    this.description,
    this.genre,
    this.location,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.livekitRoomName,
    this.listenerCount = 0,
    this.audioOnly = true,
    this.hasActiveAudioTrack = true,
  });

  bool get isActive => status == LiveBroadcastStatus.active;
  bool get isEnded => status == LiveBroadcastStatus.ended;
  bool get isPaused => status == LiveBroadcastStatus.paused;

  /// Determines whether the given user has authority to end/stop this broadcast.
  /// Broadcaster creator and band leaders/admins are allowed.
  bool canStop(String? userId, {bool isBandLeaderOrAdmin = false}) {
    if (userId == null) return false;
    return creatorUserId == userId || isBandLeaderOrAdmin;
  }

  factory LiveBroadcast.fromMap(String id, Map<dynamic, dynamic> map) {
    final statusStr = map['status']?.toString() ?? map['Status']?.toString();
    final startedAtRaw = map['startedAt'] ?? map['StartedAt'];
    final endedAtRaw = map['endedAt'] ?? map['EndedAt'];

    DateTime parsedStartedAt;
    if (startedAtRaw is int) {
      parsedStartedAt = DateTime.fromMillisecondsSinceEpoch(startedAtRaw);
    } else if (startedAtRaw is String) {
      parsedStartedAt = DateTime.tryParse(startedAtRaw) ?? DateTime.now();
    } else {
      parsedStartedAt = DateTime.now();
    }

    DateTime? parsedEndedAt;
    if (endedAtRaw is int) {
      parsedEndedAt = DateTime.fromMillisecondsSinceEpoch(endedAtRaw);
    } else if (endedAtRaw is String) {
      parsedEndedAt = DateTime.tryParse(endedAtRaw);
    }

    final double lat = (map['latitude'] as num?)?.toDouble() ??
        (map['Latitude'] as num?)?.toDouble() ??
        (map['lat'] as num?)?.toDouble() ??
        0.0;

    final double lng = (map['longitude'] as num?)?.toDouble() ??
        (map['Longitude'] as num?)?.toDouble() ??
        (map['lng'] as num?)?.toDouble() ??
        0.0;

    return LiveBroadcast(
      id: id,
      bandId: (map['bandId'] ?? map['BandId'] ?? '').toString(),
      bandName: (map['bandName'] ?? map['BandName'] ?? 'Live Band').toString(),
      creatorUserId: (map['creatorUserId'] ?? map['CreatorUserId'] ?? '').toString(),
      title: (map['title'] ?? map['Title'] ?? 'Live Broadcast').toString(),
      description: map['description']?.toString() ?? map['Description']?.toString(),
      genre: map['genre']?.toString() ?? map['Genre']?.toString(),
      location: map['location']?.toString() ?? map['Location']?.toString(),
      latitude: lat,
      longitude: lng,
      status: LiveBroadcastStatus.fromString(statusStr),
      startedAt: parsedStartedAt,
      endedAt: parsedEndedAt,
      livekitRoomName: (map['livekitRoomName'] ?? map['LivekitRoomName'] ?? 'room_$id').toString(),
      listenerCount: (map['listenerCount'] as num?)?.toInt() ?? (map['ListenerCount'] as num?)?.toInt() ?? 0,
      audioOnly: map['audioOnly'] == null ? true : map['audioOnly'] == true,
      hasActiveAudioTrack: map['hasActiveAudioTrack'] == null ? true : map['hasActiveAudioTrack'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bandId': bandId,
      'bandName': bandName,
      'creatorUserId': creatorUserId,
      'title': title,
      if (description != null) 'description': description,
      if (genre != null) 'genre': genre,
      if (location != null) 'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.toDbValue(),
      'startedAt': startedAt.millisecondsSinceEpoch,
      if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
      'livekitRoomName': livekitRoomName,
      'listenerCount': listenerCount,
      'audioOnly': audioOnly,
      'hasActiveAudioTrack': hasActiveAudioTrack,
    };
  }

  LiveBroadcast copyWith({
    String? id,
    String? bandId,
    String? bandName,
    String? creatorUserId,
    String? title,
    String? description,
    String? genre,
    String? location,
    double? latitude,
    double? longitude,
    LiveBroadcastStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    String? livekitRoomName,
    int? listenerCount,
    bool? audioOnly,
    bool? hasActiveAudioTrack,
  }) {
    return LiveBroadcast(
      id: id ?? this.id,
      bandId: bandId ?? this.bandId,
      bandName: bandName ?? this.bandName,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      title: title ?? this.title,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      livekitRoomName: livekitRoomName ?? this.livekitRoomName,
      listenerCount: listenerCount ?? this.listenerCount,
      audioOnly: audioOnly ?? this.audioOnly,
      hasActiveAudioTrack: hasActiveAudioTrack ?? this.hasActiveAudioTrack,
    );
  }
}
