// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart' as auth_platform;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/profile_tab_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'new_user_skills_and_band_guards_01_test.dart' as guards;
import 'registration_secondary_skills_01_test.dart' as base;
import 'band_member_hold_test.dart' as hold;

/// Logs the IO boundary used by the real FirebaseService membership reader.
class ReadSpy {
  final Map<String, Object?> data = {};
  final List<String> reads = [];
  final List<String> writes = [];
  String? failedPath;
  Completer<void>? gate;

  Future<Object?> read(String path) async {
    reads.add(path);
    if (path == 'Bands') throw StateError('Forbidden full /Bands read');
    if (path == failedPath) throw StateError('Read failed');
    await gate?.future;
    if (data.containsKey(path)) return data[path];
    final parts = path.split('/');
    for (var end = parts.length - 1; end > 0; end--) {
      final prefix = parts.take(end).join('/');
      if (!data.containsKey(prefix)) continue;
      Object? value = data[prefix];
      for (final segment in parts.skip(end)) {
        if (value is! Map) return null;
        value = value[segment];
      }
      return value;
    }
    return null;
  }

  void band(String id, {String uid = 'a', String role = 'Leader', String? name}) {
    data['Bands/$id'] = {
      'Name': name ?? 'Canonical $id',
      'Members_band': {uid: {'Role': role, 'Nickname': 'Fixture member'}},
    };
  }
  void index(String uid, List<String> ids) {
    data['users/$uid/Bands'] = {for (final id in ids) id: {'Name': 'Untrusted cached name'}};
  }
  void clearLog() { reads.clear(); writes.clear(); }
}

