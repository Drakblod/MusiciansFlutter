import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const double audibleRadiusKm = 250.0;
const double minimumAudibleVolume = 0.10;
const double maximumVolume = 1.0;
const double secondaryAudibleCap = 0.20;

/// Calculates the geographical distance between two LatLng points in kilometers
/// using the Haversine formula.
double calculateHaversineDistanceKm(LatLng pos1, LatLng pos2) {
  const double earthRadiusKm = 6371.0;

  final double dLat = _degreesToRadians(pos2.latitude - pos1.latitude);
  final double dLon = _degreesToRadians(pos2.longitude - pos1.longitude);

  final double lat1Rad = _degreesToRadians(pos1.latitude);
  final double lat2Rad = _degreesToRadians(pos2.latitude);

  final double a =
      sin(dLat / 2) * sin(dLat / 2) +
      sin(dLon / 2) * sin(dLon / 2) * cos(lat1Rad) * cos(lat2Rad);

  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  final double distance = earthRadiusKm * c;
  return distance.isFinite && distance >= 0 ? distance : 0.0;
}

double _degreesToRadians(double degrees) {
  return degrees * (pi / 180.0);
}

/// Calculates the target audio volume (0.0 to 1.0) based on distance in kilometers.
/// If [isNearest] is false (secondary band in range), output is capped at 0.20.
double calculateRehearsalVolume(double distanceKm, {bool isNearest = true}) {
  if (distanceKm >= audibleRadiusKm || !distanceKm.isFinite) {
    return 0.0;
  }

  final double normalized = (1.0 - (distanceKm / audibleRadiusKm)).clamp(
    0.0,
    1.0,
  );
  final double eased = normalized * normalized;
  double volume =
      minimumAudibleVolume + eased * (maximumVolume - minimumAudibleVolume);

  volume = volume.clamp(0.0, maximumVolume);

  if (!isNearest) {
    volume = volume.clamp(0.0, secondaryAudibleCap);
  }

  return volume;
}
