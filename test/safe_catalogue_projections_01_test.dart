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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/utils/catalogue_profiles.dart';
import 'package:musicians_flutter/utils/catalogue_loading.dart';
import 'package:musicians_flutter/views/browse_musicians_screen.dart';
import 'package:musicians_flutter/views/producer_search_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/views/create_event_page.dart';
import 'create_event_edit_members_test.dart' as event_fixtures;
import 'registration_secondary_skills_01_test.dart' as fixtures;
import 'membership_authority_hardening_01_test.dart' as authority;

class CatalogueService extends FirebaseService {
  @override
  Stream<bool> subscribeToBandProfileAccess(String bandId) => Stream.value(true);

  CatalogueService(Future<Object?> Function(String) read)
    : super(catalogueRead: read);
  String? uid = 'a';
  final identities = StreamController<String?>.broadcast(sync: true);
  @override
  String? get currentUserId => uid;
  @override
  Stream<String?> get catalogueIdentityChanges => identities.stream;
  void switchTo(String? next) {
    uid = next;
    identities.add(next);
  }
}

class UiService extends authority.AuthorityService {
  final paths = <String>[];
  Completer<Object?>? pending;
  Object? users = {
    'visible': {
      'DisplayName': 'Visible musician',
      'UserType': 'Guitar',
      'Instruments': ['Guitar', 'Piano'],
      'Genres': ['Jazz'],
    },
  };
  Object? bands = {
    'public_band': {'Name': 'Public band', 'activeMemberCount': 3},
  };
  late final transport = CatalogueService((path) async {
    paths.add(path);
    return pending != null
        ? await pending!.future
        : path == 'publicUserProfiles'
        ? users
        : bands;
  });
  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];
  @override
  Future<List<UserProfile>> getAllUsersAsync() => transport.getAllUsersAsync();
  @override
  Future<List<Band>> getAllBandsAsync() => transport.getAllBandsAsync();
}

class CatalogueState extends authority.AuthorityState {
  final catalogue = UiService();
  @override
  FirebaseService get firebaseService => catalogue;
  @override
  String? get currentUserId => catalogue.transport.uid;
  void change(String? id, String? band) {
    catalogue.transport.switchTo(id);
    selectedBand = band;
    notifyListeners();
  }
}

class EventCatalogueService extends event_fixtures.MockFirebaseService {
  final paths = <String>[];
  late final transport = CatalogueService((path) async {
    paths.add(path);
    return {
      'u4': {
        'DisplayName': 'Dave Bass',
        'Nickname': 'Stage Dave',
        'UserType': 'Bass',
        'Instruments': ['Bass', 'Piano'],
        'Location': 'Stockholm',
        'Email': 'private-only@example.test',
      },
    };
  })..uid = 'u1';
  @override
  Future<List<UserProfile>> getAllUsersAsync() => transport.getAllUsersAsync();
}

class EventCatalogueState extends event_fixtures.MockAppState {
  final catalogue = EventCatalogueService();
  @override
  FirebaseService get firebaseService => catalogue;
  @override
  String? get activeBandId => 'band_1';
}

