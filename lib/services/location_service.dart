import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String city;
  final String country;
  final String displayName;

  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.country,
    required this.displayName,
  });
}

class LocationService {
  Future<LocationResult> getCurrentLocationAsync() async {
    // 1. Verify location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    // 2. Check and request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    // 3. Retrieve coordinates
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    double latitude = position.latitude;
    double longitude = position.longitude;

    String city = "Unknown city";
    String country = "Unknown country";
    String displayName = "$latitude, $longitude";

    // 4. Reverse geocode if not on Web
    if (!kIsWeb) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          city = place.locality ?? place.subAdministrativeArea ?? "Unknown city";
          country = place.country ?? "Unknown country";
          displayName = "$city, $country";
        }
      } catch (e) {
        // Fallback remains active if reverse geocoding fails
      }
    }

    return LocationResult(
      latitude: latitude,
      longitude: longitude,
      city: city,
      country: country,
      displayName: displayName,
    );
  }
}
