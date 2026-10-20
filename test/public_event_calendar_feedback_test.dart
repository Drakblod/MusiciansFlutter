import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/models/public_calendar_event.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/repositories/public_event_repository.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/theme/app_theme.dart';
import 'package:musicians_flutter/views/create_public_event_screen.dart';
import 'package:musicians_flutter/views/public_event_calendar_screen.dart';
import 'package:musicians_flutter/views/public_event_details_screen.dart';
import 'package:musicians_flutter/widgets/animated_tap_detector.dart';
import 'package:musicians_flutter/widgets/event_category_picker_sheet.dart';

class SpyingFirebaseService extends FirebaseService {
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(userId: 'u1', displayName: 'Test User');
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {'b1': 'Test Band'};
  }

  @override
  Future<List<PublicCalendarEvent>> getPublicCalendarEventsAsync() async => [];

  @override
  Future<String> savePublicCalendarEventAsync(PublicCalendarEvent event) async => event.id;
}

class MockAppStateForFeedbackTest extends AppState {
  final SpyingFirebaseService spyService;

  MockAppStateForFeedbackTest(this.spyService);

  @override
  FirebaseService get firebaseService => spyService;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_1',
        displayName: 'Test Musician',
        email: 'test@example.com',
      );

  @override
  String? get currentUserId => 'test_user_1';

  @override
  List<String> get selectedBubbles => [
        'event_calendar',
      ];
}

class SingleNoImageEventRepository implements PublicEventRepository {
  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async {
    return [
      PublicCalendarEvent(
        id: 'no_img_event_1',
        title: 'Acoustic Solo Night',
        eventType: PublicEventType.other,
        organizerName: 'Solo Artists',
        venueName: 'Kafé Vinyl',
        city: 'Stockholm',
        address: 'Vinylgatan 1',
        startDateTime: DateTime(2026, 9, 10, 19, 0),
        endDateTime: DateTime(2026, 9, 10, 21, 0),
        shortDescription: 'An intimate solo acoustic evening.',
        description: 'Detailed description for acoustic evening without image.',
        isMock: false,
        imageUrl: null,
      ),
    ];
  }

  @override
  Future<String> createEvent(PublicCalendarEvent event) async => event.id;

  @override
  Future<void> updateEvent(PublicCalendarEvent event) async {}

  @override
  Future<void> deleteEvent(String eventId) async {}
}

class SingleCreatorEventRepository implements PublicEventRepository {
  @override
  Future<List<PublicCalendarEvent>> getUpcomingEvents() async {
    return [
      PublicCalendarEvent(
        id: 'creator_event_1',
        title: 'Stockholm Jazz Night',
        eventType: PublicEventType.liveGig,
        organizerName: 'Stockholm Jazz Collective',
        venueName: 'Jazzbaren',
        city: 'Stockholm',
        address: 'Jazzgränd 4, Gamla Stan',
        startDateTime: DateTime(2026, 9, 10, 20, 0),
        endDateTime: DateTime(2026, 9, 10, 23, 0),
        shortDescription: 'Live jazz and swing evening.',
        description: 'Detailed description for live jazz and swing evening.',
        isMock: false,
        createdBy: 'test_user_1',
        status: PublicEventStatus.published,
      ),
    ];
  }

  @override
  Future<String> createEvent(PublicCalendarEvent event) async => event.id;

  @override
  Future<void> updateEvent(PublicCalendarEvent event) async {}

