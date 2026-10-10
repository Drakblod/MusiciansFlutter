import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/create_event_page.dart';
import 'package:provider/provider.dart';

class MockFirebaseService extends Fake implements FirebaseService {
  final List<BandMember> mockMembers = [
    BandMember(userId: 'u1', nickname: 'Alice', role: 'Leader', status: 'active'),
    BandMember(userId: 'u2', nickname: 'Bob', role: 'Guitarist', status: 'active'),
    BandMember(userId: 'u3', nickname: 'Charlie', role: 'Drummer', status: 'on_hold'),
  ];

  final List<UserProfile> mockUsers = [
    UserProfile(userId: 'u1', displayName: 'Alice Singer', nickname: 'Alice', instruments: ['Vocals']),
    UserProfile(userId: 'u2', displayName: 'Bob Guitar', nickname: 'Bob', instruments: ['Guitar']),
    UserProfile(userId: 'u3', displayName: 'Charlie Drummer', nickname: 'Charlie', instruments: ['Drums']),
    UserProfile(userId: 'u4', displayName: 'Dave Bass', nickname: 'Dave', instruments: ['Bass'], location: 'Stockholm'),
  ];

  BandEvent? lastSavedEvent;
  final List<SubRequest> savedSubRequests = [];

  @override
  Future<Band?> getBandInfoAsync(String bandId) async => Band(id: bandId, name: 'Test Band');

  @override
  String generateEventId(String bandId) => 'event_123';

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    savedSubRequests.addAll(requests);
    return requests.map((r) => r.id ?? 'sub_id').toList();
  }

  @override
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    savedSubRequests.addAll(requests);
    return requests.map((r) => r.id ?? 'sub_id').toList();
  }

  @override
  Future<void> updateBandEventAsync(String bandId, String eventId, Map<String, dynamic> editableFields) async {}

  @override
  Future<bool> deleteSubRequestAsync(String creatorId, String subRequestId) async => true;

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async => 'leader';

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async => mockMembers;

  @override
  Future<List<UserProfile>> getAllUsersAsync() async => mockUsers;

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return mockUsers.firstWhere(
      (u) => u.userId == (userId ?? 'u1'),
      orElse: () => UserProfile(userId: userId ?? 'u1'),
    );
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async => [];

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) => const Stream.empty();

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) => const Stream.empty();

  @override
  Future<String> saveBandEventAsync(String bandId, BandEvent event) async {
    lastSavedEvent = event;
    return 'event_123';
  }

  @override
  Future<String> createTemporaryEventRoomAsync({
    required String bandId,
    required String eventId,
    required String roomName,
    required String createdBy,
    List<String> initialMembers = const [],
  }) async {
    return 'room_123';
  }
}

