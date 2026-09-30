enum PublicEventType {
  liveGig,
  openSession,
  workshopCourse,
  other,
}

enum PublicEventStatus {
  published,
  cancelled,
}

class PublicCalendarEvent {
  final String id;
  final String title;
  final String shortDescription;
  final String description;
  final PublicEventType eventType;
  final String organizerName;
  final String venueName;
  final String city;
  final String address;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final List<String> genres;
  final double? priceAmount;
  final String currency;
  final bool isFree;
  final PublicEventStatus status;
  final bool isMock;
  final String? imageUrl;
  final String? createdBy;
  final int? createdAt;

  const PublicCalendarEvent({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.description,
    required this.eventType,
    required this.organizerName,
    required this.venueName,
    required this.city,
    required this.address,
    required this.startDateTime,
    required this.endDateTime,
    this.genres = const [],
    this.priceAmount,
    this.currency = 'SEK',
    this.isFree = false,
    this.status = PublicEventStatus.published,
    this.isMock = true,
    this.imageUrl,
    this.createdBy,
    this.createdAt,
  });

  factory PublicCalendarEvent.fromJson(Map<dynamic, dynamic> json, [String? id]) {
    PublicEventType parseType(String? val) {
      final s = (val ?? '').toLowerCase().trim();
      if (s == 'livegig' || s == 'live/gig' || s == 'live' || s == 'gig' || s == 'live_gig') {
        return PublicEventType.liveGig;
      }
      if (s == 'opensession' || s == 'session' || s == 'open_session') {
        return PublicEventType.openSession;
      }
      if (s == 'workshopcourse' || s == 'workshop' || s == 'course' || s == 'workshop_course') {
        return PublicEventType.workshopCourse;
      }
      return PublicEventType.other;
    }

    PublicEventStatus parseStatus(String? val) {
      final s = (val ?? '').toLowerCase().trim();
      if (s == 'cancelled' || s == 'canceled') {
        return PublicEventStatus.cancelled;
      }
      return PublicEventStatus.published;
    }

    List<String> parseGenres(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is Map) return raw.values.map((e) => e.toString()).toList();
      return [raw.toString()];
    }

