/// Precision level of the resolved coordinates.
enum LocationPrecision {
  /// Exact venue or street address (used for gigs/concerts/substitutes).
  exact,

  /// Approximate or city-level location (used for new member searches to protect privacy).
  city,
}

/// Geocoding resolution status for the request location.
enum LocationResolutionStatus {
  /// Coordinates have been successfully resolved and confirmed.
  resolved,

  /// Location has not yet been resolved or confirmed.
  unresolved,

  /// Resolution was attempted but failed (e.g. unknown address).
  failed,
}

/// Centralized canonical location contract for Map View and SubRequests.
///
/// Ensures consistent field names, coordinate bounds checking, and precision
/// while preventing fallbacks (like Stockholm or 0,0) and protecting private addresses.
class CanonicalLocation {
  final String locationLabel;
  final double? latitude;
  final double? longitude;
  final LocationPrecision precision;
  final String? placeId;
  final LocationResolutionStatus status;

  const CanonicalLocation({
    required this.locationLabel,
    this.latitude,
    this.longitude,
    this.precision = LocationPrecision.exact,
    this.placeId,
    this.status = LocationResolutionStatus.unresolved,
  });

  /// Factory for an unresolved location with a free-text label.
  factory CanonicalLocation.unresolved(String label) {
    return CanonicalLocation(
      locationLabel: label.trim(),
      latitude: null,
      longitude: null,
      precision: LocationPrecision.exact,
      placeId: null,
      status: LocationResolutionStatus.unresolved,
    );
  }

  /// Factory for a city-level resolved location.
  factory CanonicalLocation.city({
    required String cityName,
    required double latitude,
    required double longitude,
    String? placeId,
  }) {
    return CanonicalLocation(
      locationLabel: cityName.trim(),
      latitude: latitude,
      longitude: longitude,
      precision: LocationPrecision.city,
      placeId: placeId,
      status: LocationResolutionStatus.resolved,
    );
  }

  /// Factory for an exact venue/street resolved location.
  factory CanonicalLocation.exact({
    required String locationLabel,
    required double latitude,
    required double longitude,
    String? placeId,
  }) {
    return CanonicalLocation(
      locationLabel: locationLabel.trim(),
      latitude: latitude,
      longitude: longitude,
      precision: LocationPrecision.exact,
      placeId: placeId,
      status: LocationResolutionStatus.resolved,
    );
  }

  /// Validates whether coordinates exist, are finite, within standard geographic ranges,
  /// and not a default (0.0, 0.0) null-island coordinate.
  /// Whether both latitude and longitude are non-null.
  bool get hasCoordinates => latitude != null && longitude != null;

  bool get hasValidCoordinates {
    if (latitude == null || longitude == null) return false;
    if (!latitude!.isFinite || !longitude!.isFinite) return false;
    if (latitude! < -90.0 || latitude! > 90.0) return false;
    if (longitude! < -180.0 || longitude! > 180.0) return false;
    // Reject 0,0 (Null Island) as invalid invented fallback
    if (latitude == 0.0 && longitude == 0.0) return false;
    return true;
  }

  /// Normalizes legacy and variant JSON fields into a [CanonicalLocation].
  factory CanonicalLocation.fromJson(Map<dynamic, dynamic> json) {
    final label = (json['Location'] ??
            json['location'] ??
            json['Venue'] ??
            json['venue'] ??
            json['Address'] ??
            json['address'] ??
            '')
        .toString()
        .trim();

    final latRaw = json['Latitude'] ??
        json['latitude'] ??
        json['lat'] ??
        json['Lat'];
    final lngRaw = json['Longitude'] ??
        json['longitude'] ??
        json['lng'] ??
        json['Lng'] ??
        json['lon'] ??
        json['Lon'];

    double? lat;
    double? lng;
    if (latRaw is num) {
      lat = latRaw.toDouble();
    } else if (latRaw != null) {
      lat = double.tryParse(latRaw.toString());
    }
    if (lngRaw is num) {
      lng = lngRaw.toDouble();
    } else if (lngRaw != null) {
      lng = double.tryParse(lngRaw.toString());
    }

    // Precision normalization
    final precRaw = (json['LocationPrecision'] ??
            json['locationPrecision'] ??
            json['precision'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();
    final precision = precRaw == 'city'
        ? LocationPrecision.city
        : LocationPrecision.exact;

    final placeId = (json['PlaceId'] ?? json['placeId'])?.toString();

    // Check validity
    final candidate = CanonicalLocation(
      locationLabel: label,
      latitude: lat,
      longitude: lng,
      precision: precision,
      placeId: placeId,
      status: (lat != null && lng != null)
          ? LocationResolutionStatus.resolved
          : LocationResolutionStatus.unresolved,
    );

    if (candidate.hasValidCoordinates) {
      return candidate;
    }

    // Invalid or out-of-bounds coordinates return unresolved with null coords
    return CanonicalLocation(
      locationLabel: label,
      latitude: null,
      longitude: null,
      precision: precision,
      placeId: placeId,
      status: LocationResolutionStatus.unresolved,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Location': locationLabel,
      if (latitude != null) 'Latitude': latitude,
      if (longitude != null) 'Longitude': longitude,
      'LocationPrecision': precision.name,
      if (placeId != null && placeId!.isNotEmpty) 'PlaceId': placeId,
      'LocationStatus': status.name,
    };
  }

  CanonicalLocation copyWith({
    String? locationLabel,
    double? latitude,
    double? longitude,
    LocationPrecision? precision,
    String? placeId,
    LocationResolutionStatus? status,
  }) {
    return CanonicalLocation(
      locationLabel: locationLabel ?? this.locationLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      precision: precision ?? this.precision,
      placeId: placeId ?? this.placeId,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'CanonicalLocation(label: "$locationLabel", lat: $latitude, lng: $longitude, precision: ${precision.name}, status: ${status.name})';
  }
}
