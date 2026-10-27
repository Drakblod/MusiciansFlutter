import '../models/canonical_location.dart';

/// Clean interface abstraction for coordinate validation and location resolution.
/// Eliminates mutable production test callbacks and enforces dependency injection.
abstract class LocationResolver {
  /// Validates whether given coordinates represent a genuine, finite geographic position,
  /// strictly rejecting null island (0.0, 0.0) and out-of-bounds values.
  bool isValidCoordinate(double? lat, double? lng);

  /// Obscures exact residential coordinates to city-level approximate coordinates (~1.1 km area)
  /// to protect privacy for New Member recruitment.
  CanonicalLocation toCityLevelLocation(CanonicalLocation location);

  /// Resolves a known city to its approximate centroid coordinates offline.
  CanonicalLocation? resolveKnownCity(String label);
}

/// Default offline location resolver.
/// Does not call external autocomplete endpoints.
class DefaultLocationResolver implements LocationResolver {
  const DefaultLocationResolver();

  // Curated Swedish city centroids for offline resolution
  static const Map<String, ({double lat, double lng, String name})> _swedishCities = {
    'stockholm': (lat: 59.3293, lng: 18.0686, name: 'Stockholm'),
    'göteborg': (lat: 57.7089, lng: 11.9746, name: 'Göteborg'),
    'gothenburg': (lat: 57.7089, lng: 11.9746, name: 'Göteborg'),
    'malmö': (lat: 55.6050, lng: 13.0038, name: 'Malmö'),
    'uppsala': (lat: 59.8586, lng: 17.6389, name: 'Uppsala'),
    'linköping': (lat: 58.4108, lng: 15.6214, name: 'Linköping'),
    'örebro': (lat: 59.2753, lng: 15.2134, name: 'Örebro'),
    'västerås': (lat: 59.6099, lng: 16.5448, name: 'Västerås'),
    'helsingborg': (lat: 56.0465, lng: 12.6945, name: 'Helsingborg'),
    'jönköping': (lat: 57.7826, lng: 14.1618, name: 'Jönköping'),
    'norrköping': (lat: 58.5877, lng: 16.1924, name: 'Norrköping'),
    'lund': (lat: 55.7047, lng: 13.1910, name: 'Lund'),
    'umeå': (lat: 63.8258, lng: 20.2630, name: 'Umeå'),
    'gävle': (lat: 60.6749, lng: 17.1417, name: 'Gävle'),
    'borås': (lat: 57.7210, lng: 12.9401, name: 'Borås'),
    'halmstad': (lat: 56.6745, lng: 12.8578, name: 'Halmstad'),
    'karlstad': (lat: 59.3793, lng: 13.5036, name: 'Karlstad'),
  };

  @override
  bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    return true;
  }

  @override
  CanonicalLocation toCityLevelLocation(CanonicalLocation location) {
    // 1. Prefer known Swedish city centroid if label matches
    final known = resolveKnownCity(location.locationLabel);
    if (known != null) {
      return known;
    }

    if (location.latitude == null || location.longitude == null) {
      final cityLabel = LocationService.extractCityLabel(location.locationLabel);
      return location.copyWith(
        precision: LocationPrecision.city,
        locationLabel: cityLabel.isNotEmpty ? cityLabel : location.locationLabel,
      );
    }

    // Coarsen to 1 decimal place (~11 km lat, ~6 km lng uncertainty) to guarantee residential privacy
    final approxLat = double.parse(location.latitude!.toStringAsFixed(1));
    final approxLng = double.parse(location.longitude!.toStringAsFixed(1));
    final cityLabel = LocationService.extractCityLabel(location.locationLabel);

    return CanonicalLocation.city(
      cityName: cityLabel.isNotEmpty ? cityLabel : (location.locationLabel.isNotEmpty ? location.locationLabel : 'Stockholm'),
      latitude: approxLat,
      longitude: approxLng,
      placeId: null, // exact placeId stripped
    );
  }

  @override
  CanonicalLocation? resolveKnownCity(String label) {
    final clean = label.trim().toLowerCase();
    if (clean.isEmpty) return null;

    for (final entry in _swedishCities.entries) {
      if (clean.contains(entry.key)) {
        return CanonicalLocation.city(
          cityName: entry.value.name,
          latitude: entry.value.lat,
          longitude: entry.value.lng,
        );
      }
    }
    return null;
  }
}

/// Centralized service for address lookup and coordinate validation.
/// Delegated to an injected [LocationResolver] without test hooks or external autocomplete.
class LocationService {
  static const LocationResolver defaultResolver = DefaultLocationResolver();

  /// Validates whether given coordinates represent a genuine, finite geographic position,
  /// strictly rejecting null island (0.0, 0.0) and out-of-bounds values.
  static bool isValidCoordinate(double? lat, double? lng, {LocationResolver? resolver}) {
    return (resolver ?? defaultResolver).isValidCoordinate(lat, lng);
  }

  /// Obscures exact coordinates to city-level approximate coordinates for New Member recruitment.
  static CanonicalLocation toCityLevelLocation(CanonicalLocation location, {LocationResolver? resolver}) {
    return (resolver ?? defaultResolver).toCityLevelLocation(location);
  }

  /// Resolves a known city centroid offline.
  static CanonicalLocation? resolveKnownCity(String label, {LocationResolver? resolver}) {
    return (resolver ?? defaultResolver).resolveKnownCity(label);
  }

  /// Extracts the city label from a full address string by stripping street numbers and street names.
  static String extractCityLabel(String rawLocation) {
    final str = rawLocation.trim();
    if (str.isEmpty) return '';

    if (str.contains(',')) {
      final parts = str.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      for (int i = parts.length - 1; i >= 0; i--) {
        final part = parts[i];
        if ((part.toLowerCase() == 'sweden' || part.toLowerCase() == 'sverige') && i > 0) {
          continue;
        }
        final cleaned = part.replaceAll(RegExp(r'^\d{3}\s?\d{2}\s+'), '').trim();
        if (cleaned.isNotEmpty && !RegExp(r'^\d+$').hasMatch(cleaned)) {
          return cleaned;
        }
      }
      return parts.last;
    }

    final noHouseNum = str.replaceAll(RegExp(r'^[A-Za-zåäöÅÄÖ\s\.\-]+\s+\d+[A-Za-z]?\s+'), '').trim();
    if (noHouseNum.isNotEmpty && !RegExp(r'^\d+$').hasMatch(noHouseNum)) {
      return noHouseNum;
    }

    return str;
  }
}
