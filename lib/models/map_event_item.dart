import 'canonical_location.dart';
import 'sub_request.dart';

/// MAP-VIEW-FEED-02: Typed client model for server-owned Event map projections.
/// Source of truth: publicMapEventFeed/{mapItemId} and userMapEventFeed/{userId}/{mapItemId}.
class MapEventItem {
  final String mapItemId;
  final String eventId;
  final String? schedulePartId;
  final String source; // 'public_calendar' or 'private_band'
  final String? bandId;
  final String bandName;
  final String title;
  final String? schedulePartTitle;
  final String description;
  final String eventType;
  final String date;
  final String startTime;
  final String endTime;
  final String startDateTime;
  final String endDateTime;
  final String location;
  final String? city;
  final double? latitude;
  final double? longitude;
  final String locationPrecision;
  final String visibility; // 'public' or 'private'
  final String status;
  final String? creatorUserId;
  final int? createdAt;
  final int? updatedAt;

  const MapEventItem({
    required this.mapItemId,
    required this.eventId,
    this.schedulePartId,
    required this.source,
    this.bandId,
    this.bandName = '',
    required this.title,
    this.schedulePartTitle,
    this.description = '',
    this.eventType = 'Event',
    this.date = '',
    this.startTime = '',
    this.endTime = '',
    this.startDateTime = '',
    this.endDateTime = '',
    this.location = '',
    this.city,
    this.latitude,
    this.longitude,
    this.locationPrecision = 'exact',
    this.visibility = 'private',
    this.status = 'scheduled',
    this.creatorUserId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPublic => visibility == 'public' || source == 'public_calendar';
  bool get isPrivateBand => source == 'private_band';
  bool get isMultiPart => schedulePartId != null && schedulePartId!.isNotEmpty;

  factory MapEventItem.fromJson(Map<dynamic, dynamic> json, [String? keyId]) {
    double? parseCoord(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    int? parseInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val);
      return null;
    }

    final id = json['mapItemId']?.toString() ?? keyId ?? '';

    return MapEventItem(
      mapItemId: id,
      eventId: json['eventId']?.toString() ?? '',
      schedulePartId: json['schedulePartId']?.toString(),
      source: json['source']?.toString() ?? 'private_band',
      bandId: json['bandId']?.toString(),
      bandName: json['bandName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      schedulePartTitle: json['schedulePartTitle']?.toString(),
      description: json['description']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'Event',
      date: json['date']?.toString() ?? '',
      startTime: json['startTime']?.toString() ?? '',
      endTime: json['endTime']?.toString() ?? '',
      startDateTime: json['startDateTime']?.toString() ?? '',
      endDateTime: json['endDateTime']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      city: json['city']?.toString(),
      latitude: parseCoord(json['latitude'] ?? json['Latitude']),
      longitude: parseCoord(json['longitude'] ?? json['Longitude']),
      locationPrecision: json['locationPrecision']?.toString() ?? 'exact',
      visibility: json['visibility']?.toString() ?? 'private',
      status: json['status']?.toString() ?? 'scheduled',
      creatorUserId: json['creatorUserId']?.toString(),
      createdAt: parseInt(json['createdAt']),
      updatedAt: parseInt(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mapItemId': mapItemId,
      'eventId': eventId,
      if (schedulePartId != null) 'schedulePartId': schedulePartId,
      'source': source,
      if (bandId != null) 'bandId': bandId,
      'bandName': bandName,
      'title': title,
      if (schedulePartTitle != null) 'schedulePartTitle': schedulePartTitle,
      'description': description,
      'eventType': eventType,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'startDateTime': startDateTime,
      'endDateTime': endDateTime,
      'location': location,
      if (city != null) 'city': city,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'locationPrecision': locationPrecision,
      'visibility': visibility,
      'status': status,
      if (creatorUserId != null) 'creatorUserId': creatorUserId,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  /// Converts this projection to a [SubRequest] so existing map rendering,
  /// filtering taxonomy, and markers interact seamlessly without duplication.
  SubRequest toSubRequest() {
    final displayTitle = (schedulePartTitle != null && schedulePartTitle!.isNotEmpty)
        ? '$title: $schedulePartTitle'
        : title;

    final precisionEnum = (locationPrecision.toLowerCase() == 'city')
        ? LocationPrecision.city
        : LocationPrecision.exact;

    return SubRequest(
      id: mapItemId,
      subRequestId: mapItemId,
      eventId: eventId,
      eventTitle: displayTitle,
      bandId: bandId,
      bandName: bandName,
      description: description,
      role: eventType,
      requestType: eventType,
      date: date.isNotEmpty ? date : (startDateTime.isNotEmpty ? startDateTime.split('T')[0] : null),
      startTime: startTime.isNotEmpty ? startTime : null,
      endTime: endTime.isNotEmpty ? endTime : null,
      location: location,
      city: city,
      latitude: latitude,
      longitude: longitude,
      locationPrecision: precisionEnum,
      creatorUserId: creatorUserId,
      createdAt: createdAt,
      status: status,
      extraFields: {
        'mapItemId': mapItemId,
        'eventId': eventId,
        'schedulePartId': schedulePartId,
        'eventSource': source,
        'schedulePartTitle': schedulePartTitle,
        'isEventProjection': true,
        'visibility': visibility,
        'subCategory': 'Music',
        'eventType': eventType,
        'startDateTime': startDateTime,
        'endDateTime': endDateTime,
        'locationPrecision': locationPrecision,
        'status': status,
        'updatedAt': updatedAt,
        'isLive': true,
      },
    );
  }
}
