import 'dart:async';

import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/request_management_access.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/notification_router.dart';
import 'package:musicians_flutter/views/event_details_page.dart';
import 'package:musicians_flutter/views/sub_request_details_screen.dart';
import 'package:musicians_flutter/views/sub_request_response_details_screen.dart';

class RoutingService extends FirebaseService {
  final identities = StreamController<String?>.broadcast(sync: true);
  String? uid;
  final calls = <(String?, String, String?, bool)>[];
  final marked = <String>[];
  late FutureOr<Map<String, dynamic>> Function(String?, String?, bool) resolve;

  @override
  String? get currentUserId => uid;
  @override
  bool get isLoggedIn => false;
  @override
  Stream<String?> get catalogueIdentityChanges => identities.stream;
  @override
  Future<void> listenForNativeNotifications() async {}

  void switchTo(String? account) {
    uid = account;
    identities.add(account);
  }

  @override
  Future<Map<String, dynamic>> resolveNotificationAsync(
    String notificationId, {String? slotId, bool preview = false}
  ) async {
    calls.add((uid, notificationId, slotId, preview));
    return await resolve(uid, slotId, preview);
  }

  @override
  Future<void> markNotificationReadAsync(String notificationId) async {
    marked.add(notificationId);
  }

  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<RequestManagementAccess> authorizeRequestManagement({
    String? bandId, String? requestId, String? expectedCreatorId,
    bool Function()? isCurrent,
  }) async => RequestManagementAccess(
    userId: uid!, bandId: bandId!,
    request: SubRequest(id: requestId, bandId: bandId),
  );

  @override
  Stream<bool> watchRequestManagementAccess(RequestManagementAccess access) =>
      Stream.value(true);

  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String subRequestId) async =>
      {'other-responder': true, 'target-responder': true};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async =>
      UserProfile(userId: userId, displayName: userId);

  (String, String, bool)? eventRead;
  @override
  Future<BandEvent?> getNotificationEventAsync(
    String bandId, String eventId, {required bool memberAccess}
  ) async {
    eventRead = (bandId, eventId, memberAccess);
    return null;
  }
}

