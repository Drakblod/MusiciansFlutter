import 'dart:async';

import 'tab_label_expectations.dart';
import 'support/bounded_ui_pump.dart';
import 'package:musicians_flutter/utils/band_membership_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/event_room.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/event_results_page.dart';
import 'package:musicians_flutter/views/manage_events_screen.dart';
import 'package:musicians_flutter/widgets/rsvp_reminder_dialog.dart';

class MockGigsInfoFirebaseService extends FirebaseService {
  @override
  Future<Band?> getPublicBandProfileAsync(String bandId) => getBandInfoAsync(bandId);
  @override
  Future<UserProfile?> getPublicUserProfileAsync(String uid) => getUserProfileAsync(uid);

  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async => {};

  @override
  Future<BandEvent?> getManagerBandEventOnceAsync(String bandId, String eventId) async => await subscribeToBandEvent(bandId, eventId).first;
  @override
  Future<List<BandEvent>> getManagerBandEventsListAsync(String bandId) => getBandEventsListAsync(bandId);
  @override
  Stream<BandEvent?> subscribeToManagerBandEvent(String bandId, String eventId) => subscribeToBandEvent(bandId, eventId);
  @override
  Future<bool> canManageBandEventAsync(String bandId) async => BandMembershipPolicy.canStaff(await getBandInfoAsync(bandId), currentUserId);

  @override
  bool get isLoggedIn => true;
  @override
  String? get currentUserId => 'leader_1';
  @override
  Future<void> initializePushNotifications() async {}

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => {'band_feed_test': 'Rock Band'};

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async => 'Leader';

  BandEvent? testEvent;
  List<BandEvent> testEventsList = [];
  List<BandMember> testMembers = [];
  Map<String, Map<String, String>> testFiles = {};
  List<Map<String, dynamic>> testPosts = [];
  final postedNews = <Map<String, dynamic>>[];
  final deletedNews = <(String, String)>[];
  final List<Map<String, String>> updatedResponses = [];
  StreamController<List<BandEvent>>? eventUpdates;
  bool denyRsvpWrite = false;

  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) async* {
    yield testEventsList.isNotEmpty ? testEventsList : [if (testEvent != null) testEvent!];
    final updates = eventUpdates;
    if (updates != null) yield* updates.stream;
  }

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) =>
      subscribeToBandEvents(bandId).map(
        (events) => events.where((event) => event.id == eventId).firstOrNull,
      );

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    if (denyRsvpWrite) throw StateError('write denied');
    updatedResponses.add({
      'bandId': bandId,
      'eventId': eventId,
      'userId': userId,
      'response': status,
    });
    final updates = eventUpdates;
    if (updates != null) {
      testEventsList = [
        for (final event in testEventsList)
          if (event.id == eventId)
            BandEvent.fromJson({
              ...event.toJson(),
              'Responses': {
                ...event.toJson()['Responses'] as Map,
                userId: EventResponse(status: status, timestamp: DateTime.now()).toJson(),
              },
            }, eventId)
          else
            event,
      ];
      updates.add(testEventsList);
    }
  }

  @override
  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) {
    return Stream.value(testPosts);
  }

  @override
  Future<void> postGigsNewsAsync(String bandId, Map<String, dynamic> data) async {
    postedNews.add({'bandId': bandId, ...data});
  }

  @override
  Future<void> deleteGigsNewsAsync(String bandId, String postId) async {
    deletedNews.add((bandId, postId));
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: 'Rock Band',
      membersBand: {'leader_1': BandMember(userId: 'leader_1', role: 'Leader')},
      description: 'Test Band',
    );
  }

  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    return testFiles;
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return testMembers;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return testEventsList.isNotEmpty ? testEventsList : [if (testEvent != null) testEvent!];
  }

  @override
  Future<Map<String, SubstituteAssignment>> getSubstituteAssignmentsAsync(
    String bandId,
    String eventId,
  ) async {
    return {};
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: userId ?? 'u1', displayName: 'Musician $userId');
  }
}

class MockGigsInfoAppState extends AppState {
  final MockGigsInfoFirebaseService mockFirebase;

  MockGigsInfoAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get activeBandId => 'band_feed_test';

  @override
  String? get activeBandName => 'Rock Band';

  @override
  String? get currentUserId => 'leader_1';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'leader_1',
        displayName: 'Leader Musician',
      );
}