class PerformanceService extends guards.GuardService {
  final ReadSpy spy = ReadSpy();
  late final FirebaseService reader = FirebaseService(membershipRead: spy.read);

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) => reader.getUserBandsAsync(userId);
  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    final raw = await spy.read('Bands/$bandId');
    return raw is Map ? Band.fromJson(raw, bandId) : null;
  }
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    final id = userId ?? uid;
    await spy.read('users/$id');
    return UserProfile(userId: id, displayName: 'Performance user', email: 'fixture@example.com');
  }
  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async {
    await spy.read('users/$userId/metrics/buttonClicks');
    return {};
  }
  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    await spy.read('users/$uid/Favorites');
    return [];
  }
  @override
  Future<List<UserProfile>> getAllUsersAsync() async { await spy.read('users'); return []; }
  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async {
    await spy.read('creatorSubRequestFeed/$userId'); return [];
  }
  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async {
    final raw = await spy.read('Bands/$bandId/Members_band');
    return raw is Map ? [for (final e in raw.entries) if (e.value is Map)
      BandMember.fromJson(e.value as Map, e.key.toString())] : [];
  }
  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async {
    await spy.read('files/$bandId'); return {};
  }
}
class PerformanceState extends guards.GuardState {
  @override
  final PerformanceService service = PerformanceService();
}
List<String> discoveryPaths(String uid, List<String> ids) => [
  'users/$uid/Bands',
  for (final id in ids) ...[
    'Bands/$id/Members_band/$uid', 'Bands/$id/Name', 'Bands/$id/isMock', 'Bands/$id/isDemo',
  ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    auth_platform.FirebaseAuthPlatform.instance = base.GateAuthPlatform();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final count in [0, 1, 3]) {
    test('discovery of $count bands reads only index and canonical candidate fields', () async {
      final service = PerformanceService();
      final ids = List.generate(count, (i) => 'band_$i');
      service.spy.index('a', ids);
      for (final id in ids) { service.spy.band(id); }
      expect(await service.getUserBandsAsync('a'), {for (final id in ids) id: 'Canonical $id'});
      expect(service.spy.reads, discoveryPaths('a', ids));
      expect(service.spy.reads, hasLength(1 + 4 * count));
      expect(service.spy.writes, isEmpty);
      expect(service.writes, 0);
    });
  }
  test('fabricated index entry cannot authorize an unrelated canonical member', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['foreign']);
    state.service.spy.band('foreign', uid: 'b');
    expect(await state.resolveAuthorizedBand('foreign'), isNull);
    expect(state.activeBandId, isNull);
    expect(state.service.spy.reads, ['users/a/Bands', 'Bands/foreign/Members_band/a']);
  });
  test('stale deleted-band index entry is rejected without metadata reads', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['deleted']);
    expect(await state.resolveAuthorizedBand('deleted'), isNull);
    expect(state.service.spy.reads, ['users/a/Bands', 'Bands/deleted/Members_band/a']);
  });
  test('unindexed canonical membership is not recovered through a root scan', () async {
    final state = PerformanceState();
    state.service.spy.band('unindexed');
    expect(await state.resolveAuthorizedBand('unindexed'), isNull);
    expect(state.service.spy.reads, ['users/a/Bands']);
  });
  test('membership discovery and verification write nothing including stale entries', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid', 'stale']);
    state.service.spy.band('valid');
    expect(await state.resolveAuthorizedBand('valid', requireManager: true), isNotNull);
    expect(state.service.spy.writes, isEmpty);
    expect(state.service.writes, 0);
  });
  testWidgets('concurrent checks share one authenticated discovery and band verification', (tester) async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    state.service.spy.gate = Completer<void>();
    final first = state.resolveAuthorizedBand('valid');
    final second = state.resolveAuthorizedBand('valid');
    state.service.spy.gate!.complete();
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    expect(state.service.spy.reads.where((path) => path == 'users/a/Bands'), hasLength(1));
    expect(state.service.spy.reads.where((path) => path == 'Bands/valid/Members_band/a'), hasLength(1));
    expect(state.service.spy.reads.where((path) => path == 'Bands/valid'), hasLength(1));
  });
  test('cached A membership cannot authorize B using a fabricated index name', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    await state.refreshBandMemberships();
    state.service.uid = 'b';
    expect(state.activeBandId, isNull);
    state.service.spy.index('b', ['valid']);
    expect(await state.resolveAuthorizedBand('valid'), isNull);
    expect(state.activeBandId, isNull);
  });
  test('logout clears authorization and prevents another membership read', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    await state.refreshBandMemberships();
    final logout = state.logout();
    expect(state.activeBandId, isNull);
    await logout;
    state.service.spy.clearLog();
    expect(await state.refreshBandMemberships(), isEmpty);
    expect(state.service.spy.reads, isEmpty);
  });
  testWidgets('user switch invalidates the prior verified index cache', (tester) async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    await state.refreshBandMemberships();
    state.service.spy.clearLog();
    await state.login('b@example.com', 'test-password');
    expect(state.activeBandId, isNull);
    expect(state.service.spy.reads.where((path) => path.endsWith('/Bands')), ['users/b/Bands']);
  });
  test('failed canonical refresh clears previously selected authorization', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    await state.refreshBandMemberships();
    state.service.spy.failedPath = 'Bands/valid/Members_band/a';
    await expectLater(state.refreshBandMemberships(), throwsStateError);
    expect(state.activeBandId, isNull);
    expect(state.activeBandName, isNull);
  });
  test('canonical member removal revokes access despite a retained index', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    expect(await state.resolveAuthorizedBand('valid'), isNotNull);
    state.service.spy.data['Bands/valid/Members_band/a'] = null;
    await state.refreshBandMemberships();
    expect(state.activeBandId, isNull);
    expect(await state.resolveAuthorizedBand('valid'), isNull);
  });
  test('Leader to Member revokes staffing while retaining ordinary Band Room membership', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid');
    expect(await state.resolveAuthorizedBand('valid', requireManager: true), isNotNull);
    state.service.spy.band('valid', role: ' Member ');
    expect(await state.resolveAuthorizedBand('valid', requireManager: true), isNull);
    expect(await state.resolveAuthorizedBand('valid'), isNotNull);
  });
  test('canonical name replaces an untrusted index copy', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid', name: 'Actual canonical name');
    await state.refreshBandMemberships();
    expect(state.activeBandName, 'Actual canonical name');
    expect(state.activeBandName, isNot('Untrusted cached name'));
  });
  testWidgets('direct routes reject fabricated index access before loading their content', (tester) async {
    await guards.size(tester);
    final state = PerformanceState();
    state.service.spy.index('a', ['foreign']);
    state.service.spy.band('foreign', uid: 'b');
    await tester.pumpWidget(guards.app(state, const FindSubScreen(bandId: 'foreign')));
    await guards.settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
    expect(state.service.writes, 0);
    expect(state.service.spy.reads, isNot(contains('Bands')));
  });
  test('placeholder, mock and demo IDs never cause canonical reads', () async {
    final service = PerformanceService();
    service.spy.index('a', ['', 'mock_band', 'demo-band', 'mock', 'freelance', 'standalone', 'null', '../other']);
    expect(await service.getUserBandsAsync('a'), isEmpty);
    expect(service.spy.reads, ['users/a/Bands']);
  });
  test('canonical mock marker rejects an otherwise valid candidate', () async {
    final service = PerformanceService();
    service.spy.index('a', ['valid']);
    service.spy.band('valid');
    service.spy.data['Bands/valid/isMock'] = true;
    expect(await service.getUserBandsAsync('a'), isEmpty);
  });
  test('role matching is trimmed and case-insensitive but exact', () async {
    final state = PerformanceState();
    state.service.spy.index('a', ['valid']);
    state.service.spy.band('valid', role: '  aDmIn ');
    expect(await state.resolveAuthorizedBand('valid', requireManager: true), isNotNull);
    state.service.spy.band('valid', role: 'NotAnAdmin');
    expect(await state.resolveAuthorizedBand('valid', requireManager: true), isNull);
  });

  test('legacy UI authorization fake rejects foreign route arguments', () async {
    final state = hold.MockAppStateForHoldTest();
    expect(await state.resolveAuthorizedBand('foreign', requireManager: true), isNull);
    expect(await state.resolveAuthorizedBand('band_123', requireManager: true), isNotNull);
  });
  test('legacy UI authorization fake denies removed membership despite UserRole Leader', () async {
    final state = hold.MockAppStateForHoldTest();
    (state.mockFirebase.mockBandData['Members_band'] as Map).remove('user_leader');
    expect(await state.resolveAuthorizedBand('band_123'), isNull);
    expect(await state.resolveAuthorizedBand('band_123', requireManager: true), isNull);
  });

  // Exact, deterministic point-read matrix for normal navigation. Streaming
  // notifications/event subscriptions are fixed empty by the existing fakes.
  for (final scenario in ['login-none', 'login-one', 'login-several', 'profile',
      'band-room', 'find-musician', 'switch-user', 'after-removal',
      'home-band-room', 'home-find-musician']) {
    testWidgets('read matrix $scenario has no full /Bands root read or writes', (tester) async {
      await guards.size(tester);
      final state = PerformanceState();
      final spy = state.service.spy;
      final ids = scenario == 'login-none' || scenario == 'profile' ? <String>[] :
        scenario == 'login-several' ? ['one', 'two', 'three'] : ['one'];
      spy.index('a', ids);
      for (final id in ids) { spy.band(id); }
      if (scenario.startsWith('login-')) {
        await state.login('a@example.com', 'test-password');
        expect(spy.reads, ['users/a', 'users/a/metrics/buttonClicks', ...discoveryPaths('a', ids)]);
      } else if (scenario == 'switch-user') {
        await state.refreshBandMemberships();
        spy.clearLog();
        await state.login('b@example.com', 'test-password');
        expect(spy.reads, ['users/b', 'users/b/metrics/buttonClicks', 'users/b/Bands']);
      } else if (scenario == 'after-removal') {
        await state.refreshBandMemberships();
        spy.data['Bands/one/Members_band/a'] = null;
        spy.clearLog();
        await state.refreshBandMemberships();
        expect(spy.reads, ['users/a/Bands', 'Bands/one/Members_band/a']);
      } else {
        // Warm initial auth load before measuring the subsequent opening.
        await tester.pumpWidget(guards.app(state, const SizedBox()));
        await guards.settle(tester);
        spy.clearLog();
        if (scenario.startsWith('home-')) {
          await tester.pumpWidget(guards.app(state, const HomeScreen()));
          await guards.settle(tester);
          final label = scenario == 'home-band-room' ? 'Band Room' : 'Find\nMusician/Vocalist';
          await tester.ensureVisible(find.text(label).first);
          await tester.tap(find.text(label).first);
        } else if (scenario == 'profile') {
          await tester.pumpWidget(guards.app(state, const ProfileTabScreen()));
        } else if (scenario == 'band-room') {
          await tester.pumpWidget(guards.app(state, const BandRoomChatScreen()));
        } else {
          await tester.pumpWidget(guards.app(state, const FindSubScreen()));
        }
        await guards.settle(tester);
        if (scenario == 'profile') {
          expect(spy.reads, ['users/a/Favorites', 'users']);
          expect(find.text('No active band'), findsOneWidget);
        } else if (scenario == 'band-room' || scenario == 'home-band-room') {
          expect(spy.reads, [
            if (scenario.startsWith('home-')) ...discoveryPaths('a', ['one']),
            ...discoveryPaths('a', ['one']),
            'Bands/one', 'Bands/one', 'Bands/one/Members_band', 'files/one', 'users/a']);
        } else {
          expect(spy.reads, [
            if (scenario.startsWith('home-')) ...[...discoveryPaths('a', ['one']), 'creatorSubRequestFeed/a'],
            ...discoveryPaths('a', ['one']),
            'Bands/one', 'users/a/Favorites', 'users', 'Bands/one', 'creatorSubRequestFeed/a']);
        }
      }
      expect(spy.reads, isNot(contains('Bands')));
      expect(spy.writes, isEmpty);
      expect(state.service.writes, 0);
      print('MEMBERSHIP_READ_MATRIX=' + jsonEncode({'scenario': scenario,
        'reads': spy.reads, 'getCount': spy.reads.length, 'writes': spy.writes.length}));
    });
  }
}
