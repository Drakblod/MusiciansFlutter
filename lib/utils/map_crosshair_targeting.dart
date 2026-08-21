import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/sub_request.dart';
import '../models/mock_live_rehearsal.dart';
import 'geo_distance.dart';

/// Supported types of POI candidates for map crosshair targeting.
enum MapTargetKind { subRequest, rehearsal }

/// Immutable candidate object representing a map POI for crosshair targeting.
class MapTargetCandidate {
  final String id;
  final MapTargetKind kind;
  final double latitude;
  final double longitude;
  final SubRequest? subRequest;
  final MockLiveRehearsal? rehearsal;

  const MapTargetCandidate({
    required this.id,
    required this.kind,
    required this.latitude,
    required this.longitude,
    this.subRequest,
    this.rehearsal,
  });

  factory MapTargetCandidate.fromSubRequest(SubRequest req) {
    return MapTargetCandidate(
      id: req.id ?? req.subRequestId ?? '',
      kind: MapTargetKind.subRequest,
      latitude: req.latitude!,
      longitude: req.longitude!,
      subRequest: req,
    );
  }

  factory MapTargetCandidate.fromRehearsal(MockLiveRehearsal reh) {
    return MapTargetCandidate(
      id: reh.id,
      kind: MapTargetKind.rehearsal,
      latitude: reh.position.latitude,
      longitude: reh.position.longitude,
      rehearsal: reh,
    );
  }

  bool get isValid =>
      id.isNotEmpty &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0;
}

/// Pure Dart utility for zoom-aware POI acquisition under the map crosshair.
class MapCrosshairTargeting {
  /// Default crosshair hit-test radius in display pixels.
  static const double defaultHitRadiusPixels = 32.0;

  /// Calculates meters per pixel at a given [latitude] and [zoom] level
  /// using standard Web Mercator projection mathematics.
  ///
  /// Formula:
  /// `metersPerPixel = 156543.03392 * cos(latitudeInRadians) / (2 ^ zoom)`
  static double metersPerPixel(double latitude, double zoom) {
    if (!latitude.isFinite || !zoom.isFinite) return 0.0;
    final latRad = latitude * (math.pi / 180.0);
    final cosLat = math.cos(latRad).abs();
    return (156543.03392 * cosLat) / math.pow(2, zoom);
  }

  /// Calculates the geographic hit radius in meters for a crosshair of radius [hitRadiusPixels]
  /// at the target [latitude] and map [zoom].
  static double hitRadiusMeters({
    required double latitude,
    required double zoom,
    double hitRadiusPixels = defaultHitRadiusPixels,
  }) {
    final mpp = metersPerPixel(latitude, zoom);
    return mpp * hitRadiusPixels;
  }

  /// Finds the geographically nearest valid [MapTargetCandidate] to ([cameraLat], [cameraLng])
  /// within the calculated [hitRadiusMeters].
  ///
  /// Distance is computed using the Haversine formula via [calculateHaversineDistanceKm].
  ///
  /// Deterministic Tie-Breaking Rule:
  /// If two candidates have an identical distance (or differ by less than 1mm / 0.001 meters),
  /// the tie is broken by comparing candidate IDs lexicographically (`id.compareTo`).
  ///
  /// Returns null if no valid candidate falls within the hit radius or if input parameters are invalid.
  static MapTargetCandidate? findNearestTarget({
    required double cameraLat,
    required double cameraLng,
    required double zoom,
    required List<MapTargetCandidate> candidates,
    double hitRadiusPixels = defaultHitRadiusPixels,
  }) {
    if (!cameraLat.isFinite || !cameraLng.isFinite || !zoom.isFinite) {
      return null;
    }

    final maxDistanceMeters = hitRadiusMeters(
      latitude: cameraLat,
      zoom: zoom,
      hitRadiusPixels: hitRadiusPixels,
    );

    MapTargetCandidate? bestCandidate;
    double minDistance = double.infinity;

    for (final candidate in candidates) {
      if (!candidate.isValid) continue;

      final distKm = calculateHaversineDistanceKm(
        LatLng(cameraLat, cameraLng),
        LatLng(candidate.latitude, candidate.longitude),
      );
      final distMeters = distKm * 1000.0;

      if (distMeters > maxDistanceMeters) continue;

      if (bestCandidate == null) {
        bestCandidate = candidate;
        minDistance = distMeters;
      } else {
        final diff = distMeters - minDistance;
        if (diff < -0.001) {
          // Strictly closer candidate
          bestCandidate = candidate;
          minDistance = distMeters;
        } else if (diff.abs() <= 0.001) {
          // Near/exact distance tie (within 1mm): tie-break deterministically by ID
          if (candidate.id.compareTo(bestCandidate.id) < 0) {
            bestCandidate = candidate;
            minDistance = distMeters;
          }
        }
      }
    }

    return bestCandidate;
  }
}
