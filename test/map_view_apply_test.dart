import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/widgets/map_pin_details_card.dart';

class MockMapApplyFirebaseService extends FirebaseService {
  String _currentUserId = 'musician_user_b';
  final Set<String> backendAppliedIds = {};
  final Map<String, Set<String>> bandAdmins = {};
  final List<String> submittedSubRequestIds = [];
  final List<List<String>> cardLookupCalls = [];

  Completer<void>? pendingApplyCompleter;
  Map<String, Completer<Set<String>>> pendingCardLookupByKey = {};
  Object? nextApplyError;

  @override
  String? get currentUserId => _currentUserId;

  void setCurrentUserId(String uid) {
    _currentUserId = uid;
  }

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> initializePushNotifications() async {}

  @override
  Future<bool> isBandLeaderOrAdminAsync(String bandId, String userId) async {
    return bandAdmins[bandId]?.contains(userId) ?? false;
  }

  @override
  Future<Set<String>> resolveAppliedSubRequestIdsForCardAsync({
    required String userId,
    required Iterable<String> subRequestIds,
  }) async {
    final ids = subRequestIds.toList();
    cardLookupCalls.add(ids);
    final key = ids.join('|');
    if (pendingCardLookupByKey.containsKey(key)) {
      return pendingCardLookupByKey[key]!.future;
    }
return ids.where((id) => backendAppliedIds.contains(id)).toSet();
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async {
    return Set<String>.from(backendAppliedIds);
  }

  @override
  Future<void> addResponseToSubRequestAsync(String subRequestId, String userId) async {
    submittedSubRequestIds.add(subRequestId);
    if (pendingApplyCompleter != null) {
      await pendingApplyCompleter!.future;
    }
    if (nextApplyError != null) {
      final err = nextApplyError!;
      nextApplyError = null;
      throw err;
    }
    backendAppliedIds.add(subRequestId);
  }
}

class MockMapApplyAppState extends AppState {
  final MockMapApplyFirebaseService mockService;
  String _userId;

  MockMapApplyAppState(this.mockService, {String userId = 'musician_user_b'})
      : _userId = userId;

  void setUserId(String uid) {
    _userId = uid;
    mockService.setCurrentUserId(uid);
    notifyListeners();
  }

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => _userId;

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: _userId,
        displayName: 'Musician $_userId',
        email: '$_userId@example.com',
      );
}

SubRequest _buildStaffingRequest({
  String id = 'sub_deku_1',
  String bandId = 'Deku_Tree_Bongo',
  String bandName = 'Deku Tree Bongo',
  String creatorUserId = 'creator_user_a',
  String requestType = 'Substitute',
  String role = 'Substitute',
  String voicePart = 'Electric Guitar',
  String status = 'published',
  String? assignedUserId,
  bool isPaid = false,
  int? payAmount,
  String? date,
  String startTime = '19:00',
  String endTime = '22:00',
  String? notificationMode,
  Map<String, dynamic> extraFields = const {},
}) {
  final futureDate = date ??
      DateTime.now().add(const Duration(days: 3)).toIso8601String().split('T').first;
  final mergedExtra = <String, dynamic>{
    ...extraFields,
    if (notificationMode != null) 'NotificationMode': notificationMode,
  };
  return SubRequest(
    id: id,
    subRequestId: id,
    bandId: bandId,
    bandName: bandName,
    creatorUserId: creatorUserId,
    userId: creatorUserId,
    requestType: requestType,
    role: role,
    voicePart: voicePart,
    status: status,
    assignedUserId: assignedUserId,
    isPaid: isPaid,
    payAmount: payAmount,
    date: futureDate,
    startTime: startTime,
    endTime: endTime,
    location: 'Sundsvall, Sweden',
    city: 'Sundsvall',
    latitude: 62.3908,
    longitude: 17.3069,
    extraFields: mergedExtra,
  );
}

