import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/event_details_page.dart';

class MockEventDetailsFirebaseService extends FirebaseService {
  BandEvent? mockEvent;
  List<BandMember> mockMembers = [];
  Map<String, UserProfile> mockProfiles = {};

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    return Stream.value(mockEvent);
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return mockMembers;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return mockEvent != null ? [mockEvent!] : [];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: userId ?? 'u1', displayName: 'User ');
  }

  @override
  Future<void> updateEventResponseAsync(
    String bandId,
    String eventId,
    String userId,
    String status, {
    String? comment,
  }) async {}
}

class MockEventDetailsAppState extends AppState {
  final MockEventDetailsFirebaseService mockFirebase;

  MockEventDetailsAppState(this.mockFirebase);

  @override
  FirebaseService get firebaseService => mockFirebase;

  @override
  String? get currentUserId => 'user_1';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'user_1',
        displayName: 'Alex',
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

  BandEvent createTestBandEvent({
    required String title,
    Map<String, EventResponse> responses = const {},
  }) {
    return BandEvent(
      id: 'evt_1',
      title: title,
      description: 'Event description',
      eventType: 'Concert',
      location: 'Main Stage',
      startDateTime: '2026-09-16T19:00:00Z',
      endDateTime: '2026-09-16T21:00:00Z',
      additionalNotes: '',
      createdBy: 'leader_1',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      requireResponse: true,
      responses: responses,
    );
  }

  Widget createTestWidget({
    required BandEvent event,
    required MockEventDetailsFirebaseService mockFirebase,
  }) {
    mockFirebase.mockEvent = event;
    mockFirebase.mockMembers = [
      BandMember(userId: 'user_1', role: 'Member', nickname: 'Alex'),
    ];

    return ChangeNotifierProvider<AppState>(
      create: (_) => MockEventDetailsAppState(mockFirebase),
      child: MaterialApp(
        home: EventDetailsPage(
          bandId: 'band_1',
          eventId: 'evt_1',
          initialEvent: event,
        ),
      ),
    );
  }

  group('EventDetailsPage RSVP Display Tests', () {
    testWidgets('1. Reflects Yes response when status is "Yes" in responses', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Torsdagskul',
        responses: {
          'user_1': EventResponse(
            status: 'Yes',
            timestamp: DateTime.now(),
          ),
        },
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('Torsdagskul'), findsWidgets);
      expect(find.text('YOUR RESPONSE'), findsOneWidget);
      expect(find.text('YES'), findsOneWidget);

      // Verify that YES button is rendered with success styling (selected)
      final yesContainer = tester.widget<Container>(
        find.ancestor(
          of: find.text('YES'),
          matching: find.byType(Container),
        ).first,
      );
      final boxDecoration = yesContainer.decoration as BoxDecoration;
      final borderColor = (boxDecoration.border as Border).top.color;
      // AppTheme.success is selected border color
      expect(borderColor, equals(const Color(0xFF2ECC71)));
    });

    testWidgets('2. Reflects Uncertain response and displays comment', (tester) async {
      final mockFb = MockEventDetailsFirebaseService();
      final event = createTestBandEvent(
        title: 'Torsdagskul',
        responses: {
          'user_1': EventResponse(
            status: 'Uncertain',
            comment: 'Might be late',
            timestamp: DateTime.now(),
          ),
        },
      );

      await tester.pumpWidget(createTestWidget(event: event, mockFirebase: mockFb));
      await tester.pumpAndSettle();

      expect(find.text('WHY ARE YOU UNCERTAIN? (mandatory)'), findsOneWidget);
      expect(find.text('Might be late'), findsOneWidget);
    });
  });
}
