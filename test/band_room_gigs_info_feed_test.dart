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
import 'package:musicians_flutter/views/event_results_page.dart';
import 'package:musicians_flutter/widgets/animated_tap_detector.dart';

class MockGigsInfoFirebaseService extends FirebaseService {
  BandEvent? testEvent;
  List<BandMember> testMembers = [];

  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) {
    return Stream.value(testEvent != null ? [testEvent!] : []);
  }

  @override
  Stream<BandEvent?> subscribeToBandEvent(String bandId, String eventId) {
    return Stream.value(testEvent);
  }

  @override
  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) {
    return Stream.value([]);
  }

  @override
  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) {
    return Stream.value([]);
  }

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return Band(
      id: bandId,
      name: 'Rock Band',
      description: 'Test Band',
    );
  }

  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    return {};
  }

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    return testMembers;
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return testEvent != null ? [testEvent!] : [];
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Gigs/Info event card is whole clickable, has chevron, no RSVP button, opens EventResultsPage', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final mockService = MockGigsInfoFirebaseService();
    mockService.testMembers = [
      BandMember(userId: 'leader_1', nickname: 'Leader', role: 'Leader'),
      BandMember(userId: 'u2', nickname: 'Bassist', role: 'Member'),
    ];

    final now = DateTime.now();
    mockService.testEvent = BandEvent(
      id: 'event_feed_1',
      title: 'Summer Fest Gig',
      description: 'Gig details description',
      eventType: 'Concert',
      location: 'Main Stage',
      startDateTime: now.add(const Duration(days: 3)).toIso8601String(),
      endDateTime: now.add(const Duration(days: 3, hours: 3)).toIso8601String(),
      additionalNotes: 'Backline provided',
      createdBy: 'leader_1',
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
      requireResponse: true,
      responses: {
        'leader_1': EventResponse(status: 'YES', timestamp: now),
        'u2': EventResponse(status: 'declined', timestamp: now),
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => MockGigsInfoAppState(mockService),
        child: const MaterialApp(
          home: BandRoomChatScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Gigs/Info tab
    final gigsTab = find.text('Gigs/Info');
    expect(gigsTab, findsOneWidget);
    await tester.tap(gigsTab);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 1. Verify Event Card Title & Location rendered
    expect(find.text('Summer Fest Gig'), findsOneWidget);
    expect(find.text('Main Stage'), findsOneWidget);

    // 2. Verify normalized response counts
    expect(find.textContaining('1 Attending (2 responses)'), findsOneWidget);

    // 3. Verify separate "RSVP / Details" button is REMOVED
    expect(find.text('RSVP / Details'), findsNothing);
    expect(find.text('View Details'), findsNothing);

    // 4. Verify trailing chevron icon is present
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);

    // 5. Verify whole card is wrapped in AnimatedTapDetector and trigger navigation
    final cardFinder = find.ancestor(
      of: find.text('Summer Fest Gig'),
      matching: find.byType(AnimatedTapDetector),
    );
    expect(cardFinder, findsOneWidget);

    final tapDetector = tester.widget<AnimatedTapDetector>(cardFinder);
    tapDetector.onTap();

    await tester.pumpAndSettle();

    // EventResultsPage should be active with its 4 regular member groups
    expect(find.byType(EventResultsPage), findsOneWidget);
    expect(find.text('REGULAR BAND MEMBERS'), findsOneWidget);
    expect(find.textContaining('YES (1)'), findsOneWidget);
    expect(find.textContaining('NO (1)'), findsOneWidget);
    expect(find.textContaining('UNCERTAIN (0)'), findsOneWidget);
    expect(find.textContaining('NO ANSWER (0)'), findsOneWidget);
  });
}
