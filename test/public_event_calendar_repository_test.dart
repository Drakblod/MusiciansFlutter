import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';

void main() {
  group('PublicEventRepository and Models', () {
    final fixedRef = DateTime(2026, 8, 25, 12, 0);

    test('1. Mock repository returns exactly three events', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      expect(events.length, 3);
    });

    test('2. All mock event IDs are unique', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      final ids = events.map((e) => e.id).toSet();
      expect(ids.length, 3);
    });

    test('3. All mock events are marked as mock/demo', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      for (final event in events) {
        expect(event.isMock, isTrue);
        expect(event.status, PublicEventStatus.published);
      }
    });

    test('4. All mock events occur after the injected reference time', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      for (final event in events) {
        expect(event.startDateTime.isAfter(fixedRef), isTrue);
        expect(event.endDateTime.isAfter(event.startDateTime), isTrue);
      }
    });

    test('5. Events are sorted by start time ascending', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      expect(events[0].startDateTime.isBefore(events[1].startDateTime), isTrue);
      expect(events[1].startDateTime.isBefore(events[2].startDateTime), isTrue);
    });

    test('6. Event 1 is calendar date +2 days (DST-safe comparison)', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      final event1 = events.firstWhere((e) => e.id == 'mock_event_1');

      final expectedDate = DateTime(fixedRef.year, fixedRef.month, fixedRef.day + 2);
      final actualDate = DateTime(event1.startDateTime.year, event1.startDateTime.month, event1.startDateTime.day);

      expect(actualDate, equals(expectedDate));
      expect(event1.startDateTime.hour, 20);
      expect(event1.startDateTime.minute, 0);
      expect(event1.endDateTime.hour, 23);
      expect(event1.endDateTime.minute, 0);
      expect(event1.title, 'Stockholm Jazz Night');
      expect(event1.eventType, PublicEventType.liveGig);
      expect(event1.eventTypeDisplayLabel, 'Live/Gig');
      expect(event1.typeFilterCategory, 'Live/Gigs');
      expect(event1.venueName, 'Jazzbaren');
      expect(event1.city, 'Stockholm');
    });

    test('7. Event 2 is calendar date +9 days (DST-safe comparison)', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      final event2 = events.firstWhere((e) => e.id == 'mock_event_2');

      final expectedDate = DateTime(fixedRef.year, fixedRef.month, fixedRef.day + 9);
      final actualDate = DateTime(event2.startDateTime.year, event2.startDateTime.month, event2.startDateTime.day);

      expect(actualDate, equals(expectedDate));
      expect(event2.startDateTime.hour, 18);
      expect(event2.startDateTime.minute, 30);
      expect(event2.endDateTime.hour, 21);
      expect(event2.endDateTime.minute, 30);
      expect(event2.title, 'Open Co-writing Session');
      expect(event2.eventType, PublicEventType.openSession);
      expect(event2.eventTypeDisplayLabel, 'Open Session');
      expect(event2.typeFilterCategory, 'Open Sessions');
      expect(event2.venueName, 'Song Lab Göteborg');
      expect(event2.city, 'Göteborg');
      expect(event2.isFree, isTrue);
    });

    test('8. Event 3 is calendar date +35 days (DST-safe comparison, next month)', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();
      final event3 = events.firstWhere((e) => e.id == 'mock_event_3');

      final expectedDate = DateTime(fixedRef.year, fixedRef.month, fixedRef.day + 35);
      final actualDate = DateTime(event3.startDateTime.year, event3.startDateTime.month, event3.startDateTime.day);

      expect(actualDate, equals(expectedDate));
      expect(event3.startDateTime.hour, 13);
      expect(event3.startDateTime.minute, 0);
      expect(event3.endDateTime.hour, 17);
      expect(event3.endDateTime.minute, 0);
      expect(event3.title, 'Music Production Workshop');
      expect(event3.eventType, PublicEventType.workshopCourse);
      expect(event3.eventTypeDisplayLabel, 'Workshop/Course');
      expect(event3.typeFilterCategory, 'Workshops');
      expect(event3.venueName, 'Nordic Sound Studio');
      expect(event3.city, 'Malmö');
    });

    test('9. Price formatting renders Free, 150 SEK, and 295 SEK correctly', () async {
      final repo = MockPublicEventRepository(referenceNow: fixedRef);
      final events = await repo.getUpcomingEvents();

      final e1 = events.firstWhere((e) => e.id == 'mock_event_1');
      final e2 = events.firstWhere((e) => e.id == 'mock_event_2');
      final e3 = events.firstWhere((e) => e.id == 'mock_event_3');

      expect(e1.formattedPrice, '150 SEK');
      expect(e2.formattedPrice, 'Free');
      expect(e3.formattedPrice, '295 SEK');
    });

    test('10. EmptyPublicEventRepository returns an empty list', () async {
      final emptyRepo = EmptyPublicEventRepository();
      final events = await emptyRepo.getUpcomingEvents();
      expect(events, isEmpty);
    });
  });
}
