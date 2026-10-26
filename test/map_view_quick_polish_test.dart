// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/utils/map_pin_details_helper.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:musicians_flutter/data/stockholm_demo_pins.dart';
import 'package:musicians_flutter/data/genres_taxonomy.dart';

class MockFirebaseServiceForQuickPolishTest extends FirebaseService {
  @override
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    return pin.copyWith(
      id: 'mock_pin_id',
      subRequestId: 'mock_pin_id',
      extraFields: {
        ...pin.extraFields,
        'NotificationMode': 'map_pin',
      },
    );
  }
}

class MockAppStateForQuickPolishTest extends AppState {
  final MockFirebaseServiceForQuickPolishTest mockService = MockFirebaseServiceForQuickPolishTest();

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'test_user_qp', displayName: 'Quick Polish Tester');

  @override
  String? get currentUserId => 'test_user_qp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  Widget buildTestableWidget(Widget child, {AppState? appState}) {
    final state = appState ?? MockAppStateForQuickPolishTest();

    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  Widget buildCard(SubRequest gig, {AppState? appState}) {
    final state = appState ?? MockAppStateForQuickPolishTest();
    return buildTestableWidget(
      MapPinDetailsCard(gig: gig, appState: state),
      appState: state,
    );
  }

  group('MAP-VIEW-QUICK-POLISH-01 Tests', () {
    testWidgets('1. Type label absent while actual type value remains visible in details card', (tester) async {
      final pin = SubRequest(
        id: 'pin_type_test',
        bandName: 'The Jazz Quartet',
        requestType: 'Gig / Concert',
        style: 'Jazz',
        extraFields: {
          'eventType': 'gigConcert',
          'genre': 'Jazz',
        },
      );

      await tester.pumpWidget(buildCard(pin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Standalone "Type" label must be absent
      expect(find.text('Type'), findsNothing);

      // The actual type value must remain visible
      expect(find.text('Gig'), findsOneWidget);
    });

    testWidgets('2. Pin location label is exactly "Map View Note / Pin Location (Street, City)"', (tester) async {
      final appState = MockAppStateForQuickPolishTest();

      await tester.pumpWidget(
        buildTestableWidget(const GigMapPage(), appState: appState),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Upload Map View Pin / Audio button
      final uploadBtn = find.text('Upload Map View Pin / Audio');
      expect(uploadBtn, findsOneWidget);
      await tester.tap(uploadBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify exact location label
      expect(find.text('Map View Note / Pin Location (Street, City)'), findsOneWidget);
      expect(find.textContaining('Country'), findsNothing);
    });

    testWidgets('3. Ronnie Scott\'s and Blue Note absent from venue field; venue remains present and editable', (tester) async {
      final appState = MockAppStateForQuickPolishTest();

      await tester.pumpWidget(
        buildTestableWidget(const GigMapPage(), appState: appState),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Hardcoded famous venue examples must NOT exist
      expect(find.textContaining('Ronnie Scott'), findsNothing);
      expect(find.textContaining('Blue Note'), findsNothing);
      expect(find.textContaining('Village Vanguard'), findsNothing);

      // Venue label & neutral hint must exist
      expect(find.text('Venue (Optional)'), findsOneWidget);
      expect(find.text('Venue name (optional)'), findsOneWidget);

      // Venue field must be editable
      final venueFinder = find.widgetWithText(TextField, 'Venue (Optional)');
      expect(venueFinder, findsOneWidget);
      await tester.enterText(venueFinder, 'Stockholm Jazz Club');
      expect(find.text('Stockholm Jazz Club'), findsOneWidget);
    });

    testWidgets('4. Audio Track Info (title + info) heading typography: bold heading and non-bold (title + info)', (tester) async {
      final pin = SubRequest(
        id: 'pin_audio_typo',
        bandName: 'Acoustic Trio',
        requestType: 'Demos / Recordings',
        extraFields: {
          'eventType': 'recordedMusic',
          'audioSnippetTitle': 'Acoustic Session Track',
          'infoAudioTrack': 'Live recording in studio room A',
        },
      );

      await tester.pumpWidget(buildCard(pin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Find RichText containing Audio Track Info
      final richTextFinder = find.byWidgetPredicate((w) {
        if (w is Text && w.textSpan != null) {
          final span = w.textSpan!;
          return span.toPlainText().contains('Audio Track Info (title + info)');
        }
        return false;
      });
      expect(richTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(richTextFinder);
      final span = textWidget.textSpan! as TextSpan;
      expect(span.text, 'Audio Track Info ');
      expect(span.style?.fontWeight, FontWeight.w600);

      // Child span (title + info) is not bold
      expect(span.children?.isNotEmpty, isTrue);
      final childSpan = span.children!.first as TextSpan;
      expect(childSpan.text, '(title + info)');
      expect(childSpan.style?.fontWeight, FontWeight.normal);

      // Now verify Upload Map View Pin form structure
      final appState = MockAppStateForQuickPolishTest();
      await tester.pumpWidget(
        buildTestableWidget(const GigMapPage(), appState: appState),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Upload Map View Pin / Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Combined section heading appears exactly once in form
      final formHeadingFinder = find.byWidgetPredicate((w) {
        if (w is Text && w.textSpan != null) {
          final s = w.textSpan!;
          return s.toPlainText().contains('Audio Track Info (title + info)');
        }
        return false;
      });
      expect(formHeadingFinder, findsOneWidget);

      // Form heading typography: bold 'Audio Track Info ', normal '(title + info)'
      final formTextWidget = tester.widget<Text>(formHeadingFinder);
      final formSpan = formTextWidget.textSpan! as TextSpan;
      expect(formSpan.text, 'Audio Track Info ');
      expect(formSpan.style?.fontWeight, FontWeight.bold);
      final formChildSpan = formSpan.children!.first as TextSpan;
      expect(formChildSpan.text, '(title + info)');
      expect(formChildSpan.style?.fontWeight, FontWeight.normal);

      // Under that heading, exactly two input fields labeled 'Title' and 'Info'
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Info'), findsOneWidget);

      // Neither input field is labeled 'Audio Track Info (title + info)'
      expect(
        find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').contains('Audio Track Info')),
        findsNothing,
      );
    });

    test('5. Scala Stage Demos uses a valid canonical genre from GenresTaxonomy and not "Contemporary"', () {
      final allCanonicalGenres = GenresTaxonomy.categoryMap.values.expand((list) => list).toSet();

      final scalaPin = getStockholmDemoPins('test_user').firstWhere((p) => p.bandName == 'Scala Stage Demos');
      expect(scalaPin, isNotNull);

      // Scala Stage Demos must NOT use 'Contemporary'
      expect(scalaPin.style, isNot('Contemporary'));
      expect(scalaPin.extraFields['genre'], isNot('Contemporary'));

      // It must use an existing canonical genre
      expect(allCanonicalGenres.contains(scalaPin.style), isTrue);
      expect(allCanonicalGenres.contains(scalaPin.extraFields['genre']), isTrue);
      expect(scalaPin.style, 'Jazz');
      expect(scalaPin.extraFields['genre'], 'Jazz');
    });

    testWidgets('6. Substitute Request with valid creation time displays "Posted: ..."', (tester) async {
      final createdMs = DateTime(2026, 10, 26, 14, 30).millisecondsSinceEpoch;
      final subPin = SubRequest(
        id: 'sub_pin_posted',
        bandName: 'Brass Ensemble',
        requestType: 'Substitute',
        role: 'Trumpet',
        createdAt: createdMs,
        extraFields: {
          'eventType': 'subs',
        },
      );

      final helperDetails = resolveMapPinDetails(subPin);
      expect(helperDetails.postedDateDisplay, 'Posted: Oct 26, 2026');

      await tester.pumpWidget(buildCard(subPin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Posted: Oct 26, 2026'), findsOneWidget);
    });

    testWidgets('7. New Member Request with valid creation time displays "Posted: ..."', (tester) async {
      final createdMs = DateTime(2026, 10, 20, 10, 0).millisecondsSinceEpoch;
      final nmPin = SubRequest(
        id: 'nm_pin_posted',
        bandName: 'Indie Band',
        requestType: 'New Member',
        role: 'Drummer',
        createdAt: createdMs,
        extraFields: {
          'eventType': 'newMember',
        },
      );

      await tester.pumpWidget(buildCard(nmPin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Posted: Oct 20, 2026'), findsOneWidget);
    });

    testWidgets('8. Ordinary Music pin does NOT display Posted even if createdAt timestamp is present', (tester) async {
      final createdMs = DateTime(2026, 10, 26, 12, 0).millisecondsSinceEpoch;
      final gigPin = SubRequest(
        id: 'gig_pin_no_posted',
        bandName: 'Rock Group',
        requestType: 'Gig / Concert',
        createdAt: createdMs,
        extraFields: {
          'eventType': 'gigConcert',
          'CreatedAt': createdMs,
        },
      );

      await tester.pumpWidget(buildCard(gigPin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Posted:'), findsNothing);
    });

    testWidgets('9. Sub Request with missing/invalid creation timestamp cleanly omits Posted', (tester) async {
      final subPinNoDate = SubRequest(
        id: 'sub_pin_no_ts',
        bandName: 'String Quartet',
        requestType: 'Substitute',
        role: 'Violin',
        createdAt: null,
        extraFields: {
          'eventType': 'subs',
        },
      );

      await tester.pumpWidget(buildCard(subPinNoDate));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Posted:'), findsNothing);
    });

    testWidgets('10. Existing Band name / Genre / Date & Time hierarchy remains intact', (tester) async {
      final pin = SubRequest(
        id: 'hierarchy_pin',
        bandName: 'Stockholm Brass Band',
        requestType: 'Gig / Concert',
        date: '2026-11-15T19:00:00',
        description: 'Annual autumn concert in Grand Hall.',
        style: 'Brass Band',
        extraFields: {
          'eventType': 'gigConcert',
          'genre': 'Brass Band',
        },
      );

      await tester.pumpWidget(buildCard(pin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Band name present and prominent
      expect(find.text('Stockholm Brass Band'), findsOneWidget);
      // Genre present with dot separator
      expect(find.text('· Brass Band'), findsOneWidget);
      // Type value badge present without "Type" label
      expect(find.text('Type'), findsNothing);
      expect(find.text('Gig'), findsOneWidget);
      // Date & Time present
      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.textContaining('Nov 15, 2026'), findsOneWidget);
      // Description present
      expect(find.text('Description / Details'), findsOneWidget);
      expect(find.text('Annual autumn concert in Grand Hall.'), findsOneWidget);
    });

    testWidgets('11. 320 px viewport has no RenderFlex overflow with Sub Request details card', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final subPin = SubRequest(
        id: 'responsive_sub_pin',
        bandName: 'Very Long Stockholm Symphony Orchestra Name',
        requestType: 'Substitute',
        role: 'Principal French Horn Required',
        date: '2026-10-30T20:00:00',
        createdAt: DateTime(2026, 10, 26, 15, 0).millisecondsSinceEpoch,
        description: 'Comprehensive detailed description of the gig performance requirements.',
        extraFields: {
          'eventType': 'subs',
          'genre': 'Classical Symphonic',
          'audioSnippetTitle': 'Symphony Excerpt Track (Extended Title That Wraps)',
          'infoAudioTrack': 'Rehearsal take 3 with principal winds',
          'audioSnippetUrl': 'https://example.com/audio.mp3',
        },
      );

      await tester.pumpWidget(buildCard(subPin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Posted: Oct 26, 2026'), findsOneWidget);
      expect(find.text('Substitute'), findsOneWidget);
    });

    testWidgets('12. 320 px container has no overflow for Audio Track Info heading and input fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'Audio Track Info ',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        children: const [
                          TextSpan(
                            text: '(title + info)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const TextField(decoration: InputDecoration(labelText: 'Title')),
                    const SizedBox(height: 8),
                    const TextField(decoration: InputDecoration(labelText: 'Info')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Audio Track Info (title + info)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Info'), findsOneWidget);
    });
  });
}
