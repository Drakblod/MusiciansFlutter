// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/musician_profile_screen.dart';
import 'package:musicians_flutter/views/profile_tab_screen.dart';

class MockFirebaseServiceForProfile extends FirebaseService {
  @override
  Future<bool> isFavoriteAsync(String targetUserId) async => false;

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => [];
}

class MockAppStateForProfile extends AppState {
  final MockFirebaseServiceForProfile _mockService = MockFirebaseServiceForProfile();
  UserProfile? _user;

  MockAppStateForProfile({UserProfile? user}) {
    _user = user;
  }

  void setUser(UserProfile? user) {
    _user = user;
    notifyListeners();
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

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('PROFILES-01 — MusicianProfileScreen', () {
    testWidgets('Displays PRIMARY SKILL/TALENT (singular) and not plural variant', (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'John Doe',
        instruments: ['Guitarist', 'Singer'],
        mainInstrument: 'Guitarist',
        genres: ['Rock', 'Blues'],
        collabBio: 'Open for jazz fusion projects',
      );

      final mockAppState = MockAppStateForProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIMARY SKILL/TALENT'), findsOneWidget);
      expect(find.text('PRIMARY Skills/Talents'), findsNothing);
      expect(find.text('PRIMARY SKILLS/TALENTS'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.widgetWithText(Row, 'Guitarist'), findsOneWidget);
    });

    testWidgets('Section order is PRIMARY SKILL/TALENT, then SECONDARY Skills/Talents, then Genres/Band Types', (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'John Doe',
        instruments: ['Guitarist', 'Singer'],
        mainInstrument: 'Guitarist',
        genres: ['Rock', 'Blues'],
      );

      final mockAppState = MockAppStateForProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Genres/Band Types section heading is unique (not duplicated)
      expect(find.text('Genres/Band Types'), findsOneWidget);
      expect(find.text('Rock'), findsWidgets);
      expect(find.text('Blues'), findsWidgets);

      final primarySkillPos = tester.getTopLeft(find.text('PRIMARY SKILL/TALENT')).dy;
      final secondarySkillsPos = tester.getTopLeft(find.text('SECONDARY Skills/Talents')).dy;
      final genresPos = tester.getTopLeft(find.text('Genres/Band Types')).dy;

      expect(primarySkillPos < secondarySkillsPos, isTrue, reason: 'PRIMARY SKILL/TALENT must be above SECONDARY Skills/Talents');
      expect(secondarySkillsPos < genresPos, isTrue, reason: 'SECONDARY Skills/Talents must be above Genres/Band Types');
    });

    testWidgets('Collaborations displays helper text and populated collabBio', (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'John Doe',
        instruments: ['Guitarist'],
        mainInstrument: 'Guitarist',
        collabBio: 'Looking for an acoustic duo partner.',
      );

      final mockAppState = MockAppStateForProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Collaborations'), findsOneWidget);
      expect(
        find.text('Specify what types of collaborations you are open to (if any)'),
        findsOneWidget,
      );
      expect(find.text('Looking for an acoustic duo partner.'), findsOneWidget);
      expect(find.text("I'm looking for musical collaborations!"), findsNothing);
    });

    testWidgets('Collaborations displays None specified when collabBio is empty without fabricated copy', (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'John Doe',
        instruments: ['Guitarist'],
        mainInstrument: 'Guitarist',
        collabBio: null,
      );

      final mockAppState = MockAppStateForProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Genres/Band Types'), findsOneWidget);
      expect(find.text('None specified'), findsNWidgets(2));
      expect(find.text("I'm looking for musical collaborations!"), findsNothing);
    });

    testWidgets('Genres/Band Types is still showing even if genres is empty', (tester) async {
      final musician = UserProfile(
        userId: 'm1',
        displayName: 'John Doe',
        instruments: ['Guitarist'],
        mainInstrument: 'Guitarist',
        genres: [],
        collabBio: 'Looking for a band.',
      );

      final mockAppState = MockAppStateForProfile();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: MusicianProfileScreen(musician: musician),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Genres/Band Types'), findsOneWidget);
      expect(find.text('None specified'), findsOneWidget);
    });
  });

  group('PROFILES-01 — ProfileTabScreen', () {
    testWidgets('Displays PRIMARY SKILL/TALENT, ordered Genres, and Collaborations helper with neutral fallback', (tester) async {
      final user = UserProfile(
        userId: 'self_1',
        displayName: 'My Own Profile',
        instruments: ['Bassist', 'Keyboardist'],
        mainInstrument: 'Bassist',
        genres: ['Funk', 'Soul'],
        collabBio: '',
      );

      final mockAppState = MockAppStateForProfile(user: user);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: const Scaffold(body: ProfileTabScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIMARY SKILL/TALENT'), findsOneWidget);
      expect(find.text('PRIMARY Skills/Talents'), findsNothing);
      expect(find.text('PRIMARY SKILLS/TALENTS'), findsNothing);
      expect(find.widgetWithText(Row, 'Bassist'), findsOneWidget);

      expect(find.text('Genres/Band Types'), findsOneWidget);
      expect(find.text('Funk'), findsWidgets);
      expect(find.text('Soul'), findsWidgets);

      final primarySkillPos = tester.getTopLeft(find.text('PRIMARY SKILL/TALENT')).dy;
      final secondarySkillsPos = tester.getTopLeft(find.text('SECONDARY Skills/Talents')).dy;
      final genresPos = tester.getTopLeft(find.text('Genres/Band Types')).dy;

      expect(primarySkillPos < secondarySkillsPos, isTrue);
      expect(secondarySkillsPos < genresPos, isTrue);

      expect(find.text('Collaborations'), findsOneWidget);
      expect(
        find.text('Specify what types of collaborations you are open to (if any)'),
        findsOneWidget,
      );
      expect(find.text('None specified'), findsOneWidget);
      expect(find.text("I'm looking for musical collaborations!"), findsNothing);
    });

    testWidgets('ProfileTabScreen displays Genres/Band Types even if genres is empty', (tester) async {
      final user = UserProfile(
        userId: 'self_1',
        displayName: 'My Own Profile',
        instruments: ['Bassist'],
        mainInstrument: 'Bassist',
        genres: [],
        collabBio: 'Open to jam.',
      );

      final mockAppState = MockAppStateForProfile(user: user);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: mockAppState,
            child: const Scaffold(body: ProfileTabScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Genres/Band Types'), findsOneWidget);
      expect(find.text('None specified'), findsOneWidget);
    });
  });
}
