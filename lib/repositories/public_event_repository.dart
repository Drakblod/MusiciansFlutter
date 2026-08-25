import '../models/public_calendar_event.dart';

/// Contract for fetching public calendar events
abstract class PublicEventRepository {
  Future<List<PublicCalendarEvent>> getUpcomingEvents();
}

/// Mock repository implementation returning 3 deterministic upcoming events
/// based on an injected reference time (defaults to local DateTime.now()).
class MockPublicEventRepository implements PublicEventRepository {
  final DateTime? referenceNow;

  MockPublicEventRepository({this.referenceNow});

  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async {
    final ref = referenceNow ?? DateTime.now();

    // Event 1: Reference date + 2 days at 20:00 - 23:00
    final event1Start = DateTime(ref.year, ref.month, ref.day + 2, 20, 0);
    final event1End = DateTime(ref.year, ref.month, ref.day + 2, 23, 0);

    // Event 2: Reference date + 9 days at 18:30 - 21:30
    final event2Start = DateTime(ref.year, ref.month, ref.day + 9, 18, 30);
    final event2End = DateTime(ref.year, ref.month, ref.day + 9, 21, 30);

    // Event 3: Reference date + 35 days at 13:00 - 17:00 (crosses into subsequent month)
    final event3Start = DateTime(ref.year, ref.month, ref.day + 35, 13, 0);
    final event3End = DateTime(ref.year, ref.month, ref.day + 35, 17, 0);

    final List<PublicCalendarEvent> events = [
      PublicCalendarEvent(
        id: 'mock_event_1',
        title: 'Stockholm Jazz Night',
        eventType: PublicEventType.liveGig,
        organizerName: 'Stockholm Jazz Collective',
        venueName: 'Jazzbaren',
        city: 'Stockholm',
        address: 'Jazzgränd 4 (Demo Venue), Gamla Stan',
        startDateTime: event1Start,
        endDateTime: event1End,
        genres: const ['Jazz', 'Swing'],
        priceAmount: 150,
        currency: 'SEK',
        isFree: false,
        shortDescription:
            'An evening of live jazz and swing featuring musicians from across Stockholm.',
        description:
            'Join Stockholm Jazz Collective for an evening of live jazz, swing and spontaneous musical encounters. The program brings together established performers and emerging musicians for a relaxed night of live music.',
        status: PublicEventStatus.published,
        isMock: true,
      ),
      PublicCalendarEvent(
        id: 'mock_event_2',
        title: 'Open Co-writing Session',
        eventType: PublicEventType.openSession,
        organizerName: 'West Coast Songwriters',
        venueName: 'Song Lab Göteborg',
        city: 'Göteborg',
        address: 'Musikgatan 12 (Demo Studio), Majorna',
        startDateTime: event2Start,
        endDateTime: event2End,
        genres: const ['Pop', 'Songwriting'],
        priceAmount: null,
        currency: 'SEK',
        isFree: true,
        shortDescription:
            'Meet other songwriters and create new music together in an open collaborative session.',
        description:
            'An open co-writing evening for lyricists, composers, vocalists and producers. Participants will form small groups, develop ideas and share their work at the end of the session. Bring an instrument, notebook or laptop if useful.',
        status: PublicEventStatus.published,
        isMock: true,
      ),
      PublicCalendarEvent(
        id: 'mock_event_3',
        title: 'Music Production Workshop',
        eventType: PublicEventType.workshopCourse,
        organizerName: 'Nordic Sound Academy',
        venueName: 'Nordic Sound Studio',
        city: 'Malmö',
        address: 'Ljudvägen 8 (Demo Studio), Möllevången',
        startDateTime: event3Start,
        endDateTime: event3End,
        genres: const ['Production', 'Electronic'],
        priceAmount: 295,
        currency: 'SEK',
        isFree: false,
        shortDescription:
            'A practical workshop covering arrangement, recording and modern music production.',
        description:
            'A hands-on workshop for musicians and producers who want to improve their production workflow. The session covers arrangement, recording decisions, sound selection and practical approaches to building a finished track.',
        status: PublicEventStatus.published,
        isMock: true,
      ),
    ];

    // Sort ascending by startDateTime
    events.sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    return events;
  }
}

/// Fallback empty repository when mock data toggle is disabled
class EmptyPublicEventRepository implements PublicEventRepository {
  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async {
    return [];
  }
}
