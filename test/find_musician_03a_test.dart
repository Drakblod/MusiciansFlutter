import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';

class MockFirebaseService extends Fake implements FirebaseService {
  final Map<String, BandEvent> events = {};
  final Map<String, List<BandEvent>> bandEvents = {};
  final Map<String, List<SubRequest>> eventSubRequests = {};
  final Map<String, UserProfile> userProfiles = {};
  final List<String> favoriteUserIds = [];
  final List<BandMember> bandMembers = [];
  Band? bandInfo;
  final List<SubRequest> allSubRequests = [];
  final List<SubRequest> savedBatchRequests = [];

  int totalWriteCalls = 0;
  int eventWriteCalls = 0;
  int revokeCalls = 0;
  int assignCalls = 0;
  int publishCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUserId => 'organizer_1';

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Future<void> initializePushNotifications() async {}

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async {
    return events[eventId];
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return bandEvents[bandId] ?? [];
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    return eventSubRequests[eventId] ?? [];
  }

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async {
    return {};
  }

  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async {
    return {};
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    if (bandInfo != null) return {bandInfo!.id ?? '': bandInfo!.name ?? ''};
    return {};
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    if (userId == null) return null;
    return userProfiles[userId];
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return userProfiles.values.toList();
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return favoriteUserIds;
  }

  @override
  Future<bool> isFavoriteAsync(String targetUserId) async {
    return favoriteUserIds.contains(targetUserId);
  }

  @override
  Future<void> toggleFavoriteAsync(String targetUserId, bool isFavorite) async {
    totalWriteCalls++;
    if (isFavorite) {
      if (!favoriteUserIds.contains(targetUserId)) favoriteUserIds.add(targetUserId);
    } else {
      favoriteUserIds.remove(targetUserId);
    }
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return bandMembers;
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return bandInfo;
  }

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    return allSubRequests;
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return allSubRequests;
  }

  @override
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    totalWriteCalls++;
    publishCalls++;
    savedBatchRequests.addAll(requests);
    allSubRequests.addAll(requests);
    return requests.asMap().entries.map((e) => 'sub_id_${e.key}').toList();
  }

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    return saveSubRequestsBatchAsync(requests);
  }

  @override
  Future<void> saveSubRequestPublicationAsync(String publicationId, Map<String, dynamic> manifest) async {
    totalWriteCalls++;
  }

  @override
  Future<void> assignSubstituteCandidateAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    required String roleOrInstrument,
    String? candidateName,
    String? slotId,
    String? replacedMemberId,
    String? replacedMemberName,
  }) async {
    totalWriteCalls++;
    assignCalls++;
  }

  @override
  Future<void> revokeSubstituteAssignmentAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    String? slotId,
  }) async {
    totalWriteCalls++;
    revokeCalls++;
  }

  @override
  Future<void> updateBandEventAsync(
    String bandId,
    String eventId,
    Map<String, dynamic> editableFields,
  ) async {
    totalWriteCalls++;
    eventWriteCalls++;
  }
}

class MockAppStateForFindMusicianTest extends AppState {
  final MockFirebaseService mockService = MockFirebaseService();
  String? testCurrentUserId;
  UserProfile? testUserProfile;
  String? testActiveBandId;
  String? testActiveBandName;

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => testCurrentUserId;

  @override
  UserProfile? get currentUserProfile => testUserProfile;

  @override
  String? get activeBandId => testActiveBandId;

  @override
  String? get activeBandName => testActiveBandName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late MockAppStateForFindMusicianTest appState;
  late MockFirebaseService mockFirebaseService;

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = MockAppStateForFindMusicianTest();
    mockFirebaseService = appState.mockService;

    appState.testCurrentUserId = 'organizer_1';
    appState.testActiveBandId = 'band_123';
    appState.testActiveBandName = 'The Sonic Waves';
    appState.testUserProfile = UserProfile(
      userId: 'organizer_1',
      displayName: 'Leader User',
      location: 'Stockholm, Sweden',
      instruments: ['Guitar'],
    );

    mockFirebaseService.userProfiles['organizer_1'] = appState.testUserProfile!;
    mockFirebaseService.userProfiles['musician_1'] = UserProfile(
      userId: 'musician_1',
      displayName: 'Alice Bass',
      location: 'Stockholm, Sweden',
      instruments: ['Bass'],
    );
    mockFirebaseService.userProfiles['musician_2'] = UserProfile(
      userId: 'musician_2',
      displayName: 'Bob Drums',
      location: 'Stockholm, Sweden',
      instruments: ['Drums'],
    );
    mockFirebaseService.userProfiles['musician_guitar'] = UserProfile(
      userId: 'musician_guitar',
      displayName: 'Jimi Hendrix',
      location: 'Stockholm, Sweden',
      instruments: ['Electric Guitar', 'Guitar'],
    );

