import 'package:musicians_flutter/models/sub_request.dart';
import 'support/bounded_ui_pump.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';

import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/views/edit_profile_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

class MockInstrumentFirebaseService extends FirebaseService {
  @override
  Future<List<SubRequest>> getUserSubRequestsAsync(String uid) async => [];

  @override
  bool get isLoggedIn => true;
  @override
  String? get currentUserId => 'test_user_inst';
  @override
  Future<void> initializePushNotifications() async {}
  @override
  Future<Map<String, int>> getButtonClicksAsync(String uid) async => {};

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'test_user_inst',
      displayName: 'Test Musician',
      email: 'test@example.com',
      genres: ['Rock'],
      instruments: ['Guitar'],
    );
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String uid) async => {'instrument_band':'Instrument Band'};
  @override
  Future<Band?> getBandInfoAsync(String bandId) async => Band(id: bandId, name: 'Instrument Band', membersBand: {'test_user_inst': BandMember(userId: 'test_user_inst', role: 'Leader', status: 'active')});

  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return [];
  }

  @override
  Future<List<UserProfile>> getAllUsersAsync() async {
    return [];
  }

}

class MockAppStateForInstrumentTest extends AppState {
  @override
  final FirebaseService firebaseService = MockInstrumentFirebaseService();

  @override
  UserProfile? get currentUserProfile => UserProfile(
        userId: 'test_user_inst',
        displayName: 'Test Musician',
        email: 'test@example.com',
        genres: ['Rock'],
        instruments: ['Guitar'],
      );

  @override
  String? get currentUserId => 'test_user_inst';
}

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<AppState>(
    create: (_) => MockAppStateForInstrumentTest(),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Master Instrument and Skills List Verification Tests', () {
    final expectedCategories = [
      'Songwriters/Lyricists/Producers/Engineers...',
      'Sessions',
      'Woodwinds',
      'Brass',
      'Strings',
      'Keyboards',
      'Percussion',
      'Miscellaneous Instruments',
      'Voices (Choir)',
      'Voices (Popular Music)',
      'Miscellaneous Voices',
    ];

    testWidgets('EditProfileScreen picker opens and contains updated categories and items', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const EditProfileScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final primaryField = find.text('Primary Skill/Talent (Select 1)');
      await tester.tap(primaryField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      expect(find.text('Sessions'), findsNothing);
      for (final cat in expectedCategories.where((cat) => cat != 'Sessions')) {
        if (cat.contains('(') && cat.contains('Voices')) {
          expect(
            find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText() == cat),
            findsOneWidget,
          );
        } else {
          expect(find.text(cat), findsOneWidget);
        }
      }

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('FindSubScreen picker opens and displays updated master category structure', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(const FindSubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await pumpUiTransitions(tester);
      final instrumentTitle = find.text('Role / Instrument');
      expect(instrumentTitle, findsOneWidget);

      await tester.tap(instrumentTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SearchableCategoryMultiSelectSheet), findsOneWidget);

      expect(find.text('Songwriters/Lyricists/Producers/Engineers...'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            (w is Text && w.data == 'Voices (Choir)') ||
            (w is RichText && w.text.toPlainText() == 'Voices (Choir)')),
        findsOneWidget,
      );
      expect(find.text('Miscellaneous Voices'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SearchableCategoryMultiSelectSheet)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
