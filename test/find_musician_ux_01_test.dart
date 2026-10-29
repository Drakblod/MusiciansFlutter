import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/widgets/location_picker_field.dart';
import 'package:musicians_flutter/utils/map_view_unified_feed_helper.dart';

class _MockFindMusicianService extends Fake implements FirebaseService {
  final Map<String, BandEvent> events = {};
  final Map<String, List<BandEvent>> bandEvents = {};
  final Map<String, List<SubRequest>> eventSubRequests = {};
  final Map<String, UserProfile> userProfiles = {};
  final List<String> favoriteUserIds = [];
  final List<BandMember> bandMembers = [];
  Band? bandInfo;
  final List<SubRequest> allSubRequests = [];
  final List<SubRequest> savedBatchRequests = [];

  int publishCalls = 0;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUserId => 'organizer_1';

  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();

  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) => Stream.value(0);

  @override
  Stream<List<AppNotification>> subscribeToUserNotifications([String? userId]) => Stream.value([]);

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => <String>{};

  @override
  Future<void> initializePushNotifications() async {}

  @override
  Future<BandEvent?> getBandEventOnceAsync(String bandId, String eventId) async {
    return events[eventId];
  }

  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async {
    return bandEvents[bandId] ?? [];
  }

  @override
  Future<List<SubRequest>> getSubRequestsForEventAsync(String bandId, String eventId) async {
    return eventSubRequests[eventId] ?? [];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    if (userId == null) return null;
    return userProfiles[userId];
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return userProfiles.values.toList();
  }

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => favoriteUserIds;

  @override
  Future<bool> isFavoriteAsync(String targetUserId) async => favoriteUserIds.contains(targetUserId);

  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async => bandMembers;

  @override
  Future<Band?> getBandInfoAsync(String bandId) async => bandInfo;

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => allSubRequests;

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => allSubRequests;

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async => allSubRequests;

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async => {};

  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async => {};

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    if (bandInfo != null) return {bandInfo!.id ?? 'band_1': bandInfo!.name ?? 'Test Band'};
    return {};
  }

  @override
  Future<List<String>> saveSubRequestsBatchAsync(List<SubRequest> requests) async {
    publishCalls++;
    savedBatchRequests.addAll(requests);
    allSubRequests.addAll(requests);
    return requests.asMap().entries.map((e) => 'sub_id_${e.key}').toList();
  }

  @override
  Future<List<String>> publishSubRequestGroupAsync({
    required String? bandId,
    required String requestGroupId,
    required List<SubRequest> requests,
    String? bandName,
  }) async {
    return saveSubRequestsBatchAsync(requests);
  }
}

class _MockFindMusicianAppState extends AppState {
  final _MockFindMusicianService mockService = _MockFindMusicianService();
  String? testCurrentUserId = 'organizer_1';
  UserProfile? testUserProfile;
  String? testActiveBandId = 'band_1';
  String? testActiveBandName = 'Deku Tree Bongo';

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => testCurrentUserId;

  @override
  UserProfile? get currentUserProfile => testUserProfile;

  @override
  String? get activeBandId => testActiveBandId;

  @override
  String? get activeBandName => testActiveBandName;
}

Widget _createTestApp(_MockFindMusicianAppState appState, {SubRequest? initialRequest}) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: FindSubScreen(initialRequest: initialRequest),
    ),
  );
}