  @override
  Future<void> deleteEvent(String eventId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  final fixedRef = DateTime(2026, 8, 1, 12, 0);

  Widget createTestWidget({
    PublicEventRepository? repository,
  }) {
    final service = SpyingFirebaseService();
    return ChangeNotifierProvider<AppState>(
      create: (_) => MockAppStateForFeedbackTest(service),
      child: MaterialApp(
        routes: {
          '/event-calendar': (context) => PublicEventCalendarScreen(
                repository: repository ?? MockPublicEventRepository(referenceNow: fixedRef),
              ),
          '/public-event-details': (context) => const PublicEventDetailsScreen(),
        },
        home: PublicEventCalendarScreen(
          repository: repository ?? MockPublicEventRepository(referenceNow: fixedRef),
        ),
      ),
    );
  }

  group('EVENT-CALENDAR-01 Owner Feedback Tests', () {
    testWidgets('1. Search field placeholder is exactly "Search events..."', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final searchTextField = tester.widget<TextField>(find.byType(TextField));
      expect(searchTextField.decoration?.hintText, 'Search events...');
    });

    testWidgets('2. Tapping Search field immediately opens category picker sheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap search field
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Verify category picker sheet is opened
      expect(find.byType(EventCategoryPickerSheet), findsOneWidget);
      expect(find.text('EVENT CATEGORIES'), findsOneWidget);
    });

    testWidgets('3. Category options include Live/Gigs, Sessions, Workshops, and NOT Open Sessions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap to open sheet
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Verify required options exist
      expect(find.text('Live/Gigs'), findsWidgets);
      expect(find.text('Sessions'), findsWidgets);
      expect(find.text('Workshops'), findsWidgets);

      // Verify 'Open Sessions' is NEVER displayed
      expect(find.text('Open Sessions'), findsNothing);
      expect(find.textContaining(RegExp(r'open session', caseSensitive: false)), findsNothing);
    });

    testWidgets('4. Selecting a category filters the event list to matching event types', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initially Stockholm Jazz Night and Open Co-writing Session are visible
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);

      // Tap search field to open category picker
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Select 'Live/Gigs' from sheet
      await tester.tap(find.descendant(
        of: find.byType(EventCategoryPickerSheet),
        matching: find.text('Live/Gigs'),
      ));
      await tester.pumpAndSettle();