void main() {
  final id = List.filled(64, 'a').join();
  final payload = {'schemaVersion': '2', 'notificationId': id, 'type': 'event_invite'};
  const summary = 'Band name • Rehearsal • Thursday';

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late RoutingService service;
  late NotificationRouter router;
  late GlobalKey<NavigatorState> key;

  Future<void> mount(WidgetTester tester, {String? uid}) async {
    SharedPreferences.setMockInitialValues({});
    service = RoutingService()..uid = uid;
    key = GlobalKey<NavigatorState>();
    router = NotificationRouter(service, () => key.currentState, selectBand: (_) {});
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(firebaseService: service),
      child: MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pump();
    addTearDown(() => service.identities.close());
  }

  testWidgets('foreground preview is authorized and deduplicated', (tester) async {
    await mount(tester, uid: 'a');
    service.resolve = (uid, _, preview) {
      expect(uid, 'a');
      expect(preview, true);
      return {'title': 'Gig Request', 'body': summary};
    };
    await router.receiveForeground(payload);
    await router.receiveForeground(payload);
    await tester.pump();
    expect(find.text('Gig Request\n$summary'), findsOneWidget);
    expect(service.calls, [('a', id, null, true)]);
    service.switchTo('b');
    await tester.pumpAndSettle();
    expect(find.textContaining(summary), findsNothing);
  });

  testWidgets('cold-start open waits for login and background duplicates are ignored', (tester) async {
    await mount(tester);
    service.resolve = (uid, _, __) {
      expect(uid, 'a');
      return {
        'kind': 'group',
        'matches': [
          {'id': 'one', 'label': 'First match'},
          {'id': 'two', 'label': 'Second match'},
        ],
      };
    };
    router.receiveNativeOpen(payload);
    expect(service.calls, isEmpty);
    service.switchTo('a');
    router.resumeNativeOpen();
    router.receiveNativeOpen(payload);
    await tester.pumpAndSettle();
    expect(service.calls, [('a', id, null, false)]);
    expect(find.text('Matching gig requests'), findsOneWidget);
    expect(find.text('First match'), findsOneWidget);
    expect(find.text('Second match'), findsOneWidget);
  });

  testWidgets('a delayed open under the wrong account fails neutrally', (tester) async {
    await mount(tester, uid: 'b');
    service.resolve = (_, __, ___) => throw const PrivateDataAccessException();
    router.receiveNativeOpen(payload);
    await tester.pumpAndSettle();
    expect(find.text('This notification is unavailable.'), findsOneWidget);
    expect(find.textContaining('Band name'), findsNothing);
    expect(service.calls, [('b', id, null, false)]);
    expect(service.marked, isEmpty);
  });

  testWidgets('account switch invalidates an in-flight foreground preview', (tester) async {
    await mount(tester, uid: 'a');
    final pending = Completer<Map<String, dynamic>>();
    service.resolve = (_, __, ___) => pending.future;
    final opening = router.receiveForeground(payload);
    service.switchTo('b');
    pending.complete({'title': 'Gig Request', 'body': summary});
    await opening;
    await tester.pump();
    expect(find.textContaining(summary), findsNothing);
  });

  testWidgets('group selection rechecks the exact slot before showing Description', (tester) async {
    await mount(tester, uid: 'a');
    service.resolve = (_, slot, __) => slot == null ? {
      'kind': 'group',
      'matches': [
        {'id': 'one', 'label': 'First match'},
        {'id': 'two', 'label': 'Second match'},
      ],
    } : {
      'kind': 'request',
      'request': {'id': slot, 'Description': 'Authorized Description', 'Status': 'published'},
    };
    await router.open(id);
    await tester.pumpAndSettle();
    expect(find.text('Authorized Description'), findsNothing);
    await tester.tap(find.text('Second match'));
    await tester.pumpAndSettle();
    final details = tester.widget<SubRequestDetailsScreen>(find.byType(SubRequestDetailsScreen));
    expect(details.subRequest.id, 'two');
    expect(details.subRequest.description, 'Authorized Description');
    expect(service.calls.last, ('a', id, 'two', false));
    service.switchTo('b');
    await tester.pump();
    expect(find.byType(SubRequestDetailsScreen), findsNothing);
  });

  testWidgets('response open passes the exact responder through the management gate', (tester) async {
    await mount(tester, uid: 'a');
    service.resolve = (_, __, ___) => {
      'kind': 'response', 'responderId': 'target-responder',
      'request': {'id': 'exact-request', 'BandId': 'exact-band'},
    };
    await router.open(id);
    await tester.pumpAndSettle();
    final details = tester.widget<SubRequestResponseDetailsScreen>(
      find.byType(SubRequestResponseDetailsScreen),
    );
    expect(details.initialResponderId, 'target-responder');
    expect(details.subRequest.id, 'exact-request');
    expect(find.text('target-responder'), findsOneWidget);
    final selected = find.byWidgetPredicate(
      (widget) => widget is Checkbox && widget.value == true,
    );
    expect(selected, findsOneWidget);
    final targetRow = find.ancestor(of: find.text('target-responder'), matching: find.byType(Row)).first;
    expect(find.descendant(of: targetRow, matching: selected), findsOneWidget);
  });

  testWidgets('deleted Event resolution produces no placeholder route', (tester) async {
    await mount(tester, uid: 'a');
    service.resolve = (_, __, ___) => {
      'kind': 'event', 'bandId': 'exact-band', 'eventId': 'exact-event', 'memberAccess': true,
    };
    await router.open(id);
    await tester.pump();
    expect(service.eventRead, ('exact-band', 'exact-event', true));
    expect(find.byType(EventDetailsPage), findsNothing);
    expect(find.text('This notification is unavailable.'), findsOneWidget);
  });
}
