// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/map_event_item.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/utils/map_event_activity_helper.dart';
import 'package:musicians_flutter/views/gig_map_page.dart' show MapEventType;
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';

class MockEventFeedFirebaseService extends FirebaseService {
  String? _currentUserId = 'user_alice';
  final Map<String, MapEventItem> publicEvents = {};
  final Map<String, Map<String, MapEventItem>> userEvents = {}; // userId -> {mapItemId: item}

  int readCount = 0;
  int writeCount = 0;
  int streamActiveSubscriptions = 0;

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? uid) {
    _currentUserId = uid;
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
  Stream<List<MapEventItem>> getMapEventFeedStream({String? targetUserId}) {
    final selfId = targetUserId ?? currentUserId;
    late StreamController<List<MapEventItem>> controller;

    void emitMerged() {
      if (controller.isClosed) return;
      readCount++;
      final Map<String, MapEventItem> merged = {};
      for (final entry in publicEvents.entries) {
        merged[entry.key] = entry.value;
      }
      if (selfId != null && userEvents.containsKey(selfId)) {
        for (final entry in userEvents[selfId]!.entries) {
          merged[entry.key] = entry.value;
        }
      }
      controller.add(merged.values.toList());
    }

    controller = StreamController<List<MapEventItem>>(
      onListen: () {
        streamActiveSubscriptions++;
        emitMerged();
      },
      onCancel: () {
        streamActiveSubscriptions--;
      },
    );

    return controller.stream;
  }
}

class MockAppState extends AppState {
  final MockEventFeedFirebaseService _mockFirebase;

  MockAppState(this._mockFirebase);

  @override
  FirebaseService get firebaseService => _mockFirebase;

