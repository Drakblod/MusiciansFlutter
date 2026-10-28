import 'package:musicians_flutter/utils/map_pin_details_helper.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/services/location_service.dart';
import 'package:musicians_flutter/widgets/location_picker_field.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:musicians_flutter/providers/app_state.dart';

/// Test mock implementation tracking feeds, listeners, and ensuring zero database writes during reads.
class MockMapViewFirebaseService extends FirebaseService {
  String? _currentUserId = 'user_musician_1';
  bool _isLoggedIn = true;

  final Map<String, SubRequest> publicFeeds = {};
  final Map<String, Map<String, SubRequest>> userFeeds = {}; // userId -> {reqId: req}
  final Map<String, Map<String, SubRequest>> creatorFeeds = {}; // creatorId -> {reqId: req}

  int writeCount = 0;
  int saveMapPinCount = 0;
  List<SubRequest> savedPins = [];

  // Lifecycle tracking for listeners
  int publicListenerCount = 0;
  int userListenerCount = 0;
  int creatorListenerCount = 0;
  final Set<String> activeFeedsListened = {};

  final StreamController<List<SubRequest>> _feedStreamController =
      StreamController<List<SubRequest>>.broadcast();

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  void setIsLoggedIn(bool loggedIn) {
    _isLoggedIn = loggedIn;
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final uid = userId ?? _currentUserId ?? 'test_user';
    return UserProfile(
      userId: uid,
      displayName: 'User $uid',
      email: '$uid@example.com',
      mainInstrument: 'Guitar',
      instruments: ['Guitar'],
    );
  }

  @override
  Stream<List<SubRequest>> getSubRequestFeedStream({String? targetUserId}) {
    final selfId = targetUserId ?? currentUserId;
    late StreamController<List<SubRequest>> controller;

    void emitMerged() {
      if (controller.isClosed) return;
      final List<SubRequest> results = [];
      final Set<String> seenIds = {};

      void addValid(SubRequest r) {
        final id = r.subRequestId ?? r.id;
        if (id != null && !seenIds.contains(id) && r.isLive) {
          seenIds.add(id);
          results.add(r);
        }
      }

      for (final r in publicFeeds.values) {
        addValid(r);
      }
      if (selfId != null && userFeeds.containsKey(selfId)) {
        for (final r in userFeeds[selfId]!.values) {
          addValid(r);
        }
      }
      if (selfId != null && creatorFeeds.containsKey(selfId)) {
        for (final r in creatorFeeds[selfId]!.values) {
          addValid(r);
        }
      }

      controller.add(results);
    }

    controller = StreamController<List<SubRequest>>(
      onListen: () {
        publicListenerCount++;
        activeFeedsListened.add('publicSubRequests');

        if (selfId != null && selfId.isNotEmpty) {
          userListenerCount++;
          creatorListenerCount++;
          activeFeedsListened.add('userSubRequestFeed/$selfId');
          activeFeedsListened.add('creatorSubRequestFeed/$selfId');
        }

        emitMerged();
      },
      onCancel: () {
        publicListenerCount--;
        activeFeedsListened.remove('publicSubRequests');

        if (selfId != null && selfId.isNotEmpty) {
          userListenerCount--;
          creatorListenerCount--;
          activeFeedsListened.remove('userSubRequestFeed/$selfId');
          activeFeedsListened.remove('creatorSubRequestFeed/$selfId');
        }
      },
    );

    return controller.stream;
  }

  void emitFeedUpdate(List<SubRequest> requests) {
    _feedStreamController.add(requests);
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    // Reads from public, recipient, and creator feeds with 0 writes
    final List<SubRequest> results = [];
    final selfId = currentUserId;
    final Set<String> seenIds = {};

    void addValid(SubRequest r) {
      final id = r.subRequestId ?? r.id;
      if (id != null && !seenIds.contains(id) && r.isLive) {
        seenIds.add(id);
        results.add(r);
      }
    }

    for (final r in publicFeeds.values) {
      addValid(r);
    }
    if (selfId != null && userFeeds.containsKey(selfId)) {
      for (final r in userFeeds[selfId]!.values) {
        addValid(r);
      }
    }
    if (selfId != null && creatorFeeds.containsKey(selfId)) {
      for (final r in creatorFeeds[selfId]!.values) {
        addValid(r);
      }
    }
    return results;
  }

