import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';

class MockFirebaseServiceForMapTest extends FirebaseService {
  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<List<dynamic>> getSubRequestsAsync() async => [];
}

class MockAppStateForMapTest extends AppState {
  final MockFirebaseServiceForMapTest _service = MockFirebaseServiceForMapTest();

  @override
  FirebaseService get firebaseService => _service;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'u1', displayName: 'Test User');

  @override
  String? get currentUserId => 'u1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Map View Light Version Comprehensive Tests', () {
    test('1. SubRequest model correctly exposes audio snippet getters', () {
      final gigWithAudio = SubRequest(
        role: 'Rock Guitarist Needed',
        requestType: 'Gig',
        extraFields: {
          'audioSnippetUrl': 'audio/bandrep1.mp3',
          'audioSnippetTitle': 'Live Promo Demo',
        },
      );

      expect(gigWithAudio.hasAudioSnippet, isTrue);
      expect(gigWithAudio.audioSnippetUrl, 'audio/bandrep1.mp3');
      expect(gigWithAudio.audioSnippetTitle, 'Live Promo Demo');

      final gigWithoutAudio = SubRequest(
        role: 'Acoustic Player',
        requestType: 'Gig',
      );

      expect(gigWithoutAudio.hasAudioSnippet, isFalse);
      expect(gigWithoutAudio.audioSnippetUrl, isNull);
    });

    testWidgets('2. Map View renders primary category filter tabs (All, Music, Gig Promo, Sub & Member Search, This Week)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppStateForMapTest(),
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // Verify all 5 primary category tabs are rendered
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Gig Promo'), findsOneWidget);
      expect(find.text('Sub & Member Search'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('Upload Event'), findsOneWidget);
    });

    testWidgets('3. Map View shows sub-filters when Music or Sub & Member Search is selected',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppStateForMapTest(),
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // Tap 'Music' tab
      await tester.tap(find.text('Music'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sub-filters under Music appear
      expect(find.text('All Music'), findsOneWidget);
      expect(find.text('Gig / Concert'), findsOneWidget);
      expect(find.text('Rehearsal'), findsOneWidget);
      expect(find.text('Jam Session'), findsOneWidget);
      expect(find.text('Recorded Music'), findsOneWidget);

      // Tap 'Sub & Member Search' tab
      await tester.tap(find.text('Sub & Member Search'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sub-filters under Sub & Member Search appear
      expect(find.text('All Sub/Member'), findsOneWidget);
      expect(find.text('New Member'), findsOneWidget);
      expect(find.text('Subs'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Search Instrument'), findsOneWidget);

      // Tap 'Search Instrument' to open instrument search bar
      await tester.tap(find.text('Search Instrument'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Guitar'), findsOneWidget);
      expect(find.text('Bass'), findsOneWidget);
      expect(find.text('Drums'), findsOneWidget);
    });

    testWidgets('4. Map View keeps top controls streamlined with City Jumpers omitted',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppStateForMapTest(),
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // City Jumpers are omitted from the top row
      expect(find.text('All Sweden'), findsNothing);
      expect(find.text('What is Map View?'), findsOneWidget);
    });

    testWidgets('5. Map View contains Live Audio control with Turn OFF / Turn ON power toggle',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppStateForMapTest(),
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // Live Audio bar exists
      expect(find.text('LIVE AUDIO'), findsOneWidget);
      expect(find.text('Turn OFF'), findsOneWidget);

      // Tap Turn OFF
      await tester.tap(find.text('Turn OFF'));
      await tester.pump(const Duration(milliseconds: 300));

      // Audio is stopped and button displays Turn ON
      expect(find.text('Turn ON'), findsOneWidget);
      expect(find.text('Turned OFF'), findsOneWidget);

      // Tap Turn ON
      await tester.tap(find.text('Turn ON'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Turn OFF'), findsOneWidget);
    });

    testWidgets('6. Upload Event sheet opens and contains category selection and form fields',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppStateForMapTest(),
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // Tap Upload Event button
      await tester.tap(find.text('Upload Event'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify bottom sheet opens
      expect(find.text('Upload Map Event / Audio'), findsOneWidget);
      expect(find.text('Publish to Map'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Event Type'), findsOneWidget);
    });
  });
}
