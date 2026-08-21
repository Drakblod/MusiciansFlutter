import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/mock_live_rehearsal.dart';
import 'package:musicians_flutter/utils/map_crosshair_targeting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('MAP-02 MapCrosshairTargeting Production Utility Tests', () {
    const cameraLat = 59.3293;
    const cameraLng = 18.0686;
    const defaultZoom = 12.0;

    SubRequest createRequest({
      required String id,
      required double lat,
      required double lng,
    }) {
      return SubRequest(
        id: id,
        subRequestId: id,
        voicePart: 'Guitar',
        role: 'Guitarist',
        bandName: 'Test Band',
        location: 'Stockholm',
        date: '2026-09-01T20:00:00Z',
        startTime: '20:00:00',
        endTime: '22:00:00',
        description: 'Test description',
        isPaid: true,
        latitude: lat,
        longitude: lng,
        responses: {},
      );
    }

    MockLiveRehearsal createRehearsal({
      required String id,
      required double lat,
      required double lng,
    }) {
      return MockLiveRehearsal(
        id: id,
        bandName: 'Mock Band $id',
        city: 'Stockholm',
        position: LatLng(lat, lng),
        audioAssetPath: 'assets/audio/rehearsal.mp3',
        genre: 'Rock',
      );
    }

    test('1. A marker exactly at the camera target is selected', () {
      final candidates = [
        MapTargetCandidate.fromSubRequest(createRequest(id: 'req_center', lat: cameraLat, lng: cameraLng)),
      ];

      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: candidates,
      );

      expect(target, isNotNull);
      expect(target!.id, equals('req_center'));
      expect(target.kind, equals(MapTargetKind.subRequest));
    });

    test('2. A marker outside the crosshair radius is not selected', () {
      // 0.1 degrees latitude diff at lat 59 is ~11km away (far outside 32px radius at zoom 12)
      final candidates = [
        MapTargetCandidate.fromSubRequest(createRequest(id: 'far_req', lat: cameraLat + 0.1, lng: cameraLng)),
      ];

      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: candidates,
      );

      expect(target, isNull);
    });

    test('3. The nearest marker is selected when multiple markers are inside the radius', () {
      // Near candidate (~10 meters away) vs Far candidate (~100 meters away)
      final nearCandidate = MapTargetCandidate.fromSubRequest(
        createRequest(id: 'near_req', lat: cameraLat + 0.0001, lng: cameraLng),
      );
      final farCandidate = MapTargetCandidate.fromSubRequest(
        createRequest(id: 'far_req', lat: cameraLat + 0.0008, lng: cameraLng),
      );

      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: 15.0, // zoom 15 has hit radius ~300m
        candidates: [farCandidate, nearCandidate],
      );

      expect(target, isNotNull);
      expect(target!.id, equals('near_req'));
    });

    test('4. An exact-distance tie is resolved deterministically by candidate ID', () {
      // Two candidates at identical coordinates
      final candA = MapTargetCandidate.fromSubRequest(createRequest(id: 'alpha_req', lat: cameraLat, lng: cameraLng));
      final candB = MapTargetCandidate.fromSubRequest(createRequest(id: 'beta_req', lat: cameraLat, lng: cameraLng));

      final targetAB = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [candB, candA],
      );

      final targetBA = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [candA, candB],
      );

      expect(targetAB, isNotNull);
      expect(targetBA, isNotNull);
      expect(targetAB!.id, equals('alpha_req'));
      expect(targetBA!.id, equals('alpha_req'));
    });

    test('5. Increasing zoom reduces the geographic hit radius', () {
      final radiusZoom10 = MapCrosshairTargeting.hitRadiusMeters(latitude: cameraLat, zoom: 10.0);
      final radiusZoom15 = MapCrosshairTargeting.hitRadiusMeters(latitude: cameraLat, zoom: 15.0);

      expect(radiusZoom15, lessThan(radiusZoom10));
    });

    test('6. Decreasing zoom increases the geographic hit radius', () {
      final radiusZoom15 = MapCrosshairTargeting.hitRadiusMeters(latitude: cameraLat, zoom: 15.0);
      final radiusZoom5 = MapCrosshairTargeting.hitRadiusMeters(latitude: cameraLat, zoom: 5.0);

      expect(radiusZoom5, greaterThan(radiusZoom15));
    });

    test('7. Latitude is handled correctly by the meters-per-pixel calculation', () {
      // High latitude (Stockholm ~59°) has smaller cos(lat) than Equator (0°)
      final mppEquator = MapCrosshairTargeting.metersPerPixel(0.0, 10.0);
      final mppStockholm = MapCrosshairTargeting.metersPerPixel(59.3293, 10.0);

      expect(mppStockholm, lessThan(mppEquator));
      expect(mppEquator, greaterThan(0.0));
      expect(mppStockholm, greaterThan(0.0));
    });

    test('8. An empty candidate list returns no selection (null)', () {
      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [],
      );

      expect(target, isNull);
    });

    test('9. Candidates excluded by caller filtering cannot be selected', () {
      // Suppose filtered candidate list only has gig 'req_2' because 'req_1' was filtered out by caller
      final filteredCandidates = [
        MapTargetCandidate.fromSubRequest(createRequest(id: 'req_2', lat: cameraLat + 0.0005, lng: cameraLng)),
      ];

      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: 15.0,
        candidates: filteredCandidates,
      );

      expect(target, isNotNull);
      expect(target!.id, equals('req_2'));
    });

    test('10. Request and rehearsal candidates can both participate', () {
      final reqCand = MapTargetCandidate.fromSubRequest(
        createRequest(id: 'req_1', lat: cameraLat + 0.001, lng: cameraLng),
      );
      final rehCand = MapTargetCandidate.fromRehearsal(
        createRehearsal(id: 'reh_1', lat: cameraLat + 0.0001, lng: cameraLng),
      );

      final target = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: 15.0,
        candidates: [reqCand, rehCand],
      );

      expect(target, isNotNull);
      expect(target!.kind, equals(MapTargetKind.rehearsal));
      expect(target.id, equals('reh_1'));
    });

    test('11. Invalid/non-finite inputs are handled safely', () {
      final validCandidate = MapTargetCandidate.fromSubRequest(createRequest(id: 'valid', lat: cameraLat, lng: cameraLng));
      final nanCandidate = MapTargetCandidate.fromSubRequest(createRequest(id: 'nan', lat: double.nan, lng: cameraLng));

      expect(nanCandidate.isValid, isFalse);

      final targetNaNLat = MapCrosshairTargeting.findNearestTarget(
        cameraLat: double.nan,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [validCandidate],
      );

      expect(targetNaNLat, isNull);
    });

    test('12. Selection does not depend on candidate input order when distances tie', () {
      final cand1 = MapTargetCandidate.fromSubRequest(createRequest(id: 'spot_a', lat: cameraLat, lng: cameraLng));
      final cand2 = MapTargetCandidate.fromRehearsal(createRehearsal(id: 'spot_b', lat: cameraLat, lng: cameraLng));

      final target1 = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [cand1, cand2],
      );

      final target2 = MapCrosshairTargeting.findNearestTarget(
        cameraLat: cameraLat,
        cameraLng: cameraLng,
        zoom: defaultZoom,
        candidates: [cand2, cand1],
      );

      expect(target1, isNotNull);
      expect(target2, isNotNull);
      expect(target1!.id, equals(target2!.id));
    });
  });
}
