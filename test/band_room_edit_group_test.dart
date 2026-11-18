import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/views/band_section_chat_screen.dart';
import 'band_room_new_group_test.dart' as groups;
import 'band_room_gigs_info_feed_test.dart' as fixtures;
import 'support/bounded_ui_pump.dart';

class RenameService extends groups.GroupService {
  final metadataChanges = StreamController<Map<String, dynamic>>.broadcast();
  final renameCalls = <Map<String, dynamic>>[];
  final metadata = <String, dynamic>{
    'bandId': 'band_feed_test',
    'bandName': 'Current Band',
    'groupName': 'Existing horns',
    'createdBy': 'leader_1',
    'admins': {'leader_1': true},
    'participants': {'leader_1': true, 'peer': true},
    'participantCount': 2,
  };
  bool denyRename = false;

  @override
  Stream<Map<String, dynamic>?> subscribeToBandSectionMetadata(String id) async* {
    openedIds.add(id);
    yield Map.of(metadata);
    yield* metadataChanges.stream;
  }

  @override
  Stream<List<Message>> subscribeToMessages(String id) => Stream.value([
    Message(id: 'existing-message', senderId: 'peer', senderName: 'Peer',
      text: 'Existing message is preserved', timestamp: DateTime(2026, 11, 18)),
  ]);

  @override
  Future<void> manageBandSectionConversationAsync({
    required String conversationId,
    required String action,
    String? groupName,
    List<String>? participantIds,
  }) async {
    renameCalls.add({
      'conversationId': conversationId, 'action': action,
      'groupName': groupName, 'participantIds': participantIds,
    });
    if (denyRename) throw StateError('PRIVATE SERVER ERROR');
    metadata['groupName'] = groupName;
    metadataChanges.add(Map.of(metadata));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(fixtures.initializeBandRoomTestFirebase);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> mount(WidgetTester tester, RenameService service) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.metadataChanges.close);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>(
      create: (_) => groups.GroupState(service),
      child: const MaterialApp(home: BandSectionChatScreen(
        conversationId: 'exact-existing-group', bandId: 'band_feed_test',
        initialGroupName: 'Stale route name',
      )),
    ));
    await pumpUiTransitions(tester);
    await tester.tap(find.byTooltip('Group Info & Members'));
    await pumpUiTransitions(tester);
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Edit Group'));
    await pumpUiTransitions(tester);
    expect(find.widgetWithText(AlertDialog, 'Edit Group'), findsOneWidget);
    expect(tester.widget<TextField>(find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField),
    )).controller!.text, 'Existing horns');
    await tester.enterText(find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField),
    ), '  Renamed horns  ');
  }

  Future<void> unmount(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('Edit Group renames the exact conversation and shows live name without changing messages or participants', (tester) async {
    final service = RenameService();
    await mount(tester, service);
    await edit(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await pumpUiTransitions(tester);
    expect(service.renameCalls, [{
      'conversationId': 'exact-existing-group', 'action': 'rename',
      'groupName': 'Renamed horns', 'participantIds': null,
    }]);
    expect(find.text('Renamed horns'), findsOneWidget);
    expect(find.text('Existing message is preserved'), findsOneWidget);
    expect(find.text('Current Band • 2 members'), findsOneWidget);
    expect(service.metadata['participants'], {'leader_1': true, 'peer': true});
    expect(service.openedIds, everyElement('exact-existing-group'));
    expect(service.groupCalls, isEmpty);
    await unmount(tester);
  });

  testWidgets('Cancel after editing does not call the server or change the name', (tester) async {
    final service = RenameService();
    await mount(tester, service);
    await edit(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpUiTransitions(tester);
    expect(service.renameCalls, isEmpty);
    expect(service.metadata['groupName'], 'Existing horns');
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('An ordinary participant has no Edit Group action', (tester) async {
    final service = RenameService()
      ..metadata['createdBy'] = 'peer'
      ..metadata['admins'] = {'peer': true};
    await mount(tester, service);
    expect(find.byTooltip('Edit Group'), findsNothing);
    expect(service.renameCalls, isEmpty);
    await unmount(tester);
  });

  testWidgets('A denied rename preserves the current group and shows only a neutral error', (tester) async {
    final service = RenameService()..denyRename = true;
    await mount(tester, service);
    await edit(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await pumpUiTransitions(tester);
    expect(service.renameCalls, hasLength(1));
    expect(service.metadata['groupName'], 'Existing horns');
    expect(find.text('Could not rename this group. Check your access and try again.'), findsOneWidget);
    expect(find.textContaining('PRIVATE SERVER ERROR'), findsNothing);
    await unmount(tester);
  });
}
