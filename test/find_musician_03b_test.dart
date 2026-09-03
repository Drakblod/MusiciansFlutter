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
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/create_event_page.dart';

class Mock03bFirebaseService extends Fake implements FirebaseService {
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
  int toggleFavoriteCalls = 0;

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
    return List.from(favoriteUserIds);
  }

  @override
  Future<bool> isFavoriteAsync(String targetUserId) async {
    return favoriteUserIds.contains(targetUserId);
  }

  bool shouldFailToggleFavorite = false;

  @override
  Future<void> toggleFavoriteAsync(String targetUserId, bool isFavorite) async {
    if (shouldFailToggleFavorite) {
      throw Exception('Simulated network write error');
    }
    totalWriteCalls++;
    toggleFavoriteCalls++;
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

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return 'Leader';
  }
}

class MockAppState03b extends AppState {
  final Mock03bFirebaseService mockService = Mock03bFirebaseService();
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

  late MockAppState03b appState;
  late Mock03bFirebaseService mockService;

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = MockAppState03b();
    mockService = appState.mockService;

    appState.testCurrentUserId = 'organizer_1';
    appState.testActiveBandId = 'band_123';
    appState.testActiveBandName = 'The Sonic Waves';
    appState.testUserProfile = UserProfile(
      userId: 'organizer_1',
      displayName: 'Leader User',
      location: 'Stockholm, Sweden',
      instruments: ['Guitar'],
    );

    mockService.userProfiles['organizer_1'] = appState.testUserProfile!;
    mockService.userProfiles['musician_gurra'] = UserProfile(
      userId: 'musician_gurra',
      displayName: 'Gurra',
      location: 'Stockholm, Sweden',
      instruments: ['Electric Guitar'],
    );
    mockService.userProfiles['musician_alice'] = UserProfile(
      userId: 'musician_alice',
      displayName: 'Alice Bass',
      location: 'Stockholm, Sweden',
      instruments: ['Bass'],
    );
    mockService.userProfiles['musician_bob'] = UserProfile(
      userId: 'musician_bob',
      displayName: 'Bob Drums',
      location: 'Stockholm, Sweden',
      instruments: ['Drums'],
    );
    mockService.userProfiles['musician_new'] = UserProfile(
      userId: 'musician_new',
      displayName: 'New Global Musician',
      location: 'Stockholm, Sweden',
      instruments: ['Keys', 'Piano'],
    );

    // Initial favorites: Gurra and Alice
    mockService.favoriteUserIds.add('musician_gurra');
    mockService.favoriteUserIds.add('musician_alice');

    mockService.bandMembers.addAll([
      BandMember(userId: 'organizer_1', role: 'Leader', nickname: 'Organizer'),
      BandMember(userId: 'member_guitar', role: 'Member', nickname: 'Original Guitarist'),
    ]);

