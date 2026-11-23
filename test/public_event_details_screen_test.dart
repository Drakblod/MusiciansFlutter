// ignore_for_file: depend_on_referenced_packages

import 'support/bounded_ui_pump.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_database_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/calendar_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_details_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SpyingPublicEventRepository implements PublicEventRepository {
  final List<String> deletedEventIds = [];
  final List<PublicCalendarEvent> updatedEvents = [];

  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async => [];

  @override
  Future<String> createEvent(PublicCalendarEvent event) async => event.id;

  @override
  Future<void> updateEvent(PublicCalendarEvent event) async {
    updatedEvents.add(event);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    deletedEventIds.add(eventId);
  }
}

class SpyingFirebaseService extends FirebaseService {
  int callCount = 0;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    callCount++;
    return UserProfile(userId: 'u1', displayName: 'Test User');
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    callCount++;
    return {'b1': 'Test Band'};
  }

  @override
  Future<List<PublicCalendarEvent>> getPublicCalendarEventsAsync() async => [];

  @override
  Future<String> savePublicCalendarEventAsync(PublicCalendarEvent event) async => event.id;
}

class MockAppStateForDetailsTest extends AppState {
  final FirebaseService spyService;

  MockAppStateForDetailsTest(this.spyService);

  @override
  FirebaseService get firebaseService => spyService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_1',
        displayName: 'Test Musician',
        email: 'test@example.com',
      );

  @override
  String? get currentUserId => 'test_user_1';

  @override
  List<String> get selectedBubbles => [
        'event_calendar',
        'band_room',
        'create_event',
      ];
}

class CalendarOwnerFirebaseService extends FirebaseService {
  @override
  String get currentUserId => 'test_user_1';

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => {};
}

class CalendarDatabaseFixture {
  final Map<String, Object?> records;
  final String publicPath;
  final String ownerPath;
  String? rejectedPath;
  String rejection = 'unavailable';
  int writes = 0;

  CalendarDatabaseFixture(WidgetTester tester, PublicCalendarEvent event)
      : publicPath = 'PublicEvents/${event.id}',
        ownerPath = 'users/${event.createdBy}/PublicEvents/${event.id}',
        records = {
          'PublicEvents/${event.id}': event.toJson(),
          'users/${event.createdBy}/PublicEvents/${event.id}': event.toJson(),
        } {
    const host = 'dev.flutter.pigeon.firebase_database_platform_interface.FirebaseDatabaseHostApi';
    const codec = FirebaseDatabaseHostApi.pigeonChannelCodec;
    final messenger = tester.binding.defaultBinaryMessenger;
    const query = BasicMessageChannel<Object?>('$host.queryGet', codec);
    const set = BasicMessageChannel<Object?>('$host.databaseReferenceSet', codec);
    const update = BasicMessageChannel<Object?>('$host.databaseReferenceUpdate', codec);

    messenger.setMockDecodedMessageHandler<Object?>(query, (message) async {
      final request = (message as List)[1] as QueryRequest;
      final path = request.path.replaceFirst(RegExp(r'^/'), '');
      final value = <String, Object?>{
        for (final entry in records.entries)
          if (entry.key.startsWith('$path/')) entry.key.substring(path.length + 1): entry.value,
      };
      return [{'snapshot': {'key': path.split('/').last, 'value': value.isEmpty ? null : value}}];
    });
    messenger.setMockDecodedMessageHandler<Object?>(set, (message) async {
      final request = (message as List)[1] as DatabaseReferenceRequest;
      return _write({request.path.replaceFirst(RegExp(r'^/'), ''): request.value});
    });
    messenger.setMockDecodedMessageHandler<Object?>(update, (message) async {
      final request = (message as List)[1] as UpdateRequest;
      expect(request.path, '/');
      return _write(request.value);
    });
    addTearDown(() {
      for (final channel in [query, set, update]) {
        messenger.setMockDecodedMessageHandler<Object?>(channel, null);
      }
    });
  }

