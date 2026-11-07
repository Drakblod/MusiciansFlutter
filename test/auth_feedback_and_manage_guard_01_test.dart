import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as platform;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/main.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/models/request_management_access.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/login_screen.dart';
import 'package:musicians_flutter/views/sub_request_responses_screen.dart';
import 'package:musicians_flutter/views/sub_request_response_details_screen.dart';
import 'package:musicians_flutter/widgets/request_management_gate.dart';
import 'registration_secondary_skills_01_test.dart' as fixtures;

class LoginService extends Fake implements FirebaseService {
  int calls = 0;
  Completer<UserCredential> pending = Completer<UserCredential>();
  @override
  bool get isLoggedIn => false;
  @override
  String? get currentUserId => null;
  @override
  Future<UserCredential> loginAsync(String email, String password) {
    calls++;
    return pending.future;
  }
}

class Credential extends Fake implements UserCredential {}

class World {
  Map<String, Object?> request = {
    'BandId': 'band',
    'CreatorUserId': 'manager',
    'Status': 'published',
    'Role': 'Substitute',
    'BandName': 'Canonical band',
    'Date': '2099-12-01',
  };
  Map<String, Object?>? member = {'Role': 'Leader', 'Status': 'active'};
  final reads = <String>[];
  Completer<void>? delay;
  bool error = false;
  Future<Object?> read(String path) async {
    reads.add(path);
    if (delay != null) await delay!.future;
    if (error)
      throw FirebaseException(
        plugin: 'database',
        code: 'permission-denied',
        message: 'internal secret',
      );
    if (path.startsWith('userBandMembershipIndex/')) return {'band': true};
    if (path == 'Bands/band/Members_band/manager') return member;
    if (path == 'Bands/band/Name') return 'Band';
    if (path == 'SubRequests/request') return Map<String, Object?>.of(request);
    if (path.startsWith('SubRequests/request/'))
      return request[path.split('/').last];
    return null;
  }
}

class GuardService extends FirebaseService {
  GuardService(this.world) : super(membershipRead: world.read);
  final World world;
  String? uid = 'manager';
  final identities = StreamController<String?>.broadcast(sync: true);
  final access = StreamController<bool>.broadcast(sync: true);
  int responseReads = 0, profileReads = 0, feedReads = 0, legacyReads = 0;
  Completer<Map<String, dynamic>>? responses;
  @override
  String? get currentUserId => uid;
  @override
  Stream<String?> get catalogueIdentityChanges => identities.stream;
  @override
  Stream<bool> watchRequestManagementAccess(RequestManagementAccess grant) =>
      access.stream;
  int deleteCalls=0;
  @override Future<bool> deleteSubRequestAsync(String uid,String id) async {deleteCalls++;return true;}
  @override
  Future<Map<String, dynamic>> getSubRequestResponsesAsync(String id) {
    responseReads++;
    return responses?.future ?? Future.value({'applicant': true});
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? uid]) async {
    profileReads++;
    return UserProfile(userId: uid, displayName: 'Private Applicant');
  }

  @override
  Future<SubRequest?> getSubRequestAsync(String id) async {
    legacyReads++;
    throw StateError('Legacy fallback forbidden');
  }

  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String uid) async {
    feedReads++;
    return [SubRequest.fromJson(world.request, 'request')];
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async => [];
  @override
  Stream<int> subscribeToSubRequestResponseCount(String id) =>
      const Stream.empty();
  Future<void> close() async {
    await identities.close();
    await access.close();
  }
}

class ListGuardService extends GuardService {
  ListGuardService(super.world);
  final ownership=StreamController<bool>.broadcast(sync:true);
  @override
  Stream<bool> watchRequestManagementAccess(RequestManagementAccess grant) =>
      grant.request == null ? access.stream : ownership.stream;
  @override
  Future<void> close() async {await ownership.close();await super.close();}
}

class GuardState extends ChangeNotifier implements AppState {
  GuardState(this.service);
  final GuardService service;
  String? band = 'band';
  @override
  FirebaseService get firebaseService => service;
  @override
  String? get currentUserId => service.uid;
  @override
  String? get activeBandId => band;
  @override
  UserProfile? get currentUserProfile => null;
  @override
  int get unreadNotificationCount => 0;
  @override
  bool get hasUnreadMessages => false;
  @override
  List<AppNotification> get userNotifications => [];
  void switchUser(String? uid) {
    service.uid = uid;
    service.identities.add(uid);
    notifyListeners();
  }

  void switchBand(String? value) {
    band = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mount(WidgetTester tester, GuardState state, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: child),
    ),
  );
  await pump(tester);
}

SubRequest hint({String? band = 'band', String creator = 'manager'}) =>
    SubRequest(subRequestId: 'request', bandId: band, creatorUserId: creator);
