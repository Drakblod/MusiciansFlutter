import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/producer_search_screen.dart';
import 'package:musicians_flutter/views/collabs_landing_screen.dart';
import 'package:musicians_flutter/views/find_collabs_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/views/profile_tab_screen.dart';
import 'package:musicians_flutter/views/musician_profile_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:provider/provider.dart';

class MockGenFirebaseService extends FirebaseService {
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'user1',
      displayName: 'Alex Hill',
      instruments: ['Guitar', 'Mix Engineer'],
      genres: ['Rock', 'R&B'],
      level: 'C = INTERMEDIATE',
    );
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [
      UserProfile(
        userId: 'user1',
        displayName: 'Alex Hill',
        instruments: ['Guitar'],
        genres: ['Rock'],
        level: 'C = INTERMEDIATE',
      ),
    ];
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return [];
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return [];
  }
}

class MockGenAppState extends AppState {
  @override
  final FirebaseService firebaseService = MockGenFirebaseService();

  @override
  String? get currentUserId => 'user1';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user1',
        displayName: 'Alex Hill',
        instruments: ['Guitar', 'Mix Engineer'],
        genres: ['Rock', 'R&B'],
        level: 'C = INTERMEDIATE',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('GEN-02, GEN-03, GEN-04, GEN-05 Batch Presentation Tests', () {
    testWidgets('GEN-02 / GEN-03: Headings and selectors display canonical Genres/Band Types and SKILLS/TALENTS', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SKILLS/TALENTS'), findsOneWidget);
      expect(find.text('GENRES/BAND TYPES'), findsOneWidget);
      expect(find.text('GENRES & STYLES'), findsNothing);
      expect(find.text('Genres & Styles'), findsNothing);
      expect(find.text('Genres/Styles'), findsNothing);
    });

    testWidgets('GEN-02: Collabs screens use normalized Songwriters/Producers and Studios/Engineers without space-surrounded slashes', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: CollabsLandingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Songwriters/\nProducers'), findsOneWidget);
      expect(find.text('Studios/\nEngineers'), findsOneWidget);
      expect(find.text('Songwriters /\nProducers'), findsNothing);
      expect(find.text('Studios /\nEngineers'), findsNothing);
    });

    testWidgets('GEN-02: Field labels use slash without surrounding spaces (Primary Skill/Talent, Instrument/Skills)', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Skill/Talent (Select 1)'), findsOneWidget);
      expect(find.text('Primary Skill / Talent (Select 1)'), findsNothing);
    });

    testWidgets('GEN-02: Legitimate ampersand values (e.g. R&B) and legacy stored data load safely without crashing', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: ProfileTabScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('R&B'), findsOneWidget);
      expect(find.text('Mix Engineer'), findsOneWidget);
    });

    testWidgets('GEN-04: Parenthetical text (if any) and (City, Country) use normal font weight while main label is bold', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: CreateBandScreen()),
        ),
      );
      await tester.pumpAndSettle();

      bool foundIfAny = false;
      bool foundCityCountry = false;

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      for (final widget in textWidgets) {
        final span = widget.textSpan;
        if (span is TextSpan && span.children != null && span.children!.length >= 2) {
          final first = span.children![0] as TextSpan;
          final second = span.children![1] as TextSpan;

          if (second.text == ' (if any)') {
            foundIfAny = true;
            expect(first.style?.fontWeight, equals(FontWeight.bold));
            expect(second.style?.fontWeight, equals(FontWeight.normal));
          }

          if (second.text == ' (City, Country)') {
            foundCityCountry = true;
            expect(first.style?.fontWeight, equals(FontWeight.bold));
            expect(second.style?.fontWeight, equals(FontWeight.normal));
          }
        }
      }

      expect(foundIfAny, isTrue, reason: 'Should find (if any) label');
      expect(foundCityCountry, isTrue, reason: 'Should find (City, Country) label');
    });

    testWidgets('GEN-05: EditProfileScreen enforces relative section order Skills/Talents < Genres/Band Types < Level', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final skillsPos = tester.getTopLeft(find.text('SKILLS/TALENTS')).dy;
      final genresPos = tester.getTopLeft(find.text('GENRES/BAND TYPES')).dy;
      final levelPos = tester.getTopLeft(find.text('Level')).dy;

      expect(skillsPos, lessThan(genresPos), reason: 'SKILLS/TALENTS must render before GENRES/BAND TYPES');
      expect(genresPos, lessThan(levelPos), reason: 'GENRES/BAND TYPES must render before Level');
    });

    testWidgets('GEN-05: ProfileTabScreen enforces relative section order PRIMARY Skills/Talents < Genres/Band Types < Level', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: const MaterialApp(home: ProfileTabScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final skillsPos = tester.getTopLeft(find.text('PRIMARY Skills/Talents')).dy;
      final genresPos = tester.getTopLeft(find.text('Genres/Band Types')).dy;
      final levelPos = tester.getTopLeft(find.text('Level')).dy;

      expect(skillsPos, lessThan(genresPos), reason: 'PRIMARY Skills/Talents must render before Genres/Band Types');
      expect(genresPos, lessThan(levelPos), reason: 'Genres/Band Types must render before Level');
    });

    testWidgets('GEN-05: MusicianProfileScreen enforces relative section order PRIMARY Skills/Talents < Genres/Band Types < Level', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profile = UserProfile(
        userId: 'u1',
        displayName: 'Test Artist',
        instruments: ['Guitar'],
        genres: ['Jazz'],
        level: 'B = ADVANCED',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockGenAppState(),
          child: MaterialApp(home: MusicianProfileScreen(musician: profile)),
        ),
      );
      await tester.pumpAndSettle();

      final skillsPos = tester.getTopLeft(find.text('PRIMARY Skills/Talents')).dy;
      final genresPos = tester.getTopLeft(find.text('Genres/Band Types')).dy;
      final levelPos = tester.getTopLeft(find.text('Level')).dy;

      expect(skillsPos, lessThan(genresPos), reason: 'PRIMARY Skills/Talents must render before Genres/Band Types');
      expect(genresPos, lessThan(levelPos), reason: 'Genres/Band Types must render before Level');
    });
  });
}
