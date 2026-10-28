import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => [];
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

    testWidgets('2. Map View renders primary category filter tabs (MUSIC, SUB & MEMBER SEARCH, THIS WEEK)',
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
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Verify all 3 primary category tabs are rendered
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'MUSIC' || w.data == 'Music')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'SUB & MEMBER SEARCH' || w.data == 'Sub...')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == 'THIS WEEK' || w.data == 'This week')), findsOneWidget);
      expect(find.text('Upload Map View Pin / Audio'), findsOneWidget);
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
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // MUSIC tab is selected by default
      // Tap MUSIC tab to view sub-filters
      final musicTab = find.byWidgetPredicate((w) => w is Text && (w.data == 'MUSIC' || w.data == 'Music'));
      await tester.tap(musicTab);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Gig Promo'), findsNothing);
      expect(find.text('Gig'), findsOneWidget);
      expect(find.text('Concert'), findsOneWidget);
      expect(find.text('Rehearsal'), findsWidgets);
      expect(find.text('Jam Sessions'), findsOneWidget);
      expect(find.text('Demos / Recordings'), findsOneWidget);

      // Tap 'SUB & MEMBER SEARCH' tab
      final subTab = find.byWidgetPredicate((w) => w is Text && (w.data == 'SUB & MEMBER SEARCH' || w.data == 'Sub...'));
      await tester.tap(subTab);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sub-filters under Sub & Member Search appear
      expect(find.text('Substitutes'), findsOneWidget);
      expect(find.text('New Members'), findsOneWidget);
      expect(find.text('Paid Gigs'), findsWidgets);
      expect(find.text('Search Instruments'), findsOneWidget);

      // Tap 'Search Instruments' to open instrument picker
      await tester.tap(find.text('Search Instruments'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SELECT ROLE / INSTRUMENT'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
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
      await tester.pump(const Duration(milliseconds: 300));

      // City Jumpers are omitted from the top row
      expect(find.text('All Sweden'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => (w is Text && (w.data?.contains('What is Map View') ?? false)) ||
              (w is RichText && w.text.toPlainText().contains('What is Map View')) ||
              (w is IconButton && w.tooltip == 'What is Map View?'),
        ),
        findsWidgets,
      );
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
      await tester.pump(const Duration(milliseconds: 500));

      // Trigger selection of a mock rehearsal to display the docked Live Audio bar
      final mapFinder = find.byType(GoogleMap);
      if (mapFinder.evaluate().isNotEmpty) {
        final map = tester.widget<GoogleMap>(mapFinder);
        final rehearsalMarker = map.markers.firstWhere(
          (m) => m.markerId.value.startsWith('live_rehearsal'),
          orElse: () => map.markers.first,
        );
        rehearsalMarker.onTap?.call();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Live Audio bar exists
      expect(find.text('LIVE AUDIO'), findsOneWidget);
      expect(find.text('Turn OFF'), findsOneWidget);

      // Tap Turn OFF
      await tester.tap(find.text('Turn OFF'));
      await tester.pump(const Duration(milliseconds: 300));

      // Audio is stopped and button displays Turn ON
      expect(find.textContaining('Turn ON'), findsOneWidget);

      // Tap Turn ON
      await tester.tap(find.textContaining('Turn ON'));
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
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Tap Upload Event button
      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify bottom sheet opens
      expect(find.text('Upload Map View Pin / Audio'), findsWidgets);
      expect(find.text('Publish Map View Pin / Audio'), findsOneWidget);
      expect(find.text('Music Pin Type'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    test('7. MAP-VIEW-ROAD-LABELS-01: Both dark and white map styles hide all road labels while preserving geometry, locality and transit', () {
      final darkRules = (jsonDecode(GigMapPage.darkMapStyle) as List).cast<Map<String, dynamic>>();
      final whiteRules = (jsonDecode(GigMapPage.whiteMapStyle) as List).cast<Map<String, dynamic>>();

      for (final rules in [darkRules, whiteRules]) {
        // 1. Both styles contain a road + labels rule with visibility: off
        final roadLabelsRule = rules.firstWhere(
          (rule) => rule['featureType'] == 'road' && rule['elementType'] == 'labels',
        );
        expect(
          (roadLabelsRule['stylers'] as List).any((s) => s['visibility'] == 'off'),
          isTrue,
        );

        // 2. Road geometry remains visible (no visibility: off on road geometry)
        final roadGeomRules = rules.where(
          (rule) => rule['featureType'] == 'road' && rule['elementType']?.toString().startsWith('geometry') == true,
        );
        expect(roadGeomRules.isNotEmpty, isTrue);
        for (final geom in roadGeomRules) {
          expect(
            (geom['stylers'] as List).any((s) => s['visibility'] == 'off'),
            isFalse,
          );
        }

        // 3. administrative.locality labels remain visible (no visibility: off)
        final localityRules = rules.where(
          (rule) => rule['featureType'] == 'administrative.locality',
        );
        expect(localityRules.isNotEmpty, isTrue);
        for (final loc in localityRules) {
          expect(
            (loc['stylers'] as List).any((s) => s['visibility'] == 'off'),
            isFalse,
          );
        }
      }

      // 4. Transit labels configured in whiteMapStyle
      final transitStationLabels = whiteRules.where(
        (rule) => rule['featureType']?.toString().startsWith('transit') == true,
      );
      expect(transitStationLabels.isNotEmpty, isTrue);
    });

    testWidgets('8. MAP-VIEW-FEEDBACK-01: Upload form cleanup, labels and single Description field',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
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
      await tester.pump(const Duration(milliseconds: 300));

      // Close auto-targeted bottom card if open
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Tap Upload Map View Pin / Audio
      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Music Pin Type selector and no staffing options
      expect(find.text('Music Pin Type'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Sub & Member Search'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Gig Promo'), findsNothing);

      // Verify Type selector under Music contains 'Demos / Recordings' and not 'Recorded Music'
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      final itemValues = dropdown.items!.map((i) => i.value).toList();
      expect(itemValues.contains('Music Promotion'), isTrue);
      expect(itemValues.contains('Jam Session'), isTrue);
      expect(itemValues.contains('Demos / Recordings'), isTrue);
      expect(itemValues.contains('Recorded Music'), isFalse);
      expect(itemValues.contains('Substitute'), isFalse);
      expect(itemValues.contains('Band Member Search'), isFalse);

      // Verify Description / Details appears exactly once as an input label
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.textContaining('Event Title / Role'), findsNothing);

      // Verify Map View Pin Location / Address label
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField &&
              (w.decoration?.labelText?.contains('Location') == true ||
                  w.decoration?.labelText?.contains('Address') == true),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Pin Location (Street, City without postal code)'), findsNothing);

      // Verify Audio Track Info (title + info) section header and field
      expect(find.textContaining('Audio Track Info'), findsWidgets);

      expect(tester.takeException(), isNull);
    });
  });
}