    mockFirebaseService.favoriteUserIds.add('musician_1');
    mockFirebaseService.favoriteUserIds.add('musician_guitar');

    mockFirebaseService.bandMembers.addAll([
      BandMember(userId: 'organizer_1', role: 'Leader', nickname: 'Organizer'),
      BandMember(userId: 'member_bass', role: 'Member', nickname: 'Original Bassist'),
    ]);

    mockFirebaseService.bandInfo = Band(
      id: 'band_123',
      name: 'The Sonic Waves',
      membersBand: {
        'organizer_1': mockFirebaseService.bandMembers[0],
        'member_bass': mockFirebaseService.bandMembers[1],
      },
    );
  });

  Widget createWidgetUnderTest({
    String? bandId = 'band_123',
    String? eventId = 'event_single',
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: MaterialApp(
        home: FindSubScreen(
          bandId: bandId,
          eventId: eventId,
        ),
      ),
    );
  }

  group('FIND-MUSICIAN-03A.1 Entry Context & Request Snapshot Tests', () {
    testWidgets('1. HomeView/standalone entry renders an empty Name of Event without EVENT 1 header', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.textContaining('EVENT 1'), findsNothing);
      expect(find.text('Name of Event'), findsOneWidget);

      final titleField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, ''));
      expect(titleField.controller?.text, isEmpty);
    });

    testWidgets('2. Standalone Name of Event is editable', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      expect(textFields, findsOneWidget);

      await tester.enterText(textFields.first, 'Acoustic Sunday Showcase');
      await tester.pumpAndSettle();

      expect(find.text('Acoustic Sunday Showcase'), findsWidgets);
    });

    testWidgets('3. Standalone Event Type begins unselected and is selectable', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Select Event Type'), findsOneWidget);

      await tester.tap(find.text('Select Event Type'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rehearsal').last);
      await tester.pumpAndSettle();

      expect(find.text('Rehearsal'), findsWidgets);
    });

    testWidgets('4. Other standalone event fields begin blank', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Date & Time'), findsOneWidget);

      final descField = find.widgetWithText(TextField, '');
      expect(descField, findsWidgets);
    });

    testWidgets('5. Existing-event entry pre-fills all event fields', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_existing_1',
        title: 'Stockholm Rock Gala',
        eventType: 'Concert',
        description: 'Special annual charity rock gala',
        location: 'Globe Arena, Stockholm',
        startDateTime: '2026-07-20T19:30:00Z',
        endDateTime: '2026-07-20T22:30:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_existing_1'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_existing_1'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Rock Gala'), findsWidgets);
      expect(find.text('Concert'), findsWidgets);
      expect(find.text('Special annual charity rock gala'), findsOneWidget);
      expect(find.text('Globe Arena, Stockholm'), findsOneWidget);
    });

    testWidgets('6. Existing-event Name of Event can be edited as request-local data', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_existing_2',
        title: 'Original Festival Name',
        eventType: 'Concert',
        description: 'Main festival stage',
        location: 'City Park',
        startDateTime: '2026-08-10T18:00:00Z',
        endDateTime: '2026-08-10T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_existing_2'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_existing_2'));
      await tester.pumpAndSettle();

      final titleFinder = find.widgetWithText(TextFormField, 'Original Festival Name');
      expect(titleFinder, findsOneWidget);

      await tester.enterText(titleFinder, 'Festival Substitute Search Call');
      await tester.pumpAndSettle();

      expect(find.text('Festival Substitute Search Call'), findsWidgets);
    });

    testWidgets('7. Existing-event Event Type can be changed as request-local data', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_existing_3',
        title: 'Gig 1',
        eventType: 'Concert',
        description: 'Concert set',
        location: 'Club A',
        startDateTime: '2026-08-10T18:00:00Z',
        endDateTime: '2026-08-10T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_existing_3'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_existing_3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Concert').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Club gig').last);
      await tester.pumpAndSettle();

      expect(find.text('Club gig'), findsWidgets);
    });

    testWidgets('8. Request-local edits do not mutate the source BandEvent', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_source_check',
        title: 'Untouched Source Title',
        eventType: 'Rehearsal',
        description: 'Untouched Source Description',
        location: 'Untouched Source Location',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_source_check'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_source_check'));
      await tester.pumpAndSettle();

      // Edit title and description
      final titleField = find.widgetWithText(TextFormField, 'Untouched Source Title');
      await tester.enterText(titleField, 'Heavily Edited Request Snapshot');
      await tester.pumpAndSettle();

      // Verify zero write calls were triggered
      expect(mockFirebaseService.eventWriteCalls, 0);
      expect(mockFirebaseService.totalWriteCalls, 0);

      // Verify original BandEvent in storage remains completely unaltered
      final storedEvent = mockFirebaseService.events['event_source_check']!;
      expect(storedEvent.title, 'Untouched Source Title');
      expect(storedEvent.description, 'Untouched Source Description');
      expect(storedEvent.location, 'Untouched Source Location');
      expect(storedEvent.eventType, 'Rehearsal');
    });

    testWidgets('9. Dismissing after editing performs zero event writes', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_dismiss_test',
        title: 'Dismissal Event',
        eventType: 'Gig',
        description: 'Gig desc',
        location: 'Bar',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_dismiss_test'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_dismiss_test'));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextFormField, 'Dismissal Event');
      await tester.enterText(titleField, 'Discarded Title Edit');
      await tester.pumpAndSettle();

      // Pump a replacement empty widget to simulate dismissal/navigation away
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Dismissed'))));
      await tester.pumpAndSettle();

      expect(mockFirebaseService.eventWriteCalls, 0);
      expect(mockFirebaseService.totalWriteCalls, 0);
      expect(mockFirebaseService.events['event_dismiss_test']!.title, 'Dismissal Event');
    });

    testWidgets('10. Switching modes preserves the request draft', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final existingEvent = BandEvent(
        id: 'event_mode_test',
        title: 'Mode Switch Event',
        eventType: 'Gig',
        description: 'Original mode desc',
        location: 'Main Bar',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_mode_test'] = existingEvent;
      mockFirebaseService.bandEvents['band_123'] = [existingEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_mode_test'));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextFormField, 'Mode Switch Event');
      await tester.enterText(titleField, 'Custom Request Title 2026');
      await tester.pumpAndSettle();

      // Switch to New Band Member mode
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      expect(find.text('Permanent Band Recruitment'), findsOneWidget);

      // Switch back to Substitute mode
      await tester.tap(find.text('Find Substitute(s)'));
      await tester.pumpAndSettle();

      expect(find.text('Custom Request Title 2026'), findsWidgets);
    });

    testWidgets('11. Event 1 and Event 2 maintain independent editable values', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ev1 = BandEvent(
        id: 'ev_multi_1',
        parentEventId: 'ev_multi_parent',
        subEventSequence: 1,
        title: 'Rehearsal 1',
        eventType: 'Rehearsal',
        description: 'Rehearsal day 1',
        location: 'Studio A',
        startDateTime: '2026-09-10T18:00:00Z',
        endDateTime: '2026-09-10T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );

      final ev2 = BandEvent(
        id: 'ev_multi_2',
        parentEventId: 'ev_multi_parent',
        subEventSequence: 2,
        title: 'Tour Gig',
        eventType: 'Concert',
        description: 'Tour gig day 2',
        location: 'Arena B',
        startDateTime: '2026-09-11T19:00:00Z',
        endDateTime: '2026-09-11T22:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );

      mockFirebaseService.events['ev_multi_parent'] = ev1;
      mockFirebaseService.bandEvents['band_123'] = [ev1, ev2];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'ev_multi_parent'));
      await tester.pumpAndSettle();

      final title1Field = find.widgetWithText(TextFormField, 'Rehearsal 1');
      final title2Field = find.widgetWithText(TextFormField, 'Tour Gig');

      expect(title1Field, findsOneWidget);
      expect(title2Field, findsOneWidget);

      await tester.enterText(title1Field, 'Rehearsal 1 (Warmup Set)');
      await tester.enterText(title2Field, 'Tour Gig (Main Stage)');
      await tester.pumpAndSettle();

      expect(find.text('Rehearsal 1 (Warmup Set)'), findsWidgets);
      expect(find.text('Tour Gig (Main Stage)'), findsWidgets);
    });

    testWidgets('12. Publishing Event 1 slots uses Event 1 request snapshot', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ev1 = BandEvent(
        id: 'ev_pub_1',
        parentEventId: 'ev_pub_parent',
        subEventSequence: 1,
        title: 'Initial Event 1',
        eventType: 'Rehearsal',
        description: 'Notes 1',
        location: 'Loc 1',
        startDateTime: '2026-09-10T18:00:00Z',
        endDateTime: '2026-09-10T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
        responses: {
          'member_bass': EventResponse(
            status: 'NO',
            timestamp: DateTime.parse('2026-06-02T10:00:00Z'),
          ),
        },
      );

      final ev2 = BandEvent(
        id: 'ev_pub_2',
        parentEventId: 'ev_pub_parent',
        subEventSequence: 2,
        title: 'Initial Event 2',
        eventType: 'Concert',
        description: 'Notes 2',
        location: 'Loc 2',
        startDateTime: '2026-09-11T19:00:00Z',
        endDateTime: '2026-09-11T22:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
        responses: {
          'member_bass': EventResponse(
            status: 'NO',
            timestamp: DateTime.parse('2026-06-02T10:00:00Z'),
          ),
        },
      );

      mockFirebaseService.events['ev_pub_parent'] = ev1;
      mockFirebaseService.bandEvents['band_123'] = [ev1, ev2];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'ev_pub_parent'));
      await tester.pumpAndSettle();

      final title1Field = find.widgetWithText(TextFormField, 'Initial Event 1');
      await tester.enterText(title1Field, 'Edited Snapshot Title 1');
      await tester.pumpAndSettle();

      final publishBtn = find.text('PUBLISH MULTIPLE REQUEST');
      await tester.ensureVisible(publishBtn);
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      expect(mockFirebaseService.publishCalls, 1);
      final ev1Req = mockFirebaseService.allSubRequests.firstWhere((r) => r.eventId == 'ev_pub_1');
      expect(ev1Req.eventTitle, 'Edited Snapshot Title 1');
      expect(ev1Req.date, contains('2026-09-10'));
    });

    testWidgets('13. Publishing Event 2 slots uses Event 2 request snapshot', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ev1 = BandEvent(
        id: 'ev_pub2_1',
        parentEventId: 'ev_pub2_parent',
        subEventSequence: 1,
        title: 'E1',
        eventType: 'Rehearsal',
        description: 'N1',
        location: 'L1',
        startDateTime: '2026-09-10T18:00:00Z',
        endDateTime: '2026-09-10T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
        responses: {
          'member_bass': EventResponse(
            status: 'NO',
            timestamp: DateTime.parse('2026-06-02T10:00:00Z'),
          ),
        },
      );

      final ev2 = BandEvent(
        id: 'ev_pub2_2',
        parentEventId: 'ev_pub2_parent',
        subEventSequence: 2,
        title: 'E2',
        eventType: 'Concert',
        description: 'N2',
        location: 'L2',
        startDateTime: '2026-09-11T19:00:00Z',
        endDateTime: '2026-09-11T22:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
        responses: {
          'member_bass': EventResponse(
            status: 'NO',
            timestamp: DateTime.parse('2026-06-02T10:00:00Z'),
          ),
        },
      );

      mockFirebaseService.events['ev_pub2_parent'] = ev1;
      mockFirebaseService.bandEvents['band_123'] = [ev1, ev2];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'ev_pub2_parent'));
      await tester.pumpAndSettle();

      final title2Field = find.widgetWithText(TextFormField, 'E2');
      await tester.enterText(title2Field, 'Custom Snapshot E2');
      await tester.pumpAndSettle();

      final publishBtn = find.text('PUBLISH MULTIPLE REQUEST');
      await tester.ensureVisible(publishBtn);
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      final ev2Req = mockFirebaseService.allSubRequests.firstWhere((r) => r.eventId == 'ev_pub2_2');
      expect(ev2Req.eventTitle, 'Custom Snapshot E2');
      expect(ev2Req.date, contains('2026-09-11'));
    });

    testWidgets('14. A new standalone slot does not display Assigned substitute or empty box', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.text('No substitute assigned yet'), findsNothing);
    });

    testWidgets('15. An existing unassigned slot does not display the empty assignment box', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_single'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.text('No substitute assigned yet'), findsNothing);
    });

    testWidgets('16. Favorite or applicant selection alone does not display the assignment section', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Switch search source to Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Jimi Hendrix is selected as target favorite notification recipient
      expect(find.text('Jimi Hendrix'), findsWidgets);

      // But assignment box is not rendered
      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.textContaining('Assigned:'), findsNothing);
    });

    testWidgets('17. A successfully assigned slot displays Assigned substitute and Assigned: <name>', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final assignedSubRequest = SubRequest(
        id: 'sub_req_assigned',
        subRequestId: 'sub_req_assigned',
        slotId: 'slot_assigned_1',
        eventId: 'event_assigned',
        bandId: 'band_123',
        voicePart: 'Bass Guitar',
        status: 'assigned',
        assignedUserId: 'user_bassist',
        assignedUserName: 'Alice Bass',
        assignedAt: 1772445600000,
        role: 'Substitute',
      );

      final assignedEvent = BandEvent(
        id: 'event_assigned',
        title: 'Assigned Gig',
        eventType: 'Concert',
        description: 'Gig desc',
        location: 'Concert Hall',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );

      mockFirebaseService.events['event_assigned'] = assignedEvent;
      mockFirebaseService.bandEvents['band_123'] = [assignedEvent];
      mockFirebaseService.eventSubRequests['event_assigned'] = [assignedSubRequest];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_assigned'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsOneWidget);
      expect(find.text('Assigned: Alice Bass'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);
    });

    testWidgets('17b. Slot with status assigned but null or empty assignedUserId does not display Assigned substitute section', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final emptyAssignedSubRequest = SubRequest(
        id: 'sub_req_empty_assigned',
        subRequestId: 'sub_req_empty_assigned',
        slotId: 'slot_empty_assigned_1',
        eventId: 'event_empty_assigned',
        bandId: 'band_123',
        voicePart: 'Bass Guitar',
        status: 'assigned',
        assignedUserId: null,
        assignedUserName: null,
        role: 'Substitute',
      );

      final emptyAssignedEvent = BandEvent(
        id: 'event_empty_assigned',
        title: 'Empty Assigned Gig',
        eventType: 'Concert',
        description: 'Gig desc',
        location: 'Concert Hall',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );

      mockFirebaseService.events['event_empty_assigned'] = emptyAssignedEvent;
      mockFirebaseService.bandEvents['band_123'] = [emptyAssignedEvent];
      mockFirebaseService.eventSubRequests['event_empty_assigned'] = [emptyAssignedSubRequest];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_empty_assigned'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.textContaining('Assigned:'), findsNothing);
      expect(find.text('Revoke'), findsNothing);
    });

    testWidgets('18. Revoke remains functional and revoking the assignment hides the section again', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final assignedSubRequest = SubRequest(
        id: 'sub_req_revoke',
        subRequestId: 'sub_req_revoke',
        slotId: 'slot_revoke_1',
        eventId: 'event_revoke',
        bandId: 'band_123',
        voicePart: 'Bass Guitar',
        status: 'assigned',
        assignedUserId: 'user_bassist',
        assignedUserName: 'Alice Bass',
        assignedAt: 1772445600000,
        role: 'Substitute',
      );

      final assignedEvent = BandEvent(
        id: 'event_revoke',
        title: 'Revoke Gig',
        eventType: 'Concert',
        description: 'Gig desc',
        location: 'Concert Hall',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );

      mockFirebaseService.events['event_revoke'] = assignedEvent;
      mockFirebaseService.bandEvents['band_123'] = [assignedEvent];
      mockFirebaseService.eventSubRequests['event_revoke'] = [assignedSubRequest];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_revoke'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsOneWidget);
      expect(find.text('Assigned: Alice Bass'), findsOneWidget);

      final revokeBtn = find.widgetWithText(TextButton, 'Revoke');
      expect(revokeBtn, findsOneWidget);

      await tester.tap(revokeBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Revoke Assignment?'), findsOneWidget);

      // Confirm revocation in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(mockFirebaseService.revokeCalls, 1);
      // Section is now hidden again
      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.text('Assigned: Alice Bass'), findsNothing);
    });

    testWidgets('19. Required standalone fields block invalid publication', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Open standalone (no eventId) -> Name of Event is empty, Event Type is unselected
      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      final publishBtn = find.textContaining('PUBLISH SUBSTITUTE REQUESTS');
      await tester.ensureVisible(publishBtn);
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      // Publication should be blocked and show error SnackBar
      expect(find.text('Please enter Name of Event and select an Event Type before publishing.'), findsOneWidget);
      expect(mockFirebaseService.publishCalls, 0);
    });

    testWidgets('20. Narrow 320px layout renders without throwing any Flutter layout or render exceptions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final singleEvent = BandEvent(
        id: 'event_narrow',
        title: 'Super Long Event Name For Responsive Overflow Test 2026',
        eventType: 'Special Anniversary Festival & Rehearsal Gig',
        description: 'Super long description that wraps across multiple lines gracefully.',
        location: 'Stockholm Konserthuset Great Hall Main Stage',
        startDateTime: '2026-06-15T19:00:00Z',
        endDateTime: '2026-06-15T21:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1772445600000,
        updatedAt: 1772445600000,
        requireResponse: true,
      );
      mockFirebaseService.events['event_narrow'] = singleEvent;
      mockFirebaseService.bandEvents['band_123'] = [singleEvent];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_narrow'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Switch to New Band Member at 320px
      await tester.ensureVisible(find.text('Find New Band Member(s)'));
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
