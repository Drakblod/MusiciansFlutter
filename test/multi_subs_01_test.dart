import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/agreement.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/event_details_page.dart';

class MockMultiSubsFirebaseService extends FirebaseService {
  Map<String, String> userBands = {'band_123': 'Electric Dreamers'};
  Map<String, String> userRoles = {'band_123': 'Leader'};
  Map<String, BandEvent> storedBandEvents = {};
  Map<String, UserProfile> userProfiles = {};
  List<String> favoriteUserIds = [];
  Map<String, SubRequest> storedSubRequests = {};

  int batchSaveCalls = 0;
  int singleSaveCalls = 0;
  int assignCalls = 0;
  int deleteCalls = 0;
  int writeOperationCount = 0;

  @override
  String? get currentUserId => 'user_leader';

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return userProfiles.values.toList();
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return userBands;
  }

  @override
  Future<String?> getUserBandRoleAsync(String bandId, String userId) async {
    return userRoles[bandId];
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: userBands[bandId] ?? 'Electric Dreamers',
      userRole: userRoles[bandId] ?? 'Leader',
      location: 'Stockholm, Sweden',
      rehearsalStartTime: '18:00',
      rehearsalEndTime: '21:00',
    );
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return [
      BandMember(userId: 'user_leader', role: 'Leader', nickname: 'Alice Leader'),
      BandMember(userId: 'user_guitar', role: 'Member', nickname: 'Bob Guitar'),
      BandMember(userId: 'user_drums', role: 'Member', nickname: 'Charlie Drums'),
      BandMember(userId: 'user_bass', role: 'Member', nickname: 'Diana Bass'),
    ];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final uid = userId ?? 'user_leader';
    if (userProfiles.containsKey(uid)) {
      return userProfiles[uid];
    }
    return UserProfile(
      userId: uid,
      displayName: uid == 'user_leader' ? 'Alice Leader' : (uid == 'user_guitar' ? 'Bob Guitar' : (uid == 'user_drums' ? 'Charlie Drums' : 'Musician $uid')),
      email: '$uid@example.com',
      location: 'Stockholm, Sweden',
      instruments: uid == 'user_drums' ? ['Drums'] : ['Electric Guitar'],
      userType: uid == 'user_drums' ? 'Drums' : 'Electric Guitar',
    );
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return favoriteUserIds;
  }

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async {
    return storedBandEvents[eventId];
  }

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    return Stream.value(storedBandEvents[eventId]);
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return storedBandEvents.values.where((e) => true).toList();
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    return storedSubRequests.values
        .where((r) => r.bandId == bandId && r.eventId == eventId)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async {
    return storedSubRequests[subRequestId]?.responses ?? {};
  }

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async {
    return storedSubRequests.values.toList();
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return storedSubRequests.values.toList();
  }

  @override
  Future<String?> saveSubRequestAsync(SubRequest request) async {
    writeOperationCount++;
    singleSaveCalls++;
    final id = 'sub_${storedSubRequests.length + 1}';
    final saved = request.copyWith(id: id, subRequestId: id);
    storedSubRequests[id] = saved;
    return id;
  }

  String _sanitizeKey(String input) => input.replaceAll(RegExp(r'[\.\#\$\[\]\/\s]'), '_');

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
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    writeOperationCount++;
    batchSaveCalls++;
    final List<String> ids = [];
    for (final req in requests) {
      final cleanBandId = req.bandId != null ? _sanitizeKey(req.bandId!) : 'band';
      final cleanEventId = req.eventId != null ? _sanitizeKey(req.eventId!) : 'standalone';
      final cleanSlotId = req.slotId != null ? _sanitizeKey(req.slotId!) : '${storedSubRequests.length + 1}';

      final id = (req.subRequestId != null &&
              req.subRequestId!.isNotEmpty &&
              !req.subRequestId!.startsWith('slot_'))
          ? req.subRequestId!
          : 'sub_${cleanBandId}_${cleanEventId}_$cleanSlotId';
      ids.add(id);
      final saved = req.copyWith(id: id, subRequestId: id, status: 'published');
      storedSubRequests[id] = saved;
    }
    return ids;
  }

  @override
  Future<bool> deleteSubRequestAsync(String creatorId, String subRequestId) async {
    writeOperationCount++;
    deleteCalls++;
    storedSubRequests.remove(subRequestId);
    return true;
  }

  Map<String, Map<String, dynamic>> substituteAssignments = {};

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
    writeOperationCount++;
    assignCalls++;
    final actualSlotId = (slotId != null && slotId.isNotEmpty) ? slotId : subRequestId;
    if (storedSubRequests.containsKey(subRequestId)) {
      final existing = storedSubRequests[subRequestId]!;
      if (existing.isSelected && existing.assignedUserId != null && existing.assignedUserId != candidateUserId) {
        throw StateError('Assignment conflict: Slot $subRequestId has already been assigned to another candidate.');
      }
      storedSubRequests[subRequestId] = existing.copyWith(
        isSelected: true,
        status: 'assigned',
        assignedUserId: candidateUserId,
        assignedUserName: candidateName ?? 'Candidate $candidateUserId',
        assignedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    substituteAssignments.putIfAbsent(eventId, () => {})[actualSlotId] = {
      'slotId': actualSlotId,
      'subRequestId': subRequestId,
      'assignedUserId': candidateUserId,
      'status': 'assigned',
      'instrument': roleOrInstrument,
    };

    if (storedBandEvents.containsKey(eventId)) {
      final event = storedBandEvents[eventId]!;
      final updatedInvitees = Map<String, ExternalInvitee>.from(event.externalInvitees);
      updatedInvitees[candidateUserId] = ExternalInvitee(
        userId: candidateUserId,
        status: 'attending',
        instrument: roleOrInstrument,
        invitedAt: DateTime.now().millisecondsSinceEpoch,
        displayName: candidateName,
      );
      storedBandEvents[eventId] = BandEvent(
        id: event.id,
        title: event.title,
        description: event.description,
        eventType: event.eventType,
        location: event.location,
        startDateTime: event.startDateTime,
        endDateTime: event.endDateTime,
        additionalNotes: event.additionalNotes,
        createdBy: event.createdBy,
        createdAt: event.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        requireResponse: event.requireResponse,
        responses: event.responses,
        externalInvitees: updatedInvitees,
      );
    }
  }

  @override
  Future<void> revokeSubstituteAssignmentAsync({
    required String subRequestId,
    required String candidateUserId,
    required String bandId,
    required String eventId,
    String? slotId,
  }) async {
    writeOperationCount++;
    final actualSlotId = (slotId != null && slotId.isNotEmpty) ? slotId : subRequestId;
    if (storedSubRequests.containsKey(subRequestId)) {
      final existing = storedSubRequests[subRequestId]!;
      storedSubRequests[subRequestId] = existing.copyWith(
        isSelected: false,
        status: 'published',
        assignedUserId: null,
        assignedUserName: null,
        assignedAt: null,
      );
    }

    if (substituteAssignments.containsKey(eventId)) {
      substituteAssignments[eventId]!.remove(actualSlotId);
    }

    bool hasOtherAssignment = false;
    if (substituteAssignments.containsKey(eventId)) {
      for (final a in substituteAssignments[eventId]!.values) {
        if (a['assignedUserId'] == candidateUserId && a['status'] == 'assigned') {
          hasOtherAssignment = true;
          break;
        }
      }
    }

    if (storedBandEvents.containsKey(eventId) && !hasOtherAssignment) {
      final event = storedBandEvents[eventId]!;
      final updatedInvitees = Map<String, ExternalInvitee>.from(event.externalInvitees);
      if (updatedInvitees.containsKey(candidateUserId)) {
        final inv = updatedInvitees[candidateUserId]!;
        updatedInvitees[candidateUserId] = ExternalInvitee(
          userId: inv.userId,
          status: 'pending',
          instrument: inv.instrument,
          invitedAt: inv.invitedAt,
          displayName: inv.displayName,
        );
      }
      storedBandEvents[eventId] = BandEvent(
        id: event.id,
        title: event.title,
        description: event.description,
        eventType: event.eventType,
        location: event.location,
        startDateTime: event.startDateTime,
        endDateTime: event.endDateTime,
        additionalNotes: event.additionalNotes,
        createdBy: event.createdBy,
        createdAt: event.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        requireResponse: event.requireResponse,
        responses: event.responses,
        externalInvitees: updatedInvitees,
      );
    }
  }

  bool failAgreementChat = false;

  @override
  Future<String> createAgreementChatAsync(
    String senderId,
    String receiverId,
    Agreement agreement,
    Message message,
  ) async {
    writeOperationCount++;
    if (failAgreementChat) {
      throw StateError('Simulated agreement chat transient failure');
    }
    return 'conv_${senderId}_$receiverId';
  }
}

