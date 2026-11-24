import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/collab_session.dart';
import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';
import 'package:musicians_flutter/views/create_public_event_screen.dart';
import 'package:musicians_flutter/views/create_session_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';
import 'package:provider/provider.dart';

import 'public_event_create_test.dart'
    show MockAppStateForCreateTest, SpyingFirebaseService;
import 'session_01_create_session_test.dart' show MockAppStateForSession01Test;
import 'support/bounded_ui_pump.dart';

final _sheet = find.byType(SearchableCategoryMultiSelectSheet);
final _other = find.descendant(of: _sheet, matching: find.text('Other'));
final _dialog = find.byType(AlertDialog);
final _nameField = find.descendant(
  of: _dialog,
  matching: find.byType(TextFormField),
);
final _saveName = find.descendant(of: _dialog, matching: find.text('Save'));
final _done = find.descendant(
  of: _sheet,
  matching: find.textContaining('Done'),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpUiTransitions(tester);
}

Future<void> _mount(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold()),
    ),
  );
}

Future<void> _openForm(
  WidgetTester tester,
  Widget form, {
  Object? arguments,
}) async {
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push<Object>(
        MaterialPageRoute<Object>(
          builder: (_) => form,
          settings: RouteSettings(arguments: arguments),
        ),
      );
  await pumpUiTransitions(tester);
}

Future<void> _addCustomGenre(
  WidgetTester tester,
  Finder genreField,
  String name,
) async {
  await _tap(tester, genreField);
  await _tap(tester, _other);
  await tester.enterText(_nameField, '   ');
  await _tap(tester, _saveName);
  expect(find.text('Enter a name.'), findsOneWidget);
  await tester.enterText(_nameField, ' bLuEs ');
  await _tap(tester, _saveName);
  expect(find.text('Choose this option from the list.'), findsOneWidget);
  await tester.enterText(_nameField, '  $name  ');
  await _tap(tester, _saveName);

  await _tap(tester, _other);
  await tester.enterText(_nameField, ' ${name.toUpperCase()} ');
  await _tap(tester, _saveName);
  expect(find.text('This option is already selected.'), findsOneWidget);
  await _tap(
    tester,
    find.descendant(of: _dialog, matching: find.text('Cancel')),
  );

  // Dismissing the sheet discards its draft while retaining the saved choice.
  await _tap(
    tester,
    find.descendant(of: _sheet, matching: find.byIcon(Icons.close_rounded)),
  );
  await _tap(tester, genreField);
  expect(find.descendant(of: _sheet, matching: find.text(name)), findsNothing);
  await _tap(tester, _other);
  await tester.enterText(_nameField, '  $name  ');
  await _tap(tester, _saveName);
  await _tap(tester, _done);
}

Future<void> _renameGenre(
  WidgetTester tester,
  Finder genreField,
  String original,
  String renamed,
) async {
  await _tap(tester, genreField);
  await _tap(
    tester,
    find.descendant(of: _sheet, matching: find.text(original)),
  );
  expect(tester.widget<TextFormField>(_nameField).initialValue, original);
  await tester.enterText(_nameField, ' $renamed ');
  await _tap(tester, _saveName);
  await _tap(tester, _done);
}

Future<void> _removeGenre(
  WidgetTester tester,
  Finder genreField,
  String name,
) async {
  await _tap(tester, genreField);
  await _tap(tester, find.byTooltip('Remove $name'));
  await _tap(tester, _done);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());

  testWidgets('Public event custom genres survive create, edit and reload', (
    tester,
  ) async {
    const original = 'Nordic Folk, Jazz';
    const renamed = 'Nordic Chamber Jazz';
    final repository = EmptyPublicEventRepository();
    await _mount(tester, MockAppStateForCreateTest(SpyingFirebaseService()));

    Future<PublicCalendarEvent> readSavedEvent() async {
      final event = (await repository.getUpcomingEvents()).single;
      return PublicCalendarEvent.fromJson(event.toJson(), event.id);
    }

    await _openForm(tester, CreatePublicEventScreen(repository: repository));
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'e.g. Stockholm Live Showcase, Jazz Jam',
      ),
      'Nordic Folk Showcase',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Jazzbaren, Fasching'),
      'Concert Hall',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Stockholm'),
      'Stockholm',
    );
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Detailed program, schedule, line-up, participant details...',
      ),
      'A folk showcase with live musicians.',
    );
    await selectBlues(tester, find.text('Select Genres & Tags'));
    await _addCustomGenre(tester, find.text('Edit Genres (1)'), original);
    await _tap(tester, find.byType(Switch));
    await _tap(tester, find.text('Publish Event'));

    final created = await readSavedEvent();
    final savedType = created.toJson()['eventType'];
    expect(created.genres, ['Blues', original]);
    await _openForm(
      tester,
      CreatePublicEventScreen(repository: repository, eventToEdit: created),
    );
    expect(find.widgetWithText(Chip, original), findsOneWidget);
    await _renameGenre(tester, find.text('Edit Genres (2)'), original, renamed);
    await _tap(tester, find.text('Save Changes'));

    final edited = await readSavedEvent();
    expect(edited.id, created.id);
    expect(edited.toJson()['eventType'], savedType);
    expect(edited.genres, ['Blues', renamed]);
    await _openForm(
      tester,
      CreatePublicEventScreen(repository: repository, eventToEdit: edited),
    );
    expect(find.widgetWithText(Chip, renamed), findsOneWidget);
    await _removeGenre(tester, find.text('Edit Genres (2)'), renamed);
    await _tap(tester, find.text('Save Changes'));

    final saved = await readSavedEvent();
    expect(saved.genres, ['Blues']);
    expect(saved.toJson()['eventType'], savedType);
  });

  testWidgets('Session custom genres survive create, edit and reload', (
    tester,
  ) async {
    const original = 'Nordic Folk, Jazz';
    const renamed = 'Nordic Chamber Jazz';
    final state = MockAppStateForSession01Test();
    await _mount(tester, state);

    Future<CollabSession> readSavedSession() async {
      final session =
          (await state.mockFirebase.getCollabSessionsAsync()).single;
      return CollabSession.fromJson(session.toJson(), session.id!);
    }

    await _openForm(tester, const CreateSessionScreen());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Session Title'),
      'Nordic Folk Workshop',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Session Description'),
      'A session for sharing arrangements.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Set hours here'),
      '24',
    );
    await selectBlues(tester, find.text('Tap to select genres'));
    await _addCustomGenre(tester, find.text('Blues'), original);
    await _tap(tester, find.text('Create Session'));

    final created = await readSavedSession();
    expect(created.genres, ['Blues', original]);
    await _openForm(tester, const CreateSessionScreen(), arguments: created);
    await _renameGenre(
      tester,
      find.text('Blues, $original'),
      original,
      renamed,
    );
    await _tap(tester, find.text('Save Changes'));

    final edited = await readSavedSession();
    expect(edited.id, created.id);
    expect(edited.sessionType, created.sessionType);
    expect(edited.sessionCategory, created.sessionCategory);
    expect(edited.genres, ['Blues', renamed]);
    await _openForm(tester, const CreateSessionScreen(), arguments: edited);
    await _removeGenre(tester, find.text('Blues, $renamed'), renamed);
    await _tap(tester, find.text('Save Changes'));

    final saved = await readSavedSession();
    expect(saved.genres, ['Blues']);
    expect(saved.sessionType, created.sessionType);
    expect(saved.sessionCategory, created.sessionCategory);
  });
}
