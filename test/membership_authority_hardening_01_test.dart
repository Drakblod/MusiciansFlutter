// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as auth;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/city_location.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/services/city_search_service.dart';
import 'package:musicians_flutter/utils/band_membership_policy.dart';
import 'package:musicians_flutter/utils/membership_mutation_feedback.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/widgets/animated_tap_detector.dart';
import 'package:musicians_flutter/widgets/city_location_picker_field.dart';
import 'registration_secondary_skills_01_test.dart' as fixtures;
import 'new_user_skills_and_band_guards_01_test.dart' as guards;

class AuthorityService extends FirebaseService {
  String? uid = 'leader';
  List<Map<String, dynamic>> calls = [];
  Completer<void>? pending;
  bool fail = false;
  Band band = Band(
    id: 'band',
    name: 'Band',
    membersBand: {
      'leader': BandMember(userId: 'leader', role: 'Leader'),
      'admin': BandMember(userId: 'admin', role: 'Admin'),
      'member': BandMember(userId: 'member', role: 'Member'),
    },
  );
  @override
  String? get currentUserId => uid;
  @override
  Future<void> mutateBandMembershipAsync(Map<String, dynamic> payload) async {
    calls.add(Map.of(payload));
    if (pending != null) await pending!.future;
    if (fail) throw StateError('RAW PRIVATE ERROR');
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? id]) async =>
      UserProfile(userId: id ?? uid, displayName: 'Musician');
  @override
  Future<List<UserProfile>> getAllUsersAsync() async => [];
  @override
  Future<List<BandMember>> getBandMembersAsync(String id) async =>
      band.membersBand.values.toList();
}

class _AuthorityCityProvider implements CitySearchProvider {
  @override
  Future<String> createSession() async => newCitySearchSessionToken();
  @override
  Future<List<CityCandidate>> search(String query, String token) async =>
      [const CityCandidate(placeId:'stockholm-city',city:'Stockholm',country:'Sweden')];
  @override
  Future<CityLocation?> resolve(CityCandidate candidate, String token,
      {required String purpose,required String targetId,
       required String city,required String country}) async =>
      CityLocation.confirmed(city:city,country:country,confirmationNonce:'fake-grant');
}

class DelayedDeletionService extends guards.GuardService {
  final deletion = Completer<void>();
  @override
  Future<void> deleteBandAsync(String bandId) => deletion.future;
  @override
  Future<void> deleteUserAccountAsync() => deletion.future;
}

class DeletionEpochState extends fixtures.SkillState {
  // Preference loading is unrelated to deletion scope; avoid background fixture work.
  @override
  Future<void> loadSelectedBubbles() async {}
  @override
  final DelayedDeletionService service = DelayedDeletionService();
}

class AuthorityState extends Fake with ChangeNotifier implements AppState {
  final service = AuthorityService();
  String? selectedBand = 'band';
  @override
  String? get currentUserId => service.uid;
  @override
  String? get activeBandId => selectedBand;
  @override
  FirebaseService get firebaseService => service;
  @override
  bool get isLoading => false;
  @override
  UserProfile? get currentUserProfile =>
      UserProfile(userId: currentUserId, displayName: 'Musician');
  @override
  bool get hasUnreadMessages => false;
  @override
  int get unreadNotificationCount => 0;
  @override
  Future<void> refreshProfile() async {}
  void switchTo(String? user, String? band) {
    service.uid = user;
    selectedBand = band;
    notifyListeners();
  }
}

