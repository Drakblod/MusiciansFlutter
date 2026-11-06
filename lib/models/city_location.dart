/// A confirmed, public city-level location. Provider IDs and coordinates are
/// deliberately absent from the persisted and projected contract.
class CityAttribution {
  final String provider;
  final Uri? providerUri;
  const CityAttribution(this.provider, this.providerUri);
}

class CityLocation {
  final String city;
  final String? region;
  final String country;
  final String? countryCode;
  /// Short-lived server grant. It is never included in canonical/public JSON.
  final String? confirmationNonce;
  /// Transient Google Place Details credit; deliberately omitted from JSON.
  final List<CityAttribution> attributions;

  const CityLocation._(this.city, this.region, this.country, this.countryCode,
      this.confirmationNonce, this.attributions);

  static String? _part(Object? value, {int max = 100}) {
    if (value is! String) return null;
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty ||
        clean.length > max ||
        clean.contains(',') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(clean)) {
      return null;
    }
    return clean;
  }

  static CityLocation? confirmed({
    required Object? city,
    Object? region,
    required Object? country,
    Object? countryCode,
    String? confirmationNonce,
    List<CityAttribution> attributions = const [],
  }) {
    final c = _part(city), nation = _part(country);
    if (c == null || nation == null) return null;
    final state = region == null ? null : _part(region);
    if (region != null && state == null) return null;
    String? code;
    if (countryCode != null) {
      if (countryCode is! String ||
          !RegExp(r'^[A-Za-z]{2}$').hasMatch(countryCode.trim())) {
        return null;
      }
      code = countryCode.trim().toUpperCase();
    }
    return CityLocation._(c, state, nation, code, confirmationNonce,
        List.unmodifiable(attributions));
  }

  static CityLocation? fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['precision'] != 'city' ||
        value['confirmed'] != true) {
      return null;
    }
    return confirmed(
      city: value['city'],
      region: value['region'],
      country: value['country'],
      countryCode: value['countryCode'],
    );
  }

  String get label =>
      region == null ? '$city, $country' : '$city, $region, $country';

  Map<String, Object> toJson() => {
    'version': 1,
    'precision': 'city',
    'confirmed': true,
    'city': city,
    if (region != null) 'region': region!,
    'country': country,
    if (countryCode != null) 'countryCode': countryCode!,
  };
}
