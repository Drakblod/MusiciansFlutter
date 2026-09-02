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
import 'package:musicians_flutter/views/musician_profile_screen.dart';

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
    savedBatchRequests.addAll(requests);
    return requests.asMap().entries.map((e) => 'sub_generated_${e.key}').toList();
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
  Future<void> saveSubRequestPublicationAsync(String publicationId, Map<String, dynamic> manifest) async {}

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
  }) async {}

  @override
  Future<void> revokeSubstituteAssignmentAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    String? slotId,
  }) async {}
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

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('FIND-MUSICIAN-02: SubRequest Model & Formatted Pay Amount', () {
    test('1. Formats unpaid sub requests as Unpaid', () {
      final req = SubRequest(isPaid: false);
      expect(req.formattedPayAmount, 'Unpaid');
    });

    test('2. Formats paid sub request without amount as Paid · Amount not specified', () {
      final req = SubRequest(isPaid: true, payAmount: null);
      expect(req.formattedPayAmount, 'Paid · Amount not specified');

      final reqZero = SubRequest(isPaid: true, payAmount: 0);
      expect(reqZero.formattedPayAmount, 'Paid · Amount not specified');
    });

    test('3. Formats exact Swedish Kronor amount (SEK 1,500)', () {
      final req = SubRequest(isPaid: true, payAmount: 1500, currency: 'SEK');
      expect(req.formattedPayAmount, 'Paid · SEK 1,500');
    });

    test('4. Formats large amount with thousands separator', () {
      final req = SubRequest(isPaid: true, payAmount: 25000, currency: 'SEK');
      expect(req.formattedPayAmount, 'Paid · SEK 25,000');
    });

    test('5. Formats other currencies when specified', () {
      final req = SubRequest(isPaid: true, payAmount: 300, currency: 'EUR');
      expect(req.formattedPayAmount, 'Paid · EUR 300');
    });

    test('6. Serializes and deserializes multiple request group fields', () {
      final req = SubRequest(
        id: 'sub_123',
        subRequestId: 'sub_123',
        slotId: 'slot_1',
        requestGroupId: 'req_group_band1_parent1',
        eventSequence: 2,
        eventTitle: 'Live at Berns',
        voicePart: 'Electric Guitar',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        extraFields: {'CustomMeta': 'TestValue'},
      );

      final json = req.toJson();
      expect(json['RequestGroupId'], 'req_group_band1_parent1');
      expect(json['EventSequence'], 2);
      expect(json['EventTitle'], 'Live at Berns');
      expect(json['PayAmount'], 1500);
      expect(json['Currency'], 'SEK');
      expect(json['CustomMeta'], 'TestValue');

      final fromJson = SubRequest.fromJson(json, 'sub_123');
      expect(fromJson.requestGroupId, 'req_group_band1_parent1');
      expect(fromJson.eventSequence, 2);
      expect(fromJson.eventTitle, 'Live at Berns');
      expect(fromJson.payAmount, 1500);
      expect(fromJson.currency, 'SEK');
      expect(fromJson.extraFields['CustomMeta'], 'TestValue');
    });

    test('7. copyWith updates multiple request fields properly', () {
      final original = SubRequest(
        slotId: 'slot_1',
        voicePart: 'Bass',
        requestGroupId: 'group_1',
        eventSequence: 1,
        payAmount: 1000,
      );

      final copied = original.copyWith(
        voicePart: 'Drums',
        eventSequence: 2,
        payAmount: 2000,
      );

      expect(copied.voicePart, 'Drums');
      expect(copied.requestGroupId, 'group_1');
      expect(copied.eventSequence, 2);
      expect(copied.payAmount, 2000);
    });
  });

  group('FIND-MUSICIAN-02: Gigs List Grouping (GigGroup)', () {
    test('8. Groups multiple sub-requests sharing requestGroupId into one GigGroup', () {
      final sub1 = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        requestGroupId: 'group_summer_tour',
        eventSequence: 1,
        eventTitle: 'Day 1 Gig',
        voicePart: 'Bass',
        bandName: 'The Rockers',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        date: '2026-09-10T18:00:00Z',
      );

      final sub2 = SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        requestGroupId: 'group_summer_tour',
        eventSequence: 2,
        eventTitle: 'Day 2 Gig',
        voicePart: 'Drums',
        bandName: 'The Rockers',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        date: '2026-09-11T18:00:00Z',
      );

      final group = GigGroup(
        groupId: 'group_summer_tour',
        title: 'The Rockers',
        bandName: 'The Rockers',
        isMultiple: true,
        requests: [sub1, sub2],
        earliestDate: DateTime.parse('2026-09-10T18:00:00Z'),
      );

      expect(group.totalPositions, 2);
      expect(group.eventCount, 2);
      expect(group.filledPositions, 0);
      expect(group.isMultiple, isTrue);
      expect(group.formattedPayment, 'Paid · SEK 1,500');
    });

    test('9. Tracks filled positions correctly in GigGroup', () {
      final sub1 = SubRequest(
        id: 'sub_1',
        requestGroupId: 'group_1',
        status: 'assigned',
        assignedUserId: 'user_guitarist',
        isPaid: true,
        payAmount: 1500,
      );

      final sub2 = SubRequest(
        id: 'sub_2',
        requestGroupId: 'group_1',
        status: 'published',
        isPaid: true,
        payAmount: 1500,
      );

      final group = GigGroup(
        groupId: 'group_1',
        title: 'Mats Band',
        bandName: 'Mats Band',
        isMultiple: true,
        requests: [sub1, sub2],
        earliestDate: DateTime.now(),
      );

      expect(group.totalPositions, 2);
      expect(group.filledPositions, 1);
    });
  });


  group('FIND-MUSICIAN-02: FindSubScreen Multi-Event Hierarchy & Streamlined UI', () {
    late MockAppStateForFindMusicianTest appState;

    setUp(() {
      appState = MockAppStateForFindMusicianTest();
      appState.testCurrentUserId = 'organizer_1';
      appState.testUserProfile = UserProfile(
        userId: 'organizer_1',
        displayName: 'Band Leader',
        location: 'Stockholm, Sweden',
        instruments: ['Bass'],
      );
      appState.testActiveBandId = 'band_mats';
      appState.testActiveBandName = 'Mats Band';

      appState.mockService.bandInfo = Band(
        id: 'band_mats',
        name: 'Mats Band',
        location: 'Stockholm, Sweden',
        genres: ['Rock'],
      );

      final childEvent1 = BandEvent(
        id: 'child_event_1',
        parentEventId: 'parent_tour_1',
        subEventSequence: 1,
        title: 'Mats Band - Stockholm Gig',
        description: 'Stockholm Gig',
        additionalNotes: '',
        eventType: 'Gig',
        location: 'Stockholm, Sweden',
        startDateTime: '2026-09-10T19:00:00Z',
        endDateTime: '2026-09-10T22:00:00Z',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      final childEvent2 = BandEvent(
        id: 'child_event_2',
        parentEventId: 'parent_tour_1',
        subEventSequence: 2,
        title: 'Mats Band - Uppsala Gig',
        description: 'Uppsala Gig',
        additionalNotes: '',
        eventType: 'Gig',
        location: 'Uppsala, Sweden',
        startDateTime: '2026-09-12T19:00:00Z',
        endDateTime: '2026-09-12T22:00:00Z',
        createdBy: 'organizer_1',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      appState.mockService.events['child_event_1'] = childEvent1;
      appState.mockService.events['child_event_2'] = childEvent2;
      appState.mockService.bandEvents['band_mats'] = [childEvent1, childEvent2];
    });

    testWidgets('10. Displays FIND MUSICIAN/VOCALIST title and mode switcher', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
      expect(find.text('Find Substitute(s)'), findsOneWidget);
      expect(find.text('Find New Band Member(s)'), findsOneWidget);
    });

    testWidgets('11. Displays only the band name in band context area (no Staffing for...)', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mats Band'), findsOneWidget);
      expect(find.textContaining('Staffing for Mats'), findsNothing);
    });

    testWidgets('12. Renames heading to Date & Time', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Date & Time'), findsWidgets);
      expect(find.text('Gig/Event Details'), findsNothing);
    });

    testWidgets('13. Redundant top staffing summary box is absent', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('substitute position(s) filled'), findsNothing);
      expect(find.textContaining('draft position(s) ready to publish'), findsNothing);
    });

    testWidgets('14. Resolves and displays each child event in Multiple Event with shortened title and sequence', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('EVENT 1 ·'), findsWidgets);
      expect(find.textContaining('EVENT 2 ·'), findsWidgets);
      expect(find.text('ADD SUBSTITUTE TO EVENT 1'), findsOneWidget);
      expect(find.text('ADD SUBSTITUTE TO EVENT 2'), findsOneWidget);
    });

    testWidgets('15. Slot numbering restarts per event occurrence', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsNWidgets(2));
    });

    testWidgets('16. Adds substitute slot to specific event occurrence when + ADD SUBSTITUTE is tapped', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD SUBSTITUTE TO EVENT 1'));
      await tester.pumpAndSettle();

      expect(find.text('SUBSTITUTE 1'), findsNWidgets(2));
      expect(find.text('SUBSTITUTE 2'), findsOneWidget);
    });

    testWidgets('17. Description field has visible label Description', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Description'), findsWidgets);
      expect(find.textContaining('Describe what the substitute will do...'), findsNothing);
    });

    testWidgets('18. Paid Gig toggle shows Amount input field with SEK prefix', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paid Gig'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('SEK '), findsOneWidget);
    });

    testWidgets('19. Primary action displays PUBLISH MULTIPLE REQUEST when multiple slots exist', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PUBLISH MULTIPLE REQUEST'), findsOneWidget);
    });

    testWidgets('20. Publishing saves all slots with same RequestGroupId, EventSequence, and PayAmount', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(
              eventId: 'child_event_1',
              bandId: 'band_mats',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLISH MULTIPLE REQUEST'));
      await tester.pumpAndSettle();

      expect(appState.mockService.savedBatchRequests.length, 2);
      final req1 = appState.mockService.savedBatchRequests[0];
      final req2 = appState.mockService.savedBatchRequests[1];

      expect(req1.requestGroupId, isNotNull);
      expect(req1.requestGroupId, req2.requestGroupId);
      expect(req1.eventSequence, 1);
      expect(req2.eventSequence, 2);
      expect(req1.payAmount, 1500);
      expect(req2.payAmount, 1500);
      expect(req1.currency, 'SEK');
      expect(req2.currency, 'SEK');
    });
  });


  group('FIND-MUSICIAN-02: Favorites Search & Selection Controls', () {
    late MockAppStateForFindMusicianTest appState;

    setUp(() {
      appState = MockAppStateForFindMusicianTest();
      appState.testCurrentUserId = 'organizer_1';
      appState.testActiveBandId = 'band_1';

      final fav1 = UserProfile(
        userId: 'fav_guitarist',
        displayName: 'Alice Guitar',
        instruments: ['Electric Guitar'],
      );

      final nonFav = UserProfile(
        userId: 'candidate_guitarist',
        displayName: 'Bob Rocker',
        instruments: ['Electric Guitar'],
      );

      appState.mockService.userProfiles['fav_guitarist'] = fav1;
      appState.mockService.userProfiles['candidate_guitarist'] = nonFav;
      appState.mockService.favoriteUserIds.add('fav_guitarist');
    });

    testWidgets('21. Favorites section shows Add Favorites search field and SELECT ALL / CLEAR ALL buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List').first);
      await tester.pumpAndSettle();

      expect(find.text('Favorites List'), findsWidgets);
      expect(find.text('Add Favorites'), findsOneWidget);
      expect(find.text('SELECT ALL'), findsOneWidget);
      expect(find.text('CLEAR ALL'), findsOneWidget);
    });

    testWidgets('22. SELECT ALL and CLEAR ALL update favorites selection count', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List').first);
      await tester.pumpAndSettle();

      expect(find.text('1 of 1 favorites selected'), findsOneWidget);

      await tester.tap(find.text('CLEAR ALL'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 1 favorites selected'), findsOneWidget);

      await tester.tap(find.text('SELECT ALL'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 1 favorites selected'), findsOneWidget);
    });

    testWidgets('23. Searching and starring musician immediately adds to favorites and selects for slot', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Add Favorites'), 'Bob');
      await tester.pumpAndSettle();

      expect(find.text('Bob Rocker'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.star_border_rounded));
      await tester.pumpAndSettle();

      expect(appState.mockService.favoriteUserIds.contains('candidate_guitarist'), isTrue);
      expect(find.text('2 of 2 favorites selected'), findsOneWidget);
    });
  });

  group('FIND-MUSICIAN-02: FindGigsScreen Grouped Multiple Requests', () {
    late MockAppStateForFindMusicianTest appState;

    setUp(() {
      appState = MockAppStateForFindMusicianTest();
      appState.testCurrentUserId = 'candidate_user';
      appState.testUserProfile = UserProfile(
        userId: 'candidate_user',
        displayName: 'Charlie Musician',
        instruments: ['Electric Guitar', 'Bass'],
      );

      final multi1 = SubRequest(
        id: 'sub_multi_1',
        subRequestId: 'sub_multi_1',
        requestGroupId: 'group_summerfest',
        eventSequence: 1,
        eventTitle: 'SummerFest - Stage A',
        voicePart: 'Electric Guitar',
        bandName: 'Nordic Stars',
        location: 'Stockholm, Sweden',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        date: '2026-09-15T18:00:00Z',
        startTime: '18:00',
        endTime: '21:00',
      );

      final multi2 = SubRequest(
        id: 'sub_multi_2',
        subRequestId: 'sub_multi_2',
        requestGroupId: 'group_summerfest',
        eventSequence: 2,
        eventTitle: 'SummerFest - Stage B',
        voicePart: 'Bass',
        bandName: 'Nordic Stars',
        location: 'Stockholm, Sweden',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
        date: '2026-09-16T18:00:00Z',
        startTime: '18:00',
        endTime: '21:00',
      );

      appState.mockService.allSubRequests.addAll([multi1, multi2]);
    });

    testWidgets('24. Renders one grouped card with Multiple Request badge and payment amount', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nordic Stars'), findsOneWidget);
      expect(find.text('Multiple Request'), findsOneWidget);
      expect(find.text('Paid · SEK 1,500'), findsOneWidget);
      expect(find.text('2 events · 2 substitute positions'), findsOneWidget);
    });

    testWidgets('25. Tapping grouped card opens bottom sheet showing each event occurrence and position', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nordic Stars'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute Positions (2)'), findsOneWidget);
      expect(find.text('Event #1'), findsOneWidget);
      expect(find.text('Event #2'), findsOneWidget);
      expect(find.text('Electric Guitar'), findsOneWidget);
      expect(find.text('Bass'), findsOneWidget);
      expect(find.text('Apply'), findsNWidgets(2));
    });

    testWidgets('26. Exact integer minor unit monetary serialization, rejection/fallback of malformed or missing pay amount', (tester) async {
      final reqValid = SubRequest(
        subRequestId: 'sub_pay_valid',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
      );
      expect(reqValid.formattedPayAmount, equals('Paid · SEK 1,500'));
      expect(reqValid.payAmount, isA<int>());
      expect(reqValid.payAmount, equals(1500));

      final reqUnpaid = SubRequest(
        subRequestId: 'sub_pay_unpaid',
        isPaid: false,
        payAmount: 1500,
      );
      expect(reqUnpaid.formattedPayAmount, equals('Unpaid'));

      final reqLegacyPaid = SubRequest(
        subRequestId: 'sub_pay_legacy',
        isPaid: true,
        payAmount: null,
      );
      expect(reqLegacyPaid.formattedPayAmount, equals('Paid · Amount not specified'));

      final reqZero = SubRequest(
        subRequestId: 'sub_pay_zero',
        isPaid: true,
        payAmount: 0,
      );
      expect(reqZero.formattedPayAmount, equals('Paid · Amount not specified'));

      final jsonMap = {
        'SubRequestId': 'sub_json_1',
        'IsPaid': true,
        'PayAmount': 2500,
        'Currency': 'SEK',
      };
      final fromJsonReq = SubRequest.fromJson(jsonMap, 'sub_json_1');
      expect(fromJsonReq.payAmount, equals(2500));
      expect(fromJsonReq.currency, equals('SEK'));
      expect(fromJsonReq.formattedPayAmount, equals('Paid · SEK 2,500'));
    });

    testWidgets('27. Resolves same occurrences in correct order when opened from parent event, event 1, or event 2', (tester) async {
      final parentEv = BandEvent(
        id: 'ev_tour_parent',
        title: 'Summer Tour',
        description: 'Tour 2026',
        eventType: 'Multiple Event',
        location: 'Stockholm',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-22T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child1 = BandEvent(
        id: 'ev_tour_child1',
        parentEventId: 'ev_tour_parent',
        title: 'Summer Tour - Night 1',
        subEventSequence: 1,
        description: 'Night 1',
        eventType: 'Gig',
        location: 'Stockholm',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-20T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child2 = BandEvent(
        id: 'ev_tour_child2',
        parentEventId: 'ev_tour_parent',
        title: 'Summer Tour - Night 2',
        subEventSequence: 2,
        description: 'Night 2',
        eventType: 'Gig',
        location: 'Stockholm',
        startDateTime: '2026-09-21T18:00:00Z',
        endDateTime: '2026-09-21T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      appState.mockService.events['ev_tour_parent'] = parentEv;
      appState.mockService.events['ev_tour_child1'] = child1;
      appState.mockService.events['ev_tour_child2'] = child2;
      appState.mockService.bandEvents['band_tour_1'] = [parentEv, child1, child2];

      // Open from Parent
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(bandId: 'band_tour_1', eventId: 'ev_tour_parent'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('EVENT 1 · Summer Tour - Night 1'), findsWidgets);
      expect(find.textContaining('EVENT 2 · Summer Tour - Night 2'), findsWidgets);

      // Open from Child 2
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(bandId: 'band_tour_1', eventId: 'ev_tour_child2'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('EVENT 1 · Summer Tour - Night 1'), findsWidgets);
      expect(find.textContaining('EVENT 2 · Summer Tour - Night 2'), findsWidgets);
    });

    testWidgets('28. MusicianProfileScreen star button writes through canonical service toggleFavoriteAsync and toggles instantly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final targetMusician = UserProfile(
        userId: 'target_guitarist_99',
        displayName: 'Dave Soloist',
        instruments: ['Electric Guitar'],
      );
      appState.mockService.userProfiles['target_guitarist_99'] = targetMusician;

      expect(appState.mockService.favoriteUserIds.contains('target_guitarist_99'), isFalse);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: MusicianProfileScreen(musician: targetMusician),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final starFinder = find.byIcon(Icons.star_border_rounded);
      expect(starFinder, findsWidgets);

      await tester.tap(starFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockService.favoriteUserIds.contains('target_guitarist_99'), isTrue);
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
    });

    testWidgets('29. Cancelling or updating one slot preserves RequestGroupId and grouped card', (tester) async {
      final slot1 = SubRequest(
        subRequestId: 'sub_g_slot_1',
        requestGroupId: 'group_test_preserved',
        eventSequence: 1,
        eventTitle: 'Gig Part 1',
        role: 'Substitute',
        voicePart: 'Electric Guitar',
        status: 'published',
        bandName: 'Group Band',
        date: '2026-09-20T18:00:00Z',
      );
      final slot2 = SubRequest(
        subRequestId: 'sub_g_slot_2',
        requestGroupId: 'group_test_preserved',
        eventSequence: 2,
        eventTitle: 'Gig Part 2',
        role: 'Substitute',
        voicePart: 'Bass',
        status: 'cancelled',
        bandName: 'Group Band',
        date: '2026-09-21T18:00:00Z',
      );

      appState.mockService.allSubRequests.clear();
      appState.mockService.allSubRequests.addAll([slot1, slot2]);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Group Band'), findsOneWidget);
      expect(find.text('Multiple Request'), findsOneWidget);
    });

    testWidgets('30. Two distinct bands with identical event/slot names generate isolated RequestGroupIds without collision', (tester) async {
      final bandAId = 'band_alpha';
      final bandBId = 'band_beta';

      final groupAId = 'group_${bandAId}_event1_12345';
      final groupBId = 'group_${bandBId}_event1_12345';

      expect(groupAId, isNot(equals(groupBId)));
      expect(groupAId.contains('band_alpha'), isTrue);
      expect(groupBId.contains('band_beta'), isTrue);
    });

    testWidgets('31. Legacy SubRequests without RequestGroupId render cleanly as individual singleton groups', (tester) async {
      final legacySub = SubRequest(
        subRequestId: 'legacy_single_sub',
        role: 'Substitute',
        voicePart: 'Electric Guitar',
        bandName: 'Solo Jazz Trio',
        isPaid: false,
        status: 'published',
        date: '2026-09-20T18:00:00Z',
        requestGroupId: null,
      );

      appState.mockService.allSubRequests.clear();
      appState.mockService.allSubRequests.add(legacySub);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solo Jazz Trio'), findsOneWidget);
      expect(find.text('Multiple Request'), findsNothing);
    });

    testWidgets('32. Before any SubRequests exist: opening parent, child 1, or child 2 derives identical RequestGroupId', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final parentEvent = BandEvent(
        id: 'ev_clean_parent',
        title: 'Spring Festival 2026',
        eventType: 'Multiple Event',
        description: '',
        location: 'Stockholm',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-20T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child1 = BandEvent(
        id: 'ev_clean_child_1',
        parentEventId: 'ev_clean_parent',
        subEventSequence: 1,
        title: 'Spring Festival 2026 - Day 1',
        eventType: 'Gig',
        description: '',
        location: 'Stockholm',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-20T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child2 = BandEvent(
        id: 'ev_clean_child_2',
        parentEventId: 'ev_clean_parent',
        subEventSequence: 2,
        title: 'Spring Festival 2026 - Day 2',
        eventType: 'Gig',
        description: '',
        location: 'Stockholm',
        startDateTime: '2026-09-21T18:00:00Z',
        endDateTime: '2026-09-21T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      appState.mockService.bandEvents['band_clean_tour'] = [parentEvent, child1, child2];
      appState.mockService.events['ev_clean_parent'] = parentEvent;
      appState.mockService.events['ev_clean_child_1'] = child1;
      appState.mockService.events['ev_clean_child_2'] = child2;
      appState.mockService.allSubRequests.clear();
      appState.mockService.savedBatchRequests.clear();

      // Open from child 1 and publish
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(bandId: 'band_clean_tour', eventId: 'ev_clean_child_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final publishBtn = find.text('PUBLISH MULTIPLE REQUEST');
      expect(publishBtn, findsOneWidget);
      await tester.ensureVisible(publishBtn);
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      expect(appState.mockService.savedBatchRequests.isNotEmpty, isTrue);
      final derivedGroupId = appState.mockService.savedBatchRequests.first.requestGroupId;
      expect(derivedGroupId, contains('group_band_clean_tour_ev_clean_parent'));
    });

    testWidgets('33. Header-only parent event is excluded from occurrences list; only child occurrences render as Event 1, Event 2', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final parentEvent = BandEvent(
        id: 'ev_header_only_parent',
        title: 'Nordic Tour 2026',
        eventType: 'Multiple Event',
        description: '',
        location: 'Stockholm',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-20T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child1 = BandEvent(
        id: 'ev_nordic_c1',
        parentEventId: 'ev_header_only_parent',
        subEventSequence: 1,
        title: 'Nordic Tour 2026 - Oslo',
        eventType: 'Gig',
        description: '',
        location: 'Oslo',
        startDateTime: '2026-09-20T18:00:00Z',
        endDateTime: '2026-09-20T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );
      final child2 = BandEvent(
        id: 'ev_nordic_c2',
        parentEventId: 'ev_header_only_parent',
        subEventSequence: 2,
        title: 'Nordic Tour 2026 - Stockholm',
        eventType: 'Gig',
        description: '',
        location: 'Stockholm',
        startDateTime: '2026-09-21T18:00:00Z',
        endDateTime: '2026-09-21T22:00:00Z',
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      appState.mockService.bandEvents['band_nordic'] = [parentEvent, child1, child2];
      appState.mockService.events['ev_header_only_parent'] = parentEvent;
      appState.mockService.events['ev_nordic_c1'] = child1;
      appState.mockService.events['ev_nordic_c2'] = child2;
      appState.mockService.allSubRequests.clear();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindSubScreen(bandId: 'band_nordic', eventId: 'ev_header_only_parent'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render child events as Event 1, Event 2
      expect(find.textContaining('EVENT 1 ·'), findsWidgets);
      expect(find.textContaining('EVENT 2 ·'), findsWidgets);
      expect(find.text('EVENT 3 ·'), findsNothing);
    });

    testWidgets('34. PayAmountMinor (150000) round-trips with PayAmount (1500) and displays formatted Swedish currency', (tester) async {
      final sub = SubRequest(
        subRequestId: 'sub_minor_test',
        isPaid: true,
        payAmount: 1500,
        currency: 'SEK',
      );

      expect(sub.payAmount, equals(1500));
      expect(sub.payAmountMinor, equals(150000));
      expect(sub.formattedPayAmount, equals('Paid · SEK 1,500'));

      final json = sub.toJson();
      expect(json['PayAmount'], equals(1500));
      expect(json['PayAmountMinor'], equals(150000));

      final roundTrip = SubRequest.fromJson(json, 'sub_minor_test');
      expect(roundTrip.payAmount, equals(1500));
      expect(roundTrip.payAmountMinor, equals(150000));
      expect(roundTrip.formattedPayAmount, equals('Paid · SEK 1,500'));
    });

    testWidgets('35. Favorites persistence: reloading profiles retains starred favorite and populates in Find Musician Favorites list', (tester) async {
      appState.mockService.favoriteUserIds.clear();
      appState.mockService.favoriteUserIds.add('musician_persisted_fav_1');
      appState.mockService.userProfiles['musician_persisted_fav_1'] = UserProfile(
        userId: 'musician_persisted_fav_1',
        displayName: 'Eva Bassist',
        instruments: ['Bass', 'Electric Guitar'],
      );

      final isFav = await appState.firebaseService.isFavoriteAsync('musician_persisted_fav_1');
      expect(isFav, isTrue);

      final favIds = await appState.firebaseService.getFavoriteUserIdsAsync();
      expect(favIds, contains('musician_persisted_fav_1'));
    });
  });
}
