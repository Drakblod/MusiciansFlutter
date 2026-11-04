// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/widgets/band_required_prompt.dart';
import 'package:musicians_flutter/widgets/animated_tap_detector.dart';
import 'new_user_skills_and_band_guards_01_test.dart' as guards;
import 'registration_secondary_skills_01_test.dart' as base;

class PromptService extends guards.GuardService {
  bool fail = false;
  int membershipReads = 0;
  int bandInfoReads = 0;
  bool failRoomDetails = false;
  bool missingRoomDetails = false;
  @override
  Future<Band?> getBandInfoAsync(String bandId) {
    bandInfoReads++;
    if (bandInfoReads > 1 && failRoomDetails) {
      throw FirebaseException(
        plugin: 'firebase_database',
        code: 'permission-denied',
        message: 'PRIVATE RAW FIREBASE DETAIL',
      );
    }
    if (bandInfoReads > 1 && missingRoomDetails) return Future.value(null);
    return super.getBandInfoAsync(bandId);
  }

  Completer<List<SubRequest>>? delayedRequests;
  List<SubRequest> activeRequests = [];
  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) =>
      delayedRequests?.future ?? Future.value(activeRequests);
  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) {
    membershipReads++;
    if (fail)
      throw FirebaseException(
        plugin: 'firebase_database',
        code: 'permission-denied',
        message: 'PRIVATE RAW FIREBASE DETAIL',
      );
    return super.getUserBandsAsync(userId);
  }
}

class PromptState extends guards.GuardState {
  @override
  final PromptService service = PromptService();
  bool busy = false;
  @override
  bool get isLoading => busy;
}

class RouteSpy extends NavigatorObserver {
  final List<RouteSettings> pushes = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes.add(route.settings);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) pushes.add(newRoute.settings);
  }
}

Widget app(PromptState state, RouteSpy spy, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        navigatorObservers: [spy],
        home: child,
        routes: {
          '/create-band': (_) =>
              const Scaffold(body: Text('EXISTING CREATE BAND ROUTE')),
          '/band-room': (_) => const BandRoomChatScreen(),
          '/find-sub': (_) => const FindSubScreen(),
          '/main-nav': (_) => const Scaffold(body: Text('SAFE HOME ROUTE')),
        },
      ),
    );

Widget launcher() => Builder(
  builder: (context) => Scaffold(
    body: Column(
      children: [
        const Text('UNCHANGED PREVIOUS SCREEN'),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/band-room'),
          child: const Text('DIRECT ROOM'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/find-sub'),
          child: const Text('DIRECT STAFFING'),
        ),
      ],
    ),
  ),
);

String label(bool staffing) =>
    staffing ? 'Find\nMusician/Vocalist' : 'Band Room';
String body(bool staffing) => staffing
    ? BandRequiredDialog.staffingBody
    : BandRequiredDialog.bandRoomBody;
Future<void> click(WidgetTester tester, bool staffing) async {
  final target = find.text(label(staffing)).first;
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  await tester.tap(target);
  await guards.settle(tester);
}

