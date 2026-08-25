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
        return 'Open Session';
      case PublicEventType.workshopCourse:
        return 'Workshop/Course';
      case PublicEventType.other:
        return 'Other';
    }
  }

  /// Filter category name corresponding to the 4 main filter tabs
  String get typeFilterCategory {
    switch (eventType) {
      case PublicEventType.liveGig:
        return 'Live/Gigs';
      case PublicEventType.openSession:
        return 'Open Sessions';
      case PublicEventType.workshopCourse:
        return 'Workshops';
      case PublicEventType.other:
        return 'Other';
    }
  }
}
