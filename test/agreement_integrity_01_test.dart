// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/agreement.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/sub_request_card_helper.dart';
import 'package:musicians_flutter/views/chat_detail_screen.dart';
import 'package:musicians_flutter/views/inbox_screen.dart';
import 'package:musicians_flutter/views/sub_request_response_details_screen.dart';

class MockAgreementIntegrityService extends FirebaseService {
  final List<Map<String, dynamic>> conversations = [];
  final Map<String, Agreement> conversationAgreements = {};
  final Map<String, List<Message>> conversationMessages = {};
  final Set<String> markedRead = {};
  String activeUserId = 'user_organizer';

  int assignSubstituteCallCount = 0;
  int createAgreementConversationCallCount = 0;
  int createAgreementChatCallCount = 0;
  int directAgreementWriteCount = 0;
  int chosenMessageSendCount = 0;
  String? mockAssignedConversationId;
  SubRequest? mockSubRequest;
  final Map<String, UserProfile> mockProfiles = {};

  @override
  String? get currentUserId => activeUserId;

  @override
  String? get lastAssignedAgreementConversationId => mockAssignedConversationId;

  @override
  Future<SubRequest?> getSubRequestAsync(String id) async => mockSubRequest;

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String id) async =>
      mockSubRequest?.responses ?? {};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async =>
      userId != null ? mockProfiles[userId] : null;

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async => null;

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
    assignSubstituteCallCount++;
    mockAssignedConversationId ??= 'conv_server_assigned_1';
  }

  @override
  Future<String> createAgreementConversationAsync(
    String subRequestId,
    String applicantId, {
    Agreement? agreement,
  }) async {
    createAgreementConversationCallCount++;
    return 'unexpected_conv';
  }

  @override
  Future<String> createAgreementChatAsync(
    String senderId,
    String receiverId,
    Agreement agreement,
    Message message,
  ) async {
    createAgreementChatCallCount++;
    return 'unexpected_conv';
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveConversationsAsync() async =>
      List.from(conversations);

  @override
  Future<void> markConversationAsRead(String conversationId) async {
    markedRead.add(conversationId);
  }

  @override
  Stream<Map<String, dynamic>?> subscribeToConversationMetadata(String conversationId) {
    final agr = conversationAgreements[conversationId];
    return Stream.value({'agreement': agr});
  }

  @override
  Stream<List<Message>> subscribeToMessages(String conversationId) {
    return Stream.value(conversationMessages[conversationId] ?? []);
  }

  @override
  Future<void> sendConversationMessageAsync(
    String conversationId,
    String text,
    String receiverId,
    String senderName,
  ) async {
    if (text.contains('has been chosen')) {
      chosenMessageSendCount++;
    }
  }
}

class MockAgreementIntegrityAppState extends AppState {
  final MockAgreementIntegrityService mockService;
  String? customUserId;
  String? customActiveBandName;

  MockAgreementIntegrityAppState(this.mockService, {this.customUserId, this.customActiveBandName});

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => customUserId ?? mockService.activeUserId;

  @override
  String? get activeBandName => customActiveBandName;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: currentUserId ?? 'user_organizer',
        displayName: currentUserId == 'user_organizer' ? 'Organizer Alice' : 'Musician Bob',
      );
}

Widget createInboxTestApp({
  required MockAgreementIntegrityAppState appState,
  Size size = const Size(800, 1200),
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/chat-detail': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return Scaffold(body: Text('Chat Detail: ${args['conversationId']}'));
        },
      },
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: const InboxScreen(),
        ),
      ),
    ),
  );
}

