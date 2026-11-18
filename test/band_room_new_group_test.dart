import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/band_section_chat_screen.dart';
import 'package:musicians_flutter/widgets/create_band_section_sheet.dart';
import 'band_room_gigs_info_feed_test.dart' as fixtures;
import 'support/bounded_ui_pump.dart';

class GroupService extends fixtures.MockGigsInfoFirebaseService {
  String? uid = 'leader_1';
  Map<String, String> bands = {
    'band_feed_test': 'Current Band',
    'other_band': 'Other Band',
  };
  final memberReads = <String>[];
  final groupCalls = <Map<String, dynamic>>[];
  final openedIds = <String>[];
  final readIds = <String>[];
  bool fail = false;
  String resultId = 'exact-created-conversation';
  Completer<String>? pending;
  final members = [
    BandMember(userId: 'leader_1', nickname: 'You', role: 'Member'),
    BandMember(userId: 'peer', nickname: 'Peer', role: 'Member'),
    BandMember(
      userId: 'held',
      nickname: 'Held',
      role: 'Member',
      status: 'on_hold',
    ),
    BandMember(
      userId: 'off',
      nickname: 'Off',
      role: 'Member',
      status: 'temporarily_off',
    ),
    BandMember(
      userId: 'inactive',
      nickname: 'Inactive',
      role: 'Member',
      status: 'inactive',
    ),
  ];
  @override
  String? get currentUserId => uid;
  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => bands;
  @override
  Future<Band?> getBandInfoAsync(String id) async => Band(
    id: id,
    name: bands[id],
    membersBand: {for (final m in members) m.userId!: m},
  );
  @override
  Future<List<BandMember>> getBandMembersAsync(String id) async {
    memberReads.add(id);
    return id == 'band_feed_test'
        ? members
        : [BandMember(userId: 'foreign', nickname: 'Other-band person')];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? id]) async =>
      UserProfile(userId: id, displayName: id, mainInstrument: 'Trumpet');
  @override
  Future<String> createBandSectionConversationAsync({
    required String bandId,
    required String groupName,
    required List<String> participantIds,
    String? sectionKey,
    String? sourceInstrument,
  }) async {
    groupCalls.add({
      'bandId': bandId,
      'groupName': groupName,
      'participants': List.of(participantIds),
    });
    if (fail) throw StateError('PRIVATE FIREBASE ERROR');
    return pending == null ? resultId : pending!.future;
  }

  @override
  Stream<Map<String, dynamic>?> subscribeToBandSectionMetadata(String id) {
    openedIds.add(id);
    return Stream.value({
      'bandId': 'band_feed_test',
      'groupName': groupCalls.last['groupName'],
      'bandName': 'Current Band',
      'participantCount': 2,
      'participants': {'leader_1': true, 'peer': true},
    });
  }

  @override
  Stream<List<Message>> subscribeToMessages(String id) => Stream.value([]);
  @override
  Future<void> markBandSectionConversationReadAsync(String id) async {
    readIds.add(id);
  }
}

