import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/widgets/rsvp_reminder_dialog.dart';

class MockRsvpFirebaseService extends FirebaseService {
  String? lastBandId;
  String? lastEventId;
  String? lastUserId;
  String? lastStatus;
  String? lastComment;

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {
    lastBandId = bandId;
    lastEventId = eventId;
    lastUserId = userId;
    lastStatus = status;
    lastComment = comment;
  }
}

class MockRsvpAppState extends AppState {
  final MockRsvpFirebaseService mockFirebase;

  MockRsvpAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => 'user_me';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_me',
        displayName: 'Test User',
      );
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

  BandEvent createTestEvent({
    String id = 'evt_100',
    String title = 'Summer Festival Gig',
    String location = 'Stockholm Stage',
    String startDateTime = '2026-09-20T19:00:00Z',
    Map<String, EventResponse> responses = const {},
  }) {
    return BandEvent(
      id: id,
      title: title,
      description: 'Main festival stage performance',
      eventType: 'Concert',
      location: location,
      startDateTime: startDateTime,
      endDateTime: '2026-09-20T22:00:00Z',
      additionalNotes: '',
      createdBy: 'leader_1',
      createdAt: DateTime.now().millisecondsSinceEpoch - (2 * 3600 * 1000),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      requireResponse: true,
      responses: responses,
    );
  }

  Widget createTestWidget({
    required BandEvent event,
    required MockRsvpFirebaseService mockFirebase,
    String bandId = 'band_1',
    String currentUserId = 'user_me',
    VoidCallback? onResponded,
  }) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockRsvpAppState(mockFirebase),
      child: MaterialApp(
        home: Scaffold(
          body: RsvpReminderDialog(
            event: event,
            bandId: bandId,
            currentUserId: currentUserId,
            onResponded: onResponded,
          ),
        ),
      ),
    );
  }

  group('RsvpReminderDialog Tests', () {
    testWidgets('1. Renders initial prompt with title, options, and MUSICIANS header', (tester) async {
      final mockFb = MockRsvpFirebaseService();
      final event = createTestEvent();

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('MUSICIANS'), findsOneWidget);
      expect(find.text('Summer Festival Gig'), findsOneWidget);
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('UNCERTAIN'), findsOneWidget);
      expect(find.text('RSVP RECEIPT'), findsNothing);
    });

    testWidgets('2. Clicking YES submits response and displays receipt card', (tester) async {
      final mockFb = MockRsvpFirebaseService();
      final event = createTestEvent();
      bool respondedCallbackCalled = false;

      await tester.pumpWidget(createTestWidget(
        event: event,
        mockFirebase: mockFb,
        onResponded: () => respondedCallbackCalled = true,
      ));
      await tester.pumpAndSettle();

      // Tap YES
      await tester.tap(find.text('YES'));
      await tester.pumpAndSettle();

      expect(mockFb.lastStatus, equals('Yes'));
      expect(mockFb.lastEventId, equals('evt_100'));
      expect(mockFb.lastUserId, equals('user_me'));
      expect(respondedCallbackCalled, isTrue);

      // Verify Receipt UI
      expect(find.text('RSVP RECEIPT'), findsOneWidget);
      expect(find.text('ATTENDING (YES)'), findsOneWidget);
      expect(find.text('Your attendance has been confirmed.'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('Change response'), findsOneWidget);
    });

    testWidgets('3. Clicking NO submits response and displays receipt card', (tester) async {
      final mockFb = MockRsvpFirebaseService();
      final event = createTestEvent();

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      // Tap NO
      await tester.tap(find.text('NO'));
      await tester.pumpAndSettle();

      expect(mockFb.lastStatus, equals('No'));
      expect(find.text('RSVP RECEIPT'), findsOneWidget);
      expect(find.text('NOT ATTENDING (NO)'), findsOneWidget);
      expect(find.text('Your decline has been recorded.'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('4. Clicking UNCERTAIN reveals note input and allows custom note submission with receipt', (tester) async {
      final mockFb = MockRsvpFirebaseService();
      final event = createTestEvent();

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      // Tap UNCERTAIN button
      await tester.tap(find.text('UNCERTAIN'));
      await tester.pumpAndSettle();

      // Should now show the custom note input section
      expect(find.text('Reason / Note for bandleader:'), findsOneWidget);
      expect(find.text('CONFIRM UNCERTAIN'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Enter custom note
      await tester.enterText(find.byType(TextField), 'Checking flight schedule, might be 15 mins late');
      await tester.pumpAndSettle();

      // Confirm Uncertain
      await tester.tap(find.text('CONFIRM UNCERTAIN'));
      await tester.pumpAndSettle();

      expect(mockFb.lastStatus, equals('Uncertain'));
      expect(mockFb.lastComment, equals('Checking flight schedule, might be 15 mins late'));

      // Verify receipt shows UNCERTAIN and custom note quote box
      expect(find.text('RSVP RECEIPT'), findsOneWidget);
      expect(find.text('UNCERTAIN'), findsOneWidget);
      expect(find.text('Note to bandleader:'), findsOneWidget);
      expect(find.text('"Checking flight schedule, might be 15 mins late"'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('5. Clicking Change response returns back to the prompt view', (tester) async {
      final mockFb = MockRsvpFirebaseService();
      final event = createTestEvent();

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      // Tap YES to get to receipt
      await tester.tap(find.text('YES'));
      await tester.pumpAndSettle();
      expect(find.text('RSVP RECEIPT'), findsOneWidget);

      // Tap "Change response"
      await tester.tap(find.text('Change response'));
      await tester.pumpAndSettle();

      // Should be back to prompt with YES/NO/UNCERTAIN buttons
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('UNCERTAIN'), findsOneWidget);
      expect(find.text('RSVP RECEIPT'), findsNothing);
    });
  });
}
