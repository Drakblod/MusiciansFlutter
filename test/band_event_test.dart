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

    test('classifyEventResponse normalizes status variants correctly', () {
      expect(classifyEventResponse('YES'), EventResponseStatus.yes);
      expect(classifyEventResponse('yes'), EventResponseStatus.yes);
      expect(classifyEventResponse('Yes'), EventResponseStatus.yes);
      expect(classifyEventResponse('attending'), EventResponseStatus.yes);
      expect(classifyEventResponse('Attending'), EventResponseStatus.yes);

      expect(classifyEventResponse('NO'), EventResponseStatus.no);
      expect(classifyEventResponse('no'), EventResponseStatus.no);
      expect(classifyEventResponse('No'), EventResponseStatus.no);
      expect(classifyEventResponse('declined'), EventResponseStatus.no);
      expect(classifyEventResponse('Declined'), EventResponseStatus.no);

      expect(classifyEventResponse('UNCERTAIN'), EventResponseStatus.uncertain);
      expect(classifyEventResponse('uncertain'), EventResponseStatus.uncertain);
      expect(classifyEventResponse('Uncertain'), EventResponseStatus.uncertain);
      expect(classifyEventResponse('maybe'), EventResponseStatus.uncertain);
      expect(classifyEventResponse('Maybe'), EventResponseStatus.uncertain);

      expect(classifyEventResponse(null), EventResponseStatus.noAnswer);
      expect(classifyEventResponse(''), EventResponseStatus.noAnswer);
      expect(classifyEventResponse('unknown'), EventResponseStatus.noAnswer);
      expect(classifyEventResponse('pending'), EventResponseStatus.noAnswer);
    });

    test('SubstituteAssignment parsing and isConfirmedAssignment rules', () {
      // 1. Valid canonical assignment
      final validSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_123',
        'assignedUserName': 'John Bass',
        'instrument': 'Bass',
        'replacedMemberName': 'Paul',
        'status': 'assigned',
      }, 'slot_1');
      expect(validSub.slotId, 'slot_1');
      expect(validSub.assignedUserId, 'sub_123');
      expect(validSub.assignedUserName, 'John Bass');
      expect(validSub.instrument, 'Bass');
      expect(validSub.replacedMemberName, 'Paul');
      expect(validSub.isConfirmedAssignment, isTrue);

      // 2. Filled status canonical assignment
      final filledSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_789',
        'assignedUserName': 'Ringo Drum',
        'instrument': 'Drums',
        'status': 'filled',
      }, 'slot_2');
      expect(filledSub.isConfirmedAssignment, isTrue);

      // 3. Accepted-but-unassigned applicant is NOT confirmed
      final acceptedSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_456',
        'assignedUserName': 'George Guitar',
        'instrument': 'Guitar',
        'status': 'accepted',
      }, 'slot_3');
      expect(acceptedSub.isConfirmedAssignment, isFalse);

      // 4. Selected favorite is NOT confirmed
      final selectedSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_555',
        'assignedUserName': 'Selected Musician',
        'instrument': 'Guitar',
        'status': 'selected',
      }, 'slot_4');
      expect(selectedSub.isConfirmedAssignment, isFalse);

      // 5. Name-only record (empty or whitespace assignedUserId) is NOT confirmed
      final nameOnlySub = SubstituteAssignment.fromJson({
        'assignedUserId': '',
        'assignedUserName': 'Only A Name',
        'instrument': 'Keys',
        'status': 'assigned',
      }, 'slot_5');
      expect(nameOnlySub.isConfirmedAssignment, isFalse);

      final whitespaceSub = SubstituteAssignment.fromJson({
        'assignedUserId': '   ',
        'assignedUserName': 'Whitespace User',
        'instrument': 'Keys',
        'status': 'assigned',
      }, 'slot_6');
      expect(whitespaceSub.isConfirmedAssignment, isFalse);

      // 6. Revoked / cancelled should not be confirmed
      final revokedSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_000',
        'assignedUserName': 'Revoked Sub',
        'instrument': 'Keys',
        'status': 'revoked',
      }, 'slot_7');
      expect(revokedSub.isConfirmedAssignment, isFalse);

      final cancelledSub = SubstituteAssignment.fromJson({
        'assignedUserId': 'sub_001',
        'assignedUserName': 'Cancelled Sub',
        'instrument': 'Keys',
        'status': 'cancelled',
      }, 'slot_8');
      expect(cancelledSub.isConfirmedAssignment, isFalse);
    });

    test('BandEvent.fromJson parses substituteAssignments map correctly', () {
      final json = {
        'title': 'Gig with Subs',
        'substituteAssignments': {
          'slot_1': {
            'assignedUserId': 'sub_1',
            'assignedUserName': 'Alice Sub',
            'instrument': 'Bass',
            'replacedMemberName': 'Bob',
            'status': 'assigned',
          },
          'slot_2': {
            'assignedUserId': 'sub_2',
            'assignedUserName': 'Charlie Sub',
            'instrument': 'Drums',
            'replacedMemberName': 'Dave',
            'status': 'cancelled',
          },
        },
      };

      final event = BandEvent.fromJson(json, 'evt_subs');
      expect(event.substituteAssignments.length, 2);
      expect(event.substituteAssignments['slot_1']?.isConfirmedAssignment, isTrue);
      expect(event.substituteAssignments['slot_2']?.isConfirmedAssignment, isFalse);
    });
  });
}