    mockService.bandInfo = Band(
      id: 'band_123',
      name: 'The Sonic Waves',
      membersBand: {
        'organizer_1': mockService.bandMembers[0],
        'member_guitar': mockService.bandMembers[1],
      },
    );
  });

  Widget createWidgetUnderTest({
    String? bandId = 'band_123',
    String? eventId,
    SubRequest? initialRequest,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: MaterialApp(
        home: FindSubScreen(
          bandId: bandId,
          eventId: eventId,
          initialRequest: initialRequest,
        ),
      ),
    );
  }

  void setupMultiEventOccurrences() {
    mockService.events['event_parent'] = BandEvent(
      id: 'event_parent',
      title: 'Sommarturné',
      eventType: 'Multiple Events',
      description: 'Summer tour parent',
      location: 'Stockholm',
      additionalNotes: '',
      requireResponse: true,
      startDateTime: '2026-07-01T18:00:00.000Z',
      endDateTime: '2026-07-01T21:00:00.000Z',
      createdBy: 'organizer_1',
      createdAt: 1000,
      updatedAt: 1000,
    );

    mockService.bandEvents['band_123'] = [
      mockService.events['event_parent']!,
      BandEvent(
        id: 'event_occ_1',
        title: 'Första rep. Sommarturné',
        eventType: 'Rehearsal',
        description: 'First rehearsal',
        location: 'Stockholm Studio A',
        additionalNotes: '',
        requireResponse: true,
        parentEventId: 'event_parent',
        startDateTime: '2026-07-01T18:00:00.000Z',
        endDateTime: '2026-07-01T21:00:00.000Z',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
      ),
      BandEvent(
        id: 'event_occ_2',
        title: 'Andra rep. Sommarturné',
        eventType: 'Rehearsal',
        description: 'Second rehearsal',
        location: 'Stockholm Studio B',
        additionalNotes: '',
        requireResponse: true,
        parentEventId: 'event_parent',
        startDateTime: '2026-07-02T18:00:00.000Z',
        endDateTime: '2026-07-02T21:00:00.000Z',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
      ),
    ];

    mockService.events['event_occ_1'] = mockService.bandEvents['band_123']![1];
    mockService.events['event_occ_2'] = mockService.bandEvents['band_123']![2];
  }

  group('FIND-MUSICIAN-03B: Conditional Numbering & Favorites Workflow', () {
    // 1. A single event does not display EVENT 1.
    testWidgets('1. A single event does not display EVENT 1', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.textContaining('EVENT 1'), findsNothing);
      expect(find.text('Name of Event'), findsOneWidget);
    });

    // 2. Adding Event 2 causes both Event 1 and Event 2 headings to appear.
    testWidgets('2. Adding Event 2 causes both Event 1 and Event 2 headings to appear', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      setupMultiEventOccurrences();
      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_occ_1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('EVENT 1'), findsWidgets);
      expect(find.textContaining('EVENT 2'), findsWidgets);
    });

    // 3. Multiple-event headings use the exact format: EVENT 2 - REHEARSAL: "Andra rep. Sommarturné".
    testWidgets('3. Multiple-event headings use the exact format: EVENT 2 - REHEARSAL: "Andra rep. Sommarturné"', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      setupMultiEventOccurrences();
      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_occ_1'));
      await tester.pumpAndSettle();

      expect(find.text('EVENT 1 - REHEARSAL: "Första rep. Sommarturné"'), findsWidgets);
      expect(find.text('EVENT 2 - REHEARSAL: "Andra rep. Sommarturné"'), findsWidgets);
    });

    // 4. No · separator remains in these headings.
    testWidgets('4. No · separator remains in these headings', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      setupMultiEventOccurrences();
      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_occ_1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('EVENT 1 ·'), findsNothing);
      expect(find.textContaining('EVENT 2 ·'), findsNothing);
    });

    // 5. One substitute slot does not display SUBSTITUTE 1.
    testWidgets('5. One substitute slot does not display SUBSTITUTE 1', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsNothing);
      expect(find.text('Instrument/Skill'), findsOneWidget);
    });

    // 6. Adding Substitute 2 causes both substitute numbers to appear.
    testWidgets('6. Adding Substitute 2 causes both substitute numbers to appear', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsNothing);

      // Tap ADD ANOTHER SUBSTITUTE
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SUBSTITUTE 1 - "'), findsOneWidget);
      expect(find.textContaining('SUBSTITUTE 2 - "'), findsOneWidget);
    });

    // 7. Removing Substitute 2 hides SUBSTITUTE 1 again.
    testWidgets('7. Removing Substitute 2 hides SUBSTITUTE 1 again', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SUBSTITUTE 1 - "'), findsOneWidget);
      expect(find.textContaining('SUBSTITUTE 2 - "'), findsOneWidget);

      // Find Remove Slot button for the second slot
      final removeButtons = find.text('Remove Slot');
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      // Now only 1 slot remains: SUBSTITUTE 1 must be hidden again
      expect(find.textContaining('SUBSTITUTE 1 - "'), findsNothing);
      expect(find.textContaining('SUBSTITUTE 2 - "'), findsNothing);
    });

    // 8. Substitute numbering is independent per event.
    testWidgets('8. Substitute numbering is independent per event', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      setupMultiEventOccurrences();
      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_occ_1'));
      await tester.pumpAndSettle();

      // Initially Event 1 has 1 slot and Event 2 has 1 slot -> neither shows SUBSTITUTE 1
      expect(find.textContaining('SUBSTITUTE 1 - "'), findsNothing);

      // Tap ADD SUBSTITUTE TO EVENT 1
      await tester.tap(find.text('ADD SUBSTITUTE TO EVENT 1'));
      await tester.pumpAndSettle();

      // Now Event 1 has 2 slots (shows SUBSTITUTE 1 & SUBSTITUTE 2)
      // Event 2 has 1 slot (shows NO SUBSTITUTE number)
      expect(find.textContaining('SUBSTITUTE 1 - "'), findsOneWidget);
      expect(find.textContaining('SUBSTITUTE 2 - "'), findsOneWidget);
    });

    // 9. Favorites List appears left of Search All.
    testWidgets('9. Favorites List appears left of Search All', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      final favFinder = find.text('Favorites List');
      final searchAllFinder = find.text('Search All');

      expect(favFinder, findsOneWidget);
      expect(searchAllFinder, findsOneWidget);

      final favPos = tester.getTopLeft(favFinder);
      final searchPos = tester.getTopLeft(searchAllFinder);
      expect(favPos.dx, lessThan(searchPos.dx));
    });

    // 10. Clicking Favorites List opens the complete existing list.
    testWidgets('10. Clicking Favorites List opens the complete existing list', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Gurra'), findsNothing);
      expect(find.text('Alice Bass'), findsNothing);

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('Gurra'), findsOneWidget);
      expect(find.text('Alice Bass'), findsOneWidget);
    });

    // 11. No search field appears inside the existing Favorites List.
    testWidgets('11. No search field appears inside the existing Favorites List', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // The Favorites List panel itself contains NO search field until + Add Favorite(s) is tapped
      expect(find.widgetWithText(TextField, 'Search musicians to add as favorite...'), findsNothing);
    });

    // 12. The Favorites List heading uses the corrected presentation.
    testWidgets('12. The Favorites List heading uses the corrected presentation', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Heading inside panel
      expect(find.text('Favorites List'), findsNWidgets(2)); // Button + Panel Heading
    });

    // 13. Selection controls appear before musician names.
    testWidgets('13. Selection controls appear before musician names', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      final tileFinder = find.widgetWithText(CheckboxListTile, 'Gurra');
      expect(tileFinder, findsOneWidget);
      final tile = tester.widget<CheckboxListTile>(tileFinder);
      expect(tile.controlAffinity, equals(ListTileControlAffinity.leading));
    });

    // 14. A substitute slot allows one chosen Favorite.
    // 15. Selecting a Favorite collapses the list.
    // 16. Chosen Substitute appears below Instrument/Skill.
    // 17. The chosen musician’s name is displayed.
    testWidgets('14-17. Selecting a favorite collapses list, allows one choice, and displays Chosen Substitute', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('Chosen Substitute'), findsNothing);

      // Tap Gurra
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // List collapses
      expect(find.byType(CheckboxListTile), findsNothing);

      // Chosen Substitute appears with Gurra
      expect(find.text('Chosen Substitute'), findsOneWidget);
      expect(find.text('Gurra'), findsOneWidget);

      // Verify Chosen Substitute appears below Instrument/Skill
      final instPos = tester.getTopLeft(find.text('Instrument/Skill'));
      final chosenPos = tester.getTopLeft(find.text('Chosen Substitute'));
      expect(chosenPos.dy, greaterThan(instPos.dy));
    });

    // 18. Reopening the list preserves the selected state.
    testWidgets('18. Reopening the list preserves the selected state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // Reopen Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra'));
      expect(tile.value, isTrue);

      final tileAlice = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Bass'));
      expect(tileAlice.value, isFalse);
    });

    // 19. Selecting another Favorite replaces the previous choice.
    testWidgets('19. Selecting another Favorite replaces the previous choice', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      expect(find.text('Gurra'), findsOneWidget);

      // Reopen and select Alice
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alice Bass'));
      await tester.pumpAndSettle();

      // Gurra replaced with Alice
      expect(find.text('Gurra'), findsNothing);
      expect(find.text('Alice Bass'), findsOneWidget);
    });

    // 20. Clearing the choice hides Chosen Substitute.
    testWidgets('20. Clearing the choice hides Chosen Substitute', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      expect(find.text('Chosen Substitute'), findsOneWidget);

      // Reopen and tap Gurra to uncheck
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      expect(find.text('Chosen Substitute'), findsNothing);
    });

    // 21. Slot 1 and Slot 2 maintain independent chosen Favorites.
    testWidgets('21. Slot 1 and Slot 2 maintain independent chosen Favorites', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Add second slot
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      final favButtons = find.text('Favorites List');
      expect(favButtons, findsNWidgets(2));

      // Choose Gurra for Slot 1
      await tester.tap(favButtons.first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // Choose Alice for Slot 2
      await tester.tap(find.text('Favorites List').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alice Bass'));
      await tester.pumpAndSettle();

      // Both should be visible in their respective Chosen Substitute containers
      expect(find.text('Gurra'), findsOneWidget);
      expect(find.text('Alice Bass'), findsOneWidget);
    });

    // 22-24. Safety: Favorite selection does not set assignedUserId, does not change status, and does not show assignment UI.
    testWidgets('22-24. Favorite selection does not set assignedUserId, status, or display Assigned substitute', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsNothing);
      expect(find.text('Revoke'), findsNothing);
      expect(mockService.assignCalls, equals(0));
    });

    // 25. + Add Favorite(s) appears below Favorites List.
    testWidgets('25. + Add Favorite(s) appears below Favorites List', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('+ Add Favorite(s)'), findsOneWidget);
    });

    // 26. Clicking it opens musician search.
    // 27. Search results use real profile IDs.
    // 28. Adding a musician persists through canonical Favorites API.
    // 29. The refreshed Favorites List displays the new musician.
    // 30. Adding a global Favorite does not automatically choose them for the slot.
    // 31. Duplicate Favorites are prevented.
    testWidgets('26-31. Global + Add Favorite(s) search, persist via canonical API, prevent duplicates, and do not auto-choose', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Tap + Add Favorite(s)
      await tester.tap(find.text('+ Add Favorite(s)'));
      await tester.pumpAndSettle();

      // Search field appears
      final searchInput = find.widgetWithText(TextField, 'Search musicians to add as favorite...');
      expect(searchInput, findsOneWidget);

      // Search for "New Global Musician"
      await tester.enterText(searchInput, 'New Global');
      await tester.pumpAndSettle();

      expect(find.text('New Global Musician'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);

      // Tap Add
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // 28. Persisted via canonical API
      expect(mockService.favoriteUserIds, contains('musician_new'));
      expect(mockService.toggleFavoriteCalls, equals(1));

      // 29. Refreshed Favorites List displays the new musician
      expect(find.widgetWithText(CheckboxListTile, 'New Global Musician'), findsOneWidget);

      // 30. Does not automatically choose them for the slot
      final newTile = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'New Global Musician'));
      expect(newTile.value, isFalse);
      expect(find.text('Chosen Substitute'), findsNothing);

      // 31. Duplicate prevention: search again for "New Global"
      await tester.enterText(searchInput, 'New Global');
      await tester.pumpAndSettle();
      expect(find.text('No matching musicians to add.'), findsOneWidget);
    });

    // 32. Existing profile-star Favorites appear in this same list.
    // 33. A Favorite added here appears wherever canonical Favorites List is used.
    testWidgets('32-33. Existing profile-star favorites and newly added favorites share canonical storage', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Add a third favorite directly to mock storage as if starred from profile
      mockService.favoriteUserIds.add('musician_bob');

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(CheckboxListTile, 'Bob Drums'), findsOneWidget);
    });

    // 34. Favorites List is left of Search All (New Member mode).
    testWidgets('34. New Member mode source controls: Favorites List on left, Search All on right', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      final favFinder = find.text('Favorites List');
      final searchAllFinder = find.text('Search All');

      expect(favFinder, findsOneWidget);
      expect(searchAllFinder, findsOneWidget);

      final favPos = tester.getTopLeft(favFinder);
      final searchPos = tester.getTopLeft(searchAllFinder);
      expect(favPos.dx, lessThan(searchPos.dx));
    });

    // 35. Clicking Favorites List opens the actual list (New Member mode).
    // 36. Existing Favorites are selectable (New Member mode).
    testWidgets('35-36. New Member mode opens favorites list and allows selecting favorites', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(CheckboxListTile, 'Gurra'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Alice Bass'), findsOneWidget);

      // Select Gurra
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      final tileGurra = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra'));
      expect(tileGurra.value, isTrue);
    });

    // 37. + Add Favorite(s) works through the shared implementation (New Member mode).
    testWidgets('37. New Member mode + Add Favorite(s) shares global implementation', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('+ Add Favorite(s)'), findsOneWidget);
      await tester.tap(find.text('+ Add Favorite(s)'));
      await tester.pumpAndSettle();

      final searchInput = find.widgetWithText(TextField, 'Search musicians to add as favorite...');
      await tester.enterText(searchInput, 'Bob Drums');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(mockService.favoriteUserIds, contains('musician_bob'));
      expect(find.widgetWithText(CheckboxListTile, 'Bob Drums'), findsOneWidget);
    });

    // 38. Switching modes does not duplicate the Favorites panel.
    testWidgets('38. Switching modes does not duplicate the Favorites panel', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Open in Substitute mode
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));

      // Switch to New Member mode
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);

      // Switch back to Substitute mode
      await tester.tap(find.text('Find Substitute(s)'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });

    // 39. Existing New Member publication remains functional.
    testWidgets('39. Existing New Member publication remains functional', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Enter event details
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.first, 'Auditions 2026');
      await tester.tap(find.text('Select Event Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rehearsal').last);
      await tester.pumpAndSettle();

      // Switch to New Member mode
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLISH NEW MEMBER SEARCH'));
      await tester.pumpAndSettle();

      expect(mockService.publishCalls, equals(1));
      expect(mockService.savedBatchRequests.length, equals(1));
      expect(mockService.savedBatchRequests.first.role, equals('New Member'));
    });

    // 40. Existing request publication remains functional.
    testWidgets('40. Existing request publication remains functional with chosen favorite', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Fill Name and Type
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.first, 'Tour Rehearsal');
      await tester.tap(find.text('Select Event Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rehearsal').last);
      await tester.pumpAndSettle();

      // Select Gurra as favorite
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // Publish
      await tester.tap(find.text('PUBLISH SUBSTITUTE REQUESTS (1)'));
      await tester.pumpAndSettle();

      expect(mockService.publishCalls, equals(1));
      expect(mockService.savedBatchRequests.length, equals(1));
      expect(mockService.savedBatchRequests.first.targetUserIds, equals(['musician_gurra']));
    });

    // 41. Secure assignment and Revoke remain unchanged.
    testWidgets('41. Secure assignment and Revoke remain unchanged', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final assignedSlot = SubRequest(
        id: 'sub_assigned_1',
        subRequestId: 'sub_assigned_1',
        slotId: 'slot_1',
        eventId: 'event_1',
        bandId: 'band_123',
        role: 'Substitute',
        voicePart: 'Electric Guitar',
        status: 'assigned',
        assignedUserId: 'musician_gurra',
        assignedUserName: 'Gurra',
        assignedAt: 1000,
      );

      final assignedEvent = BandEvent(
        id: 'event_1',
        title: 'Assigned Gig',
        eventType: 'Concert',
        description: 'Gig desc',
        location: 'Concert Hall',
        startDateTime: '2026-09-01T17:00:00Z',
        endDateTime: '2026-09-01T20:00:00Z',
        additionalNotes: '',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      mockService.events['event_1'] = assignedEvent;
      mockService.bandEvents['band_123'] = [assignedEvent];
      mockService.eventSubRequests['event_1'] = [assignedSlot];

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_1', initialRequest: assignedSlot));
      await tester.pumpAndSettle();

      expect(find.text('Assigned substitute'), findsOneWidget);
      expect(find.text('Assigned: Gurra'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);

      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(find.text('Revoke Assignment?'), findsOneWidget);

      await tester.tap(find.text('Revoke').last);
      await tester.pumpAndSettle();

      expect(mockService.revokeCalls, equals(1));
    });

    // 42. Existing 320 px layout renders without overflow.
    testWidgets('42. Existing 320 px layout renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // 43. Create Event remains unaffected.
    testWidgets('43. Create Event remains unaffected (snapshot isolation preserved)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      mockService.events['event_standalone'] = BandEvent(
        id: 'event_standalone',
        title: 'Original Event Title',
        eventType: 'Gig',
        description: 'Original Description',
        location: 'Stockholm',
        additionalNotes: '',
        requireResponse: true,
        startDateTime: '2026-07-01T18:00:00.000Z',
        endDateTime: '2026-07-01T21:00:00.000Z',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
      );

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_standalone'));
      await tester.pumpAndSettle();

      // Edit Name of Event
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.first, 'Altered Title For Sub');
      await tester.pumpAndSettle();

      // Original event in mockService must NOT be modified
      expect(mockService.events['event_standalone']!.title, equals('Original Event Title'));
      expect(mockService.eventWriteCalls, equals(0));
    });

    // 44. Draft badge remains removed for single slot, two slots, and multiple events.
    testWidgets('44. Draft badge is completely absent for 1 slot, 2 slots, and multiple events', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // A: 1 unpublished slot
      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Draft'), findsNothing);
      expect(find.text('[Draft]'), findsNothing);

      // B: 2 unpublished slots
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.text('Draft'), findsNothing);
      expect(find.text('[Draft]'), findsNothing);

      // C: Multiple events with slots
      setupMultiEventOccurrences();
      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_occ_1'));
      await tester.pumpAndSettle();

      expect(find.text('Draft'), findsNothing);
      expect(find.text('[Draft]'), findsNothing);
    });

    // 45. Real global Favorites persistence: complete 13-step asynchronous flow and error handling.
    testWidgets('45. Complete 13-step asynchronous Favorites persistence, write verification, and write error rejection', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      mockService.userProfiles['musician_fail'] = UserProfile(
        userId: 'musician_fail',
        displayName: 'Failing Musician',
        instruments: ['Vocals'],
      );

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // 1. Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // 2. Open + Add Favorite(s)
      await tester.tap(find.text('+ Add Favorite(s)'));
      await tester.pumpAndSettle();

      // 3. Find non-favorite profile
      final searchInput = find.widgetWithText(TextField, 'Search musicians to add as favorite...');
      expect(searchInput, findsOneWidget);
      await tester.enterText(searchInput, 'New Global');
      await tester.pumpAndSettle();
      expect(find.text('New Global Musician'), findsOneWidget);

      // 4. Add profile using canonical API
      // 5. Wait for write to complete
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // 6. Refresh/rebuild
      // 7. Confirm new Favorite remains visible in list
      expect(find.widgetWithText(CheckboxListTile, 'New Global Musician'), findsOneWidget);

      // 8. Close and reopen panel
      await tester.tap(find.text('Favorites List').first); // Close
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);

      await tester.tap(find.text('Favorites List').first); // Reopen
      await tester.pumpAndSettle();

      // 9. Confirm new Favorite remains visible
      expect(find.widgetWithText(CheckboxListTile, 'New Global Musician'), findsOneWidget);

      // 10. Confirm same Favorite is returned by getFavoriteUserIdsAsync()
      final storedIds = await mockService.getFavoriteUserIdsAsync();
      expect(storedIds, contains('musician_new'));

      // 11. Confirm it is not automatically selected as Chosen Substitute
      final newTile = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'New Global Musician'));
      expect(newTile.value, isFalse);
      expect(find.text('Chosen Substitute'), findsNothing);

      // 12. Confirm duplicates remain impossible
      await tester.enterText(searchInput, 'New Global');
      await tester.pumpAndSettle();
      expect(find.text('No matching musicians to add.'), findsOneWidget);

      // 13. Write failure handling: simulated network error does NOT falsely add locally
      mockService.shouldFailToggleFavorite = true;

      await tester.enterText(searchInput, 'Failing');
      await tester.pumpAndSettle();
      expect(find.text('Failing Musician'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Error snackbar shown
      expect(find.textContaining('Failed to add favorite'), findsOneWidget);

      // Not added to canonical service
      expect(mockService.favoriteUserIds, isNot(contains('musician_fail')));

      // Not falsely added to visible favorites list
      expect(find.widgetWithText(CheckboxListTile, 'Failing Musician'), findsNothing);
    });

    // 46. Verify Substitute and New Member Favorites independently.
    testWidgets('46. Independent verification of Substitute and New Member Favorites workflows', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // --- SUBSTITUTE MODE ---
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // One Chosen Substitute per slot: selecting collapses list and displays Chosen Substitute
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Chosen Substitute'), findsOneWidget);
      expect(find.text('Gurra'), findsOneWidget);

      // Safety: no assignedUserId or assigned status set
      expect(find.text('Assigned substitute'), findsNothing);
      expect(mockService.assignCalls, equals(0));

      // Reopening preserves checked state; clearing removes Chosen Substitute
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      final tile = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra'));
      expect(tile.value, isTrue);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();
      expect(find.text('Chosen Substitute'), findsNothing);

      // --- NEW MEMBER MODE ---
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      // Favorites List on left, Search All on right
      final favFinder = find.text('Favorites List');
      final searchAllFinder = find.text('Search All');
      expect(tester.getTopLeft(favFinder).dx, lessThan(tester.getTopLeft(searchAllFinder).dx));

      // Opens real list with canonical favorites
      await tester.tap(favFinder);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Gurra'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Alice Bass'), findsOneWidget);

      // Multi-select contracts preserved
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alice Bass'));
      await tester.pumpAndSettle();

      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Bass')).value, isTrue);
    });

    // 47. Add all favorites selects every saved Favorite without assigning a substitute, displays Chosen Substitutes, and allows individual removal.
    testWidgets('47. Add all favorites selects all saved Favorites without assigning and displays Chosen Substitutes', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Tap 'Add all favorites'
      expect(find.text('Add all favorites'), findsOneWidget);
      await tester.tap(find.text('Add all favorites'));
      await tester.pumpAndSettle();

      // Both favorites are checked
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Bass')).value, isTrue);
      expect(mockService.assignCalls, equals(0));

      // Multiple selected Favorites display 'Chosen Substitutes'
      expect(find.text('Chosen Substitutes'), findsOneWidget);
      expect(find.text('Chosen Substitute'), findsNothing);
      expect(find.textContaining('Gurra, Alice Bass'), findsOneWidget);

      // Individual favorites remain removable: uncheck Gurra
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // Now exactly one Favorite remains -> displays 'Chosen Substitute'
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra')).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Bass')).value, isTrue);
      expect(find.text('Chosen Substitute'), findsOneWidget);
      expect(find.text('Chosen Substitutes'), findsNothing);
      expect(find.text('Alice Bass'), findsWidgets);

      // Uncheck Alice Bass -> neither displays
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Alice Bass'));
      await tester.pumpAndSettle();
      expect(find.text('Chosen Substitute'), findsNothing);
      expect(find.text('Chosen Substitutes'), findsNothing);
    });

    // 48. Paid Gig displays Details field, survives serialization, and reopens correctly.
    testWidgets('48. Paid Gig displays Details field, survives serialization, and reopens correctly', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // A: When Paid Gig is true, Details field is visible
      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Travel expenses included, payment after invoice, hotel included'),
        'Travel expenses included, hotel paid',
      );
      await tester.pumpAndSettle();

      // Fill Name and Type
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.first, 'Tour Rehearsal');
      await tester.tap(find.text('Select Event Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rehearsal').last);
      await tester.pumpAndSettle();

      // Select Gurra as favorite
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gurra'));
      await tester.pumpAndSettle();

      // Publish
      await tester.tap(find.text('PUBLISH SUBSTITUTE REQUESTS (1)'));
      await tester.pumpAndSettle();

      expect(mockService.savedBatchRequests, isNotEmpty);
      final publishedReq = mockService.savedBatchRequests.first;
      expect(publishedReq.payDetails, equals('Travel expenses included, hotel paid'));

      // Serialization test
      final json = publishedReq.toJson();
      expect(json['PayDetails'], equals('Travel expenses included, hotel paid'));
      final fromJsonReq = SubRequest.fromJson(json, 'sub_test_id');
      expect(fromJsonReq.payDetails, equals('Travel expenses included, hotel paid'));

      // Reopen with initialRequest containing payDetails
      await tester.pumpWidget(createWidgetUnderTest(eventId: null, initialRequest: fromJsonReq));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Travel expenses included, hotel paid'), findsOneWidget);
    });

    // 49. Find Gigs details view displays Description (not About this event), correct Event name, and saved Paid Gig Details.
    testWidgets('49. Find Gigs details view displays Description, Event name, and saved Paid Gig Details', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      mockService.allSubRequests.clear();
      final req1 = SubRequest(
        id: 'sub_gigs_1',
        subRequestId: 'sub_gigs_1',
        slotId: 'slot_1',
        bandId: 'band_1',
        bandName: 'The Rockers',
        role: 'Substitute',
        voicePart: 'Lead Guitar',
        description: 'Need a shredder for weekend show',
        date: '2026-09-20T18:00:00Z',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm Club',
        isPaid: true,
        payAmount: 2000,
        payDetails: 'Hotel included, invoice payment',
        currency: 'SEK',
        eventTitle: 'Rock Fest 2026',
        requestGroupId: 'grp_rock_fest',
      );
      mockService.allSubRequests.add(req1);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.text('The Rockers'));
      await tester.pumpAndSettle();

      // Verifies:
      // 1. Description label, NOT About this event or About this Request
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('About this event'), findsNothing);
      expect(find.text('About this Request'), findsNothing);
      expect(find.text('Need a shredder for weekend show'), findsOneWidget);

      // 2. Event name label and value
      expect(find.text('Event name'), findsOneWidget);
      expect(find.text('Rock Fest 2026'), findsOneWidget);

      // 3. Paid Gig Details
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Hotel included, invoice payment'), findsOneWidget);
    });

    // 50. Multi-event Find Gigs details view displays correct Event name for each occurrence without single top-level title.
    testWidgets('50. Multi-event Find Gigs displays distinct Event name per occurrence without top-level collision', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      mockService.allSubRequests.clear();
      final occ1 = SubRequest(
        id: 'sub_multi_occ_1',
        subRequestId: 'sub_multi_occ_1',
        slotId: 'slot_1',
        bandId: 'band_tour',
        bandName: 'Touring Band',
        role: 'Substitute',
        voicePart: 'Lead Guitar',
        description: 'Tour gig',
        date: '2026-09-20T18:00:00Z',
        eventSequence: 1,
        eventTitle: 'Tour Stop Oslo',
        requestGroupId: 'grp_tour_distinct',
      );
      final occ2 = SubRequest(
        id: 'sub_multi_occ_2',
        subRequestId: 'sub_multi_occ_2',
        slotId: 'slot_2',
        bandId: 'band_tour',
        bandName: 'Touring Band',
        role: 'Substitute',
        voicePart: 'Rhythm Guitar',
        description: 'Tour gig',
        date: '2026-09-21T18:00:00Z',
        eventSequence: 2,
        eventTitle: 'Tour Stop Stockholm',
        requestGroupId: 'grp_tour_distinct',
      );
      mockService.allSubRequests.addAll([occ1, occ2]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Touring Band'));
      await tester.pumpAndSettle();

      // Displays both occurrence event names in their respective position sections
      expect(find.text('Tour Stop Oslo'), findsOneWidget);
      expect(find.text('Tour Stop Stockholm'), findsOneWidget);
      expect(find.text('Event name'), findsNWidgets(2));
    });

    // 51. Older requests without PayDetails load safely and display cleanly.
    test('51. Older requests without PayDetails load safely without exceptions', () {
      final legacyJson = {
        'SubRequestId': 'legacy_sub_999',
        'Role': 'Substitute',
        'VoicePart': 'Piano',
        'Date': '2026-09-10T18:00:00Z',
        'IsPaid': false,
      };

      final legacyReq = SubRequest.fromJson(legacyJson, 'legacy_sub_999');
      expect(legacyReq.payDetails, isNull);

      final legacyMap = legacyReq.toJson();
      expect(legacyMap.containsKey('PayDetails'), isFalse);
    });

    // 52. Numbered Substitute headings append straight-quoted event name with hyphen.
    testWidgets('52. Numbered Substitute headings include straight-quoted event name with hyphen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest(eventId: null));
      await tester.pumpAndSettle();

      // Set event name
      await tester.enterText(find.widgetWithText(TextField, 'Enter event name'), 'Sommarturné Gig');
      await tester.pumpAndSettle();

      // Add second slot
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1 - "Sommarturné Gig"'), findsOneWidget);
      expect(find.text('SUBSTITUTE 2 - "Sommarturné Gig"'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    // 53. Create Event does not display Generated Dates Summary, while Multiple Events generation still works.
    testWidgets('53. Create Event omits Generated Dates Summary and preserves Multiple Events generation', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: Scaffold(
              body: CreateEventPage(bandId: 'band_123'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Toggle Multiple Events switch
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Generated Dates Summary is NO LONGER visible
      expect(find.text('Generated Dates, Summary'), findsNothing);
      expect(find.text('Generated Dates Summary'), findsNothing);

      // Multiple Events generation still works: '+ Add Event(s)' is functional
      expect(find.text('+ Add Event(s)'), findsOneWidget);
      await tester.tap(find.text('+ Add Event(s)'));
      await tester.pumpAndSettle();

      expect(find.text('Add Event'), findsWidgets);
    });
  });
}
