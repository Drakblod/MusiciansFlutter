import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:musicians_flutter/views/register_screen.dart';
import 'package:musicians_flutter/views/find_gigs_screen.dart';
import 'package:musicians_flutter/views/collabs_landing_screen.dart';
import 'package:musicians_flutter/views/find_sub_screen.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/models/sub_request.dart';
import 'package:provider/provider.dart';

class MockFirebaseService extends FirebaseService {
  @override
  Future<List<String>> getFavoriteUserIdsAsync() async {
    return ['fav1'];
  }

  @override
  Future<UserProfile?> getUserProfileAsync([String? userId]) async {
    return UserProfile(
      userId: 'fav1',
      displayName: 'Favorite Artist',
      instruments: ['Guitar'],
    );
  }

  @override
  Future<List<SubRequest>> getAllSubRequestsAsync() async {
    return [];
  }

  @override
  Future<Map<String, String>> getUserBandsAsync(String userId) async {
    return {};
  }
}

class MockAppState extends AppState {
  @override
  final FirebaseService firebaseService = MockFirebaseService();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('P2 Tasks UI & Presentation Regression Tests', () {
    testWidgets(
      'COL-03: Favorites CheckboxListTile uses leading control affinity',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>(
            create: (_) => MockAppState(),
            child: const MaterialApp(home: CollabsLandingScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final favListButton = find.text('FAVORITES LIST');
        expect(favListButton, findsOneWidget);
        await tester.tap(favListButton);
        await tester.pumpAndSettle();

        final tiles = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(tiles, isNotEmpty);
        for (final tile in tiles) {
          expect(tile.controlAffinity, equals(ListTileControlAffinity.leading));
        }
      },
    );

    testWidgets('COL-04: Collaboration area helper text is not italic', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppState(),
          child: const MaterialApp(home: CollabsLandingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final textFinder = find.text('Tap to add area of collaboration...');
      expect(textFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.fontStyle, isNot(equals(FontStyle.italic)));
    });

    testWidgets(
      'FIND-02: Find Musician screen displays Gig/Event Details consistently',
      (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>(
            create: (_) => MockAppState(),
            child: const MaterialApp(home: FindSubScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Gig/Event Details'), findsNWidgets(2));
        expect(find.text('Gig/Rehearsal Details'), findsNothing);
        expect(find.text('Gig / Event Details'), findsNothing);
      },
    );

    testWidgets('REG-01: Profile Name field displays guidance helper text', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => MockAppState(),
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Preferably use your real name to make it easier for users to find you',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'GIG-03: Gigs list tab label remains Upcoming without false booked claim',
      (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>(
            create: (_) => MockAppState(),
            child: const MaterialApp(home: FindGigsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Upcoming'), findsOneWidget);
        expect(find.text('Upcoming (booked)'), findsNothing);
      },
    );
  });
}
