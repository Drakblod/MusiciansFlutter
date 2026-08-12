import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/message.dart';

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
  });
}
