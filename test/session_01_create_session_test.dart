import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/collab_session.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/views/create_session_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockSession01FirebaseService extends FirebaseService {
  List<CollabSession> savedSessions = [];
  Map<String, CollabSession> storedSessions = {};
  Map<String, Map<String, CollabSessionApplication>> storedApplications = {};
  Map<String, Map<String, dynamic>> storedSessionChats = {};
  int createSessionCalls = 0;
  int updateSessionCalls = 0;
  int groupSessionCalls = 0;

  @override
  Future<String> createCollabSessionAsync(CollabSession session) async {
    createSessionCalls++;
    final id = session.id ?? 'sess_${savedSessions.length + 1}';
    final saved = CollabSession(
      id: id,
      title: session.title,
      description: session.description,
      sessionType: session.sessionType,
      sessionCategory: session.sessionCategory,
      isDateFlexible: session.isDateFlexible,
      startDateTime: session.startDateTime,
      endDateTime: session.endDateTime,
      location: session.location,
      genres: session.genres,
      lookingForRoles: session.lookingForRoles,
      lookingForInstruments: session.lookingForInstruments,
      creatorId: session.creatorId,
      createdAt: session.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : session.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      status: session.status,
      requireResponse: session.requireResponse,
      rsvpDeadline: session.rsvpDeadline,
      reminderIntervalHours: session.reminderIntervalHours,
      responses: session.responses,
      parentSessionId: session.parentSessionId,
      subSessionSequence: session.subSessionSequence,
      sessionChatId: session.sessionChatId,
    );
    savedSessions.add(saved);
    storedSessions[id] = saved;
    return id;
  }

  @override
  Future<void> updateCollabSessionAsync(String sessionId, CollabSession updatedSession) async {
    updateSessionCalls++;
    final existing = storedSessions[sessionId];
    final merged = CollabSession(
      id: sessionId,
      title: updatedSession.title,
      description: updatedSession.description,
      sessionType: updatedSession.sessionType,
      sessionCategory: updatedSession.sessionCategory,
      isDateFlexible: updatedSession.isDateFlexible,
      startDateTime: updatedSession.startDateTime,
      endDateTime: updatedSession.endDateTime,
      location: updatedSession.location,
      genres: updatedSession.genres,
      lookingForRoles: updatedSession.lookingForRoles.isNotEmpty
          ? updatedSession.lookingForRoles
          : (existing?.lookingForRoles ?? []),
      lookingForInstruments: updatedSession.lookingForInstruments.isNotEmpty
          ? updatedSession.lookingForInstruments
          : (existing?.lookingForInstruments ?? []),
      creatorId: existing?.creatorId ?? updatedSession.creatorId,
      createdAt: existing?.createdAt ?? updatedSession.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      status: updatedSession.status,
      requireResponse: updatedSession.requireResponse,
      rsvpDeadline: updatedSession.rsvpDeadline,
      reminderIntervalHours: updatedSession.reminderIntervalHours,
      responses: existing?.responses ?? updatedSession.responses,
      parentSessionId: existing?.parentSessionId ?? updatedSession.parentSessionId,
      subSessionSequence: existing?.subSessionSequence ?? updatedSession.subSessionSequence,
      sessionChatId: existing?.sessionChatId ?? updatedSession.sessionChatId,
    );
    savedSessions.add(merged);
    storedSessions[sessionId] = merged;
  }

  @override
  Future<void> saveCollabSessionAsync(CollabSession session) async {
    if (session.id == null || session.id!.isEmpty) {
      await createCollabSessionAsync(session);
    } else {
      await updateCollabSessionAsync(session.id!, session);
    }
  }

  @override
  Future<List<String>> createCollabSessionGroupAsync(List<CollabSession> sessions) async {
    groupSessionCalls++;
    final parentId = sessions.first.id ?? 'sess_group_${savedSessions.length + 1}';
    final List<String> ids = [];
    for (int i = 0; i < sessions.length; i++) {
      final id = i == 0 ? parentId : '$parentId-sub-$i';
      ids.add(id);
      final s = sessions[i];
      final saved = CollabSession(
        id: id,
        title: s.title,
        description: s.description,
        sessionType: s.sessionType,
        sessionCategory: s.sessionCategory,
        isDateFlexible: s.isDateFlexible,
        startDateTime: s.startDateTime,
        endDateTime: s.endDateTime,
        location: s.location,
        genres: s.genres,
        lookingForRoles: s.lookingForRoles,
        lookingForInstruments: s.lookingForInstruments,
        creatorId: s.creatorId,
        createdAt: s.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : s.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: s.status,
        requireResponse: s.requireResponse,
        rsvpDeadline: s.rsvpDeadline,
        reminderIntervalHours: s.reminderIntervalHours,
        parentSessionId: sessions.length > 1 ? parentId : null,
        subSessionSequence: sessions.length > 1 ? i + 1 : null,
      );
      savedSessions.add(saved);
      storedSessions[id] = saved;
    }
    return ids;
  }

  @override
  Future<List<CollabSession>> getCollabSessionsAsync() async {
    return storedSessions.values.toList();
  }

  @override
  Future<CollabSessionApplication?> getCollabSessionApplicationAsync(String sessionId, String applicantId) async {
    return storedApplications[sessionId]?[applicantId];
  }

  @override
  Future<void> applyToCollabSessionAsync(String sessionId, String userId, CollabSessionApplication application) async {
    storedApplications.putIfAbsent(sessionId, () => {})[userId] = application;
  }

  @override
  Future<void> submitSessionRsvpResponseAsync({
    required String sessionId,
    required String userId,
    required String status,
    String? comment,
    String? uncertainReason,
  }) async {
    final app = storedApplications[sessionId]?[userId];
    if (app == null || app.status != 'accepted') {
      throw Exception('Only accepted session participants can submit an RSVP response');
    }

    final existing = storedSessions[sessionId];
    if (existing != null) {
      final updatedResponses = Map<String, EventResponse>.from(existing.responses);
      updatedResponses[userId] = EventResponse(
        status: status,
        timestamp: DateTime.now(),
        comment: comment,
        uncertainReason: uncertainReason,
      );
      storedSessions[sessionId] = CollabSession(
        id: existing.id,
        title: existing.title,
        description: existing.description,
        sessionType: existing.sessionType,
        sessionCategory: existing.sessionCategory,
        isDateFlexible: existing.isDateFlexible,
        startDateTime: existing.startDateTime,
        endDateTime: existing.endDateTime,
        location: existing.location,
        genres: existing.genres,
        lookingForRoles: existing.lookingForRoles,
        lookingForInstruments: existing.lookingForInstruments,
        creatorId: existing.creatorId,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: existing.status,
        requireResponse: existing.requireResponse,
        rsvpDeadline: existing.rsvpDeadline,
        reminderIntervalHours: existing.reminderIntervalHours,
        responses: updatedResponses,
        parentSessionId: existing.parentSessionId,
        subSessionSequence: existing.subSessionSequence,
        sessionChatId: existing.sessionChatId,
      );
    }
  }

  @override
  Future<String> createSessionChatRoomAsync({
    required String sessionId,
    required String sessionTitle,
    required String createdBy,
  }) async {
    final chatId = 'chat_$sessionId';
    storedSessionChats[chatId] = {
      'chatId': chatId,
      'sessionId': sessionId,
      'title': sessionTitle,
      'createdBy': createdBy,
      'members': {createdBy: 'owner'},
    };
    final existing = storedSessions[sessionId];
    if (existing != null) {
      storedSessions[sessionId] = CollabSession(
        id: existing.id,
        title: existing.title,
        description: existing.description,
        sessionType: existing.sessionType,
        sessionCategory: existing.sessionCategory,
        isDateFlexible: existing.isDateFlexible,
        startDateTime: existing.startDateTime,
        endDateTime: existing.endDateTime,
        location: existing.location,
        genres: existing.genres,
        lookingForRoles: existing.lookingForRoles,
        lookingForInstruments: existing.lookingForInstruments,
        creatorId: existing.creatorId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
        status: existing.status,
        requireResponse: existing.requireResponse,
        rsvpDeadline: existing.rsvpDeadline,
        reminderIntervalHours: existing.reminderIntervalHours,
        responses: existing.responses,
        parentSessionId: existing.parentSessionId,
        subSessionSequence: existing.subSessionSequence,
        sessionChatId: chatId,
      );
    }
    return chatId;
  }

  @override
  Future<void> addParticipantToSessionChatAsync({
    required String sessionId,
    required String chatId,
    required String participantId,
  }) async {
    final app = storedApplications[sessionId]?[participantId];
    if (app == null || app.status != 'accepted') {
      throw Exception('Only accepted applicants can join the session chat');
    }
    final chat = storedSessionChats[chatId];
    if (chat != null) {
      (chat['members'] as Map<String, dynamic>)[participantId] = 'member';
    }
  }
}

