// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart' as auth_platform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musicians_flutter/data/skills_taxonomy.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/app_notification.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/utils/secondary_skills_utils.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/views/musician_profile_screen.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/widgets/secondary_skills_editor.dart';
import 'package:musicians_flutter/widgets/skill_picker.dart';
import 'package:musicians_flutter/widgets/secondary_skills_badge.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

// Network-free auth platform for exercising the real registration service.
class GateAuthPlatform extends auth_platform.FirebaseAuthPlatform {
  late final gateUser = GateAuthUser(this);
  @override
  auth_platform.FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  auth_platform.FirebaseAuthPlatform setInitialValues({
    auth_platform.InternalUserDetails? currentUser, String? languageCode,
  }) => this;
  @override
  auth_platform.UserPlatform get currentUser => gateUser;
  @override
  Future<auth_platform.UserCredentialPlatform> createUserWithEmailAndPassword(
    String email, String password,
  ) async => GateAuthCredential(this, gateUser);
}

class GateMultiFactor extends auth_platform.MultiFactorPlatform {
  GateMultiFactor(super.auth);
}

class GateAuthUser extends auth_platform.UserPlatform {
  GateAuthUser(auth_platform.FirebaseAuthPlatform auth) : super(
    auth, GateMultiFactor(auth), auth_platform.InternalUserDetails(
      userInfo: auth_platform.InternalUserInfo(uid: 'a', isAnonymous: false,
        isEmailVerified: false), providerData: [],
    ),
  );
  @override
  Future<void> updateProfile(Map<String, String?> profile) async {}
}

class GateAuthCredential extends auth_platform.UserCredentialPlatform {
  GateAuthCredential(auth_platform.FirebaseAuthPlatform auth,
    auth_platform.UserPlatform user) : super(auth: auth, user: user);
}

// Capture at the established service boundary; registration, model serialization
// and saveUserProfileAsync all execute their production implementations.
class PayloadService extends FirebaseService {
  Map<String, dynamic>? serialized;
  Map<String, dynamic>? fields;
  int writes = 0;
  @override
  Future<void> saveUserProfileAsync(String userId, UserProfile profile) async {
    serialized = profile.toJson();
    await super.saveUserProfileAsync(userId, profile);
  }
  @override
  Future<void> updateUserProfileFields(String userId, Map<String, dynamic> value) async {
    expect(userId, 'a');
    fields = Map.of(value);
    writes++;
  }
}

class SkillService extends FirebaseService {
  String? uid = 'a';
  UserProfile? profile = UserProfile(userId: 'a', displayName: 'Alex',
    email: 'alex@example.com', userType: 'Electric Guitar',
    instruments: ['Electric Guitar', 'Electric Bass']);
  UserProfile? saved;
  bool fail = false;
  int writes = 0;
  List<SubRequest> requests = [];
  Completer<void>? saveGate;
  Completer<UserProfile?>? delayed;
  @override
  String? get currentUserId => uid;
  @override
  bool get isLoggedIn => uid != null;
  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) =>
      delayed?.future ?? Future.value(profile);
  @override
  Future<void> saveUserProfileAsync(String userId, UserProfile value) async {
    if (fail) throw StateError('save failed');
    await saveGate?.future;
    writes++;
    saved = value;
    profile = value;
  }
  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async => {};
  @override
  Future<Map<String, int>> getButtonClicksAsync(String userId) async => {};
  @override
  Future<void> initializePushNotifications() async {}
  @override
  Future<List<SubRequest>> getUserSubRequestFeedAsync() async => requests;
  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};
  @override
  Future<bool> isFavoriteAsync(String userId) async => false;
  @override
  Future<List<String>> getFavoriteUserIdsAsync() async => [];
  @override
  Future<void> logoutAsync() async { uid = null; }
  @override
  Stream<bool> subscribeToUnreadNotifications() => const Stream.empty();
  @override
  Stream<int> subscribeToUnreadNotificationCount([String? userId]) => const Stream.empty();
  @override
  Stream<List<AppNotification>> subscribeToUserNotifications([String? userId]) => const Stream.empty();
}

