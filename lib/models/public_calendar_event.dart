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
  });

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
