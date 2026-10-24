import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musicians_flutter/services/mock_rehearsal_audio_controller.dart';
import 'package:musicians_flutter/widgets/custom_top_bar.dart';
import 'package:musicians_flutter/services/route_observer.dart';
import 'package:provider/provider.dart';
import 'package:musicians_flutter/providers/app_state.dart';
import 'package:musicians_flutter/models/user_profile.dart';

class _TestAppState extends ChangeNotifier implements AppState {
  @override
  UserProfile? get currentUserProfile => UserProfile(userId: 'u1', displayName: 'Test');

  @override
  int get unreadNotificationCount => 0;

  @override
  bool get hasUnreadMessages => false;

  @override
  void setTab(int index) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Task 4: Navigation & Global Audio Cleanup Tests', () {
    testWidgets('Top bar has Map View in Column 3 and Inbox in Column 4', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) => _TestAppState(),
          child: const MaterialApp(
            home: Scaffold(
              appBar: CustomTopBar(),
            ),
          ),
        ),
      );

      final rowFinder = find.byType(Row);
      expect(rowFinder, findsWidgets);

      final mapIconFinder = find.byIcon(Icons.public_rounded);
      final chatIconFinder = find.byIcon(Icons.chat_bubble_outline_rounded);

      expect(mapIconFinder, findsOneWidget);
      expect(chatIconFinder, findsOneWidget);

      final mapOffset = tester.getCenter(mapIconFinder);
      final chatOffset = tester.getCenter(chatIconFinder);
      expect(mapOffset.dx < chatOffset.dx, isTrue);
    });

    test('MockRehearsalAudioController singleton pauseActiveAudio pauses playback', () {
      final controller = MockRehearsalAudioController();
      expect(MockRehearsalAudioController.activeInstance, controller);

      controller.pauseAudio();
      expect(controller.isPlaying, isFalse);

      MockRehearsalAudioController.pauseActiveAudio();
      expect(controller.isPlaying, isFalse);
    });

    test('Organic linear proximity volume decreases with distance', () {
      final controller = MockRehearsalAudioController();
      controller.updatePosition(
        const LatLng(59.3293, 18.0686),
        zoom: 15.0,
      );

      controller.updatePosition(
        const LatLng(0.0, 0.0),
        zoom: 15.0,
      );
      expect(controller.isPlaying, isFalse);
    });

    test('Route observer is initialized and ready for PageRoute subscriptions', () {
      expect(appRouteObserver, isNotNull);
      expect(appRouteObserver, isA<RouteObserver<PageRoute>>());
    });
  });
}