    DateTime parseDate(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    return PublicCalendarEvent(
      id: json['id']?.toString() ?? id ?? '',
      title: json['title']?.toString() ?? '',
      shortDescription: json['shortDescription']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      eventType: parseType(json['eventType']?.toString()),
      organizerName: json['organizerName']?.toString() ?? '',
      venueName: json['venueName']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      startDateTime: parseDate(json['startDateTime']),
      endDateTime: parseDate(json['endDateTime']),
      genres: parseGenres(json['genres']),
      priceAmount: json['priceAmount'] is num
          ? (json['priceAmount'] as num).toDouble()
          : double.tryParse(json['priceAmount']?.toString() ?? ''),
      currency: json['currency']?.toString() ?? 'SEK',
      isFree: json['isFree'] == true,
      status: parseStatus(json['status']?.toString()),
      isMock: json['isMock'] == true,
      imageUrl: json['imageUrl']?.toString(),
      createdBy: json['createdBy']?.toString(),
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : int.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'shortDescription': shortDescription,
      'description': description,
      'eventType': eventType.name,
      'organizerName': organizerName,
      'venueName': venueName,
      'city': city,
      'address': address,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'genres': genres,
      if (priceAmount != null) 'priceAmount': priceAmount,
      'currency': currency,
      'isFree': isFree,
      'status': status.name,
      'isMock': isMock,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  PublicCalendarEvent copyWith({
    String? id,
    String? title,
    String? shortDescription,
    String? description,
    PublicEventType? eventType,
    String? organizerName,
    String? venueName,
    String? city,
    String? address,
    DateTime? startDateTime,
    DateTime? endDateTime,
    List<String>? genres,
    double? priceAmount,
    String? currency,
    bool? isFree,
    PublicEventStatus? status,
    bool? isMock,
    String? imageUrl,
    String? createdBy,
    int? createdAt,
  }) {
    return PublicCalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      shortDescription: shortDescription ?? this.shortDescription,
      description: description ?? this.description,
      eventType: eventType ?? this.eventType,
      organizerName: organizerName ?? this.organizerName,
      venueName: venueName ?? this.venueName,
      city: city ?? this.city,
      address: address ?? this.address,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      genres: genres ?? this.genres,
      priceAmount: priceAmount ?? this.priceAmount,
      currency: currency ?? this.currency,
      isFree: isFree ?? this.isFree,
      status: status ?? this.status,
      isMock: isMock ?? this.isMock,
      imageUrl: imageUrl ?? this.imageUrl,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Human-readable formatted price label (e.g. 'Free', '150 SEK', '295 SEK')
  String get formattedPrice {
    if (isFree || (priceAmount == null && isFree)) {
      return 'Free';
    }
    if (priceAmount != null) {
      if (priceAmount == priceAmount!.roundToDouble()) {
        return '${priceAmount!.toInt()} $currency';
      }
      return '${priceAmount!.toStringAsFixed(2)} $currency';
    }
    return 'Free';
  }

  /// Display badge label for event type
  String get eventTypeDisplayLabel {
    switch (eventType) {
      case PublicEventType.liveGig:
        return 'Live/Gig';
      case PublicEventType.openSession:
        return 'Session';
      case PublicEventType.workshopCourse:
        return 'Workshop/Course';
      case PublicEventType.other:
        return 'Other';
    }
  }

  /// Filter category name corresponding to the main filter options
  String get typeFilterCategory {
    switch (eventType) {
      case PublicEventType.liveGig:
        return EventCalendarCategories.liveGigs;
      case PublicEventType.openSession:
        return EventCalendarCategories.sessions;
      case PublicEventType.workshopCourse:
        return EventCalendarCategories.workshops;
      case PublicEventType.other:
        return 'Other';
    }
  }
}

/// Centralized category taxonomy and matching rules for the public event calendar.
class EventCalendarCategories {
  static const String all = 'All';
  static const String liveGigs = 'Live/Gigs';
  static const String sessions = 'Sessions';
  static const String workshops = 'Workshops';

  /// The visible category filter options (excluding 'All')
  static const List<String> categories = [
    liveGigs,
    sessions,
    workshops,
  ];

  /// All category filter options including 'All'
  static const List<String> allOptions = [
    all,
    liveGigs,
    sessions,
    workshops,
  ];

  /// Checks if an event matches a given category string, supporting existing aliases
  static bool matches(PublicCalendarEvent event, String category) {
    if (category == all || category.isEmpty || category == 'All Events') return true;
    final c = category.toLowerCase().trim();
    if (c == 'live/gigs' || c == 'live' || c == 'gig' || c == 'live/gig') {
      return event.eventType == PublicEventType.liveGig;
    }
    if (c == 'sessions' || c == 'session' || c == 'open sessions' || c == 'open session') {
      return event.eventType == PublicEventType.openSession;
    }
    if (c == 'workshops' ||
        c == 'workshop' ||
        c == 'courses' ||
        c == 'course' ||
        c == 'workshop/course') {
      return event.eventType == PublicEventType.workshopCourse;
    }
    return event.typeFilterCategory.toLowerCase() == c;
  }
}

/// Artwork helper providing demo image asset paths and fallbacks.
class EventCalendarArtwork {
  static const String liveGigDemoAsset = 'assets/event_calendar/live_gig_demo.png';
  static const String sessionWorkshopDemoAsset =
      'assets/event_calendar/session_workshop_demo.png';

  /// Resolves image source (network URL or bundled generic category artwork) in priority order:
  /// 1. Real supported image URL (`imageUrl`) if present and non-empty.
  /// 2. Bundled generic category artwork based on `eventType`.
  /// 3. null (clean compact non-image card) when no suitable real or category image exists
  ///    or when category fallback is disabled.
  static String? resolveArtwork(
    PublicCalendarEvent event, {
    bool enableCategoryFallback = true,
  }) {
    if (event.imageUrl != null && event.imageUrl!.trim().isNotEmpty) {
      return event.imageUrl!.trim();
    }
    if (!enableCategoryFallback) {
      return null;
    }
    switch (event.eventType) {
      case PublicEventType.liveGig:
        return liveGigDemoAsset;
      case PublicEventType.openSession:
      case PublicEventType.workshopCourse:
        return sessionWorkshopDemoAsset;
      case PublicEventType.other:
        return null;
    }
  }

  /// Backward-compatible alias for resolving artwork.
  static String? getDemoAsset(
    PublicCalendarEvent event, {
    bool enableCategoryFallback = true,
  }) {
    return resolveArtwork(event, enableCategoryFallback: enableCategoryFallback);
  }
}