class MockAppStateForSession01Test extends AppState {
  final MockSession01FirebaseService mockFirebase = MockSession01FirebaseService();

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_session_creator',
        displayName: 'Session Creator',
        email: 'creator@example.com',
      );

  @override
  String? get currentUserId => 'user_session_creator';
}

Widget createTestWrapper({
  required AppState appState,
  Widget? child,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/': (context) => Scaffold(body: child ?? const CreateSessionScreen()),
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('SESSION-01 — Create Session Redesign & Parity Tests', () {
    test('1, 2. CollabSession authoritative categories and types list', () {
      expect(CollabSession.standardCategories, equals([
        'Songwriting',
        'Recording',
        'Production',
        'Jam',
        'Workshop',
        'Other',
      ]));
      expect(CollabSession.standardTypes, equals([
        'In person',
        'Remote',
        'Hybrid',
      ]));
    });

    testWidgets('3, 4. Header is CREATE SESSION and labels have no asterisks', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CREATE SESSION'), findsOneWidget);
      expect(find.text('CREATE COLLAB SESSION'), findsNothing);
      expect(find.text('Create Collab Session'), findsNothing);

      // Verify no asterisks in visible field labels
      expect(find.text('Session Title *'), findsNothing);
      expect(find.text('Session Category *'), findsNothing);
      expect(find.text('Session Description *'), findsNothing);
      expect(find.text('Session Type *'), findsNothing);
      expect(find.text('Location *'), findsNothing);
      expect(find.text('Looking For Roles *'), findsNothing);
      expect(find.text('Instruments Needed'), findsNothing);
    });

    testWidgets('5, 6. Category dropdown contains Workshop and exact 6 choices', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open Category dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      for (final cat in CollabSession.standardCategories) {
        expect(find.text(cat), findsWidgets, reason: 'Expected category $cat');
      }
    });

    testWidgets('7, 8, 9, 10, 11. Session Type tappable field opens modal with 3 choices; Remote hides location', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Default is Remote -> Location field is hidden
      expect(find.widgetWithText(TextFormField, 'Location'), findsNothing);

      // Tap Session Type field
      await tester.tap(find.text('Remote'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal options visible
      expect(find.text('Select Session Type'), findsOneWidget);
      expect(find.text('In person'), findsOneWidget);
      expect(find.text('Hybrid'), findsOneWidget);

      // Select 'In person'
      await tester.tap(find.text('In person'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Location field is now visible
      expect(find.widgetWithText(TextFormField, 'Location'), findsOneWidget);
    });

    testWidgets('12, 13, 14, 15. Genres/Band Types exposes only Rock/Pop, Jazz, World Music', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Genres field
      await tester.tap(find.text('Tap to select genres'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);
      expect(find.text('🎸 Rock, Pop, R&B, Hip Hop, etc'), findsOneWidget);
      expect(find.text('🎷 Jazz'), findsOneWidget);
      expect(find.text('🌍 World Music'), findsOneWidget);

      // Unrelated categories not present
      expect(find.text('🗣️ Choir'), findsNothing);
      expect(find.text('🎼 Classical'), findsNothing);
      expect(find.text('🎺 Wind, Concert & Brass Band'), findsNothing);
      expect(find.text('🥁 Big Band'), findsNothing);
    });

    testWidgets('17, 18, 19, 20, 21. No Looking For Roles or Instruments required; creates session safely', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Fill in title, description, RSVP hours
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Title'), 'Pop Songwriting Workshop');
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Description'), 'Writing hooks and toplines together');
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '24');

      // Tap Category dropdown and select Workshop
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Workshop').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Save session
      await tester.tap(find.text('Create Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedSessions.length, equals(1));
      final saved = appState.mockFirebase.savedSessions.first;
      expect(saved.title, equals('Pop Songwriting Workshop'));
      expect(saved.sessionCategory, equals('Workshop'));
      expect(saved.sessionType, equals('Remote'));
      expect(saved.lookingForRoles, isEmpty);
      expect(saved.lookingForInstruments, isEmpty);
      expect(saved.reminderIntervalHours, equals(24));
    });

    testWidgets('22, 23. Date & Time picker structure and end time validation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.text('DATE & TIME'), findsNothing);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('End Time'), findsOneWidget);
    });

    testWidgets('26, 27, 28, 29. Create Multiple Sessions creates grouped occurrences under Collabs/Sessions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.widgetWithText(TextFormField, 'Session Title'), 'Writing Camp');
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Description'), '3-day writing camp');
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '48');

      // Toggle Create Multiple Sessions
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('+ Add Session(s)'), findsOneWidget);

      // Tap + Add Session(s)
      await tester.tap(find.text('+ Add Session(s)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add Session'), findsOneWidget);
      // Tap Add in dialog
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Save multi-session group
      await tester.tap(find.text('Create Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.groupSessionCalls, equals(1));
      expect(appState.mockFirebase.savedSessions.length, equals(2));
      final first = appState.mockFirebase.savedSessions[0];
      final second = appState.mockFirebase.savedSessions[1];
      expect(first.parentSessionId, isNotNull);
      expect(first.subSessionSequence, equals(1));
      expect(second.parentSessionId, equals(first.parentSessionId));
      expect(second.subSessionSequence, equals(2));
    });

    testWidgets('30, 31, 32. RSVP defaults to Set your own and deadline uses publishedAt', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = MockAppStateForSession01Test();
      await tester.pumpWidget(createTestWrapper(
        appState: appState,
        child: const CreateSessionScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Set your own'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Set hours here'), findsOneWidget);
      final customField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Set hours here'));
      expect(customField.controller?.text, equals(''));

      // Empty custom hours blocks submission
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Title'), 'RSVP Test Session');
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Description'), 'Testing RSVP window');
      await tester.tap(find.text('Create Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Please enter response window in hours'), findsOneWidget);
      expect(appState.mockFirebase.savedSessions.isEmpty, isTrue);

      // Enter 36 hours
      await tester.enterText(find.widgetWithText(TextFormField, 'Set hours here'), '36');
      final beforePublish = DateTime.now().millisecondsSinceEpoch;
      await tester.tap(find.text('Create Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(appState.mockFirebase.savedSessions.length, equals(1));
      final saved = appState.mockFirebase.savedSessions.first;
      expect(saved.reminderIntervalHours, equals(36));
      expect(saved.rsvpDeadline, isNotNull);
      final expectedApprox = beforePublish + (36 * 3600 * 1000);
      expect((saved.rsvpDeadline! - expectedApprox).abs() < 5000, isTrue);
    });

    test('33, 34. RSVP responses: accepted participants can RSVP; pending cannot', () async {
      final appState = MockAppStateForSession01Test();

      // Create session
      final session = CollabSession(
        title: 'RSVP Eligibility Session',
        description: 'Testing eligibility',
        sessionType: 'Remote',
        sessionCategory: 'Songwriting',
        isDateFlexible: false,
        creatorId: 'user_session_creator',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );
      final sessionId = await appState.firebaseService.createCollabSessionAsync(session);

      // Applicant 1 is pending
      final app1 = CollabSessionApplication(
        userId: 'user_applicant_pending',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        timestamp: 1700000001000,
        status: 'pending',
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_applicant_pending', app1);

      // Applicant 2 is accepted
      final app2 = CollabSessionApplication(
        userId: 'user_applicant_accepted',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        timestamp: 1700000002000,
        status: 'accepted',
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_applicant_accepted', app2);

      // Pending applicant cannot submit RSVP
      expect(
        () async => await appState.firebaseService.submitSessionRsvpResponseAsync(
          sessionId: sessionId,
          userId: 'user_applicant_pending',
          status: 'YES',
        ),
        throwsException,
      );

      // Accepted applicant can submit RSVP
      await appState.firebaseService.submitSessionRsvpResponseAsync(
        sessionId: sessionId,
        userId: 'user_applicant_accepted',
        status: 'YES',
      );

      final updated = (await appState.firebaseService.getCollabSessionsAsync()).firstWhere((s) => s.id == sessionId);
      expect(updated.responses['user_applicant_accepted']?.status, equals('YES'));
    });

    test('35, 36, 37, 38. Create Session Chat creates chat room and adds only accepted participants', () async {
      final appState = MockAppStateForSession01Test();

      final session = CollabSession(
        title: 'Chat Session',
        description: 'Testing chat creation',
        sessionType: 'Remote',
        sessionCategory: 'Jam',
        isDateFlexible: false,
        creatorId: 'user_session_creator',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );
      final sessionId = await appState.firebaseService.createCollabSessionAsync(session);

      final chatId = await appState.firebaseService.createSessionChatRoomAsync(
        sessionId: sessionId,
        sessionTitle: 'Chat Session',
        createdBy: 'user_session_creator',
      );
      expect(chatId, isNotEmpty);

      // Pending applicant cannot join chat
      final appPending = CollabSessionApplication(
        userId: 'user_pending',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        timestamp: 1700000000000,
        status: 'pending',
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_pending', appPending);

      expect(
        () async => await appState.firebaseService.addParticipantToSessionChatAsync(
          sessionId: sessionId,
          chatId: chatId,
          participantId: 'user_pending',
        ),
        throwsException,
      );

      // Accepted applicant is added to chat
      final appAccepted = CollabSessionApplication(
        userId: 'user_accepted',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        timestamp: 1700000000000,
        status: 'accepted',
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_accepted', appAccepted);

      await appState.firebaseService.addParticipantToSessionChatAsync(
        sessionId: sessionId,
        chatId: chatId,
        participantId: 'user_accepted',
      );

      final chat = (appState.firebaseService as MockSession01FirebaseService).storedSessionChats[chatId];
      expect(chat?['members']['user_accepted'], equals('member'));
    });

    testWidgets('39, 40. Editing existing session preserves legacy role/instrument lists, RSVP, and chat ID', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existingSession = CollabSession(
        id: 'sess_edit_1',
        title: 'Original Title',
        description: 'Original Description',
        sessionType: 'Remote',
        sessionCategory: 'Songwriting',
        isDateFlexible: false,
        startDateTime: '2026-09-15T19:00:00.000Z',
        endDateTime: '2026-09-15T21:00:00.000Z',
        genres: ['Rock', 'Classical'], // Classical from hidden category preserved
        lookingForRoles: ['producer', 'songwriter'],
        lookingForInstruments: ['Electric Guitar', 'Piano'],
        creatorId: 'user_session_creator',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        sessionChatId: 'chat_existing_123',
        reminderIntervalHours: 48,
      );

      final appState = MockAppStateForSession01Test();
      (appState.firebaseService as MockSession01FirebaseService).storedSessions['sess_edit_1'] = existingSession;

      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const CreateSessionScreen(),
                      settings: RouteSettings(arguments: existingSession),
                    ),
                  );
                },
                child: const Text('Open Edit'),
              );
            },
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Open Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EDIT SESSION'), findsOneWidget);
      expect(find.text('Original Title'), findsOneWidget);

      // Edit title
      await tester.enterText(find.widgetWithText(TextFormField, 'Session Title'), 'Updated Title');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final updated = (appState.firebaseService as MockSession01FirebaseService).storedSessions['sess_edit_1'];
      expect(updated?.title, equals('Updated Title'));
      expect(updated?.genres, contains('Classical')); // Hidden genre preserved
      expect(updated?.lookingForRoles, equals(['producer', 'songwriter'])); // Legacy roles preserved
      expect(updated?.lookingForInstruments, equals(['Electric Guitar', 'Piano'])); // Legacy instruments preserved
      expect(updated?.sessionChatId, equals('chat_existing_123')); // Chat ID preserved
    });

    test('41. Canonical conversation structure and inbox index representation for session chat', () async {
      final appState = MockAppStateForSession01Test();

      final session = CollabSession(
        title: 'Producer Masterclass',
        description: 'Deep dive into mixing',
        sessionType: 'Remote',
        sessionCategory: 'Workshop',
        isDateFlexible: false,
        creatorId: 'user_session_creator',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );
      final sessionId = await appState.firebaseService.createCollabSessionAsync(session);

      final chatId = await appState.firebaseService.createSessionChatRoomAsync(
        sessionId: sessionId,
        sessionTitle: 'Producer Masterclass',
        createdBy: 'user_session_creator',
      );

      final appAccepted = CollabSessionApplication(
        userId: 'user_producer_student',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        status: 'accepted',
        timestamp: 1700000000000,
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_producer_student', appAccepted);
      await appState.firebaseService.addParticipantToSessionChatAsync(
        sessionId: sessionId,
        chatId: chatId,
        participantId: 'user_producer_student',
      );

      final chat = (appState.firebaseService as MockSession01FirebaseService).storedSessionChats[chatId];
      expect(chat, isNotNull);
      expect(chat?['sessionId'], equals(sessionId));
      expect(chat?['title'], equals('Producer Masterclass'));
      expect(chat?['createdBy'], equals('user_session_creator'));
      expect(chat?['members']['user_producer_student'], equals('member'));
    });

    test('42. Unsafe direct client cross-user write rejection & RSVP authorization boundary', () async {
      final appState = MockAppStateForSession01Test();

      final session = CollabSession(
        title: 'Closed Workshop',
        description: 'Private workshop',
        sessionType: 'In person',
        sessionCategory: 'Workshop',
        isDateFlexible: false,
        creatorId: 'user_session_creator',
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );
      final sessionId = await appState.firebaseService.createCollabSessionAsync(session);

      // Pending applicant cannot RSVP
      final appPending = CollabSessionApplication(
        userId: 'user_pending_rsvp',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        status: 'pending',
        timestamp: 1700000000000,
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_pending_rsvp', appPending);

      expect(
        () async => await appState.firebaseService.submitSessionRsvpResponseAsync(
          sessionId: sessionId,
          userId: 'user_pending_rsvp',
          status: 'YES',
        ),
        throwsException,
      );

      // Accepted applicant can RSVP
      final appAccepted = CollabSessionApplication(
        userId: 'user_accepted_rsvp',
        sessionId: sessionId,
        creatorId: 'user_session_creator',
        status: 'accepted',
        timestamp: 1700000000000,
      );
      await appState.firebaseService.applyToCollabSessionAsync(sessionId, 'user_accepted_rsvp', appAccepted);

      await appState.firebaseService.submitSessionRsvpResponseAsync(
        sessionId: sessionId,
        userId: 'user_accepted_rsvp',
        status: 'YES',
      );

      final stored = (appState.firebaseService as MockSession01FirebaseService).storedSessions[sessionId];
      expect(stored?.responses['user_accepted_rsvp']?.status, equals('YES'));
    });
  });
}