class GroupState extends fixtures.MockGigsInfoAppState {
  final GroupService groups;
  String selectedBand = 'band_feed_test';
  GroupState(this.groups) : super(groups);
  @override
  String? get currentUserId => groups.uid;
  @override
  String? get activeBandId => selectedBand;
  @override
  bool get isLoading => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(fixtures.initializeBandRoomTestFirebase);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<GroupState> mount(
    WidgetTester tester,
    GroupService service, {
    bool room = true,
    bool locked = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = GroupState(service);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => state,
        child: MaterialApp(
          home: room
              ? const BandRoomChatScreen()
              : Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => CreateBandSectionSheet.show(
                        context,
                        initialBandId: 'band_feed_test',
                              lockToInitialBand: locked,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
          onGenerateRoute: (settings) {
            if (settings.name != '/band-section-chat') return null;
            final args = settings.arguments! as Map<String, dynamic>;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => BandSectionChatScreen(
                conversationId: args['conversationId'] as String,
                bandId: args['bandId'] as String,
                initialGroupName: args['groupName'] as String,
              ),
            );
          },
        ),
      ),
    );
    await pumpUiTransitions(tester);
    return state;
  }

  Future<void> open(WidgetTester tester, {bool room = true}) async {
    await tester.tap(
      room
          ? find.byKey(const ValueKey('band-room-new-group'))
          : find.text('Open'),
    );
    await pumpUiTransitions(tester);
    expect(find.byType(CreateBandSectionSheet), findsOneWidget);
  }

  Future<void> selectAndName(WidgetTester tester) async {
    final name = find.byKey(const ValueKey('band-group-name'));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Trumpets & Friends');
    final peer = find.byKey(const ValueKey('band-group-member-peer'));
    await tester.ensureVisible(peer);
    await tester.tap(peer);
    await pumpUiTransitions(tester);
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('create-band-group'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await pumpUiTransitions(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'Chat creates and opens exactly the named conversation for selected current-band members',
    (tester) async {
      final s = GroupService();
      await mount(tester, s);
      await open(tester);
      expect(find.text('Select Band'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(
        find.byKey(const ValueKey('band-group-member-inactive')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('band-group-member-held')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('band-group-member-off')),
        findsOneWidget,
      );
      expect(find.text('foreign'), findsNothing);
      await selectAndName(tester);
      await submit(tester);
      expect(s.groupCalls, hasLength(1));
      expect(s.groupCalls.single['bandId'], 'band_feed_test');
      expect(s.groupCalls.single['groupName'], 'Trumpets & Friends');
      expect(
        s.groupCalls.single['participants'],
        unorderedEquals(['leader_1', 'peer']),
      );
      final screen = tester.widget<BandSectionChatScreen>(
        find.byType(BandSectionChatScreen),
      );
      expect(screen.conversationId, s.resultId);
      expect(screen.bandId, 'band_feed_test');
      expect(find.text('Trumpets & Friends'), findsOneWidget);
      expect(s.openedIds, everyElement(s.resultId));
      expect(s.readIds, [s.resultId]);
      expect(s.memberReads, everyElement('band_feed_test'));
      await unmount(tester);
    },
  );
  testWidgets(
    'Cancel after naming and selection does not create or open anything',
    (tester) async {
      final s = GroupService();
      await mount(tester, s);
      await open(tester);
      await selectAndName(tester);
      await tester.tap(find.byKey(const ValueKey('cancel-band-group')));
      await pumpUiTransitions(tester);
      expect(find.byType(CreateBandSectionSheet), findsNothing);
      expect(s.groupCalls, isEmpty);
      expect(s.openedIds, isEmpty);
      expect(s.readIds, isEmpty);
      await unmount(tester);
    },
  );
  testWidgets(
    'A missing locked band never switches to another available band',
    (tester) async {
      final s = GroupService()..bands = {'other_band': 'Other Band'};
      await mount(tester, s, room: false);
      await open(tester, room: false);
      expect(
        find.text('This band is unavailable for your current access.'),
        findsOneWidget,
      );
      expect(s.memberReads, isEmpty);
      expect(s.groupCalls, isEmpty);
      expect(find.byKey(const ValueKey('create-band-group')), findsNothing);
      await unmount(tester);
    },
  );
  testWidgets('Changed band before submit does not call the server', (
    tester,
  ) async {
    final s = GroupService();
    final state = await mount(tester, s, room: false);
    await open(tester, room: false);
    await selectAndName(tester);
    state.selectedBand = 'other_band';
    await submit(tester);
    expect(s.groupCalls, isEmpty);
    expect(
      find.text('Your band or account changed. Close and try again.'),
      findsOneWidget,
    );
    await unmount(tester);
  });
  testWidgets('Changed account before submit does not call the server', (
    tester,
  ) async {
    final s = GroupService();
    await mount(tester, s, room: false);
    await open(tester, room: false);
    await selectAndName(tester);
    s.uid = 'other_user';
    await submit(tester);
    expect(s.groupCalls, isEmpty);
    expect(s.openedIds, isEmpty);
    await unmount(tester);
  });
  testWidgets(
    'Denied creation stays in the sheet with a neutral error and no route',
    (tester) async {
      final s = GroupService()..fail = true;
      await mount(tester, s);
      await open(tester);
      await selectAndName(tester);
      await submit(tester);
      expect(find.byType(CreateBandSectionSheet), findsOneWidget);
      expect(s.openedIds, isEmpty);
      expect(find.textContaining('PRIVATE FIREBASE ERROR'), findsNothing);
      expect(
        find.text(
          'Could not create this group. Check the members and try again.',
        ),
        findsOneWidget,
      );
      await unmount(tester);
    },
  );
  testWidgets('An empty server ID never opens a placeholder conversation', (
    tester,
  ) async {
    final s = GroupService()..resultId = '';
    await mount(tester, s);
    await open(tester);
    await selectAndName(tester);
    await submit(tester);
    expect(s.openedIds, isEmpty);
    expect(find.byType(CreateBandSectionSheet), findsOneWidget);
    await unmount(tester);
  });
  testWidgets(
    'Locked picker selection works on a narrow screen with keyboard open',
    (tester) async {
      final s = GroupService();
      await mount(tester, s, room: false);
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetViewInsets);
      await open(tester, room: false);
      await tester.enterText(
        find.byKey(const ValueKey('band-group-name')),
        'Mobile group',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await pumpUiTransitions(tester);
      final peer = find.byKey(const ValueKey('band-group-member-peer'));
      await tester.ensureVisible(peer);
      await tester.tap(peer);
      await pumpUiTransitions(tester);
      expect(tester.widget<CheckboxListTile>(peer).value, isTrue);
      expect(s.groupCalls, isEmpty);
      await unmount(tester);
    },
  );
  testWidgets('The shared Messages dialog retains its optional band selector', (tester) async {
    final s = GroupService();
    await mount(tester, s, room: false, locked: false);
    await open(tester, room: false);
    final picker = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(picker.items!.map((item) => item.value), unorderedEquals(['band_feed_test', 'other_band']));
    await tester.tap(find.byKey(const ValueKey('cancel-band-group')));
    await pumpUiTransitions(tester);
    expect(s.groupCalls, isEmpty);
    await unmount(tester);
  });
  testWidgets('A band change during creation never opens the old-band conversation', (tester) async {
    final s = GroupService()..pending = Completer<String>();
    final state = await mount(tester, s);
    await open(tester);
    await selectAndName(tester);
    await submit(tester);
    expect(s.groupCalls, hasLength(1));
    state.selectedBand = 'other_band';
    s.pending!.complete('created-in-previous-band');
    await pumpUiTransitions(tester);
    expect(s.openedIds, isEmpty);
    expect(s.readIds, isEmpty);
    expect(find.byType(BandSectionChatScreen), findsNothing);
    await unmount(tester);
  });
}