Widget createChatDetailTestApp({
  required MockAgreementIntegrityAppState appState,
  required String conversationId,
  String receiverId = 'user_musician',
  String receiverName = 'Musician Bob',
  Size size = const Size(800, 1200),
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ChatDetailScreen(
            conversationId: conversationId,
            receiverId: receiverId,
            receiverName: receiverName,
          ),
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpInboxAgreementsTab(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await settle(tester);
  await tester.tap(find.text('Agreements'));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('Group 1: Complete Snapshot Creation & Field Preservation', () {
    test('1. Agreement model parses and serializes complete canonical snapshot', () {
      final json = {
        'subRequestId': 'req_101',
        'requestGroupId': 'group_alpha',
        'eventId': 'event_55',
        'bandId': 'band_26',
        'bandName': 'The Silver Tones',
        'requestType': 'Substitute',
        'eventType': 'Concert',
        'role': 'Tenor Sax',
        'voicePart': 'Tenor Sax',
        'date': '2026-11-20',
        'startTime': '18:00',
        'endTime': '21:30',
        'location': 'Stockholm Concert Hall',
        'description': 'Main stage concert with brass section.',
        'payDetails': 'Invoice via Cool Company',
        'additionalTerms': 'Bring black suit.',
        'payAmount': 1500,
        'currency': 'SEK',
        'choirLeaderId': 'user_alice',
        'vocalistId': 'user_bob',
        'choirLeaderName': 'Alice Leader',
        'vocalistName': 'Bob Sax',
        'status': 'confirmed',
        'createdAt': 1763660000000,
      };

      final agreement = Agreement.fromJson(json);

      expect(agreement.subRequestId, 'req_101');
      expect(agreement.requestGroupId, 'group_alpha');
      expect(agreement.eventId, 'event_55');
      expect(agreement.bandId, 'band_26');
      expect(agreement.bandName, 'The Silver Tones');
      expect(agreement.requestType, 'Substitute');
      expect(agreement.eventType, 'Concert');
      expect(agreement.voicePart, 'Tenor Sax');
      expect(agreement.date, '2026-11-20');
      expect(agreement.startTime, '18:00');
      expect(agreement.endTime, '21:30');
      expect(agreement.location, 'Stockholm Concert Hall');
      expect(agreement.description, 'Main stage concert with brass section.');
      expect(agreement.payDetails, 'Invoice via Cool Company');
      expect(agreement.additionalTerms, 'Bring black suit.');
      expect(agreement.payAmount, 1500);
      expect(agreement.currency, 'SEK');
      expect(agreement.choirLeaderId, 'user_alice');
      expect(agreement.vocalistId, 'user_bob');
      expect(agreement.choirLeaderName, 'Alice Leader');
      expect(agreement.vocalistName, 'Bob Sax');
      expect(agreement.status, 'confirmed');

      final serialized = agreement.toJson();
      expect(serialized['subRequestId'], 'req_101');
      expect(serialized['bandName'], 'The Silver Tones');
      expect(serialized['BandName'], 'The Silver Tones');
      expect(serialized['ChoirLeaderId'], 'user_alice');
      expect(serialized['VocalistId'], 'user_bob');
      expect(serialized['PayAmount'], 1500);
      expect(serialized['Currency'], 'SEK');
    });

    test('2. Agreement payment formatting formats correctly', () {
      final agreement = Agreement(
        payAmount: 1500,
        currency: 'SEK',
      );
      final formatted = formatAgreementPayment(agreement);
      expect(formatted, 'Paid · 1,500 SEK');
    });

    test('3. Agreement payment formatting returns null for missing or zero pay', () {
      final agreement1 = Agreement(payAmount: null, currency: null);
      expect(formatAgreementPayment(agreement1), isNull);

      final agreement2 = Agreement(payAmount: 0, currency: 'SEK');
      expect(formatAgreementPayment(agreement2), isNull);
    });
  });

  group('Group 2: Backward Compatibility & Legacy Agreement Handling', () {
    test('4. Parses legacy PascalCase-only Agreement cleanly', () {
      final legacyJson = {
        'ChoirLeaderId': 'user_alice',
        'VocalistId': 'user_bob',
        'VoicePart': 'Tenor Sax',
        'Date': '2026-11-20',
        'StartTime': '18:00',
        'EndTime': '21:30',
        'Location': 'Stockholm Concert Hall',
        'AdditionalTerms': 'Substitute staffing assignment.',
        'BandName': 'The Silver Tones',
        'SubRequestId': 'sub_legacy_1',
        'PayAmount': 2000,
        'Currency': 'SEK',
      };

      final agreement = Agreement.fromJson(legacyJson);
      expect(agreement.choirLeaderId, 'user_alice');
      expect(agreement.vocalistId, 'user_bob');
      expect(agreement.voicePart, 'Tenor Sax');
      expect(agreement.date, '2026-11-20');
      expect(agreement.startTime, '18:00');
      expect(agreement.endTime, '21:30');
      expect(agreement.location, 'Stockholm Concert Hall');
      expect(agreement.bandName, 'The Silver Tones');
      expect(agreement.subRequestId, 'sub_legacy_1');
      expect(agreement.payAmount, 2000);
      expect(agreement.currency, 'SEK');
    });

    test('5. Rejects null, n/a, and placeholder strings from BandName display', () {
      final placeholders = ['null', 'N/A', 'Gig Agreement', 'Unknown band', 'Band / Project', 'band'];
      for (final p in placeholders) {
        final agr = Agreement(bandName: p);
        final lower = agr.bandName!.toLowerCase();
        final isValid = lower != 'null' &&
            lower != 'n/a' &&
            lower != 'gig agreement' &&
            lower != 'unknown band' &&
            lower != 'band / project' &&
            lower != 'band';
        expect(isValid, isFalse, reason: 'Placeholder "$p" should not be treated as a valid band');
      }
    });

    test('6. Description / Details falls back to legacy additionalTerms when description is absent', () {
      final agreement = Agreement(
        description: null,
        additionalTerms: 'Performance in Gothenburg cathedral.',
      );
      final desc = agreement.description?.trim();
      final terms = agreement.additionalTerms?.trim();
      final effectiveDesc = (desc != null && desc.isNotEmpty && desc.toLowerCase() != 'null')
          ? desc
          : ((terms != null && terms.isNotEmpty && terms.toLowerCase() != 'null' && terms != 'Substitute staffing assignment.') ? terms : null);

      expect(effectiveDesc, 'Performance in Gothenburg cathedral.');
    });
  });

  group('Group 3: Participant Authority & Counterpart Derivation', () {
    testWidgets('7. Creator A viewing Agreement in inbox sees Musician B counterpart', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice Leader',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Sax',
        voicePart: 'Tenor Sax',
        bandName: 'Band 26',
        subRequestId: 'sub_101',
      );
      service.conversations.add({
        'conversationId': 'conv_101',
        'isGroup': false,
        'otherUserId': 'musician_bob',
        'otherUserName': 'Bob Sax',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });
      service.conversationAgreements['conv_101'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // Alice sees Bob Sax
      expect(find.text('Bob Sax'), findsOneWidget);
      expect(find.text('Alice Leader'), findsNothing);
    });

    testWidgets('8. Musician B viewing Agreement in inbox sees Creator A counterpart', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'musician_bob';
      final agr = Agreement(
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice Leader',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Sax',
        voicePart: 'Tenor Sax',
        bandName: 'Band 26',
        subRequestId: 'sub_101',
      );
      service.conversations.add({
        'conversationId': 'conv_101',
        'isGroup': false,
        'otherUserId': 'creator_alice',
        'otherUserName': 'Alice Leader',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });
      service.conversationAgreements['conv_101'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'musician_bob');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // Bob sees Alice Leader
      expect(find.text('Alice Leader'), findsOneWidget);
      expect(find.text('Bob Sax'), findsNothing);
    });

    testWidgets('9. Current user never sees themselves as counterpart in Agreement card', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice Leader',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Sax',
        voicePart: 'Tenor Sax',
        bandName: 'Band 26',
      );
      // Even if raw thread had otherUserId incorrectly set to self
      service.conversations.add({
        'conversationId': 'conv_corrupt',
        'isGroup': false,
        'otherUserId': 'creator_alice',
        'otherUserName': 'Alice Leader',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });
      service.conversationAgreements['conv_corrupt'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // Alice never sees Alice Leader as counterpart
      expect(find.text('Bob Sax'), findsOneWidget);
      expect(find.text('Alice Leader'), findsNothing);
    });

    testWidgets('10. Unrelated user viewing Agreement is rejected and sees no card', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'stranger_eve';
      final agr = Agreement(
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice Leader',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Sax',
        voicePart: 'Tenor Sax',
        bandName: 'Band 26',
      );
      service.conversations.add({
        'conversationId': 'conv_101',
        'isGroup': false,
        'otherUserId': 'creator_alice',
        'otherUserName': 'Alice Leader',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });
      service.conversationAgreements['conv_101'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'stranger_eve');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // Stranger Eve sees no agreement card
      expect(find.text('Band 26'), findsNothing);
      expect(find.text('Tenor Sax'), findsNothing);
    });
  });

  group('Group 4: Cross-Band Isolation Regression Tests (Requirement 11)', () {
    testWidgets('11. Creator A and Musician B: Band 26 Agreement never displays Band 27', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_a';

      final agr26 = Agreement(
        subRequestId: 'sub_26',
        bandId: 'band_26',
        bandName: 'Band 26',
        requestType: 'Substitute',
        eventType: 'Rehearsal',
        voicePart: 'Trumpet',
        choirLeaderId: 'user_a',
        choirLeaderName: 'Leader Alice',
        vocalistId: 'user_b',
        vocalistName: 'Musician Bob',
      );

      final agr27 = Agreement(
        subRequestId: 'sub_27',
        bandId: 'band_27',
        bandName: 'Band 27',
        requestType: 'Substitute',
        eventType: 'Concert',
        voicePart: 'Trombone',
        choirLeaderId: 'user_a',
        choirLeaderName: 'Leader Alice',
        vocalistId: 'user_b',
        vocalistName: 'Musician Bob',
      );

      service.conversations.add({
        'conversationId': 'conv_26',
        'isGroup': false,
        'otherUserId': 'user_b',
        'otherUserName': 'Musician Bob',
        'bandName': 'Band 26',
        'agreement': agr26,
        'hasUnread': false,
        'timestamp': DateTime.now().subtract(const Duration(hours: 1)),
      });

      service.conversations.add({
        'conversationId': 'conv_27',
        'isGroup': false,
        'otherUserId': 'user_b',
        'otherUserName': 'Musician Bob',
        'bandName': 'Band 27',
        'agreement': agr27,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });

      service.conversationAgreements['conv_26'] = agr26;
      service.conversationAgreements['conv_27'] = agr27;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_a', customActiveBandName: 'Band 99');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // Both distinct band cards are present
      expect(find.text('Band 26'), findsOneWidget);
      expect(find.text('Band 27'), findsOneWidget);
      // Active band in app header ('Band 99') has zero effect on either card
      expect(find.text('Band 99'), findsNothing);

      // Distinct roles are rendered on their respective cards
      expect(find.text('Substitute · Trumpet'), findsOneWidget);
      expect(find.text('Substitute · Trombone'), findsOneWidget);
    });

    testWidgets('12. Opening Band 26 chat detail displays only Band 26 details', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_a';
      final agr26 = Agreement(
        subRequestId: 'sub_26',
        bandId: 'band_26',
        bandName: 'Band 26',
        requestType: 'Substitute',
        eventType: 'Rehearsal',
        voicePart: 'Trumpet',
        location: 'Studio 26',
        choirLeaderId: 'user_a',
        choirLeaderName: 'Leader Alice',
        vocalistId: 'user_b',
        vocalistName: 'Musician Bob',
      );
      service.conversationAgreements['conv_26'] = agr26;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_a');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_26',
        receiverId: 'user_b',
        receiverName: 'Musician Bob',
      ));
      await settle(tester);

      expect(find.textContaining('Band 26'), findsOneWidget);
      expect(find.textContaining('Band 27'), findsNothing);
      expect(find.textContaining('Trumpet'), findsWidgets);
      expect(find.textContaining('Trombone'), findsNothing);
      expect(find.textContaining('Studio 26'), findsOneWidget);
    });

    testWidgets('13. Opening Band 27 chat detail displays only Band 27 details', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_a';
      final agr27 = Agreement(
        subRequestId: 'sub_27',
        bandId: 'band_27',
        bandName: 'Band 27',
        requestType: 'Substitute',
        eventType: 'Concert',
        voicePart: 'Trombone',
        location: 'Concert Hall 27',
        choirLeaderId: 'user_a',
        choirLeaderName: 'Leader Alice',
        vocalistId: 'user_b',
        vocalistName: 'Musician Bob',
      );
      service.conversationAgreements['conv_27'] = agr27;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_a');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_27',
        receiverId: 'user_b',
        receiverName: 'Musician Bob',
      ));
      await settle(tester);

      expect(find.textContaining('Band 27'), findsOneWidget);
      expect(find.textContaining('Band 26'), findsNothing);
      expect(find.textContaining('Trombone'), findsWidgets);
      expect(find.textContaining('Trumpet'), findsNothing);
      expect(find.textContaining('Concert Hall 27'), findsOneWidget);
    });
  });

  group('Group 5: Multi-Slot Isolation Tests (Requirement 12)', () {
    testWidgets('14. Multi-slot group Guitar and Drums assign to distinct agreements', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';

      final guitarAgr = Agreement(
        subRequestId: 'slot_guitar',
        requestGroupId: 'group_rock',
        voicePart: 'Lead Guitar',
        vocalistId: 'musician_guitarist',
        vocalistName: 'Gary Guitarist',
        choirLeaderId: 'creator_alice',
        bandName: 'Rock Band',
      );

      final drumsAgr = Agreement(
        subRequestId: 'slot_drums',
        requestGroupId: 'group_rock',
        voicePart: 'Drums',
        vocalistId: 'musician_drummer',
        vocalistName: 'Danny Drummer',
        choirLeaderId: 'creator_alice',
        bandName: 'Rock Band',
      );

      service.conversationAgreements['conv_guitar'] = guitarAgr;
      service.conversationAgreements['conv_drums'] = drumsAgr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');

      // Verify Guitar view
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_guitar',
        receiverId: 'musician_guitarist',
        receiverName: 'Gary Guitarist',
      ));
      await settle(tester);

      expect(find.textContaining('Lead Guitar'), findsWidgets);
      expect(find.textContaining('Drums'), findsNothing);
      expect(find.text('Gary Guitarist'), findsWidgets);
      expect(find.text('Danny Drummer'), findsNothing);
    });
  });

  group('Group 6: Destination & UI Presentation (ChatDetailScreen & Inbox)', () {
    testWidgets('15. Agreement destination in ChatDetailScreen shows CONFIRMED AGREEMENT header', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_301',
        voicePart: 'Keys',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
        bandName: 'Jazz Trio',
      );
      service.conversationAgreements['conv_301'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_301',
        receiverId: 'musician_bob',
        receiverName: 'Bob Keys',
      ));
      await settle(tester);

      expect(find.text('CONFIRMED AGREEMENT'), findsWidgets);
      expect(find.text('DIRECT CHAT'), findsNothing);
    });

    testWidgets('16. Non-agreement direct chat displays DIRECT CHAT', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_alice';
      // Zero agreement attached to conv_direct
      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_direct',
        receiverId: 'user_bob',
        receiverName: 'Bob Friend',
      ));
      await settle(tester);

      expect(find.text('DIRECT CHAT'), findsOneWidget);
      expect(find.text('CONFIRMED AGREEMENT'), findsNothing);
    });

    testWidgets('17. Legacy chosen message is suppressed in Agreement conversation', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_401',
        voicePart: 'Bass',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
        bandName: 'Groove Band',
      );
      service.conversationAgreements['conv_401'] = agr;
      service.conversationMessages['conv_401'] = [
        Message(
          id: 'msg_1',
          senderId: 'creator_alice',
          receiverId: 'musician_bob',
          text: 'Bob has been chosen to attend the rehearsal.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        Message(
          id: 'msg_2',
          senderId: 'creator_alice',
          receiverId: 'musician_bob',
          text: 'Looking forward to playing with you!',
          timestamp: DateTime.now(),
        ),
      ];

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_401',
        receiverId: 'musician_bob',
        receiverName: 'Bob Bass',
      ));
      await settle(tester);

      // Legacy chosen message is suppressed
      expect(find.text('Bob has been chosen to attend the rehearsal.'), findsNothing);
      // Real conversation message remains visible
      expect(find.text('Looking forward to playing with you!'), findsOneWidget);
    });

    testWidgets('18. Ordinary user messages with words chosen or attend remain visible', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_402',
        voicePart: 'Vocals',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
      );
      service.conversationAgreements['conv_402'] = agr;
      service.conversationMessages['conv_402'] = [
        Message(
          id: 'msg_chosen_user',
          senderId: 'musician_bob',
          receiverId: 'creator_alice',
          text: 'I am happy that our band has chosen this setlist.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
        Message(
          id: 'msg_attend_user',
          senderId: 'creator_alice',
          receiverId: 'musician_bob',
          text: 'Can you attend the soundcheck at 17:00?',
          timestamp: DateTime.now(),
        ),
      ];

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_402',
        receiverId: 'musician_bob',
        receiverName: 'Bob Singer',
      ));
      await settle(tester);

      expect(find.text('I am happy that our band has chosen this setlist.'), findsOneWidget);
      expect(find.text('Can you attend the soundcheck at 17:00?'), findsOneWidget);
    });

    testWidgets('19. 320 px viewport has zero RenderFlex overflow on Agreement card and chat details', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_small',
        bandName: 'Very Long Symphonic Orchestra Name That Might Overflow Small Screens',
        requestType: 'Substitute Musician Staffing',
        eventType: 'Grand Symphony Concert & Rehearsal',
        voicePart: 'First Principal Violin Soloist',
        date: '2026-11-20',
        startTime: '18:00',
        endTime: '22:30',
        location: 'Stockholm Konserthuset Stora Salen Entrance A',
        description: 'Comprehensive staffing assignment with extended rehearsals.',
        payDetails: 'Electronic invoice with 30-day payment term.',
        payAmount: 3500,
        currency: 'SEK',
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Conductor Alexander',
        vocalistId: 'musician_bob',
        vocalistName: 'Virtuoso Robert',
      );
      service.conversationAgreements['conv_small'] = agr;
      service.conversations.add({
        'conversationId': 'conv_small',
        'isGroup': false,
        'otherUserId': 'musician_bob',
        'otherUserName': 'Virtuoso Robert',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');

      // Test Inbox on 320 px viewport
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState, size: const Size(320, 600)));
      expect(tester.takeException(), isNull);

      // Test Chat Detail Screen on 320 px viewport
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_small',
        receiverId: 'musician_bob',
        receiverName: 'Virtuoso Robert',
        size: const Size(320, 600),
      ));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('20. Inbox agreement card has complete hierarchy rows in order', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_hier',
        bandName: 'The Northern Lights Quintet',
        requestType: 'Substitute',
        eventType: 'Concert',
        voicePart: 'Clarinet',
        date: '2026-11-20',
        startTime: '19:00',
        endTime: '21:00',
        location: 'Uppsala Music Hall',
        payAmount: 1800,
        currency: 'SEK',
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Clarinetist',
      );
      service.conversationAgreements['conv_hier'] = agr;
      service.conversations.add({
        'conversationId': 'conv_hier',
        'isGroup': false,
        'otherUserId': 'musician_bob',
        'otherUserName': 'Bob Clarinetist',
        'agreement': agr,
        'hasUnread': false,
        'timestamp': DateTime.now(),
      });

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await pumpInboxAgreementsTab(tester, createInboxTestApp(appState: appState));

      // 1. Counterpart header
      expect(find.text('Bob Clarinetist'), findsOneWidget);
      expect(find.text('Agreement'), findsOneWidget);
      // 2. Band
      expect(find.text('The Northern Lights Quintet'), findsOneWidget);
      // 3. Request Type · Role
      expect(find.text('Substitute · Clarinet'), findsOneWidget);
      // 4. Event Type · Paid summary
      expect(find.text('Concert · Paid · 1,800 SEK'), findsOneWidget);
      // 5. Location
      expect(find.text('Uppsala Music Hall'), findsOneWidget);
      // 6. Action button
      expect(find.text('View Agreement'), findsOneWidget);
    });

    testWidgets('21. Full expanded Agreement displays all 9 detail rows when available', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_full_9',
        bandName: 'Symphony Nova',
        requestType: 'Substitute',
        eventType: 'Concert',
        voicePart: 'Oboe',
        date: '2026-11-20',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Gothenburg Concert Hall',
        description: 'Full orchestral program.',
        additionalTerms: 'Arrive in concert black 60 min early.',
        payAmount: 3000,
        currency: 'SEK',
        payDetails: 'Paid via bank transfer within 14 days.',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
      );
      service.conversationAgreements['conv_full_9'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_full_9',
        receiverId: 'musician_bob',
        receiverName: 'Bob Oboist',
      ));
      await settle(tester);

      expect(find.textContaining('Band / Project'), findsOneWidget);
      expect(find.textContaining('Symphony Nova'), findsOneWidget);
      expect(find.textContaining('Request Type'), findsOneWidget);
      expect(find.textContaining('Substitute'), findsOneWidget);
      expect(find.textContaining('Event Type:  Concert'), findsOneWidget);
      expect(find.textContaining('Role / Instrument'), findsOneWidget);
      expect(find.textContaining('Oboe'), findsOneWidget);
      expect(find.textContaining('Date & Time'), findsOneWidget);
      expect(find.textContaining('Location / Venue'), findsOneWidget);
      expect(find.textContaining('Gothenburg Concert Hall'), findsOneWidget);
      expect(find.textContaining('Description / Details'), findsOneWidget);
      expect(find.textContaining('Full orchestral program.'), findsOneWidget);
      expect(find.textContaining('Additional Terms'), findsOneWidget);
      expect(find.textContaining('Arrive in concert black 60 min early.'), findsOneWidget);
      expect(find.textContaining('Compensation'), findsOneWidget);
      expect(find.textContaining('Paid · 3,000 SEK'), findsOneWidget);
      expect(find.textContaining('Payment Details'), findsOneWidget);
      expect(find.textContaining('Paid via bank transfer within 14 days.'), findsOneWidget);
    });

    testWidgets('22. ChatDetailScreen derives counterpart name from Agreement even when widget.receiverName is wrong', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_party_chat',
        choirLeaderId: 'creator_alice',
        choirLeaderName: 'Alice Leader',
        vocalistId: 'musician_bob',
        vocalistName: 'Bob Real Counterpart',
        voicePart: 'Flute',
      );
      service.conversationAgreements['conv_party_chat'] = agr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_party_chat',
        receiverId: 'creator_alice', // Wrongly passed self
        receiverName: 'Alice Leader', // Wrongly passed self name
      ));
      await settle(tester);

      expect(find.text('Bob Real Counterpart'), findsOneWidget);
      expect(find.text('Alice Leader'), findsNothing);
    });

    testWidgets('23. Legacy substitute chosen message ("has been chosen as substitute for") is also suppressed in Agreement chat', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_legacy_msg',
        voicePart: 'Cello',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
      );
      service.conversationAgreements['conv_legacy_msg'] = agr;
      service.conversationMessages['conv_legacy_msg'] = [
        Message(
          id: 'm1',
          senderId: 'creator_alice',
          receiverId: 'musician_bob',
          text: 'Bob has been chosen as substitute for Cello.',
          timestamp: DateTime.now(),
        ),
      ];

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_legacy_msg',
      ));
      await settle(tester);

      expect(find.text('Bob has been chosen as substitute for Cello.'), findsNothing);
      expect(find.text('No messages yet.'), findsOneWidget);
    });

    testWidgets('24. Ordinary Direct Chat does NOT suppress messages even if they match chosen phrasing', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_alice';
      // No agreement on conv_ordinary
      service.conversationMessages['conv_ordinary'] = [
        Message(
          id: 'm1',
          senderId: 'user_alice',
          receiverId: 'user_bob',
          text: 'Bob has been chosen to attend the rehearsal.',
          timestamp: DateTime.now(),
        ),
      ];

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_ordinary',
      ));
      await settle(tester);

      expect(find.text('Bob has been chosen to attend the rehearsal.'), findsOneWidget);
    });

    testWidgets('25. Multi-slot Drums view displays only Drums and Danny Drummer', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final drumsAgr = Agreement(
        subRequestId: 'slot_drums',
        requestGroupId: 'group_rock',
        voicePart: 'Drums',
        vocalistId: 'musician_drummer',
        vocalistName: 'Danny Drummer',
        choirLeaderId: 'creator_alice',
        bandName: 'Rock Band',
      );
      service.conversationAgreements['conv_drums'] = drumsAgr;

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_drums',
        receiverId: 'musician_drummer',
        receiverName: 'Danny Drummer',
      ));
      await settle(tester);

      expect(find.textContaining('Drums'), findsWidgets);
      expect(find.textContaining('Lead Guitar'), findsNothing);
      expect(find.text('Danny Drummer'), findsWidgets);
      expect(find.text('Gary Guitarist'), findsNothing);
    });

    testWidgets('26. Single user assignment action invokes assignSubstitute once, createAgreementConversation zero times, zero direct Agreement writes, and zero chosen-message sends', (tester) async {
      final service = MockAgreementIntegrityService()
        ..activeUserId = 'creator_alice'
        ..mockAssignedConversationId = 'conv_server_authoritative_99';
      final req = SubRequest(
        id: 'sub_single_action_1',
        subRequestId: 'sub_single_action_1',
        bandId: 'band_26',
        bandName: 'Band 26',
        eventId: 'evt_26',
        voicePart: 'Trumpet',
        requestType: 'Substitute',
        eventType: 'Concert',
        date: '2026-11-28',
        startTime: '19:00',
        endTime: '22:00',
        location: 'Stockholm Konserthuset',
        responses: {'musician_bob': true},
      );
      service.mockSubRequest = req;
      service.mockProfiles['musician_bob'] = UserProfile(
        userId: 'musician_bob',
        displayName: 'Bob Trumpet',
        mainInstrument: 'Trumpet',
      );

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      Map<String, dynamic>? receiptArgs;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            routes: {
              '/receipt': (context) {
                receiptArgs = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
                return Scaffold(body: Text('Receipt: ${receiptArgs?['conversationId']}'));
              },
            },
            home: SubRequestResponseDetailsScreen(subRequest: req),
          ),
        ),
      );
      await settle(tester);

      // Candidate is auto-selected when only 1 responder is present; tap CONFIRM SELECTION
      expect(find.text('CONFIRM SELECTION'), findsOneWidget);
      await tester.tap(find.text('CONFIRM SELECTION'));
      await settle(tester);

      expect(service.assignSubstituteCallCount, equals(1));
      expect(service.createAgreementConversationCallCount, equals(0));
      expect(service.createAgreementChatCallCount, equals(0));
      expect(service.directAgreementWriteCount, equals(0));
      expect(service.chosenMessageSendCount, equals(0));
      expect(receiptArgs, isNotNull);
      expect(receiptArgs!['conversationId'], equals('conv_server_authoritative_99'));
      expect(receiptArgs!['receiverUserId'], equals('musician_bob'));
    });

    testWidgets('27. Stored legacy chosen message remains intact in backing store while hidden in Agreement UI, and retry assignment sends zero chosen messages', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'creator_alice';
      final agr = Agreement(
        subRequestId: 'sub_preserve_history',
        voicePart: 'Piano',
        choirLeaderId: 'creator_alice',
        vocalistId: 'musician_bob',
      );
      service.conversationAgreements['conv_preserve_history'] = agr;
      service.conversationMessages['conv_preserve_history'] = [
        Message(
          id: 'legacy_m1',
          senderId: 'creator_alice',
          receiverId: 'musician_bob',
          text: 'Bob has been chosen to attend the rehearsal.',
          timestamp: DateTime.now(),
        ),
      ];

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'creator_alice');
      await tester.pumpWidget(createChatDetailTestApp(
        appState: appState,
        conversationId: 'conv_preserve_history',
      ));
      await settle(tester);

      // UI hides the legacy chosen message
      expect(find.text('Bob has been chosen to attend the rehearsal.'), findsNothing);
      // Backing store preserves the historical message unmutated
      expect(service.conversationMessages['conv_preserve_history']!.length, equals(1));
      expect(service.conversationMessages['conv_preserve_history']!.first.id, equals('legacy_m1'));

      // Retrying assignment sends zero chosen messages
      await service.assignSubstituteCandidateAsync(
        subRequestId: 'sub_preserve_history',
        candidateUserId: 'musician_bob',
        bandId: 'band_26',
        eventId: 'evt_26',
        roleOrInstrument: 'Piano',
      );
      await service.assignSubstituteCandidateAsync(
        subRequestId: 'sub_preserve_history',
        candidateUserId: 'musician_bob',
        bandId: 'band_26',
        eventId: 'evt_26',
        roleOrInstrument: 'Piano',
      );
      expect(service.chosenMessageSendCount, equals(0));
    });

    testWidgets('28. Inbox preview does not attach an Agreement or classify thread as Agreement based on chosen-to-attend message text', (tester) async {
      final service = MockAgreementIntegrityService()..activeUserId = 'user_alice';
      service.conversations.add({
        'conversationId': 'conv_direct_with_chosen_text',
        'isGroup': false,
        'otherUserId': 'user_bob',
        'otherUserName': 'Bob Friend',
        'lastMessage': 'Bob Friend has been chosen to attend the rehearsal.',
        'timestamp': DateTime.now(),
        'hasUnread': false,
        'agreement': null,
      });

      final appState = MockAgreementIntegrityAppState(service, customUserId: 'user_alice');
      // Pump Inbox Messages tab first — ordinary conversation appears in Direct Messages
      await tester.pumpWidget(createInboxTestApp(appState: appState));
      await settle(tester);
      expect(find.text('Bob Friend'), findsOneWidget);

      // Switch to Agreements tab — ordinary conversation must NOT appear under Agreements
      await tester.tap(find.text('Agreements'));
      await settle(tester);
      expect(find.text('Bob Friend'), findsNothing);
    });
  });
}
