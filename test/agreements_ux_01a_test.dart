// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/agreement.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/sub_request_card_helper.dart';
import 'package:musicians_flutter/views/chat_detail_screen.dart';
import 'package:musicians_flutter/views/inbox_screen.dart';

class MockAgreementsFirebaseService extends FirebaseService {
  final List<Map<String, dynamic>> conversations = [];
  final Map<String, Agreement> conversationAgreements = {};
  final Map<String, List<Message>> conversationMessages = {};
  final Set<String> markedRead = {};

  @override
  String? get currentUserId => 'test_user';

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
  ) async {}
}

class MockAgreementsAppState extends AppState {
  final MockAgreementsFirebaseService mockService;
  MockAgreementsAppState(this.mockService);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => 'test_user';

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user',
        displayName: 'Test User',
      );
}

Widget createChatDetailApp({
  required MockAgreementsAppState appState,
  required String conversationId,
  Agreement? agreement,
  Size size = const Size(800, 1200),
}) {
  if (agreement != null) {
    appState.mockService.conversationAgreements[conversationId] = agreement;
  }
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
            receiverId: 'receiver_1',
            receiverName: 'Jane Vocalist',
          ),
        ),
      ),
    ),
  );
}

Widget createInboxApp({
  required MockAgreementsAppState appState,
  Size size = const Size(800, 1200),
  void Function(Map<String, dynamic>)? onChatNavigated,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      routes: {
        '/chat-detail': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          onChatNavigated?.call(args);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  group('AGREEMENTS-UX-01A — Agreement Presentation Cleanup', () {
    late MockAgreementsFirebaseService mockService;
    late MockAgreementsAppState appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Firebase.initializeApp();
      mockService = MockAgreementsFirebaseService();
      appState = MockAgreementsAppState(mockService);
    });

    test('1. formatSubRequestDateTime uses weekday, date, dot time and en dash', () {
      final formatted = formatSubRequestDateTime(
        date: '2026-10-30',
        startTime: '18:00',
        endTime: '21:30',
      );
      expect(formatted, equals('Fri, Oct 30 · 18.00–21.30'));
    });

    test('2. formatSubRequestDateTime never invents end time if only start time exists', () {
      final formatted = formatSubRequestDateTime(
        date: '2026-10-30',
        startTime: '18:00',
      );
      expect(formatted, equals('Fri, Oct 30 · 18.00'));
      expect(formatted!.contains('–'), isFalse);
    });

    test('3. formatSubRequestDateTime returns null when date is empty or null', () {
      expect(formatSubRequestDateTime(date: null, startTime: '18:00'), isNull);
      expect(formatSubRequestDateTime(date: '  ', startTime: '18:00'), isNull);
    });

    test('4a. formatAgreementPayment formats explicit SEK: Paid · 1,500 SEK', () {
      final agr = Agreement(payAmount: 1500, currency: 'SEK');
      expect(formatAgreementPayment(agr), equals('Paid · 1,500 SEK'));
    });

    test('4b. formatAgreementPayment formats explicit EUR: Paid · 1,500 EUR', () {
      final agr = Agreement(payAmount: 1500, currency: 'EUR');
      expect(formatAgreementPayment(agr), equals('Paid · 1,500 EUR'));
    });

    test('4c. formatAgreementPayment formats missing currency as Paid · 1,500 without inventing SEK', () {
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: null)), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: '')), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: '   ')), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: 'null')), equals('Paid · 1,500'));
    });

    test('4d. formatAgreementPayment formats malformed currency as Paid · 1,500 without invalid code', () {
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: '\$\$\$')), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: '123')), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: 'SEKK')), equals('Paid · 1,500'));
      expect(formatAgreementPayment(Agreement(payAmount: 1500, currency: 'INVALID')), equals('Paid · 1,500'));
    });

    test('5. formatAgreementPayment returns null when payAmount is missing, zero or negative', () {
      expect(formatAgreementPayment(Agreement(payAmount: null)), isNull);
      expect(formatAgreementPayment(Agreement(payAmount: 0)), isNull);
      expect(formatAgreementPayment(Agreement(payAmount: -50)), isNull);
    });

    test('5b. formatAgreementPayment does not modify stored Agreement data and has no empty separator', () {
      final agr = Agreement(payAmount: 1500, currency: 'SEK');
      final formatted = formatAgreementPayment(agr);
      expect(formatted, equals('Paid · 1,500 SEK'));
      expect(agr.payAmount, equals(1500));
      expect(agr.currency, equals('SEK'));
      expect(formatted!.contains('null'), isFalse);
      expect(formatted.endsWith('·'), isFalse);
    });

    test('6. Agreement model preserves AdditionalTerms serialization without change', () {
      final json = {
        'ChoirLeaderId': 'leader_1',
        'VocalistId': 'vocalist_1',
        'VoicePart': 'Alto',
        'Date': '2026-10-30',
        'StartTime': '18:00',
        'EndTime': '21:30',
        'Location': 'Stockholm Concert Hall',
        'AdditionalTerms': 'Bring sheet music and black dress.',
        'BandName': 'Nordic Choir',
        'SubRequestId': 'sub_req_42',
        'PayAmount': 1500,
        'Currency': 'SEK',
      };

      final agreement = Agreement.fromJson(json);
      expect(agreement.additionalTerms, equals('Bring sheet music and black dress.'));
      expect(agreement.choirLeaderId, equals('leader_1'));
      expect(agreement.vocalistId, equals('vocalist_1'));

      final serialized = agreement.toJson();
      expect(serialized['AdditionalTerms'], equals('Bring sheet music and black dress.'));
      expect(serialized['BandName'], equals('Nordic Choir'));
      expect(serialized['PayAmount'], equals(1500));
    });

    testWidgets('7. Compact Agreement card approved hierarchy and elements', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_test_1',
        'otherUserId': 'user_jane',
        'otherUserName': 'Jane Vocalist',
        'timestamp': '2026-10-30T10:00:00Z',
        'agreement': Agreement(
          bandName: 'Stockholm Jazz Ensemble',
          voicePart: 'Tenor Saxophone',
          date: '2026-10-30',
          startTime: '18:00',
          endTime: '21:30',
          location: 'Fasching Club, Stockholm',
          payAmount: 1500,
          currency: 'SEK',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap on Agreements tab (tab 1)
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Counterpart header row
      expect(find.text('Jane Vocalist'), findsOneWidget);
      expect(find.text('Agreement'), findsOneWidget);

      // 2. Band / Project
      expect(find.text('Stockholm Jazz Ensemble'), findsOneWidget);

      // 3. Role / Instrument
      expect(find.text('Tenor Saxophone'), findsOneWidget);

      // 4. Date & Time
      expect(find.text('Fri, Oct 30 · 18.00–21.30'), findsOneWidget);

      // 5. Location / Venue
      expect(find.text('Fasching Club, Stockholm'), findsOneWidget);

      // 6. Payment
      expect(find.text('Paid · 1,500 SEK'), findsOneWidget);

      // 7. Action button
      expect(find.text('View Agreement'), findsOneWidget);
      expect(find.byKey(const Key('inbox_agreement_open_conv_test_1')), findsOneWidget);

      // Verify vertical hierarchy order: Header < Band < Role < Date < Location < Button
      final headerY = tester.getTopLeft(find.text('Jane Vocalist')).dy;
      final bandY = tester.getTopLeft(find.text('Stockholm Jazz Ensemble')).dy;
      final roleY = tester.getTopLeft(find.text('Tenor Saxophone')).dy;
      final dateY = tester.getTopLeft(find.text('Fri, Oct 30 · 18.00–21.30')).dy;
      final locY = tester.getTopLeft(find.text('Fasching Club, Stockholm')).dy;
      final btnY = tester.getTopLeft(find.text('View Agreement')).dy;

      expect(headerY < bandY, isTrue, reason: 'Header should appear above Band');
      expect(bandY < roleY, isTrue, reason: 'Band should appear above Role');
      expect(roleY < dateY, isTrue, reason: 'Role should appear above Date');
      expect(dateY < locY, isTrue, reason: 'Date should appear above Location');
      expect(locY < btnY, isTrue, reason: 'Location should appear above View Agreement button');
    });

    testWidgets('8. Large calendar month/day badge is absent on compact card', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_test_1',
        'otherUserId': 'user_jane',
        'otherUserName': 'Jane Vocalist',
        'agreement': Agreement(
          bandName: 'Stockholm Jazz Ensemble',
          voicePart: 'Tenor Saxophone',
          date: '2026-10-30',
          startTime: '18:00',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No large calendar badge (no standalone 'OCT' or '30' badges)
      expect(find.text('OCT'), findsNothing);
      expect(find.text('Oct'), findsNothing);
      expect(find.text('Fri, Oct 30 · 18.00'), findsOneWidget);
    });

    testWidgets('9a. Compact card renders valid agreement.bandName', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_valid_band',
        'otherUserId': 'user_valid',
        'otherUserName': 'Valid Musician',
        'agreement': Agreement(
          bandName: 'Nordic Jazz Trio',
          voicePart: 'Bass',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Nordic Jazz Trio'), findsOneWidget);
      expect(find.text('Band / Project'), findsNothing);
      expect(find.text('Unknown Band'), findsNothing);
    });

    testWidgets('9b. Compact card cleanly omits Band row when bandName is null', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_null_band',
        'otherUserId': 'user_null_band',
        'otherUserName': 'Independent Pianist',
        'agreement': Agreement(
          bandName: null,
          voicePart: 'Solo Piano',
          date: '2026-10-30',
          startTime: '19:00',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Independent Pianist'), findsOneWidget);
      expect(find.text('Solo Piano'), findsOneWidget);
      expect(find.text('Band / Project'), findsNothing);
      expect(find.text('Unknown Band'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('N/A'), findsNothing);
    });

    testWidgets('9c. Compact card cleanly omits Band row when bandName is empty or whitespace', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_empty_band',
        'otherUserId': 'user_empty_band',
        'otherUserName': 'Guitarist Dave',
        'agreement': Agreement(
          bandName: '   ',
          voicePart: 'Electric Guitar',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Guitarist Dave'), findsOneWidget);
      expect(find.text('Electric Guitar'), findsOneWidget);
      expect(find.text('Band / Project'), findsNothing);
      expect(find.text('Unknown Band'), findsNothing);
      expect(find.textContaining('N/A'), findsNothing);
    });

    testWidgets('9d. Compact card falls back to reliable conversation thread title if agreement.bandName is missing', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_fallback_band',
        'otherUserId': 'user_fallback',
        'otherUserName': 'Cellist Clara',
        'bandName': 'Stockholm Philharmonic Quartet',
        'agreement': Agreement(
          bandName: null,
          voicePart: 'Cello',
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Stockholm Philharmonic Quartet'), findsOneWidget);
      expect(find.text('Band / Project'), findsNothing);
      expect(find.text('Unknown Band'), findsNothing);
    });

    testWidgets('9e. Compact card omits missing optional values cleanly without empty bullets', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_minimal',
        'otherUserId': 'user_minimal',
        'otherUserName': 'Minimalist Musician',
        'agreement': Agreement(
          bandName: 'Acoustic Trio',
          voicePart: 'Acoustic Guitar',
          // date, time, location, payAmount are all null
        ),
      });

      await tester.pumpWidget(createInboxApp(appState: appState));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Minimalist Musician'), findsOneWidget);
      expect(find.text('Acoustic Trio'), findsOneWidget);
      expect(find.text('Acoustic Guitar'), findsOneWidget);

      // Ensure no N/A, null or empty strings
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('N/A'), findsNothing);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
      expect(find.byIcon(Icons.access_time_rounded), findsNothing);
      expect(find.byIcon(Icons.payments_outlined), findsNothing);
    });

    testWidgets('10. Compact card action navigates to /chat-detail with correct conversationId', (tester) async {
      Map<String, dynamic>? navigatedArgs;
      mockService.conversations.add({
        'conversationId': 'conv_nav_99',
        'otherUserId': 'user_nav',
        'otherUserName': 'Drummer Dave',
        'agreement': Agreement(
          bandName: 'Rock Collective',
          voicePart: 'Drums',
        ),
      });

      await tester.pumpWidget(createInboxApp(
        appState: appState,
        onChatNavigated: (args) => navigatedArgs = args,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap View Agreement button
      await tester.tap(find.byKey(const Key('inbox_agreement_open_conv_nav_99')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(navigatedArgs, isNotNull);
      expect(navigatedArgs!['conversationId'], equals('conv_nav_99'));
      expect(navigatedArgs!['receiverId'], equals('user_nav'));
      expect(navigatedArgs!['receiverName'], equals('Drummer Dave'));
      expect(mockService.markedRead.contains('conv_nav_99'), isTrue);
    });

    testWidgets('11. CONFIRMED AGREEMENT header is visible and CONFIRMED GIG AGREEMENT is absent', (tester) async {
      final agreement = Agreement(
        bandName: 'Brass Quintet',
        voicePart: 'Trumpet',
        date: '2026-10-30',
        startTime: '18:00',
        endTime: '21:30',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_chat_1',
        agreement: agreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CONFIRMED AGREEMENT'), findsOneWidget);
      expect(find.text('CONFIRMED GIG AGREEMENT'), findsNothing);
    });

    testWidgets('12. Confirmed Agreement details visible labels: Location / Venue & Description / Details', (tester) async {
      final agreement = Agreement(
        bandName: 'Brass Quintet',
        voicePart: 'Trumpet',
        date: '2026-10-30',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Concert Hall Main Stage',
        additionalTerms: 'Arrive 30 minutes before warm-up.',
        payAmount: 1800,
        currency: 'SEK',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_chat_2',
        agreement: agreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify approved labels exist
      expect(find.textContaining('Location / Venue'), findsOneWidget);
      expect(find.textContaining('Concert Hall Main Stage'), findsOneWidget);

      expect(find.textContaining('Description / Details'), findsOneWidget);
      expect(find.textContaining('Arrive 30 minutes before warm-up.'), findsOneWidget);

      // Verify old labels are strictly absent
      expect(find.text('Additional Terms'), findsNothing);
      expect(find.text('Additional Terms:'), findsNothing);
      expect(find.text('Location:'), findsNothing);
    });

    testWidgets('13. Confirmed Agreement details shows Compensation when payAmount > 0 and omits when absent', (tester) async {
      final paidAgreement = Agreement(
        bandName: 'String Quartet',
        voicePart: 'Cello',
        payAmount: 2500,
        currency: 'EUR',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_paid',
        agreement: paidAgreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Compensation'), findsOneWidget);
      expect(find.textContaining('Paid · 2,500 EUR'), findsOneWidget);

      // Now pump with unpaid/null amount
      final unpaidAgreement = Agreement(
        bandName: 'Community Jam',
        voicePart: 'Bass',
        payAmount: null,
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_unpaid',
        agreement: unpaidAgreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Compensation'), findsNothing);
      expect(find.textContaining('Paid ·'), findsNothing);
    });

    testWidgets('14. Confirmed Agreement details omits missing rows cleanly without N/A or empty bullets', (tester) async {
      final minimalAgreement = Agreement(
        bandName: 'Solo Gig',
        voicePart: 'Piano',
        // date, location, additionalTerms, payAmount are all null
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_min_chat',
        agreement: minimalAgreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Band / Project'), findsOneWidget);
      expect(find.textContaining('Role / Instrument'), findsOneWidget);

      // No N/A, null or empty rows
      expect(find.textContaining('N/A'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('Date & Time'), findsNothing);
      expect(find.textContaining('Location / Venue'), findsNothing);
      expect(find.textContaining('Description / Details'), findsNothing);
      expect(find.textContaining('Compensation'), findsNothing);
    });

    testWidgets('15. Description / Details appears at most once in confirmed details', (tester) async {
      final agreement = Agreement(
        bandName: 'Orchestra',
        voicePart: 'Violin 1',
        additionalTerms: 'Concert dress code: Black tie.',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_terms_once',
        agreement: agreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Description / Details'), findsOneWidget);
    });

    testWidgets('16. Request Type and Event Type are not invented on Agreement surfaces', (tester) async {
      final agreement = Agreement(
        bandName: 'Fusion Quartet',
        voicePart: 'Keyboard',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_no_invented',
        agreement: agreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Neither Request Type nor Event Type should appear because Agreement does not store them
      expect(find.textContaining('Request Type'), findsNothing);
      expect(find.textContaining('Event Type'), findsNothing);
      expect(find.text('Substitute'), findsNothing);
      expect(find.text('New Band Member'), findsNothing);
    });

    testWidgets('17. Collapsed agreement summary uses middle dot and omits missing values', (tester) async {
      final agreement = Agreement(
        bandName: 'Big Band',
        voicePart: 'Lead Trombone',
        date: '2026-10-30',
        startTime: '19:00',
        endTime: '22:00',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_collapse',
        agreement: agreement,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Toggle Show/Hide details to collapse
      await tester.tap(find.text('Hide Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Show Details'), findsOneWidget);
      expect(
        find.text('Big Band · Lead Trombone · Fri, Oct 30 · 19.00–22.00'),
        findsOneWidget,
      );
    });

    testWidgets('18. 320px narrow width renders compact agreement card without overflow', (tester) async {
      mockService.conversations.add({
        'conversationId': 'conv_narrow',
        'otherUserId': 'user_narrow',
        'otherUserName': 'A Very Long Musician Name That Might Wrap',
        'agreement': Agreement(
          bandName: 'Extremely Long Band Name For Testing Narrow Widths',
          voicePart: 'Principal Concertmaster Violinist',
          date: '2026-10-30',
          startTime: '18:00',
          endTime: '21:30',
          location: 'Very Long Venue Name, Street Address 123, Stockholm',
          payAmount: 1500,
          currency: 'SEK',
        ),
      });

      await tester.pumpWidget(createInboxApp(
        appState: appState,
        size: const Size(320, 600),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agreements'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('View Agreement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('19. 320px narrow width renders ChatDetailScreen confirmed agreement banner without overflow', (tester) async {
      final agreement = Agreement(
        bandName: 'Extremely Long Band Name For Testing Narrow Widths',
        voicePart: 'Principal Concertmaster Violinist',
        date: '2026-10-30',
        startTime: '18:00',
        endTime: '21:30',
        location: 'Very Long Venue Name, Street Address 123, Stockholm',
        additionalTerms: 'A very detailed and long terms string that spans multiple lines.',
        payAmount: 25000,
        currency: 'SEK',
      );

      await tester.pumpWidget(createChatDetailApp(
        appState: appState,
        conversationId: 'conv_narrow_chat',
        agreement: agreement,
        size: const Size(320, 600),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CONFIRMED AGREEMENT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('20. Agreement participant fields remain intact and unmutated', () {
      final agreement = Agreement(
        choirLeaderId: 'leader_abc',
        vocalistId: 'applicant_xyz',
        subRequestId: 'req_123',
      );

      expect(agreement.choirLeaderId, equals('leader_abc'));
      expect(agreement.vocalistId, equals('applicant_xyz'));
      expect(agreement.subRequestId, equals('req_123'));
    });
  });
}
