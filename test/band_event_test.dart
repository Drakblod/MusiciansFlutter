import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band_event.dart';

void main() {
  group('BandEvent Model & Editing Whitelist Tests', () {
    test(
      'Creation initializes default fields and 24h reminder flag correctly',
      () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final event = BandEvent(
          title: 'Rehearsal Night',
          description: 'Practice for upcoming show',
          eventType: 'Rehearsal',
          location: 'Studio A',
          startDateTime: '2026-08-15T18:00:00Z',
          endDateTime: '2026-08-15T21:00:00Z',
          additionalNotes: 'Bring chord charts',
          createdBy: 'user_123',
          createdAt: now,
          updatedAt: now,
          requireResponse: true,
          sentReminder24h: true,
        );

        expect(event.title, 'Rehearsal Night');
        expect(event.createdBy, 'user_123');
        expect(event.sentReminder24h, isTrue);
        expect(event.isLocked, isFalse);
      },
    );

    test(
      'fromJson & toJson correctly serialize sentReminder24h and workflow metadata',
      () {
        final json = {
          'title': 'Gig Night',
          'description': 'Live performance',
          'eventType': 'Concert',
          'location': 'Club 123',
          'startDateTime': '2026-08-20T20:00:00Z',
          'endDateTime': '2026-08-20T23:00:00Z',
          'additionalNotes': 'Soundcheck at 18:00',
          'createdBy': 'leader_1',
          'createdAt': 1700000000000,
          'updatedAt': 1700000000000,
          'requireResponse': true,
          'isLocked': true,
          'lockedAt': 1700000050000,
          'lockedBy': 'leader_1',
          'sentReminder24h': true,
          'sentReminder48h': true,
          'Responses': {
            'user_2': {'status': 'YES', 'timestamp': '2026-08-12T10:00:00Z'},
          },
        };

        final event = BandEvent.fromJson(json, 'event_99');
        expect(event.id, 'event_99');
        expect(event.isLocked, isTrue);
        expect(event.lockedBy, 'leader_1');
        expect(event.sentReminder24h, isTrue);
        expect(event.sentReminder48h, isTrue);
        expect(event.responses['user_2']?.status, 'YES');

        final exported = event.toJson();
        expect(exported['sentReminder24h'], isTrue);
        expect(exported['isLocked'], isTrue);
        expect(exported['Responses'], isNotNull);
      },
    );

    test(
      'Whitelisted update payload preserves workflow fields and lock state',
      () {
        final existingJson = {
          'title': 'Original Title',
          'description': 'Original Desc',
          'eventType': 'Rehearsal',
          'location': 'Old Room',
          'startDateTime': '2026-08-15T18:00:00Z',
          'endDateTime': '2026-08-15T21:00:00Z',
          'additionalNotes': '',
          'createdBy': 'creator_admin',
          'createdAt': 1700000000000,
          'updatedAt': 1700000000000,
          'requireResponse': true,
          'isLocked': true,
          'lockedBy': 'creator_admin',
          'sentReminder24h': true,
          'Responses': {
            'user_10': {'status': 'YES', 'timestamp': '2026-08-12T12:00:00Z'},
          },
        };

        expect(BandEvent.fromJson(existingJson, 'evt_locked').isLocked, isTrue);

        // Simulate whitelist merge update
        final editWhitelist = {
          'title': 'New Updated Title',
          'location': 'New Studio B',
          'updatedAt': 1700000099000,
        };

        final mergedJson = Map<String, dynamic>.from(existingJson);
        editWhitelist.forEach((k, v) => mergedJson[k] = v);

        final updatedEvent = BandEvent.fromJson(mergedJson, 'evt_locked');

        expect(updatedEvent.title, 'New Updated Title');
        expect(updatedEvent.location, 'New Studio B');
        // Verify preserved workflow metadata
        expect(updatedEvent.isLocked, isTrue);
        expect(updatedEvent.createdBy, 'creator_admin');
        expect(updatedEvent.sentReminder24h, isTrue);
        expect(updatedEvent.responses['user_10']?.status, 'YES');
      },
    );
  });
}
