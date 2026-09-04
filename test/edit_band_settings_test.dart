import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/views/band_room_chat_screen.dart';
import 'package:musicians_flutter/views/create_band_screen.dart';
import 'package:musicians_flutter/views/edit_band_info_screen.dart';
import 'package:musicians_flutter/widgets/custom_top_bar.dart';
import 'package:provider/provider.dart';

class MockSettingsFirebaseService extends FirebaseService {
  Band? bandToReturn;
  final List<Map<String, String>> addedMembers = [];
  Completer<void>? addMemberCompleter;

  @override
  Future<Band?> getBandInfoAsync(String bandId) async {
    return bandToReturn;
  }

  @override
  Future<void> addBandMemberAsync(
    String bandId,
    String userId,
    String role,
    String nickname,
  ) async {
    if (addMemberCompleter != null) {
      await addMemberCompleter!.future;
    }
    addedMembers.add({
      'bandId': bandId,
      'userId': userId,
      'role': role,
      'nickname': nickname,
    });
  }
}

class MockSettingsAppState extends AppState {
  final MockSettingsFirebaseService mockService;
  String? _mockCurrentUserId = 'user_leader';
  String? _mockActiveBandId;
  final UserProfile? _mockUserProfile = UserProfile(
    userId: 'user_leader',
    displayName: 'Test Leader',
  );

  MockSettingsAppState(this.mockService, {String? activeBandId, String? currentUserId}) {
    _mockActiveBandId = activeBandId;
    if (currentUserId != null) {
      _mockCurrentUserId = currentUserId;
    }
  }

  @override
  FirebaseService get firebaseService => mockService;

  @override
  String? get currentUserId => _mockCurrentUserId;

  @override
  String? get activeBandId => _mockActiveBandId;

  @override
  UserProfile? get currentUserProfile => _mockUserProfile;

  @override
  List<String> get selectedBubbles => ['find_musicians', 'band_room', 'browse_musicians'];
}