Future<void> pump(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mount(
  WidgetTester tester,
  AuthorityState state,
  Widget child,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: child),
    ),
  );
  await pump(tester);
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Widget operationButton(
  AuthorityState state,
  Future<void> Function() operation,
  void Function(bool) done,
) => Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () async => done(
        await MembershipMutationFeedback.run(context, 'band', operation),
      ),
      child: const Text('Update membership'),
    ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() {
    auth.FirebaseAuthPlatform.instance = fixtures.GateAuthPlatform();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('Canonical client manager policy', () {
    for (final role in ['Leader', 'Admin', ' LEADER ', ' admin ']) {
      for (final status in [null, 'active', 'on_hold', 'temporarily_off']) {
        test('$role with $status retains active-access manager actions', () {
          final band = Band(
            id: 'band',
            name: 'Band',
            membersBand: {'self': BandMember(role: role, status: status)},
          );
          expect(BandMembershipPolicy.canStaff(band, 'self'), isTrue);
          expect(band.canUserEdit('self'), isTrue);
        });
      }
    }
    for (final role in ['Member', 'MOD', 'SuperAdmin', 'Leader helper', '']) {
      test('$role is not an exact management role', () {
        expect(
          BandMembershipPolicy.canManageMember(BandMember(role: role)),
          isFalse,
        );
      });
    }
    for (final status in [
      'inactive',
      'removed',
      'pending',
      'archived',
      'excluded',
      'unknown',
      '',
    ]) {
      test('Leader with $status has no manager actions', () {
        expect(
          BandMembershipPolicy.canManageMember(
            BandMember(role: 'Leader', status: status),
          ),
          isFalse,
        );
      });
    }
    test(
      'legacy band UserRole cannot grant privileges without canonical membership',
      () {
        expect(
          Band(
            id: 'band',
            name: 'Band',
            userRole: 'Leader',
          ).canUserEdit('outsider'),
          isFalse,
        );
      },
    );
  });
  test('nickname and legacy UserRole cannot grant Leader ownership', () {
    final band = Band(
      id: 'band',
      name: 'Band',
      userRole: 'Leader',
      membersBand: {'self': BandMember(role: 'Member', nickname: 'Leader')},
    );
    expect(band.isUserLeader('self'), isFalse);
    expect(band.isUserLeader('other'), isFalse);
  });
  group('Production membership service callable cutover', () {
    test(
      'Create Band submits one atomic creation and initial roster',
      () async {
        final service = AuthorityService();
        await service.createBandAsync(
          'leader',
          Band(
            name: 'New Band',
            membersBand: {'member': BandMember(role: 'Member')},
          ),
        );
        expect(service.calls, hasLength(1));
        expect(service.calls.single['action'], 'create');
        expect(service.calls.single['bandId'], 'New_Band');
        expect(service.calls.single['initialMembers'], [
          {'userId': 'member', 'role': 'Member', 'nickname': 'Member'},
        ]);
        expect(service.calls.single.containsKey('callerUid'), isFalse);
      },
    );
    test('cannot create Band for a different client user', () async {
      final service = AuthorityService();
      await expectLater(
        service.createBandAsync('other', Band(name: 'Band')),
        throwsStateError,
      );
      expect(service.calls, isEmpty);
    });
    test('Add Member uses a single membership callable', () async {
      final service = AuthorityService();
      await service.addBandMemberAsync('band', 'member', 'Member', 'Musician');
      expect(service.calls.single['action'], 'add');
      expect(service.calls.single['userId'], 'member');
    });
    test('role and status updates use scoped callable payloads', () async {
      final service = AuthorityService();
      await service.updateBandMemberRoleAsync('band', 'member', 'Admin');
      await service.updateBandMemberStatusAsync('band', 'member', 'on_hold');
      expect(service.calls.map((x) => x['action']), ['role', 'status']);
      expect(
        service.calls.every(
          (x) => x['bandId'] == 'band' && x['userId'] == 'member',
        ),
        isTrue,
      );
    });
    test('Leader transfer is one call, never demote then promote', () async {
      final service = AuthorityService();
      await service.updateBandMemberRoleAsync('band', 'member', 'Leader');
      expect(service.calls, hasLength(1));
      expect(service.calls.single['action'], 'transfer');
    });
    test('remove and self leave have distinct server operations', () async {
      final service = AuthorityService();
      await service.removeBandMemberAsync('band', 'member');
      await service.removeBandMemberAsync('band', 'leader');
      await service.leaveBandAsync('band');
      expect(service.calls.map((x) => x['action']), [
        'remove',
        'leave',
        'leave',
      ]);
    });
    test('retry after uncertain failure reuses operation ID', () async {
      final service = AuthorityService()..fail = true;
      await expectLater(
        service.updateBandMemberRoleAsync('band', 'member', 'Admin'),
        throwsStateError,
      );
      service.fail = false;
      await service.updateBandMemberRoleAsync('band', 'member', 'Admin');
      expect(service.calls[0]['operationId'], service.calls[1]['operationId']);
    });
    test('late user-switched result is rejected', () async {
      final service = AuthorityService()..pending = Completer<void>();
      final action = service.addBandMemberAsync(
        'band',
        'member',
        'Member',
        'Member',
      );
      final expectation = expectLater(action, throwsStateError);
      service.uid = 'other';
      service.pending!.complete();
      await expectation;
    });
    test(
      'membership operations contain no direct protected database writes or deletion fallback',
      () {
        final source = File(
          'lib/services/firebase_service.dart',
        ).readAsStringSync();
        final create = source.substring(
          source.indexOf('Future<void> createBandAsync'),
          source.indexOf('Future<List<BandMember>> getBandMembersAsync'),
        );
        final updates = source.substring(
          source.indexOf('Future<void> addBandMemberAsync'),
          source.indexOf('Future<void> postGigsNewsAsync'),
        );
        expect(create.contains('_dbRef'), isFalse);
        expect(updates.contains('_dbRef'), isFalse);
        expect(source.contains('_deleteUserAccountFallback'), isFalse);
        expect(source.contains('_deleteBandFallback'), isFalse);
      },
    );
  });
  group('Session-safe mutation feedback', () {
    testWidgets('loading is visible and completion is not optimistic', (
      tester,
    ) async {
      final state = AuthorityState();
      final pending = Completer<void>();
      bool? result;
      await mount(
        tester,
        state,
        operationButton(state, () => pending.future, (v) => result = v),
      );
      await tester.tap(find.text('Update membership'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(result, isNull);
      pending.complete();
      await pump(tester);
      expect(result, isTrue);
      await unmount(tester);
    });
    testWidgets('failure displays safe error without false success', (
      tester,
    ) async {
      final state = AuthorityState();
      bool? result;
      await mount(
        tester,
        state,
        operationButton(
          state,
          () async => throw StateError('PRIVATE RAW ERROR'),
          (v) => result = v,
        ),
      );
      await tester.tap(find.text('Update membership'));
      await pump(tester);
      expect(result, isFalse);
      expect(
        find.text('Could not update band membership. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE RAW ERROR'), findsNothing);
      await unmount(tester);
    });
    testWidgets('duplicate activation issues one server operation', (
      tester,
    ) async {
      final state = AuthorityState();
      final pending = Completer<void>();
      var calls = 0;
      await mount(
        tester,
        state,
        operationButton(state, () {
          calls++;
          return pending.future;
        }, (_) {}),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(calls, 1);
      pending.complete();
      await pump(tester);
      await unmount(tester);
    });
    for (final change in ['user', 'band', 'logout']) {
      testWidgets('$change change dismisses progress and rejects late result', (
        tester,
      ) async {
        final state = AuthorityState();
        final pending = Completer<void>();
        bool? result;
        await mount(
          tester,
          state,
          operationButton(state, () => pending.future, (v) => result = v),
        );
        await tester.tap(find.text('Update membership'));
        await tester.pump();
        state.switchTo(
          change == 'logout'
              ? null
              : change == 'user'
              ? 'other'
              : 'leader',
          change == 'band' ? 'other_band' : 'band',
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        pending.complete();
        await pump(tester);
        expect(result, isFalse);
        await unmount(tester);
      });
    }
    testWidgets('mismatching selected band prevents server invocation', (
      tester,
    ) async {
      final state = AuthorityState()..selectedBand = 'other_band';
      var calls = 0;
      await mount(
        tester,
        state,
        operationButton(state, () async {
          calls++;
        }, (_) {}),
      );
      await tester.tap(find.text('Update membership'));
      await pump(tester);
      expect(calls, 0);
      await unmount(tester);
    });
    testWidgets(
      'A to B to A rejects the first result and does not unlock the new operation',
      (tester) async {
        final state = AuthorityState();
        final first = Completer<void>(), second = Completer<void>();
        final results = <bool>[];
        var calls = 0;
        await mount(
          tester,
          state,
          operationButton(state, () {
            calls++;
            return calls == 1 ? first.future : second.future;
          }, results.add),
        );
        final button = tester.widget<TextButton>(find.byType(TextButton));
        button.onPressed!();
        await tester.pump();
        state.switchTo('leader', 'other_band');
        state.switchTo('leader', 'band');
        await tester.pump();
        button.onPressed!();
        await tester.pump();
        expect(calls, 2);
        first.complete();
        await pump(tester);
        expect(results, [false]);
        button.onPressed!();
        await tester.pump();
        expect(calls, 2);
        second.complete();
        await pump(tester);
        expect(results.last, isTrue);
        await unmount(tester);
      },
    );
    testWidgets('320 px feedback has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AuthorityState();
      await mount(
        tester,
        state,
        operationButton(state, () async => throw StateError('failure'), (_) {}),
      );
      await tester.tap(find.text('Update membership'));
      await pump(tester);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
  group('Provider deletion session ownership', () {
    testWidgets(
      'failed account deletion preserves the profile and propagates failure',
      (tester) async {
        final state = DeletionEpochState();
        await tester.pumpWidget(const SizedBox.shrink());
        await pump(tester);
        await state.refreshProfile();
        await pump(tester);
        final pending = state.deleteCurrentAccount();
        final rejected = expectLater(pending, throwsStateError);
        state.service.deletion.completeError(
          StateError('Server deletion failed'),
        );
        await rejected;
        expect(state.currentUserProfile?.userId, 'a');
        expect(state.isLoading, isFalse);
        await pump(tester);
        state.dispose();
      },
    );
    testWidgets(
      'late account deletion cannot clear a newly signed-in user profile',
      (tester) async {
        final state = DeletionEpochState();
        await tester.pumpWidget(const SizedBox.shrink());
        await pump(tester);
        await state.refreshProfile();
        await pump(tester);
        final pending = state.deleteCurrentAccount();
        final rejected = expectLater(pending, throwsStateError);
        await state.login('b@example.com', 'test-password');
        expect(state.currentUserProfile?.userId, 'b');
        state.service.deletion.complete();
        await rejected;
        expect(state.currentUserId, 'b');
        expect(state.currentUserProfile?.userId, 'b');
        expect(state.isLoading, isFalse);
        await pump(tester);
        state.dispose();
      },
    );
    testWidgets('account A to B to A rejects an old deletion result by epoch', (
      tester,
    ) async {
      final state = DeletionEpochState();
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester);
      await state.refreshProfile();
      await pump(tester);
      final pending = state.deleteCurrentAccount();
      final rejected = expectLater(pending, throwsStateError);
      await state.login('b@example.com', 'test-password');
      await state.login('a@example.com', 'test-password');
      state.service.deletion.complete();
      await rejected;
      expect(state.currentUserProfile?.userId, 'a');
      expect(state.isLoading, isFalse);
      await pump(tester);
      state.dispose();
    });
    testWidgets(
      'Band A to B to A rejects an old deletion and releases only its own loading state',
      (tester) async {
        final state = DeletionEpochState();
        await tester.pumpWidget(const SizedBox.shrink());
        await pump(tester);
        state.service.bands.addAll({
          'one': guards.realBand(id: 'one'),
          'two': guards.realBand(id: 'two'),
        });
        await state.refreshProfile();
        await pump(tester);
        await state.refreshBandMemberships();
        state.selectBand('one', 'One');
        final pending = state.deleteBand('one');
        final rejected = expectLater(pending, throwsStateError);
        state.selectBand('two', 'Two');
        state.selectBand('one', 'One');
        state.service.deletion.complete();
        await rejected;
        expect(state.activeBandId, 'one');
        expect(state.isLoading, isFalse);
        await pump(tester);
        state.dispose();
      },
    );
  });
  group('Membership UI', () {
    for (final who in ['leader', 'admin', 'member']) {
      testWidgets('$who has correct Add Member actions', (tester) async {
        final state = AuthorityState();
        state.service.uid = who;
        await mount(
          tester,
          state,
          EditBandInfoScreen(band: state.service.band),
        );
        expect(
          find.text('Add Band Member'),
          who == 'member' ? findsNothing : findsWidgets,
        );
        expect(
          find.text('Save Changes'),
          who == 'member' ? findsNothing : findsOneWidget,
        );
        await unmount(tester);
      });
    }
    for (final who in ['leader', 'member']) {
      testWidgets('320 px edit membership controls for $who have no overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AuthorityState();
        state.service.uid = who;
        await mount(
          tester,
          state,
          EditBandInfoScreen(band: state.service.band),
        );
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
    testWidgets('inactive Leader has no Add Member action', (tester) async {
      final state = AuthorityState();
      state.service.band = Band(
        id: 'band',
        name: 'Band',
        membersBand: {
          'leader': BandMember(
            userId: 'leader',
            role: 'Leader',
            status: 'inactive',
          ),
        },
      );
      await mount(tester, state, EditBandInfoScreen(band: state.service.band));
      expect(find.text('Add Band Member'), findsNothing);
      await unmount(tester);
    });
    testWidgets('320 px Create Band form has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, AuthorityState(), const CreateBandScreen());
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
    testWidgets('Create Band screen calls server and waits before success', (
      tester,
    ) async {
      final state = AuthorityState();
      state.service.pending = Completer<void>();
      await mount(tester, state, CitySearchProviderScope(
        provider:_AuthorityCityProvider(),child:const CreateBandScreen()));
      final fields = find.byType(TextFormField);
      for (final f in tester.widgetList<TextFormField>(fields)) {
        if (f.validator?.call('') == 'Please enter a band name')
          f.controller!.text = 'Local Band';
      }
      final cityField=find.descendant(of:find.byType(CityLocationPickerField),
        matching:find.byType(TextFormField));
      await tester.ensureVisible(cityField);
      await tester.enterText(cityField,'Stock');
      await tester.pump(const Duration(milliseconds:350));
      await tester.pump();
      await tester.ensureVisible(find.text('Stockholm'));
      await tester.tap(find.text('Stockholm'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField,'City'),'Stockholm');
      await tester.enterText(find.widgetWithText(TextField,'Country'),'Sweden');
      await tester.tap(find.text('Confirm city'));
      await tester.pump();
      final save = find.ancestor(
        of: find.text('Save Band'),
        matching: find.byType(AnimatedTapDetector),
      );
      tester.widget<AnimatedTapDetector>(save).onTap();
      await tester.pump();
      expect(state.service.calls.single['action'], 'create');
      expect(find.text('Band created successfully!'), findsNothing);
      state.service.pending!.complete();
      await pump(tester);
      await unmount(tester);
    });
  });
}
