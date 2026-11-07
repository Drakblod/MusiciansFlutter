// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/request_management_access.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/sub_request_card_helper.dart';
import 'package:musicians_flutter/views/sub_request_responses_screen.dart';

class ManageService extends Fake implements FirebaseService {
  // Lifecycle fixtures model an already authorized exact-band manager. The
  // focused security suite exercises the production authorization implementation.
  @override
  Stream<String?> get catalogueIdentityChanges => const Stream.empty();
  @override
  Stream<bool> watchRequestManagementAccess(RequestManagementAccess access) => const Stream.empty();
  @override
  Future<RequestManagementAccess> authorizeRequestManagement({String? bandId,
    String? requestId, String? expectedCreatorId, bool Function()? isCurrent}) async {
    if (bandId != 'band' || (isCurrent != null && !isCurrent())) {
      throw const PrivateDataAccessException();
    }
    final request = requestId == null ? null : [...requests,...bandRequests]
        .firstWhere((r) => (r.subRequestId ?? r.id) == requestId);
    return RequestManagementAccess(userId:'manager',bandId:bandId!,request:request);
  }

  @override
  Stream<int> subscribeToSubRequestResponseCount(String id) => const Stream<int>.empty();

  List<SubRequest> requests = [];
  List<SubRequest> bandRequests = [];
  final countReads = <String>[];
  final deletes = <String>[];
  final markedNotifications = <String>[];
  final notifications = <AppNotification>[];
  @override
  Future<void> markNotificationReadAsync(String id) async {
    markedNotifications.add(id);
  }

  int unexpectedCalls = 0;
  bool admin = false;
  Completer<List<SubRequest>>? delayed;
  Completer<int>? delayedCount;
  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String uid) =>
      delayed?.future ?? Future.value(List.of(requests));
  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async =>
      List.of(bandRequests);
  @override
  Future<bool> isBandLeaderOrAdminAsync(String band, String uid) async => admin;
  @override
  Future<int> getSubRequestResponseCountAsync(String id) {
    countReads.add(id);
    return delayedCount?.future ?? Future.value(3);
  }

  @override
  Future<bool> deleteSubRequestAsync(String uid, String id) async {
    deletes.add(id);
    requests.removeWhere((r) => r.subRequestId == id);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    return super.noSuchMethod(invocation);
  }
}

class ManageState extends ChangeNotifier implements AppState {
  @override
  String? get activeBandId => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  UserProfile? get currentUserProfile => null;
  @override
  int get unreadNotificationCount => 0;
  @override
  bool get hasUnreadMessages => false;
  @override
  List<AppNotification> get userNotifications => service.notifications;
  final ManageService service;
  ManageState(this.service);
  @override
  String? get currentUserId => 'manager';
  @override
  FirebaseService get firebaseService => service;
}

final fixedNow = DateTime(2026, 11, 4, 12);
SubRequest request({
  String id = 'position',
  String status = 'published',
  String? date = '2026-11-10',
  String? start = '18:00',
  String? end = '22:00',
  String? assigned,
  String role = 'Substitute',
  String? group,
  String? band,
}) => SubRequest(
  subRequestId: id,
  status: status,
  date: date,
  startTime: start,
  endTime: end,
  assignedUserId: assigned,
  role: role,
  requestType: role,
  requestGroupId: group,
  bandId: band ?? 'band',
  bandName: 'Band $id',
  creatorUserId: 'manager',
);

// The shared top bar animates continuously; pump a bounded animation window.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mount(
  WidgetTester tester,
  ManageService service, {
  DateTime Function()? clock,
  String band = 'band',
  void Function(SubRequest)? navigated,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: ManageState(service),
      child: MaterialApp(
        home: SubRequestResponsesScreen(
          bandId: band,
          clock: clock ?? () => fixedNow,
        ),
        routes: {
          '/sub-request-response-details': (context) {
            final req =
                (ModalRoute.of(context)!.settings.arguments
                        as Map)['subRequest']
                    as SubRequest;
            navigated?.call(req);
            return const Scaffold(body: Text('Isolated detail route'));
          },
        },
      ),
    ),
  );
  await settle(tester);
}