Widget createSettingsTestWidget(Widget child, MockSettingsAppState appState) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: child,
      onGenerateRoute: (settings) {
        if (settings.name == '/edit-band') {
          final band = settings.arguments as Band;
          return MaterialPageRoute(
            builder: (context) => EditBandInfoScreen(band: band),
            settings: settings,
          );
        }
        return null;
      },
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('EDIT-BAND-01: Band.canUserEdit Unit Tests', () {
    test('canUserEdit returns true for Leader and Admin, false for Member and non-member', () {
      final band = Band(
        id: 'b1',
        name: 'Rockers',
        membersBand: {
          'user_leader': BandMember(userId: 'user_leader', role: 'Leader'),
          'user_admin': BandMember(userId: 'user_admin', role: 'Admin'),
          'user_member': BandMember(userId: 'user_member', role: 'Member'),
        },
      );

      expect(band.canUserEdit('user_leader'), isTrue);
      expect(band.canUserEdit('user_admin'), isTrue);
      expect(band.canUserEdit('user_member'), isFalse);
      expect(band.canUserEdit('user_outsider'), isFalse);
      expect(band.canUserEdit(null), isFalse);
    });

    test('canUserEdit respects band userRole fallback', () {
      final leaderBand = Band(id: 'b1', name: 'Rockers', userRole: 'Leader');
      expect(leaderBand.canUserEdit('any_id'), isTrue);

      final memberBand = Band(id: 'b1', name: 'Rockers', userRole: 'Member');
      expect(memberBand.canUserEdit('any_id'), isFalse);
    });
  });

  group('EDIT-BAND-01: Regular Settings Menu & Edit Band', () {
    testWidgets('Edit Band is hidden from regular Settings menu in HomeView', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService, activeBandId: 'band_123');

      await tester.pumpWidget(createSettingsTestWidget(
        const Scaffold(
          appBar: CustomTopBar(title: 'Home'),
          body: Center(child: Text('Home View')),
        ),
        appState,
      ));
      await tester.pumpAndSettle();

      // Tap settings gear icon to open menu
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final editProfileFinder = find.text('Edit Profile');
      final editBandFinder = find.text('Edit Band');
      final createBandFinder = find.text('Create Band');

      expect(editProfileFinder, findsOneWidget);
      expect(editBandFinder, findsNothing, reason: 'Edit Band must be hidden from regular Settings menu');
      expect(createBandFinder, findsOneWidget);

      final editProfileY = tester.getTopLeft(editProfileFinder).dy;
      final createBandY = tester.getTopLeft(createBandFinder).dy;
      expect(editProfileY, lessThan(createBandY));
    });

    testWidgets('/edit-band route successfully opens EditBandInfoScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService);
      final band = Band(id: 'band_123', name: 'Direct Route Band');

      await tester.pumpWidget(createSettingsTestWidget(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/edit-band', arguments: band);
              },
              child: const Text('Go to Edit Band'),
            ),
          ),
        ),
        appState,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go to Edit Band'));
      await tester.pumpAndSettle();

      expect(find.byType(EditBandInfoScreen), findsOneWidget);
      expect(find.text('Direct Route Band'), findsWidgets);
    });
  });

  group('EDIT-BAND-01: Add Members Clickable Row & Tap Handlers', () {
    testWidgets('Tapping anywhere on user row triggers member addition', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService, activeBandId: 'band_123');
      bool callbackInvoked = false;

      final testUser = UserProfile(
        userId: 'u_candidate',
        displayName: 'Alice Bassist',
        instruments: ['Bass', 'Backing Vocals'],
      );

      await tester.pumpWidget(createSettingsTestWidget(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 400,
                    height: 500,
                    child: AddMemberDialogContent(
                      bandId: 'band_123',
                      allUsers: [testUser],
                      existingMembers: const [],
                      onMemberAdded: () {
                        callbackInvoked = true;
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
        appState,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap on the user's name text in the row
      await tester.tap(find.text('Alice Bassist'));
      await tester.pumpAndSettle();

      expect(mockService.addedMembers.length, 1);
      expect(mockService.addedMembers.first['userId'], 'u_candidate');
      expect(mockService.addedMembers.first['bandId'], 'band_123');
      expect(callbackInvoked, isTrue);
      expect(find.text('Alice Bassist added to the band!'), findsOneWidget);
    });

    testWidgets('Tapping + icon button also triggers member addition', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService, activeBandId: 'band_123');
      bool callbackInvoked = false;

      final testUser = UserProfile(
        userId: 'u_drummer',
        displayName: 'Dave Drummer',
        instruments: ['Drums'],
      );

      await tester.pumpWidget(createSettingsTestWidget(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 400,
                    height: 500,
                    child: AddMemberDialogContent(
                      bandId: 'band_123',
                      allUsers: [testUser],
                      existingMembers: const [],
                      onMemberAdded: () {
                        callbackInvoked = true;
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
        appState,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap on the + icon directly
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(mockService.addedMembers.length, 1);
      expect(mockService.addedMembers.first['userId'], 'u_drummer');
      expect(callbackInvoked, isTrue);
    });

    testWidgets('Rapid multiple taps do not add the member twice', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      mockService.addMemberCompleter = Completer<void>();
      final appState = MockSettingsAppState(mockService, activeBandId: 'band_123');

      final testUser = UserProfile(
        userId: 'u_guitarist',
        displayName: 'Gary Guitar',
        instruments: ['Guitar'],
      );

      await tester.pumpWidget(createSettingsTestWidget(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 400,
                    height: 500,
                    child: AddMemberDialogContent(
                      bandId: 'band_123',
                      allUsers: [testUser],
                      existingMembers: const [],
                      onMemberAdded: () {},
                    ),
                  ),
                ),
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
        appState,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Double tap rapidly before completer finishes
      await tester.tap(find.text('Gary Guitar'));
      await tester.tap(find.text('Gary Guitar'));
      await tester.pump();

      // Complete async addition
      mockService.addMemberCompleter!.complete();
      await tester.pumpAndSettle();

      expect(mockService.addedMembers.length, 1, reason: 'Member must not be added multiple times on rapid taps');
    });
  });

  group('EDIT-BAND-01: Map View Explanatory Text', () {
    const expectedHelperText =
        'The band’s official location for "Map View" where sound snippets from rehearsals and concerts, recorded music, etc. may be uploaded. Example: 1. Same as "Rehearsal Location" 2. Bandleader’s Address a.o.';

    testWidgets('Map View explanatory text appears in CreateBandScreen directly beneath correct field', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService);

      await tester.pumpWidget(createSettingsTestWidget(const CreateBandScreen(), appState));
      await tester.pumpAndSettle();

      final labelFinder = find.text('Map view location (if other than Rehearsal Location)');
      final helperFinder = find.text(expectedHelperText);
      final inputFinder = find.widgetWithText(TextFormField, 'Tap to input location for Map View Pin');

      expect(labelFinder, findsOneWidget);
      expect(helperFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);

      final labelY = tester.getTopLeft(labelFinder).dy;
      final helperY = tester.getTopLeft(helperFinder).dy;
      final inputY = tester.getTopLeft(inputFinder).dy;

      expect(labelY, lessThan(helperY), reason: 'Label must be above explanatory text');
      expect(helperY, lessThan(inputY), reason: 'Explanatory text must be above input field');
    });

    testWidgets('Map View explanatory text appears in EditBandInfoScreen directly beneath correct field', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockSettingsFirebaseService();
      final appState = MockSettingsAppState(mockService);
      final band = Band(id: 'b1', name: 'Test Band');

      await tester.pumpWidget(createSettingsTestWidget(EditBandInfoScreen(band: band), appState));
      await tester.pumpAndSettle();

      final labelFinder = find.text('Map view location (if other than Rehearsal Location)');
      final helperFinder = find.text(expectedHelperText);
      final inputFinder = find.widgetWithText(TextFormField, 'Tap to input location for Map View Pin');

      expect(labelFinder, findsOneWidget);
      expect(helperFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);

      final labelY = tester.getTopLeft(labelFinder).dy;
      final helperY = tester.getTopLeft(helperFinder).dy;
      final inputY = tester.getTopLeft(inputFinder).dy;

      expect(labelY, lessThan(helperY), reason: 'Label must be above explanatory text');
      expect(helperY, lessThan(inputY), reason: 'Explanatory text must be above input field');
    });
  });
}
