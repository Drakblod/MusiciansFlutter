import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/map_event_activity_helper.dart';
import 'package:musicians_flutter/views/gig_map_page.dart' show MapEventType;
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/data/mock_live_rehearsals.dart';

void main() {
  group('MapEventActivityHelper - Canonical Activity Calculation', () {

    test('1. Exact boundary rule: start <= now < end', () {
      final start = DateTime(2026, 10, 23, 19, 0);
      final end = DateTime(2026, 10, 23, 21, 0);

      // now < start -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 23, 18, 59, 59),
        ),
        isFalse,
      );

      // now == start -> ACTIVE (inclusive start)
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 23, 19, 0, 0),
        ),
        isTrue,
      );

      // start < now < end -> ACTIVE
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 23, 20, 0, 0),
        ),
        isTrue,
      );

      // now == end -> INACTIVE (strictly < end)
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 23, 21, 0, 0),
        ),
        isFalse,
      );

      // now > end -> INACTIVE
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 10, 23, 21, 0, 1),
        ),
        isFalse,
      );
    });

    test('2. Midnight-crossing event: 22:00 to 02:00', () {
      final date = '2026-10-23';
      final startTime = '22:00';
      final endTime = '02:00';

      // 21:30 (before start) -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 23, 21, 30),
        ),
        isFalse,
      );

      // 22:00 (exact start) -> active
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 23, 22, 0),
        ),
        isTrue,
      );

      // 23:45 (same day) -> active
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 23, 23, 45),
        ),
        isTrue,
      );

      // 01:30 (next calendar day) -> active
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 24, 1, 30),
        ),
        isTrue,
      );

      // 02:00 (exact end on next day) -> inactive (strictly < end)
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 24, 2, 0),
        ),
        isFalse,
      );

      // 03:00 (after end) -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: date,
          startTime: startTime,
          endTime: endTime,
          now: DateTime(2026, 10, 24, 3, 0),
        ),
        isFalse,
      );
    });

    test('3. Missing end time resolves strictly to false (never infer or invent duration)', () {
      final date = '2026-10-23';
      final startTime = '18:00';

      // Start time present but missing end time -> MUST be false
      expect(
        isMapItemActive(
          type: MapEventType.rehearsal,
          date: date,
          startTime: startTime,
          now: DateTime(2026, 10, 23, 18, 0),
        ),
        isFalse,
      );

      expect(
        isMapItemActive(
          type: MapEventType.rehearsal,
          date: date,
          startTime: startTime,
          now: DateTime(2026, 10, 23, 19, 0),
        ),
        isFalse,
      );

      // startDateTime without endDateTime -> MUST be false
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: DateTime(2026, 10, 23, 18, 0),
          now: DateTime(2026, 10, 23, 18, 30),
        ),
        isFalse,
      );
    });

    test('4. Date and time string formats (12-hour AM/PM, dots, colons, range)', () {
      // 12-hour PM: "6:00 PM"
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: '2026-10-23',
          startTime: '6:00 PM',
          endTime: '9:00 PM',
          now: DateTime(2026, 10, 23, 18, 30),
        ),
        isTrue,
      );

      // Dot notation: "18.00" - "21.00"
      expect(
        isMapItemActive(
          type: MapEventType.rehearsal,
          date: '2026-10-23',
          startTime: '18.00',
          endTime: '21.00',
          now: DateTime(2026, 10, 23, 20, 0),
        ),
        isTrue,
      );

      // Time range: "18:00 - 21:00"
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          date: '2026-10-23',
          timeRange: '18:00 - 21:00',
          now: DateTime(2026, 10, 23, 19, 0),
        ),
        isTrue,
      );
    });

    test('5. Missing, empty, or malformed fields safely return false without throwing', () {
      // Missing date
      expect(isMapItemActive(type: MapEventType.gigConcert, startTime: '18:00'), isFalse);

      // Missing start time when date has no time
      expect(isMapItemActive(type: MapEventType.gigConcert, date: '2026-10-23'), isFalse);

      // Empty strings
      expect(isMapItemActive(type: MapEventType.gigConcert, date: '', startTime: ''), isFalse);

      // Malformed date/time
      expect(isMapItemActive(type: MapEventType.gigConcert, date: 'invalid-date', startTime: 'invalid-time'), isFalse);
    });

    test('6. Non-eligible types ALWAYS return false', () {
      final now = DateTime(2026, 10, 23, 19, 0);
      final start = DateTime(2026, 10, 23, 18, 0);
      final end = DateTime(2026, 10, 23, 21, 0);

      const nonEligibleTypes = [
        MapEventType.jamSession,
        MapEventType.recordedMusic,
        MapEventType.gigPromo,
        MapEventType.newMember,
        MapEventType.subs,
        MapEventType.paid,
      ];

      for (final type in nonEligibleTypes) {
        expect(
          isMapItemActive(
            type: type,
            startDateTime: start,
            endDateTime: end,
            now: now,
          ),
          isFalse,
          reason: '$type must never be active',
        );
      }
    });

    test('7. SubRequest evaluation via isSubRequestActive', () {
      final activeGig = SubRequest(
        id: 'gig_active_1',
        extraFields: {
          'eventType': 'gigConcert',
          'startDateTime': '2026-10-23T18:00:00Z',
          'endDateTime': '2026-10-23T22:00:00Z',
        },
      );
      expect(
        isSubRequestActive(activeGig, now: DateTime.parse('2026-10-23T19:00:00Z')),
        isTrue,
      );
      expect(
        isSubRequestActive(activeGig, now: DateTime.parse('2026-10-23T23:00:00Z')),
        isFalse,
      );

      final nonEligibleSub = SubRequest(
        id: 'sub_1',
        requestType: 'Substitute',
        extraFields: {'eventType': 'subs'},
        date: '2026-10-23',
        startTime: '18:00',
        endTime: '22:00',
      );
      expect(
        isSubRequestActive(nonEligibleSub, now: DateTime(2026, 10, 23, 19, 0)),
        isFalse,
      );
    });

    test('8. MockLiveRehearsal data active vs inactive status', () {
      final list = mockLiveRehearsals;
      final stockholm = list.firstWhere((r) => r.id == 'live_rehearsal_stockholm');
      final umea = list.firstWhere((r) => r.id == 'live_rehearsal_umea');
      final gothenburg = list.firstWhere((r) => r.id == 'live_rehearsal_gothenburg');
      final la = list.firstWhere((r) => r.id == 'live_rehearsal_la');

      final now = DateTime.now();

      // Stockholm has fixed historical dates (Oct 23, 2026, 18:00 - 21:00)
      expect(isMockLiveRehearsalActive(stockholm, now: DateTime(2026, 10, 23, 19, 0)), isTrue);
      expect(isMockLiveRehearsalActive(stockholm, now: DateTime(2026, 10, 24, 12, 0)), isFalse);
      final activeFixture = createActiveMockLiveRehearsalFixture(now: now);
      expect(isMockLiveRehearsalActive(activeFixture, now: now), isTrue);

      // Umeå is future (+1 day) -> INACTIVE
      expect(isMockLiveRehearsalActive(umea, now: now), isFalse);

      // Gothenburg is future (+2 days) -> INACTIVE
      expect(isMockLiveRehearsalActive(gothenburg, now: now), isFalse);

      // LA is past (-2 days) -> INACTIVE
      expect(isMockLiveRehearsalActive(la, now: now), isFalse);
    });
  });

  group('SubRequest Canonical Target ID Resolution', () {
    test('1. Resolves id when id is present', () {
      final gig = SubRequest(id: 'gig_id_123', subRequestId: 'sub_456');
      expect(gig.canonicalTargetId, 'gig_id_123');
    });

    test('2. Resolves subRequestId when id is absent (legacy fallback)', () {
      final gig = SubRequest(id: null, subRequestId: 'legacy_sub_789');
      expect(gig.canonicalTargetId, 'legacy_sub_789');
    });

    test('3. Pin with neither id nor subRequestId returns null and cannot become an audio target', () {
      final gig = SubRequest(id: null, subRequestId: null, latitude: 59.3, longitude: 18.0);
      expect(gig.canonicalTargetId, isNull);
    });

    test('4. Pin with empty string IDs returns null', () {
      final gig = SubRequest(id: '   ', subRequestId: '', latitude: 59.3, longitude: 18.0);
      expect(gig.canonicalTargetId, isNull);
    });
  });
}