Finder card(String id) => find.byKey(ValueKey('view_responses_$id'));
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('Central active management policy', () {
    test('01 Future published Substitute is visible', () {
      expect(isActiveManageRequest(request(), now: fixedNow), isTrue);
    });
    test('02 Current request before end time is visible', () {
      expect(
        isActiveManageRequest(request(date: '2026-11-04'), now: fixedNow),
        isTrue,
      );
    });
    test('03 Exact end boundary is absent', () {
      expect(
        isActiveManageRequest(
          request(date: '2026-11-04'),
          now: DateTime(2026, 11, 4, 22),
        ),
        isFalse,
      );
    });
    test('04 Past dated Other request is absent', () {
      expect(
        isActiveManageRequest(
          request(date: '2026-11-02', role: 'Other'),
          now: fixedNow,
        ),
        isFalse,
      );
    });
    test('05 No end time survives date and expires at next local midnight', () {
      final req = request(date: '2026-11-04', end: null);
      expect(
        isActiveManageRequest(req, now: DateTime(2026, 11, 4, 23, 59, 59)),
        isTrue,
      );
      expect(isActiveManageRequest(req, now: DateTime(2026, 11, 5)), isFalse);
    });
    test('06 Midnight crossing survives until following-day exact end', () {
      final req = request(date: '2026-11-04', start: '22:00', end: '02:00');
      expect(
        isActiveManageRequest(req, now: DateTime(2026, 11, 5, 1, 59, 59)),
        isTrue,
      );
      expect(
        isActiveManageRequest(req, now: DateTime(2026, 11, 5, 2)),
        isFalse,
      );
    });
    for (final status in [
      'cancelled',
      'canceled',
      'deleted',
      'closed',
      'archived',
      'filled',
      'assigned',
      'expired',
      'draft',
      'pending_approval',
      '',
      ' ',
      'unknown',
    ]) {
      test('07 Inactive status "$status" is absent', () {
        expect(
          isActiveManageRequest(request(status: status), now: fixedNow),
          isFalse,
        );
      });
    }
    for (final status in [' published ', 'OPEN', 'Active']) {
      test('08 Normalized active status "$status" is visible', () {
        expect(
          isActiveManageRequest(request(status: status), now: fixedNow),
          isTrue,
        );
      });
    }
    test('09 Nonempty assignedUserId hides an active request', () {
      expect(
        isActiveManageRequest(request(assigned: ' musician '), now: fixedNow),
        isFalse,
      );
    });
    test('10 Null empty and whitespace assignment remain visible', () {
      for (final assigned in [null, '', '   ']) {
        expect(
          isActiveManageRequest(request(assigned: assigned), now: fixedNow),
          isTrue,
        );
      }
    });
    test('11 Undated active New Band Member remains visible', () {
      expect(
        isActiveManageRequest(
          request(role: 'New Member', date: null),
          now: fixedNow,
        ),
        isTrue,
      );
    });
    test('12 Closed undated New Band Member is absent', () {
      expect(
        isActiveManageRequest(
          request(role: 'New Member', date: null, status: 'closed'),
          now: fixedNow,
        ),
        isFalse,
      );
    });
    test(
      '13 Malformed and missing legacy date remain active without crashing',
      () {
        for (final date in [null, '', 'not-a-date']) {
          expect(
            isActiveManageRequest(request(date: date), now: fixedNow),
            isTrue,
          );
        }
      },
    );
    test('14 Positions in same group are evaluated independently', () {
      final active = request(id: 'active', group: 'group');
      final expired = request(
        id: 'expired',
        group: 'group',
        date: '2026-11-02',
      );
      expect(filterActiveManageRequests([expired, active], now: fixedNow), [
        active,
      ]);
    });
    test('15 Duplicate exact IDs produce one retained request', () {
      final req = request();
      expect(
        filterActiveManageRequests([
          req,
          req.copyWith(role: 'Other'),
        ], now: fixedNow),
        [req],
      );
    });
    test('16 November 2 and July 8 are absent on November 4', () {
      expect(
        filterActiveManageRequests([
          request(date: '2026-11-02'),
          request(id: 'recorder', date: '2026-07-08'),
        ], now: fixedNow),
        isEmpty,
      );
    });
    test(
      '17 Existing Applied and Manage use identical expiration boundaries',
      () {
        for (final req in [
          request(),
          request(end: null),
          request(date: 'bad'),
          request(date: '2026-11-04', start: '22:00', end: '02:00'),
        ]) {
          for (final now in [
            fixedNow,
            DateTime(2026, 11, 5, 2),
            DateTime(2026, 11, 11),
          ]) {
            expect(
              isActiveManageRequest(req, now: now),
              isActiveAppliedRequest(
                req,
                currentUserId: 'musician',
                appliedIds: {req.subRequestId!},
                now: now,
              ),
            );
          }
        }
      },
    );
  });
  group('Manage Requests pipeline', () {
    testWidgets('18 Active future request shows exact response count', (
      tester,
    ) async {
      final service = ManageService()..requests = [request()];
      await mount(tester, service);
      expect(card('position'), findsOneWidget);
      expect(find.text('View Responses (3)'), findsOneWidget);
      expect(service.countReads, ['position']);
      expect(service.unexpectedCalls, 0);
      await unmount(tester);
    });
    testWidgets(
      '19 Hidden requests have no counter reads cards or unread dots',
      (tester) async {
        final service = ManageService()
          ..requests = [
            request(date: '2026-11-02'),
            request(id: 'closed', status: 'closed'),
          ];
        await mount(tester, service);
        expect(find.text('View Responses (3)'), findsNothing);
        expect(service.countReads, isEmpty);
        final redDots = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE11D48),
        );
        expect(redDots, findsNothing);
        expect(service.unexpectedCalls, 0);
        await unmount(tester);
      },
    );
    testWidgets('20 Refresh removes newly expired and revoked records', (
      tester,
    ) async {
      var now = fixedNow;
      final service = ManageService()
        ..requests = [request(date: '2026-11-04'), request(id: 'revoked')];
      await mount(tester, service, clock: () => now);
      expect(card('position'), findsOneWidget);
      now = DateTime(2026, 11, 4, 22);
      service.requests = [
        service.requests.first,
        request(id: 'revoked', status: 'cancelled'),
      ];
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await settle(tester);
      expect(card('position'), findsNothing);
      expect(card('revoked'), findsNothing);
      expect(service.countReads, ['position', 'revoked']);
      await unmount(tester);
    });
    testWidgets('21 Empty state appears when every request is inactive', (
      tester,
    ) async {
      final service = ManageService()..requests = [request(status: 'archived')];
      await mount(tester, service);
      expect(find.text('No active requests found.'), findsWidgets);
      expect(find.byType(RefreshIndicator), findsWidgets);
      await unmount(tester);
    });
    testWidgets('22 No RenderFlex overflow at 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = ManageService()
        ..requests = [
          request(id: 'a very long future position instrument description'),
        ];
      await mount(tester, service);
      expect(find.text('View Responses (3)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
    testWidgets(
      '23 Filtering refresh and boundary expiry perform zero service writes',
      (tester) async {
        var now = DateTime(2026, 11, 4, 21, 59, 59);
        final service = ManageService()
          ..requests = [request(date: '2026-11-04')];
        await mount(tester, service, clock: () => now);
        now = DateTime(2026, 11, 4, 22);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await settle(tester);
        expect(service.deletes, isEmpty);
        expect(
          service.unexpectedCalls,
          0,
          reason: 'Any new RTDB or service method would fail the fake',
        );
        await unmount(tester);
      },
    );
    testWidgets(
      '24 Response navigation remains isolated by exact subRequestId',
      (tester) async {
        SubRequest? navigated;
        final service = ManageService()
          ..requests = [request(id: 'slot'), request(id: 'slot_2')];
        service.notifications.addAll([
          const AppNotification(
            id: 'reply_slot',
            type: 'sub_request_response',
            title: 'Reply',
            body: 'Reply',
            createdAt: 0,
            data: {'subRequestId': 'slot'},
          ),
          const AppNotification(
            id: 'reply_slot_2',
            type: 'sub_request_response',
            title: 'Other reply',
            body: 'Reply',
            createdAt: 0,
            data: {'subRequestId': 'slot_2'},
          ),
        ]);
        await mount(tester, service, navigated: (req) => navigated = req);
        await tester.tap(card('slot'));
        await settle(tester);
        expect(navigated?.subRequestId, 'slot');
        expect(service.markedNotifications, ['reply_slot']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('viewed_resp_slot'), 3);
        expect(prefs.getInt('viewed_resp_slot_2'), isNull);
        expect(service.deletes, isEmpty);
        await unmount(tester);
      },
    );
    testWidgets(
      '25 Existing confirmed delete targets only exact subRequestId',
      (tester) async {
        final service = ManageService()
          ..requests = [request(id: 'slot'), request(id: 'slot_2')];
        await mount(tester, service);
        await tester.tap(find.byKey(const ValueKey('delete_request_slot')));
        await settle(tester);
        await tester.tap(find.text('Yes'));
        await settle(tester);
        expect(service.deletes, ['slot']);
        expect(card('slot'), findsNothing);
        expect(card('slot_2'), findsOneWidget);
        await unmount(tester);
      },
    );
    testWidgets(
      '26 Boundary timer removes card at exact end without database reads',
      (tester) async {
        var now = DateTime(2026, 11, 4, 21, 59, 59);
        final service = ManageService()
          ..requests = [request(date: '2026-11-04')];
        await mount(tester, service, clock: () => now);
        expect(card('position'), findsOneWidget);
        now = DateTime(2026, 11, 4, 22);
        await tester.pump(const Duration(seconds: 1));
        expect(card('position'), findsNothing);
        expect(service.countReads, ['position']);
        expect(service.deletes, isEmpty);
        expect(service.unexpectedCalls, 0);
        await unmount(tester);
      },
    );
    testWidgets('27 Duplicate feed copies render one card and one count read', (
      tester,
    ) async {
      final service = ManageService()..admin = true;
      service.requests = [request(), request()];
      service.bandRequests = [request()];
      await mount(tester, service, band: 'band');
      expect(card('position'), findsOneWidget);
      expect(service.countReads, ['position']);
      await unmount(tester);
    });
    testWidgets(
      '28 Expired sibling never returns with active same-group slot',
      (tester) async {
        final service = ManageService()
          ..requests = [
            request(id: 'old', group: 'g', date: '2026-11-02'),
            request(id: 'future', group: 'g'),
          ];
        await mount(tester, service);
        expect(card('old'), findsNothing);
        expect(card('future'), findsOneWidget);
        expect(service.countReads, ['future']);
        await unmount(tester);
      },
    );
    testWidgets(
      '29 Members tab keeps undated active member and hides closed member',
      (tester) async {
        final service = ManageService()
          ..requests = [
            request(id: 'member', role: 'New Member', date: null),
            request(
              id: 'closed',
              role: 'New Member',
              date: null,
              status: 'closed',
            ),
          ];
        await mount(tester, service);
        await tester.tap(find.text('2. Members'));
        await settle(tester);
        expect(card('member'), findsOneWidget);
        expect(card('closed'), findsNothing);
        expect(service.countReads, ['member']);
        await unmount(tester);
      },
    );
    testWidgets('30 Expiry during response-count await cannot resurrect card', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 4, 21, 59, 59);
      final service = ManageService()..requests = [request(date: '2026-11-04')];
      service.delayedCount = Completer<int>();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: ManageState(service),
          child: MaterialApp(
            home: SubRequestResponsesScreen(bandId: 'all', clock: () => now),
          ),
        ),
      );
      await tester.pump();
      now = DateTime(2026, 11, 4, 22);
      service.delayedCount!.complete(3);
      await settle(tester);
      expect(card('position'), findsNothing);
      expect(find.text('View Responses (3)'), findsNothing);
      await unmount(tester);
    });
    testWidgets('31 Pull to refresh reloads already authorized records', (
      tester,
    ) async {
      final service = ManageService()..requests = [request()];
      await mount(tester, service);
      service.requests = [request(status: 'deleted')];
      await tester.drag(find.byType(ListView).first, const Offset(0, 350));
      await settle(tester);
      expect(card('position'), findsNothing);
      expect(service.deletes, isEmpty);
      expect(service.unexpectedCalls, 0);
      await unmount(tester);
    });

    testWidgets('32 No-end timer expires at next local midnight', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 4, 23, 59, 59);
      final service = ManageService()
        ..requests = [request(date: '2026-11-04', end: null)];
      await mount(tester, service, clock: () => now);
      expect(card('position'), findsOneWidget);
      now = DateTime(2026, 11, 5);
      await tester.pump(const Duration(seconds: 1));
      expect(card('position'), findsNothing);
      expect(service.countReads, ['position']);
      expect(service.deletes, isEmpty);
      await unmount(tester);
    });
    testWidgets('33 Superseded refresh cannot reintroduce stale feed results', (
      tester,
    ) async {
      final oldLoad = Completer<List<SubRequest>>();
      final service = ManageService()..delayed = oldLoad;
      await mount(tester, service);
      service.delayed = null;
      service.requests = [request(id: 'current')];
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await settle(tester);
      expect(card('current'), findsOneWidget);
      oldLoad.complete([request(id: 'stale')]);
      await settle(tester);
      expect(card('stale'), findsNothing);
      expect(card('current'), findsOneWidget);
      expect(service.countReads, ['current']);
      await unmount(tester);
    });
    testWidgets(
      '34 Leaving during load causes no late update or counter reads',
      (tester) async {
        final pending = Completer<List<SubRequest>>();
        final service = ManageService()..delayed = pending;
        await mount(tester, service);
        await unmount(tester);
        pending.complete([request()]);
        await settle(tester);
        expect(service.countReads, isEmpty);
        expect(service.unexpectedCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