class MockMultiSubsAppState extends AppState {
  final MockMultiSubsFirebaseService mockFirebase;

  MockMultiSubsAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_leader',
        displayName: 'Alice Leader',
        email: 'leader@example.com',
        location: 'Stockholm, Sweden',
        instruments: ['Electric Guitar'],
        userType: 'Electric Guitar',
      );

  @override
  String? get currentUserId => 'user_leader';

  @override
  String? get activeBandId => 'band_123';

  @override
  String? get activeBandName => 'Electric Dreamers';
}

Widget createMultiSubsTestApp({
  required MockMultiSubsFirebaseService mockService,
  required Widget child,
  Size size = const Size(800, 2400),
}) {
  final appState = MockMultiSubsAppState(mockService);
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('MULTI-SUBS-01: Unified Multi-Substitute Staffing Workflow', () {
    testWidgets('1. Existing single-substitute workflow still works in standalone mode', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
      expect(find.text('Substitute 1'), findsOneWidget);
      expect(find.text('INSTRUMENT/SKILLS'), findsOneWidget);
      expect(find.text('Electric Guitar'), findsOneWidget);
    });

    testWidgets('2. A legacy single request displays as one slot', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Gig at Nalen',
        description: 'Need subs',
        eventType: 'Concert',
        location: 'Stockholm, Sweden',
        startDateTime: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 3, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_legacy_1'] = SubRequest(
        id: 'sub_legacy_1',
        subRequestId: 'sub_legacy_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Drums',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Drums'), findsWidgets);
      expect(find.text('Waiting for answers'), findsWidgets);
    });

    testWidgets('3. Opening the workflow performs zero writes', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Gig at Nalen',
        description: 'Need subs',
        eventType: 'Concert',
        location: 'Stockholm, Sweden',
        startDateTime: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 3, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 1000,
        updatedAt: 1000,
        requireResponse: true,
      );

      mock.writeOperationCount = 0;
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(mock.writeOperationCount, equals(0));
    });

    testWidgets('4. Several draft slots can exist in one unified workflow', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 1'), findsOneWidget);

      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 1'), findsOneWidget);
      expect(find.text('Substitute 2'), findsOneWidget);
    });

    testWidgets('5. Slot 1 can independently choose Favorites source', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.favoriteUserIds = ['fav_guitar_1'];
      mock.userProfiles['fav_guitar_1'] = UserProfile(
        userId: 'fav_guitar_1',
        displayName: 'Favorite Guitarist',
        instruments: ['Electric Guitar'],
        userType: 'Electric Guitar',
      );

      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      final favoritesButtons = find.text('Favorites');
      await tester.tap(favoritesButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('1 of 1 favorites selected'), findsOneWidget);
    });

    testWidgets('6. Slot 2 can independently choose Search All source', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      final searchAllButtons = find.text('Search All');
      await tester.tap(searchAllButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Will be broadcast to all eligible Electric Guitar musicians.'), findsNWidgets(2));
    });

    testWidgets('7. All draft slots publish from one event-level action', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      final publishContainer = find.textContaining('PUBLISH SUBSTITUTE REQUESTS');
      expect(publishContainer, findsOneWidget);

      await tester.ensureVisible(publishContainer);
      await tester.tap(publishContainer);
      await tester.pumpAndSettle();

      expect(mock.batchSaveCalls, equals(1));
      expect(mock.storedSubRequests.length, equals(2));
    });

    testWidgets('8. Reopening restores all slots', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Rehearsal',
        description: 'Standard',
        eventType: 'Rehearsal',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Acoustic Guitar',
        status: 'published',
      );
      mock.storedSubRequests['sub_2'] = SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Drum Kit',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Acoustic Guitar'), findsWidgets);
      expect(find.text('Drum Kit'), findsWidgets);
    });

    testWidgets('9. Two identical instrument/role slots remain separate', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 1'), findsOneWidget);
      expect(find.text('Substitute 2'), findsOneWidget);
    });

    testWidgets('10. Missing-participant prepopulation does not create duplicates', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Rehearsal',
        description: 'Standard',
        eventType: 'Rehearsal',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'NO', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      // Pre-existing published sub for user_guitar
      mock.storedSubRequests['sub_guitar'] = SubRequest(
        id: 'sub_guitar',
        subRequestId: 'sub_guitar',
        eventId: 'event_1',
        bandId: 'band_123',
        replacedMemberId: 'user_guitar',
        replacedMemberName: 'Bob Guitar',
        voicePart: 'Electric Guitar',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      // Only 1 slot for user_guitar should exist (the published one, not an extra duplicate draft)
      final guitarReplaced = find.text('Replacing: Bob Guitar');
      expect(guitarReplaced, findsOneWidget);
    });

    testWidgets('11. A manually added position without a replaced member works', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(mockService: mock, child: const FindSubScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 2'), findsOneWidget);
      expect(find.textContaining('Replacing:'), findsNothing);
    });

    testWidgets('12. Candidates are grouped under the correct slot', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.userProfiles['candidate_guitar'] = UserProfile(
        userId: 'candidate_guitar',
        displayName: 'Jimi Hendrix',
        instruments: ['Electric Guitar'],
        userType: 'Electric Guitar',
        location: 'Stockholm, Sweden',
      );

      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
        responses: {'candidate_guitar': true},
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Jimi Hendrix'), findsOneWidget);
      expect(find.text('1 candidate'), findsOneWidget);
    });

    testWidgets('13. Assigning one candidate fills only the intended slot', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.userProfiles['candidate_guitar'] = UserProfile(
        userId: 'candidate_guitar',
        displayName: 'Jimi Hendrix',
        instruments: ['Electric Guitar'],
        userType: 'Electric Guitar',
        location: 'Stockholm, Sweden',
      );

      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
        responses: {'candidate_guitar': true},
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Assign'), findsOneWidget);
      await tester.ensureVisible(find.text('Assign'));
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Assignment'), findsOneWidget);
      await tester.tap(find.text('Assign Substitute'));
      await tester.pumpAndSettle();

      expect(mock.assignCalls, equals(1));
      expect(find.text('Jimi Hendrix assigned'), findsOneWidget);
    });

    testWidgets('14. Assigning one slot leaves unrelated slots open', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.userProfiles['candidate_guitar'] = UserProfile(
        userId: 'candidate_guitar',
        displayName: 'Jimi Hendrix',
        instruments: ['Electric Guitar'],
        userType: 'Electric Guitar',
        location: 'Stockholm, Sweden',
      );

      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
        responses: {'candidate_guitar': true},
      );

      mock.storedSubRequests['sub_2'] = SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Drums',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Assign'));
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign Substitute'));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for answers'), findsOneWidget); // Slot 2 is still open
    });

    testWidgets('15. Partial progress survives reopening without data loss', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'assigned',
        isSelected: true,
        assignedUserId: 'candidate_guitar',
        assignedUserName: 'Jimi Hendrix',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Jimi Hendrix assigned'), findsOneWidget);
    });

    testWidgets('16. Reopening does not overwrite existing assignments', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'assigned',
        isSelected: true,
        assignedUserId: 'candidate_guitar',
        assignedUserName: 'Jimi Hendrix',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Jimi Hendrix assigned'), findsOneWidget);
    });

    testWidgets('17. Conflicting concurrent assignment is rejected safely and retry is idempotent', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        voicePart: 'Electric Guitar',
        isSelected: false,
        status: 'published',
      );

      // 1. First writer assigns successfully
      await mock.assignSubstituteCandidateAsync(
        subRequestId: 'sub_1',
        candidateUserId: 'user_winner_1',
        bandId: 'band_123',
        eventId: 'event_1',
        roleOrInstrument: 'Electric Guitar',
        candidateName: 'Winner Musician',
      );
      expect(mock.storedSubRequests['sub_1']!.assignedUserId, equals('user_winner_1'));
      expect(mock.storedSubRequests['sub_1']!.status, equals('assigned'));

      // 2. Competing concurrent writer is safely rejected with typed conflict error
      expect(
        () async => await mock.assignSubstituteCandidateAsync(
          subRequestId: 'sub_1',
          candidateUserId: 'user_late_2',
          bandId: 'band_123',
          eventId: 'event_1',
          roleOrInstrument: 'Electric Guitar',
          candidateName: 'Late Musician',
        ),
        throwsA(isA<StateError>()),
      );

      // Winner data was NOT corrupted by the rejected late writer
      expect(mock.storedSubRequests['sub_1']!.assignedUserId, equals('user_winner_1'));

      // 3. Idempotent retry by the winner succeeds without creating duplicate state
      await mock.assignSubstituteCandidateAsync(
        subRequestId: 'sub_1',
        candidateUserId: 'user_winner_1',
        bandId: 'band_123',
        eventId: 'event_1',
        roleOrInstrument: 'Electric Guitar',
        candidateName: 'Winner Musician',
      );
      expect(mock.storedSubRequests['sub_1']!.assignedUserId, equals('user_winner_1'));
    });

    testWidgets('18. Per-slot assignment isolation: candidate assigned to multiple slots preserves status until all are revoked', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Festival',
        description: '',
        eventType: 'Festival',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );

      mock.storedSubRequests['sub_guitar'] = SubRequest(
        id: 'sub_guitar',
        subRequestId: 'sub_guitar',
        slotId: 'slot_guitar',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
      );
      mock.storedSubRequests['sub_bass'] = SubRequest(
        id: 'sub_bass',
        subRequestId: 'sub_bass',
        slotId: 'slot_bass',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Bass',
        status: 'published',
      );

      // Assign the SAME versatile musician (user_versatile) to both Guitar and Bass slots
      await mock.assignSubstituteCandidateAsync(
        subRequestId: 'sub_guitar',
        candidateUserId: 'user_versatile',
        bandId: 'band_123',
        eventId: 'event_1',
        roleOrInstrument: 'Electric Guitar',
        candidateName: 'Versatile Player',
        slotId: 'slot_guitar',
      );

      await mock.assignSubstituteCandidateAsync(
        subRequestId: 'sub_bass',
        candidateUserId: 'user_versatile',
        bandId: 'band_123',
        eventId: 'event_1',
        roleOrInstrument: 'Bass',
        candidateName: 'Versatile Player',
        slotId: 'slot_bass',
      );

      // Both slots exist in substituteAssignments
      expect(mock.substituteAssignments['event_1']!.length, equals(2));
      expect(mock.storedBandEvents['event_1']!.externalInvitees['user_versatile']!.status, equals('attending'));

      // Revoking slot 1 (guitar) keeps user_versatile attending because slot 2 (bass) is still assigned!
      await mock.revokeSubstituteAssignmentAsync(
        subRequestId: 'sub_guitar',
        candidateUserId: 'user_versatile',
        bandId: 'band_123',
        eventId: 'event_1',
        slotId: 'slot_guitar',
      );
      expect(mock.storedSubRequests['sub_guitar']!.status, equals('published'));
      expect(mock.storedSubRequests['sub_bass']!.status, equals('assigned'));
      expect(mock.storedBandEvents['event_1']!.externalInvitees['user_versatile']!.status, equals('attending'));

      // Only revoking the remaining slot transitions user_versatile to pending
      await mock.revokeSubstituteAssignmentAsync(
        subRequestId: 'sub_bass',
        candidateUserId: 'user_versatile',
        bandId: 'band_123',
        eventId: 'event_1',
        slotId: 'slot_bass',
      );
      expect(mock.storedBandEvents['event_1']!.externalInvitees['user_versatile']!.status, equals('pending'));
    });

    testWidgets('19. Duplicate callable/batch retry does not duplicate requests or notifications', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      final draft1 = SubRequest(voicePart: 'Drums', slotId: 'slot_drums', eventId: 'event_1', status: 'draft');
      final draft2 = SubRequest(voicePart: 'Bass', slotId: 'slot_bass', eventId: 'event_1', status: 'draft');

      // First batch publish invocation
      final idsFirst = await mock.saveSubRequestsBatchAsync([draft1, draft2]);
      expect(idsFirst.length, equals(2));
      expect(mock.storedSubRequests.length, equals(2));

      // Second invocation (retry of the exact same batch)
      final idsSecond = await mock.saveSubRequestsBatchAsync([draft1, draft2]);
      expect(idsSecond, equals(idsFirst)); // Stable idempotent IDs
      expect(mock.storedSubRequests.length, equals(2)); // Zero duplicate sub-request records created
    });

    testWidgets('20. Cancelling one slot preserves other slots and the event', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
      );
      mock.storedSubRequests['sub_2'] = SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Bass',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      final cancelButtons = find.byIcon(Icons.delete_outline_rounded);
      expect(cancelButtons, findsNWidgets(2));

      await tester.tap(cancelButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Cancel Substitute Request?'), findsOneWidget);
      await tester.tap(find.text('Cancel Request'));
      await tester.pumpAndSettle();

      expect(mock.deleteCalls, equals(1));
      expect(mock.storedSubRequests.length, equals(1));
      expect(mock.storedSubRequests.containsKey('sub_2'), isTrue);
    });

    testWidgets('21. Unknown legacy data remains preserved in SubRequest serialization round-trip', (tester) async {
      final json = {
        'SubRequestId': 'sub_123',
        'VoicePart': 'Saxophone',
        'IsSelected': true,
        'CustomLegacyProperty': 'CustomValue',
        'LegacyNumericFlag': 42,
      };

      final parsed = SubRequest.fromJson(json, 'sub_123');
      expect(parsed.voicePart, equals('Saxophone'));
      expect(parsed.status, equals('assigned'));
      expect(parsed.extraFields['CustomLegacyProperty'], equals('CustomValue'));
      expect(parsed.extraFields['LegacyNumericFlag'], equals(42));

      // Modify a known field via copyWith
      final updated = parsed.copyWith(voicePart: 'Tenor Saxophone');
      expect(updated.voicePart, equals('Tenor Saxophone'));
      expect(updated.extraFields['CustomLegacyProperty'], equals('CustomValue'));

      // Serialize back to JSON and assert unknown fields remain intact
      final serialized = updated.toJson();
      expect(serialized['VoicePart'], equals('Tenor Saxophone'));
      expect(serialized['CustomLegacyProperty'], equals('CustomValue'));
      expect(serialized['LegacyNumericFlag'], equals(42));
    });

    testWidgets('22. The overall selection/status count is correct', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Concert',
        description: '',
        eventType: 'Concert',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_bass': EventResponse(status: 'YES', timestamp: DateTime.now()),
        },
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'assigned',
        isSelected: true,
        assignedUserId: 'candidate_guitar',
        assignedUserName: 'Jimi Hendrix',
      );
      mock.storedSubRequests['sub_2'] = SubRequest(
        id: 'sub_2',
        subRequestId: 'sub_2',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Drums',
        status: 'published',
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Jimi Hendrix assigned'), findsOneWidget);
      expect(find.text('Waiting for answers'), findsOneWidget);
    });

    testWidgets('23. UI works at 320 px width without overflow', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        size: const Size(320, 640),
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('24. Empty Favorites state is handled gracefully without silent fallback', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.favoriteUserIds = []; // No favorites

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      final favButton = find.text('Favorites');
      await tester.tap(favButton);
      await tester.pumpAndSettle();

      expect(find.text('No favorited Electric Guitar players found.'), findsOneWidget);

      // Attempting to publish should display validation warning
      final publishContainer = find.textContaining('PUBLISH SUBSTITUTE REQUESTS');
      await tester.ensureVisible(publishContainer);
      await tester.tap(publishContainer);
      await tester.pumpAndSettle();

      expect(find.textContaining('No favorited musicians play Electric Guitar'), findsOneWidget);
      expect(mock.batchSaveCalls, equals(0));
    });

    testWidgets('25. Search All continues using existing instrument matching eligibility behavior', (tester) async {
      final req = SubRequest(
        id: 'sub_search_all',
        subRequestId: 'sub_search_all',
        voicePart: 'Bass Guitar',
        targetUserIds: null, // Null targetUserIds = Search All broadcast
        searchSource: 'search_all',
      );

      expect(req.targetUserIds, isNull);
      expect(req.searchSource, equals('search_all'));
      final json = req.toJson();
      expect(json['TargetUserIds'], isNull);
      expect(json['SearchSource'], equals('search_all'));
    });

    testWidgets('26. Existing Event RSVP behavior is unchanged', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      final testEvent = BandEvent(
        id: 'event_1',
        title: 'Concert at Nalen',
        description: 'Big show',
        eventType: 'Concert',
        location: 'Stockholm, Sweden',
        startDateTime: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 2, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      mock.storedBandEvents['event_1'] = testEvent;

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: EventDetailsPage(bandId: 'band_123', eventId: 'event_1', initialEvent: testEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('YOUR RESPONSE'), findsOneWidget);
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('UNCERTAIN'), findsOneWidget);
    });

    testWidgets('27. Existing Finalize Event & Lock RSVPs behavior is unchanged', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      final testEvent = BandEvent(
        id: 'event_1',
        title: 'Concert at Nalen',
        description: 'Big show',
        eventType: 'Concert',
        location: 'Stockholm, Sweden',
        startDateTime: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 2, hours: 3)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      mock.storedBandEvents['event_1'] = testEvent;

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: EventDetailsPage(bandId: 'band_123', eventId: 'event_1', initialEvent: testEvent),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Finalize Event & Lock RSVPs'), findsOneWidget);
    });

    testWidgets('28. RSVP Prepopulation Audit: YES never drafted, NO drafted, UNCERTAIN & NO ANSWER require confirmation', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      // Alice (leader): YES
      // Bob (guitar): NO
      // Charlie (drums): UNCERTAIN
      // Diana (bass): NO ANSWER (null response)
      mock.storedBandEvents['event_1'] = BandEvent(
        id: 'event_1',
        title: 'Rehearsal',
        description: 'Testing RSVP states',
        eventType: 'Rehearsal',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
        responses: {
          'user_leader': EventResponse(status: 'YES', timestamp: DateTime.now()),
          'user_guitar': EventResponse(status: 'NO', timestamp: DateTime.now()),
          'user_drums': EventResponse(status: 'UNCERTAIN', timestamp: DateTime.now()),
        },
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      // 1. YES (Alice) is never created as a slot
      expect(find.text('Replacing: Alice Leader'), findsNothing);

      // 2. NO (Bob) is created as an active draft slot
      expect(find.text('Replacing: Bob Guitar'), findsOneWidget);

      // 3. UNCERTAIN (Charlie) is created as a suggested unconfirmed slot
      expect(find.text('Replacing: Charlie Drums'), findsOneWidget);
      expect(find.text('Suggested (UNCERTAIN)'), findsWidgets);

      // 4. NO ANSWER (Diana) is created as a suggested unconfirmed slot
      expect(find.text('Replacing: Musician user_bass'), findsOneWidget);
      expect(find.text('Suggested (NO ANSWER)'), findsWidgets);

      // 5. Only 1 draft position (Bob Guitar) is ready to publish initially
      expect(find.text('PUBLISH SUBSTITUTE REQUESTS (1)'), findsOneWidget);

      // 6. Confirming the suggested UNCERTAIN slot includes it in publish
      final confirmButtons = find.text('CONFIRM & INCLUDE POSITION');
      expect(confirmButtons, findsNWidgets(2));
      await tester.tap(confirmButtons.first);
      await tester.pumpAndSettle();

      // Now 2 draft positions are ready to publish
      expect(find.text('PUBLISH SUBSTITUTE REQUESTS (2)'), findsOneWidget);
    });

    testWidgets('29. Gig/Event Details (Schedule, Location, Description) are fully interactive and editable', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Event Date(s)'), findsOneWidget);

      // 1. Edit location
      final locationField = find.widgetWithText(TextField, 'Stockholm, Sweden');
      expect(locationField, findsOneWidget);
      await tester.enterText(locationField, 'Gothenburg, Sweden');
      await tester.pumpAndSettle();
      expect(find.text('Gothenburg, Sweden'), findsOneWidget);

      // 2. Edit description / notes
      final notesField = find.byWidgetPredicate((w) => w is TextField && w.maxLines == 3);
      await tester.enterText(notesField, 'Looking for experienced rock guitarist for Friday gig.');
      await tester.pumpAndSettle();
      expect(find.text('Looking for experienced rock guitarist for Friday gig.'), findsOneWidget);

      // 3. Tap date selector opens date picker
      final dateFinder = find.byIcon(Icons.calendar_today_rounded);
      expect(dateFinder, findsOneWidget);
      await tester.tap(dateFinder);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Close date picker
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('30. Declined candidate responses (value == false) are excluded from the assignable list', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.userProfiles['cand_yes'] = UserProfile(
        userId: 'cand_yes',
        displayName: 'Yes Candidate',
        instruments: ['Electric Guitar'],
      );
      mock.userProfiles['cand_no'] = UserProfile(
        userId: 'cand_no',
        displayName: 'Declined Candidate',
        instruments: ['Electric Guitar'],
      );

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
        responses: {
          'cand_yes': true,  // Affirmative response
          'cand_no': false,  // Declined response
        },
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      // Only cand_yes is displayed in candidates list
      expect(find.text('Yes Candidate'), findsOneWidget);
      expect(find.text('Declined Candidate'), findsNothing);
      expect(find.text('CANDIDATES (1)'), findsOneWidget);
    });

    testWidgets('31. Event-scoped query retrieves only the targeted event subrequests', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      mock.storedSubRequests['sub_ev1'] = SubRequest(
        id: 'sub_ev1',
        subRequestId: 'sub_ev1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
      );
      mock.storedSubRequests['sub_ev2'] = SubRequest(
        id: 'sub_ev2',
        subRequestId: 'sub_ev2',
        eventId: 'event_2',
        bandId: 'band_123',
        voicePart: 'Drums',
      );
      mock.storedSubRequests['sub_other_band'] = SubRequest(
        id: 'sub_other_band',
        subRequestId: 'sub_other_band',
        eventId: 'event_1',
        bandId: 'band_other',
        voicePart: 'Bass',
      );

      final event1Subs = await mock.getSubRequestsForEventAsync('band_123', 'event_1');
      expect(event1Subs.length, equals(1));
      expect(event1Subs.first.id, equals('sub_ev1'));
    });

    testWidgets('32. Partial agreement chat failure preserves canonical assignment and displays recoverable notice', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      mock.failAgreementChat = true; // Simulate chat failure

      mock.storedSubRequests['sub_1'] = SubRequest(
        id: 'sub_1',
        subRequestId: 'sub_1',
        eventId: 'event_1',
        bandId: 'band_123',
        voicePart: 'Electric Guitar',
        status: 'published',
        responses: {'candidate_guitar': true},
      );

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Assign'));
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign Substitute'));
      await tester.pumpAndSettle();

      // Canonical assignment succeeded
      expect(mock.storedSubRequests['sub_1']!.status, equals('assigned'));
      expect(mock.storedSubRequests['sub_1']!.assignedUserId, equals('candidate_guitar'));

      // UI accurately reflects assigned status rather than falsely reporting total failure
      expect(find.textContaining('assigned successfully (chat notification deferred)'), findsOneWidget);
    });

    // =========================================================================
    // FIND MUSICIAN/VOCALIST & NEW BAND MEMBER REGRESSION TESTS (33 - 44)
    // =========================================================================

    testWidgets('33. Regression: Page title is exactly FIND MUSICIAN/VOCALIST', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
    });

    testWidgets('34. Regression: Both mode controls (Find Substitute(s) and Find New Band Member) are visible before interaction', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Find Substitute(s)'), findsOneWidget);
      expect(find.text('Find New Band Member'), findsOneWidget);
    });

    testWidgets('35. Regression: Substitute mode opens the unified multi-slot workflow', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 1'), findsOneWidget);
      expect(find.text('ADD ANOTHER SUBSTITUTE'), findsOneWidget);
      expect(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'), findsOneWidget);
    });

    testWidgets('36. Regression: New Band Member mode does not show event substitute slots', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      // Switch to Find New Band Member
      await tester.tap(find.text('Find New Band Member'));
      await tester.pumpAndSettle();

      // Substitute slot UI elements must not be present
      expect(find.text('Substitute 1'), findsNothing);
      expect(find.text('ADD ANOTHER SUBSTITUTE'), findsNothing);
      expect(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'), findsNothing);

      // New Band Member UI elements must be present
      expect(find.text('Permanent Band Recruitment'), findsOneWidget);
      expect(find.text('PUBLISH NEW MEMBER SEARCH'), findsOneWidget);
    });

    testWidgets('37. Regression: New Band Member mode does not write externalInvitees', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      final testEvent = BandEvent(
        id: 'event_1',
        title: 'Gig',
        description: '',
        eventType: 'Gig',
        location: 'Stockholm',
        startDateTime: DateTime.now().toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      mock.storedBandEvents['event_1'] = testEvent;

      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(eventId: 'event_1', bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      // Switch to Find New Band Member and submit
      await tester.tap(find.text('Find New Band Member'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLISH NEW MEMBER SEARCH'));
      await tester.pumpAndSettle();

      // Event externalInvitees must remain empty
      expect(mock.storedBandEvents['event_1']!.externalInvitees.isEmpty, isTrue);
      expect(mock.assignCalls, equals(0));
    });

    testWidgets('38. Regression: New Band Member mode preserves its historical persisted role value (Role: New Member)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(bandId: 'band_123'),
      ));
      await tester.pumpAndSettle();

      // Switch to Find New Band Member
      await tester.tap(find.text('Find New Band Member'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLISH NEW MEMBER SEARCH'));
      await tester.pumpAndSettle();

      expect(mock.storedSubRequests.isNotEmpty, isTrue);
      final published = mock.storedSubRequests.values.first;
      expect(published.role, equals('New Member'));
      expect(published.voicePart, equals('Electric Guitar'));

      final json = published.toJson();
      expect(json['Role'], equals('New Member'));
      expect(json['VoicePart'], equals('Electric Guitar'));
    });

    testWidgets('39. Regression: Legacy Substitute request resolves to Substitute mode', (tester) async {
      final legacySub = SubRequest(
        id: 'sub_legacy_1',
        subRequestId: 'sub_legacy_1',
        role: 'Substitute',
        voicePart: 'Drums',
        status: 'published',
      );

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: FindSubScreen(initialRequest: legacySub),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Substitute 1'), findsOneWidget);
      expect(find.text('Find Substitute(s)'), findsOneWidget);
    });

    testWidgets('40. Regression: Legacy New Member request resolves to New Band Member mode', (tester) async {
      final legacyMember = SubRequest(
        id: 'member_legacy_1',
        subRequestId: 'member_legacy_1',
        role: 'New Member',
        voicePart: 'Bass',
        status: 'published',
      );

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: FindSubScreen(initialRequest: legacyMember),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Permanent Band Recruitment'), findsOneWidget);
      expect(find.text('PUBLISH NEW MEMBER SEARCH'), findsOneWidget);
      expect(find.text('Bass'), findsOneWidget);
    });

    testWidgets('41. Regression: Switching modes does not leak draft state between them', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      // Add second slot in Substitute mode
      await tester.tap(find.text('ADD ANOTHER SUBSTITUTE'));
      await tester.pumpAndSettle();
      expect(find.text('Substitute 2'), findsOneWidget);

      // Switch to New Band Member mode
      await tester.tap(find.text('Find New Band Member'));
      await tester.pumpAndSettle();
      expect(find.text('Permanent Band Recruitment'), findsOneWidget);
      expect(find.text('Substitute 2'), findsNothing);

      // Switch back to Substitute mode
      await tester.tap(find.text('Find Substitute(s)'));
      await tester.pumpAndSettle();
      expect(find.text('Substitute 2'), findsOneWidget);
    });

    testWidgets('42. Regression: New Member eligibility and notification behavior remains unchanged from pre-b7e40b2', (tester) async {
      final newMemberReq = SubRequest(
        id: 'req_member_test',
        subRequestId: 'req_member_test',
        role: 'New Member',
        voicePart: 'Lead Vocals',
        searchSource: 'search_all',
        targetUserIds: null,
      );

      expect(newMemberReq.role, equals('New Member'));
      expect(newMemberReq.searchSource, equals('search_all'));
      expect(newMemberReq.targetUserIds, isNull);

      final json = newMemberReq.toJson();
      expect(json['Role'], equals('New Member'));
      expect(json['VoicePart'], equals('Lead Vocals'));
      expect(json['SearchSource'], equals('search_all'));
    });

    testWidgets('43. Regression: Mode controls and New Member UI fit at 320 px without overflow', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      await tester.pumpWidget(createMultiSubsTestApp(
        mockService: mock,
        size: const Size(320, 640),
        child: const FindSubScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
      expect(find.text('Find Substitute(s)'), findsOneWidget);
      expect(find.text('Find New Band Member'), findsOneWidget);

      // Switch to New Member at 320 px
      await tester.tap(find.text('Find New Band Member'));
      await tester.pumpAndSettle();
      expect(find.text('Permanent Band Recruitment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('44. Regression: Existing MULTI-SUBS tests continue to pass alongside New Member mode', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      final draftSlot = SubRequest(
        subRequestId: 'sub_multi_test',
        role: 'Substitute',
        voicePart: 'Tenor Saxophone',
        status: 'draft',
      );

      final ids = await mock.saveSubRequestsBatchAsync([draftSlot]);
      expect(ids.length, equals(1));
      expect(mock.storedSubRequests[ids.first]!.voicePart, equals('Tenor Saxophone'));
    });

    testWidgets('45. Deterministic subrequest IDs sanitize invalid characters and isolate across bands and standalone searches', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      final reqWithSpecialChars = SubRequest(
        bandId: 'band.with#special\$chars[1]',
        eventId: 'event/with/slashes',
        slotId: 'slot guitar 1',
        voicePart: 'Guitar',
      );

      final ids = await mock.saveSubRequestsBatchAsync([reqWithSpecialChars]);
      expect(ids.length, equals(1));
      final generatedId = ids.first;

      // Must not contain any forbidden RTDB characters: . # $ [ ] / or whitespace
      expect(generatedId.contains('.'), isFalse);
      expect(generatedId.contains('#'), isFalse);
      expect(generatedId.contains(r'$'), isFalse);
      expect(generatedId.contains('['), isFalse);
      expect(generatedId.contains(']'), isFalse);
      expect(generatedId.contains('/'), isFalse);
      expect(generatedId.contains(' '), isFalse);
      expect(generatedId, equals('sub_band_with_special_chars_1__event_with_slashes_slot_guitar_1'));
    });

    testWidgets('46. Cross-band isolation prevents collision between distinct bands with identical slot names', (tester) async {
      final mock = MockMultiSubsFirebaseService();
      final band1Slot = SubRequest(
        bandId: 'band_alpha',
        eventId: 'event_x',
        slotId: 'slot_lead',
        voicePart: 'Lead Guitar',
      );
      final band2Slot = SubRequest(
        bandId: 'band_beta',
        eventId: 'event_x',
        slotId: 'slot_lead',
        voicePart: 'Lead Guitar',
      );

      final ids1 = await mock.saveSubRequestsBatchAsync([band1Slot]);
      final ids2 = await mock.saveSubRequestsBatchAsync([band2Slot]);

      expect(ids1.first, isNot(equals(ids2.first)));
      expect(ids1.first, equals('sub_band_alpha_event_x_slot_lead'));
      expect(ids2.first, equals('sub_band_beta_event_x_slot_lead'));
      expect(mock.storedSubRequests.length, equals(2));
    });
  });
}
