import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/date_parser.dart';

void main() {
  testWidgets(
    'Inbox thread tile renders null, missing, malformed, and epoch timestamps without throwing',
    (WidgetTester tester) async {
      final testThreads = [
        {
          'conversationId': 'conv_null',
          'otherUserId': 'user_1',
          'otherUserName': 'Alice',
          'lastMessageText': 'Hello',
          'timestamp': parseDateTime(null),
          'hasUnread': false,
        },
        {
          'conversationId': 'conv_malformed',
          'otherUserId': 'user_2',
          'otherUserName': 'Bob',
          'lastMessageText': 'Malformed date',
          'timestamp': parseDateTime('invalid_date_string'),
          'hasUnread': false,
        },
        {
          'conversationId': 'conv_epoch_int',
          'otherUserId': 'user_3',
          'otherUserName': 'Charlie',
          'lastMessageText': 'Epoch msg',
          'timestamp': parseDateTime(1786650000000),
          'hasUnread': false,
        },
        {
          'conversationId': 'conv_iso',
          'otherUserId': 'user_4',
          'otherUserName': 'Dave',
          'lastMessageText': 'ISO msg',
          'timestamp': parseDateTime('2026-08-14T12:00:00.000Z'),
          'hasUnread': true,
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: testThreads.length,
              itemBuilder: (context, index) {
                final thread = testThreads[index];
                final otherUserName = thread['otherUserName'] as String;
                final lastMessage = thread['lastMessageText'] as String;
                final timestamp = parseDateTime(
                  thread['timestamp'] ?? thread['lastMessageTimestamp'],
                );

                String formattedTime = '';
                if (timestamp != null) {
                  formattedTime =
                      '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
                }

                return ListTile(
                  title: Text(otherUserName),
                  subtitle: Text(lastMessage),
                  trailing: Text(formattedTime),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Dave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