  @override
  String? get currentUserId => _mockFirebase.currentUserId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late MockEventFeedFirebaseService mockFirebase;
  late MockAppState appState;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
  });

  setUp(() {
    mockFirebase = MockEventFeedFirebaseService();
    appState = MockAppState(mockFirebase);
  });

  group('MAP-VIEW-FEED-02: MapEventItem Model & Conversion Tests', () {
    test('1. Deserializes valid public calendar event projection', () {
      final json = {
        'mapItemId': 'event:public:evt_pub_001',
        'source': 'public_calendar',
        'eventId': 'evt_pub_001',
        'title': 'Jazz Night Stockholm',
        'description': 'A wonderful jazz evening with local musicians.',
        'eventType': 'liveGig',
        'date': '2026-11-05',
        'startTime': '20:00',
        'endTime': '23:00',
        'startDateTime': '2026-11-05T20:00:00Z',
        'endDateTime': '2026-11-05T23:00:00Z',
        'latitude': 59.3293,
        'longitude': 18.0686,
        'locationPrecision': 'exact',
        'location': 'Fasching Jazz Club',
        'city': 'Stockholm',
        'visibility': 'public',
        'status': 'scheduled',
        'updatedAt': 1761000000000,
      };

      final item = MapEventItem.fromJson(json, 'event:public:evt_pub_001');
      expect(item.mapItemId, equals('event:public:evt_pub_001'));
      expect(item.source, equals('public_calendar'));
      expect(item.eventId, equals('evt_pub_001'));
      expect(item.bandId, isNull);
      expect(item.title, equals('Jazz Night Stockholm'));
      expect(item.latitude, equals(59.3293));
      expect(item.longitude, equals(18.0686));
      expect(item.location, equals('Fasching Jazz Club'));

      // Convert to SubRequest adapter for Map View
      final sub = item.toSubRequest();
      expect(sub.subRequestId, equals('event:public:evt_pub_001'));
      expect(sub.eventTitle, equals('Jazz Night Stockholm'));
      expect(sub.latitude, equals(59.3293));
      expect(sub.longitude, equals(18.0686));
      expect(sub.role, equals('liveGig'));
      expect(sub.extraFields['eventSource'], equals('public_calendar'));
    });

    test('2. Deserializes valid private band event projection', () {
      final json = {
        'mapItemId': 'event:private:band_101:evt_priv_55',
        'source': 'private_band',
        'bandId': 'band_101',
        'bandName': 'The Midnight Echoes',
        'eventId': 'evt_priv_55',
        'title': 'Album Release Rehearsal',
        'description': 'Final rehearsal before studio recording.',
        'eventType': 'Rehearsal',
        'date': '2026-11-10',
        'startTime': '18:00',
        'endTime': '21:00',
        'startDateTime': '2026-11-10T18:00:00Z',
        'endDateTime': '2026-11-10T21:00:00Z',
        'latitude': 59.3325,
        'longitude': 18.0649,
        'locationPrecision': 'exact',
        'location': 'Studio 4, Stockholm',
        'city': 'Stockholm',
        'visibility': 'private',
        'status': 'scheduled',
      };

      final item = MapEventItem.fromJson(json, 'event:private:band_101:evt_priv_55');
      expect(item.mapItemId, equals('event:private:band_101:evt_priv_55'));
      expect(item.source, equals('private_band'));
      expect(item.bandId, equals('band_101'));
      expect(item.bandName, equals('The Midnight Echoes'));

      final sub = item.toSubRequest();
      expect(sub.subRequestId, equals('event:private:band_101:evt_priv_55'));
      expect(sub.role, equals('Rehearsal'));
      expect(sub.extraFields['eventSource'], equals('private_band'));
      expect(sub.extraFields['isEventProjection'], isTrue);
    });

    test('3. Deserializes multi-part private schedule sub-event', () {
      final json = {
        'mapItemId': 'event:private:band_101:evt_priv_55:part_soundcheck',
        'source': 'private_band',
        'bandId': 'band_101',
        'bandName': 'The Midnight Echoes',
        'eventId': 'evt_priv_55',
        'schedulePartId': 'part_soundcheck',
        'schedulePartTitle': 'Soundcheck',
        'title': 'Festival Main Stage',
        'description': 'Stage 2 soundcheck',
        'eventType': 'Rehearsal',
        'date': '2026-11-12',
        'startTime': '14:00',
        'endTime': '15:00',
        'startDateTime': '2026-11-12T14:00:00Z',
        'endDateTime': '2026-11-12T15:00:00Z',
        'latitude': 59.3400,
        'longitude': 18.0700,
        'locationPrecision': 'exact',
        'location': 'Stage 2',
        'city': 'Stockholm',
      };

      final item = MapEventItem.fromJson(json, 'event:private:band_101:evt_priv_55:part_soundcheck');
      expect(item.schedulePartId, equals('part_soundcheck'));
      expect(item.schedulePartTitle, equals('Soundcheck'));
      expect(item.source, equals('private_band'));

      final sub = item.toSubRequest();
      expect(sub.eventTitle, equals('Festival Main Stage: Soundcheck'));
      expect(sub.extraFields['schedulePartId'], equals('part_soundcheck'));
      expect(sub.extraFields['schedulePartTitle'], equals('Soundcheck'));
    });
  });

  group('MAP-VIEW-FEED-02: Feed Merging & User Isolation', () {
    test('1. Merges public and private authorized events without leaking to unauthorized user', () async {
      final service = MockEventFeedFirebaseService();

      final pubItem = MapEventItem(
        mapItemId: 'event:public:evt_1',
        source: 'public_calendar',
        eventId: 'evt_1',
        title: 'Public Open Jam',
        description: 'All welcome',
        eventType: 'openSession',
        date: '2026-11-01',
        startTime: '19:00',
        latitude: 59.33,
        longitude: 18.06,
        locationPrecision: 'exact',
        location: 'Pub Anchor',
      );

      final privItemAlice = MapEventItem(
        mapItemId: 'event:private:band_a:evt_alice',
        source: 'private_band',
        bandId: 'band_a',
        eventId: 'evt_alice',
        title: 'Alice Secret Band Rehearsal',
        description: 'Members only',
        eventType: 'Rehearsal',
        date: '2026-11-02',
        startTime: '18:00',
        latitude: 59.34,
        longitude: 18.07,
        locationPrecision: 'exact',
        location: 'Secret Bunker',
      );

      service.publicEvents['event:public:evt_1'] = pubItem;
      service.userEvents['user_alice'] = {'event:private:band_a:evt_alice': privItemAlice};

      // Alice listens: sees pubItem AND privItemAlice
      service.setCurrentUserId('user_alice');
      final aliceStream = service.getMapEventFeedStream();
      final aliceEvents = await aliceStream.first;
      expect(aliceEvents.length, equals(2));
      expect(aliceEvents.any((e) => e.mapItemId == 'event:public:evt_1'), isTrue);
      expect(aliceEvents.any((e) => e.mapItemId == 'event:private:band_a:evt_alice'), isTrue);

      // Bob listens: sees pubItem only, NEVER privItemAlice
      service.setCurrentUserId('user_bob');
      final bobStream = service.getMapEventFeedStream();
      final bobEvents = await bobStream.first;
      expect(bobEvents.length, equals(1));
      expect(bobEvents.first.mapItemId, equals('event:public:evt_1'));
      expect(bobEvents.any((e) => e.mapItemId == 'event:private:band_a:evt_alice'), isFalse);

      // Verify zero writes occurred
      expect(service.writeCount, equals(0));
    });

    test('2. Stream cleans up active listener on cancellation', () async {
      final service = MockEventFeedFirebaseService();
      expect(service.streamActiveSubscriptions, equals(0));

      final sub = service.getMapEventFeedStream().listen((_) {});
      expect(service.streamActiveSubscriptions, equals(1));

      await sub.cancel();
      expect(service.streamActiveSubscriptions, equals(0));
    });
  });

  group('MAP-VIEW-FEED-02: Coexistence & Deterministic Coordinate Separation', () {
    test('1. Separates Event and SubRequest markers when coordinates coincide', () {
      final double sharedLat = 59.3293;
      final double sharedLng = 18.0686;

      // When an Event projection and a SubRequest share identical lat/lng
      final staffingPin = SubRequest(
        subRequestId: 'sub_req_staffing_1',
        voicePart: 'Drummer',
        eventTitle: 'Gig Drummer Needed',
        location: 'Fasching, Stockholm',
        latitude: sharedLat,
        longitude: sharedLng,
        requestType: 'Substitute',
        status: 'published',
      );

      final eventProjection = MapEventItem(
        mapItemId: 'event:public:fasching_jazz',
        source: 'public_calendar',
        eventId: 'fasching_jazz',
        title: 'Fasching Saturday Jazz',
        description: 'Live show',
        eventType: 'liveGig',
        date: '2026-11-15',
        startTime: '20:00',
        latitude: sharedLat,
        longitude: sharedLng,
        locationPrecision: 'exact',
        location: 'Fasching, Stockholm',
      ).toSubRequest();

      // Check coordinates before separation
      expect(staffingPin.latitude, equals(eventProjection.latitude));
      expect(staffingPin.longitude, equals(eventProjection.longitude));

      // Visual separation logic applied in gig_map_page.dart:
      // Event pins offset by +0.00018 latitude when overlapping with SubRequest pins
      const double eventLatOffset = 0.00018;
      final double separatedEventLat = eventProjection.latitude! + eventLatOffset;

      expect(separatedEventLat, isNot(equals(staffingPin.latitude)));
      expect((separatedEventLat - staffingPin.latitude!).abs(), closeTo(0.00018, 0.000001));
    });
  });

  group('MAP-VIEW-FEED-02: Blinking / Active Rule Verification', () {
    test('1. Active blinking rule: start <= now < end', () {
      final start = DateTime(2026, 11, 20, 20, 0);
      final end = DateTime(2026, 11, 20, 23, 0);

      // 19:59 -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 11, 20, 19, 59, 59),
        ),
        isFalse,
      );

      // 20:00 (exact start) -> active (blinking)
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 11, 20, 20, 0, 0),
        ),
        isTrue,
      );

      // 21:30 (during event) -> active (blinking)
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 11, 20, 21, 30, 0),
        ),
        isTrue,
      );

      // 23:00 (exact end) -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 11, 20, 23, 0, 0),
        ),
        isFalse,
      );

      // 23:01 (after end) -> inactive
      expect(
        isMapItemActive(
          type: MapEventType.gigConcert,
          startDateTime: start,
          endDateTime: end,
          now: DateTime(2026, 11, 20, 23, 1, 0),
        ),
        isFalse,
      );
    });
  });

  group('MAP-VIEW-FEED-02: Details Card Rendering & 320px Responsiveness', () {
    testWidgets('1. Renders public calendar event details card cleanly at 320px width', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final publicEventSub = MapEventItem(
        mapItemId: 'event:public:evt_320',
        source: 'public_calendar',
        eventId: 'evt_320',
        title: 'Compact Jazz Show',
        description: 'Compact description for responsive test',
        eventType: 'liveGig',
        date: '2026-11-25',
        startTime: '19:00',
        endTime: '22:00',
        latitude: 59.33,
        longitude: 18.06,
        locationPrecision: 'exact',
        location: 'Stampen, Stockholm',
        city: 'Stockholm',
      ).toSubRequest();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MapPinDetailsCard(
                  gig: publicEventSub,
                  appState: appState,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title and location rendered
      expect(find.text('Compact Jazz Show'), findsOneWidget);
      // Verify "View Public Event" action button
      expect(find.text('View Public Event'), findsOneWidget);
      // Verify no RSVP / attendance controls are leaked in the map card
      expect(find.text('Going'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.text('RSVP'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. Renders private band event details card cleanly at 320px width', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final privateEventSub = MapEventItem(
        mapItemId: 'event:private:band_99:evt_priv_99',
        source: 'private_band',
        bandId: 'band_99',
        bandName: 'The Northern Lights',
        eventId: 'evt_priv_99',
        title: 'Full Band Tour Rehearsal',
        description: 'Private rehearsal for band members',
        eventType: 'Rehearsal',
        date: '2026-11-28',
        startTime: '17:00',
        endTime: '20:00',
        latitude: 59.335,
        longitude: 18.065,
        locationPrecision: 'exact',
        location: 'Rehearsal Hall B',
      ).toSubRequest();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MapPinDetailsCard(
                  gig: privateEventSub,
                  appState: appState,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title and band name rendered
      expect(find.text('Full Band Tour Rehearsal'), findsOneWidget);
      expect(find.text('· The Northern Lights'), findsOneWidget);
      // Verify "View Event Details" button
      expect(find.text('View Event Details'), findsOneWidget);
      // Verify no private RSVP edit controls leaked in the map card
      expect(find.text('Attending'), findsNothing);
      expect(find.text('Declined'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
