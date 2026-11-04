// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart' as auth_platform;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/band_event.dart';
import 'package:musicians_flutter/models/event_room.dart';
import 'package:musicians_flutter/models/message.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/data/skills_taxonomy.dart';
import 'package:musicians_flutter/utils/band_membership_policy.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/views/home_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/profile_tab_screen.dart';
import 'package:musicians_flutter/widgets/skill_picker.dart';
import 'package:musicians_flutter/widgets/secondary_skills_editor.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';
import 'package:musicians_flutter/widgets/authorized_band_gate.dart';
import 'registration_secondary_skills_01_test.dart' as base;

Band realBand({String uid = 'a', String role = 'Leader', String id = 'real'}) => Band(
  id: id, name: 'Verified Band', membersBand: {uid: BandMember(userId: uid, role: role)},
);

class GuardService extends base.SkillService {
  Map<String, Band> bands = {};
  Completer<Map<String, String>>? delayedBands;
  Completer<void>? delayedLogout;
  int formReads = 0;
  int roomReads = 0;
  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async =>
    delayedBands?.future ?? {for (final band in bands.values)
      if (BandMembershipPolicy.isMember(band, userId)) band.id!: band.name!};
  @override
  Future<Band?> getBandInfoAsync(String bandId) async => bands[bandId];
  @override
  Future<List<UserProfile>> getAllUsersAsync() async { formReads++; return []; }
  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String userId) async => [];
  @override
  Future<List<BandEvent>> getBandEventsListAsync(String bandId) async => [];
  @override
  Future<List<BandMember>> getBandMembersAsync(String bandId) async => bands[bandId]!.membersBand.values.toList();
  @override
  Future<Map<String, Map<String, String>>> getBandFilesAsync(String bandId) async { roomReads++; return {}; }
  @override
  Stream<List<Message>> subscribeToBandMessages(String bandId) => Stream.value([]);
  @override
  Stream<List<BandEvent>> subscribeToBandEvents(String bandId) => Stream.value([]);
  @override
  Stream<List<EventRoom>> subscribeToBandEventRooms(String bandId) => Stream.value([]);
  @override
  Stream<List<Map<String, dynamic>>> subscribeToGigsNews(String bandId) => Stream.value([]);
  @override
  Future<void> saveButtonClickAsync(String userId, String buttonId, int count) async { writes++; }
  @override
  Future<void> logoutAsync() async { await delayedLogout?.future; uid = null; }
  @override
  Future<UserCredential> loginAsync(String email, String password) async {
    uid = email.split('@').first;
    profile = UserProfile(userId: uid, displayName: 'New user', email: email);
    return FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
  }
}

class GuardState extends base.SkillState {
  @override
  final GuardService service = GuardService();
  @override
  bool get isLoading => false;
}

Widget app(GuardState state, Widget child) => ChangeNotifierProvider<AppState>.value(
  value: state,
  child: MaterialApp(home: child, routes: {
    '/create-band': (_) => const Scaffold(body: Text('EXISTING CREATE BAND ROUTE')),
    '/find-sub': (_) => const FindSubScreen(),
    '/band-room': (_) => const BandRoomChatScreen(),
    '/main-nav': (_) => const Scaffold(body: Text('REGISTERED')),
  }),
);

