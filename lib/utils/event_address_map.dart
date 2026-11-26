/// A search link for a user-entered address, not a verified map position.
Uri? eventAddressMapUri(String address, {String city = ''}) {
  final streetAddress = address.trim();
  if (streetAddress.isEmpty) return null;

  // A full address is authoritative for this link. Use the separate City
  // field only for older or street-only entries, not to override the address.
  final locality = city.trim();
  final hasLocality = streetAddress.contains(',') ||
      (locality.isNotEmpty && streetAddress.toLowerCase().endsWith(' ${locality.toLowerCase()}'));
  final query = locality.isEmpty || hasLocality
      ? streetAddress
      : '$streetAddress, $locality';
  return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query});
}
