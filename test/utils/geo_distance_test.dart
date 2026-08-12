import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musicians_flutter/utils/geo_distance.dart';

void main() {
  group('GeoDistance Haversine Calculation Tests', () {
    const stockholm = LatLng(59.3293, 18.0686);
    const umea = LatLng(63.8258, 20.2630);

    test('Distance between identical points should be 0 km', () {
      final distStockholm = calculateHaversineDistanceKm(stockholm, stockholm);
      final distUmea = calculateHaversineDistanceKm(umea, umea);

      expect(distStockholm, equals(0.0));
      expect(distUmea, equals(0.0));
    });

    test(
      'Distance between Stockholm and Umeå should be approximately 500-550 km',
      () {
        final distance = calculateHaversineDistanceKm(stockholm, umea);

        expect(distance, greaterThan(500.0));
        expect(distance, lessThan(600.0));
        expect(distance.isFinite, isTrue);
        expect(distance, greaterThanOrEqualTo(0.0));
      },
    );
  });
}
