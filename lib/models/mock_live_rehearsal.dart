import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Prototype model representing a mock live band rehearsal broadcast source.
class MockLiveRehearsal {
  final String id;
  final String bandName;
  final String city;
  final LatLng position;
  final String audioAssetPath;
  final String genre;

  const MockLiveRehearsal({
    required this.id,
    required this.bandName,
    required this.city,
    required this.position,
    required this.audioAssetPath,
    this.genre = 'Rock / Indie',
  });
}
