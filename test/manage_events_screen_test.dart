import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/manage_events_screen.dart';
import 'package:musicians_flutter/controllers/global_create_event_launcher.dart';
import 'package:musicians_flutter/services/firebase_service.dart';

class MockFirebaseServiceForManageEvents extends Fake implements FirebaseService {
  final Map<String, String> userBands = {
    'band_1': 'Mats Testband 26',
    'band_2': 'Stockholm Rockers',
  };

  final Map<String, String> bandRoles = {
    'band_1': 'leader',
    'band_2': 'member',
  };

  final Map<String, List<BandEvent>> bandEvents = {
    'band_1': [
      BandEvent(
        id: 'ev_1',
        title: 'Summer Arena Concert',
        eventType: 'Concert',
        location: 'Globen, Stockholm',
        description: 'Big festival headline',
        startDateTime: DateTime.now().add(const Duration(days: 10)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 10, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_1',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        responses: {
          'user_1': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_2': EventResponse(status: 'NO', timestamp: DateTime.now()),
        },
      ),
      BandEvent(
        id: 'ev_2',
        title: 'Old Rehearsal Session',
        eventType: 'Rehearsal',
        location: 'Studio A',
        description: 'Tutti practice',
        startDateTime: DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
        endDateTime: DateTime.now().subtract(const Duration(days: 5, hours: -2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_1',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        responses: {},
      ),
    ],
    'band_2': [
      BandEvent(
        id: 'ev_3',
        title: 'Club Night Gig',
        eventType: 'Club gig',
        location: 'Debaser, Stockholm',
        description: 'Club gig night',
        startDateTime: DateTime.now().add(const Duration(days: 15)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 15, hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_2',
        createdAt: 0,
        updatedAt: 0,
        requireResponse: true,
        responses: {},
      ),
    ],
  };

  String? deletedEventBandId;
  String? deletedEventId;

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return Map<String, String>.from(userBands);
  }

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return bandRoles[bandId] ?? 'member';
  }

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value(bandEvents[bandId] ?? []);
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return bandEvents[bandId] ?? [];
  }

  @override
  Future<void> deleteBandEventAsync(String bandId, String eventId) async {
    deletedEventBandId = bandId;
    deletedEventId = eventId;
    bandEvents[bandId]?.removeWhere((e) => e.id == eventId);
  }
}

class MockAppStateForManageEvents extends Fake with ChangeNotifier implements AppState {
  final MockFirebaseServiceForManageEvents mockFirebase = MockFirebaseServiceForManageEvents();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => 'user_1';

  @override
  String? get activeBandId => 'band_1';

  @override
  String? get activeBandName => 'Mats Testband 26';

  @override
  UserProfile? get currentUserProfile => null;

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  List<String> get selectedBubbles => ['find_musicians', 'band_room', 'create_event'];

  @override
  void selectBand(String bandId, String bandName) {}
}

Widget createTestWrapper({required MockAppStateForManageEvents appState, required Widget child}) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Manage Events Feature Tests', () {
    testWidgets('1. GlobalCreateEventLauncher bottom sheet displays Create Event, Create Session, and Manage Events', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForManageEvents();

      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GlobalCreateEventLauncher.showLauncherSheet(context, appState),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify all 3 options are present
      expect(find.text('EVENTS & SESSIONS'), findsOneWidget);
      expect(find.text('Create Event'), findsOneWidget);
      expect(find.text('Create Session'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('View, edit, track RSVPs & manage your events...'), findsOneWidget);
    });

    testWidgets('2. ManageEventsScreen displays upcoming events, band chips, search bar, and RSVP stats', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForManageEvents();

      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const ManageEventsScreen(),
      ));
      await tester.pumpAndSettle();

      // Header title
      expect(find.text('MANAGE EVENTS'), findsOneWidget);

      // Search bar
      expect(find.byType(TextField), findsOneWidget);

      // Tabs
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('PAST EVENTS'), findsOneWidget);

      // Upcoming event title for band 1
      expect(find.text('Summer Arena Concert'), findsOneWidget);
      expect(find.text('1 Yes'), findsOneWidget);
      expect(find.text('1 No'), findsOneWidget);

      // RSVPs and View Event buttons
      expect(find.text('RSVPs'), findsWidgets);
      expect(find.text('View Event'), findsWidgets);
    });

    testWidgets('3. ManageEventsScreen switching to Past Events tab shows past events', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForManageEvents();

      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const ManageEventsScreen(),
      ));
      await tester.pumpAndSettle();

      // Tap PAST EVENTS tab
      await tester.tap(find.text('PAST EVENTS'));
      await tester.pumpAndSettle();

      // Verify past event is visible
      expect(find.text('Old Rehearsal Session'), findsOneWidget);
    });

    testWidgets('4. ManageEventsScreen filter search narrows down displayed events', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForManageEvents();

      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const ManageEventsScreen(),
      ));
      await tester.pumpAndSettle();

      final searchFinder = find.byType(TextField).first;

      // Search for 'Arena'
      await tester.enterText(searchFinder, 'Arena');
      await tester.pumpAndSettle();

      expect(find.text('Summer Arena Concert'), findsOneWidget);

      // Search for nonexistent event
      await tester.enterText(searchFinder, 'Nonexistent Gig');
      await tester.pumpAndSettle();

      expect(find.text('Summer Arena Concert'), findsNothing);
      expect(find.text('No events match "Nonexistent Gig".'), findsOneWidget);
    });
  });
}