Future<void> settle(WidgetTester tester) async {
  // Existing top bar spins continuously; bound pumps instead of pumpAndSettle.
  for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 150)); }
}
Future<void> size(WidgetTester tester, {double width = 800}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
Future<void> openPrimary(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Primary Skill/Talent (Select 1)'));
  await tester.tap(find.text('Primary Skill/Talent (Select 1)'));
  await settle(tester);
}

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

  testWidgets('primary opens the categorized hierarchy with current selection', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(GuardState(), const RegisterScreen()));
    await settle(tester);
    await openPrimary(tester);
    final sheet = tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet));
    expect(sheet.presentation, CategoryPickerPresentation.skillsHierarchy);
    expect(sheet.categoryMap.length, greaterThan(1));
    expect(sheet.initialSelected, ['Electric Guitar']);
    expect(sheet.isSingleSelect, isTrue);
    expect(sheet.maxSelection, 1);
  });
  testWidgets('primary search selects one canonical role and closes the sheet', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(GuardState(), const RegisterScreen()));
    await settle(tester);
    await openPrimary(tester);
    await tester.enterText(find.byType(TextField).last, 'Songwriter');
    await settle(tester);
    await tester.tap(find.text('Songwriter').last);
    await settle(tester);
    expect(find.byType(SearchableCategoryMultiSelectSheet), findsNothing);
    expect(tester.widget<PrimarySkillEditor>(find.byType(PrimarySkillEditor)).selected, 'SONGWRITER');
  });
  testWidgets('secondary remains multi-select using exactly the shared categories minus primary', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(GuardState(), const RegisterScreen()));
    await settle(tester);
    await tester.tap(find.text('Secondary Skills (optional)'));
    await settle(tester);
    final sheet = tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet));
    expect(sheet.isSingleSelect, isFalse);
    expect(sheet.maxSelection, isNull);
    expect(sheet.categoryMap, SkillPicker.categories(SkillTaxonomyContext.register, excludedSkill: 'Electric Guitar'));
  });
  test('both context allowlists exclude headings/actions/navigation/placeholders', () {
    for (final context in [SkillTaxonomyContext.register, SkillTaxonomyContext.editProfile]) {
      final values = SkillPicker.categories(context).values.expand((v) => v)
        .map(SkillsTaxonomy.getPersistedValueForDisplayLabel).toList();
      expect(values, containsAll(['Electric Guitar', 'Electric Bass', 'Piano', 'Soprano', 'SONGWRITER']));
      for (final value in values) {
        final option = SkillsTaxonomy.resolveLegacyValue(value)!;
        expect(option.kind, isNot(SkillOptionKind.action));
        expect(option.kind, isNot(SkillOptionKind.legacyHeader));
      }
      expect(values, isNot(contains('browse_musicians')));
      expect(values, isNot(contains('null')));
      expect(values, isNot(contains('N/A')));
    }
  });
  testWidgets('new primary removes only that secondary skill immediately', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(GuardState(), const RegisterScreen()));
    await settle(tester);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Electric Bass', 'Piano']);
    await tester.pump();
    await openPrimary(tester);
    await tester.enterText(find.byType(TextField).last, 'Electric Bass');
    await settle(tester);
    await tester.tap(find.text('Electric Bass').last);
    await settle(tester);
    expect(tester.widget<PrimarySkillEditor>(find.byType(PrimarySkillEditor)).selected, 'Electric Bass');
    expect(tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected, ['Piano']);
  });
  testWidgets('registration saves canonical primary with no secondary skills', (tester) async {
    await size(tester);
    final state = GuardState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    await openPrimary(tester);
    await tester.enterText(find.byType(TextField).last, 'Songwriter');
    await settle(tester);
    await tester.tap(find.text('Songwriter').last);
    await settle(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'New User');
    await tester.enterText(fields.at(1), 'new@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await settle(tester);
    expect(state.service.saved!.userType, 'SONGWRITER');
    expect(state.service.saved!.instruments, ['SONGWRITER']);
    expect(state.service.saved!.secondarySkills, isEmpty);
    expect(find.text('REGISTERED'), findsOneWidget);
  });
  testWidgets('320 px primary hierarchy and search do not overflow', (tester) async {
    await size(tester, width: 320);
    await tester.pumpWidget(app(GuardState(), const RegisterScreen()));
    await settle(tester);
    await openPrimary(tester);
    await tester.enterText(find.byType(TextField).last, 'Piano');
    await settle(tester);
    expect(find.text('Piano'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  for (final home in [false, true]) {
    testWidgets('${home ? 'Home' : 'direct route'} blocks no-band staffing without draft reads or writes', (tester) async {
      await size(tester);
      final state = GuardState();
      await state.refreshProfile();
      await tester.pumpWidget(app(state, home ? const HomeScreen() : const FindSubScreen()));
      await settle(tester);
      if (home) {
        await tester.ensureVisible(find.text('Find\nMusician/Vocalist').first);
        await tester.tap(find.text('Find\nMusician/Vocalist').first);
        await settle(tester);
      }
      expect(find.text('Create a band first'), findsOneWidget);
      expect(find.text(NoBandState.staffingBody), findsOneWidget);
      expect(find.text('PUBLISH SUBSTITUTE REQUESTS'), findsNothing);
      expect(state.service.formReads, 0);
      expect(state.service.writes, 0);
      await tester.tap(find.text('Create a Band'));
      await settle(tester);
      expect(find.text('EXISTING CREATE BAND ROUTE'), findsOneWidget);
    });
  }
  testWidgets('staffing rejects a stale or foreign route band ID', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, const FindSubScreen(bandId: 'foreign')));
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
    expect(state.service.formReads, 0);
    expect(state.service.writes, 0);
  });
  testWidgets('staffing rejects conflicting initial request band IDs', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, FindSubScreen(bandId: 'real', initialRequest: SubRequest(bandId: 'foreign'))));
    await settle(tester);
    expect(state.service.formReads, 0);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
  });
  testWidgets('authorized leader can still enter the staffing form', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, const FindSubScreen(bandId: 'real')));
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
    expect(state.service.formReads, greaterThan(0));
    expect(state.activeBandId, 'real');
  });
  testWidgets('changing a mounted route to a foreign band revalidates before rendering', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    final requested = ValueNotifier<String>('real');
    addTearDown(requested.dispose);
    await tester.pumpWidget(app(state, ValueListenableBuilder<String>(
      valueListenable: requested, builder: (_, id, __) => FindSubScreen(bandId: id))));
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
    requested.value = 'foreign';
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
    expect(state.service.writes, 0);
  });
  testWidgets('ordinary band member cannot enter staffing creation', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand(role: 'Member');
    await tester.pumpWidget(app(state, const FindSubScreen()));
    await settle(tester);
    expect(find.text('Band leader or admin required'), findsOneWidget);
    expect(state.service.formReads, 0);
    expect(state.service.writes, 0);
  });
  for (final home in [false, true]) {
    testWidgets('${home ? 'Home' : 'direct'} Band Room shows onboarding and existing Create route', (tester) async {
      await size(tester);
      final state = GuardState();
      await state.refreshProfile();
      await tester.pumpWidget(app(state, home ? const HomeScreen() : const BandRoomChatScreen()));
      await settle(tester);
      if (home) {
        await tester.ensureVisible(find.text('Band Room').first);
        await tester.tap(find.text('Band Room').first);
        await settle(tester);
      }
      expect(find.text('Create a band first'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(state.service.roomReads, 0);
      expect(state.service.writes, 0);
      await tester.tap(find.text('Create a Band'));
      await settle(tester);
      expect(find.text('EXISTING CREATE BAND ROUTE'), findsOneWidget);
    });
  }
  testWidgets('authorized ordinary member can enter Band Room', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand(role: 'Member');
    await tester.pumpWidget(app(state, const BandRoomChatScreen()));
    await settle(tester);
    expect(find.text('You’re not in a band yet'), findsNothing);
    expect(state.service.roomReads, 1);
    expect(find.text('Verified Band'), findsWidgets);
  });
  test('new user has no active band and cannot select arbitrary placeholders', () async {
    final state = GuardState();
    await state.refreshBandMemberships();
    state.selectBand('mock_band_1', 'Default Mock Band');
    expect(state.hasAuthorizedBand, isFalse);
    expect(state.activeBandId, isNull);
    expect(state.activeBandName, isNull);
  });
  test('canonical membership excludes mock/demo/empty/unrelated bands', () {
    expect(BandMembershipPolicy.isMember(realBand(id: 'mock_band_1'), 'a'), isFalse);
    expect(BandMembershipPolicy.isMember(realBand(id: 'demo_band_1'), 'a'), isFalse);
    expect(BandMembershipPolicy.isMember(realBand(uid: 'b'), 'a'), isFalse);
    expect(BandMembershipPolicy.isMember(Band(id: 'real', name: ''), 'a'), isFalse);
    expect(BandMembershipPolicy.isMember(realBand(role: 'Member'), 'a'), isTrue);
    expect(BandMembershipPolicy.canStaff(realBand(role: 'Member'), 'a'), isFalse);
    expect(BandMembershipPolicy.canStaff(realBand(role: 'Admin'), 'a'), isTrue);
  });
  testWidgets('logout clears active band before asynchronous sign-out completes', (tester) async {
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await state.refreshBandMemberships();
    expect(state.activeBandId, 'real');
    state.service.delayedLogout = Completer<void>();
    final logout = state.logout();
    expect(state.activeBandId, isNull);
    state.service.delayedLogout!.complete();
    await logout;
    expect(state.hasAuthorizedBand, isFalse);
  });
  testWidgets('an open destination cannot reload a band while logout is pending', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, const BandRoomChatScreen()));
    await settle(tester);
    expect(find.text('Verified Band'), findsWidgets);
    state.service.delayedLogout = Completer<void>();
    final logout = state.logout();
    await settle(tester);
    expect(find.text('Verified Band'), findsNothing);
    expect(state.activeBandId, isNull);
    expect(await state.refreshBandMemberships(), isEmpty);
    state.service.delayedLogout!.complete();
    await logout;
    await settle(tester);
    expect(state.hasAuthorizedBand, isFalse);
  });
  testWidgets('login A to B clears selected band and never carries A metadata', (tester) async {
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await state.refreshBandMemberships();
    final login = state.login('b@example.com', 'test-password');
    expect(state.activeBandId, isNull);
    await login;
    expect(state.currentUserId, 'b');
    expect(state.activeBandName, isNull);
  });
  testWidgets('late User A band load cannot overwrite User B', (tester) async {
    final state = GuardState();
    state.service.delayedBands = Completer<Map<String, String>>();
    final pending = state.refreshBandMemberships();
    state.service.uid = 'b';
    state.service.delayedBands!.complete({'real': 'A private band'});
    await pending;
    expect(state.activeBandId, isNull);
    state.service.delayedBands = null;
    await state.refreshBandMemberships();
    expect(state.hasAuthorizedBand, isFalse);
  });
  testWidgets('concurrent membership checks share a read and both authorize the real band', (tester) async {
    final state = GuardState();
    state.service.bands['real'] = realBand();
    state.service.delayedBands = Completer<Map<String, String>>();
    final first = state.resolveAuthorizedBand('real', requireManager: true);
    final second = state.resolveAuthorizedBand('real', requireManager: true);
    state.service.delayedBands!.complete({'real': 'Verified Band'});
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    expect(state.activeBandId, 'real');
  });
  testWidgets('removing membership clears a previously active band', (tester) async {
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await state.refreshBandMemberships();
    state.service.bands.clear();
    await state.refreshBandMemberships();
    expect(state.activeBandId, isNull);
    expect(state.activeBandName, isNull);
  });
  testWidgets('profile without membership shows no fabricated active band', (tester) async {
    await size(tester);
    final state = GuardState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const ProfileTabScreen()));
    await settle(tester);
    expect(find.text('No active band'), findsOneWidget);
    expect(find.text('Deku Tree Bongo'), findsNothing);
    expect(find.text('Default Mock Band'), findsNothing);
    expect(find.text('Create a Band'), findsOneWidget);
  });
  testWidgets('profile shows only the real authorized active name', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const ProfileTabScreen()));
    await settle(tester);
    expect(find.text('Verified Band'), findsOneWidget);
    expect(find.text('No active band'), findsNothing);
    expect(find.text('Default Mock Band'), findsNothing);
  });
  testWidgets('account switch disposes the authorized staffing form before B can use it', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, const FindSubScreen()));
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsOneWidget);
    state.service.uid = 'b';
    state.notifyListeners();
    await settle(tester);
    expect(find.text('FIND MUSICIAN/VOCALIST'), findsNothing);
    expect(find.text('Create a band first'), findsOneWidget);
    expect(state.service.writes, 0);
  });

  testWidgets('Home no-band Cancel closes guard with zero writes', (tester) async {
    await size(tester);
    final state = GuardState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const HomeScreen()));
    await settle(tester);
    await tester.tap(find.text('Find\nMusician/Vocalist'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Create a band first'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(state.service.writes, 0);
  });
  testWidgets('mock membership never becomes active or opens Band Room', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['mock_band_1'] = realBand(id: 'mock_band_1');
    await tester.pumpWidget(app(state, const BandRoomChatScreen()));
    await settle(tester);
    expect(state.activeBandId, isNull);
    expect(state.service.roomReads, 0);
    expect(find.text('Create a band first'), findsOneWidget);
  });
  test('unrelated legacy UserRole alone never grants membership or staffing', () {
    final forged = Band(id: 'real', name: 'Band', userRole: 'Leader');
    expect(BandMembershipPolicy.isMember(forged, 'a'), isFalse);
    expect(BandMembershipPolicy.canStaff(forged, 'a'), isFalse);
  });
  testWidgets('late membership result after logout cannot restore a band', (tester) async {
    final state = GuardState();
    state.service.delayedBands = Completer<Map<String, String>>();
    final pending = state.refreshBandMemberships();
    await state.logout();
    state.service.delayedBands!.complete({'real': 'A band'});
    await pending;
    expect(state.activeBandId, isNull);
    expect(state.activeBandName, isNull);
  });
  testWidgets('revoked membership removes an already open Band Room', (tester) async {
    await size(tester);
    final state = GuardState();
    state.service.bands['real'] = realBand();
    await tester.pumpWidget(app(state, const BandRoomChatScreen()));
    await settle(tester);
    expect(find.text('Verified Band'), findsWidgets);
    state.service.bands.clear();
    await state.refreshBandMemberships();
    await settle(tester);
    expect(find.text('Verified Band'), findsNothing);
    expect(find.text('Create a band first'), findsOneWidget);
  });
  for (final staffing in [false, true]) {
    testWidgets('320 px ${staffing ? 'staffing' : 'Band Room'} no-band state has no overflow', (tester) async {
      await size(tester, width: 320);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpWidget(app(GuardState(), staffing ? const FindSubScreen() : const BandRoomChatScreen()));
      await settle(tester);
      expect(find.text('Create a Band'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