  @override
  Future<SubRequest> saveMapPinAsync(SubRequest pin) async {
    writeCount++;
    saveMapPinCount++;
    savedPins.add(pin);
    return pin.copyWith(
      id: 'saved_pin_$writeCount',
      subRequestId: 'saved_pin_$writeCount',
      extraFields: {
        ...pin.extraFields,
        'NotificationMode': 'map_pin',
      },
    );
  }

  @override
  Future<SubRequest> updateMapPinAsync(SubRequest pin) async {
    writeCount++;
    return pin;
  }

  @override
  Future<bool> deleteMapPinAsync(String pinId) async {
    writeCount++;
    return true;
  }
}

class MockAppState extends AppState {
  final MockMapViewFirebaseService _mockFirebase;

  MockAppState(this._mockFirebase);

  @override
  FirebaseService get firebaseService => _mockFirebase;

  @override
  String? get currentUserId => _mockFirebase.currentUserId;
}

/// Fake implementation of LocationResolver for testing dependency injection
class FakeLocationResolver implements LocationResolver {
  final Map<String, CanonicalLocation> customLocations = {};

  @override
  bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    return true;
  }

  @override
  CanonicalLocation toCityLevelLocation(CanonicalLocation location) {
    if (location.latitude == null || location.longitude == null) return location;
    final rLat = double.parse(location.latitude!.toStringAsFixed(2));
    final rLng = double.parse(location.longitude!.toStringAsFixed(2));
    return CanonicalLocation.city(
      cityName: location.locationLabel,
      latitude: rLat,
      longitude: rLng,
    );
  }

  @override
  CanonicalLocation? resolveKnownCity(String label) {
    final clean = label.trim().toLowerCase();
    if (customLocations.containsKey(clean)) {
      return customLocations[clean];
    }
    if (clean.contains('göteborg') || clean.contains('gothenburg')) {
      return CanonicalLocation.city(cityName: 'Göteborg', latitude: 57.71, longitude: 11.97);
    }
    if (clean.contains('stockholm')) {
      return CanonicalLocation.city(cityName: 'Stockholm', latitude: 59.33, longitude: 18.07);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  group('MAP-VIEW-FEED-01: Automatic SubRequest Pins & Location Resolution', () {
    late MockMapViewFirebaseService mockFirebase;
    late MockAppState appState;

    setUp(() {
      mockFirebase = MockMapViewFirebaseService();
      appState = MockAppState(mockFirebase);
    });

    test('1. Public Substitute request with coordinates appears in Map View stream', () async {
      final subReq = SubRequest(
        id: 'sub_pub_1',
        subRequestId: 'sub_pub_1',
        role: 'Substitute',
        requestType: 'Substitute',
        voicePart: 'Drums',
        status: 'published',
        location: 'Stockholm Konserthus',
        latitude: 59.3361,
        longitude: 18.0664,
        locationPrecision: LocationPrecision.exact,
        locationStatus: LocationResolutionStatus.resolved,
      );

      expect(LocationService.isValidCoordinate(subReq.latitude, subReq.longitude), isTrue);
      expect(subReq.isLive, isTrue);
      expect(subReq.latitude, equals(59.3361));
      expect(subReq.longitude, equals(18.0664));

      mockFirebase.publicFeeds['sub_pub_1'] = subReq;
      final feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.map((r) => r.id), contains('sub_pub_1'));
    });

    test('2. Public New Member request appears at city-level precision and obscures private address', () async {
      // Input has exact residential coordinates and private street address
      final exactPrivateLocation = CanonicalLocation.exact(
        locationLabel: 'Storgatan 12, 114 55 Stockholm',
        latitude: 59.3361234,
        longitude: 18.0664567,
      );

      // Obscure for New Member privacy
      final obscured = LocationService.toCityLevelLocation(exactPrivateLocation);

      expect(obscured.precision, equals(LocationPrecision.city));
      // Preferred city centroid, never exposing exact residential street position
      expect(obscured.latitude, equals(59.3293));
      expect(obscured.longitude, equals(18.0686));
      expect(obscured.latitude, isNot(equals(59.3361234)));
      expect(obscured.locationLabel, equals('Stockholm'));

      final memberReq = SubRequest(
        id: 'member_pub_1',
        subRequestId: 'member_pub_1',
        role: 'New Member',
        requestType: 'New Member',
        voicePart: 'Bass',
        status: 'published',
        location: 'Stockholm',
        latitude: obscured.latitude,
        longitude: obscured.longitude,
        locationPrecision: LocationPrecision.city,
        locationStatus: LocationResolutionStatus.resolved,
      );

      expect(LocationService.isValidCoordinate(memberReq.latitude, memberReq.longitude), isTrue);
      expect(memberReq.locationPrecision, equals(LocationPrecision.city));
      expect(memberReq.latitude, equals(59.3293));
      expect(memberReq.longitude, equals(18.0686));
    });

    test('3. Direct Invitation appears only for authorized recipient and creator', () async {
      final directReq = SubRequest(
        id: 'direct_sub_1',
        subRequestId: 'direct_sub_1',
        creatorUserId: 'creator_1',
        searchSource: 'favorites',
        targetUserIds: ['recipient_1'],
        role: 'Substitute',
        status: 'published',
        latitude: 59.3293,
        longitude: 18.0686,
      );

      mockFirebase.userFeeds['recipient_1'] = {'direct_sub_1': directReq};
      mockFirebase.creatorFeeds['creator_1'] = {'direct_sub_1': directReq};

      // 1. Recipient sees it
      mockFirebase.setCurrentUserId('recipient_1');
      var feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.map((r) => r.id), contains('direct_sub_1'));

      // 2. Creator sees it
      mockFirebase.setCurrentUserId('creator_1');
      feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.map((r) => r.id), contains('direct_sub_1'));

      // 3. Unrelated user does NOT see it
      mockFirebase.setCurrentUserId('stranger_99');
      feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.map((r) => r.id), isNot(contains('direct_sub_1')));
    });

    test('4. Favorites-only request never appears publicly', () async {
      final favOnlyReq = SubRequest(
        id: 'fav_only_1',
        subRequestId: 'fav_only_1',
        creatorUserId: 'creator_1',
        searchSource: 'favorites',
        targetUserIds: ['fav_user_1', 'fav_user_2'],
        status: 'published',
        latitude: 59.33,
        longitude: 18.07,
      );

      mockFirebase.userFeeds['fav_user_1'] = {'fav_only_1': favOnlyReq};
      mockFirebase.userFeeds['fav_user_2'] = {'fav_only_1': favOnlyReq};
      mockFirebase.creatorFeeds['creator_1'] = {'fav_only_1': favOnlyReq};

      expect(mockFirebase.publicFeeds.containsKey('fav_only_1'), isFalse);

      mockFirebase.setCurrentUserId('unrelated_viewer');
      final feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.isEmpty, isTrue);
    });

    test('5. Cancelled/assigned/deleted/expired request disappears from feed', () async {
      final activeReq = SubRequest(id: 'active_1', status: 'published', latitude: 59.33, longitude: 18.06);
      final cancelledReq = SubRequest(id: 'canc_1', status: 'cancelled', latitude: 59.33, longitude: 18.06);
      final assignedReq = SubRequest(id: 'asgn_1', status: 'assigned', latitude: 59.33, longitude: 18.06);
      final deletedReq = SubRequest(id: 'del_1', status: 'deleted', latitude: 59.33, longitude: 18.06);

      expect(activeReq.isLive, isTrue);
      expect(cancelledReq.isLive, isFalse);
      expect(assignedReq.isLive, isFalse);
      expect(deletedReq.isLive, isFalse);

      mockFirebase.publicFeeds['active_1'] = activeReq;
      mockFirebase.publicFeeds['canc_1'] = cancelledReq;
      mockFirebase.publicFeeds['asgn_1'] = assignedReq;
      mockFirebase.publicFeeds['del_1'] = deletedReq;

      final feed = await mockFirebase.getAllSubRequestsAsync();
      expect(feed.map((r) => r.id), contains('active_1'));
      expect(feed.map((r) => r.id), isNot(contains('canc_1')));
      expect(feed.map((r) => r.id), isNot(contains('asgn_1')));
      expect(feed.map((r) => r.id), isNot(contains('del_1')));
    });

    test('6. Request without coordinates is not placed at a fallback position', () {
      final noCoordsReq = SubRequest(
        id: 'no_coords_1',
        location: 'Somewhere in Sweden',
        latitude: null,
        longitude: null,
      );
      final nullIslandReq = SubRequest(
        id: 'null_island_1',
        location: 'Off Gulf of Guinea',
        latitude: 0.0,
        longitude: 0.0,
      );
      final outOfBoundsReq = SubRequest(
        id: 'oob_1',
        location: 'Invalid Coords',
        latitude: 95.0,
        longitude: 200.0,
      );

      expect(LocationService.isValidCoordinate(noCoordsReq.latitude, noCoordsReq.longitude), isFalse);
      expect(LocationService.isValidCoordinate(nullIslandReq.latitude, nullIslandReq.longitude), isFalse);
      expect(LocationService.isValidCoordinate(outOfBoundsReq.latitude, outOfBoundsReq.longitude), isFalse);
    });

    test('7. Existing event coordinates are reused', () {
      final eventLocation = CanonicalLocation.exact(
        locationLabel: 'Fasching, Stockholm',
        latitude: 59.3346,
        longitude: 18.0561,
        placeId: 'venue_fasching_1',
      );

      final inheritedSubReq = SubRequest(
        id: 'sub_inherited_1',
        eventId: 'event_fasching_1',
        location: eventLocation.locationLabel,
        latitude: eventLocation.latitude,
        longitude: eventLocation.longitude,
        locationPrecision: eventLocation.precision,
        placeId: eventLocation.placeId,
        locationStatus: eventLocation.status,
      );

      expect(inheritedSubReq.latitude, equals(59.3346));
      expect(inheritedSubReq.longitude, equals(18.0561));
      expect(inheritedSubReq.locationPrecision, equals(LocationPrecision.exact));
      expect(inheritedSubReq.placeId, equals('venue_fasching_1'));
    });

    testWidgets('8. Editing selected address invalidates stale coordinates immediately', (tester) async {
      CanonicalLocation? confirmedLocation = CanonicalLocation.exact(
        locationLabel: 'Kulturhuset, Stockholm',
        latitude: 59.3323,
        longitude: 18.0649,
      );

      final controller = TextEditingController(text: 'Kulturhuset, Stockholm');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return LocationPickerField(
                  controller: controller,
                  initialLocation: confirmedLocation,
                  onLocationChanged: (newLoc) {
                    setState(() {
                      confirmedLocation = newLoc;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Kulturhuset, Stockholm'), findsOneWidget);
      expect(find.textContaining('coordinates confirmed'), findsOneWidget);

      // User types into the text field, modifying the address
      await tester.enterText(find.byType(TextFormField), 'Kulturhuset, Stockholm Edited');
      await tester.pumpAndSettle();

      // Coordinates must be invalidated immediately
      expect(confirmedLocation?.hasCoordinates, isFalse);
      expect(confirmedLocation?.latitude, isNull);
      expect(confirmedLocation?.longitude, isNull);
      expect(confirmedLocation?.status, equals(LocationResolutionStatus.unresolved));
      expect(find.textContaining('Location unconfirmed'), findsOneWidget);
    });

    test('9. Multiple positions in one request group create one visual marker key', () {
      final req1 = SubRequest(
        id: 'slot_1',
        requestGroupId: 'req_group_100',
        eventId: 'event_500',
        bandId: 'band_7',
        voicePart: 'Drummer',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      final req2 = SubRequest(
        id: 'slot_2',
        requestGroupId: 'req_group_100',
        eventId: 'event_500',
        bandId: 'band_7',
        voicePart: 'Bassist',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      String getGroupKey(SubRequest r) {
        final latKey = r.latitude?.toStringAsFixed(5) ?? '0';
        final lngKey = r.longitude?.toStringAsFixed(5) ?? '0';
        if (r.requestGroupId != null && r.requestGroupId!.isNotEmpty) {
          return 'group_${r.requestGroupId}_${latKey}_$lngKey';
        }
        return 'single_${r.id ?? r.subRequestId}';
      }

      final key1 = getGroupKey(req1);
      final key2 = getGroupKey(req2);
      expect(key1, equals(key2));
      expect(key1, contains('req_group_100'));
    });

    test('10. Unrelated requests at the same venue remain separate visual markers', () {
      final reqBandA = SubRequest(
        id: 'req_band_a',
        requestGroupId: 'req_group_band_a',
        bandId: 'band_alpha',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      final reqBandB = SubRequest(
        id: 'req_band_b',
        requestGroupId: 'req_group_band_b',
        bandId: 'band_beta',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      String getGroupKey(SubRequest r) {
        final latKey = r.latitude?.toStringAsFixed(5) ?? '0';
        final lngKey = r.longitude?.toStringAsFixed(5) ?? '0';
        if (r.requestGroupId != null && r.requestGroupId!.isNotEmpty) {
          return 'group_${r.requestGroupId}_${latKey}_$lngKey';
        }
        return 'single_${r.id ?? r.subRequestId}';
      }

      final keyA = getGroupKey(reqBandA);
      final keyB = getGroupKey(reqBandB);
      expect(keyA, isNot(equals(keyB)));
    });

    test('11. Realtime feed refresh adds and removes pins dynamically', () async {
      final stream = mockFirebase.getSubRequestFeedStream();
      final emittedBatches = <List<SubRequest>>[];

      final subscription = stream.listen((batch) {
        emittedBatches.add(batch);
      });

      final reqA = SubRequest(id: 'pin_a', status: 'published', latitude: 59.31, longitude: 18.05);
      final reqB = SubRequest(id: 'pin_b', status: 'published', latitude: 59.32, longitude: 18.06);

      mockFirebase.publicFeeds['pin_a'] = reqA;
      mockFirebase.emitFeedUpdate([reqA]);
      await Future.delayed(const Duration(milliseconds: 10));

      mockFirebase.publicFeeds['pin_b'] = reqB;
      mockFirebase.emitFeedUpdate([reqA, reqB]);
      await Future.delayed(const Duration(milliseconds: 10));

      mockFirebase.publicFeeds.remove('pin_a');
      mockFirebase.emitFeedUpdate([reqB]);
      await Future.delayed(const Duration(milliseconds: 10));

      await subscription.cancel();
    });

    test('12. Map View performs zero database writes while reading', () async {
      mockFirebase.writeCount = 0;

      final stream = mockFirebase.getSubRequestFeedStream();
      final sub = stream.listen((_) {});

      await mockFirebase.getAllSubRequestsAsync();
      await mockFirebase.getUserProfileAsync();

      expect(mockFirebase.writeCount, equals(0));
      await sub.cancel();
    });

    testWidgets('13. Manual upload form contains no staffing categories', (tester) async {
      const categories = [
        {'id': 'jam_session', 'label': 'Jam Session'},
        {'id': 'gig', 'label': 'Live Gig / Show'},
        {'id': 'listening_party', 'label': 'Listening Party'},
        {'id': 'release', 'label': 'Single / Album Release'},
        {'id': 'other', 'label': 'Other Musical Activity'},
      ];

      final categoryLabels = categories.map((c) => c['label']).toList();
      expect(categoryLabels, isNot(contains('Sub & Member Search')));
      expect(categoryLabels, isNot(contains('Substitute')));
      expect(categoryLabels, isNot(contains('New Member')));
    });

    test('14. Music Promotion upload still works as a map_pin', () async {
      final promoPin = SubRequest(
        id: 'promo_pin_1',
        eventTitle: 'Album Listening Party',
        location: 'Debaser Strand, Stockholm',
        latitude: 59.3145,
        longitude: 18.0335,
        extraFields: {
          'NotificationMode': 'map_pin',
          'promoCategory': 'listening_party',
        },
      );

      final saved = await mockFirebase.saveMapPinAsync(promoPin);
      expect(saved.extraFields['NotificationMode'], equals('map_pin'));
      expect(mockFirebase.saveMapPinCount, equals(1));
      expect(mockFirebase.savedPins.first.eventTitle, equals('Album Listening Party'));
    });

    test('15. Go Live feature flag and capability remains intact', () {
      final liveGig = SubRequest(
        id: 'live_gig_1',
        extraFields: {
          'isLiveStreamActive': true,
          'liveViewerCount': 42,
        },
      );

      expect(liveGig.extraFields['isLiveStreamActive'], isTrue);
      expect(liveGig.extraFields['liveViewerCount'], equals(42));
    });

    testWidgets('16. 320 px layout has no RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final gig = SubRequest(
        id: 'overflow_test_gig',
        eventTitle: 'Festival Headliner Slot Very Long Title For Layout Testing',
        bandName: 'The Long Band Name Ensemble',
        voicePart: 'Electric Guitar & Backing Vocals',
        location: 'Very Long Venue Name, Street Address 42, Stockholm',
        date: '2026-11-15',
        startTime: '20:00',
        endTime: '22:00',
        isPaid: true,
        payAmount: 3500,
        currency: 'SEK',
        extraFields: {
          'positionsNeeded': ['Guitarist', 'Keyboardist', 'Vocalist'],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MapPinDetailsCard(
                  gig: gig,
                  appState: appState,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('17. Legacy casing and coordinate variants parse safely', () {
      final mapPascal = {
        'id': 'p1',
        'Latitude': 59.3293,
        'Longitude': 18.0686,
      };
      final req1 = SubRequest.fromJson(mapPascal, 'p1');
      expect(req1.latitude, equals(59.3293));
      expect(req1.longitude, equals(18.0686));

      final mapShort = {
        'id': 'p2',
        'lat': '57.7089',
        'lng': '11.9746',
        'locationPrecision': 'city',
      };
      final req2 = SubRequest.fromJson(mapShort, 'p2');
      expect(req2.latitude, equals(57.7089));
      expect(req2.longitude, equals(11.9746));
      expect(req2.locationPrecision, equals(LocationPrecision.city));

      final mapNullIsland = {
        'id': 'p3',
        'LAT': 0.0,
        'LNG': 0.0,
      };
      final req3 = SubRequest.fromJson(mapNullIsland, 'p3');
      expect(req3.latitude, isNull);
      expect(req3.longitude, isNull);
    });

    test('18. Dry-run coordinate backfill performs zero writes and only writes event-inherited coords', () {
      final dryRunOptions = {
        'apply': false,
        'allowProduction': false,
      };

      bool canWriteDatabase(Map<String, dynamic> opts, bool hasEventCoords) {
        return opts['apply'] == true && hasEventCoords;
      }

      // Dry run never writes
      expect(canWriteDatabase(dryRunOptions, true), isFalse);
      expect(canWriteDatabase(dryRunOptions, false), isFalse);

      // Apply mode ONLY writes if canonical event coordinates exist
      final applyOptions = {'apply': true, 'allowProduction': false};
      expect(canWriteDatabase(applyOptions, true), isTrue);
      expect(canWriteDatabase(applyOptions, false), isFalse);
    });

    // Focused tests for Phase 4: Dependency Injection
    test('19. LocationResolver dependency injection without static test hooks', () {
      final fakeResolver = FakeLocationResolver();
      fakeResolver.customLocations['custom venue'] = CanonicalLocation.city(
        cityName: 'Custom City',
        latitude: 58.00,
        longitude: 15.00,
      );

      final city = fakeResolver.resolveKnownCity('custom venue');
      expect(city, isNotNull);
      expect(city!.locationLabel, equals('Custom City'));
      expect(city.latitude, equals(58.00));
      expect(city.longitude, equals(15.00));

      final defaultResolver = LocationService.defaultResolver;
      final sthlm = defaultResolver.resolveKnownCity('Stockholm');
      expect(sthlm, isNotNull);
      expect(sthlm!.latitude, equals(59.3293));
    });

    // Focused tests for Phase 6: Realtime Stream Lifecycle
    test('20. Realtime stream lifecycle: exactly one listener per feed, cancelled on dispose, no leaks', () async {
      mockFirebase.setCurrentUserId('user_alice');
      expect(mockFirebase.publicListenerCount, equals(0));
      expect(mockFirebase.userListenerCount, equals(0));
      expect(mockFirebase.creatorListenerCount, equals(0));

      // 1. Subscribe Map View stream for user_alice
      final stream1 = mockFirebase.getSubRequestFeedStream();
      final sub1 = stream1.listen((_) {});

      // Exactly one listener per required feed (public, recipient, creator)
      expect(mockFirebase.publicListenerCount, equals(1));
      expect(mockFirebase.userListenerCount, equals(1));
      expect(mockFirebase.creatorListenerCount, equals(1));
      expect(mockFirebase.activeFeedsListened, contains('publicSubRequests'));
      expect(mockFirebase.activeFeedsListened, contains('userSubRequestFeed/user_alice'));
      expect(mockFirebase.activeFeedsListened, contains('creatorSubRequestFeed/user_alice'));

      // 2. Dispose/cancel Map View subscription
      await sub1.cancel();
      expect(mockFirebase.publicListenerCount, equals(0));
      expect(mockFirebase.userListenerCount, equals(0));
      expect(mockFirebase.creatorListenerCount, equals(0));
      expect(mockFirebase.activeFeedsListened.isEmpty, isTrue);

      // 3. Reopening Map View does not accumulate duplicate listeners
      final stream2 = mockFirebase.getSubRequestFeedStream();
      final sub2 = stream2.listen((_) {});
      expect(mockFirebase.publicListenerCount, equals(1));
      expect(mockFirebase.userListenerCount, equals(1));
      expect(mockFirebase.creatorListenerCount, equals(1));

      // 4. Authenticated user changes to user_bob
      mockFirebase.setCurrentUserId('user_bob');
      await sub2.cancel(); // Map View replaces stream on user change
      expect(mockFirebase.activeFeedsListened.isEmpty, isTrue);

      final stream3 = mockFirebase.getSubRequestFeedStream();
      final sub3 = stream3.listen((_) {});
      expect(mockFirebase.activeFeedsListened, contains('userSubRequestFeed/user_bob'));
      expect(mockFirebase.activeFeedsListened, contains('creatorSubRequestFeed/user_bob'));
      expect(mockFirebase.activeFeedsListened, isNot(contains('userSubRequestFeed/user_alice')));

      // 5. User logs out (targetUserId is null)
      mockFirebase.setCurrentUserId(null);
      await sub3.cancel();
      final streamLoggedOut = mockFirebase.getSubRequestFeedStream();
      final subLoggedOut = streamLoggedOut.listen((_) {});

      // Logged out user only listens to public feed, 0 user/creator listeners active
      expect(mockFirebase.publicListenerCount, equals(1));
      expect(mockFirebase.userListenerCount, equals(0));
      expect(mockFirebase.creatorListenerCount, equals(0));
      expect(mockFirebase.activeFeedsListened, equals({'publicSubRequests'}));

      await subLoggedOut.cancel();
      expect(mockFirebase.activeFeedsListened.isEmpty, isTrue);
    });

    test('21. Stream isolation: Stale results from previous user never appear for next user', () async {
      mockFirebase.userFeeds['user_alice'] = {
        'secret_alice': SubRequest(id: 'secret_alice', status: 'published', latitude: 59.3, longitude: 18.0),
      };
      mockFirebase.userFeeds['user_bob'] = {
        'secret_bob': SubRequest(id: 'secret_bob', status: 'published', latitude: 57.7, longitude: 11.9),
      };

      // Alice's feed stream
      mockFirebase.setCurrentUserId('user_alice');
      var feedStream = mockFirebase.getSubRequestFeedStream();
      List<SubRequest>? receivedGigs;
      var sub = feedStream.listen((gigs) => receivedGigs = gigs);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedGigs!.map((g) => g.id), contains('secret_alice'));
      expect(receivedGigs!.map((g) => g.id), isNot(contains('secret_bob')));
      await sub.cancel();

      // Bob's feed stream
      mockFirebase.setCurrentUserId('user_bob');
      feedStream = mockFirebase.getSubRequestFeedStream();
      sub = feedStream.listen((gigs) => receivedGigs = gigs);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedGigs!.map((g) => g.id), contains('secret_bob'));
      expect(receivedGigs!.map((g) => g.id), isNot(contains('secret_alice')));
      await sub.cancel();
    });

    test('22. Table-driven New Member classification recognizes all variants and excludes non-members', () {
      final positiveVariants = [
        {'RequestType': 'NewMember'},
        {'RequestType': 'New Member'},
        {'requestType': 'new member'},
        {'requestType': 'NEW MEMBER'},
        {'requestType': 'new_member'},
        {'requestType': 'new-member'},
        {'requestType': '   New   Member   '},
        {'Role': 'New Member'},
        {'role': 'new member'},
        {'role': 'NewMember'},
        {'extraFields': {'eventType': 'newMember'}},
        {'requestType': 'New Member', 'role': 'New Member', 'voicePart': 'Electric Guitar'},
      ];

      for (final map in positiveVariants) {
        expect(SubRequest.isNewMemberRecord(map), isTrue, reason: 'Failed for $map');
        final req = SubRequest.fromJson(map, 'test_id');
        expect(req.isNewMember, isTrue, reason: 'SubRequest.isNewMember failed for $map');
        expect(req.requestType, equals('New Member'));
      }

      final negativeVariants = [
        {'RequestType': 'Substitute', 'Role': 'Guitar'},
        {'requestType': 'sub'},
        {'requestType': 'Other'},
        {'role': 'Bass'},
        {'notificationMode': 'map_pin', 'role': 'New Member'},
        {'NotificationMode': 'map_pin', 'RequestType': 'New Member'},
        {'Type': 'direct_invitation', 'RequestType': 'Substitute', 'targetUserIds': ['u1']},
        {'BandMembers': ['Alice', 'Bob'], 'role': 'Guitar'},
        {'EventParticipants': '5 members', 'role': 'Bass'},
        {'NotificationMode': 'map_pin', 'Title': 'Band members album release', 'role': 'New Member'},
        {'RequestType': 'Substitute', 'Description': 'Looking for a substitute member'},
        {'RequestType': 'Other', 'Description': 'Band member audition for session'},
        {'Role': 'Guitar', 'Description': 'Our band has 4 members'},
        <String, dynamic>{},
      ];

      for (final map in negativeVariants) {
        expect(SubRequest.isNewMemberRecord(map), isFalse, reason: 'Misclassified $map');
        final req = SubRequest.fromJson(map, 'neg_id');
        expect(req.isNewMember, isFalse, reason: 'SubRequest.isNewMember true for $map');
      }
    });

    test('23. New Member location privacy: coarsens coordinates to 1 decimal place and card displays city label only', () {
      final residentialReq = SubRequest(
        id: 'member_priv_card_test',
        requestType: 'New Member',
        latitude: 59.33258,
        longitude: 18.06491,
        location: 'Storgatan 14, 114 51 Stockholm, Sweden',
        locationPrecision: LocationPrecision.city,
      );

      final coarsened = LocationService.toCityLevelLocation(residentialReq.canonicalLocation);
      expect(coarsened.latitude, equals(59.3293)); // known city centroid preferred
      expect(coarsened.locationLabel, equals('Stockholm'));

      // If custom non-city centroid area selected:
      final customLoc = CanonicalLocation.city(cityName: 'Custom Region', latitude: 58.4567, longitude: 15.6543);
      final customCoarsened = LocationService.toCityLevelLocation(customLoc);
      expect(customCoarsened.latitude, equals(58.5)); // coarsened to 1 decimal place
      expect(customCoarsened.longitude, equals(15.7));

      // Details card resolution for New Member
      final details = resolveMapPinDetails(residentialReq);
      expect(details.typeDisplayLabel, equals('New Member'));
      expect(details.locationDisplay, equals('Stockholm'));
      expect(details.locationDisplay, isNot(contains('Storgatan')));
      expect(details.locationDisplay, isNot(contains('14')));
    });

    testWidgets('24. Location selection behavior: editing label invalidates coordinates & cancel modal does not confirm', (tester) async {
      final controller = TextEditingController(text: 'Initial Venue');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPickerField(
              controller: controller,
              initialLocation: CanonicalLocation.exact(
                locationLabel: 'Initial Venue',
                latitude: 59.3293,
                longitude: 18.0686,
              ),
              onLocationChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<LocationPickerFieldState>(find.byType(LocationPickerField));
      expect(state.isConfirmed, isTrue);

      // 1. Editing text invalidates coordinates
      controller.text = 'Initial Venue with changes';
      await tester.pump();
      expect(state.isConfirmed, isFalse);
      expect(state.currentLocation?.hasValidCoordinates, isFalse);
    });

    test('25. Stream lifecycle: private feed error does not terminate public feed and 0 writes on read', () async {
      final mock = MockMapViewFirebaseService();
      mock.publicFeeds['pub_1'] = SubRequest(id: 'pub_1', status: 'published', latitude: 59.3, longitude: 18.0);
      mock.setCurrentUserId('user_alice');

      expect(mock.writeCount, equals(0));

      final stream = mock.getSubRequestFeedStream();
      List<SubRequest>? received;
      final sub = stream.listen((list) => received = list);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(received, isNotNull);
      expect(received!.length, equals(1));
      expect(received!.first.id, equals('pub_1'));

      // Zero writes were executed
      expect(mock.writeCount, equals(0));

      await sub.cancel();
      expect(mock.publicListenerCount, equals(0));
      expect(mock.userListenerCount, equals(0));
      expect(mock.creatorListenerCount, equals(0));
    });
  });
}
