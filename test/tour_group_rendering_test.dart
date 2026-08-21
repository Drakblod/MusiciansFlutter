import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:musicians_flutter/models/band_event.dart';

// Helper mirror corresponding to _EventGroup in band_room_chat_screen.dart for presentation testing
class TestEventGroup {
  final BandEvent mainEvent;
  final List<BandEvent> subEvents;

  TestEventGroup({required this.mainEvent, required this.subEvents});

  bool get isGroup => subEvents.length > 1;

  DateTime get overallStart {
    DateTime earliest =
        DateTime.tryParse(mainEvent.startDateTime)?.toLocal() ?? DateTime.now();
    for (var e in subEvents) {
      final t = DateTime.tryParse(e.startDateTime)?.toLocal();
      if (t != null && t.isBefore(earliest)) earliest = t;
    }
    return earliest;
  }

  DateTime get overallEnd {
    DateTime latest =
        DateTime.tryParse(mainEvent.endDateTime)?.toLocal() ?? DateTime.now();
    for (var e in subEvents) {
      final t = DateTime.tryParse(e.endDateTime)?.toLocal();
      if (t != null && t.isAfter(latest)) latest = t;
    }
    return latest;
  }

  String formatGroupDateRange() {
    final startLocal = overallStart;
    final endLocal = overallEnd;
    final isSameDay =
        startLocal.year == endLocal.year &&
        startLocal.month == endLocal.month &&
        startLocal.day == endLocal.day;

    if (isSameDay) {
      return DateFormat('EEE, MMM d').format(startLocal);
    } else {
      return '${DateFormat('EEE, MMM d').format(startLocal)} – ${DateFormat('EEE, MMM d').format(endLocal)}';
    }
  }
}

void main() {
  group('EVT-12 & EVT-13 Tour Group Presentation Tests', () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    test(
      'Single-day tour group formats date range without duplicated date string',
      () {
        final sub1 = BandEvent(
          title: 'Tour test Aug 13 - Part 1',
          description: 'Part 1 show',
          eventType: 'Concert',
          location: 'Arena 1',
          startDateTime: '2026-08-13T14:00:00',
          endDateTime: '2026-08-13T16:00:00',
          additionalNotes: '',
          createdBy: 'user1',
          createdAt: nowMs,
          updatedAt: nowMs,
          requireResponse: true,
          parentEventId: 'group_123',
          subEventSequence: 1,
        );

        final sub2 = BandEvent(
          title: 'Tour test Aug 13 - Part 2',
          description: 'Part 2 show',
          eventType: 'Concert',
          location: 'Arena 1',
          startDateTime: '2026-08-13T18:00:00',
          endDateTime: '2026-08-13T20:00:00',
          additionalNotes: '',
          createdBy: 'user1',
          createdAt: nowMs,
          updatedAt: nowMs,
          requireResponse: true,
          parentEventId: 'group_123',
          subEventSequence: 2,
        );

        final group = TestEventGroup(mainEvent: sub1, subEvents: [sub1, sub2]);

        final formattedRange = group.formatGroupDateRange();
        final expectedSingleDate = DateFormat(
          'EEE, MMM d',
        ).format(group.overallStart);

        // The date range string must equal the single date string, and NOT contain "–" or duplicated date
        expect(formattedRange, equals(expectedSingleDate));
        expect(formattedRange.contains('–'), isFalse);

        // Individual sub-event dates and times remain available
        final sub1StartLocal = DateTime.parse(sub1.startDateTime).toLocal();
        final sub2StartLocal = DateTime.parse(sub2.startDateTime).toLocal();
        expect(
          DateFormat('EEE, MMM d • HH:mm').format(sub1StartLocal),
          contains('14:00'),
        );
        expect(
          DateFormat('EEE, MMM d • HH:mm').format(sub2StartLocal),
          contains('18:00'),
        );
      },
    );

    test(
      'Multi-day tour group preserves overall date range from start to end date',
      () {
        final sub1 = BandEvent(
          title: 'Summer Tour - Day 1',
          description: 'Day 1 show',
          eventType: 'Concert',
          location: 'City A',
          startDateTime: '2026-08-13T14:00:00',
          endDateTime: '2026-08-13T18:00:00',
          additionalNotes: '',
          createdBy: 'user1',
          createdAt: nowMs,
          updatedAt: nowMs,
          requireResponse: true,
          parentEventId: 'group_456',
          subEventSequence: 1,
        );

        final sub2 = BandEvent(
          title: 'Summer Tour - Day 3',
          description: 'Day 3 show',
          eventType: 'Concert',
          location: 'City B',
          startDateTime: '2026-08-15T18:00:00',
          endDateTime: '2026-08-15T21:00:00',
          additionalNotes: '',
          createdBy: 'user1',
          createdAt: nowMs,
          updatedAt: nowMs,
          requireResponse: true,
          parentEventId: 'group_456',
          subEventSequence: 2,
        );

        final group = TestEventGroup(mainEvent: sub1, subEvents: [sub1, sub2]);

        final formattedRange = group.formatGroupDateRange();
        final expectedStart = DateFormat(
          'EEE, MMM d',
        ).format(group.overallStart);
        final expectedEnd = DateFormat('EEE, MMM d').format(group.overallEnd);

        expect(formattedRange, equals('$expectedStart – $expectedEnd'));
        expect(formattedRange, contains('–'));
      },
    );

    test('Single event formatting works normally', () {
      final event = BandEvent(
        title: 'Regular Rehearsal',
        description: 'Practice',
        eventType: 'Rehearsal',
        location: 'Rehearsal Room',
        startDateTime: '2026-08-13T18:00:00',
        endDateTime: '2026-08-13T21:00:00',
        additionalNotes: '',
        createdBy: 'user1',
        createdAt: nowMs,
        updatedAt: nowMs,
        requireResponse: true,
      );

      final startLocal = DateTime.parse(event.startDateTime).toLocal();
      final endLocal = DateTime.parse(event.endDateTime).toLocal();

      final isSameDay =
          startLocal.year == endLocal.year &&
          startLocal.month == endLocal.month &&
          startLocal.day == endLocal.day;

      expect(isSameDay, isTrue);

      final formattedTime =
          '${DateFormat('EEE, MMM d').format(startLocal)} • ${DateFormat('HH:mm').format(startLocal)} - ${DateFormat('HH:mm').format(endLocal)}';
      expect(formattedTime, contains('18:00 - 21:00'));
    });
  });
}