class MockAppState extends Fake with ChangeNotifier implements AppState {
  final MockFirebaseService mockFirebase = MockFirebaseService();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'u1', displayName: 'Alice Singer');

  @override
  String? get currentUserId => 'u1';

  @override
  bool get hasUnreadMessages => false;

  @override
  int get unreadNotificationCount => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BandEvent Model excludedMemberIds and externalInvitees tests', () {
    test('BandEvent serialization and deserialization preserves excludedMemberIds', () {
      final event = BandEvent(
        id: 'ev_1',
        title: 'Summer Festival',
        description: 'Main festival stage',
        location: 'Stockholm',
        startDateTime: '2026-07-01T18:00:00.000Z',
        endDateTime: '2026-07-01T22:00:00.000Z',
        additionalNotes: 'Bring gear',
        createdBy: 'u1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
        excludedMemberIds: ['u2', 'u3'],
        externalInvitees: {
          'u4': ExternalInvitee(
            userId: 'u4',
            displayName: 'Dave Bass',
            instrument: 'Bass',
            status: 'attending',
            invitedAt: 1000,
          ),
        },
      );

      final json = event.toJson();
      expect(json['excludedMemberIds'], ['u2', 'u3']);
      expect(json['externalInvitees'], isNotNull);
      expect(json['externalInvitees']['u4']['displayName'], 'Dave Bass');

      final deserialized = BandEvent.fromJson(json, 'ev_1');
      expect(deserialized.id, 'ev_1');
      expect(deserialized.excludedMemberIds, ['u2', 'u3']);
      expect(deserialized.externalInvitees.containsKey('u4'), true);
      expect(deserialized.externalInvitees['u4']?.displayName, 'Dave Bass');
      expect(deserialized.externalInvitees['u4']?.status, 'attending');
    });
  });

  group('CreateEventPage Edit Band Members Widget Tests', () {
    late MockAppState appState;

    setUp(() {
      appState = MockAppState();
    });

    testWidgets('Displays expandable Edit Band Members card with members and add guest button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: CreateEventPage(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check for expandable Edit Band Members card
      expect(find.text('EDIT BAND MEMBERS (& SUBS)'), findsOneWidget);
      expect(find.text('3/3 Included'), findsOneWidget);

      // Tap on the header to expand
      await tester.tap(find.text('EDIT BAND MEMBERS (& SUBS)'));
      await tester.pumpAndSettle();

      // Now sub-sections should be visible
      expect(find.text('ADD SUB (if needed)'), findsOneWidget);
      expect(find.text('+ Add Sub'), findsOneWidget);
      expect(find.text('MANAGE BAND MEMBERS FOR THIS SPECIFIC EVENT'), findsOneWidget);

      // Members should be listed
      expect(find.text('Alice Singer'), findsOneWidget);
      expect(find.text('Bob Guitar'), findsOneWidget);
      expect(find.text('Charlie Drummer'), findsOneWidget);
      expect(find.text('ON HOLD'), findsOneWidget);
    });

    testWidgets('Toggling member off excludes them from event and saves excludedMemberIds', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: CreateEventPage(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('EDIT BAND MEMBERS (& SUBS)'));
      await tester.pumpAndSettle();

      // Find switches - first 3 are members (Alice, Bob, Charlie), 4th is Create Event Chat
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(4));

      // Toggle Bob (index 1)
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      expect(find.text('2/3 Included'), findsOneWidget);
      expect(find.text('Excluded'), findsOneWidget);

      // Fill in required fields to save
      await tester.enterText(find.widgetWithText(TextFormField, 'Main Event Name'), 'Gothic Night');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Stockholm');

      // Scroll to bottom
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Tap Publish Event
      await tester.tap(find.text('Publish Event'));
      await tester.pumpAndSettle();

      expect(appState.mockFirebase.lastSavedEvent, isNotNull);
      expect(appState.mockFirebase.lastSavedEvent!.title, 'Gothic Night');
      expect(appState.mockFirebase.lastSavedEvent!.excludedMemberIds, contains('u2'));
      expect(appState.mockFirebase.lastSavedEvent!.excludedMemberIds, isNot(contains('u1')));
    });

    testWidgets('Adding guest musician adds to externalInvitees and displays guest badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: CreateEventPage(bandId: 'band_1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expand card
      await tester.tap(find.text('EDIT BAND MEMBERS (& SUBS)'));
      await tester.pumpAndSettle();

      // Tap + Add Sub
      await tester.tap(find.text('+ Add Sub'));
      await tester.pumpAndSettle();

      // Check sheet opened with Dave Bass (u4)
      expect(find.text('Add Sub for this Event'), findsOneWidget);
      expect(find.text('+ Add External / Non-registered Sub'), findsNothing);
      expect(find.text('Dave Bass'), findsOneWidget);
      expect(find.text('+ Add'), findsOneWidget);

      // Tap + Add on Dave Bass
      await tester.tap(find.text('+ Add'));
      await tester.pumpAndSettle();

      // Close sheet by tapping close icon in bottom sheet
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      // Check that Dave Bass is now rendered as a Sub
      expect(find.text('+1 Sub'), findsOneWidget);
      expect(find.text('Dave Bass'), findsOneWidget);
      expect(find.text('Sub'), findsOneWidget);

      // Save event
      await tester.enterText(find.widgetWithText(TextFormField, 'Main Event Name'), 'Special Show');
      await tester.enterText(find.widgetWithText(TextFormField, 'Location (City, Country)'), 'Uppsala');

      // Scroll to bottom
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Publish Event'));
      await tester.pumpAndSettle();

      expect(appState.mockFirebase.lastSavedEvent, isNotNull);
      expect(appState.mockFirebase.lastSavedEvent!.externalInvitees.containsKey('u4'), true);
      expect(appState.mockFirebase.lastSavedEvent!.externalInvitees['u4']?.displayName, 'Dave Bass');
      expect(appState.mockFirebase.lastSavedEvent!.externalInvitees['u4']?.subRequestId, isNotNull);
      expect(appState.mockFirebase.lastSavedEvent!.externalInvitees['u4']?.source, 'subRequest');
      expect(appState.mockFirebase.savedSubRequests, isNotEmpty);
      final sub = appState.mockFirebase.savedSubRequests.first;
      expect(sub.targetUserIds, contains('u4'));
      expect(sub.role, 'Substitute');
      expect(sub.requestType, 'Substitute');
      expect(sub.voicePart, 'Bass');
      expect(sub.eventId, 'event_123');
    });

    testWidgets('Date range is automatically derived from sub-events/rehearsals', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));

      final initialEvent = BandEvent(
        id: 'ev_existing',
        title: 'Festival Weekend',
        description: 'Multi-day music festival',
        location: 'Gothenburg',
        startDateTime: '2026-10-02T00:00:00.000',
        endDateTime: '2026-10-02T23:59:59.000',
        additionalNotes: 'Bring wristbands',
        createdBy: 'u1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
        rehearsals: [
          EventRehearsal(
            id: 'reh_1',
            title: 'Day 1 Gig',
            date: '2026-10-02',
            startTime: '18:00',
            endTime: '20:00',
            location: 'Main Stage',
            type: 'Festival',
          ),
          EventRehearsal(
            id: 'reh_2',
            title: 'Day 2 Gig',
            date: '2026-10-04',
            startTime: '14:00',
            endTime: '16:00',
            location: 'Acoustic Tent',
            type: 'Festival',
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: CreateEventPage(
              bandId: 'band_1',
              existingEvent: initialEvent,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Main Event schedule card should display the derived date range across the sub-events
      expect(find.text('"Festival Weekend"'), findsOneWidget);
      expect(find.text('Fri, Oct 2 – Sun, Oct 4, 2026'), findsOneWidget);

      // Save the event
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Publish Event'));
      await tester.pumpAndSettle();

      expect(appState.mockFirebase.lastSavedEvent, isNotNull);
      expect(appState.mockFirebase.lastSavedEvent!.startDateTime.startsWith('2026-10-02'), isTrue);
      expect(appState.mockFirebase.lastSavedEvent!.endDateTime.startsWith('2026-10-04'), isTrue);
    });
  });
}

