import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/geo_distance.dart';

void main() {
  group('Mock Rehearsal Audio Volume Curve Tests', () {
    test('Volume at or beyond 250 km should be 0.0', () {
      expect(calculateRehearsalVolume(250.0), equals(0.0));
      expect(calculateRehearsalVolume(300.0), equals(0.0));
      expect(calculateRehearsalVolume(1000.0), equals(0.0));
    });

    test('Volume just inside 250 km boundary should be approximately 0.10 (minimumAudibleVolume)', () {
      final volBoundary = calculateRehearsalVolume(249.9);
      expect(volBoundary, greaterThanOrEqualTo(0.10));
      expect(volBoundary, lessThan(0.12));
    });

    test('Volume should increase smoothly as distance decreases towards source', () {
      final volFar = calculateRehearsalVolume(200.0);
      final volMid = calculateRehearsalVolume(100.0);
      final volClose = calculateRehearsalVolume(10.0);
      final volZero = calculateRehearsalVolume(0.0);

      expect(volFar, lessThan(volMid));
      expect(volMid, lessThan(volClose));
      expect(volClose, lessThan(volZero));
      expect(volZero, closeTo(1.0, 0.01));
    });

    test('Secondary non-nearest band volume should be capped at 0.20', () {
      final volPrimaryAtSource = calculateRehearsalVolume(0.0, isNearest: true);
      final volSecondaryAtSource = calculateRehearsalVolume(0.0, isNearest: false);

      expect(volPrimaryAtSource, equals(1.0));
      expect(volSecondaryAtSource, equals(0.20));
    });
  });
}