      // Only Live/Gig should be visible
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsNothing);
      expect(find.text('Music Production Workshop'), findsNothing);

      // Verify active category is displayed on screen
      expect(find.text('Active category:'), findsOneWidget);

      // Now filter by Workshops using the category tune button
      await tester.tap(find.byTooltip('Select Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(EventCategoryPickerSheet),
        matching: find.text('Workshops'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsNothing);
      expect(find.text('Open Co-writing Session'), findsNothing);
      expect(find.text('Music Production Workshop'), findsOneWidget);

      // Now filter by Sessions using the category tune button
      await tester.tap(find.byTooltip('Select Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(EventCategoryPickerSheet),
        matching: find.text('Sessions'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsNothing);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Music Production Workshop'), findsNothing);
    });

    testWidgets('5. Clearing category restores all events', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Filter by Live/Gigs
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(EventCategoryPickerSheet),
        matching: find.text('Live/Gigs'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Open Co-writing Session'), findsNothing);

      // Clear filter via "Clear filter" button
      await tester.tap(find.text('Clear filter'));
      await tester.pumpAndSettle();

      // Events restored
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Active category:'), findsNothing);
    });

    testWidgets('6. Text search works alongside and after category selection', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter search text directly
      await tester.enterText(find.byType(TextField), 'West Coast');
      await tester.pumpAndSettle();

      // Only Open Co-writing Session is organized by West Coast Songwriters
      expect(find.text('Open Co-writing Session'), findsOneWidget);
      expect(find.text('Stockholm Jazz Night'), findsNothing);

      // Clear text
      await tester.tap(find.byTooltip('Clear search text'));
      await tester.pumpAndSettle();

      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsOneWidget);
    });

    testWidgets('7. Venue and time row uses readable non-muted colors', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Check venue text color
      final venueText = tester.widget<Text>(find.text('Jazzbaren, Stockholm'));
      expect(venueText.style?.color, const Color(0xFFD4CEEB));
      expect(venueText.style?.color != AppTheme.textMuted, isTrue);

      // Check time text color
      final timeText = tester.widget<Text>(find.text('20:00 – 23:00'));
      expect(timeText.style?.color, const Color(0xFFD4CEEB));
      expect(timeText.style?.color != AppTheme.textMuted, isTrue);

      // Check icons colors
      final locationIcon = tester.widget<Icon>(find.byIcon(Icons.location_on_outlined).first);
      expect(locationIcon.color, const Color(0xFFA899E6));

      final timeIcon = tester.widget<Icon>(find.byIcon(Icons.access_time_rounded).first);
      expect(timeIcon.color, const Color(0xFFA899E6));
    });

    testWidgets('8. Cards with images render with upright A4 poster proportions (portrait format) beside event text and BoxFit.cover', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Mock events have demo artwork resolved on the cards
      final cardFinder = find.ancestor(
        of: find.text('Stockholm Jazz Night'),
        matching: find.byType(AnimatedTapDetector),
      );

      final cardImage = find.descendant(of: cardFinder, matching: find.byType(Image));
      expect(cardImage, findsOneWidget);
      expect(tester.widget<Image>(cardImage).fit, BoxFit.cover);

      // Verify the image container is upright/portrait (A4 proportion height > width)
      final imageBox = tester.getSize(cardImage);
      expect(imageBox.width, 110.0);
      expect(imageBox.height >= 150.0, isTrue);
      expect(imageBox.height > imageBox.width, isTrue);

      // Verify image is positioned on the left, with text beside it to the right
      final imageTopLeft = tester.getTopLeft(cardImage);
      final titleTopLeft = tester.getTopLeft(find.text('Stockholm Jazz Night'));
      expect(imageTopLeft.dx < titleTopLeft.dx, isTrue);
    });

    testWidgets('9. Cards without images render cleanly without broken or empty image box', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(repository: SingleNoImageEventRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Acoustic Solo Night'), findsOneWidget);

      // Verify no Image exists on the card itself
      final cardFinder = find.ancestor(
        of: find.text('Acoustic Solo Night'),
        matching: find.byType(AnimatedTapDetector),
      );
      expect(find.descendant(of: cardFinder, matching: find.byType(Image)), findsNothing);
    });

    testWidgets('10. Screen renders without overflow at 320px-wide viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('EVENT CALENDAR'), findsOneWidget);
    });

    testWidgets('11. Tap Search events opens sheet, dismiss allows text entry without loop', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 1. Tap Search events...
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(EventCategoryPickerSheet), findsOneWidget);

      // 2. Dismiss sheet (tap close button)
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(EventCategoryPickerSheet), findsNothing);

      // Repeated tap on TextField must NOT open the sheet again (prevents infinite loops)
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(EventCategoryPickerSheet), findsNothing);

      // 3. Enter text in the search field
      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();

      // 4. Verify filtered results
      expect(find.text('Stockholm Jazz Night'), findsOneWidget);
      expect(find.text('Open Co-writing Session'), findsNothing);
      expect(find.text('Music Production Workshop'), findsNothing);

      // Repeated taps while text is present do NOT open sheet
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(EventCategoryPickerSheet), findsNothing);
    });

    testWidgets('12. No duplicate horizontal category-options row exists on the calendar screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Complete category list must not appear as horizontal chips on the screen initially
      expect(find.text('All'), findsNothing);
      expect(find.text('Live/Gigs'), findsNothing);
      expect(find.text('Sessions'), findsNothing);
      expect(find.text('Workshops'), findsNothing);
      expect(find.text('Active category:'), findsNothing);
    });

    testWidgets('13. Calendar view is constrained to a max-width on wide desktop screens', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final constrainedBoxFinder = find.descendant(
        of: find.byType(PublicEventCalendarScreen),
        matching: find.byWidgetPredicate((widget) =>
            widget is ConstrainedBox &&
            widget.constraints.maxWidth == 800),
      );
      expect(constrainedBoxFinder, findsOneWidget);
    });

    testWidgets('14. Event cards display edit pencil icon button and tapping it opens edit event form for creator', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Using SingleCreatorEventRepository where createdBy == 'test_user_1'
      await tester.pumpWidget(createTestWidget(repository: SingleCreatorEventRepository()));
      await tester.pumpAndSettle();

      final editButton = find.byTooltip('Edit Event');
      expect(editButton, findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Tap edit pencil
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // Verify CreatePublicEventScreen opened in editing mode with prefilled event details
      expect(find.text('EDIT EVENT'), findsOneWidget);
      expect(find.text('Stockholm Jazz Night'), findsWidgets);
    });

    testWidgets('14b. Event cards do NOT display edit pencil icon button for non-creators or mock events', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Default mock events have no matching createdBy
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit Event'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('15. Event cards display clickable Read More button that opens PublicEventDetailsScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify "Read More" button exists on the cards
      final readMoreFinder = find.text('Read More');
      expect(readMoreFinder, findsWidgets);

      // Tap "Read More" on the first card
      await tester.tap(readMoreFinder.first);
      await tester.pumpAndSettle();

      // Verify PublicEventDetailsScreen opened
      expect(find.byType(PublicEventDetailsScreen), findsOneWidget);
      expect(find.text('ABOUT THIS EVENT'), findsOneWidget);
    });

    testWidgets('16. PublicEventDetailsScreen displays upright A4 poster with tap-to-zoom InteractiveViewer modal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final eventWithPoster = PublicCalendarEvent(
        id: 'poster_event_1',
        title: 'Festival Showcase',
        shortDescription: 'Grand festival with multiple stages and special guests.',
        description: 'Full detailed description for festival showcase.',
        eventType: PublicEventType.liveGig,
        organizerName: 'Jazz Club',
        venueName: 'Concert Hall',
        city: 'Stockholm',
        address: 'Storgatan 1',
        startDateTime: DateTime.now().add(const Duration(days: 3)),
        endDateTime: DateTime.now().add(const Duration(days: 3, hours: 3)),
        imageUrl: 'https://example.com/poster_festival.jpg',
      );

      final mockApp = MockAppStateForFeedbackTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: mockApp,
          child: MaterialApp(
            home: PublicEventDetailsScreen(
              event: eventWithPoster,
              repository: SingleNoImageEventRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify A4 poster pill and image are displayed
      expect(find.text('A4 Poster'), findsOneWidget);
      final posterImageFinder = find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage);
      expect(posterImageFinder, findsOneWidget);

      // Verify image container dimensions are upright A4 proportions (height > width)
      final posterSize = tester.getSize(posterImageFinder);
      expect(posterSize.height >= 320.0, isTrue);
      expect(posterSize.width >= 225.0, isTrue);
      expect(posterSize.height > posterSize.width, isTrue);

      // Tap on poster to open interactive full-screen zoom modal
      await tester.tap(find.byTooltip('Tap to view / zoom poster'));
      await tester.pumpAndSettle();
      tester.takeException();

      // Verify InteractiveViewer is opened in the dialog
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Close the modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('17. CreatePublicEventScreen displays upright A4 poster preview and Fit options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApp = MockAppStateForFeedbackTest(SpyingFirebaseService());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: mockApp,
          child: const MaterialApp(
            home: CreatePublicEventScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify upright A4 format indicator in upload container
      expect(find.text('Standing A4 Format'), findsOneWidget);
      expect(find.text('Upload Cover Photo or Poster'), findsOneWidget);

      // Enter an image URL to test A4 Poster Preview and Fit controls
      final imageField = find.widgetWithText(TextFormField, 'https://example.com/poster.jpg');
      await tester.enterText(imageField, 'https://example.com/gig_poster.jpg');
      await tester.pumpAndSettle();

      // Verify A4 Poster Preview indicator and Fit controls are present
      expect(find.text('A4 Poster Preview'), findsOneWidget);
      expect(find.text('Cover (Fill)'), findsOneWidget);
      expect(find.text('Contain (Full Image)'), findsOneWidget);

      // Toggle fit mode
      await tester.tap(find.text('Contain (Full Image)'));
      await tester.pumpAndSettle();
    });
  });
}