Future<void> mount(
  WidgetTester tester,
  CatalogueState state,
  Widget child,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: child),
    ),
  );
  await authority.pump(tester);
  await authority.pump(tester);
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

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
  test(
    'compatibility entry points use only safe roots and retain all 251 IDs',
    () async {
      final paths = <String>[];
      final service = CatalogueService((path) async {
        paths.add(path);
        return {
          for (var i = 0; i < 251; i++)
            'id$i': path == 'publicUserProfiles'
                ? {'DisplayName': 'Person $i'}
                : {'Name': 'Band $i', 'activeMemberCount': i},
        };
      });
      final users = await service.getAllUsersAsync(),
          bands = await service.getAllBandsAsync();
      expect(users.length, 251);
      expect(bands.length, 251);
      expect(users.map((u) => u.userId).toSet().length, 251);
      expect(bands.last.id, 'id250');
      expect(paths, ['publicUserProfiles', 'publicBandProfiles']);
    },
  );
  test(
    'nonowner profile loading uses safe leaf and drops injected private fields',
    () async {
      final paths = <String>[];
      final service = CatalogueService((path) async {
        paths.add(path);
        return {
          'DisplayName': 'Public',
          'Email': 'secret',
          'Contact': 'secret',
          'Bands': {'secret': true},
        };
      });
      final profile = await service.getUserProfileAsync('other');
      expect(paths, ['publicUserProfiles/other']);
      expect(profile!.userId, 'other');
      expect(profile.email, isNull);
      expect(profile.contact, isNull);
    },
  );
  test(
    'safe band leaf preserves count without fake membership authority',
    () async {
      final service = CatalogueService(
        (_) async => {
          'Name': 'Public',
          'activeMemberCount': 9,
          'Members_band': {
            'a': {'Role': 'Leader'},
          },
          'Events': {'secret': true},
        },
      );
      final band = await service.getPublicBandProfileAsync('b');
      expect(band!.activeMemberCount, 9);
      expect(band.membersBand, isEmpty);
      expect(band.isUserLeader('a'), isFalse);
    },
  );
  for (final value in [null, 7, 'invalid', true, []])
    test('malformed catalogue $value is harmless', () {
      expect(CatalogueProfiles.users(value), isEmpty);
      expect(CatalogueProfiles.bands(value), isEmpty);
    });
  test('malformed children optional fields and ID conflicts fail safely', () {
    final users = CatalogueProfiles.users({
      'good': {
        'userId': 'forged',
        'DisplayName': {},
        'Instruments': [7, 'Piano'],
      },
      'bad': 'invalid',
      'bad/id': {},
    });
    expect(users.length, 1);
    expect(users.single.userId, 'good');
    expect(users.single.displayName, isNull);
    expect(users.single.instruments, ['Piano']);
    expect(
      CatalogueProfiles.band('b', {'activeMemberCount': -1})!.activeMemberCount,
      isNull,
    );
  });
  test('primary and secondary skills remain searchable without duplicates', () {
    final user = CatalogueProfiles.user('u', {
      'UserType': 'Guitar',
      'Instruments': ['Guitar', ' Piano ', 'piano'],
    })!;
    expect(user.primarySkill, 'Guitar');
    expect(user.secondarySkills, ['Piano']);
    expect(user.matchingSkills.contains('Piano'), isTrue);
  });
  test(
    'numeric RTDB arrays retain identities and duplicate decoded IDs collapse deterministically',
    () {
      expect(
        CatalogueProfiles.users([
          null,
          {'DisplayName': 'Numeric'},
        ]).single.userId,
        '1',
      );
      final users = CatalogueProfiles.users({
        1: {'DisplayName': 'First'},
        '1': {'DisplayName': 'Second'},
      });
      expect(users.length, 1);
      expect(users.single.displayName, 'First');
    },
  );
  test(
    'approved invite search preserves public matching and never matches private email',
    () {
      final profile = UserProfile(
        userId: 'u',
        displayName: 'Public Name',
        nickname: 'Stage Nick',
        userType: 'Guitar',
        instruments: ['Guitar', 'Piano'],
        location: 'Stockholm',
        email: 'private-only@example.test',
      );
      for (final query in [
        'public name',
        'stage nick',
        'guitar',
        'piano',
        'stockholm',
        '',
      ]) {
        expect(CatalogueProfiles.matchesUserQuery(profile, query), isTrue);
      }
      expect(
        CatalogueProfiles.matchesUserQuery(
          profile,
          'private-only@example.test',
        ),
        isFalse,
      );
      final picker = File(
        'lib/views/create_event_page.dart',
      ).readAsStringSync();
      expect(picker, contains('CatalogueProfiles.matchesUserQuery(u, query)'));
      expect(picker.contains('email.contains(query)'), isFalse);
    },
  );
  test('absent fields are omitted and no personal defaults are fabricated', () {
    final user = CatalogueProfiles.user('u', {})!;
    expect(user.displayName, isNull);
    expect(user.location, isNull);
    expect(user.email, isNull);
    expect(user.about, isNull);
    expect(user.instruments, isEmpty);
  });
  for (final switchBack in [false, true])
    test(
      'service rejects stale account result, return to original=$switchBack',
      () async {
        final gate = Completer<Object?>();
        final service = CatalogueService((_) => gate.future);
        final read = service.getAllUsersAsync();
        final rejected = expectLater(read, throwsStateError);
        service.switchTo('b');
        if (switchBack) service.switchTo('a');
        gate.complete({
          'other': {'DisplayName': 'Stale'},
        });
        await rejected;
      },
    );
  testWidgets(
    'scope permanently cancels account and selected-band round trips',
    (tester) async {
      final state = CatalogueState();
      await mount(tester, state, const SizedBox.shrink());
      final scope = CatalogueScope(state);
      state.change('b', 'other');
      state.change('a', 'band');
      expect(scope.current, isFalse);
      scope.dispose();
      await unmount(tester);
    },
  );
  for (final file in [
    'create_band_screen.dart',
    'edit_band_info_screen.dart',
    'band_room_chat_screen.dart',
    'create_event_page.dart',
  ])
    test('$file picker wiring uses scoped safe catalogue loader', () {
      final code = File('lib/views/$file').readAsStringSync();
      expect(code, contains('CatalogueLoading.usersForPicker(context)'));
      expect(code.contains("_dbRef('users')"), isFalse);
    });
  test(
    'own-profile service path stays owner-specific and separate from public lookup',
    () {
      final code = File(
        'lib/services/firebase_service.dart',
      ).readAsStringSync();
      expect(
        code,
        contains(
          'if (targetId != currentUserId) return getPublicUserProfileAsync(targetId);',
        ),
      );
      expect(code, isNot(contains("_dbRef('users/\$targetId').get()")));
      expect(code, contains("const fields = ['info', 'UserType', 'Nickname', 'DisplayName'];"));
      expect(code, contains("_dbRef('users/\$targetId/\$field').get()"));
    },
  );
  test(
    'discovery transport introduces no users/Bands root reads or listeners',
    () {
      final code = File(
        'lib/services/firebase_service.dart',
      ).readAsStringSync();
      expect(code.contains("_dbRef('users').get()"), isFalse);
      expect(code.contains("_dbRef('Bands').get()"), isFalse);
      final section = code.substring(
        code.indexOf('Stream<String?> get catalogueIdentityChanges'),
        code.indexOf('Future<String> uploadAudioSnippetAsync'),
      );
      expect(section.contains('.onValue'), isFalse);
      expect(section.contains('limitToFirst'), isFalse);
    },
  );
  testWidgets(
    'Browse Musicians uses both safe catalogues, no mock empty replacements',
    (tester) async {
      final state = CatalogueState();
      state.catalogue.users = {};
      state.catalogue.bands = {};
      await mount(tester, state, const BrowseMusiciansScreen());
      expect(state.catalogue.paths, [
        'publicUserProfiles',
        'publicBandProfiles',
      ]);
      expect(find.text('Lina Rockwell'), findsNothing);
      expect(find.text('Marcus K.'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets('Browse 320px keeps full-band count and has no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = CatalogueState();
    await mount(tester, state, const BrowseMusiciansScreen());
    await tester.tap(find.text('Bands'));
    await authority.pump(tester);
    expect(find.text('3 members'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets(
    'Browse applies the latest local search after an asynchronous catalogue load',
    (tester) async {
      final state = CatalogueState();
      final gate = Completer<Object?>();
      state.catalogue.pending = gate;
      await mount(tester, state, const BrowseMusiciansScreen());
      await tester.enterText(find.byType(TextField).first, 'Updated query');
      gate.complete({
        'keep': {'DisplayName': 'Updated query musician'},
        'drop': {'DisplayName': 'Earlier name'},
      });
      state.catalogue.pending = null;
      await authority.pump(tester);
      await authority.pump(tester);
      expect(find.text('Updated query musician'), findsOneWidget);
      expect(find.text('Earlier name'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'Browse discards old-account results even after returning to the same account',
    (tester) async {
      final state = CatalogueState();
      final gate = Completer<Object?>();
      state.catalogue.pending = gate;
      await mount(tester, state, const BrowseMusiciansScreen());
      state.change('b', 'other');
      state.change('a', 'band');
      gate.complete({
        'old': {'DisplayName': 'Stale musician'},
      });
      state.catalogue.pending = null;
      await authority.pump(tester);
      expect(find.text('Stale musician'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets('Producer Search uses safe catalogue and latest skill filters', (
    tester,
  ) async {
    final state = CatalogueState();
    await mount(tester, state, const ProducerSearchScreen());
    expect(state.catalogue.paths, ['publicUserProfiles']);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('Create Band member picker executes safe catalogue transport', (
    tester,
  ) async {
    final state = CatalogueState();
    await mount(tester, state, const CreateBandScreen());
    await tester.ensureVisible(find.text('Add Member'));
    await tester.tap(find.text('Add Member'));
    await authority.pump(tester);
    expect(state.catalogue.paths, contains('publicUserProfiles'));
    expect(find.text('Visible musician'), findsWidgets);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('Edit Band member picker executes safe catalogue transport', (
    tester,
  ) async {
    final state = CatalogueState();
    state.catalogue.uid = 'leader';
    state.catalogue.transport.uid = 'leader';
    await mount(tester, state, EditBandInfoScreen(band: state.catalogue.band));
    await tester.ensureVisible(find.text('Add Band Member'));
    await tester.tap(find.text('Add Band Member'));
    await authority.pump(tester);
    expect(state.catalogue.paths, contains('publicUserProfiles'));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets(
    'late picker result cannot pop a different route or open old-account results',
    (tester) async {
      final state = CatalogueState();
      state.catalogue.pending = Completer<Object?>();
      await mount(
        tester,
        state,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await CatalogueLoading.usersForPicker(context);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await authority.pump(tester);
      state.change('b', 'other');
      await authority.pump(tester);
      state.catalogue.pending!.complete({
        'stale': {'DisplayName': 'Stale'},
      });
      await authority.pump(tester);
      expect(find.text('Open picker'), findsOneWidget);
      expect(find.text('Stale'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'Create Event guest picker searches safe public fields and never private email',
    (tester) async {
      final state = EventCatalogueState();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: CreateEventPage(bandId: 'band_1')),
        ),
      );
      await authority.pump(tester);
      await authority.pump(tester);
      await tester.ensureVisible(find.text('EDIT BAND MEMBERS (& SUBS)'));
      await tester.tap(find.text('EDIT BAND MEMBERS (& SUBS)'));
      await authority.pump(tester);
      await tester.ensureVisible(find.text('+ Add Sub'));
      await tester.tap(find.text('+ Add Sub'));
      await authority.pump(tester);
      await authority.pump(tester);
      expect(state.catalogue.paths, ['publicUserProfiles']);
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search by name, nickname, skill, city...',
      );
      expect(search, findsOneWidget);
      for (final query in ['Stage Dave', 'Piano', 'Stockholm']) {
        await tester.enterText(search, query);
        await tester.pump();
        expect(find.text('Dave Bass'), findsOneWidget);
      }
      await tester.enterText(search, 'private-only@example.test');
      await tester.pump();
      expect(find.text('Dave Bass'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
}
