import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/utils/rsvp_deadline_utils.dart';

void main() {
  group('EVT-06 RsvpDeadlineUtils & Deadline Resolution Tests', () {
    const pubTimeMs = 1787054400000; // e.g. 2026-08-18 12:00:00 UTC
    const msPerHour = 3600 * 1000;

    // Helper to construct BandEvent for testing
    BandEvent createTestEvent({
      required String startDateTime,
      int? createdAt = pubTimeMs,
      int? rsvpDeadline,
      int? reminderIntervalHours = 48,
      bool requireResponse = true,
      String? parentEventId,
      int? subEventSequence,
    }) {
      final safeCreatedAt = createdAt ?? 0;
      return BandEvent(
        title: 'Test Event',
        description: 'Testing RSVP deadline',
        eventType: 'Concert',
        location: 'Main Stage',
        startDateTime: startDateTime,
        endDateTime: '2026-09-01T22:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: safeCreatedAt,
        updatedAt: safeCreatedAt,
        requireResponse: requireResponse,
        rsvpDeadline: rsvpDeadline,
        reminderIntervalHours: reminderIntervalHours,
        parentEventId: parentEventId,
        subEventSequence: subEventSequence,
      );
    }

    // 1. New deadline calculation tests
    test('1. Publication plus 48 hours produces the correct deadline', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      final deadline = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
        event,
      );
      expect(deadline, equals(pubTimeMs + (48 * msPerHour)));
    });

    test('2. Publication plus 24 hours produces the correct deadline', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 24,
      );
      final deadline = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
        event,
      );
      expect(deadline, equals(pubTimeMs + (24 * msPerHour)));
    });

    test('3. Publication plus 12 hours produces the correct deadline', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 12,
      );
      final deadline = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
        event,
      );
      expect(deadline, equals(pubTimeMs + (12 * msPerHour)));
    });

    test('4. The scheduled event start date does not influence the result', () {
      final nearEvent = createTestEvent(
        startDateTime: '2026-08-19T12:00:00Z', // 1 day after pub
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      final farEvent = createTestEvent(
        startDateTime: '2026-10-18T12:00:00Z', // 2 months after pub
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );

      final nearDeadline = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
        nearEvent,
      );
      final farDeadline = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
        farEvent,
      );

      expect(nearDeadline, equals(farDeadline));
      expect(nearDeadline, equals(pubTimeMs + (48 * msPerHour)));
    });

    // 2. Remaining-time calculation tests
    test('5. A 48-hour window with exactly 12 hours elapsed returns 36', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      final now12h = pubTimeMs + (12 * msPerHour);
      final remaining = RsvpDeadlineUtils.calculateRemainingRsvpHours(
        event,
        nowMs: now12h,
      );
      expect(remaining, equals(36));
    });

    test('6. A 24-hour window with exactly 5 hours elapsed returns 19', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 24,
      );
      final now5h = pubTimeMs + (5 * msPerHour);
      final remaining = RsvpDeadlineUtils.calculateRemainingRsvpHours(
        event,
        nowMs: now5h,
      );
      expect(remaining, equals(19));
    });

    test('7. A small positive partial hour rounds upward', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      // 10 milliseconds elapsed after publication
      final nowJustAfterPub = pubTimeMs + 10;
      final remaining = RsvpDeadlineUtils.calculateRemainingRsvpHours(
        event,
        nowMs: nowJustAfterPub,
      );
      expect(remaining, equals(48));
    });

    test('8. Exactly at the deadline returns 0', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      final atDeadline = pubTimeMs + (48 * msPerHour);
      final remaining = RsvpDeadlineUtils.calculateRemainingRsvpHours(
        event,
        nowMs: atDeadline,
      );
      expect(remaining, equals(0));
    });

    test('9. After the deadline returns 0, never a negative number', () {
      final event = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: pubTimeMs,
        reminderIntervalHours: 48,
      );
      final afterDeadline = pubTimeMs + (50 * msPerHour);
      final remaining = RsvpDeadlineUtils.calculateRemainingRsvpHours(
        event,
        nowMs: afterDeadline,
      );
      expect(remaining, equals(0));
    });

    test('10. Missing deadline information returns null, not 1', () {
      final noResponseEvent = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        requireResponse: false,
      );
      final zeroIntervalEvent = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        reminderIntervalHours: 0,
      );
      final noMetadataEvent = createTestEvent(
        startDateTime: '2026-09-01T20:00:00Z',
        createdAt: 0,
        reminderIntervalHours: null,
        rsvpDeadline: null,
      );

      expect(
        RsvpDeadlineUtils.calculateRemainingRsvpHours(
          noResponseEvent,
          nowMs: pubTimeMs,
        ),
        isNull,
      );
      expect(
        RsvpDeadlineUtils.calculateRemainingRsvpHours(
          zeroIntervalEvent,
          nowMs: pubTimeMs,
        ),
        isNull,
      );
      expect(
        RsvpDeadlineUtils.calculateRemainingRsvpHours(
          noMetadataEvent,
          nowMs: pubTimeMs,
        ),
        isNull,
      );
    });

    // 3. Legacy compatibility tests
    test(
      '11. For an old event with valid createdAt, positive reminderIntervalHours, and an incorrect old rsvpDeadline, effective deadline is calculated from createdAt + reminderIntervalHours',
      () {
        const eventStartMs = 1787659200000; // e.g. Sept 1 (2 weeks after pub)
        const incorrectOldDeadline =
            eventStartMs - (48 * msPerHour); // start - 48h

        final legacyEvent = createTestEvent(
          startDateTime: '2026-09-01T20:00:00Z',
          createdAt: pubTimeMs,
          reminderIntervalHours: 48,
          rsvpDeadline: incorrectOldDeadline,
        );

        final effectiveDeadline =
            RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(legacyEvent);
        final expectedPublicationDeadline = pubTimeMs + (48 * msPerHour);

        expect(effectiveDeadline, equals(expectedPublicationDeadline));
        expect(effectiveDeadline, isNot(equals(incorrectOldDeadline)));
      },
    );

    test(
      '12. A valid persisted deadline can be used as a fallback when publication metadata is unavailable',
      () {
        const legacyPersistedDeadline = pubTimeMs + (24 * msPerHour);
        final legacyEventNoPubDate = createTestEvent(
          startDateTime: '2026-09-01T20:00:00Z',
          createdAt: 0,
          reminderIntervalHours: null,
          rsvpDeadline: legacyPersistedDeadline,
        );

        final effectiveDeadline =
            RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
              legacyEventNoPubDate,
            );
        expect(effectiveDeadline, equals(legacyPersistedDeadline));
      },
    );

    test(
      '13. A zero reminder interval does not produce a 24-hour fallback deadline',
      () {
        final zeroIntervalEvent = createTestEvent(
          startDateTime: '2026-09-01T20:00:00Z',
          createdAt: pubTimeMs,
          reminderIntervalHours: 0,
          rsvpDeadline:
              pubTimeMs + (24 * msPerHour), // old fallback stored in DB
        );

        final effectiveDeadline =
            RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
              zeroIntervalEvent,
            );
        expect(effectiveDeadline, isNull);
      },
    );

    // 4. Tour consistency test
    test(
      '14. Events created in one Tour/batch use the same captured createdAt and rsvpDeadline',
      () {
        final publishedAt = pubTimeMs;
        final sharedRsvpDeadline = publishedAt + (48 * msPerHour);

        final tourSub1 = createTestEvent(
          startDateTime: '2026-08-20T18:00:00Z',
          createdAt: publishedAt,
          rsvpDeadline: sharedRsvpDeadline,
          reminderIntervalHours: 48,
          parentEventId: 'group_1787054400000',
          subEventSequence: 1,
        );

        final tourSub2 = createTestEvent(
          startDateTime: '2026-08-22T20:00:00Z',
          createdAt: publishedAt,
          rsvpDeadline: sharedRsvpDeadline,
          reminderIntervalHours: 48,
          parentEventId: 'group_1787054400000',
          subEventSequence: 2,
        );

        expect(tourSub1.createdAt, equals(tourSub2.createdAt));
        expect(tourSub1.createdAt, equals(publishedAt));

        final deadline1 = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
          tourSub1,
        );
        final deadline2 = RsvpDeadlineUtils.calculateEffectiveRsvpDeadlineMs(
          tourSub2,
        );

        expect(deadline1, equals(deadline2));
        expect(deadline1, equals(publishedAt + (48 * msPerHour)));
      },
    );
  });
}
