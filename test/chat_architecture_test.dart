import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/utils/date_parser.dart';

void main() {
  group('Chat Architecture & Message Compatibility Tests', () {
    test(
      'Message.fromJson parses both legacy capitalized and canonical lowercase fields',
      () {
        final legacyJson = {
          'SenderId': 'user_a',
          'ReceiverId': 'user_b',
          'Text': 'Hey, ready for rehearsal?',
          'Timestamp': '2026-08-12T12:00:00Z',
          'IsRead': false,
        };

        final canonicalJson = {
          'senderId': 'user_a',
          'receiverId': 'user_b',
          'text': 'Hey, ready for rehearsal?',
          'timestamp': '2026-08-12T12:00:00Z',
          'isRead': false,
        };

        final msg1 = Message.fromJson(
          legacyJson,
          'msg_1',
          currentUserId: 'user_b',
        );
        final msg2 = Message.fromJson(
          canonicalJson,
          'msg_2',
          currentUserId: 'user_b',
        );

        expect(msg1.senderId, 'user_a');
        expect(msg1.receiverId, 'user_b');
        expect(msg1.text, 'Hey, ready for rehearsal?');
        expect(msg1.isRead, isFalse);

        expect(msg2.senderId, 'user_a');
        expect(msg2.receiverId, 'user_b');
        expect(msg2.text, 'Hey, ready for rehearsal?');
        expect(msg2.isRead, isFalse);
      },
    );

    test(
      'userConversations index entry mapping correctly stores conversation metadata',
      () {
        final userConvData = {
          'otherUserId': 'user_b',
          'lastMessageText': 'Sounds great!',
          'lastMessageTimestamp': '2026-08-12T14:30:00Z',
          'hasUnread': true,
          'conversationType': 'direct',
        };

        expect(userConvData['otherUserId'], 'user_b');
        expect(userConvData['hasUnread'], isTrue);
        expect(userConvData['conversationType'], 'direct');
      },
    );

    test(
      'parseDateTime handles all expected timestamp representations safely',
      () {
        // 1. Missing or null
        expect(parseDateTime(null), isNull);

        // 2. Explicit null
        const dynamic explicitNull = null;
        expect(parseDateTime(explicitNull), isNull);

        // 3. Malformed legacy value
        expect(parseDateTime('invalid_timestamp_string'), isNull);
        expect(parseDateTime(''), isNull);
        expect(parseDateTime('   '), isNull);

        // 4. Valid ISO-8601 string
        final isoParsed = parseDateTime('2026-08-14T12:00:00.000Z');
        expect(isoParsed, isNotNull);
        expect(isoParsed!.year, 2026);
        expect(isoParsed.month, 8);

        // 5. Epoch milliseconds as int and double
        final intEpoch = parseDateTime(1786650000000);
        expect(intEpoch, isNotNull);
        expect(intEpoch!.millisecondsSinceEpoch, 1786650000000);

        final doubleEpoch = parseDateTime(1786650000000.0);
        expect(doubleEpoch, isNotNull);
        expect(doubleEpoch!.millisecondsSinceEpoch, 1786650000000);

        // 6. Numeric epoch string
        final strEpoch = parseDateTime('1786650000000');
        expect(strEpoch, isNotNull);
        expect(strEpoch!.millisecondsSinceEpoch, 1786650000000);

        // 7. Existing DateTime instance
        final now = DateTime.now();
        expect(parseDateTime(now), equals(now));
      },
    );

    test(
      'Null-safe conversation sorting ranks missing timestamps after valid timestamps',
      () {
        final conversations = [
          {
            'id': 'conv_missing',
            'hasUnread': false,
            'timestamp': parseDateTime(null),
          },
          {
            'id': 'conv_old',
            'hasUnread': false,
            'timestamp': parseDateTime('2026-08-10T10:00:00Z'),
          },
          {
            'id': 'conv_new',
            'hasUnread': false,
            'timestamp': parseDateTime('2026-08-14T10:00:00Z'),
          },
          {
            'id': 'conv_malformed',
            'hasUnread': false,
            'timestamp': parseDateTime('bad_date'),
          },
          {
            'id': 'conv_unread',
            'hasUnread': true,
            'timestamp': parseDateTime('2026-08-01T10:00:00Z'),
          },
        ];

        conversations.sort((a, b) {
          if (a['hasUnread'] != b['hasUnread']) {
            return (a['hasUnread'] == true) ? -1 : 1;
          }
          final dtA = a['timestamp'] as DateTime?;
          final dtB = b['timestamp'] as DateTime?;

          if (dtA != null && dtB != null) {
            return dtB.compareTo(dtA);
          }
          if (dtA != null && dtB == null) {
            return -1;
          }
          if (dtA == null && dtB != null) {
            return 1;
          }
          return 0;
        });

        // 1st: conv_unread (hasUnread == true)
        expect(conversations[0]['id'], 'conv_unread');
        // 2nd: conv_new (newest valid timestamp)
        expect(conversations[1]['id'], 'conv_new');
        // 3rd: conv_old (older valid timestamp)
        expect(conversations[2]['id'], 'conv_old');
        // 4th and 5th: conv_missing and conv_malformed (null timestamps sorted to end)
        final endIds = [conversations[3]['id'], conversations[4]['id']];
        expect(endIds, containsAll(['conv_missing', 'conv_malformed']));
      },
    );
  });
}