  List<Object?> _write(Map<String, Object?> values) {
    writes++;
    expect(values.keys, everyElement(isIn([publicPath, ownerPath])));
    if (values.containsKey(rejectedPath)) {
      return [rejection, 'Synthetic write failure', {'code': rejection}];
    }
    for (final entry in values.entries) {
      if (entry.value == null) {
        records.remove(entry.key);
      } else {
        records[entry.key] = entry.value;
      }
    }
    return [null];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testEvent = PublicCalendarEvent(
    id: 'mock_test_1',
    createdBy: 'test_user_1',
    title: 'Stockholm Jazz Night',
    eventType: PublicEventType.liveGig,
    organizerName: 'Stockholm Jazz Collective',
    venueName: 'Jazzbaren',
    city: 'Stockholm',
    address: 'Jazzgränd 4 (Demo Venue), Gamla Stan',
    startDateTime: DateTime(2026, 8, 27, 20, 0),
    endDateTime: DateTime(2026, 8, 27, 23, 0),
    genres: const ['Jazz', 'Swing'],
    priceAmount: 150,
    currency: 'SEK',
    isFree: false,
    shortDescription: 'Short desc',
    description: 'Full jazz description text for testing details rendering.',
    status: PublicEventStatus.published,
    isMock: true,
  );

  final testFreeEvent = PublicCalendarEvent(
    id: 'mock_test_2',
    title: 'Open Co-writing Session',
    eventType: PublicEventType.openSession,
    organizerName: 'West Coast Songwriters',
    venueName: 'Song Lab Göteborg',
    city: 'Göteborg',
    address: 'Musikgatan 12 (Demo Studio), Majorna',
    startDateTime: DateTime(2026, 9, 3, 18, 30),
    endDateTime: DateTime(2026, 9, 3, 21, 30),
    genres: const ['Pop', 'Songwriting'],
    priceAmount: null,
    currency: 'SEK',
    isFree: true,
    shortDescription: 'Short desc',
    description: 'Full songwriting session description.',
    status: PublicEventStatus.published,
    isMock: true,
  );

  group('Calendar edit and delete persistence', () {
    final now = DateTime(2030, 8, 28, 20);
    final event = testEvent.copyWith(
      id: 'public-test-event',
      isMock: false,
      startDateTime: now.subtract(const Duration(hours: 2)),
      endDateTime: now.add(const Duration(hours: 2)),
    );

    Future<void> mountCalendar(WidgetTester tester) async {
      final service = CalendarOwnerFirebaseService();
      final repo = FirebasePublicEventRepository(firebaseService: service, includeMock: false);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>(
        create: (_) => MockAppStateForDetailsTest(service),
        child: MaterialApp(
          routes: {'/public-event-details': (_) => PublicEventDetailsScreen(repository: repo)},
          home: PublicEventCalendarScreen(repository: repo, clock: () => now),
        ),
      ));
      await pumpUiTransitions(tester);
    }

    Future<void> openDetails(WidgetTester tester) async {
      await tester.tap(find.text(event.title));
      await pumpUiTransitions(tester);
      expect(find.byType(PublicEventDetailsScreen), findsOneWidget);
    }

    Future<void> saveEdit(WidgetTester tester) async {
      final save = find.text('Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await pumpUiTransitions(tester);
    }

    Future<void> confirmDelete(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await pumpUiTransitions(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
      await pumpUiTransitions(tester);
    }

    void useLargeViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('Event edit refreshes the open calendar when returning with the header arrow', (tester) async {
      useLargeViewport(tester);
      final upcoming = event.copyWith(startDateTime: now.add(const Duration(hours: 1)));
      final store = CalendarDatabaseFixture(tester, upcoming);
      await mountCalendar(tester);
      await openDetails(tester);
      await tester.tap(find.text('Edit'));
      await pumpUiTransitions(tester);
      await tester.enterText(find.widgetWithText(TextFormField, event.title), 'Updated calendar title');
      await tester.enterText(find.widgetWithText(TextFormField, event.description), 'Updated calendar description');
      await saveEdit(tester);
      expect((store.records[store.publicPath] as Map)['description'], 'Updated calendar description');
      expect(find.text('Updated calendar description'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await pumpUiTransitions(tester);
      expect(find.byType(PublicEventCalendarScreen), findsOneWidget);
      expect(find.text('Updated calendar title'), findsOneWidget);
      expect(find.text(event.title), findsNothing);
      expect(store.records[store.publicPath], store.records[store.ownerPath]);
      expect(store.writes, 1);
    });

    testWidgets('Title-only edit preserves the actual end date and keeps the event visible', (tester) async {
      useLargeViewport(tester);
      final scheduled = event.copyWith(
        startDateTime: now.subtract(const Duration(days: 1, hours: 2, seconds: 9)).toUtc(),
        endDateTime: now.add(const Duration(hours: 2, seconds: 7)).toUtc(),
      );
      final store = CalendarDatabaseFixture(tester, scheduled);
      await mountCalendar(tester);
      await tester.tap(find.byTooltip('Edit Event'));
      await pumpUiTransitions(tester);
      await tester.enterText(find.widgetWithText(TextFormField, event.title), 'Same event schedule');
      await saveEdit(tester);

      final saved = PublicCalendarEvent.fromJson(store.records[store.publicPath] as Map);
      expect(saved.startDateTime, scheduled.startDateTime);
      expect(saved.endDateTime, scheduled.endDateTime);
      expect(find.text('Same event schedule'), findsOneWidget);
    });

    testWidgets('The public copy takes precedence over a stale owner copy', (tester) async {
      useLargeViewport(tester);
      final store = CalendarDatabaseFixture(tester, event);
      store.records[store.ownerPath] = event.copyWith(title: 'Stale title').toJson();
      await mountCalendar(tester);
      expect(find.text(event.title), findsOneWidget);
      expect(find.text('Stale title'), findsNothing);
    });

    for (final storedType in ['live_gig', 'Recording Session', null]) {
      testWidgets('Editing text preserves the stored event type $storedType', (tester) async {
        useLargeViewport(tester);
        final store = CalendarDatabaseFixture(tester, event);
        final legacy = event.toJson();
        if (storedType == null) {
          legacy.remove('eventType');
        } else {
          legacy['eventType'] = storedType;
        }
        store.records[store.publicPath] = legacy;
        store.records[store.ownerPath] = legacy;
        await mountCalendar(tester);
        await tester.tap(find.byTooltip('Edit Event'));
        await pumpUiTransitions(tester);
        await tester.enterText(find.widgetWithText(TextFormField, event.title), 'Updated legacy event');
        await tester.enterText(find.widgetWithText(TextFormField, event.description), 'Updated legacy description');
        await saveEdit(tester);

        final saved = store.records[store.publicPath] as Map;
        expect(saved.containsKey('eventType'), storedType != null);
        expect(saved['eventType'], storedType);
        expect(saved['description'], 'Updated legacy description');
        expect(store.records[store.ownerPath], saved);
        expect(find.text('Updated legacy event'), findsOneWidget);
      });
    }

    testWidgets('An explicit type change persists and displays the selected calendar type', (tester) async {
      useLargeViewport(tester);
      final store = CalendarDatabaseFixture(tester, event);
      final legacy = event.toJson()..['eventType'] = 'live_gig';
      store.records[store.publicPath] = legacy;
      store.records[store.ownerPath] = legacy;
      await mountCalendar(tester);
      await tester.tap(find.byTooltip('Edit Event'));
      await pumpUiTransitions(tester);
      await tester.tap(find.text('Workshop'));
      await pumpUiTransitions(tester);
      await saveEdit(tester);

      final saved = store.records[store.publicPath] as Map;
      expect(saved['eventType'], 'workshopCourse');
      expect(store.records[store.ownerPath], saved);
      final reloaded = PublicCalendarEvent.fromJson(saved);
      expect(EventCalendarCategories.matches(reloaded, EventCalendarCategories.workshops), isTrue);
      expect(EventCalendarCategories.matches(reloaded, EventCalendarCategories.liveGigs), isFalse);
      await openDetails(tester);
      expect(find.text('Workshop/Course'), findsOneWidget);
    });

    testWidgets('A title edit does not add a synthetic end to a legacy event', (tester) async {
      useLargeViewport(tester);
      final legacyJson = event.copyWith(startDateTime: now.add(const Duration(hours: 1))).toJson()
        ..remove('endDateTime');
      final store = CalendarDatabaseFixture(tester, PublicCalendarEvent.fromJson(legacyJson));
      await mountCalendar(tester);
      await tester.tap(find.byTooltip('Edit Event'));
      await pumpUiTransitions(tester);
      await tester.enterText(find.widgetWithText(TextFormField, event.title), 'Updated legacy title');
      await saveEdit(tester);
      expect(find.text('Updated legacy title'), findsOneWidget);
      expect((store.records[store.publicPath] as Map).containsKey('endDateTime'), isFalse);
      expect(store.records[store.ownerPath], store.records[store.publicPath]);
    });

    testWidgets('Moving the end before the calendar clock hides the card but preserves the record', (tester) async {
      useLargeViewport(tester);
      final store = CalendarDatabaseFixture(tester, event);
      await mountCalendar(tester);
      await tester.tap(find.byTooltip('Edit Event'));
      await pumpUiTransitions(tester);
      await tester.tap(find.widgetWithText(ListTile, 'End Time'));
      await pumpUiTransitions(tester);
      Navigator.of(tester.element(find.byType(TimePickerDialog))).pop(const TimeOfDay(hour: 19, minute: 0));
      await pumpUiTransitions(tester);
      await saveEdit(tester);

      expect(find.byType(PublicEventCalendarScreen), findsOneWidget);
      expect(find.text(event.title), findsNothing);
      final saved = PublicCalendarEvent.fromJson(store.records[store.publicPath] as Map);
      expect(saved.endDateTime, now.subtract(const Duration(hours: 1)));
      expect(saved.status, PublicEventStatus.published);
      expect(store.records[store.ownerPath], store.records[store.publicPath]);
    });

    testWidgets('Delete removes the event from the open calendar and a fresh load', (tester) async {
      useLargeViewport(tester);
      final store = CalendarDatabaseFixture(tester, event);
      await mountCalendar(tester);
      await openDetails(tester);
      await confirmDelete(tester);

      expect(find.byType(PublicEventCalendarScreen), findsOneWidget);
      expect(find.text(event.title), findsNothing);
      expect(store.records, isEmpty);
      expect(store.writes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountCalendar(tester);
      expect(find.text(event.title), findsNothing);
    });

    for (final error in ['permission-denied', 'unavailable']) {
      testWidgets('Edit rejection $error keeps the original event and reports failure', (tester) async {
        useLargeViewport(tester);
        final store = CalendarDatabaseFixture(tester, event)
          ..rejectedPath = 'PublicEvents/${event.id}'
          ..rejection = error;
        await mountCalendar(tester);
        await tester.tap(find.byTooltip('Edit Event'));
        await pumpUiTransitions(tester);
        await tester.enterText(find.widgetWithText(TextFormField, event.title), 'Rejected title');
        await saveEdit(tester);

        expect(find.textContaining('Failed to save event'), findsOneWidget);
        expect(find.textContaining('updated successfully'), findsNothing);
        expect(store.records[store.publicPath], event.toJson());
        expect(store.records[store.ownerPath], event.toJson());
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await pumpUiTransitions(tester);
        expect(find.text(event.title), findsOneWidget);
      });

      testWidgets('Delete rejection $error keeps both copies and reports failure', (tester) async {
        useLargeViewport(tester);
        final store = CalendarDatabaseFixture(tester, event)
          ..rejectedPath = 'users/${event.createdBy}/PublicEvents/${event.id}'
          ..rejection = error;
        await mountCalendar(tester);
        await openDetails(tester);
        await confirmDelete(tester);

        expect(find.textContaining('Failed to delete event'), findsOneWidget);
        expect(find.textContaining('deleted.'), findsNothing);
        expect(find.byType(PublicEventDetailsScreen), findsOneWidget);
        expect(store.records[store.publicPath], event.toJson());
        expect(store.records[store.ownerPath], event.toJson());
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await pumpUiTransitions(tester);
        expect(find.text(event.title), findsOneWidget);
      });
    }
  });

  Widget createDetailsTestWidget({
    PublicCalendarEvent? event,
    Object? routeArgument,
    PublicEventRepository? repository,
  }) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockAppStateForDetailsTest(SpyingFirebaseService()),
      child: MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == '/public-event-details') {
            final arg = settings.arguments is PublicCalendarEvent
                ? settings.arguments as PublicCalendarEvent
                : null;
            return MaterialPageRoute(
              builder: (context) => PublicEventDetailsScreen(
                event: arg,
                repository: repository,
              ),
              settings: settings,
            );
          }
          if (settings.name == '/event-calendar') {
            return MaterialPageRoute(
              builder: (context) => const PublicEventCalendarScreen(),
              settings: settings,
            );
          }
          if (settings.name == '/calendar') {
            return MaterialPageRoute(
              builder: (context) => const CalendarScreen(bandId: 'b1'),
              settings: settings,
            );
          }
          return null;
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/public-event-details',
                    arguments: routeArgument ?? event,
                  );
                },
                child: const Text('Open Details'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('PublicEventDetailsScreen & Integration Tests', () {
    testWidgets('1. Renders all details fields, genres and price without a production demo badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testEvent));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('DEMO EVENT'), findsNothing);
      expect(find.text('Live/Gig'), findsOneWidget);
      expect(find.text('Stockholm Jazz Collective'), findsOneWidget);
      expect(find.text('Jazzbaren, Stockholm'), findsOneWidget);
      expect(find.text('Jazzgränd 4 (Demo Venue), Gamla Stan'), findsOneWidget);
      expect(find.text('150 SEK'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('Swing'), findsOneWidget);
      expect(find.text('Full jazz description text for testing details rendering.'), findsOneWidget);
      expect(find.text('Back to Calendar'), findsOneWidget);
    });

    testWidgets('2. Free event displays Free in price badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testFreeEvent));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Song Lab Göteborg, Göteborg'), findsOneWidget);
    });

    testWidgets('2b. Event with imageUrl displays cover image widget', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final eventWithImage = testEvent.copyWith(imageUrl: 'https://example.com/test_cover.jpg');
      await tester.pumpWidget(createDetailsTestWidget(event: eventWithImage));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.image(const NetworkImage('https://example.com/test_cover.jpg')), findsOneWidget);
    });

