import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Prototype model representing a mock live band rehearsal broadcast source.
class MockLiveRehearsal {
  final String id;
  final String bandName;
  final String city;
  final LatLng position;
  final String audioAssetPath;
  final String genre;
  final String? location;
  final String? venue;
  final String? dateTime;
  final String? description;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final String? date;
  final String? startTime;
  final String? endTime;
  final bool isLiveBroadcast;

  const MockLiveRehearsal({
    required this.id,
    required this.bandName,
    required this.city,
    required this.position,
    required this.audioAssetPath,
    this.genre = 'Rock / Indie',
    this.location,
    this.venue,
    this.dateTime,
    this.description,
    this.startDateTime,
    this.endDateTime,
    this.date,
    this.startTime,
    this.endTime,
    this.isLiveBroadcast = false,
  });
}
