import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/utils/band_section_utils.dart';
import 'package:musicians_flutter/utils/date_parser.dart';

void main() {
  group('BandSectionUtils - Instrument Resolution & Normalization', () {
    test('1. Resolves primary skill from mainInstrument first', () {
      final profile = UserProfile(
        userId: 'user1',
        instruments: ['Trumpet', 'Drums'],
        mainInstrument: 'Trumpet',
      );
      expect(BandSectionUtils.resolveEffectiveInstrument(profile), 'Trumpet');
    });

    test('2. Falls back to instruments if mainInstrument is empty', () {
      final profile = UserProfile(
        userId: 'user2',
        instruments: ['Trombone'],
      );
      expect(BandSectionUtils.resolveEffectiveInstrument(profile), 'Trombone');
    });

    test('3. Returns null if no valid instrument or skill exists', () {
      final profile = UserProfile(
        userId: 'user3',
        instruments: [],
        userType: 'Browse Profiles',
      );
      expect(BandSectionUtils.resolveEffectiveInstrument(profile), isNull);
    });

    test('4. Normalizes instruments case-insensitively and trims whitespace', () {
      expect(BandSectionUtils.normalizeInstrumentKey(' Trumpet '), 'trumpet');
      expect(BandSectionUtils.normalizeInstrumentKey('TRUMPET'), 'trumpet');
      expect(BandSectionUtils.normalizeInstrumentKey('trumpet'), 'trumpet');
    });

    test('5. Does not merge distinct instruments', () {
      final key1 = BandSectionUtils.normalizeInstrumentKey('Trumpet');
      final key2 = BandSectionUtils.normalizeInstrumentKey('Piccolo Trumpet');
      expect(key1, isNot(equals(key2)));
    });

    test('6. Generates deterministic section suggestions with canonical display name', () {
      final members = [
        BandMember(userId: 'u1', nickname: 'Alice'),
        BandMember(userId: 'u2', nickname: 'Bob'),
        BandMember(userId: 'u3', nickname: 'Charlie'),
        BandMember(userId: 'u4', nickname: 'Dave'),
      ];

      final Map<String, UserProfile> profiles = {
        'u1': UserProfile(userId: 'u1', displayName: 'Alice', instruments: ['Trumpet']),
        'u2': UserProfile(userId: 'u2', displayName: 'Bob', instruments: ['trumpet']),
        'u3': UserProfile(userId: 'u3', displayName: 'Charlie', instruments: ['Saxophone']),
        'u4': UserProfile(userId: 'u4', displayName: 'Dave', instruments: []),
      };

      final suggestions = BandSectionUtils.generateSectionSuggestions(
        members: members,
        userProfiles: profiles,
      );

      expect(suggestions.length, 2);
      expect(suggestions[0].sectionName, 'Trumpet');
      expect(suggestions[0].sectionKey, 'trumpet');
      expect(suggestions[0].memberCount, 2);
      expect(suggestions[0].memberUserIds, containsAll(['u1', 'u2']));
      expect(suggestions[0].memberNames, containsAll(['Alice', 'Bob']));

      expect(suggestions[1].sectionName, 'Saxophone');
      expect(suggestions[1].memberCount, 1);
      expect(suggestions[1].memberUserIds, contains('u3'));
    });
  });

  group('Band Section Message and Thread Model Parsing', () {
    test('7. Parses band_section message with senderName and reply context', () {
      final json = {
        'id': 'msg_100',
        'senderId': 'user_1',
        'senderName': 'Miles Davis',
        'text': 'Rehearsal starts at 7:30 sharp.',
        'timestamp': '2026-08-25T14:00:00Z',
        'replyToText': 'When is rehearsal?',
        'replyToSenderName': 'Coltrane',
        'isRead': false,
      };

      final msg = Message.fromJson(json, 'msg_100', currentUserId: 'user_2');
      expect(msg.id, 'msg_100');
      expect(msg.senderId, 'user_1');
      expect(msg.senderName, 'Miles Davis');
      expect(msg.text, 'Rehearsal starts at 7:30 sharp.');
      expect(msg.replyToText, 'When is rehearsal?');
      expect(msg.replyToSenderName, 'Coltrane');
      expect(msg.isCurrentUserSender, isFalse);
    });

    test('8. Parses userConversations band_section thread entry', () {
      final rawItem = {
        'conversationType': 'band_section',
        'bandId': 'band_alpha',
        'bandName': 'The Jazz Quintet',
        'groupName': 'Brass Section',
        'sectionKey': 'brass',
        'sourceInstrument': 'Brass',
        'lastMessageText': 'Got the sheet music!',
        'lastMessageTimestamp': '2026-08-25T15:00:00Z',
        'lastMessageSenderId': 'user_3',
        'lastMessageSenderName': 'Dizzy',
        'hasUnread': true,
        'participantCount': 4,
      };

      final parsedDt = parseDateTime(rawItem['lastMessageTimestamp']);
      final thread = {
        'conversationId': 'conv_brass_1',
        'isGroup': true,
        'conversationType': 'band_section',
        'groupName': rawItem['groupName'],
        'bandName': rawItem['bandName'],
        'bandId': rawItem['bandId'],
        'participantCount': rawItem['participantCount'],
        'sectionKey': rawItem['sectionKey'],
        'sourceInstrument': rawItem['sourceInstrument'],
        'otherUserName': rawItem['groupName'],
        'otherUserId': '',
        'lastMessageSenderName': rawItem['lastMessageSenderName'],
        'lastMessageSenderId': rawItem['lastMessageSenderId'],
        'lastMessageText': rawItem['lastMessageText'],
        'lastMessageTimestamp': rawItem['lastMessageTimestamp'],
        'timestamp': parsedDt,
        'hasUnread': rawItem['hasUnread'] == true,
      };

      expect(thread['isGroup'], isTrue);
      expect(thread['groupName'], 'Brass Section');
      expect(thread['bandName'], 'The Jazz Quintet');
      expect(thread['participantCount'], 4);
      expect(thread['lastMessageSenderName'], 'Dizzy');
      expect(thread['hasUnread'], isTrue);
      expect(thread['timestamp'], isNotNull);
    });
  });
}