void noProtectedWork(PromptState state, RouteSpy spy) {
  expect(
    spy.pushes.where((s) => s.name == '/band-room' || s.name == '/find-sub'),
    isEmpty,
  );
  expect(state.service.formReads, 0);
  expect(state.service.roomReads, 0);
  expect(state.service.writes, 0);
  expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    auth.FirebaseAuthPlatform.instance = base.GateAuthPlatform();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final staffing in [false, true]) {
    final name = staffing ? 'Find Musician' : 'Band Room';
    testWidgets(
      '$name no-band Home click uses approved shared dialog without navigation or writes',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(app(state, spy, const HomeScreen()));
        await guards.settle(tester);
        await click(tester, staffing);
        expect(find.byType(BandRequiredDialog), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Create a band first'), findsOneWidget);
        expect(find.text(body(staffing)), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.scrollable, isTrue);
        expect(dialog.backgroundColor, isNull);
        expect(dialog.shape, isNull);
        expect(find.byType(HomeScreen), findsOneWidget);
        noProtectedWork(state, spy);
      },
    );
    testWidgets(
      '$name Cancel leaves Home unchanged and rebuild does not reopen prompt',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(app(state, spy, const HomeScreen()));
        await guards.settle(tester);
        await click(tester, staffing);
        await tester.tap(find.text('Cancel'));
        await guards.settle(tester);
        state.notifyListeners();
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        noProtectedWork(state, spy);
        await click(tester, staffing);
        expect(find.byType(BandRequiredDialog), findsOneWidget);
      },
    );
    testWidgets(
      '$name Create a Band opens only existing route with no new arguments',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(app(state, spy, const HomeScreen()));
        await guards.settle(tester);
        await click(tester, staffing);
        await tester.tap(find.text('Create a Band'));
        await guards.settle(tester);
        expect(find.text('EXISTING CREATE BAND ROUTE'), findsOneWidget);
        final creates = spy.pushes
            .where((s) => s.name == '/create-band')
            .toList();
        expect(creates, hasLength(1));
        expect(creates.single.arguments, isNull);
        noProtectedWork(state, spy);
      },
    );
    testWidgets('$name rapid repeated taps coalesce lookup and open one prompt', (
      tester,
    ) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      state.service.membershipReads = 0;
      state.service.delayedBands = Completer<Map<String, String>>();
      final target = find.text(label(staffing)).first;
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      // Two already-dispatched handlers before the new modal barrier is painted.
      final action = tester
          .widget<AnimatedTapDetector>(
            find
                .ancestor(
                  of: target,
                  matching: find.byType(AnimatedTapDetector),
                )
                .first,
          )
          .onTap;
      action();
      action();
      await guards.settle(tester);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byType(BandRequiredDialog), findsNothing);
      expect(state.service.membershipReads, 1);
      noProtectedWork(state, spy);
      state.service.delayedBands!.complete({});
      await guards.settle(tester);
      expect(find.byType(BandRequiredDialog), findsOneWidget);
      state.notifyListeners();
      await guards.settle(tester);
      expect(find.byType(BandRequiredDialog), findsOneWidget);
    });
    testWidgets(
      '$name lookup failure is neutral, hides raw Firebase text, and Retry rechecks',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(app(state, spy, const HomeScreen()));
        await guards.settle(tester);
        state.service.membershipReads = 0;
        state.service.fail = true;
        await click(tester, staffing);
        expect(find.text('Could not verify band membership'), findsOneWidget);
        expect(find.byType(BandRequiredDialog), findsNothing);
        expect(find.text('Create a Band'), findsNothing);
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(
          find.textContaining('PRIVATE RAW FIREBASE DETAIL'),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        noProtectedWork(state, spy);
        state.service.fail = false;
        await tester.tap(find.text('Retry'));
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsOneWidget);
        expect(state.service.membershipReads, 2);
      },
    );
    testWidgets(
      '$name direct route prompts then Cancel safely returns to previous route',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(app(state, spy, launcher()));
        await guards.settle(tester);
        await tester.tap(
          find.text(staffing ? 'DIRECT STAFFING' : 'DIRECT ROOM'),
        );
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsOneWidget);
        expect(find.text(body(staffing)), findsOneWidget);
        expect(state.service.formReads, 0);
        expect(state.service.roomReads, 0);
        expect(state.service.writes, 0);
        await tester.tap(find.text('Cancel'));
        await guards.settle(tester);
        expect(find.text('UNCHANGED PREVIOUS SCREEN'), findsOneWidget);
        expect(find.byType(BandRequiredDialog), findsNothing);
        state.notifyListeners();
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsNothing);
      },
    );
    testWidgets(
      '$name direct root Create replaces blocked route with existing creation flow',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        await tester.pumpWidget(
          app(
            state,
            spy,
            staffing ? const FindSubScreen() : const BandRoomChatScreen(),
          ),
        );
        await guards.settle(tester);
        await tester.tap(find.text('Create a Band'));
        await guards.settle(tester);
        expect(find.text('EXISTING CREATE BAND ROUTE'), findsOneWidget);
        expect(spy.pushes.where((s) => s.name == '/create-band'), hasLength(1));
        expect(state.service.writes, 0);
      },
    );
    testWidgets(
      '$name direct loading and failure never become false empty membership',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        final pending = Completer<Map<String, String>>();
        state.service.delayedBands = pending;
        await tester.pumpWidget(
          app(
            state,
            spy,
            staffing ? const FindSubScreen() : const BandRoomChatScreen(),
          ),
        );
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(state.service.formReads, 0);
        expect(state.service.roomReads, 0);
        pending.completeError(
          FirebaseException(
            plugin: 'firebase_database',
            code: 'permission-denied',
            message: 'PRIVATE RAW FIREBASE DETAIL',
          ),
        );
        await guards.settle(tester);
        expect(
          find.text('Could not verify band membership. Retry'),
          findsOneWidget,
        );
        expect(find.text('Create a Band'), findsNothing);
        expect(find.byType(BandRequiredDialog), findsNothing);
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(
          find.textContaining('PRIVATE RAW FIREBASE DETAIL'),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(state.service.writes, 0);
        state.service.delayedBands = null;
        await tester.tap(find.text('Could not verify band membership. Retry'));
        await guards.settle(tester);
        expect(find.byType(BandRequiredDialog), findsOneWidget);
        expect(state.service.formReads, 0);
        expect(state.service.roomReads, 0);
        expect(state.service.writes, 0);
      },
    );
    testWidgets('$name 320px modal wraps without overflow', (tester) async {
      await guards.size(tester, width: 320);
      tester.view.physicalSize = const Size(320, 568);
      final state = PromptState();
      final spy = RouteSpy();
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      await click(tester, staffing);
      expect(find.byType(BandRequiredDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AlertDialog)).width,
        lessThanOrEqualTo(320),
      );
    });
  }

  for (final missing in [false, true]) {
    testWidgets(
      'post-authorization room details ${missing ? 'missing' : 'failure'} is a retry state, not no-band',
      (tester) async {
        await guards.size(tester);
        final state = PromptState();
        final spy = RouteSpy();
        state.service.bands['real'] = guards.realBand();
        await state.refreshBandMemberships();
        state.service.failRoomDetails = !missing;
        state.service.missingRoomDetails = missing;
        await tester.pumpWidget(app(state, spy, const BandRoomChatScreen()));
        await guards.settle(tester);
        expect(find.text('Could not load Band Room. Retry'), findsOneWidget);
        expect(find.byType(BandRequiredDialog), findsNothing);
        expect(find.text('Create a Band'), findsNothing);
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(
          find.textContaining('PRIVATE RAW FIREBASE DETAIL'),
          findsNothing,
        );
        state.service.failRoomDetails = false;
        state.service.missingRoomDetails = false;
        await tester.tap(find.text('Could not load Band Room. Retry'));
        await guards.settle(tester);
        expect(find.text('Verified Band'), findsWidgets);
        expect(find.text('Could not load Band Room. Retry'), findsNothing);
        expect(state.service.writes, 0);
      },
    );
  }

  testWidgets('existing ordinary member enters Band Room normally', (
    tester,
  ) async {
    await guards.size(tester);
    final state = PromptState();
    final spy = RouteSpy();
    state.service.bands['real'] = guards.realBand(role: 'Member');
    await tester.pumpWidget(app(state, spy, const HomeScreen()));
    await guards.settle(tester);
    await click(tester, false);
    expect(find.byType(BandRequiredDialog), findsNothing);
    expect(state.service.roomReads, 1);
    expect(find.text('Verified Band'), findsWidgets);
    expect(spy.pushes.where((s) => s.name == '/band-room'), hasLength(1));
  });
  for (final role in ['Leader', 'Admin', 'Member']) {
    testWidgets('$role staffing permission is preserved', (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      state.service.bands['real'] = guards.realBand(role: role);
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      await click(tester, true);
      expect(find.byType(BandRequiredDialog), findsNothing);
      if (role == 'Member') {
        expect(find.text('Band leader or admin required'), findsOneWidget);
        expect(state.service.formReads, 0);
        expect(find.text('Create a Band'), findsNothing);
      } else {
        expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
        expect(state.service.formReads, greaterThan(0));
      }
      expect(state.service.writes, 0);
    });
  }
  testWidgets(
    'switching user cancels a pending Home decision and clears authorization',
    (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      state.service.bands['real'] = guards.realBand();
      await state.refreshBandMemberships();
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      final pending = Completer<Map<String, String>>();
      state.service.delayedBands = pending;
      await click(tester, false);
      state.service.uid = 'b';
      state.notifyListeners();
      await guards.settle(tester);
      pending.complete({'real': 'Previous user band'});
      state.service.delayedBands = null;
      await guards.settle(tester);
      expect(state.activeBandId, isNull);
      expect(find.byType(BandRequiredDialog), findsNothing);
      noProtectedWork(state, spy);
      await click(tester, false);
      expect(find.byType(BandRequiredDialog), findsOneWidget);
    },
  );
  testWidgets('new user can navigate while prior user lookup is unfinished', (
    tester,
  ) async {
    await guards.size(tester);
    final state = PromptState();
    final spy = RouteSpy();
    await tester.pumpWidget(app(state, spy, const HomeScreen()));
    await guards.settle(tester);
    state.service.membershipReads = 0;
    final a = Completer<Map<String, String>>();
    state.service.delayedBands = a;
    await click(tester, false);
    state.service.uid = 'b';
    state.notifyListeners();
    await guards.settle(tester);
    final b = Completer<Map<String, String>>();
    state.service.delayedBands = b;
    await click(tester, false);
    expect(state.service.membershipReads, 2);
    final pushes = spy.pushes.length;
    a.complete({'old': 'Previous user band'});
    await guards.settle(tester);
    final action = tester
        .widget<AnimatedTapDetector>(
          find
              .ancestor(
                of: find.text(label(false)).first,
                matching: find.byType(AnimatedTapDetector),
              )
              .first,
        )
        .onTap;
    action();
    await guards.settle(tester);
    expect(spy.pushes, hasLength(pushes));
    expect(find.byType(BandRequiredDialog), findsNothing);
    b.complete({});
    await guards.settle(tester);
    expect(find.byType(BandRequiredDialog), findsOneWidget);
    expect(state.activeBandId, isNull);
    noProtectedWork(state, spy);
  });

  testWidgets(
    'late staffing data cannot navigate or expose a prior user request sheet',
    (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      state.service.bands['real'] = guards.realBand();
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      final pending = Completer<List<SubRequest>>();
      state.service.delayedRequests = pending;
      await click(tester, true);
      state.service.uid = 'b';
      state.notifyListeners();
      await guards.settle(tester);
      pending.complete([SubRequest(bandId: 'real', status: 'pending')]);
      await guards.settle(tester);
      expect(find.text('FIND MUSICIAN / SUBSTITUTE'), findsNothing);
      expect(find.byType(BandRequiredDialog), findsNothing);
      noProtectedWork(state, spy);
      expect(state.activeBandId, isNull);
    },
  );
  testWidgets(
    'user switch closes the prior user band selector without exposing content',
    (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      state.service.bands['one'] = guards.realBand(id: 'one');
      state.service.bands['two'] = guards.realBand(id: 'two');
      await tester.pumpWidget(app(state, spy, const HomeScreen()));
      await guards.settle(tester);
      await click(tester, false);
      expect(find.text('SELECT A BAND'), findsOneWidget);
      state.service.uid = 'b';
      state.notifyListeners();
      await guards.settle(tester);
      expect(find.text('SELECT A BAND'), findsNothing);
      expect(find.text('Verified Band'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      noProtectedWork(state, spy);
    },
  );
  testWidgets('user switch closes the previous active-request choice sheet', (
    tester,
  ) async {
    await guards.size(tester);
    final state = PromptState();
    final spy = RouteSpy();
    state.service.bands['real'] = guards.realBand();
    state.service.activeRequests = [
      SubRequest(bandId: 'real', status: 'pending'),
    ];
    await tester.pumpWidget(app(state, spy, const HomeScreen()));
    await guards.settle(tester);
    await click(tester, true);
    expect(find.text('FIND MUSICIAN / SUBSTITUTE'), findsOneWidget);
    state.service.uid = 'b';
    state.notifyListeners();
    await guards.settle(tester);
    expect(find.text('FIND MUSICIAN / SUBSTITUTE'), findsNothing);
    expect(find.text('VERIFIED BAND'), findsNothing);
    noProtectedWork(state, spy);
  });

  testWidgets(
    'account switch removes open protected content before a new prompt',
    (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      state.service.bands['real'] = guards.realBand();
      await tester.pumpWidget(app(state, spy, const BandRoomChatScreen()));
      await guards.settle(tester);
      expect(find.text('Verified Band'), findsWidgets);
      state.service.uid = 'b';
      state.notifyListeners();
      await guards.settle(tester);
      expect(find.text('Verified Band'), findsNothing);
      expect(state.activeBandId, isNull);
      expect(find.byType(BandRequiredDialog), findsOneWidget);
      expect(state.service.writes, 0);
    },
  );
  testWidgets(
    'direct root Cancel safely returns to existing main route without a blank page',
    (tester) async {
      await guards.size(tester);
      final state = PromptState();
      final spy = RouteSpy();
      await tester.pumpWidget(app(state, spy, const BandRoomChatScreen()));
      await guards.settle(tester);
      await tester.tap(find.text('Cancel'));
      await guards.settle(tester);
      expect(find.text('SAFE HOME ROUTE'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  testWidgets('auth/session loading cannot show a false direct-route prompt', (
    tester,
  ) async {
    await guards.size(tester);
    final state = PromptState();
    final spy = RouteSpy();
    await tester.pumpWidget(app(state, spy, const SizedBox()));
    await guards.settle(tester);
    state.service.membershipReads = 0;
    state.busy = true;
    await tester.pumpWidget(app(state, spy, const BandRoomChatScreen()));
    await guards.settle(tester);
    expect(find.byType(BandRequiredDialog), findsNothing);
    expect(state.service.membershipReads, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    state.busy = false;
    state.notifyListeners();
    await guards.settle(tester);
    expect(find.byType(BandRequiredDialog), findsOneWidget);
  });
  testWidgets(
    'long future text and large text scale remain scrollable at 320px',
    (tester) async {
      await guards.size(tester, width: 320);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => BandRequiredDialog(
                    staffing: false,
                    body: List.filled(
                      100,
                      'Long future translated membership explanation.',
                    ).join(' '),
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await guards.settle(tester);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AlertDialog)).height,
        lessThanOrEqualTo(568),
      );
    },
  );
}