Future<void> _pumpFindSubScreen(
  WidgetTester tester,
  _MockFindMusicianAppState appState, {
  SubRequest? initialRequest,
  Size size = const Size(800, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(_createTestApp(appState, initialRequest: initialRequest));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late _MockFindMusicianAppState appState;

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = _MockFindMusicianAppState();
    appState.testUserProfile = UserProfile(
      userId: 'organizer_1',
      displayName: 'Alex Bongo',
      location: 'Sundsvall, Sweden',
      instruments: ['Electric Guitar'],
    );
  });

  group('FIND-MUSICIAN-UX-01 Form Hierarchy and Terminology', () {
    testWidgets('1. Request Type renders before Event Type', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      final requestTypeFinder = find.text('Request Type');
      final eventTypeFinder = find.text('Event Type');

      expect(requestTypeFinder, findsOneWidget);
      expect(eventTypeFinder, findsOneWidget);

      final reqTop = tester.getTopLeft(requestTypeFinder).dy;
      final evTop = tester.getTopLeft(eventTypeFinder).dy;
      expect(reqTop, lessThan(evTop), reason: 'Request Type must render above Event Type');
    });

    testWidgets('2. UI displays New Band Member in dropdown options', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Tap on the Request Type dropdown
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('New Band Member'), findsWidgets);
    });

    test('3. The existing canonical New Member value is still serialized', () {
      final sub = SubRequest(
        role: 'New Member',
        requestType: 'New Member',
        voicePart: 'Drums',
        location: 'Stockholm, Sweden',
      );
      final json = sub.toJson();
      expect(json['RequestType'] ?? json['requestType'], equals('New Member'));
      expect(json['Role'] ?? json['role'], equals('New Member'));
    });

    test('4. Existing legacy New Member records remain compatible', () {
      final legacyJson = {
        'SubRequestId': 'leg_1',
        'Role': 'new member',
        'VoicePart': 'Bass',
        'Location': 'Gothenburg, Sweden',
      };
      final parsed = SubRequest.fromJson(legacyJson, 'leg_1');
      expect(SubRequest.isNewMemberRecord(parsed), isTrue);
      expect(parsed.isNewMember, isTrue);
    });

    testWidgets('5. Event Type is hidden for New Band Member', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Event Type'), findsNothing);
    });

    testWidgets('6. Date & Time is hidden for New Band Member', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Date & Time'), findsNothing);
    });

    testWidgets('7. Event Type and Date & Time remain visible for Substitute', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      expect(find.text('Event Type'), findsOneWidget);
      expect(find.text('Date & Time'), findsOneWidget);
    });

    testWidgets('8. The redundant New Band Member Recruitment box is absent', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('New Band Member Recruitment'), findsNothing);
      expect(find.text('Publish an open position to find a new band member.'), findsNothing);
    });

    testWidgets('9. Exactly one Description / Details field is rendered', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      expect(find.text('Description / Details'), findsOneWidget);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Description / Details'), findsOneWidget);
    });

    testWidgets('10. Description / Details remains technically optional', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // For Substitute, publish with empty description succeeds without validation snackbar for description
      // First select event type
      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm location so validation passes
      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 62.3908,
          longitude: 17.3069,
          locationLabel: 'Sundsvall, Sweden',
          precision: LocationPrecision.exact,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
    });

    testWidgets('11. Payment Details maps to the existing payDetails field', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      expect(find.text('Payment Details'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Travel expenses included, payment after invoice, hotel included'),
        'Hotel and train covered',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Select event type and confirm location
      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 62.3908,
          longitude: 17.3069,
          locationLabel: 'Sundsvall, Sweden',
          precision: LocationPrecision.exact,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.savedBatchRequests.first.payDetails, equals('Hotel and train covered'));
    });

    testWidgets('12. Exactly one Location / Venue field is rendered', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      expect(find.text('Location / Venue'), findsOneWidget);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Location / Venue'), findsOneWidget);
    });

    testWidgets('13. Location / Venue still uses the canonical location picker', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      expect(find.byType(LocationPickerField), findsOneWidget);
    });

    testWidgets('14. New Band Member retains city-level privacy', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In New Band Member, LocationPickerField has cityPrecisionOnly = true
      final locPicker = tester.widget<LocationPickerField>(find.byType(LocationPickerField));
      expect(locPicker.effectiveCityOnly, isTrue);

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.329384,
          longitude: 18.068612,
          locationLabel: 'Stockholm, Sweden',
          precision: LocationPrecision.city,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('PUBLISH NEW BAND MEMBER SEARCH'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
      final published = appState.mockService.savedBatchRequests.first;
      expect(published.locationPrecision, equals(LocationPrecision.city));
      expect(published.placeId, isNull);
      expect(published.latitude, equals(59.3));
      expect(published.longitude, equals(18.1));
    });

    testWidgets('15. Substitute retains exact confirmed venue behavior', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      final locPicker = tester.widget<LocationPickerField>(find.byType(LocationPickerField));
      expect(locPicker.effectiveCityOnly, isFalse);
    });

    testWidgets('16. Switching request types does not serialize hidden stale fields', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Select event type for substitute
      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.3293,
          longitude: 18.0686,
          locationLabel: 'Stockholm, Sweden',
          precision: LocationPrecision.city,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('PUBLISH NEW BAND MEMBER SEARCH'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
      final published = appState.mockService.savedBatchRequests.first;
      expect(published.date, isNull);
      expect(published.startTime, isNull);
      expect(published.endTime, isNull);
      expect(published.extraFields['eventType'], isNull);
    });

    testWidgets('17. Switching back safely preserves applicable form input', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Enter description
      await tester.enterText(
        find.widgetWithText(TextField, 'Add description'),
        'Fun jazz gig in Sundsvall',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Fun jazz gig in Sundsvall'), findsOneWidget);

      // Switch back to Substitute
      await tester.tap(find.text('New Band Member').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Substitute').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Fun jazz gig in Sundsvall'), findsOneWidget);
    });

    testWidgets('18. Publishing New Band Member succeeds', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.3293,
          longitude: 18.0686,
          locationLabel: 'Stockholm, Sweden',
          precision: LocationPrecision.city,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('PUBLISH NEW BAND MEMBER SEARCH'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
      final published = appState.mockService.savedBatchRequests.first;
      expect(published.role, equals('New Member'));
      expect(published.requestType, equals('New Member'));
    });

    testWidgets('19. Publishing Substitute succeeds', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 62.3908,
          longitude: 17.3069,
          locationLabel: 'Sundsvall, Sweden',
          precision: LocationPrecision.exact,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
      final published = appState.mockService.savedBatchRequests.first;
      expect(published.role, equals('Substitute'));
      expect(published.requestType, equals('Substitute'));
    });

    test('20. Automatic Map View projection behavior remains intact', () {
      final newMember = SubRequest(
        role: 'New Member',
        requestType: 'New Member',
        latitude: 59.3,
        longitude: 18.1,
        locationPrecision: LocationPrecision.city,
        location: 'Stockholm, Sweden',
      );
      expect(classifyMapItem(newMember), equals(MapItemKind.newMemberRequest));

      final sub = SubRequest(
        role: 'Substitute',
        requestType: 'Substitute',
        latitude: 62.3908,
        longitude: 17.3069,
        locationPrecision: LocationPrecision.exact,
        location: 'Sundsvall, Sweden',
      );
      expect(classifyMapItem(sub), equals(MapItemKind.staffingRequest));
    });

    test('21. Manage Requests and Find Gigs still classify both request types correctly', () {
      final newMember = SubRequest(
        role: 'New Member',
        requestType: 'New Member',
      );
      final sub = SubRequest(
        role: 'Substitute',
        requestType: 'Substitute',
      );

      final gigGroupNewMember = GigGroup(
        groupId: 'g1',
        title: 'Recruitment',
        earliestDate: DateTime.now(),
        requests: [newMember],
      );
      expect(gigGroupNewMember.isNewMember, isTrue);

      final gigGroupSub = GigGroup(
        groupId: 'g2',
        title: 'Gig',
        earliestDate: DateTime.now(),
        requests: [sub],
      );
      expect(gigGroupSub.isNewMember, isFalse);
    });

    testWidgets('22. The form has no overflow at 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpFindSubScreen(tester, appState);

      expect(tester.takeException(), isNull);

      // Switch to New Band Member at 320 px
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('23. Switching Substitute -> New Band Member clears exact venue coordinates and placeId', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Confirm exact venue on Substitute
      final locStateSub = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locStateSub.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.33258,
          longitude: 18.0649,
          locationLabel: 'Fasching, Kungsgatan 63, Stockholm',
          precision: LocationPrecision.exact,
          placeId: 'google_place_fasching_123',
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(locStateSub.isConfirmed, isTrue);
      expect(locStateSub.currentLocation?.placeId, equals('google_place_fasching_123'));
      expect(locStateSub.currentLocation?.precision, equals(LocationPrecision.exact));

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // After switching, confirmed coordinates and placeId must be completely invalidated
      final locStateNewMember = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      expect(locStateNewMember.isConfirmed, isFalse);
      expect(locStateNewMember.currentLocation?.latitude, isNull);
      expect(locStateNewMember.currentLocation?.longitude, isNull);
      expect(locStateNewMember.currentLocation?.placeId, isNull);

      // Attempting to publish without reconfirming city location is blocked
      await tester.tap(find.text('PUBLISH NEW BAND MEMBER SEARCH'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(0));
      expect(find.text('Please confirm a valid city or location before publishing.'), findsOneWidget);
    });

    testWidgets('24. Switching New Band Member -> Substitute invalidates city coordinates and blocks publication without exact venue', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to New Band Member
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('New Band Member').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm city-level location
      final locStateNewMember = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locStateNewMember.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.3,
          longitude: 18.1,
          locationLabel: 'Stockholm, Sweden',
          precision: LocationPrecision.city,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(locStateNewMember.isConfirmed, isTrue);

      // Switch back to Substitute
      await tester.tap(find.text('New Band Member').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Substitute').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verified: confirmed status is invalidated upon transition to Substitute
      final locStateSub = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      expect(locStateSub.isConfirmed, isFalse);
      expect(locStateSub.currentLocation?.latitude, isNull);

      // Select event type
      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Attempting to publish Substitute without confirming an exact venue is blocked
      await tester.tap(find.textContaining('PUBLISH SUBSTITUTE REQUESTS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(0));
      expect(find.text('Please confirm a valid venue location with exact coordinates before publishing.'), findsOneWidget);
    });

    testWidgets('25. Publishing Other request succeeds with canonical requestType Other and role Other', (tester) async {
      await _pumpFindSubScreen(tester, appState);

      // Switch to Other
      await tester.tap(find.text('Substitute').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Other').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Select event type
      final eventTypeFinder = find.widgetWithText(DropdownButtonFormField<String>, 'Select Event Type');
      await tester.tap(eventTypeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Concert').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter and confirm venue location
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Location / Venue'),
        'Konserthuset, Stockholm',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final locationState = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      locationState.confirmLocationForTesting(
        const CanonicalLocation(
          latitude: 59.3326,
          longitude: 18.0649,
          locationLabel: 'Konserthuset, Stockholm',
          precision: LocationPrecision.exact,
          status: LocationResolutionStatus.resolved,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter description
      await tester.enterText(
        find.widgetWithText(TextField, 'Add description'),
        'Need sound engineer for concert',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap PUBLISH REQUEST
      await tester.tap(find.text('PUBLISH REQUEST'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appState.mockService.publishCalls, equals(1));
      final published = appState.mockService.savedBatchRequests.first;
      expect(published.requestType, equals('Other'));
      expect(published.role, equals('Other'));
      expect(published.description, equals('Need sound engineer for concert'));
      expect(published.location, equals('Konserthuset, Stockholm'));
    });
  });
}