    testWidgets('3. Invalid navigation argument gracefully displays fallback without crashing', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(routeArgument: 'invalid_string_argument'));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.text('Event Not Found'), findsOneWidget);
      expect(find.text('The requested event could not be loaded.'), findsOneWidget);
    });

    testWidgets('4. Back to Calendar button pops details view', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createDetailsTestWidget(event: testEvent));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);

      await tester.tap(find.text('Back to Calendar'));
      await pumpUiTransitions(tester);

      expect(find.text('Open Details'), findsOneWidget);
    });

    testWidgets('4b. Delete button shows confirmation dialog and Cancel retains view', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyRepo = SpyingPublicEventRepository();
      await tester.pumpWidget(createDetailsTestWidget(event: testEvent, repository: spyRepo));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpUiTransitions(tester);

      // Dialog is displayed
      expect(find.text('Delete Event'), findsOneWidget);
      expect(find.text('Are you sure you want to delete "Stockholm Jazz Night"? This action cannot be undone.'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await pumpUiTransitions(tester);

      expect(find.text('Delete Event'), findsNothing);
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(spyRepo.deletedEventIds, isEmpty);
    });

    testWidgets('4c. Confirming Delete calls repository.deleteEvent and pops view', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyRepo = SpyingPublicEventRepository();
      await tester.pumpWidget(createDetailsTestWidget(event: testEvent, repository: spyRepo));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Delete'));
      await pumpUiTransitions(tester);

      // Tap Delete in dialog (there are two Delete texts: one on the button and one on the dialog)
      final dialogDeleteBtn = find.widgetWithText(ElevatedButton, 'Delete');
      expect(dialogDeleteBtn, findsOneWidget);
      await tester.tap(dialogDeleteBtn);
      await pumpUiTransitions(tester);

      expect(spyRepo.deletedEventIds, contains('mock_test_1'));
      expect(find.text('Event "Stockholm Jazz Night" deleted.'), findsOneWidget);
      expect(find.text('Open Details'), findsOneWidget);
    });

    testWidgets('4d. Tapping Edit opens CreatePublicEventScreen and updates event on save', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final creatorEvent = testEvent.copyWith(createdBy: 'test_user_1');
      final spyRepo = SpyingPublicEventRepository();
      await tester.pumpWidget(createDetailsTestWidget(event: creatorEvent, repository: spyRepo));
      await pumpUiTransitions(tester);

      await tester.tap(find.text('Open Details'));
      await pumpUiTransitions(tester);

      // Find Edit button
      final editBtn = find.text('Edit');
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await pumpUiTransitions(tester);

      // Check edit screen is shown with pre-populated values
      expect(find.text('EDIT EVENT'), findsOneWidget);
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Modify the title
      final titleField = find.widgetWithText(TextFormField, 'Stockholm Jazz Night');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'Stockholm Jazz & Blues');
      await pumpUiTransitions(tester);

      // Save changes
      await tester.tap(find.text('Save Changes'));
      await pumpUiTransitions(tester);

      // Verify updateEvent was called on repository
      expect(spyRepo.updatedEvents, isNotEmpty);
      expect(spyRepo.updatedEvents.last.title, equals('Stockholm Jazz & Blues'));

      // Verify details view immediately reflects updated title
      expect(find.text('Stockholm Jazz & Blues'), findsOneWidget);
    });

    testWidgets('5. Home View Event Calendar button navigates to /event-calendar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForDetailsTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: MaterialApp(
            routes: {
              '/event-calendar': (context) => const PublicEventCalendarScreen(),
              '/public-event-details': (context) => const PublicEventDetailsScreen(),
              '/calendar': (context) => const CalendarScreen(bandId: 'b1'),
            },
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final eventCalendarAction = find.text('Event Calendar');
      expect(eventCalendarAction, findsOneWidget);

      await tester.tap(eventCalendarAction);
      await pumpUiTransitions(tester);

      expect(find.text('EVENT CALENDAR'), findsOneWidget);
      expect(find.text('Discover live music, sessions, workshops and more.'), findsOneWidget);
      expect(find.text('DEMO EVENTS'), findsNothing);
    });

    testWidgets('6. Existing /calendar route resolves to private CalendarScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForDetailsTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => appState,
          child: MaterialApp(
            routes: {
              '/calendar': (context) => const CalendarScreen(bandId: 'b1'),
            },
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/calendar', arguments: 'b1'),
                    child: const Text('Open Band Calendar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Open Band Calendar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CalendarScreen), findsOneWidget);
    });
  });
}
