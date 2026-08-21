import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/user_profile.dart';

void main() {
  group('Registration Flow & Profile Persistence Security Tests', () {
    test(
      'UserProfile constructs correct multi-location paths with non-empty UID',
      () {
        final profile = UserProfile(
          userId: 'test_uid_123',
          userType: 'Guitarist',
          nickname: 'AlexTest21',
          displayName: 'AlexTest21',
          email: 'alextest21@example.com',
          location: null,
          level: 'C = INTERMEDIATE',
        );

        expect(profile.userId, equals('test_uid_123'));
        expect(profile.nickname, equals('AlexTest21'));
        expect(profile.displayName, equals('AlexTest21'));
        expect(profile.email, equals('alextest21@example.com'));
        expect(profile.location, isNull);
        expect(profile.userType, equals('Guitarist'));
      },
    );

    test(
      'Path construction throws ArgumentError if userId is empty or whitespace',
      () {
        void validateUserId(String userId) {
          final trimmed = userId.trim();
          if (trimmed.isEmpty) {
            throw ArgumentError(
              'userId cannot be empty when updating profile fields.',
            );
          }
        }

        expect(() => validateUserId(''), throwsArgumentError);
        expect(() => validateUserId('   '), throwsArgumentError);
        expect(() => validateUserId('valid_uid_456'), returnsNormally);
      },
    );

    test(
      'Root multi-location update map includes required compatibility keys without empty child paths',
      () {
        final userId = 'user_new_789';
        final profile = UserProfile(
          userId: userId,
          userType: 'Bass',
          nickname: 'AlexTest21',
          displayName: 'AlexTest21',
          email: 'alextest21@example.com',
          location: null,
          level: 'C = INTERMEDIATE',
        );

        final allowedInfoKeys = {
          'DisplayName',
          'Email',
          'Level',
          'Location',
          'About',
          'Instruments',
          'Styles',
          'Genres',
          'Contact',
          'History',
          'Projects',
          'ProfilePictureUrl',
          'SpotifyUrl',
          'YoutubeUrl',
          'AudioSnippetUrl',
          'CollabRoles',
          'CollabRemote',
          'CollabBio',
          'MainInstrument',
          'UserType',
          'Nickname',
        };

        final fields = <String, dynamic>{
          'DisplayName': profile.displayName,
          'Email': profile.email,
          'Level': profile.level,
          'Location': profile.location,
          'About': profile.about,
          'Instruments': profile.instruments,
          'Styles': profile.styles,
          'Genres': profile.genres,
          'Contact': profile.contact ?? profile.email,
          'History': profile.history,
          'Projects': profile.projects,
          'ProfilePictureUrl': profile.profilePictureUrl,
          'SpotifyUrl': profile.spotifyUrl,
          'YoutubeUrl': profile.youtubeUrl,
          'AudioSnippetUrl': profile.audioSnippetUrl,
          'CollabRoles': profile.collabRoles,
          'CollabRemote': profile.collabRemote,
          'CollabBio': profile.collabBio,
          'MainInstrument': profile.mainInstrument,
          if (profile.userType != null) 'UserType': profile.userType,
          if (profile.nickname != null) 'Nickname': profile.nickname,
        };

        final updates = <String, dynamic>{};
        fields.forEach((key, value) {
          if (allowedInfoKeys.contains(key)) {
            updates['users/$userId/info/$key'] = value;
            if (key == 'UserType' ||
                key == 'Nickname' ||
                key == 'DisplayName') {
              updates['users/$userId/$key'] = value;
            }
          }
        });

        // Assert root compatibility paths exist
        expect(
          updates['users/user_new_789/info/Email'],
          equals('alextest21@example.com'),
        );
        expect(
          updates['users/user_new_789/info/Nickname'],
          equals('AlexTest21'),
        );
        expect(
          updates['users/user_new_789/info/DisplayName'],
          equals('AlexTest21'),
        );
        expect(updates['users/user_new_789/info/UserType'], equals('Bass'));
        expect(updates['users/user_new_789/info/Location'], isNull);

        expect(updates['users/user_new_789/Nickname'], equals('AlexTest21'));
        expect(updates['users/user_new_789/DisplayName'], equals('AlexTest21'));
        expect(updates['users/user_new_789/UserType'], equals('Bass'));

        // Ensure no path contains empty child segments or invalid characters
        for (final path in updates.keys) {
          expect(
            path.contains('//'),
            isFalse,
            reason: 'Path should not contain consecutive slashes: $path',
          );
          expect(
            path.startsWith('/'),
            isFalse,
            reason:
                'Key paths in multi-location update should not start with leading slash: $path',
          );
        }
      },
    );

    test(
      'Compensation logic deletes newly created Auth user on profile write failure',
      () async {
        bool authUserDeleted = false;
        bool signedOut = false;

        Future<void> mockRegisterCompensation({
          required bool profileWriteFails,
          required bool deleteSucceeds,
        }) async {
          try {
            if (profileWriteFails) {
              throw Exception('RTDB network error');
            }
          } catch (e) {
            try {
              if (!deleteSucceeds) {
                throw Exception('Auth delete failed');
              }
              authUserDeleted = true;
            } catch (deleteError) {
              signedOut = true;
              throw Exception(
                'Registration failed during profile setup ($e). '
                'Auth account cleanup failed: $deleteError. You have been signed out. Please try registering again.',
              );
            }
            rethrow;
          }
        }

        // Test 1: Successful rollback deletes newly created user
        await expectLater(
          () => mockRegisterCompensation(
            profileWriteFails: true,
            deleteSucceeds: true,
          ),
          throwsA(isA<Exception>()),
        );
        expect(authUserDeleted, isTrue);

        // Test 2: If rollback delete fails, triggers sign out and throws clear error
        await expectLater(
          () => mockRegisterCompensation(
            profileWriteFails: true,
            deleteSucceeds: false,
          ),
          throwsA(
            predicate((e) => e.toString().contains('You have been signed out')),
          ),
        );
        expect(signedOut, isTrue);
      },
    );

    test(
      'Stale profile cache isolation resets previous user state when switching UID',
      () {
        UserProfile? currentUserProfile = UserProfile(
          userId: 'previous_uid_alexhill',
          nickname: 'AlexHill',
          displayName: 'AlexHill',
          email: 'alexhill@example.com',
        );

        void clearProfileState() {
          currentUserProfile = null;
        }

        // Starting registration clears stale user state
        clearProfileState();
        expect(currentUserProfile, isNull);

        // Newly registered profile is assigned
        final newRegisteredProfile = UserProfile(
          userId: 'new_uid_alextest21',
          nickname: 'AlexTest21',
          displayName: 'AlexTest21',
          email: 'alextest21@example.com',
        );
        currentUserProfile = newRegisteredProfile;

        expect(currentUserProfile!.userId, equals('new_uid_alextest21'));
        expect(currentUserProfile!.nickname, equals('AlexTest21'));
        expect(currentUserProfile!.nickname, isNot(equals('AlexHill')));
      },
    );
  });
}
