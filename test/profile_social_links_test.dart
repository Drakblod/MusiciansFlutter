// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/musician_profile_screen.dart';
import 'package:musicians_flutter/views/profile_tab_screen.dart';

class MockUrlLauncherPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  String? lastLaunchedUrl;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    return true;
  }
}

class MockFirebaseServiceForSocialLinks extends FirebaseService {
  @override
  Future<bool> isFavoriteAsync(String targetUserId) async => false;

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => [];
}

class MockAppStateForSocialLinks extends AppState {
  final MockFirebaseServiceForSocialLinks _mockService =
      MockFirebaseServiceForSocialLinks();
  UserProfile? _user;

  MockAppStateForSocialLinks({UserProfile? user}) {
    _user = user;
  }

  @override
  FirebaseService get firebaseService => _mockService;

  @override
  UserProfile? get currentUserProfile => _user;

  @override
  String? get currentUserId => _user?.userId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late MockUrlLauncherPlatform mockUrlLauncher;

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    mockUrlLauncher = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockUrlLauncher;
  });

  group('Social links clickable in MusicianProfileScreen', () {
    testWidgets('Clicking Spotify and YouTube launches normalized URLs',
        (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'Rockstar',
        instruments: ['Guitarist'],
        spotifyUrl: 'open.spotify.com/artist/12345',
        youtubeUrl: 'https://youtube.com/@rockstar',
      );

      final appState = MockAppStateForSocialLinks(user: musician);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final spotifyFinder = find.text('Spotify');
      expect(spotifyFinder, findsOneWidget);
      await tester.ensureVisible(spotifyFinder);
      await tester.pumpAndSettle();
      await tester.tap(spotifyFinder);
      await tester.pump();
      expect(mockUrlLauncher.lastLaunchedUrl,
          'https://open.spotify.com/artist/12345');

      final youtubeFinder = find.text('YouTube');
      expect(youtubeFinder, findsOneWidget);
      await tester.ensureVisible(youtubeFinder);
      await tester.pumpAndSettle();
      await tester.tap(youtubeFinder);
      await tester.pump();
      expect(mockUrlLauncher.lastLaunchedUrl, 'https://youtube.com/@rockstar');
    });
  });

  group('Social links clickable in ProfileTabScreen', () {
    testWidgets('Clicking Spotify and YouTube in own profile launches URLs',
        (tester) async {
      final user = UserProfile(
        userId: 'self_1',
        displayName: 'My Profile',
        instruments: ['Bassist'],
        spotifyUrl: 'https://open.spotify.com/artist/myspotify',
        youtubeUrl: 'youtube.com/@mychannel',
      );

      final appState = MockAppStateForSocialLinks(user: user);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const Scaffold(body: ProfileTabScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final spotifyFinder = find.text('Spotify');
      expect(spotifyFinder, findsOneWidget);
      await tester.ensureVisible(spotifyFinder);
      await tester.pumpAndSettle();
      await tester.tap(spotifyFinder);
      await tester.pump();
      expect(mockUrlLauncher.lastLaunchedUrl,
          'https://open.spotify.com/artist/myspotify');

      final youtubeFinder = find.text('YouTube');
      expect(youtubeFinder, findsOneWidget);
      await tester.ensureVisible(youtubeFinder);
      await tester.pumpAndSettle();
      await tester.tap(youtubeFinder);
      await tester.pump();
      expect(mockUrlLauncher.lastLaunchedUrl, 'https://youtube.com/@mychannel');
    });
  });
}
