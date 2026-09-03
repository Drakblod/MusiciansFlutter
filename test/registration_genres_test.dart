import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockRegisterAppState extends AppState {
  String? registeredEmail;
  String? registeredPassword;
  String? registeredUserType;
  String? registeredNickname;
  String? registeredLevel;
  List<String>? registeredGenres;
  UserProfile? savedProfile;

  UserProfile? mockProfile;

  @override
  UserProfile? get currentUserProfile => mockProfile ?? savedProfile;

  @override
  String? get currentUserId => currentUserProfile?.userId ?? 'test_uid_123';

  @override
  Future<void> register(
    String email,
    String password,
    String userType,
    String nickname, [
    String? level,
    List<String>? genres,
  ]) async {
    registeredEmail = email;
    registeredPassword = password;
    registeredUserType = userType;
    registeredNickname = nickname;
    registeredLevel = level;
    registeredGenres = genres;

    savedProfile = UserProfile(
      userId: 'test_uid_123',
      userType: userType,
      nickname: nickname,
      displayName: nickname,
      email: email,
      level: level ?? 'C = INTERMEDIATE',
      genres: genres ?? const [],
    );
  }
}

Widget createRegisterTestApp({required MockRegisterAppState appState, Widget? child}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/main-nav': (context) => const Scaffold(body: Text('Main Nav')),
      },
      home: child ?? const RegisterScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Registration Genres/Band Types Verification Tests', () {
    // 1. The field appears between Primary Skill and Level.
    testWidgets('1. Genres/Band Types appears between Primary Skill and Level', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      final primarySkillFinder = find.text('Primary Skill/Talent (Select 1)');
      final genresFinder = find.text('Genres/Band Types');
      final levelFinder = find.text('Level');

      expect(primarySkillFinder, findsOneWidget);
      expect(genresFinder, findsOneWidget);
      expect(levelFinder, findsOneWidget);

      final primarySkillY = tester.getTopLeft(primarySkillFinder).dy;
      final genresY = tester.getTopLeft(genresFinder).dy;
      final levelY = tester.getTopLeft(levelFinder).dy;

      expect(primarySkillY, lessThan(genresY), reason: 'Primary Skill must render above Genres/Band Types');
      expect(genresY, lessThan(levelY), reason: 'Genres/Band Types must render above Level');
    });

    // 2. The complete field opens the existing picker.
    testWidgets('2. The complete field opens the existing picker on tap', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      // Tap anywhere on the Genres/Band Types field container
      await tester.tap(find.text('Genres/Band Types'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('Genres/Band Types'), findsAtLeastNWidgets(1));

      // Close the picker
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    });

    // 3. Multiple selections work if supported by the existing picker.
    testWidgets('3. Multiple selections work and display chips in the field', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      // Open picker
      await tester.tap(find.text('Genres/Band Types'));
      await tester.pumpAndSettle();

      // Expand first category and select Rock and Pop
      await tester.tap(find.textContaining('Rock, Pop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pop'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Field now displays the selected chips and badge count 2
      expect(find.text('2'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Rock'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Pop'), findsOneWidget);
    });

    // 4. Selected values use the existing persisted format.
    test('4. Selected values use the existing persisted format in UserProfile', () {
      final profile = UserProfile(
        userId: 'test_user_genres',
        userType: 'Lead Guitar',
        nickname: 'RockGuitarist',
        displayName: 'RockGuitarist',
        email: 'guitar@test.com',
        genres: ['Rock', 'Pop'],
      );

      expect(profile.genres, equals(['Rock', 'Pop']));
      final json = profile.toJson();
      expect(json['Genres'], equals(['Rock', 'Pop']));

      final roundTrip = UserProfile.fromJson(json, 'test_user_genres');
      expect(roundTrip.genres, equals(['Rock', 'Pop']));
    });

    // 5. Registration succeeds and saves the selections.
    testWidgets('5. Registration succeeds and saves the genre selections', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      // Fill in text fields
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'JimmyPage'); // Profile Name
      await tester.enterText(textFields.at(1), 'jimmy@ledzep.com'); // Email
      await tester.enterText(textFields.at(2), 'password123'); // Password
      await tester.pumpAndSettle();

      // Select genres
      await tester.tap(find.text('Genres/Band Types'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Rock, Pop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pop'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Tap Sign Up
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(appState.registeredNickname, equals('JimmyPage'));
      expect(appState.registeredEmail, equals('jimmy@ledzep.com'));
      expect(appState.registeredGenres, equals(['Rock', 'Pop']));
      expect(appState.savedProfile, isNotNull);
      expect(appState.savedProfile!.genres, equals(['Rock', 'Pop']));
      expect(find.text('Main Nav'), findsOneWidget);
    });

    testWidgets('5b. Reopening EditProfileScreen displays saved genres correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      appState.mockProfile = UserProfile(
        userId: 'test_uid_123',
        userType: 'Lead Guitar',
        nickname: 'JimmyPage',
        displayName: 'JimmyPage',
        email: 'jimmy@ledzep.com',
        genres: ['Rock', 'Pop'],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            key: UniqueKey(),
            home: const EditProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rock'), findsAtLeastNWidgets(1));
      expect(find.text('Pop'), findsAtLeastNWidgets(1));
    });

    // 6. Registration without a selection remains valid if the field is optional.
    testWidgets('6. Registration without a genre selection remains valid', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'JohnPaulJones');
      await tester.enterText(textFields.at(1), 'jpj@ledzep.com');
      await tester.enterText(textFields.at(2), 'password123');
      await tester.pumpAndSettle();

      // Do NOT select genres -> field remains empty/optional
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(appState.registeredNickname, equals('JohnPaulJones'));
      expect(appState.registeredGenres, isEmpty);
      expect(appState.savedProfile!.genres, isEmpty);
      expect(find.text('Main Nav'), findsOneWidget);
    });

    // 7. Existing registration behavior remains unchanged (validations, password toggle, etc.)
    testWidgets('7. Existing registration validation and behavior remains unchanged', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = MockRegisterAppState();
      await tester.pumpWidget(createRegisterTestApp(appState: appState));
      await tester.pumpAndSettle();

      // Empty submission triggers standard validation errors
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a profile name'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please choose a password'), findsOneWidget);
      expect(appState.registeredNickname, isNull);
    });
  });
}