Future<void> initializeBandRoomTestFirebase() async {
  setupFirebaseCoreMocks();
  await Firebase.initializeApp();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeBandRoomTestFirebase);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final offset in [-1, 0, 1]) {
    testWidgets('Band Room reminder at $offset ms from the RSVP deadline', (tester) async {
      final deadline = DateTime.utc(2027, 1, 1, 12);
      final now = deadline.add(Duration(milliseconds: offset));
      final service = MockGigsInfoFirebaseService()
        ..testEvent = _event(now, 'deadline_event', 'Upcoming concert', 1,
          rsvpDeadline: deadline.millisecondsSinceEpoch);

      await _mountBandRoom(tester, service, clock: () => now);

      expect(find.byType(RsvpReminderDialog), offset < 0 ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('Files tab and upload picker relabel the legacy audio category', (tester) async {
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MockGigsInfoFirebaseService()
      ..testFiles = {
        'audio': {'FileName': 'rehearsal.aiff', 'Category': 'MP3s'},
      };
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => MockGigsInfoAppState(service),
        child: const MaterialApp(home: BandRoomChatScreen()),
      ),
    );
    await pumpUiTransitions(tester);
    await tester.tap(find.text('Files'));
    await pumpUiTransitions(tester);
    expect(find.text('MP3, WAV, AIFF… (1)'), findsOneWidget);
    expect(find.text('rehearsal.aiff'), findsOneWidget);
    expect(find.text('MP3s (1)'), findsNothing);

    await tester.tap(find.text('Upload a File'));
    await pumpUiTransitions(tester);
    expect(find.text('MP3, WAV, AIFF…'), findsOneWidget);
    expect(find.text('MP3s / Audio'), findsNothing);
  });

  testWidgets('Events opens manager RSVP results for the exact event', (tester) async {
    final now = DateTime.now();
    final service = MockGigsInfoFirebaseService()
      ..testMembers = [
        BandMember(userId: 'leader_1', nickname: 'Leader', role: 'Leader'),
        BandMember(userId: 'u2', nickname: 'Bassist', role: 'Member'),
        BandMember(userId: 'u3', nickname: 'Drummer', role: 'Member'),
      ]
      ..testEvent = _event(now, 'event_1', 'Summer Fest Gig', 3, responses: {
        'u3': EventResponse(status: 'YES', timestamp: now),
        'u2': EventResponse(status: 'declined', timestamp: now),
      });

    await _mountBandRoom(tester, service);
    tester.view.physicalSize = const Size(320, 2400);
    await tester.pump();
    expectVisibleTabLabels(tester, ['Chat', 'Files', 'Events', 'News', 'Members']);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 2400);
    await tester.pump();

    await _dismissReminder(tester);
    await _tapBandRoom(tester, find.widgetWithText(Tab, 'Events'));
    expect(find.byType(ManageEventsScreen), findsOneWidget);
    expect(find.text('”Summer Fest Gig”'), findsOneWidget);
    expect(find.text('Main Stage'), findsOneWidget);
    expect(find.text('Concert'), findsOneWidget);

    await _tapBandRoom(tester, find.text('RSVPs'));
    final results = tester.widget<EventResultsPage>(find.byType(EventResultsPage));
    expect(results.bandId, 'band_feed_test');
    expect(results.eventId, 'event_1');
    expect(find.text('ATTENDANCE RESPONSES'), findsOneWidget);
    expect(find.textContaining('YES (1)'), findsOneWidget);
    expect(find.textContaining('NO (1)'), findsOneWidget);
    expect(find.textContaining('UNCERTAIN (0)'), findsOneWidget);
    expect(find.textContaining('NO ANSWER (1)'), findsOneWidget);
  });

  testWidgets('News shows posts directly, keeps linked gigs and preserves post actions', (tester) async {
    final now = DateTime.now();
    final service = MockGigsInfoFirebaseService()
      ..testMembers = [
        BandMember(userId: 'leader_1', nickname: 'Leader', role: 'Leader'),
      ]
      ..testEvent = _event(now, 'gig_event', 'Summer Fest Gig', 3, requireResponse: false)
      ..testPosts = [
        {
          'id': 'regular_post',
          'title': 'Rehearsal update',
          'content': 'Rehearsal moved to Studio B.',
          'timestamp': 1000,
        },
        {
          'id': 'linked_gig',
          'type': 'Gig',
          'title': 'Sub needed for Summer Fest',
          'content': 'Looking for a bass substitute.',
          'eventId': 'gig_event',
          'timestamp': 2000,
        },
      ];
    await _mountBandRoom(tester, service);
    await _tapBandRoom(tester, find.widgetWithText(Tab, 'News'));

    expect(find.text('Rehearsal update'), findsOneWidget);
    expect(find.text('Rehearsal moved to Studio B.'), findsOneWidget);
    expect(find.text('Sub needed for Summer Fest'), findsOneWidget);
    expect(find.text('Looking for a bass substitute.'), findsOneWidget);
    expect(find.text('GIG'), findsOneWidget);
    expect(find.text('NEWS'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sub needed for Summer Fest')).dy,
      lessThan(tester.getTopLeft(find.text('Rehearsal update')).dy),
    );
    expect(find.textContaining('”Summer Fest Gig”'), findsNothing);
    expect(find.text('Other'), findsNothing);
    expect(find.text('Events'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Events'), findsOneWidget);
    expect(find.textContaining('New Events', findRichText: true), findsNothing);
    expect(find.text('Upcoming (Finalized)'), findsNothing);
    expect(find.text('Past Events'), findsNothing);
    expect(find.text('No posts or updates found.'), findsNothing);

    await _tapBandRoom(tester, find.text('Create Post / Update'));
    expect(find.text('POST GIG / NEWS'), findsOneWidget);
    expect(find.text('News Update'), findsOneWidget);
    expect(find.text('Gig / Event'), findsOneWidget);
    expect(find.text('Gig / Booking'), findsNothing);
    await _tapBandRoom(tester, find.text('Gig / Event'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Rehearsal Update or Gig Event'),
      'Venue update',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Provide all the details for the members...'),
      'Use the stage entrance.',
    );
    await _tapBandRoom(tester, find.text('Post'));
    expect(service.postedNews, [{
      'bandId': 'band_feed_test',
      'title': 'Venue update',
      'content': 'Use the stage entrance.',
      'type': 'Gig',
      'authorName': 'Leader Musician',
    }]);

    final delete = find.widgetWithIcon(IconButton, Icons.delete_outline_rounded).first;
    await _tapBandRoom(tester, delete);
    expect(find.text('Delete Post?'), findsOneWidget);
    await _tapBandRoom(tester, find.text('Cancel'));
    expect(service.deletedNews, isEmpty);
    await _tapBandRoom(tester, delete);
    await _tapBandRoom(tester, find.text('Delete'));
    expect(service.deletedNews, [('band_feed_test', 'linked_gig')]);

    await _tapBandRoom(tester, find.widgetWithText(Tab, 'Chat'));
    expect(find.byKey(const ValueKey('band-room-groups')), findsOneWidget);
    expect(find.text('New Group'), findsOneWidget);
    expect(find.text('Type a message...'), findsOneWidget);
  });

  testWidgets('Empty News shows its empty state without manager actions for a member', (tester) async {
    final service = MockGigsInfoFirebaseService()
      ..testMembers = [BandMember(userId: 'leader_1', role: 'Member')];
    await _mountBandRoom(tester, service);
    await _tapBandRoom(tester, find.widgetWithText(Tab, 'News'));

    expect(find.text('No posts or updates found.'), findsOneWidget);
    expect(find.text('Create Post / Update'), findsNothing);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('Events keeps unanswered and answered RSVPs after save, failure and reload', (tester) async {
    final now = DateTime.now();
    final updates = StreamController<List<BandEvent>>.broadcast();
    addTearDown(updates.close);
    final service = MockGigsInfoFirebaseService()
      ..eventUpdates = updates
      ..testMembers = [
        BandMember(userId: 'leader_1', nickname: 'Leader', role: 'Leader'),
        BandMember(userId: 'u2', nickname: 'Member', role: 'Member'),
      ]
      ..testEventsList = [
        _event(now, 'far', 'Later Gig', 7, responses: {
          'leader_1': EventResponse(status: 'Yes', timestamp: now),
        }),
        _event(now, 'near', 'Sooner Gig', 2),
        _event(now, 'past_older', 'Past Older Event', -10),
        _event(now, 'past_newer', 'Past Newer Event', -2),
        _event(now, 'finalized', 'Finalized Event', 3, requireResponse: false),
      ];
    await _mountBandRoom(tester, service);
    await _dismissReminder(tester);
    final eventsTab = find.widgetWithText(Tab, 'Events');
    await _tapBandRoom(tester, eventsTab);

    final sooner = find.text('”Sooner Gig”');
    final later = find.text('”Later Gig”');
    expect(sooner, findsOneWidget);
    expect(later, findsOneWidget);
    expect(tester.getTopLeft(sooner).dy, lessThan(tester.getTopLeft(later).dy));
    expect(find.text('Save RSVP'), findsNothing);

    await _tapBandRoom(tester, sooner);
    final details = tester.widget<EventDetailsPage>(find.byType(EventDetailsPage));
    expect(details.eventId, 'near');
    expect(details.bandId, 'band_feed_test');
    await _tapBandRoom(tester, find.text('YES'));
    service.denyRsvpWrite = true;
    await _tapBandRoom(tester, find.text('Save RSVP'));
    expect(find.text('Failed to update RSVP'), findsOneWidget);
    expect(service.updatedResponses, isEmpty);
    expect(service.testEventsList.singleWhere((event) => event.id == 'near')
        .responses['leader_1'], isNull);

    service.denyRsvpWrite = false;
    await _tapBandRoom(tester, find.text('Save RSVP'));
    expect(service.updatedResponses, [{
      'bandId': 'band_feed_test',
      'eventId': 'near',
      'userId': 'leader_1',
      'response': 'Yes',
    }]);
    Navigator.of(tester.element(find.byType(EventDetailsPage))).pop();
    await pumpUiTransitions(tester);
    expect(sooner, findsOneWidget);
    expect(later, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _mountBandRoom(tester, service);
    expect(find.byType(RsvpReminderDialog), findsNothing);
    await _tapBandRoom(tester, eventsTab);
    expect(sooner, findsOneWidget);
    expect(later, findsOneWidget);

    await _tapBandRoom(tester, find.text('UPCOMING (Finalized)'));
    expect(find.text('”Finalized Event”'), findsOneWidget);
    expect(sooner, findsNothing);

    await _tapBandRoom(tester, find.text('PAST EVENTS'));
    final newer = find.text('”Past Newer Event”');
    final older = find.text('”Past Older Event”');
    expect(newer, findsOneWidget);
    expect(older, findsOneWidget);
    expect(tester.getTopLeft(newer).dy, lessThan(tester.getTopLeft(older).dy));
    expect(find.text('Save RSVP'), findsNothing);

    await _tapBandRoom(tester, find.widgetWithText(Tab, 'News'));
    expect(find.byType(ManageEventsScreen), findsNothing);
    expect(sooner, findsNothing);
    expect(later, findsNothing);
    expect(newer, findsNothing);
  });
}

BandEvent _event(
  DateTime now,
  String id,
  String title,
  int days, {
  bool requireResponse = true,
  Map<String, EventResponse> responses = const {},
  int? rsvpDeadline,
}) {
  final start = now.add(Duration(days: days));
  return BandEvent(
    id: id,
    title: title,
    description: 'Gig details description',
    eventType: 'Concert',
    location: 'Main Stage',
    startDateTime: start.toIso8601String(),
    endDateTime: start.add(const Duration(hours: 3)).toIso8601String(),
    additionalNotes: 'Backline provided',
    createdBy: 'leader_1',
    createdAt: now.millisecondsSinceEpoch,
    updatedAt: now.millisecondsSinceEpoch,
    requireResponse: requireResponse,
    rsvpDeadline: rsvpDeadline,
    responses: responses,
  );
}

Future<void> _mountBandRoom(
  WidgetTester tester,
  MockGigsInfoFirebaseService service, {
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => MockGigsInfoAppState(service),
      child: MaterialApp(home: BandRoomChatScreen(clock: clock)),
    ),
  );
  await pumpUiTransitions(tester);
}

Future<void> _tapBandRoom(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpUiTransitions(tester);
}

Future<void> _dismissReminder(WidgetTester tester) async {
  final reminder = find.byType(RsvpReminderDialog);
  expect(reminder, findsOneWidget);
  Navigator.of(tester.element(reminder)).pop();
  await pumpUiTransitions(tester);
}
