import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/services/firebase_service.dart';
import 'package:musicians_flutter/models/user_profile.dart';

class MockFirebaseServiceForMapTest extends FirebaseService {
  @override
  Future<Set<String>> getUserAppliedSubRequestIdsAsync(String userId) async => {};

  @override
  Future<List<dynamic>> getSubRequestsAsync() async => [];
}

class MockAppStateForMapTest extends AppState {
  final MockFirebaseServiceForMapTest _service = MockFirebaseServiceForMapTest();

  @override
  FirebaseService get firebaseService => _service;

  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'u1', displayName: 'Test User');

  @override
  String? get currentUserId => 'u1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Map View displays clickable "What is Map View?" box and dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => MockAppStateForMapTest(),
        child: const MaterialApp(
          home: GigMapPage(),
        ),
      ),
    );
    await tester.pump();

    const expectedGuideText =
        'Move pins towards the centre of the screen (telescopic sight) to hear different bands and their recordings, band info, gig promo, etc';

    final guideFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(expectedGuideText),
    );
    final whatIsFinder = find.byWidgetPredicate(
      (w) => (w is Text && (w.data?.contains('What is Map View') ?? false)) ||
          (w is RichText && w.text.toPlainText().contains('What is Map View')),
    );

    // Verify title and exact text of the clickable box
    expect(whatIsFinder, findsWidgets);
    expect(guideFinder, findsOneWidget);

    // Tap the clickable box to open dialog
    await tester.tap(guideFinder);
    await tester.pump(const Duration(milliseconds: 300));

    // Verify dialog opens with guide and Got it button
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('HOW TO EXPLORE & LISTEN:'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Got it'), findsNothing);

    // Tap dismiss button on banner
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump(const Duration(milliseconds: 300));

    // Box is dismissed, floating re-open button appears
    expect(guideFinder, findsNothing);
    expect(find.text('What is Map View?'), findsOneWidget);

    // Tap re-open button
    await tester.tap(find.text('What is Map View?'));
    await tester.pump(const Duration(milliseconds: 300));

    // Box is restored
    expect(guideFinder, findsOneWidget);
  });
}
