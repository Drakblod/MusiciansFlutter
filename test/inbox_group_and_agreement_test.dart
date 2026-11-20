import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/utils/conversation_thread_metadata.dart';
import 'package:musicians_flutter/views/inbox_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'band_room_gigs_info_feed_test.dart' as fixtures;
import 'band_room_new_group_test.dart' as groups;
import 'support/bounded_ui_pump.dart';

class _InboxService extends groups.GroupService {
  final opened = <String>[];
  final unreadable = <String>{};
  late final List<Map<String, dynamic>> threads;

  @override
  Future<List<Map<String, dynamic>>> getActiveConversationsAsync() async =>
      List.of(threads);

  @override
  Stream<bool> subscribeToBandProfileAccess(String bandId) =>
      Stream.value(true);

  @override
  Stream<Map<String, dynamic>?> subscribeToBandSectionMetadata(String id) {
    opened.add(id);
    if (unreadable.contains(id)) return Stream.error(StateError('Denied'));
    return Stream.value({
      'conversationType': 'band_section',
      'groupName': 'Current horns name',
      'bandId': 'band_feed_test',
      'participants': {'leader_1': true, 'peer': true},
    });
  }
}

Map<String, dynamic> _thread(String id, String name, Map metadata) => {
  'conversationId': id,
  'otherUserName': name,
  'lastMessageText': 'Preview for $id',
  ...Map<String, dynamic>.from(metadata),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(fixtures.initializeBandRoomTestFirebase);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> mount(
    WidgetTester tester,
    _InboxService service,
    List<RouteSettings> routes,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => groups.GroupState(service),
        child: MaterialApp(
          home: const InboxScreen(),
          onGenerateRoute: (settings) {
            routes.add(settings);
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('Opened exact group')),
            );
          },
        ),
      ),
    );
    await pumpUiTransitions(tester);
  }

  testWidgets(
    'Verified old and typed Agreements appear only under Agreements',
    (tester) async {
      final legacy = resolveConversationMetadata(
        selfId: 'leader_1',
        index: {'otherUserId': 'peer'},
        canonical: {
          'Agreement': {
            'ChoirLeaderId': 'leader_1',
            'VocalistId': 'peer',
            'BandName': 'Legacy quartet',
          },
        },
      );
      final typed = resolveConversationMetadata(
        selfId: 'leader_1',
        index: {'ConversationType': 'Agreement', 'otherUserId': 'peer'},
      );
      final unknown = resolveConversationMetadata(
        selfId: 'leader_1',
        index: {},
      );
      final service = _InboxService()
        ..threads = [
          _thread('old', 'Old contact', legacy),
          _thread('typed', 'Typed agreement', typed),
          _thread('unknown', 'Musician', unknown),
          _thread('direct', 'Confirmed Agreement: Bass', {
            'conversationType': 'direct',
          }),
        ];
      await mount(tester, service, []);
      expect(needsConversationMetadata({'otherUserId': 'peer'}), isTrue);
      expect(find.text('Legacy quartet'), findsNothing);
      expect(find.text('Typed agreement'), findsNothing);
      expect(find.text('Musician'), findsOneWidget);
      expect(find.text('Confirmed Agreement: Bass'), findsOneWidget);
      await tester.tap(find.text('Agreements'));
      await pumpUiTransitions(tester);
      expect(find.text('Legacy quartet'), findsOneWidget);
      expect(find.text('Typed agreement'), findsOneWidget);
      expect(find.text('Musician'), findsNothing);
      expect(find.text('Confirmed Agreement: Bass'), findsNothing);
    },
  );

  testWidgets(
    'Messages use exact band role, profile fallback and no fabricated role',
    (tester) async {
      final service = _InboxService()
        ..threads = [
          _thread('first', 'First band', {
            'bandId': 'band_feed_test',
            'otherBandMember': BandMember(
              userId: 'peer',
              role: 'Admin',
              musicalRole: 'Trumpet',
            ),
            'otherUserProfile': UserProfile(mainInstrument: 'Drums'),
          }),
          _thread('second', 'Same person in another band', {
            'bandId': 'other_band',
            'otherBandMember': BandMember(userId: 'peer', role: 'MOD'),
            'otherUserProfile': UserProfile(mainInstrument: 'Drums'),
          }),
          _thread('third', 'Member without skill', {
            'bandId': 'other_band',
            'otherBandMember': BandMember(userId: 'third', role: 'Leader'),
          }),
        ];
      await mount(tester, service, []);
      expect(find.text('Trumpet'), findsOneWidget);
      expect(find.text('Drums'), findsOneWidget);
      for (final name in ['Admin', 'MOD', 'Leader', 'Musician']) {
        expect(find.text(name), findsNothing);
      }
    },
  );

  testWidgets(
    'Groups excludes Agreements and rechecks access before opening the exact choice',
    (tester) async {
      final service = _InboxService()
        ..threads = [
          for (final id in ['strings', 'horns'])
            _thread(id, 'Group $id', {
              'conversationType': 'band_section',
              'bandId': 'band_feed_test',
            }),
          _thread('agreement', 'Only in Agreements', {
            'conversationType': 'agreement',
            'isGroup': true,
          }),
        ];
      service.unreadable.add('strings');
      final routes = <RouteSettings>[];
      await mount(tester, service, routes);
      await tester.tap(find.text('Groups'));
      await pumpUiTransitions(tester);
      expect(find.text('Only in Agreements'), findsNothing);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('Group strings'));
      await pumpUiTransitions(tester);
      expect(find.text('This group is currently unavailable.'), findsOneWidget);
      expect(routes, isEmpty);
      await tester.tap(find.text('Group horns'));
      await pumpUiTransitions(tester);
      expect(service.opened, ['strings', 'horns']);
      expect(routes.single.name, '/band-section-chat');
      expect(routes.single.arguments, {
        'conversationId': 'horns',
        'bandId': 'band_feed_test',
        'groupName': 'Current horns name',
      });
      expect(find.text('Opened exact group'), findsOneWidget);
    },
  );

  testWidgets('New group in Messages still creates and opens the returned ID', (
    tester,
  ) async {
    final service = _InboxService()
      ..bands = {'band_feed_test': 'Current Band'}
      ..threads = [];
    final routes = <RouteSettings>[];
    await mount(tester, service, routes);
    await tester.tap(find.text('New group'));
    await pumpUiTransitions(tester);
    expect(find.text('Section Choice'), findsNothing);
    final name = find.byKey(const ValueKey('band-group-name'));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Saturday group');
    final peer = find.byKey(const ValueKey('band-group-member-peer'));
    await tester.ensureVisible(peer);
    await tester.tap(peer);
    final create = find.byKey(const ValueKey('create-band-group'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await pumpUiTransitions(tester);
    expect(service.groupCalls.single['groupName'], 'Saturday group');
    expect(
      service.groupCalls.single['participants'],
      unorderedEquals(['leader_1', 'peer']),
    );
    expect(routes.single.name, '/band-section-chat');
    expect(
      (routes.single.arguments as Map)['conversationId'],
      service.resultId,
    );
  });
}
