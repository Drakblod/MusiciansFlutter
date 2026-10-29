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
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/services/location_service.dart';
import 'package:musicians_flutter/utils/map_view_unified_feed_helper.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/widgets/location_picker_field.dart';

class _MockLocationOverrideFirebaseService extends FirebaseService {
  final List<SubRequest> requests;
  _MockLocationOverrideFirebaseService(this.requests);

  @override
  String? get currentUserId => 'user_account_b';

  @override
  Stream<List<SubRequest>> getSubRequestFeedStream({String? targetUserId}) =>
      Stream.value(requests);

  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => requests;

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => requests;

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};
}

class _MockLocationOverrideAppState extends AppState {
  final _MockLocationOverrideFirebaseService mockService;
  final UserProfile profile;
  _MockLocationOverrideAppState(this.mockService, this.profile);

  @override
  FirebaseService get firebaseService => mockService;

  @override
  UserProfile? get currentUserProfile => profile;

  @override
  String? get currentUserId => 'user_account_b';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Firebase.initializeApp();
    } catch (_) {}
  });
  const double ljusdalLat = 61.8286;
  const double ljusdalLng = 16.0958;
  const double sundsvallLat = 62.3908;
  const double sundsvallLng = 17.3069;

  group('MAP-VIEW-LOCATION-01: SubRequest Location Precedence & Override Regression', () {
    test('1-3. Offline resolver knows both Ljusdal and Sundsvall and finds closest city from coordinates', () {
      final sundsvall = LocationService.resolveKnownCity('Sundsvall, Sweden');
      expect(sundsvall, isNotNull);
      expect(sundsvall!.locationLabel, 'Sundsvall');
      expect(sundsvall.latitude, sundsvallLat);
      expect(sundsvall.longitude, sundsvallLng);

      final ljusdal = LocationService.resolveKnownCity('Ljusdal, Sweden');
      expect(ljusdal, isNotNull);
      expect(ljusdal!.locationLabel, 'Ljusdal');
      expect(ljusdal.latitude, ljusdalLat);
      expect(ljusdal.longitude, ljusdalLng);

      final closestToSundsvall = LocationService.findClosestKnownCity(62.3910, 17.3075);
      expect(closestToSundsvall, isNotNull);
      expect(closestToSundsvall!.locationLabel, 'Sundsvall');
    });

    testWidgets('3-4. LocationPickerField updates controller text when known city centroid is confirmed over old prefilled text', (tester) async {
      final controller = TextEditingController(text: 'Sundsvall');
      CanonicalLocation? confirmedLoc;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPickerField(
              controller: controller,
              onLocationChanged: (loc) => confirmedLoc = loc,
            ),
          ),
        ),
      );
      await tester.pump();

      final centroidTap = find.textContaining('Use approximate Sundsvall centroid');
      expect(centroidTap, findsOneWidget);
      await tester.tap(centroidTap);
      await tester.pump();

      expect(confirmedLoc, isNotNull);
      expect(confirmedLoc!.hasValidCoordinates, isTrue);
      expect(confirmedLoc!.locationLabel, 'Sundsvall');
      expect(confirmedLoc!.latitude, sundsvallLat);
      expect(confirmedLoc!.longitude, sundsvallLng);
      expect(controller.text, 'Sundsvall');

      // Editing text after confirmation invalidates stale coordinates
      controller.text = 'Sundsvall Arena';
      await tester.pump();
      expect(confirmedLoc!.hasValidCoordinates, isFalse);
      expect(confirmedLoc!.status, LocationResolutionStatus.unresolved);
    });

    test('4-8 & 11. Publication payload, canonical record, public feed, creator feed, recipient feed and hard-refresh deserialization preserve Sundsvall', () {
      final request = SubRequest(
        id: 'sub_deku_sundsvall_1',
        subRequestId: 'sub_deku_sundsvall_1',
        slotId: 'draft_initial_0',
        bandId: 'Deku_Tree_Bongo',
        bandName: 'Deku Tree Bongo',
        eventId: 'freelance_event',
        role: 'Substitute',
        requestType: 'Substitute',
        voicePart: 'Electric Guitar',
        location: 'Sundsvall, Sweden',
        city: 'Sundsvall',
        latitude: sundsvallLat,
        longitude: sundsvallLng,
        locationPrecision: LocationPrecision.exact,
        locationStatus: LocationResolutionStatus.resolved,
        requestGroupId: 'req_group_Deku_Tree_Bongo_event_1793275504906',
        date: DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        status: 'published',
      );

      final payloadJson = request.toJson();
      expect(payloadJson['Location'], 'Sundsvall, Sweden');
      expect(payloadJson['Latitude'], sundsvallLat);
      expect(payloadJson['Longitude'], sundsvallLng);

      // Simulate hard refresh deserialization from RTDB
      final deserialized = SubRequest.fromJson(payloadJson, 'sub_deku_sundsvall_1');
      expect(deserialized.location, 'Sundsvall, Sweden');
      expect(deserialized.city, 'Sundsvall');
      expect(deserialized.latitude, sundsvallLat);
      expect(deserialized.longitude, sundsvallLng);
      expect(deserialized.hasValidCoordinates, isTrue);
      expect(deserialized.canonicalLocation.locationLabel, 'Sundsvall, Sweden');
    });

    test('9-10. Map View marker and grouping use Sundsvall coordinates and NEVER collapse into an older Ljusdal request even if requestGroupId collided', () {
      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 2)).toIso8601String();

      final olderLjusdalReq = SubRequest(
        id: 'sub_Deku_Tree_Bongo_1000',
        subRequestId: 'sub_Deku_Tree_Bongo_1000',
        bandId: 'Deku_Tree_Bongo',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
        location: 'Ljusdal, Sweden',
        city: 'Ljusdal',
        latitude: ljusdalLat,
        longitude: ljusdalLng,
        requestGroupId: 'group_Deku_Tree_Bongo_event',
        date: futureDate,
        status: 'published',
      );

      final newerSundsvallReq = SubRequest(
        id: 'sub_Deku_Tree_Bongo_2000',
        subRequestId: 'sub_Deku_Tree_Bongo_2000',
        bandId: 'Deku_Tree_Bongo',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
        location: 'Sundsvall, Sweden',
        city: 'Sundsvall',
        latitude: sundsvallLat,
        longitude: sundsvallLng,
        requestGroupId: 'group_Deku_Tree_Bongo_event',
        date: futureDate,
        status: 'published',
      );

      final markers = processUnifiedMapItems(
        staffingAndPromoItems: [olderLjusdalReq, newerSundsvallReq],
        eventItems: const [],
        now: now,
      );

      // Must produce two distinct markers (one in Ljusdal, one in Sundsvall) and never pull Sundsvall into Ljusdal
      expect(markers.length, 2);

      final sundsvallMarker = markers.firstWhere((m) => m.primaryGig.id == 'sub_Deku_Tree_Bongo_2000');
      expect(sundsvallMarker.originalPosition.latitude, sundsvallLat);
      expect(sundsvallMarker.originalPosition.longitude, sundsvallLng);
      expect(sundsvallMarker.primaryGig.location, 'Sundsvall, Sweden');

      final ljusdalMarker = markers.firstWhere((m) => m.primaryGig.id == 'sub_Deku_Tree_Bongo_1000');
      expect(ljusdalMarker.originalPosition.latitude, ljusdalLat);
      expect(ljusdalMarker.originalPosition.longitude, ljusdalLng);
    });

    testWidgets('9b. FindGigsScreen parses and displays Sundsvall, Sweden and never merges into Ljusdal', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      final sundsvallReq = SubRequest(
        id: 'sub_Deku_Tree_Bongo_2000',
        subRequestId: 'sub_Deku_Tree_Bongo_2000',
        bandId: 'Deku_Tree_Bongo',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
        location: 'Sundsvall, Sweden',
        city: 'Sundsvall',
        latitude: sundsvallLat,
        longitude: sundsvallLng,
        requestGroupId: 'group_Deku_Tree_Bongo_event',
        date: dateStr,
        startTime: '19:00',
        endTime: '22:00',
        status: 'published',
      );

      final mockService = _MockLocationOverrideFirebaseService([sundsvallReq]);
      final appState = _MockLocationOverrideAppState(
        mockService,
        UserProfile(
          userId: 'user_account_b',
          displayName: 'Account B',
          location: 'Ljusdal, Sweden',
          instruments: ['Electric Guitar'],
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(
            home: FindGigsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Deku Tree Bongo'), findsOneWidget);
      expect(find.textContaining('Sundsvall, Sweden'), findsWidgets);
      expect(find.text('Ljusdal, Sweden'), findsNothing);
    });

    test('13. Linked Event location is inherited ONLY when SubRequest coordinates are absent', () {
      final confirmedSundsvallReq = SubRequest(
        id: 'sub_confirmed',
        location: 'Sundsvall, Sweden',
        latitude: sundsvallLat,
        longitude: sundsvallLng,
      );

      // Attempting to inherit Ljusdal event coordinates must NOT override confirmed Sundsvall coordinates
      final afterInheritConfirmed = confirmedSundsvallReq.withInheritedEventLocation(
        eventLatitude: ljusdalLat,
        eventLongitude: ljusdalLng,
        eventLocation: 'Ljusdal, Sweden',
      );
      expect(afterInheritConfirmed.latitude, sundsvallLat);
      expect(afterInheritConfirmed.longitude, sundsvallLng);
      expect(afterInheritConfirmed.location, 'Sundsvall, Sweden');

      // When SubRequest has no coordinates, it inherits from linked Event
      final unconfirmedReq = SubRequest(
        id: 'sub_unconfirmed',
        location: '',
        latitude: null,
        longitude: null,
      );
      final afterInheritUnconfirmed = unconfirmedReq.withInheritedEventLocation(
        eventLatitude: ljusdalLat,
        eventLongitude: ljusdalLng,
        eventLocation: 'Ljusdal, Sweden',
      );
      expect(afterInheritUnconfirmed.latitude, ljusdalLat);
      expect(afterInheritUnconfirmed.longitude, ljusdalLng);
      expect(afterInheritUnconfirmed.location, 'Ljusdal, Sweden');
    });

    test('14. Missing request and Event coordinates remain unresolved and produce no fallback marker on Map View', () {
      final now = DateTime.now();
      final unresolvedReq = SubRequest(
        id: 'sub_unresolved',
        bandId: 'Deku_Tree_Bongo',
        bandName: 'Deku Tree Bongo',
        location: 'Ljusdal, Sweden',
        latitude: null,
        longitude: null,
        date: now.add(const Duration(days: 2)).toIso8601String(),
        status: 'published',
      ).withInheritedEventLocation(
        eventLatitude: null,
        eventLongitude: null,
        eventLocation: 'Ljusdal, Sweden',
      );

      expect(unresolvedReq.hasValidCoordinates, isFalse);

      final markers = processUnifiedMapItems(
        staffingAndPromoItems: [unresolvedReq],
        eventItems: const [],
        now: now,
      );
      expect(markers, isEmpty);
    });
  });
}
