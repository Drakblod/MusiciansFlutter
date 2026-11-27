import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:musicians_flutter/models/agreement.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/chat_detail_screen.dart';
import 'package:musicians_flutter/views/inbox_screen.dart';
import 'package:musicians_flutter/widgets/message_date_divider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agreements_ux_01a_test.dart' as agreements;
import 'band_room_gigs_info_feed_test.dart' as band_room;
import 'support/bounded_ui_pump.dart';

final _firstDay = DateTime(2026, 1, 23, 23, 41);
final _nextDay = DateTime(2026, 1, 24);

List<Message> _messages() => [
  Message(text: 'First message', timestamp: _firstDay.toUtc()),
  Message.fromJson({'Text': 'Undated message'}, 'legacy'),
  Message(
    text: 'Later the same day',
    timestamp: _firstDay.add(const Duration(minutes: 18)).toUtc(),
  ),
  Message(text: 'Midnight message', timestamp: _nextDay.toUtc()),
];

class _BandChatService extends band_room.MockGigsInfoFirebaseService {
  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) =>
      Stream.value(_messages());
}

void _expectDatedThread(WidgetTester tester) {
  final dividers = find.byType(MessageDateDivider);
  expect(dividers, findsNWidgets(2));
  final localizations = MaterialLocalizations.of(
    tester.element(dividers.first),
  );
  final firstDay = find.text(localizations.formatFullDate(_firstDay));
  final nextDay = find.text(localizations.formatFullDate(_nextDay));
  expect(firstDay, findsOneWidget);
  expect(nextDay, findsOneWidget);

  final rows = [
    firstDay,
    find.text('First message'),
    find.text('Undated message'),
    find.text('Later the same day'),
    nextDay,
    find.text('Midnight message'),
  ];
  for (var index = 1; index < rows.length; index++) {
    expect(
      tester.getTopLeft(rows[index - 1]).dy,
      lessThan(tester.getTopLeft(rows[index]).dy),
    );
  }
  for (final time in ['23:41', '23:59', '00:00']) {
    expect(find.text(time), findsOneWidget);
  }
  expect(find.text('12:00'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(band_room.initializeBandRoomTestFirebase);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Band Room Chat inserts dates at the local midnight boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => band_room.MockGigsInfoAppState(_BandChatService()),
        child: const MaterialApp(home: BandRoomChatScreen()),
      ),
    );
    await pumpUiTransitions(tester);

    _expectDatedThread(tester);
  });

  testWidgets('Messages to Agreements opens the exact dated thread', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final agreement = Agreement(
      bandName: 'Brass Quartet',
      voicePart: 'Trumpet',
    );
    final service = agreements.MockAgreementsFirebaseService()
      ..conversations.add({
        'conversationId': 'agreement-1',
        'conversationType': 'agreement',
        'otherUserId': 'bandleader',
        'otherUserName': 'Taylor',
        'agreement': agreement,
      })
      ..conversationAgreements['agreement-1'] = agreement
      ..conversationMessages['agreement-1'] = _messages();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => agreements.MockAgreementsAppState(service),
        child: MaterialApp(
          home: const InboxScreen(),
          routes: {
            '/chat-detail': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map;
              return ChatDetailScreen(
                conversationId: args['conversationId'] as String,
                receiverId: args['receiverId'] as String,
                receiverName: args['receiverName'] as String,
              );
            },
          },
        ),
      ),
    );
    await pumpUiTransitions(tester);
    expect(find.text('Messages'), findsOneWidget);
    await tester.tap(find.text('Agreements'));
    await pumpUiTransitions(tester);
    await tester.tap(find.byKey(const Key('inbox_agreement_open_agreement-1')));
    await pumpUiTransitions(tester);

    expect(
      tester
          .widget<ChatDetailScreen>(find.byType(ChatDetailScreen))
          .conversationId,
      'agreement-1',
    );
    expect(service.markedRead, {'agreement-1'});
    expect(find.text('CONFIRMED AGREEMENT'), findsOneWidget);
    expect(find.textContaining('Error loading messages'), findsNothing);
    _expectDatedThread(tester);
  });

  testWidgets('Ordinary direct messages keep their time-only layout', (
    tester,
  ) async {
    final service = agreements.MockAgreementsFirebaseService()
      ..conversationMessages['direct-1'] = _messages();
    final state = agreements.MockAgreementsAppState(service);
    await tester.pumpWidget(
      agreements.createChatDetailApp(
        appState: state,
        conversationId: 'direct-1',
      ),
    );
    await pumpUiTransitions(tester);

    expect(find.byType(MessageDateDivider), findsNothing);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text('23:41'), findsOneWidget);
  });
}
