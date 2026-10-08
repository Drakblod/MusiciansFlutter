import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/utils/thousands_separator_input_formatter.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:provider/provider.dart';

import 'find_musician_03b_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('FIND-MUSICIAN-UI-04: ThousandsSeparatorInputFormatter Unit Tests', () {
    test('1. format handles null, empty, 0, and integers with commas', () {
      expect(ThousandsSeparatorInputFormatter.format(null), isEmpty);
      expect(ThousandsSeparatorInputFormatter.format(0), equals('0'));
      expect(ThousandsSeparatorInputFormatter.format(1500), equals('1,500'));
      expect(ThousandsSeparatorInputFormatter.format(25000), equals('25,000'));
      expect(ThousandsSeparatorInputFormatter.format(1000000), equals('1,000,000'));
    });

    test('2. parse handles null, empty, malformed, and comma formatted strings', () {
      expect(ThousandsSeparatorInputFormatter.parse(null), isNull);
      expect(ThousandsSeparatorInputFormatter.parse(''), isNull);
      expect(ThousandsSeparatorInputFormatter.parse('   '), isNull);
      expect(ThousandsSeparatorInputFormatter.parse('1,500'), equals(1500));
      expect(ThousandsSeparatorInputFormatter.parse('25,000'), equals(25000));
      expect(ThousandsSeparatorInputFormatter.parse('1,000,000'), equals(1000000));
      expect(ThousandsSeparatorInputFormatter.parse('abc'), isNull);
      expect(ThousandsSeparatorInputFormatter.parse('1,234abc'), equals(1234));
    });

    test('3. formatEditUpdate correctly inserts commas and maintains cursor', () {
      final formatter = ThousandsSeparatorInputFormatter();

      // Type 1500 -> 1,500
      final result1 = formatter.formatEditUpdate(
        const TextEditingValue(text: '150', selection: TextSelection.collapsed(offset: 3)),
        const TextEditingValue(text: '1500', selection: TextSelection.collapsed(offset: 4)),
      );
      expect(result1.text, equals('1,500'));
      expect(result1.selection.baseOffset, equals(5));

      // Type 25000 -> 25,000
      final result2 = formatter.formatEditUpdate(
        const TextEditingValue(text: '2500', selection: TextSelection.collapsed(offset: 4)),
        const TextEditingValue(text: '25000', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(result2.text, equals('25,000'));
      expect(result2.selection.baseOffset, equals(6));

      // Type 1000000 -> 1,000,000
      final result3 = formatter.formatEditUpdate(
        const TextEditingValue(text: '100000', selection: TextSelection.collapsed(offset: 6)),
        const TextEditingValue(text: '1000000', selection: TextSelection.collapsed(offset: 7)),
      );
      expect(result3.text, equals('1,000,000'));
      expect(result3.selection.baseOffset, equals(9));
    });
  });

  group('FIND-MUSICIAN-UI-04: UI Corrections Widget Tests', () {
    late MockAppState03b appState;

    setUp(() {
      appState = MockAppState03b();
      appState.testCurrentUserId = 'organizer_1';
      appState.testUserProfile = UserProfile(
        userId: 'organizer_1',
        displayName: 'Organizer User',
        instruments: ['Vocals'],
      );

      appState.mockService.favoriteUserIds.clear();
      appState.mockService.favoriteUserIds.addAll(['fav_1', 'fav_2', 'fav_3']);
      appState.mockService.userProfiles['fav_1'] = UserProfile(
        userId: 'fav_1',
        displayName: 'Gurra Guitar',
        instruments: ['Electric Guitar'],
      );
      appState.mockService.userProfiles['fav_2'] = UserProfile(
        userId: 'fav_2',
        displayName: 'Alice Bass',
        instruments: ['Electric Guitar', 'Bass'],
      );
      appState.mockService.userProfiles['fav_3'] = UserProfile(
        userId: 'fav_3',
        displayName: 'Alex Prod',
        instruments: ['Producer'],
        userType: 'Producer',
      );
    });

    Widget createWidgetUnderTest({String? eventId, String? bandId}) {
      return ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          home: FindSubScreen(
            eventId: eventId,
            bandId: bandId ?? 'band_test_1',
          ),
        ),
      );
    }

    testWidgets('4. "Add all favorites" label is completely absent from the UI', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('Add all favorites'), findsNothing);
      expect(find.text('Add All Favorites'), findsNothing);
      expect(find.text('ADD ALL FAVORITES'), findsNothing);
    });

    testWidgets('5. "Select All" button is present and placed left-aligned directly above first favorite item', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      final selectAllFinder = find.text('Select All');
      expect(selectAllFinder, findsOneWidget);

      final firstFavFinder = find.widgetWithText(CheckboxListTile, 'Gurra Guitar');
      expect(firstFavFinder, findsOneWidget);

      // Verify Select All is vertically above the first favorite item
      final selectAllTop = tester.getTopLeft(selectAllFinder).dy;
      final firstFavTop = tester.getTopLeft(firstFavFinder).dy;
      expect(selectAllTop, lessThan(firstFavTop));
    });

    testWidgets('6. "Select All" is hidden when favorites list is empty', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      appState.mockService.favoriteUserIds.clear();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('Select All'), findsNothing);
      expect(find.textContaining('No favorites yet.'), findsOneWidget);
    });

    testWidgets('7. "Select All" selects all saved favorites without assigning a substitute', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      // Checkboxes are checked
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Gurra Guitar')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Alice Bass')).value, isTrue);

      // No assignment call was triggered
      expect(appState.mockService.assignCalls, equals(0));

      // Chosen Substitutes summary is shown
      expect(find.text('Chosen Substitutes'), findsOneWidget);
      expect(find.textContaining('Gurra Guitar, Alice Bass'), findsOneWidget);
    });

    testWidgets('8. "+ Add Favorite(s)" button is placed below the favorites list with adequate spacing', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      final addFavsFinder = find.text('+ Add Favorite(s)');
      expect(addFavsFinder, findsOneWidget);

      final lastFavFinder = find.widgetWithText(CheckboxListTile, 'Alice Bass');
      expect(lastFavFinder, findsOneWidget);

      final lastFavBottom = tester.getBottomLeft(lastFavFinder).dy;
      final addFavsTop = tester.getTopLeft(addFavsFinder).dy;
      expect(addFavsTop, greaterThan(lastFavBottom));
    });

    testWidgets('9. "+ Add Substitute" button label is exactly "+ Add Substitute" with no duplicate plus icon', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Button is present with text '+ Add Substitute'
      final addSubFinder = find.widgetWithText(OutlinedButton, '+ Add Substitute');
      expect(addSubFinder, findsOneWidget);

      // Verify no other button with ADD ANOTHER SUBSTITUTE or ADD SUBSTITUTE exists
      expect(find.text('ADD ANOTHER SUBSTITUTE'), findsNothing);
      expect(find.text('ADD SUBSTITUTE'), findsNothing);

      // Verify no extra plus icon inside the OutlinedButton
      final iconInsideBtn = find.descendant(of: addSubFinder, matching: find.byIcon(Icons.add));
      expect(iconInsideBtn, findsNothing);
    });

    testWidgets('10. Draft position shows "Remove Substitute" (not "Remove Slot")', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Add second slot
      await tester.tap(find.widgetWithText(OutlinedButton, '+ Add Substitute'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Substitute'), findsNWidgets(2));
      expect(find.text('Remove Slot'), findsNothing);

      // Tapping Remove Substitute removes the slot
      await tester.tap(find.text('Remove Substitute').last);
      await tester.pumpAndSettle();

      expect(find.text('Remove Substitute'), findsOneWidget);
    });

    testWidgets('11. Published position shows "Cancel Slot Request" (not Remove Substitute)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final pubSub = SubRequest(
        id: 'sub_pub_1',
        subRequestId: 'sub_pub_1',
        eventId: 'event_pub_1',
        bandId: 'band_test_1',
        voicePart: 'Electric Guitar',
        status: 'published',
      );
      appState.mockService.eventSubRequests['event_pub_1'] = [pubSub];

      final bandEv = BandEvent(
        id: 'event_pub_1',
        title: 'Gig Show',
        description: 'Test Description',
        eventType: 'Gig',
        location: 'Stockholm',
        startDateTime: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 2, hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      appState.mockService.events['event_pub_1'] = bandEv;

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_pub_1'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel Slot Request'), findsOneWidget);
      expect(find.text('Remove Substitute'), findsNothing);
    });

    testWidgets('12. Paid Gig input formats with thousands separators (1,500, 25,000, 1,000,000)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Default is Paid Gig = true with 1,500
      expect(find.text('Paid Gig'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);

      final amountField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.prefixText == 'SEK ');
      expect(amountField, findsOneWidget);
      await tester.ensureVisible(amountField);

      // Verify initial formatted value
      expect(tester.widget<TextField>(amountField).controller!.text, equals('1,500'));

      // Enter 25000
      await tester.enterText(amountField, '25000');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amountField).controller!.text, equals('25,000'));

      // Enter 1000000
      await tester.enterText(amountField, '1000000');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amountField).controller!.text, equals('1,000,000'));
    });

    testWidgets('13. Publishing saves correct integer payAmount (1500) and payAmountMinor (150000)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bandEv = BandEvent(
        id: 'event_test_pay',
        title: 'Special Show',
        description: 'Concert Gig',
        eventType: 'Gig',
        location: 'Stockholm',
        startDateTime: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        endDateTime: DateTime.now().add(const Duration(days: 2, hours: 2)).toIso8601String(),
        additionalNotes: '',
        createdBy: 'user_leader',
        createdAt: 100,
        updatedAt: 100,
        requireResponse: true,
      );
      appState.mockService.events['event_test_pay'] = bandEv;

      await tester.pumpWidget(createWidgetUnderTest(eventId: 'event_test_pay'));
      await tester.pumpAndSettle();

      // Publish with default Paid Gig (1,500)
      final publishBtn = find.textContaining('PUBLISH');
      await tester.ensureVisible(publishBtn);
      await tester.tap(publishBtn);
      await tester.pumpAndSettle();

      expect(appState.mockService.savedBatchRequests.isNotEmpty, isTrue);
      final savedSub = appState.mockService.savedBatchRequests.first;
      expect(savedSub.isPaid, isTrue);
      expect(savedSub.payAmount, equals(1500));
      expect(savedSub.payAmountMinor, equals(150000));
      expect(savedSub.currency, equals('SEK'));
    });

    testWidgets('14. New Band Member mode shares "Select All" and "+ Add Favorite(s)" layout', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Switch to New Band Member
      await tester.tap(find.text('Find New Band Member(s)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('+ Add Favorite(s)'), findsOneWidget);
      expect(find.text('Add all favorites'), findsNothing);
    });

    testWidgets('15. Responsive layout renders cleanly without errors or overflow', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Enable Paid Gig
      final switchFinder = find.byType(Switch).first;
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Add another substitute
      final addSubBtn = find.widgetWithText(OutlinedButton, '+ Add Substitute');
      await tester.ensureVisible(addSubBtn);
      await tester.tap(addSubBtn);
      await tester.pumpAndSettle();

      // Verify no flutter errors or overflow exceptions thrown
      final ex = tester.takeException();
      expect(ex, isNull);
    });

    testWidgets('16. Favorites list filters out favorites who do not play the chosen instrument', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open Favorites List for slot 1 (Electric Guitar)
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Electric Guitar players (Gurra Guitar, Alice Bass) should be visible
      expect(find.text('Gurra Guitar'), findsOneWidget);
      expect(find.text('Alice Bass'), findsOneWidget);

      // Alex Prod does not play Electric Guitar, so should be filtered out
      expect(find.text('Alex Prod'), findsNothing);
    });

    testWidgets('17. Changing slot instrument dynamically filters the favorites list', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Change instrument of Slot 1 from Electric Guitar to Bass
      final instrumentPicker = find.widgetWithText(InkWell, 'Role / Instrument');
      await tester.tap(instrumentPicker);
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).last;
      await tester.enterText(searchField, 'Bass');
      await tester.pumpAndSettle();

      final bassChip = find.widgetWithText(ChoiceChip, 'Bass');
      await tester.tap(bassChip);
      await tester.pumpAndSettle();

      // Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Bass players: only Alice Bass
      expect(find.text('Alice Bass'), findsOneWidget);
      expect(find.text('Gurra Guitar'), findsNothing);
      expect(find.text('Alex Prod'), findsNothing);
    });

    testWidgets('18. Selecting an instrument with no matching favorites displays informative empty state and hides Select All', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Change instrument of Slot 1 to Drums
      final instrumentPicker = find.widgetWithText(InkWell, 'Role / Instrument');
      await tester.tap(instrumentPicker);
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).last;
      await tester.enterText(searchField, 'Drums');
      await tester.pumpAndSettle();

      final drumsChip = find.widgetWithText(ChoiceChip, 'Drums');
      await tester.tap(drumsChip);
      await tester.pumpAndSettle();

      // Open Favorites List
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      // Empty state specifically for Drums
      expect(find.textContaining('No favorites saved for "Drums"'), findsOneWidget);
      expect(find.text('Select All'), findsNothing);
      expect(find.text('Gurra Guitar'), findsNothing);
      expect(find.text('Alice Bass'), findsNothing);
      expect(find.text('Alex Prod'), findsNothing);
    });

    testWidgets('19. Changing instrument prunes non-matching favorite IDs', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open Favorites List for slot 1 (Electric Guitar) and select all
      await tester.tap(find.text('Favorites List'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      // Chosen Substitutes summary should show Gurra Guitar and Alice Bass
      expect(find.textContaining('Gurra Guitar, Alice Bass'), findsOneWidget);

      // Now change instrument to Bass (which Gurra Guitar does not play)
      final instrumentPicker = find.widgetWithText(InkWell, 'Role / Instrument');
      await tester.tap(instrumentPicker);
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).last;
      await tester.enterText(searchField, 'Bass');
      await tester.pumpAndSettle();

      final bassChip = find.widgetWithText(ChoiceChip, 'Bass');
      await tester.tap(bassChip);
      await tester.pumpAndSettle();

      // Chosen Substitute summary should now only include Alice Bass (singular Chosen Substitute)
      expect(find.text('Chosen Substitute'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Alice Bass'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Gurra Guitar'), findsNothing);
    });
  });
}