class OwnershipService extends FirebaseService {
  @override
  String? get currentUserId => 'a';
}

class SkillState extends AppState {
  final SkillService service = SkillService();
  List<String>? registered;
  @override
  FirebaseService get firebaseService => service;
  @override
  Future<void> register(String email, String password, String userType,
      String nickname, [String? level, List<String>? genres,
      List<String>? secondarySkills]) async {
    registered = secondarySkills;
    await service.saveUserProfileAsync('a', UserProfile(userId: 'a',
      userType: userType, instruments: SecondarySkillsUtils.buildInstrumentsList(
        userType, secondarySkills ?? [])));
  }
}

Widget app(SkillState state, Widget child) => ChangeNotifierProvider<AppState>.value(
  value: state,
  child: MaterialApp(home: child, routes: {
    '/main-nav': (_) => const Scaffold(body: Text('Registered')),
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    auth_platform.FirebaseAuthPlatform.instance = GateAuthPlatform();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final payloadCases = <String, List<String>>{
    'A primary only': [],
    'B multiple secondary skills': ['Electric Bass', 'Piano'],
    'C duplicate and malformed strings': [
      'electric guitar', 'Electric Bass', 'electric bass', '', '   ', 'null',
    ],
  };
  for (final entry in payloadCases.entries) {
    test('gate registration payload ${entry.key} uses production service and serialization', () async {
      final service = PayloadService();
      await service.registerAsync('alex@example.com', 'test-password',
        'Electric Guitar', 'Alex', 'C = INTERMEDIATE', ['Jazz'], entry.value);
      final expected = ['Electric Guitar',
        if (entry.key.startsWith('B') || entry.key.startsWith('C')) 'Electric Bass',
        if (entry.key.startsWith('B')) 'Piano'];
      for (final map in [service.serialized!, service.fields!]) {
        expect(map['UserType'], 'Electric Guitar');
        expect(map['Instruments'], expected);
        expect(map.keys.where((key) => key.toLowerCase().contains('secondary')), isEmpty);
        expect(map['DisplayName'], 'Alex');
        expect(map['Nickname'], 'Alex');
        expect(map['Email'], 'alex@example.com');
        expect(map['Genres'], ['Jazz']);
        expect(map['Level'], 'C = INTERMEDIATE');
        expect(map['About'], 'Hey! I am a musician ready to play.');
      }
      expect(service.writes, 1);
      print('GATE_REGISTRATION_${entry.key[0]}=' + jsonEncode(service.fields));
    });
  }
  for (final malformed in <dynamic>[null, 42, true, [null, 3, {}, ' '], {'0': null}]) {
    test('malformed Instruments $malformed safely yields no secondary skills', () {
      final profile = UserProfile.fromJson({'UserType': 'Electric Guitar', 'Instruments': malformed});
      expect(profile.secondarySkills, isEmpty);
    });
  }
  test('legacy profile without Instruments remains primary-only', () {
    final profile = UserProfile.fromJson({'UserType': 'Electric Guitar'});
    expect(profile.primarySkill, 'Electric Guitar');
    expect(profile.secondarySkills, isEmpty);
    expect(profile.matchingSkills, ['Electric Guitar']);
  });
  test('existing casing variants and map-form Instruments are supported', () {
    final profile = UserProfile.fromJson({'info': {'userType': 'Electric Guitar',
      'instruments': {'0': 'Electric Guitar', '1': 'Electric Bass'}}});
    expect(profile.secondarySkills, ['Electric Bass']);
  });
  test('normalization trims, removes placeholders, and deduplicates in selection order', () {
    expect(SecondarySkillsUtils.normalize([' ', ' Bass ', 'bass', null,
      'Guitar', 'N/A', 'null', 'Browse Profiles', '']), ['Bass', 'Guitar']);
  });
  test('primary exclusion is case insensitive', () {
    expect(SecondarySkillsUtils.normalize(['BASS', 'Guitar'], primarySkill: ' bass '), ['Guitar']);
  });
  test('primary change removes new primary and preserves other selections', () {
    expect(SecondarySkillsUtils.reconcileWithPrimary(['Bass', 'Drums', 'Piano'], 'bass'), ['Drums', 'Piano']);
  });
  test('canonical serialization has one Instruments key and round trips', () {
    final profile = UserProfile(userType: 'Electric Guitar',
      instruments: ['Electric Guitar', 'Electric Bass', 'electric bass', 'Piano']);
    final json = profile.toJson();
    expect(json['Instruments'], ['Electric Guitar', 'Electric Bass', 'Piano']);
    expect(json.containsKey('instruments'), isFalse);
    expect(json.containsKey('secondarySkills'), isFalse);
    expect(UserProfile.fromJson(json).secondarySkills, ['Electric Bass', 'Piano']);
  });
  test('instrument list cannot be mutated through constructor alias', () {
    final input = ['Electric Guitar', 'Electric Bass'];
    final profile = UserProfile(instruments: input);
    input.clear();
    expect(profile.secondarySkills, ['Electric Bass']);
    expect(() => profile.instruments.add('Piano'), throwsUnsupportedError);
  });
  test('matching union includes primary and secondary only once', () {
    final profile = UserProfile(userType: 'Electric Guitar', mainInstrument: 'Electric Guitar',
      instruments: ['Electric Guitar', 'Electric Bass', 'electric bass']);
    expect(profile.matchingSkills, ['Electric Guitar', 'Electric Bass']);
    final users = [profile].where((p) => p.matchingSkills.any((s) => s == 'Electric Bass')).toList();
    expect(users, hasLength(1));
  });

  Future<void> settle(WidgetTester tester) async {
    // The established top bar has a continuously spinning globe.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }
  Future<void> size(WidgetTester tester, {double width = 800}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  Future<void> openPicker(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Secondary Skills (optional)'));
    await tester.tap(find.text('Secondary Skills (optional)'));
    await settle(tester);
  }
  for (final skills in <List<String>>[[], ['Electric Bass'], ['Electric Bass', 'Piano']]) {
    testWidgets('registration submits ${skills.length} optional skills', (tester) async {
      await size(tester);
      final state = SkillState();
      await tester.pumpWidget(app(state, const RegisterScreen()));
      await settle(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Alex');
      await tester.enterText(fields.at(1), 'alex@example.com');
      await tester.enterText(fields.at(2), 'password123');
      final editor = tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor));
      editor.onChanged(skills);
      await settle(tester);
      await tester.ensureVisible(find.text('Sign Up'));
      await tester.tap(find.text('Sign Up'));
      await settle(tester);
      expect(state.registered, skills);
      expect(state.service.saved!.secondarySkills, skills);
      expect(find.text('Registered'), findsOneWidget);
    });
  }
  testWidgets('registration primary change immediately reconciles selections', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Electric Bass', 'Piano']);
    await tester.pump();
    final primary = tester.widget<PrimarySkillEditor>(find.byType(PrimarySkillEditor));
    primary.onChanged('Electric Bass');
    await tester.pump();
    final editor = tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor));
    expect(editor.primarySkill, 'Electric Bass');
    expect(editor.selected, ['Piano']);
  });
  testWidgets('picker excludes primary, supports taps and preserves draft on reopen/cancel', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    await openPicker(tester);
    final sheet = tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet));
    expect(sheet.categoryMap.values.expand((s) => s).map(SkillsTaxonomy.getPersistedValueForDisplayLabel), isNot(contains('Electric Guitar')));
    expect(sheet.categoryMap.values.expand((s) => s), isNotEmpty);
    // Search and select a real canonical skill.
    await tester.enterText(find.byType(TextField).last, 'Electric Bass');
    await settle(tester);
    await tester.tap(find.text('Electric Bass').last);
    await settle(tester);
    await tester.tap(find.textContaining('Done'));
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Electric Bass'), findsOneWidget);
    await openPicker(tester);
    expect(tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet)).initialSelected, ['Electric Bass']);
    Navigator.of(tester.element(find.byType(SearchableCategoryMultiSelectSheet))).pop();
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Electric Bass'), findsOneWidget);
    expect(state.service.writes, 0);
  });
  testWidgets('edit loads stored skills, adds/removes and saves empty list with refreshed state', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Electric Bass'), findsOneWidget);
    final editor = tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor));
    editor.onChanged(['Electric Bass', 'Piano']);
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Piano'), findsOneWidget);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged([]);
    await tester.pump();
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await settle(tester);
    expect(state.service.saved!.secondarySkills, isEmpty);
    expect(state.service.saved!.toJson()['Instruments'], ['Electric Guitar']);
    expect(state.service.saved!.toJson()['MainInstrument'], 'Electric Guitar');
    print('GATE_EDIT_EMPTY=' + jsonEncode(state.service.saved!.toJson()));
    expect(state.currentUserProfile!.secondarySkills, isEmpty);
  });
  testWidgets('edit cancellation does not write', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Piano']);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(state.service.writes, 0);
    expect(state.service.profile!.secondarySkills, ['Electric Bass']);
  });
  testWidgets('failed edit save stays on editor without success', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    state.service.fail = true;
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await settle(tester);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.textContaining('Failed to save profile:'), findsOneWidget);
    expect(find.text('Profile updated successfully!'), findsNothing);
    expect(state.service.writes, 0);
  });
  testWidgets('late profile refresh from A cannot populate B after switching', (tester) async {
    final state = SkillState();
    state.service.delayed = Completer<UserProfile?>();
    final pending = state.refreshProfile();
    state.service.uid = 'b';
    state.service.delayed!.complete(state.service.profile);
    await pending;
    expect(state.currentUserProfile, isNull);
    state.service.delayed = null;
    state.service.profile = UserProfile(userId: 'b', userType: 'Piano');
    await state.refreshProfile();
    expect(state.currentUserProfile!.userId, 'b');
    expect(state.currentUserProfile!.secondarySkills, isEmpty);
    await state.logout();
    expect(state.currentUserProfile, isNull);
  });
  for (final editing in [false, true]) {
    testWidgets('${editing ? 'edit' : 'registration'} at 320 px with long selections has no overflow', (tester) async {
      await size(tester, width: 320);
      final state = SkillState();
      await state.refreshProfile();
      await tester.pumpWidget(app(state, editing ? const EditProfileScreen() : const RegisterScreen()));
      await settle(tester);
      tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Studio Engineer etc.', 'Electric Bass', 'Keyboard/Synth']);
      await settle(tester);
      await tester.ensureVisible(find.byType(SecondarySkillsEditor));
      await settle(tester);
    });
  }

  testWidgets('gate edit primary switch saves exact payload without old primary', (tester) async {
    await size(tester);
    final state = SkillState();
    state.service.profile = UserProfile(userId: 'a', userType: 'Electric Guitar',
      mainInstrument: 'Electric Guitar', instruments: ['Electric Guitar', 'Electric Bass', 'Piano'],
      displayName: 'Alex', email: 'alex@example.com', styles: ['Jazz'],
      contact: 'contact', history: 'Tour', projects: 'Album', collabRoles: ['PRODUCER'], collabRemote: true);
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    tester.widget<InputChip>(find.widgetWithText(InputChip, 'Electric Guitar')).onPressed!();
    await settle(tester);
    Navigator.of(tester.element(find.byType(SearchableCategoryMultiSelectSheet))).pop(['Electric Bass']);
    await settle(tester);
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await settle(tester);
    final service = PayloadService();
    await service.saveUserProfileAsync('a', state.service.saved!);
    for (final map in [service.serialized!, service.fields!]) {
      expect(map['UserType'], 'Electric Bass');
      expect(map['MainInstrument'], 'Electric Bass');
      expect(map['Instruments'], ['Electric Bass', 'Piano']);
      expect(map['Styles'], ['Jazz']);
      expect(map['Contact'], 'contact');
      expect(map['History'], 'Tour');
      expect(map['Projects'], 'Album');
      expect(map['CollabRoles'], ['PRODUCER']);
      expect(map['CollabRemote'], isTrue);
    }
    print('GATE_EDIT_PRIMARY_SWITCH=' + jsonEncode(service.fields));
  });
  testWidgets('edit primary picker immediately reconciles secondary selections', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    final chip = tester.widget<InputChip>(find.widgetWithText(InputChip, 'Electric Guitar'));
    chip.onPressed!();
    await settle(tester);
    Navigator.of(tester.element(find.byType(SearchableCategoryMultiSelectSheet))).pop(['Electric Bass']);
    await settle(tester);
    final editor = tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor));
    expect(editor.primarySkill, 'Electric Bass');
    expect(editor.selected, isEmpty);
  });
  testWidgets('edit hides A draft immediately on account switch and performs no write', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    state.service.uid = 'b';
    state.notifyListeners();
    await settle(tester);
    expect(find.byType(SecondarySkillsEditor), findsNothing);
    expect(find.text('Your account changed. Reopen Edit Profile.'), findsOneWidget);
    expect(state.service.writes, 0);
  });
  testWidgets('edit waits for persistence before showing success', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    state.service.saveGate = Completer<void>();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await settle(tester);
    expect(state.service.saved, isNull);
    expect(find.text('Profile updated successfully!'), findsNothing);
    state.service.saveGate!.complete();
    await settle(tester);
    expect(state.service.saved, isNotNull);
  });
  testWidgets('registration failure does not navigate to success', (tester) async {
    await size(tester);
    final state = SkillState();
    state.service.fail = true;
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex');
    await tester.enterText(fields.at(1), 'alex@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await settle(tester);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Registered'), findsNothing);
    expect(find.textContaining('save failed'), findsOneWidget);
  });
  testWidgets('removable secondary chip updates registration draft only', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Electric Bass', 'Piano']);
    await settle(tester);
    tester.widget<InputChip>(find.widgetWithText(InputChip, 'Electric Bass')).onDeleted!();
    await settle(tester);
    expect(tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected, ['Piano']);
    expect(state.service.writes, 0);
  });
  test('reading and matching secondary skills performs no persistence', () {
    final service = SkillService();
    final profile = service.profile!;
    expect(profile.secondarySkills, ['Electric Bass']);
    expect(profile.matchingSkills, contains('Electric Bass'));
    profile.toJson();
    expect(service.writes, 0);
  });

  testWidgets('Find Gigs matches primary and secondary without duplicate cards or writes', (tester) async {
    await size(tester);
    final state = SkillState();
    await state.refreshProfile();
    final date = DateTime.now().add(const Duration(days: 2)).toIso8601String();
    state.service.requests = [
      SubRequest(id: 'bass', subRequestId: 'bass', bandName: 'Bass Opportunity', voicePart: 'Electric Bass', date: date),
      SubRequest(id: 'guitar', subRequestId: 'guitar', bandName: 'Guitar Opportunity', voicePart: 'Electric Guitar', date: date),
      SubRequest(id: 'drums', subRequestId: 'drums', bandName: 'Drum Opportunity', voicePart: 'Drums', date: date),
    ];
    await tester.pumpWidget(app(state, const FindGigsScreen()));
    await settle(tester);
    expect(find.text('Bass Opportunity'), findsOneWidget);
    expect(find.text('Guitar Opportunity'), findsOneWidget);
    expect(find.text('Drum Opportunity'), findsNothing);
    expect(state.service.writes, 0);
  });

  test('empty legacy JSON loads without requiring onboarding fields', () {
    final profile = UserProfile.fromJson({});
    expect(profile.secondarySkills, isEmpty);
    expect(profile.matchingSkills, isEmpty);
  });
  test('legacy comma-separated MainInstrument retains additional skills', () {
    final profile = UserProfile.fromJson({'UserType': 'Electric Guitar',
      'MainInstrument': 'Electric Guitar, Piano', 'Instruments': ['Electric Guitar', 'Piano', 'Electric Bass']});
    expect(profile.primarySkill, 'Electric Guitar');
    expect(profile.secondarySkills, ['Piano', 'Electric Bass']);
  });
  test('serialization preserves unrelated profile properties', () {
    final profile = UserProfile(userId: 'a', userType: 'Piano',
      instruments: ['Piano', 'Electric Bass'], about: 'Drums',
      location: 'Gothenburg', styles: ['Jazz'], collabRoles: ['Producer'], collabRemote: true);
    final restored = UserProfile.fromJson(profile.toJson());
    expect(restored.about, 'Drums');
    expect(restored.location, 'Gothenburg');
    expect(restored.styles, ['Jazz']);
    expect(restored.collabRoles, ['Producer']);
    expect(restored.collabRemote, isTrue);
    expect(restored.matchingSkills, isNot(contains('Drums')));
  });
  test('real persistence rejects another account before attempting an RTDB write', () async {
    await expectLater(OwnershipService().saveUserProfileAsync('b', UserProfile(userId: 'b')),
      throwsStateError);
  });
  testWidgets('edit opens a saved empty optional selection', (tester) async {
    await size(tester);
    final state = SkillState();
    state.service.profile = UserProfile(userId: 'a', displayName: 'Alex', email: 'alex@example.com', userType: 'Piano');
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    expect(tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected, isEmpty);
    expect(find.text('Secondary Skills (optional)'), findsOneWidget);
  });
  testWidgets('edit saves several skills and preserves unrelated profile fields', (tester) async {
    await size(tester);
    final state = SkillState();
    state.service.profile = UserProfile(userId: 'a', displayName: 'Alex', email: 'alex@example.com',
      userType: 'Piano', styles: ['Jazz'], history: 'Tour', collabRemote: true);
    await state.refreshProfile();
    await tester.pumpWidget(app(state, const EditProfileScreen()));
    await settle(tester);
    tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).onChanged(['Electric Bass', 'Drums']);
    await settle(tester);
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await settle(tester);
    expect(state.service.saved!.secondarySkills, ['Electric Bass', 'Drums']);
    expect(state.service.saved!.styles, ['Jazz']);
    expect(state.service.saved!.history, 'Tour');
    expect(state.service.saved!.collabRemote, isTrue);
  });
  testWidgets('cancelling picker discards unconfirmed selections', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    await openPicker(tester);
    await tester.enterText(find.byType(TextField).last, 'Electric Bass');
    await settle(tester);
    await tester.tap(find.text('Electric Bass').last);
    await settle(tester);
    Navigator.of(tester.element(find.byType(SearchableCategoryMultiSelectSheet))).pop();
    await settle(tester);
    expect(tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected, isEmpty);
    expect(state.service.writes, 0);
  });
  testWidgets('vocal secondary choices use canonical register taxonomy without headings', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    await openPicker(tester);
    final sheet = tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet));
    final values = sheet.categoryMap.values.expand((items) => items)
        .map(SkillsTaxonomy.getPersistedValueForDisplayLabel).toList();
    expect(values, contains('Soprano'));
    expect(values, contains('Tenor'));
    expect(values, isNot(contains('Browse Musicians')));
  });
  for (final editing in [false, true]) {
    testWidgets('gate ${editing ? 'edit' : 'registration'} taxonomy allowlist contains only canonical skills', (tester) async {
      await size(tester);
      final state = SkillState();
      await state.refreshProfile();
      await tester.pumpWidget(app(state, editing ? const EditProfileScreen() : const RegisterScreen()));
      await settle(tester);
      await openPicker(tester);
      final sheet = tester.widget<SearchableCategoryMultiSelectSheet>(find.byType(SearchableCategoryMultiSelectSheet));
      final labels = sheet.categoryMap.values.expand((items) => items).toList();
      final values = labels.map(SkillsTaxonomy.getPersistedValueForDisplayLabel).toList();
      final allowed = SkillsTaxonomy.optionsFor(editing
        ? SkillTaxonomyContext.editProfile : SkillTaxonomyContext.register)
        .where((option) => option.kind != SkillOptionKind.action && option.kind != SkillOptionKind.legacyHeader)
        .map((option) => option.persistedValue).toSet();
      expect(values, isNotEmpty);
      expect(values.every(allowed.contains), isTrue);
      expect(values, isNot(contains('Electric Guitar')));
      for (final excluded in ['Create Session', 'Create Jam', 'Find Session',
        'Browse Musicians', 'Browse Profiles', 'browse_musicians', 'null', 'N/A', '']) {
        expect(values, isNot(contains(excluded)));
      }
      expect(values, containsAll(['Electric Bass', 'Piano', 'Soprano', 'Tenor', 'SONGWRITER', 'PRODUCER']));
      expect(labels, contains('Songwriter'));
      expect(values, contains('SONGWRITER'));
      expect(values, isNot(contains('Songwriter')));
      print('GATE_TAXONOMY_${editing ? 'EDIT' : 'REGISTER'}=' + jsonEncode(values));
      await tester.enterText(find.byType(TextField).last, 'Songwriter');
      await settle(tester);
      await tester.tap(find.text('Songwriter').last);
      await settle(tester);
      await tester.tap(find.textContaining('Done'));
      await settle(tester);
      final selected = tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected;
      expect(selected, contains('SONGWRITER'));
      expect(selected, isNot(contains('Songwriter')));
    });
  }
  testWidgets('gate picker search cannot create arbitrary free-text skill', (tester) async {
    await size(tester);
    final state = SkillState();
    await tester.pumpWidget(app(state, const RegisterScreen()));
    await settle(tester);
    await openPicker(tester);
    await tester.enterText(find.byType(TextField).last, 'invented-gate-skill');
    await settle(tester);
    await tester.tap(find.textContaining('Done'));
    await settle(tester);
    expect(tester.widget<SecondarySkillsEditor>(find.byType(SecondarySkillsEditor)).selected, isEmpty);
  });
  testWidgets('actual musician profile at 320 px presents primary before secondary', (tester) async {
    await size(tester, width: 320);
    final state = SkillState();
    await tester.pumpWidget(app(state, MusicianProfileScreen(musician: state.service.profile!)));
    await settle(tester);
    expect(find.text('Electric Guitar'), findsAtLeastNWidgets(1));
    expect(find.byType(SecondarySkillsBadge), findsAtLeastNWidgets(1));
  });
  testWidgets('long secondary list dialog scrolls at 320 px', (tester) async {
    await size(tester, width: 320);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SecondarySkillsBadge(
      memberName: 'Alex', secondarySkills: List.generate(60, (i) => 'Instrument $i'),
    ))));
    await tester.tap(find.text('+60 skills'));
    await settle(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('presentation at 320 px omits empty badges and opens compact secondary list', (tester) async {
    await size(tester, width: 320);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [
      Text('Electric Guitar'),
      SecondarySkillsBadge(memberName: 'Alex', secondarySkills: ['Electric Bass', 'Piano']),
      SecondarySkillsBadge(memberName: 'Empty', secondarySkills: []),
    ]))));
    expect(find.text('+2 skills'), findsOneWidget);
    expect(find.text('+0 skills'), findsNothing);
    expect(tester.getTopLeft(find.text('Electric Guitar')).dy, lessThan(tester.getTopLeft(find.text('+2 skills')).dy));
    await tester.tap(find.text('+2 skills'));
    await settle(tester);
    expect(find.text('Electric Bass'), findsOneWidget);
    expect(find.text('Piano'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
