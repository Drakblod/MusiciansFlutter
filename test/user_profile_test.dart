import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/user_profile.dart';

void main() {
  group('UserProfile Model & Persistence Tests', () {
    test(
      'Registration constructs profile with email and null default location (no fake Stockholm)',
      () {
        final profile = UserProfile(
          userId: 'uid_test_1',
          userType: 'Drummer',
          nickname: 'AlexDrummer',
          displayName: 'AlexDrummer',
          email: 'alex@example.com',
          location: null,
        );

        expect(profile.email, 'alex@example.com');
        expect(profile.userType, 'Drummer');
        expect(profile.nickname, 'AlexDrummer');
        expect(profile.location, isNull);
        expect(profile.location, isNot('Stockholm, Sweden'));
      },
    );

    test('fromJson falls back seamlessly between root and info subtrees', () {
      final legacyRootJson = {
        'UserId': 'uid_legacy_99',
        'UserType': 'Guitarist',
        'Nickname': 'RockGod',
        'DisplayName': 'Rock God',
        'info': {
          'Email': 'rock@guitar.com',
          'Location': 'Gothenburg, Sweden',
          'Instruments': ['Guitar', 'Vocals'],
          'PushToken': 'fcm_token_12345',
        },
      };

      final profile = UserProfile.fromJson(legacyRootJson, 'uid_legacy_99');

      expect(profile.userId, 'uid_legacy_99');
      expect(profile.userType, 'Guitarist');
      expect(profile.nickname, 'RockGod');
      expect(profile.displayName, 'Rock God');
      expect(profile.email, 'rock@guitar.com');
      expect(profile.location, 'Gothenburg, Sweden');
      expect(profile.instruments, ['Guitar', 'Vocals']);
    });

    test(
      'Profile updates preserve existing PushToken and operational fields',
      () {
        final existingUserData = {
          'info': {
            'DisplayName': 'Old Name',
            'PushToken': 'secret_push_token_abc',
            'NotificationPrefs': {'email': true},
          },
        };

        final patchFields = {
          'DisplayName': 'New Display Name',
          'Location': 'Malmö, Sweden',
        };

        final updatedInfo = Map<String, dynamic>.from(
          existingUserData['info'] as Map,
        );
        patchFields.forEach((k, v) => updatedInfo[k] = v);

        expect(updatedInfo['DisplayName'], 'New Display Name');
        expect(updatedInfo['Location'], 'Malmö, Sweden');
        // PushToken and operational fields remain intact
        expect(updatedInfo['PushToken'], 'secret_push_token_abc');
        expect(updatedInfo['NotificationPrefs'], isNotNull);
      },
    );
  });
}
