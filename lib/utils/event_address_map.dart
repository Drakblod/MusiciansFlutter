/// A search link for a user-entered address, not a verified map position.
Uri? eventAddressMapUri(String address, {String city = ''}) {
  final streetAddress = address.trim();
  if (streetAddress.isEmpty) return null;

  // A full address is authoritative for this link. Use the separate City
  // field only for older or street-only entries, not to override the address.
  final locality = city.trim();
  final hasLocality =
      streetAddress.contains(',') ||
      (locality.isNotEmpty &&
          streetAddress.toLowerCase().endsWith(' ${locality.toLowerCase()}'));
  final query = locality.isEmpty || hasLocality
      ? streetAddress
      : '$streetAddress, $locality';
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}

/// Free-form Location can also contain a city, an online meeting link, or a
/// venue name. Only offer the address action for a street-like input here;
/// this is a UI hint, not geocoding or proof that an address exists.
Uri? eventLocationMapUri(String? location) {
  final value = location?.trim() ?? '';
  if (value.isEmpty ||
      RegExp(r'[\r\n]|://|\bwww\.|@', caseSensitive: false).hasMatch(value) ||
      !RegExp(r'\p{L}', unicode: true).hasMatch(value))
    return null;
  final streetPart = value.split(',').first.trim();
  if (RegExp(
    r"^\d{3}\s?\d{2}\s+[\p{L}\p{M}\s.'-]+$",
    unicode: true,
  ).hasMatch(streetPart))
    return null;
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(streetPart) ||
      !RegExp(
        r'(?:^|\s)\d{1,5}\p{L}?(?:\s|$)',
        unicode: true,
      ).hasMatch(streetPart))
    return null;
  return eventAddressMapUri(value);
}