Future<void> finish(WidgetTester tester, GuardState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await state.service.close();
  state.dispose();
}

const denied = 'Request management is unavailable for your current access.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    // Offline font fixture: load the SDK's bundled Roboto for named UI families.
    // This permits real event-loop settling without network font fetches or error suppression.
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    );
    final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
    final font = File(
      '$sdk/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ).readAsBytesSync();
    final assets = <String, Object>{};
    for (final family in ['Inter', 'Outfit']) {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'Italic',
        'MediumItalic',
        'SemiBoldItalic',
        'BoldItalic',
      ]) {
        final path = 'test-fonts/$family-$weight.ttf';
        assets[path] = [
          {'asset': path},
        ];
      }
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (key == 'AssetManifest.bin')
            return const StandardMessageCodec().encodeMessage(assets);
          if (key.startsWith('test-fonts/')) return ByteData.sublistView(font);
          if (key.startsWith('assets/') &&
              !key.contains('..') &&
              File(key).existsSync()) {
            return ByteData.sublistView(File(key).readAsBytesSync());
          }
          return null;
        });
  });
  setUp(() {
    platform.FirebaseAuthPlatform.instance = fixtures.GateAuthPlatform();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  final errors = {
    'user-not-found': 'Incorrect email or password.',
    'wrong-password': 'Incorrect email or password.',
    'invalid-credential': 'Incorrect email or password.',
    'invalid-login-credentials': 'Incorrect email or password.',
    'invalid-email': 'Enter a valid email address.',
    'too-many-requests': 'Too many attempts. Please try again later.',
    'network-request-failed':
        'Unable to connect. Check your internet connection.',
    'user-disabled': 'This account has been disabled.',
    'unexpected': 'Unable to sign in right now. Please try again.',
  };
  for (final entry in errors.entries) {
    testWidgets(
      'login ${entry.key}: stable form, private accessible error and retained email',
      (tester) async {
        final service = LoginService();
        final state = AppState(firebaseService: service);
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: state,
            child: MaterialApp(
              home: const AuthGate(),
              routes: {'/main-nav': (_) => const Text('Signed in destination')},
            ),
          ),
        );
        await pump(tester);
        final element = tester.element(find.byType(LoginScreen));
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'alex@example.com',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'password');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(service.calls, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.element(find.byType(LoginScreen)), same(element));
        service.pending.completeError(
          entry.key == 'unexpected'
              ? StateError('internal secret')
              : FirebaseAuthException(
                  code: entry.key,
                  message: 'internal secret',
                ),
        );
        await pump(tester);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('internal secret'), findsNothing);
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          'alex@example.com',
        );
        expect(tester.element(find.byType(LoginScreen)), same(element));
        expect(find.text('Signed in destination'), findsNothing);
        final semantics = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const Key('login_failure')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(semantics.properties.liveRegion, true);
        service.pending = Completer<UserCredential>();
        await tester.tap(find.text('Login'));
        await tester.pump();
        expect(find.byKey(const Key('login_failure')), findsNothing);
        expect(service.calls, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        service.pending.completeError(StateError('disposed'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        state.dispose();
      },
    );
  }
  testWidgets(
    'button and Enter rapid repeats share one request; success navigation retained',
    (tester) async {
      final service = LoginService();
      final state = AppState(firebaseService: service);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: const AuthGate(),
            routes: {
              '/main-nav': (_) =>
                  const Scaffold(body: Text('Signed in destination')),
            },
          ),
        ),
      );
      await pump(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'alex@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password');
      await tester.tap(find.text('Login'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(service.calls, 1);
      service.pending.complete(Credential());
      await pump(tester);
      expect(find.text('Signed in destination'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets('invalid email validation and 320px login layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = LoginService();
    final state = AppState(firebaseService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextFormField).first, 'invalid');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pump(tester);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(service.calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  for (final role in ['Leader', 'Admin']) {
    testWidgets('$role sees action and opens guarded canonical detail', (
      tester,
    ) async {
      final world = World()..member = {'Role': role, 'Status': 'active'};
      final state = GuardState(GuardService(world));
      await mount(
        tester,
        state,
        Scaffold(
          body: RequestManagementGate(
            bandId: 'band',
            hideWhenDenied: true,
            builder: (_) => Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SubRequestResponseDetailsScreen(subRequest: hint()),
                  ),
                ),
                child: const Text('Manage Requests'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Manage Requests'), findsOneWidget);
      await tester.tap(find.text('Manage Requests'));
      await pump(tester);
      expect(find.text('Private Applicant'), findsOneWidget);
      expect(state.service.responseReads, 1);
      expect(state.service.profileReads, 1);
      expect(state.service.legacyReads, 0);
      await finish(tester, state);
    });
  }
  final deniedMembers = <String, Map<String, Object?>?>{
    'ordinary Member': {'Role': 'Member', 'Status': 'active'},
    'inactive creator': {'Role': 'Leader', 'Status': 'inactive'},
    'removed creator': null,
    'conflicting roles': {
      'Role': 'Leader',
      'role': 'Member',
      'Status': 'active',
    },
    'conflicting statuses': {
      'Role': 'Admin',
      'Status': 'active',
      'status': 'inactive',
    },
  };
  for (final entry in deniedMembers.entries) {
    testWidgets(
      '${entry.key}: hidden action and direct route denied without private reads',
      (tester) async {
        final world = World()..member = entry.value;
        final state = GuardState(GuardService(world));
        await mount(
          tester,
          state,
          Scaffold(
            body: RequestManagementGate(
              bandId: 'band',
              hideWhenDenied: true,
              builder: (_) => const Text('Manage Requests'),
            ),
          ),
        );
        expect(find.text('Manage Requests'), findsNothing);
        await mount(
          tester,
          state,
          SubRequestResponseDetailsScreen(subRequest: hint()),
        );
        expect(find.text(denied), findsOneWidget);
        expect(state.service.responseReads, 0);
        expect(state.service.profileReads, 0);
        expect(world.reads, isNot(contains('SubRequests/request')));
        expect(state.service.legacyReads, 0);
        await finish(tester, state);
      },
    );
  }
  for (final band in ['freelance', 'standalone']) {
    testWidgets('$band exact creator allowed without band authority', (
      tester,
    ) async {
      final world = World()..member = null;
      world.request['BandId'] = band;
      final state = GuardState(GuardService(world));
      await mount(
        tester,
        state,
        SubRequestResponseDetailsScreen(subRequest: hint(band: band)),
      );
      expect(find.text('Private Applicant'), findsOneWidget);
      expect(world.reads.where((p) => p.startsWith('Bands/')), isEmpty);
      await finish(tester, state);
    });
  }
  for (final scenario in [
    'noncreator freelance',
    'missing band',
    'empty band',
    'malformed band',
    'conflicting band',
    'other band manager',
    'wrong route band',
    'wrong route creator',
    'ordinary map pin',
    'signed out',
    'lookup error',
    'missing owner',
  ]) {
    testWidgets('$scenario denies detail and reads no private payload', (
      tester,
    ) async {
      final world = World();
      final state = GuardState(GuardService(world));
      var route = hint();
      switch (scenario) {
        case 'noncreator freelance':
          world.request['BandId'] = 'freelance';
          world.request['CreatorUserId'] = 'other';
          route = hint(band: 'freelance', creator: 'other');
        case 'missing band':
          world.request.remove('BandId');
          route = hint(band: null);
        case 'empty band':
          world.request['BandId'] = '';
          route = hint(band: '');
        case 'malformed band':
          world.request['BandId'] = 'bad/id';
          route = hint(band: 'bad/id');
        case 'conflicting band':
          world.request['bandId'] = 'other';
        case 'other band manager':
          world.request['BandId'] = 'other';
          route = hint(band: 'other');
        case 'wrong route band':
          route = hint(band: 'other');
        case 'wrong route creator':
          route = hint(creator: 'spoof');
        case 'ordinary map pin':
          world.request['NotificationMode'] = 'map_pin';
        case 'signed out':
          state.service.uid = null;
        case 'lookup error':
          world.error = true;
        case 'missing owner':
          world.request.remove('CreatorUserId');
      }
      await mount(
        tester,
        state,
        SubRequestResponseDetailsScreen(subRequest: route),
      );
      expect(find.text(denied), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(state.service.responseReads, 0);
      expect(state.service.profileReads, 0);
      expect(world.reads, isNot(contains('SubRequests/request')));
      expect(state.service.legacyReads, 0);
      await finish(tester, state);
    });
  }
  for (final scenario in [
    'logout',
    'user switch',
    'ABA user switch',
    'band switch',
    'role loss',
    'access error',
  ]) {
    testWidgets('$scenario clears rendered private applicant', (tester) async {
      final state = GuardState(GuardService(World()));
      await mount(
        tester,
        state,
        SubRequestResponseDetailsScreen(subRequest: hint()),
      );
      expect(find.text('Private Applicant'), findsOneWidget);
      switch (scenario) {
        case 'logout':
          state.switchUser(null);
        case 'user switch':
          state.switchUser('other');
        case 'ABA user switch':
          state.switchUser('other');
          state.switchUser('manager');
        case 'band switch':
          state.switchBand('other');
        case 'role loss':
          state.service.access.add(false);
        case 'access error':
          state.service.access.addError(StateError('private internal'));
      }
      await tester.pump();
      expect(find.text('Private Applicant'), findsNothing);
      expect(find.text(denied), findsOneWidget);
      await finish(tester, state);
    });
  }
  for (final scenario in ['logout', 'ABA', 'band']) {
    testWidgets(
      '$scenario during authorization prevents full canonical or private reads',
      (tester) async {
        final world = World()..delay = Completer<void>();
        final state = GuardState(GuardService(world));
        await mount(
          tester,
          state,
          SubRequestResponseDetailsScreen(subRequest: hint()),
        );
        if (scenario == 'logout') {
          state.switchUser(null);
        } else if (scenario == 'ABA') {
          state.switchUser('other');
          state.switchUser('manager');
        } else {
          state.switchBand('other');
        }
        world.delay!.complete();
        await pump(tester);
        expect(world.reads, isNot(contains('SubRequests/request')));
        expect(state.service.responseReads, 0);
        expect(state.service.profileReads, 0);
        await finish(tester, state);
      },
    );
  }
  testWidgets(
    'revocation and pending response completion in same turn cannot start profiles',
    (tester) async {
      final service = GuardService(World())
        ..responses = Completer<Map<String, dynamic>>();
      final state = GuardState(service);
      await mount(
        tester,
        state,
        SubRequestResponseDetailsScreen(subRequest: hint()),
      );
      expect(service.responseReads, 1);
      service.access.add(false);
      service.responses!.complete({'applicant': true});
      await pump(tester);
      expect(service.profileReads, 0);
      expect(find.text('Private Applicant'), findsNothing);
      await finish(tester, state);
    },
  );
  testWidgets('ordinary band-owned Map pins absent from management list', (
    tester,
  ) async {
    final world = World();
    world.request['NotificationMode'] = 'map_pin';
    final state = GuardState(GuardService(world));
    await mount(tester, state, const SubRequestResponsesScreen(bandId: 'band'));
    expect(state.service.responseReads, 0);
    expect(find.textContaining('View Responses'), findsNothing);
    await finish(tester, state);
  });
  testWidgets(
    'missing list band denied before feeds or counts; compact Back safe at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = GuardState(GuardService(World()));
      await mount(tester, state, const SubRequestResponsesScreen(bandId: ''));
      expect(find.text(denied), findsOneWidget);
      expect(state.service.feedReads, 0);
      expect(state.service.responseReads, 0);
      await tester.tap(find.text('Back'));
      await pump(tester);
      expect(tester.takeException(), isNull);
      await finish(tester, state);
    },
  );
  testWidgets('request ownership revocation clears list even while band manager remains authorized', (tester) async {
    final service=ListGuardService(World());final state=GuardState(service);
    await mount(tester,state,const SubRequestResponsesScreen(bandId:'band'));
    expect(find.text('View Responses (1)'),findsOneWidget);
    service.ownership.add(false);await tester.pump();
    expect(find.text('View Responses (1)'),findsNothing);
    expect(find.text('Requests are unavailable for your current access. Please try again.'),findsOneWidget);
    await finish(tester,state);
  });
  testWidgets('forged route payload and response cache never replace canonical data', (tester) async {
    final state=GuardState(GuardService(World()));
    final passed=hint().copyWith(bandName:'Forged private band',responses:{'forged_applicant':true});
    await mount(tester,state,SubRequestResponseDetailsScreen(subRequest:passed));
    expect(find.text('Private Applicant'),findsOneWidget);
    expect(find.text('Forged private band'),findsNothing);
    expect(state.service.profileReads,1);expect(state.service.legacyReads,0);
    await finish(tester,state);
  });

  testWidgets('closing detail after logout cannot refresh a disposed management list', (tester) async {
    final state=GuardState(GuardService(World()));
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value:state,child:MaterialApp(
      home:const SubRequestResponsesScreen(bandId:'band'),
      routes:{'/sub-request-response-details':(context)=>Scaffold(body:TextButton(
        onPressed:()=>Navigator.pop(context),child:const Text('Close isolated details')))},
    )));
    await pump(tester);await tester.tap(find.text('View Responses (1)'));await pump(tester);
    expect(find.text('Close isolated details'),findsOneWidget);
    state.switchUser(null);await tester.pump();
    await tester.tap(find.text('Close isolated details'));await pump(tester);
    expect(find.text(denied),findsOneWidget);expect(tester.takeException(),isNull);
    await finish(tester,state);
  });
  testWidgets('ownership loss during delete confirmation prevents mutation', (tester) async {
    final service=ListGuardService(World());final state=GuardState(service);
    await mount(tester,state,const SubRequestResponsesScreen(bandId:'band'));
    await tester.tap(find.byKey(const ValueKey('delete_request_request')));await pump(tester);
    expect(find.text('Confirm Delete'),findsOneWidget);
    service.ownership.add(false);await tester.pump();
    await tester.tap(find.text('Yes'));await pump(tester);
    expect(service.deleteCalls,0);expect(tester.takeException(),isNull);
    await finish(tester,state);
  });

}