Widget _wrapCard({
  required SubRequest gig,
  List<SubRequest>? groupedGigs,
  required MockMapApplyAppState appState,
  void Function(BuildContext, SubRequest)? onManageRequest,
  void Function(SubRequest)? onEditPin,
  void Function(SubRequest)? onDeletePin,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: MapPinDetailsCard(
              gig: gig,
              groupedGigs: groupedGigs,
              appState: appState,
              onManageRequest: onManageRequest,
              onEditPin: onEditPin,
              onDeletePin: onDeletePin,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Firebase.initializeApp();
    } catch (_) {}
  });

  group('MAP-VIEW-APPLY-01 — Button Visibility & Role-Specific Labels', () {
    testWidgets('1. Eligible musician sees "Apply for this gig" on an open Substitute request card', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_open_1',
        requestType: 'Substitute',
        voicePart: 'Electric Guitar',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply for this gig'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_manage_request_button')), findsNothing);
    });

    testWidgets('2. Eligible musician sees "Apply to join" on an open New Member request card', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_new_member_1',
        requestType: 'New Member',
        role: 'New Member',
        voicePart: 'Bass Guitar',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply to join'), findsOneWidget);
    });

    testWidgets('3. Eligible musician sees "Apply for paid gig" on an open paid staffing request card', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_paid_1',
        requestType: 'Substitute',
        voicePart: 'Drums',
        isPaid: true,
        payAmount: 2500,
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply for paid gig'), findsOneWidget);
    });

    testWidgets('4. Musician who already applied to that exact subRequestId sees disabled "Already applied"', (tester) async {
      final service = MockMapApplyFirebaseService()
        ..backendAppliedIds.add('sub_already_1');
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(id: 'sub_already_1');

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      final appliedBtn = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('map_pin_applied_button')),
      );
      expect(appliedBtn.onPressed, isNull);
      expect(find.text('Already applied'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });

    testWidgets('5. Request creator sees "Manage Request" and never sees Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'creator_user_a');
      final gig = _buildStaffingRequest(
        id: 'sub_creator_1',
        creatorUserId: 'creator_user_a',
      );
      SubRequest? managedGig;

      await tester.pumpWidget(
        _wrapCard(
          gig: gig,
          appState: appState,
          onManageRequest: (_, g) => managedGig = g,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_manage_request_button')), findsOneWidget);
      expect(find.text('Manage Request'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('map_pin_manage_request_button')));
      await tester.pump();
      expect(managedGig?.id, 'sub_creator_1');
    });

    testWidgets('6. Band Leader/Admin of the band that owns the request sees "Manage Request" and never sees Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      service.bandAdmins['Deku_Tree_Bongo'] = {'co_leader_user'};
      final appState = MockMapApplyAppState(service, userId: 'co_leader_user');
      final gig = _buildStaffingRequest(
        id: 'sub_coleader_1',
        bandId: 'Deku_Tree_Bongo',
        creatorUserId: 'creator_user_a',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_manage_request_button')), findsOneWidget);
      expect(find.text('Manage Request'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });

    testWidgets('7. Assigned request does not show Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_assigned_1',
        status: 'assigned',
        assignedUserId: 'other_musician',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);
    });

    testWidgets('8. Cancelled, deleted, closed or archived request does not show Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');

      for (final closedStatus in ['cancelled', 'deleted', 'closed', 'archived']) {
        final gig = _buildStaffingRequest(
          id: 'sub_$closedStatus',
          status: closedStatus,
        );
        await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing,
            reason: 'Status "$closedStatus" must not show Apply');
      }
    });

    testWidgets('9. Expired/completed request does not show Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final pastDate = DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .split('T')
          .first;
      final gig = _buildStaffingRequest(
        id: 'sub_expired_1',
        date: pastDate,
        startTime: '18:00',
        endTime: '20:00',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });

    testWidgets('10. Ordinary Event projection card does not show Apply and still shows "View Public Event" or "View Event Details"', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final publicEventCard = _buildStaffingRequest(
        id: 'event:public_1',
        extraFields: {
          'isEventProjection': true,
          'eventSource': 'public_calendar',
        },
      );

      await tester.pumpWidget(_wrapCard(gig: publicEventCard, appState: appState));
      await tester.pumpAndSettle();

      expect(find.text('View Public Event'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
      expect(find.byKey(const ValueKey('map_pin_manage_request_button')), findsNothing);

      final bandEventCard = _buildStaffingRequest(
        id: 'event:band_1',
        extraFields: {
          'isEventProjection': true,
          'eventSource': 'band_event',
        },
      );

      await tester.pumpWidget(_wrapCard(gig: bandEventCard, appState: appState));
      await tester.pumpAndSettle();

      expect(find.text('View Event Details'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });

    testWidgets('11. Music Promotion pin card does not show Apply and preserves owner "Edit Pin" / "Delete Pin"', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'creator_user_a');
      final promoPin = _buildStaffingRequest(
        id: 'pin_promo_1',
        creatorUserId: 'creator_user_a',
        requestType: 'Music Promotion',
        role: 'Music Promotion',
        notificationMode: 'map_pin',
      );
      bool editTapped = false;
      bool deleteTapped = false;

      await tester.pumpWidget(
        _wrapCard(
          gig: promoPin,
          appState: appState,
          onEditPin: (_) => editTapped = true,
          onDeletePin: (_) => deleteTapped = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Pin'), findsOneWidget);
      expect(find.text('Delete Pin'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
      expect(find.byKey(const ValueKey('map_pin_manage_request_button')), findsNothing);

      await tester.tap(find.text('Edit Pin'));
      await tester.tap(find.text('Delete Pin'));
      expect(editTapped, isTrue);
      expect(deleteTapped, isTrue);
    });

    testWidgets('12. Go Live broadcast / mock / demo items do not show Apply', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');

      final demoItem = _buildStaffingRequest(
        id: 'demo_sthlm_1',
        extraFields: {'isDemoStockholm': true},
      );
      await tester.pumpWidget(_wrapCard(gig: demoItem, appState: appState));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);

      final mockItem = _buildStaffingRequest(
        id: 'mock_rehearsal_1',
        extraFields: {'isMock': true},
      );
      await tester.pumpWidget(_wrapCard(gig: mockItem, appState: appState));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });
  });

  group('MAP-VIEW-APPLY-01 — Confirmation Dialog & Submission Lifecycle', () {
    testWidgets('13-15 & 18. Tapping Apply opens confirmation dialog with exact position and band; Cancel makes zero calls; Confirm calls service once and transitions to ✓ Applied', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_deku_confirm_1',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      // 13. Open confirmation dialog
      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();

      expect(find.text('Apply as Electric Guitar for Deku Tree Bongo?'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_apply_dialog_cancel')), findsOneWidget);
      expect(find.byKey(const ValueKey('map_apply_dialog_confirm')), findsOneWidget);

      // 14. Tapping Cancel makes zero backend calls and leaves button as Apply
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(service.submittedSubRequestIds, isEmpty);
      expect(find.text('Apply for this gig'), findsOneWidget);

      // 15 & 18. Reopen and confirm Apply
      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(service.submittedSubRequestIds, ['sub_deku_confirm_1']);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsOneWidget);
      expect(find.text('Already applied'), findsOneWidget);
      final appliedBtn = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('map_pin_applied_button')),
      );
      expect(appliedBtn.onPressed, isNull);
    });

    testWidgets('16 & 17. In-flight submission disables button, shows "Applying...", and prevents duplicate submissions on rapid taps', (tester) async {
      final service = MockMapApplyFirebaseService();
      service.pendingApplyCompleter = Completer<void>();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_inflight_1',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
      );

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pump();

      // 17. While in flight, button is disabled and shows "Applying..."
      expect(find.text('Applying...'), findsOneWidget);
      final applyBtn = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('map_pin_apply_button')),
      );
      expect(applyBtn.onPressed, isNull);

      // 16. Rapid extra taps while in flight do not open another dialog or submit twice
      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')), warnIfMissed: false);
      await tester.pump();
      expect(service.submittedSubRequestIds.length, 1);

      // Complete backend call
      service.pendingApplyCompleter!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Already applied'), findsOneWidget);
      expect(service.submittedSubRequestIds, ['sub_inflight_1']);
    });

    testWidgets('19 & 20. Closing and reopening the same marker card or hard reload preserves "Already applied"', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(id: 'sub_persist_1');

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Already applied'), findsOneWidget);

      // 19. Close card (unmount) and reopen with same session AppState
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();
      expect(find.text('Already applied'), findsOneWidget);

      // 20. Simulate hard refresh (fresh AppState with empty session cache, resolved from backend)
      final freshAppState = MockMapApplyAppState(service, userId: 'musician_user_b');
      expect(freshAppState.hasAppliedToSubRequest('sub_persist_1'), isFalse);

      await tester.pumpWidget(_wrapCard(gig: gig, appState: freshAppState));
      await tester.pumpAndSettle();
      expect(find.text('Already applied'), findsOneWidget);
      expect(freshAppState.hasAppliedToSubRequest('sub_persist_1'), isTrue);
    });

    testWidgets('21. Callable failure leaves Apply available, keeps card open, and shows an error', (tester) async {
      final service = MockMapApplyFirebaseService()
        ..nextApplyError = Exception('permission-denied: not authorized');
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(id: 'sub_fail_1');

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();

      // Card stays open, error banner is shown, button remains enabled as Apply for this gig
      expect(find.byKey(const ValueKey('map_apply_error_banner')), findsOneWidget);
      expect(find.textContaining('do not have permission'), findsWidgets);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply for this gig'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);
    });

    testWidgets('22. Server-side "already applied" response resolves to "Already applied" without error banner', (tester) async {
      final service = MockMapApplyFirebaseService()
        ..nextApplyError = Exception('already-exists: User alreadyApplied');
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(id: 'sub_already_server_1');

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_apply_error_banner')), findsNothing);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsOneWidget);
      expect(find.text('Already applied'), findsOneWidget);
    });
  });

  group('MAP-VIEW-APPLY-01 — Grouped Staffing Requests', () {
    testWidgets('23-25. Grouped marker with multiple open positions requires explicit selection, submits only selected subRequestId, and keeps remaining positions open', (tester) async {
      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');

      final slotGuitar = _buildStaffingRequest(
        id: 'sub_group_guitar',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
      );
      final slotDrums = _buildStaffingRequest(
        id: 'sub_group_drums',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Drums',
      );

      await tester.pumpWidget(
        _wrapCard(
          gig: slotGuitar,
          groupedGigs: [slotGuitar, slotDrums],
          appState: appState,
        ),
      );
      await tester.pumpAndSettle();

      // Both position chips are visible on the card
      expect(find.byKey(const ValueKey('card_position_chip_sub_group_guitar')), findsOneWidget);
      expect(find.byKey(const ValueKey('card_position_chip_sub_group_drums')), findsOneWidget);

      // 23. Tapping Apply without pre-selecting opens dialog where Confirm is disabled until a position is selected
      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();

      expect(find.text('Select a position to apply for Deku Tree Bongo:'), findsOneWidget);
      final confirmBtnInitial = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('map_apply_dialog_confirm')),
      );
      expect(confirmBtnInitial.onPressed, isNull);

      // Select Drums inside the confirmation dialog
      await tester.tap(find.byKey(const ValueKey('dialog_position_chip_sub_group_drums')));
      await tester.pumpAndSettle();

      expect(find.text('Apply as Drums for Deku Tree Bongo?'), findsOneWidget);
      final confirmBtnAfterSelect = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('map_apply_dialog_confirm')),
      );
      expect(confirmBtnAfterSelect.onPressed, isNotNull);

      // 24. Confirming submits only sub_group_drums
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(service.submittedSubRequestIds, ['sub_group_drums']);

      // 25. Drums is marked applied ("✓ Drums"), while Electric Guitar remains open and primary button stays available
      expect(find.text('✓ Drums'), findsOneWidget);
      expect(find.text('Electric Guitar'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);

      // Applying to the remaining open position (Electric Guitar) now transitions the card to ✓ Applied
      await tester.tap(find.byKey(const ValueKey('map_pin_apply_button')));
      await tester.pumpAndSettle();
      expect(find.text('Apply as Electric Guitar for Deku Tree Bongo?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map_apply_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(service.submittedSubRequestIds, ['sub_group_drums', 'sub_group_guitar']);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsOneWidget);
      expect(find.text('Already applied'), findsOneWidget);
    });
  });

  group('MAP-VIEW-APPLY-01 — Security, Performance & Viewport Safety', () {
    test('26. Public projection payload / SubRequest serialization exposes no applicant UIDs, emails, phone numbers, or push tokens when sanitized for public feed', () {
      final gig = _buildStaffingRequest(id: 'sub_sec_1');
      final json = gig.toJson();
      final responses = json['Responses'] as Map?;
      expect(responses == null || responses.isEmpty, isTrue);
      expect(json.containsKey('email'), isFalse);
      expect(json.containsKey('phoneNumber'), isFalse);
      expect(json.containsKey('pushTokens'), isFalse);
    });

    testWidgets('27 & 28. Status is queried only for the opened card and switching rapidly between markers ignores stale lookup results', (tester) async {
      final service = MockMapApplyFirebaseService();
      final completerA = Completer<Set<String>>();
      final completerB = Completer<Set<String>>();
      service.pendingCardLookupByKey['sub_marker_a'] = completerA;
      service.pendingCardLookupByKey['sub_marker_b'] = completerB;

      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final markerA = _buildStaffingRequest(id: 'sub_marker_a', bandName: 'Band A');
      final markerB = _buildStaffingRequest(id: 'sub_marker_b', bandName: 'Band B');

      // Open Marker A
      await tester.pumpWidget(_wrapCard(gig: markerA, appState: appState));
      await tester.pump();
      expect(service.cardLookupCalls.length, 1);
      expect(service.cardLookupCalls.first, ['sub_marker_a']);

      // Rapidly switch to Marker B before Marker A's lookup completes
      await tester.pumpWidget(_wrapCard(gig: markerB, appState: appState));
      await tester.pump();
      expect(service.cardLookupCalls.length, 2);
      expect(service.cardLookupCalls[1], ['sub_marker_b']);

      // Marker B completes with not-applied; stale Marker A completes later with applied
      completerB.complete(<String>{});
      await tester.pumpAndSettle();
      completerA.complete({'sub_marker_a', 'sub_marker_b'});
      await tester.pumpAndSettle();

      // Stale result from Marker A must be ignored for Marker B
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);
    });

    testWidgets('29. Disposing MapPinDetailsCard while a lookup or application is in flight causes no setState-after-dispose errors', (tester) async {
      final service = MockMapApplyFirebaseService();
      final lookupCompleter = Completer<Set<String>>();
      service.pendingCardLookupByKey['sub_dispose_1'] = lookupCompleter;
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(id: 'sub_dispose_1');

      await tester.pumpWidget(_wrapCard(gig: gig, appState: appState));
      await tester.pump();

      // Dispose the card before lookup completes
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();

      lookupCompleter.complete({'sub_dispose_1'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('30. Narrow mobile viewport (320 px width) renders the details card and Apply button without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = MockMapApplyFirebaseService();
      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      final gig = _buildStaffingRequest(
        id: 'sub_narrow_320',
        bandName: 'Deku Tree Bongo Long Band Title',
        voicePart: 'Electric Lead & Rhythm Guitar',
        isPaid: true,
        payAmount: 3500,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: MapPinDetailsCard(
                    gig: gig,
                    appState: appState,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply for paid gig'), findsOneWidget);
    });

    testWidgets('31. New subsequent subrequest does NOT inherit applied state from a previous subrequest of same band', (tester) async {
      final service = MockMapApplyFirebaseService();
      // Musician applied to earlier gig 1
      const gig1Id = 'sub_Deku_Tree_Bongo_freelance_event_draft_initial_0_1793278947230';
      service.backendAppliedIds.add(gig1Id);

      final appState = MockMapApplyAppState(service, userId: 'musician_user_b');
      appState.markSubRequestApplied(gig1Id);

      // Brand new gig 2 created for the same band
      final gig2 = _buildStaffingRequest(
        id: 'sub_Deku_Tree_Bongo_freelance_event_draft_initial_0_1793282567362',
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
        isPaid: true,
        payAmount: 1337,
      );

      // 1. Viewing new gig 2 card must show Apply button (NOT Already applied)
      await tester.pumpWidget(_wrapCard(gig: gig2, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsOneWidget);
      expect(find.text('Apply for paid gig'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsNothing);

      // 2. Viewing previous gig 1 card shows Already applied
      final gig1 = _buildStaffingRequest(
        id: gig1Id,
        bandName: 'Deku Tree Bongo',
        voicePart: 'Electric Guitar',
        isPaid: true,
        payAmount: 1337,
      );
      await tester.pumpWidget(_wrapCard(gig: gig1, appState: appState));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('map_pin_applied_button')), findsOneWidget);
      expect(find.text('Already applied'), findsOneWidget);
      expect(find.byKey(const ValueKey('map_pin_apply_button')), findsNothing);
    });
  });
}
