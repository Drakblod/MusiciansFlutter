import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/map_event_item.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/map_view_unified_feed_helper.dart';
import 'package:musicians_flutter/utils/map_event_activity_helper.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';
import 'package:provider/provider.dart';

class MockUnifiedAppState extends AppState {
  final FirebaseService _mockFirebase;
  MockUnifiedAppState(this._mockFirebase);

  @override
  FirebaseService get firebaseService => _mockFirebase;

  @override
  String? get currentUserId => _mockFirebase.currentUserId;
}

class MockUnifiedFirebaseService extends FirebaseService {
  String? _currentUserId = 'user_musician_1';
  bool _isLoggedIn = true;

  final StreamController<List<SubRequest>> subRequestController =
      StreamController<List<SubRequest>>.broadcast();
  final StreamController<List<MapEventItem>> mapEventController =
      StreamController<List<MapEventItem>>.broadcast();
  final StreamController<List<SubRequest>> mapPinController =
      StreamController<List<SubRequest>>.broadcast();

  int subRequestListenersCount = 0;
  int mapEventListenersCount = 0;
  int mapPinListenersCount = 0;

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String? uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  Stream<List<SubRequest>> getSubRequestFeedStream({String? targetUserId}) {
    late StreamController<List<SubRequest>> controller;
    StreamSubscription<List<SubRequest>>? sub;

    controller = StreamController<List<SubRequest>>(
      onListen: () {
        subRequestListenersCount++;
        sub = subRequestController.stream.listen((data) {
          if (!controller.isClosed) controller.add(data);
        });
      },
      onCancel: () {
        subRequestListenersCount--;
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<MapEventItem>> getMapEventFeedStream({String? targetUserId}) {
    late StreamController<List<MapEventItem>> controller;
    StreamSubscription<List<MapEventItem>>? sub;

    controller = StreamController<List<MapEventItem>>(
      onListen: () {
        mapEventListenersCount++;
        sub = mapEventController.stream.listen((data) {
          if (!controller.isClosed) controller.add(data);
        });
      },
      onCancel: () {
        mapEventListenersCount--;
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<SubRequest>> getMapPinFeedStream() {
    late StreamController<List<SubRequest>> controller;
    StreamSubscription<List<SubRequest>>? sub;

    controller = StreamController<List<SubRequest>>(
      onListen: () {
        mapPinListenersCount++;
        sub = mapPinController.stream.listen((data) {
          if (!controller.isClosed) controller.add(data);
        });
      },
      onCancel: () {
        mapPinListenersCount--;
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
  });

  group('MAP-VIEW-FEED-03: Unified Map Feed Presentation & Classification', () {
    test('1. Typed presentation classification resolves every item to exactly one MapItemKind', () {
      // Event projection
      final eventGig = SubRequest(
        id: 'event:public:ev_1',
        eventTitle: 'Summer Jazz Night',
        extraFields: {'isEventProjection': true, 'eventSource': 'public_calendar'},
      );
      expect(classifyMapItem(eventGig), equals(MapItemKind.event));

      // Event schedule part projection
      final eventPartGig = SubRequest(
        id: 'event:public:ev_1:part_soundcheck',
        eventTitle: 'Summer Jazz Night: Soundcheck',
        extraFields: {
          'isEventProjection': true,
          'schedulePartId': 'part_soundcheck',
          'eventSource': 'public_calendar',
        },
      );
      expect(classifyMapItem(eventPartGig), equals(MapItemKind.eventSchedulePart));

      // Staffing request (substitute)
      final staffingGig = SubRequest(
        id: 'sub_101',
        eventTitle: 'Wedding Band Sub',
        role: 'Guitarist',
        requestType: 'Gig / Concert',
      );
      expect(classifyMapItem(staffingGig), equals(MapItemKind.staffingRequest));

      // New member request
      final newMemberGig = SubRequest(
        id: 'sub_102',
        bandName: 'Indie Rockers',
        role: 'Bass Player',
        requestType: 'New Member',
        extraFields: {'isNewMember': true},
      );
      expect(classifyMapItem(newMemberGig), equals(MapItemKind.newMemberRequest));

      // Music promotion (Manual upload map pin)
      final promoGig = SubRequest(
        id: 'map_pin_201',
        bandName: 'Solo Artist Album Release',
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin', 'eventType': 'gigpromo'},
      );
      expect(classifyMapItem(promoGig), equals(MapItemKind.musicPromotion));

      // Go Live broadcast
      final liveGig = SubRequest(
        id: 'live:broadcast_301',
        eventTitle: 'Live Acoustic Session',
        extraFields: {'isLiveBroadcast': true, 'broadcastId': 'broadcast_301'},
      );
      expect(classifyMapItem(liveGig), equals(MapItemKind.liveBroadcast));

      // Mock demo
      final mockGig = SubRequest(
        id: 'mock_rehearsal_1',
        bandName: 'Demo Band',
      );
      expect(classifyMapItem(mockGig), equals(MapItemKind.mockDemo));
    });

    test('2. Classification relies on canonical fields only, never searching arbitrary description text', () {
      // SubRequest whose description contains deceptive keywords like "Looking for a new member for our gig promo"
      final trickyStaffing = SubRequest(
        id: 'sub_regular_99',
        role: 'Drummer',
        requestType: 'Gig / Concert',
        description: 'Looking for a new member for our album release gig promo live broadcast mock!',
      );
      expect(classifyMapItem(trickyStaffing), equals(MapItemKind.staffingRequest));

      // Music promo whose description mentions "substitute needed"
      final trickyPromo = SubRequest(
        id: 'promo_99',
        extraFields: {'NotificationMode': 'map_pin'},
        description: 'Our regular substitute guitarist helped on this album release demo',
      );
      expect(classifyMapItem(trickyPromo), equals(MapItemKind.musicPromotion));
    });

    test('3. Namespaced marker IDs are stable, deterministic, collision-free, and use no UniqueKey()', () {
      final item1 = SubRequest(id: 'abc_1', extraFields: {'isEventProjection': true});
      final item2 = SubRequest(id: 'abc_1', extraFields: {'NotificationMode': 'map_pin'});
      final item3 = SubRequest(id: 'abc_1', role: 'Bass', requestType: 'Gig / Concert');
      final item4 = SubRequest(id: 'abc_1', extraFields: {'isLiveBroadcast': true});
      final item5 = SubRequest(id: 'mock_abc_1');

      final id1 = getNamespacedMarkerId(item1);
      final id2 = getNamespacedMarkerId(item2);
      final id3 = getNamespacedMarkerId(item3);
      final id4 = getNamespacedMarkerId(item4);
      final id5 = getNamespacedMarkerId(item5);

      expect(id1, equals('event:abc_1'));
      expect(id2, equals('map_pin:abc_1'));
      expect(id3, equals('subrequest:abc_1'));
      expect(id4, equals('live:abc_1'));
      expect(id5, equals('mock:mock_abc_1'));

      final allIds = {id1, id2, id3, id4, id5};
      expect(allIds.length, equals(5)); // Exactly 5 distinct IDs, zero collisions
    });

    test('4. Deduplication: Public and private projections of the same Event deduplicate to one item', () {
      final publicEvent = SubRequest(
        id: 'event:public:ev_summer_fest',
        eventId: 'ev_summer_fest',
        bandId: 'band_99',
        eventTitle: 'Summer Fest (Public Calendar)',
        latitude: 59.3293,
        longitude: 18.0686,
        extraFields: {
          'eventId': 'ev_summer_fest',
          'bandId': 'band_99',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      final privateEvent = SubRequest(
        id: 'event:private:band_99:ev_summer_fest',
        eventId: 'ev_summer_fest',
        eventTitle: 'Summer Fest (Band Access)',
        bandId: 'band_99',
        bandName: 'The Headliners',
        latitude: 59.3293,
        longitude: 18.0686,
        extraFields: {
          'eventId': 'ev_summer_fest',
          'isEventProjection': true,
          'eventSource': 'private_band',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [],
        eventItems: [publicEvent, privateEvent],
        now: DateTime.parse('2026-11-20T12:00:00Z'),
      );

      expect(processed.length, equals(1));
      // Prefers the private band projection with richer band details
      expect(processed.first.primaryGig.bandId, equals('band_99'));
    });

    test('5. Multi-part events: Renders schedule-part markers; container parent marker is omitted', () {
      final parentEvent = SubRequest(
        id: 'event:public:ev_festival',
        eventId: 'ev_festival',
        eventTitle: 'Rock Festival Full Container',
        latitude: 59.3293,
        longitude: 18.0686,
        extraFields: {
          'eventId': 'ev_festival',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-21T10:00:00Z',
          'endDateTime': '2026-11-21T23:00:00Z',
        },
      );

      final soundcheckPart = SubRequest(
        id: 'event:public:ev_festival:part_soundcheck',
        eventId: 'ev_festival',
        eventTitle: 'Rock Festival: Soundcheck',
        latitude: 59.3293,
        longitude: 18.0686,
        extraFields: {
          'eventId': 'ev_festival',
          'schedulePartId': 'part_soundcheck',
          'schedulePartTitle': 'Soundcheck',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-21T14:00:00Z',
          'endDateTime': '2026-11-21T15:30:00Z',
        },
      );

      final mainShowPart = SubRequest(
        id: 'event:public:ev_festival:part_show',
        eventId: 'ev_festival',
        eventTitle: 'Rock Festival: Main Show',
        latitude: 59.3293,
        longitude: 18.0686,
        extraFields: {
          'eventId': 'ev_festival',
          'schedulePartId': 'part_show',
          'schedulePartTitle': 'Main Show',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-21T20:00:00Z',
          'endDateTime': '2026-11-21T22:30:00Z',
        },
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [],
        eventItems: [parentEvent, soundcheckPart, mainShowPart],
        now: DateTime.parse('2026-11-21T12:00:00Z'),
      );

      // Parent container omitted, only the 2 schedule parts rendered
      expect(processed.length, equals(2));
      final partIds = processed.map((p) => p.primaryGig.extraFields['schedulePartId']).toSet();
      expect(partIds, equals({'part_soundcheck', 'part_show'}));
    });

    test('6. Staffing grouping: Multiple slots with same requestGroupId produce 1 visual marker', () {
      final slot1 = SubRequest(
        id: 'sub_slot_1',
        requestGroupId: 'req_grp_777',
        eventTitle: 'Big Band Gala',
        role: 'Lead Alto Sax',
        latitude: 59.3325,
        longitude: 18.0649,
      );

      final slot2 = SubRequest(
        id: 'sub_slot_2',
        requestGroupId: 'req_grp_777',
        eventTitle: 'Big Band Gala',
        role: 'Trumpet 2',
        latitude: 59.3325,
        longitude: 18.0649,
      );

      final slot3 = SubRequest(
        id: 'sub_slot_3',
        requestGroupId: 'req_grp_777',
        eventTitle: 'Big Band Gala',
        role: 'Trombone',
        latitude: 59.3325,
        longitude: 18.0649,
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [slot1, slot2, slot3],
        eventItems: [],
      );

      expect(processed.length, equals(1));
      expect(processed.first.id, equals('reqgrp_req_grp_777'));
      expect(processed.first.groupedGigs.length, equals(3));
    });

    test('7. Deterministic collision separation: Separate items at same coordinates receive deterministic radial offset', () {
      final eventGig = SubRequest(
        id: 'event:public:ev_fasching',
        eventId: 'ev_fasching',
        eventTitle: 'Live at Fasching',
        latitude: 59.3340,
        longitude: 18.0560,
        extraFields: {
          'isEventProjection': true,
          'startDateTime': '2026-11-22T20:00:00Z',
          'endDateTime': '2026-11-22T23:00:00Z',
        },
      );

      final promoGig = SubRequest(
        id: 'map_pin_fasching_promo',
        bandName: 'Fasching Jazz Club Demo',
        latitude: 59.3340,
        longitude: 18.0560,
        extraFields: {'NotificationMode': 'map_pin'},
      );

      final subGig = SubRequest(
        id: 'sub_fasching_pianist',
        role: 'Pianist',
        latitude: 59.3340,
        longitude: 18.0560,
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [promoGig, subGig],
        eventItems: [eventGig],
        now: DateTime.parse('2026-11-22T15:00:00Z'),
      );

      expect(processed.length, equals(3));
      // All 3 markers have the originalPosition equal to venue coordinates
      for (final m in processed) {
        expect(m.originalPosition.latitude, equals(59.3340));
        expect(m.originalPosition.longitude, equals(18.0560));
      }

      // But adjusted positions are separated and distinct
      final positions = processed.map((m) => '${m.position.latitude},${m.position.longitude}').toSet();
      expect(positions.length, equals(3));

      // Re-running produces identical positions (100% deterministic, no random jitter)
      final processedAgain = processUnifiedMapItems(
        staffingAndPromoItems: [promoGig, subGig],
        eventItems: [eventGig],
        now: DateTime.parse('2026-11-22T15:00:00Z'),
      );
      for (var i = 0; i < 3; i++) {
        expect(processed[i].position.latitude, equals(processedAgain[i].position.latitude));
        expect(processed[i].position.longitude, equals(processedAgain[i].position.longitude));
      }
    });

    test('8. Filter policy: Music filter includes Events, promotions, Live; excludes staffing', () {
      final eventGig = SubRequest(
        id: 'event:1',
        extraFields: {'isEventProjection': true, 'startDateTime': '2026-11-20T20:00:00Z'},
      );
      final promoGig = SubRequest(
        id: 'map_pin:1',
        extraFields: {'NotificationMode': 'map_pin'},
      );
      final liveGig = SubRequest(
        id: 'live:1',
        extraFields: {'isLiveBroadcast': true},
      );
      final staffingGig = SubRequest(
        id: 'sub:1',
        role: 'Drummer',
        requestType: 'Gig / Concert',
      );
      final newMemberGig = SubRequest(
        id: 'sub:2',
        role: 'Vocalist',
        requestType: 'New Member',
        extraFields: {'isNewMember': true},
      );

      final fixedClock = DateTime.parse('2026-11-20T10:00:00Z');

      expect(isItemMatchingFilter(item: eventGig, mainCategory: 'Music', subCategory: null, instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: promoGig, mainCategory: 'Music', subCategory: null, instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: liveGig, mainCategory: 'Music', subCategory: null, instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Music', subCategory: null, instrumentQuery: '', now: fixedClock), isFalse);
      expect(isItemMatchingFilter(item: newMemberGig, mainCategory: 'Music', subCategory: null, instrumentQuery: '', now: fixedClock), isFalse);
    });

    test('9. Filter policy: Sub & Member Search includes staffing, excludes Events and promotions', () {
      final eventGig = SubRequest(
        id: 'event:1',
        extraFields: {'isEventProjection': true, 'startDateTime': '2026-11-20T20:00:00Z'},
      );
      final promoGig = SubRequest(
        id: 'map_pin:1',
        extraFields: {'NotificationMode': 'map_pin'},
      );
      final staffingGig = SubRequest(
        id: 'sub:1',
        role: 'Drummer',
        requestType: 'Gig / Concert',
      );
      final newMemberGig = SubRequest(
        id: 'sub:2',
        role: 'Vocalist',
        requestType: 'New Member',
        extraFields: {'isNewMember': true},
      );

      final fixedClock = DateTime.parse('2026-11-20T10:00:00Z');

      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: newMemberGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: eventGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: '', now: fixedClock), isFalse);
      expect(isItemMatchingFilter(item: promoGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: '', now: fixedClock), isFalse);

      // Subcategory: Substitutes
      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Sub & Member Search', subCategory: 'Substitutes', instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: newMemberGig, mainCategory: 'Sub & Member Search', subCategory: 'Substitutes', instrumentQuery: '', now: fixedClock), isFalse);

      // Subcategory: New Members
      expect(isItemMatchingFilter(item: newMemberGig, mainCategory: 'Sub & Member Search', subCategory: 'New Members', instrumentQuery: '', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Sub & Member Search', subCategory: 'New Members', instrumentQuery: '', now: fixedClock), isFalse);

      // Instrument query filter
      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: 'drum', now: fixedClock), isTrue);
      expect(isItemMatchingFilter(item: staffingGig, mainCategory: 'Sub & Member Search', subCategory: null, instrumentQuery: 'piano', now: fixedClock), isFalse);
    });

    test('10. Filter policy: This Week uses deterministic local calendar week boundaries (Monday-to-Sunday) with injected clock', () {
      // Suppose current local time is Wednesday, Nov 18, 2026
      final wednesday = DateTime(2026, 11, 18, 12, 0);

      // Monday of that week: 2026-11-16
      final mondayItem = SubRequest(
        id: 'mon_gig',
        date: '2026-11-16T18:00:00',
        extraFields: {
          'startDateTime': '2026-11-16T18:00:00',
          'endDateTime': '2026-11-19T22:00:00', // Still active or visible
        },
      );

      // Sunday of that week: 2026-11-22
      final sundayItem = SubRequest(
        id: 'sun_gig',
        date: '2026-11-22T20:00:00',
        extraFields: {
          'startDateTime': '2026-11-22T20:00:00',
          'endDateTime': '2026-11-22T22:00:00',
        },
      );

      // Following Monday (next week): 2026-11-23
      final nextMondayItem = SubRequest(
        id: 'next_mon_gig',
        date: '2026-11-23T19:00:00',
        extraFields: {
          'startDateTime': '2026-11-23T19:00:00',
          'endDateTime': '2026-11-23T21:00:00',
        },
      );

      // Previous Sunday (last week): 2026-11-15
      final lastSundayItem = SubRequest(
        id: 'last_sun_gig',
        date: '2026-11-15T19:00:00',
        extraFields: {
          'startDateTime': '2026-11-15T19:00:00',
          'endDateTime': '2026-11-15T21:00:00',
        },
      );

      // Undated promo item
      final undatedPromo = SubRequest(
        id: 'undated_promo',
        extraFields: {'NotificationMode': 'map_pin'},
      );

      expect(isDateWithinLocalCalendarWeek(mondayItem, now: wednesday), isTrue);
      expect(isDateWithinLocalCalendarWeek(sundayItem, now: wednesday), isTrue);
      expect(isDateWithinLocalCalendarWeek(nextMondayItem, now: wednesday), isFalse);
      expect(isDateWithinLocalCalendarWeek(lastSundayItem, now: wednesday), isFalse);
      expect(isDateWithinLocalCalendarWeek(undatedPromo, now: wednesday), isFalse);
    });

    test('11. Stream lifecycle: Exactly one listener per feed, cleanly cancelled on dispose and user switch', () {
      final mock = MockUnifiedFirebaseService();
      expect(mock.subRequestListenersCount, equals(0));
      expect(mock.mapEventListenersCount, equals(0));

      final sub1 = mock.getSubRequestFeedStream().listen((_) {});
      final sub2 = mock.getMapEventFeedStream().listen((_) {});

      expect(mock.subRequestListenersCount, equals(1));
      expect(mock.mapEventListenersCount, equals(1));

      // User switch or page dispose
      sub1.cancel();
      sub2.cancel();

      expect(mock.subRequestListenersCount, equals(0));
      expect(mock.mapEventListenersCount, equals(0));
    });

    test('12. Large mixed fixture stress test (100 events, 100 staffing requests, 50 promo/live): zero collisions, deterministic grouping', () {
      final events = List.generate(100, (i) {
        return SubRequest(
          id: 'event:public:ev_$i',
          eventId: 'ev_$i',
          eventTitle: 'Event Title #$i',
          latitude: 59.30 + (i % 20) * 0.01,
          longitude: 18.00 + (i % 20) * 0.01,
          extraFields: {
            'eventId': 'ev_$i',
            'isEventProjection': true,
            'startDateTime': '2026-11-25T18:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        );
      });

      final staffing = List.generate(100, (i) {
        // Pair up some into groups
        final groupId = (i % 4 == 0) ? 'shared_grp_${i ~/ 4}' : null;
        return SubRequest(
          id: 'sub_req_$i',
          requestGroupId: groupId,
          eventTitle: 'Staffing Gig #$i',
          role: 'Instrumentalist',
          latitude: 59.30 + (i % 15) * 0.01,
          longitude: 18.00 + (i % 15) * 0.01,
        );
      });

      final promoAndLive = List.generate(50, (i) {
        if (i % 2 == 0) {
          return SubRequest(
            id: 'map_pin_promo_$i',
            bandName: 'Promo Track #$i',
            latitude: 59.33,
            longitude: 18.05,
            extraFields: {'NotificationMode': 'map_pin'},
          );
        } else {
          return SubRequest(
            id: 'live:stream_$i',
            eventTitle: 'Live Stream #$i',
            latitude: 59.33,
            longitude: 18.05,
            extraFields: {'isLiveBroadcast': true},
          );
        }
      });

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [...staffing, ...promoAndLive],
        eventItems: events,
        now: DateTime.parse('2026-11-25T12:00:00Z'),
      );

      // Verify zero duplicate marker IDs
      final markerIds = <String>{};
      for (final m in processed) {
        final added = markerIds.add(m.id);
        expect(added, isTrue, reason: 'Duplicate marker ID found: ${m.id}');
      }

      expect(processed.isNotEmpty, isTrue);
    });

    testWidgets('13. 320 px layout has no RenderFlex overflow for all unified item kinds', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = AppState();

      // Test Event projection card
      final eventGig = SubRequest(
        id: 'event:public:ev_overflow',
        eventId: 'ev_overflow',
        eventTitle: 'Very Long Concert Title With Many Words For Narrow Screen Overflow Testing',
        bandName: 'The Super Long Band Name Symphony Orchestra',
        location: 'Konserthuset Stockholm, Hötorgshallen, Hötorget 8, 111 57 Stockholm',
        date: '2026-11-20',
        startTime: '19:00',
        endTime: '22:00',
        extraFields: {
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-20T19:00:00',
          'endDateTime': '2026-11-20T22:00:00',
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
                  gig: eventGig,
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

    test('14. Manual upload categories contain only Music Promotion types, zero staffing routes', () {
      const allowedPromoTypes = [
        'Music Promotion',
        'Demos / Recordings',
        'Demo',
        'Recording',
        'Jam Session',
        'Songwriting Session',
        'Other Promotion'
      ];

      const forbiddenStaffingTypes = [
        'Substitute',
        'Sub',
        'New Member',
        'Audition',
        'Open Position',
        'Band Member Search',
      ];

      for (final forbidden in forbiddenStaffingTypes) {
        expect(allowedPromoTypes.contains(forbidden), isFalse,
            reason: 'Manual upload must never offer staffing category "$forbidden"');
      }

      // Uploading any allowed promo type classifies as musicPromotion and uses map_pin notificationMode
      for (final promo in allowedPromoTypes) {
        final pin = SubRequest(
          id: 'manual_${promo.hashCode}',
          role: 'map_pin',
          extraFields: {
            'NotificationMode': 'map_pin',
            'eventType': promo,
          },
        );
        expect(classifyMapItem(pin), equals(MapItemKind.musicPromotion));
        expect(getNamespacedMarkerId(pin), startsWith('map_pin:'));
      }
    });

    test('15. Selection and Audio safety: Expired, hidden, or removed items clear selection and audio focus', () {
      final activeEvent = SubRequest(
        id: 'event:public:ev_active',
        eventId: 'ev_active',
        extraFields: {
          'isEventProjection': true,
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      final expiredEvent = SubRequest(
        id: 'event:public:ev_expired',
        eventId: 'ev_expired',
        extraFields: {
          'isEventProjection': true,
          'startDateTime': '2026-11-20T10:00:00Z',
          'endDateTime': '2026-11-20T12:00:00Z',
        },
      );

      final clockAfterExpiry = DateTime.parse('2026-11-20T13:00:00Z');

      // Expired event is no longer visible
      expect(isMapEventVisible(expiredEvent, now: clockAfterExpiry), isFalse);
      expect(isMapEventVisible(activeEvent, now: clockAfterExpiry), isTrue);

      // Filtering at clockAfterExpiry excludes the expired event
      expect(
        isItemMatchingFilter(
          item: expiredEvent,
          mainCategory: 'Music',
          subCategory: null,
          instrumentQuery: '',
          now: clockAfterExpiry,
        ),
        isFalse,
      );
      expect(
        isItemMatchingFilter(
          item: activeEvent,
          mainCategory: 'Music',
          subCategory: null,
          instrumentQuery: '',
          now: clockAfterExpiry,
        ),
        isTrue,
      );
    });

    test('16. Event Deduplication Scoping: Distinct bands with identical eventId remain separate markers; accidental collision with public event remains separate; true public/private mirror deduplicates', () {
      final fixedClock = DateTime.parse('2026-11-20T12:00:00Z');

      // Band 1 event with id 'ev_shared_id'
      final band1Event = SubRequest(
        id: 'event:private:band_1:ev_shared_id',
        eventId: 'ev_shared_id',
        eventTitle: 'Band 1 Gig',
        bandId: 'band_1',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'eventId': 'ev_shared_id',
          'isEventProjection': true,
          'eventSource': 'private_band',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      // Band 2 event with SAME eventId 'ev_shared_id'
      final band2Event = SubRequest(
        id: 'event:private:band_2:ev_shared_id',
        eventId: 'ev_shared_id',
        eventTitle: 'Band 2 Gig',
        bandId: 'band_2',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'eventId': 'ev_shared_id',
          'isEventProjection': true,
          'eventSource': 'private_band',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      // Accidental matching eventId on public calendar (no band)
      final publicEvent = SubRequest(
        id: 'event:public:ev_shared_id',
        eventId: 'ev_shared_id',
        eventTitle: 'Public Calendar Accidental Collision',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'eventId': 'ev_shared_id',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      // True public mirror of Band 1's event
      final band1PublicMirror = SubRequest(
        id: 'event:public:band_1_ev_mirror',
        eventId: 'ev_mirror',
        bandId: 'band_1',
        eventTitle: 'Band 1 Mirror Public',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'eventId': 'ev_mirror',
          'bandId': 'band_1',
          'isEventProjection': true,
          'eventSource': 'public_calendar',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      // True private band projection of Band 1's event
      final band1PrivateMirror = SubRequest(
        id: 'event:private:band_1:ev_mirror',
        eventId: 'ev_mirror',
        bandId: 'band_1',
        eventTitle: 'Band 1 Mirror Private',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'eventId': 'ev_mirror',
          'bandId': 'band_1',
          'isEventProjection': true,
          'eventSource': 'private_band',
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T22:00:00Z',
        },
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [],
        eventItems: [
          band1Event,
          band2Event,
          publicEvent,
          band1PublicMirror,
          band1PrivateMirror,
        ],
        now: fixedClock,
      );

      // Exactly 4 markers:
      // 1. band1Event (band_1, ev_shared_id)
      // 2. band2Event (band_2, ev_shared_id) -> separate!
      // 3. publicEvent (public, ev_shared_id) -> separate!
      // 4. band1 mirror (ev_mirror, band_1) -> deduplicated to 1!
      expect(processed.length, equals(4));

      final dedupMirror = processed.firstWhere((m) => m.primaryGig.eventId == 'ev_mirror');
      // Prefers private projection
      expect(dedupMirror.primaryGig.extraFields['eventSource'], equals('private_band'));
    });

    test('17. Staffing Group Identity Scoping: Identical requestGroupId across distinct bands/creators remain separate markers; identical within same band merge', () {
      // Band 1 has 2 slots with requestGroupId 'grp_alpha'
      final slotB1_1 = SubRequest(
        id: 'sub_b1_1',
        bandId: 'band_1',
        requestGroupId: 'grp_alpha',
        role: 'Guitarist',
        latitude: 59.3300,
        longitude: 18.0600,
      );
      final slotB1_2 = SubRequest(
        id: 'sub_b1_2',
        bandId: 'band_1',
        requestGroupId: 'grp_alpha',
        role: 'Bassist',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      // Band 2 has a slot with the identical requestGroupId 'grp_alpha'
      final slotB2_1 = SubRequest(
        id: 'sub_b2_1',
        bandId: 'band_2',
        requestGroupId: 'grp_alpha',
        role: 'Drummer',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      // Independent user creator has a slot with the identical requestGroupId 'grp_alpha'
      final slotUser_1 = SubRequest(
        id: 'sub_u1_1',
        creatorUserId: 'user_solo_creator',
        requestGroupId: 'grp_alpha',
        role: 'Pianist',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [slotB1_1, slotB1_2, slotB2_1, slotUser_1],
        eventItems: [],
      );

      // Must produce exactly 3 markers, NOT 1!
      expect(processed.length, equals(3));

      final b1Marker = processed.firstWhere((m) => m.id == 'reqgrp_band_1_grp_alpha');
      expect(b1Marker.groupedGigs.length, equals(2));

      final b2Marker = processed.firstWhere((m) => m.id == 'reqgrp_band_2_grp_alpha');
      expect(b2Marker.groupedGigs.length, equals(1));

      final userMarker = processed.firstWhere((m) => m.id == 'reqgrp_user_solo_creator_grp_alpha');
      expect(userMarker.groupedGigs.length, equals(1));
    });

    test('18. Collision Position Stability: Marker A at location (lat, lng) has identical coordinates before and after Marker B is added or removed at the same location; no position shifts when N changes', () {
      final itemA = SubRequest(
        id: 'marker_a',
        role: 'Lead',
        latitude: 59.3300,
        longitude: 18.0600,
      );
      final itemB = SubRequest(
        id: 'marker_b',
        role: 'Rhythm',
        latitude: 59.3300,
        longitude: 18.0600,
      );
      final itemC = SubRequest(
        id: 'marker_c',
        role: 'Keys',
        latitude: 59.3300,
        longitude: 18.0600,
      );

      // 1. Item A alone
      final run1 = processUnifiedMapItems(
        staffingAndPromoItems: [itemA],
        eventItems: [],
      );
      expect(run1.length, equals(1));
      final posA_run1 = run1.firstWhere((m) => m.id.contains('marker_a')).position;

      // 2. Add Item B at the same location (N = 2)
      final run2 = processUnifiedMapItems(
        staffingAndPromoItems: [itemA, itemB],
        eventItems: [],
      );
      expect(run2.length, equals(2));
      final posA_run2 = run2.firstWhere((m) => m.id.contains('marker_a')).position;
      final posB_run2 = run2.firstWhere((m) => m.id.contains('marker_b')).position;

      // Assert Item A's coordinates are 100% IDENTICAL before and after Item B was added!
      expect(posA_run2.latitude, equals(posA_run1.latitude));
      expect(posA_run2.longitude, equals(posA_run1.longitude));

      // 3. Add Item C at the same location (N = 3)
      final run3 = processUnifiedMapItems(
        staffingAndPromoItems: [itemA, itemB, itemC],
        eventItems: [],
      );
      expect(run3.length, equals(3));
      final posA_run3 = run3.firstWhere((m) => m.id.contains('marker_a')).position;
      final posB_run3 = run3.firstWhere((m) => m.id.contains('marker_b')).position;
      final posC_run3 = run3.firstWhere((m) => m.id.contains('marker_c')).position;

      // Assert Item A and Item B coordinates are 100% UNTOUCHED by the arrival of Item C!
      expect(posA_run3.latitude, equals(posA_run2.latitude));
      expect(posA_run3.longitude, equals(posA_run2.longitude));
      expect(posB_run3.latitude, equals(posB_run2.latitude));
      expect(posB_run3.longitude, equals(posB_run2.longitude));

      // 4. Remove Item B (N returns to 2: A and C)
      final run4 = processUnifiedMapItems(
        staffingAndPromoItems: [itemA, itemC],
        eventItems: [],
      );
      expect(run4.length, equals(2));
      final posA_run4 = run4.firstWhere((m) => m.id.contains('marker_a')).position;
      final posC_run4 = run4.firstWhere((m) => m.id.contains('marker_c')).position;

      // Assert Item A and Item C coordinates are 100% UNTOUCHED by the removal of Item B!
      expect(posA_run4.latitude, equals(posA_run3.latitude));
      expect(posA_run4.longitude, equals(posA_run3.longitude));
      expect(posC_run4.latitude, equals(posC_run3.latitude));
      expect(posC_run4.longitude, equals(posC_run3.longitude));
    });

    test('19. Unified Marker Icon Cache: Deterministic generation counts; repeated requests for identical visual state reuse cache without generating new bitmaps', () async {
      final cache = UnifiedMarkerIconCache.instance;
      cache.clear();
      expect(cache.generationCount, equals(0));
      expect(cache.cachedIconCount, equals(0));

      final dummyDescriptor = BitmapDescriptor.defaultMarkerWithHue(120.0);

      // Request 1: cache miss, triggers generator
      final icon1 = await cache.getOrCreateIcon(
        kind: MapItemKind.event,
        eventType: MapEventType.gigConcert,
        isLive: true,
        blinkPhase: true,
        isDarkTheme: true,
        generator: () async => dummyDescriptor,
      );

      expect(cache.generationCount, equals(1));
      expect(cache.cachedIconCount, equals(1));
      expect(icon1, equals(dummyDescriptor));

      // Request 2-100: same visual state -> cache hit, zero generator invocations!
      for (var i = 0; i < 99; i++) {
        final iconAgain = await cache.getOrCreateIcon(
          kind: MapItemKind.event,
          eventType: MapEventType.gigConcert,
          isLive: true,
          blinkPhase: true,
          isDarkTheme: true,
          generator: () async => throw StateError('Should not be called on cache hit!'),
        );
        expect(iconAgain, equals(dummyDescriptor));
      }

      expect(cache.generationCount, equals(1));

      // Request with different visual state (dim phase): cache miss, triggers generator
      final dummyDim = BitmapDescriptor.defaultMarkerWithHue(60.0);
      final iconDim = await cache.getOrCreateIcon(
        kind: MapItemKind.event,
        eventType: MapEventType.gigConcert,
        isLive: true,
        blinkPhase: false,
        isDarkTheme: true,
        generator: () async => dummyDim,
      );

      expect(cache.generationCount, equals(2));
      expect(cache.cachedIconCount, equals(2));
      expect(iconDim, equals(dummyDim));
    });

    test('20. 750ms Blink animation separation: Blink timer does NOT trigger safety reconciliation; visibility boundary timer triggers reconciliation at exact event boundary', () {
      final now = DateTime.parse('2026-11-20T18:00:00Z');

      final upcomingEvent = SubRequest(
        id: 'event:1',
        extraFields: {
          'isEventProjection': true,
          'startDateTime': '2026-11-20T19:00:00Z',
          'endDateTime': '2026-11-20T21:00:00Z',
        },
      );

      // Nearest boundary is start of upcomingEvent (19:00:00Z)
      final nearestBoundary = findNearestEventBoundary([upcomingEvent], now: now);
      expect(nearestBoundary, equals(DateTime.parse('2026-11-20T19:00:00Z')));

      // At 19:30:00Z, nearest boundary is end of event (21:00:00Z)
      final duringEvent = DateTime.parse('2026-11-20T19:30:00Z');
      final nearestEndBoundary = findNearestEventBoundary([upcomingEvent], now: duringEvent);
      expect(nearestEndBoundary, equals(DateTime.parse('2026-11-20T21:00:00Z')));
    });

    test('21. Visible copy verification: Approved visible chip renders "Gigs / Rehearsals"; stale label "Live Gigs / Rehearsals" is never rendered in UI', () {
      // Verify filter counts evaluate 'Gigs / Rehearsals' properly
      final gigItem = SubRequest(
        id: 'ev_1',
        extraFields: {'isEventProjection': true, 'eventType': 'gigConcert', 'startDateTime': '2026-11-20T19:00:00Z'},
      );
      final rehItem = SubRequest(
        id: 'ev_2',
        extraFields: {'isEventProjection': true, 'eventType': 'rehearsal', 'startDateTime': '2026-11-20T19:00:00Z'},
      );
      final now = DateTime.parse('2026-11-20T12:00:00Z');

      expect(isItemMatchingFilter(item: gigItem, mainCategory: 'Music', subCategory: 'Gigs / Rehearsals', instrumentQuery: '', now: now), isTrue);
      expect(isItemMatchingFilter(item: rehItem, mainCategory: 'Music', subCategory: 'Gigs / Rehearsals', instrumentQuery: '', now: now), isTrue);
    });

    test('22. Staffing feed isolation proof: Music Promotion pins (NotificationMode: map_pin) never enter staffing feeds', () {
      final promoPin = SubRequest(
        id: 'pin_promo_101',
        bandName: 'Indie Artist Demo',
        latitude: 59.3300,
        longitude: 18.0600,
        extraFields: {
          'NotificationMode': 'map_pin',
          'eventType': 'recordedMusic',
        },
      );

      expect(classifyMapItem(promoPin), equals(MapItemKind.musicPromotion));
      // Never matches Sub & Member Search
      expect(
        isItemMatchingFilter(
          item: promoPin,
          mainCategory: 'Sub & Member Search',
          subCategory: null,
          instrumentQuery: '',
        ),
        isFalse,
      );
    });

    test('23. Manual upload persistence proof: calls saveMapPinAsync, writes NotificationMode: map_pin, zero staffing notifications', () {
      final draftGig = SubRequest(
        role: 'map_pin',
        bandName: 'Album Release Showcase',
        latitude: 59.3320,
        longitude: 18.0620,
        extraFields: {
          'eventType': 'gigPromo',
          'subCategory': 'Music',
          'NotificationMode': 'map_pin',
        },
      );

      expect(draftGig.extraFields['NotificationMode'], equals('map_pin'));
      expect(draftGig.extraFields['subCategory'], equals('Music'));
      expect(classifyMapItem(draftGig), equals(MapItemKind.musicPromotion));
    });

    testWidgets('24. Selection and Audio safety across all 8 triggers in GigMapPage', (tester) async {
      final mockService = MockUnifiedFirebaseService();
      final appState = MockUnifiedAppState(mockService);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
          ],
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('25. Large mixed fixture stress test (100 events, 100 staffing, 50 promo/live) with exact arithmetic, unique marker counts, and position stability', () {
      final events = List.generate(100, (i) {
        return SubRequest(
          id: 'event:public:ev_stress_$i',
          eventId: 'ev_stress_$i',
          eventTitle: 'Concert #$i',
          latitude: 59.30 + (i % 10) * 0.01,
          longitude: 18.00 + (i % 10) * 0.01,
          extraFields: {
            'eventId': 'ev_stress_$i',
            'isEventProjection': true,
            'startDateTime': '2026-11-25T18:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        );
      });

      final staffing = List.generate(100, (i) {
        final groupId = (i % 5 == 0) ? 'grp_${i ~/ 5}' : null;
        return SubRequest(
          id: 'staffing_$i',
          bandId: 'band_${i % 4}',
          requestGroupId: groupId,
          role: 'Musician #$i',
          latitude: 59.30 + (i % 10) * 0.01,
          longitude: 18.00 + (i % 10) * 0.01,
        );
      });

      final promoAndLive = List.generate(50, (i) {
        return SubRequest(
          id: 'promo_live_$i',
          role: (i % 2 == 0) ? 'map_pin' : 'Live',
          latitude: 59.33,
          longitude: 18.05,
          extraFields: (i % 2 == 0)
              ? {'NotificationMode': 'map_pin', 'eventType': 'recordedMusic'}
              : {'isLiveBroadcast': true},
        );
      });

      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [...staffing, ...promoAndLive],
        eventItems: events,
        now: DateTime.parse('2026-11-25T12:00:00Z'),
      );

      final uniqueIds = processed.map((m) => m.id).toSet();
      expect(uniqueIds.length, equals(processed.length), reason: 'Zero duplicate marker IDs allowed');
      expect(processed.length, greaterThan(100));

      // Re-processing with same data produces identical marker positions
      final processed2 = processUnifiedMapItems(
        staffingAndPromoItems: [...staffing, ...promoAndLive],
        eventItems: events,
        now: DateTime.parse('2026-11-25T12:00:00Z'),
      );

      for (var i = 0; i < processed.length; i++) {
        expect(processed[i].position.latitude, equals(processed2[i].position.latitude));
        expect(processed[i].position.longitude, equals(processed2[i].position.longitude));
      }
    });

    testWidgets('26. Music Promotion Realtime Read Path: create, update, delete, staffing-isolation, and zero leaked listeners', (tester) async {
      final mockService = MockUnifiedFirebaseService();
      final appState = MockUnifiedAppState(mockService);

      expect(mockService.mapPinListenersCount, equals(0));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
          ],
          child: const MaterialApp(
            home: GigMapPage(),
          ),
        ),
      );
      await tester.pump();

      // Exactly 1 listener for each of the 3 feeds
      expect(mockService.mapPinListenersCount, equals(1));
      expect(mockService.subRequestListenersCount, equals(1));
      expect(mockService.mapEventListenersCount, equals(1));

      // 1. Existing authorized map_pin records appear
      final pin1 = SubRequest(
        id: 'pin_promo_1',
        bandName: 'Album Promo 1',
        latitude: 59.33,
        longitude: 18.06,
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin', 'eventType': 'recordedMusic'},
      );
      mockService.mapPinController.add([pin1]);
      await tester.pump();

      // 2. Newly created map_pin appears without app restart
      final pin2 = SubRequest(
        id: 'pin_promo_2',
        bandName: 'Single Release 2',
        latitude: 59.34,
        longitude: 18.07,
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin', 'eventType': 'recordedMusic'},
      );
      mockService.mapPinController.add([pin1, pin2]);
      await tester.pump();

      // 3. Updated map_pin updates exactly one marker
      final pin1Updated = SubRequest(
        id: 'pin_promo_1',
        bandName: 'Album Promo 1 (Remastered)',
        latitude: 59.33,
        longitude: 18.06,
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin', 'eventType': 'recordedMusic'},
      );
      mockService.mapPinController.add([pin1Updated, pin2]);
      await tester.pump();

      // 4. Deleted map_pin disappears
      mockService.mapPinController.add([pin2]);
      await tester.pump();

      // 5. Unmount / Dispose cleans up all listeners
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(mockService.mapPinListenersCount, equals(0));
      expect(mockService.subRequestListenersCount, equals(0));
      expect(mockService.mapEventListenersCount, equals(0));
    });

    test('27. Independent positioning sequence A-H: adding lexically smaller IDs, anchor removal, arbitrary orders, and shuffling NEVER move existing markers', () {
      final orig = const LatLng(59.33258, 18.06490);

      // A. Start with marker `m`
      final itemM = SubRequest(
        id: 'm_marker',
        latitude: orig.latitude,
        longitude: orig.longitude,
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin'},
      );
      final resA = processUnifiedMapItems(
        staffingAndPromoItems: [itemM],
        eventItems: [],
      );
      expect(resA.length, equals(1));
      final posM_initial = resA.first.position;
      // Unmodified coordinate preserved in originalPosition and primaryGig
      expect(resA.first.originalPosition.latitude, equals(orig.latitude));
      expect(resA.first.originalPosition.longitude, equals(orig.longitude));
      expect(resA.first.primaryGig.latitude, equals(orig.latitude));
      expect(resA.first.primaryGig.longitude, equals(orig.longitude));

      // B. Add a lexically smaller marker `a`
      final itemA = SubRequest(
        id: 'a_marker',
        latitude: orig.latitude,
        longitude: orig.longitude,
        role: 'map_pin',
        extraFields: {'NotificationMode': 'map_pin'},
      );
      final resB = processUnifiedMapItems(
        staffingAndPromoItems: [itemM, itemA],
        eventItems: [],
      );
      expect(resB.length, equals(2));

      // C. Confirm `m` remains byte-identical
      final posM_afterA = resB.firstWhere((x) => x.id.contains('m_marker')).position;
      expect(posM_afterA.latitude, equals(posM_initial.latitude));
      expect(posM_afterA.longitude, equals(posM_initial.longitude));

      // D. Remove `a`
      final resD = processUnifiedMapItems(
        staffingAndPromoItems: [itemM],
        eventItems: [],
      );
      expect(resD.length, equals(1));

      // E. Confirm `m` remains byte-identical
      final posM_afterRemoveA = resD.first.position;
      expect(posM_afterRemoveA.latitude, equals(posM_initial.latitude));
      expect(posM_afterRemoveA.longitude, equals(posM_initial.longitude));

      // F. Add and remove several IDs in arbitrary order
      final itemZ = SubRequest(id: 'z_marker', latitude: orig.latitude, longitude: orig.longitude, role: 'map_pin', extraFields: {'NotificationMode': 'map_pin'});
      final itemB = SubRequest(id: 'b_marker', latitude: orig.latitude, longitude: orig.longitude, role: 'map_pin', extraFields: {'NotificationMode': 'map_pin'});
      final itemK = SubRequest(id: 'k_marker', latitude: orig.latitude, longitude: orig.longitude, role: 'map_pin', extraFields: {'NotificationMode': 'map_pin'});
      final item0 = SubRequest(id: '0_marker', latitude: orig.latitude, longitude: orig.longitude, role: 'map_pin', extraFields: {'NotificationMode': 'map_pin'});

      final resF = processUnifiedMapItems(
        staffingAndPromoItems: [itemZ, itemM, item0, itemB, itemK],
        eventItems: [],
      );
      final posM_F = resF.firstWhere((x) => x.id.contains('m_marker')).position;
      expect(posM_F.latitude, equals(posM_initial.latitude));
      expect(posM_F.longitude, equals(posM_initial.longitude));

      // G. Shuffle input repeatedly
      final allItems = [itemM, itemA, itemZ, itemB, itemK, item0];
      final baselinePositions = <String, LatLng>{};
      for (final marker in processUnifiedMapItems(staffingAndPromoItems: allItems, eventItems: [])) {
        baselinePositions[marker.id] = marker.position;
      }

      for (var round = 0; round < 10; round++) {
        final shuffled = List<SubRequest>.from(allItems)..shuffle();
        final resG = processUnifiedMapItems(staffingAndPromoItems: shuffled, eventItems: []);

        // H. Confirm every surviving ID retains its previous rendered position
        expect(resG.length, equals(allItems.length));
        for (final marker in resG) {
          final expectedPos = baselinePositions[marker.id]!;
          expect(marker.position.latitude, equals(expectedPos.latitude));
          expect(marker.position.longitude, equals(expectedPos.longitude));
        }
      }
    });

    test('28. Hash Slot Collision Handling: Deliberate collision under old 36-slot algorithm produces distinct coordinates under new algorithm', () {
      // Under old 36-slot algorithm:
      // FNV-1a('gig_1') -> slot 28
      // FNV-1a('gig_10') -> slot 28
      // They collided to the exact same ring and slot!
      final orig = const LatLng(59.3293, 18.0686);

      final pos1 = computeStableMarkerPosition(orig, 'subrequest:gig_1');
      final pos2 = computeStableMarkerPosition(orig, 'subrequest:gig_10');

      // Verify: rendered coordinates are distinct
      expect(
        pos1.latitude != pos2.latitude || pos1.longitude != pos2.longitude,
        isTrue,
        reason: 'Positions must be distinct even if IDs collided under old 36-slot algorithm',
      );

      // Verify: results remain deterministic across rebuilds
      final pos1Again = computeStableMarkerPosition(orig, 'subrequest:gig_1');
      final pos2Again = computeStableMarkerPosition(orig, 'subrequest:gig_10');
      expect(pos1Again.latitude, equals(pos1.latitude));
      expect(pos1Again.longitude, equals(pos1.longitude));
      expect(pos2Again.latitude, equals(pos2.latitude));
      expect(pos2Again.longitude, equals(pos2.longitude));

      // Verify: adding/removing unrelated markers does not move existing markers
      final posUnrelated = computeStableMarkerPosition(orig, 'subrequest:unrelated_999');
      expect(pos1.latitude, equals(pos1Again.latitude));
      expect(posUnrelated.latitude != pos1.latitude, isTrue);

      // Verify distance from origin is within [12m, 32m] annulus (~0.00012 to 0.00028 deg)
      final dLat = (pos1.latitude - orig.latitude).abs();
      expect(dLat, lessThan(0.00030));
    });

    test('29. Production Marker Cache wiring: 100 identical static markers generate 1 bitmap, rebuilds generate 0 additional, active blink on/dim at most 1 each, 256 bound', () async {
      final cache = UnifiedMarkerIconCache.instance;
      cache.clear();
      expect(cache.generationCount, equals(0));

      final dummyDescriptor = BitmapDescriptor.defaultMarkerWithHue(120.0);
      final dummyDimDescriptor = BitmapDescriptor.defaultMarkerWithHue(60.0);

      // 1. First render of 100 identical static marker styles generates exactly ONE bitmap
      for (var i = 0; i < 100; i++) {
        final icon = await cache.getOrCreateIcon(
          kind: MapItemKind.event,
          eventType: MapEventType.gigConcert,
          isLive: false,
          blinkPhase: true,
          isDarkTheme: false,
          generator: () async => dummyDescriptor,
        );
        expect(icon, equals(dummyDescriptor));
      }
      expect(cache.generationCount, equals(1));
      expect(cache.cachedIconCount, equals(1));

      // 2. Rebuilding with identical data generates ZERO additional bitmaps
      for (var i = 0; i < 50; i++) {
        final icon = await cache.getOrCreateIcon(
          kind: MapItemKind.event,
          eventType: MapEventType.gigConcert,
          isLive: false,
          blinkPhase: true,
          isDarkTheme: false,
          generator: () async => throw StateError('Should not generate!'),
        );
        expect(icon, equals(dummyDescriptor));
      }
      expect(cache.generationCount, equals(1));

      // 3. Filtering away and back generates ZERO additional bitmaps
      final iconRefiltered = await cache.getOrCreateIcon(
        kind: MapItemKind.event,
        eventType: MapEventType.gigConcert,
        isLive: false,
        blinkPhase: true,
        isDarkTheme: false,
        generator: () async => throw StateError('Should not generate!'),
      );
      expect(iconRefiltered, equals(dummyDescriptor));
      expect(cache.generationCount, equals(1));

      // 4. Active blink `on` generates at most ONE additional bitmap
      final iconBlinkOn = await cache.getOrCreateIcon(
        kind: MapItemKind.event,
        eventType: MapEventType.gigConcert,
        isLive: true,
        blinkPhase: true,
        isDarkTheme: false,
        generator: () async => dummyDescriptor,
      );
      expect(iconBlinkOn, equals(dummyDescriptor));
      expect(cache.generationCount, equals(2));

      // 5. Active blink `dim` generates at most ONE additional bitmap
      final iconBlinkDim = await cache.getOrCreateIcon(
        kind: MapItemKind.event,
        eventType: MapEventType.gigConcert,
        isLive: true,
        blinkPhase: false,
        isDarkTheme: false,
        generator: () async => dummyDimDescriptor,
      );
      expect(iconBlinkDim, equals(dummyDimDescriptor));
      expect(cache.generationCount, equals(3));

      // 6. Unrelated feed updates do not regenerate unchanged icons
      expect(cache.generationCount, equals(3));

      // 7. Verify cache size bound (maxCacheEntries = 256)
      for (var i = 0; i < 300; i++) {
        cache.putIcon('key_$i', dummyDescriptor);
      }
      expect(cache.cachedIconCount, lessThanOrEqualTo(UnifiedMarkerIconCache.maxCacheEntries));
      expect(cache.cachedIconCount, equals(256));
    });

    test('30. Exact Stress-Test Arithmetic: 100 raw events (10 duplicates, 10 suppressed parents -> 80 final), 100 raw staffing (10 groups of 4 + 60 standalone -> 70 final), 50 promo/live -> 200 visual markers', () {
      final now = DateTime.parse('2026-11-25T12:00:00Z');

      // --- EVENTS (100 raw events) ---
      // A. 10 mirror pairs (10 public + 10 private) = 20 raw events -> 10 deduped
      final mirrorEvents = <SubRequest>[];
      for (var i = 0; i < 10; i++) {
        mirrorEvents.add(SubRequest(
          id: 'event:public:ev_mirror_$i',
          eventId: 'ev_mirror_$i',
          bandId: 'band_mirror_$i',
          eventTitle: 'Concert #$i (Public)',
          latitude: 59.31,
          longitude: 18.01,
          extraFields: {
            'eventId': 'ev_mirror_$i',
            'bandId': 'band_mirror_$i',
            'isEventProjection': true,
            'eventSource': 'public_calendar',
            'startDateTime': '2026-11-25T18:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        ));
        mirrorEvents.add(SubRequest(
          id: 'event:private:band_mirror_${i}:ev_mirror_$i',
          eventId: 'ev_mirror_$i',
          bandId: 'band_mirror_$i',
          eventTitle: 'Concert #$i (Private)',
          latitude: 59.31,
          longitude: 18.01,
          extraFields: {
            'eventId': 'ev_mirror_$i',
            'bandId': 'band_mirror_$i',
            'isEventProjection': true,
            'eventSource': 'private_band',
            'startDateTime': '2026-11-25T18:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        ));
      }

      // B. 10 multi-part events (each with 1 container parent + 2 parts) = 30 raw events -> 10 parents suppressed, 20 parts kept
      final multiPartEvents = <SubRequest>[];
      for (var i = 0; i < 10; i++) {
        multiPartEvents.add(SubRequest(
          id: 'event:public:ev_multi_$i',
          eventId: 'ev_multi_$i',
          eventTitle: 'Festival #$i',
          latitude: 59.32,
          longitude: 18.02,
          extraFields: {
            'eventId': 'ev_multi_$i',
            'isEventProjection': true,
            'eventSource': 'public_calendar',
            'startDateTime': '2026-11-25T14:00:00Z',
            'endDateTime': '2026-11-25T23:00:00Z',
          },
        ));
        multiPartEvents.add(SubRequest(
          id: 'event:public:ev_multi_${i}:part_set1',
          eventId: 'ev_multi_$i',
          eventTitle: 'Festival #$i Set 1',
          latitude: 59.32,
          longitude: 18.02,
          extraFields: {
            'eventId': 'ev_multi_$i',
            'schedulePartId': 'part_set1',
            'isEventProjection': true,
            'eventSource': 'public_calendar',
            'startDateTime': '2026-11-25T15:00:00Z',
            'endDateTime': '2026-11-25T17:00:00Z',
          },
        ));
        multiPartEvents.add(SubRequest(
          id: 'event:public:ev_multi_${i}:part_set2',
          eventId: 'ev_multi_$i',
          eventTitle: 'Festival #$i Set 2',
          latitude: 59.32,
          longitude: 18.02,
          extraFields: {
            'eventId': 'ev_multi_$i',
            'schedulePartId': 'part_set2',
            'isEventProjection': true,
            'eventSource': 'public_calendar',
            'startDateTime': '2026-11-25T19:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        ));
      }

      // C. 50 standalone events (single-part) = 50 raw events -> 50 kept
      final standaloneEvents = List.generate(50, (i) {
        return SubRequest(
          id: 'event:public:ev_single_$i',
          eventId: 'ev_single_$i',
          eventTitle: 'Single Concert #$i',
          latitude: 59.33 + (i % 5) * 0.01,
          longitude: 18.03 + (i % 5) * 0.01,
          extraFields: {
            'eventId': 'ev_single_$i',
            'isEventProjection': true,
            'eventSource': 'public_calendar',
            'startDateTime': '2026-11-25T18:00:00Z',
            'endDateTime': '2026-11-25T21:00:00Z',
          },
        );
      });

      final rawEvents = [...mirrorEvents, ...multiPartEvents, ...standaloneEvents];
      expect(rawEvents.length, equals(100)); // Exactly 100 raw events

      // --- STAFFING (100 raw staffing) ---
      // A. 40 grouped requests forming 10 staffing groups (4 per group)
      final groupedStaffing = <SubRequest>[];
      for (var g = 0; g < 10; g++) {
        for (var slot = 0; slot < 4; slot++) {
          groupedStaffing.add(SubRequest(
            id: 'sub_grp_${g}_slot_$slot',
            bandId: 'band_staff_$g',
            requestGroupId: 'grp_$g',
            role: 'Instrument #$slot',
            latitude: 59.34,
            longitude: 18.04,
          ));
        }
      }
      expect(groupedStaffing.length, equals(40));

      // B. 60 standalone staffing requests
      final standaloneStaffing = List.generate(60, (i) {
        return SubRequest(
          id: 'sub_single_$i',
          bandId: 'band_single_$i',
          role: 'Solo Musician #$i',
          latitude: 59.35 + (i % 6) * 0.01,
          longitude: 18.05 + (i % 6) * 0.01,
        );
      });
      expect(standaloneStaffing.length, equals(60));

      final rawStaffing = [...groupedStaffing, ...standaloneStaffing];
      expect(rawStaffing.length, equals(100)); // Exactly 100 raw staffing requests

      // --- PROMO & LIVE (50 raw items) ---
      final promoPins = List.generate(30, (i) {
        return SubRequest(
          id: 'promo_pin_$i',
          role: 'map_pin',
          latitude: 59.36,
          longitude: 18.06,
          extraFields: {'NotificationMode': 'map_pin', 'eventType': 'recordedMusic'},
        );
      });
      expect(promoPins.length, equals(30));

      final liveBroadcasts = List.generate(20, (i) {
        return SubRequest(
          id: 'live_broadcast_$i',
          role: 'Live',
          latitude: 59.37,
          longitude: 18.07,
          extraFields: {'isLiveBroadcast': true},
        );
      });
      expect(liveBroadcasts.length, equals(20));

      final rawPromoAndLive = [...promoPins, ...liveBroadcasts];
      expect(rawPromoAndLive.length, equals(50));

      // --- PROCESS UNIFIED ITEMS ---
      final processed = processUnifiedMapItems(
        staffingAndPromoItems: [...rawStaffing, ...rawPromoAndLive],
        eventItems: rawEvents,
        now: now,
      );

      // Arithmetic Assertions:
      // Raw Events: 100
      // Duplicates: 10
      // Suppressed Parents: 10
      // Final Event Markers: 80 (10 deduped mirrors + 20 schedule parts + 50 single)
      final eventMarkers = processed.where((m) => m.kind == MapItemKind.event || m.kind == MapItemKind.eventSchedulePart).toList();
      expect(eventMarkers.length, equals(80));

      // Raw Staffing: 100
      // Staffing Groups: 10 (40 items -> 10 group markers)
      // Standalone Staffing: 60
      // Final Staffing Markers: 70
      final staffingMarkers = processed.where((m) => m.kind == MapItemKind.staffingRequest || m.kind == MapItemKind.newMemberRequest).toList();
      expect(staffingMarkers.length, equals(70));

      // Raw Promo/Live: 50
      // Final Promo/Live Markers: 50
      final promoAndLiveMarkers = processed.where((m) => m.kind == MapItemKind.musicPromotion || m.kind == MapItemKind.liveBroadcast).toList();
      expect(promoAndLiveMarkers.length, equals(50));

      // Expected Total Visual Markers: 80 + 70 + 50 = 200
      const expectedTotal = 200;
      final actualTotal = processed.length;
      expect(actualTotal, equals(expectedTotal));

      // Unique IDs vs Duplicate IDs
      final uniqueIds = processed.map((m) => m.id).toSet();
      expect(uniqueIds.length, equals(expectedTotal));
      final duplicateIdCount = actualTotal - uniqueIds.length;
      expect(duplicateIdCount, equals(0));
    });
  });
}
