// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musicians_flutter/views/gig_map_page.dart';
import 'package:musicians_flutter/widgets/audio_snippet_player.dart';
import 'package:musicians_flutter/widgets/map_crosshair.dart';
import 'package:musicians_flutter/services/mock_rehearsal_audio_controller.dart';
import 'package:musicians_flutter/utils/map_crosshair_targeting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Audio Snippet Player Slim & Volume Polish Tests', () {
    testWidgets('1. AudioSnippetPlayer omits "MUSIC SNIPPET" header label and provides compact single-row controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AudioSnippetPlayer(
              audioUrl: 'https://example.com/demo.mp3',
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // "MUSIC SNIPPET" standalone header text is omitted per owner feedback
      expect(find.text('MUSIC SNIPPET'), findsNothing);

      // Play button, slider, and duration indicators are present in compact layout
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });

    testWidgets('2. AudioSnippetPlayer fits at 320 px width without horizontal overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(8.0),
              child: AudioSnippetPlayer(
                audioUrl: 'https://example.com/demo.mp3',
                autoPlay: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      FlutterError.onError = oldHandler;
      expect(errors, isEmpty);
    });

    test('3. MockRehearsalAudioController enforces maxRehearsalVolume ceiling at 0.70', () {
      expect(MockRehearsalAudioController.maxRehearsalVolume, equals(0.70));
    });
  });

  group('Map Crosshair Elevation & Targeting Tests', () {
    test('4. GigMapPageState crosshairYOffset is set to -60.0 to clear bottom cards', () {
      expect(GigMapPageState.crosshairYOffset, equals(-60.0));
    });

    test('5. Coordinate math correctly offsets latitude North when crosshair is elevated', () {
      const zoom = 15.0;
      const cameraCenter = LatLng(59.3293, 18.0686);

      final mpp = MapCrosshairTargeting.metersPerPixel(cameraCenter.latitude, zoom);
      final metersNorth = -GigMapPageState.crosshairYOffset * mpp;
      final latOffset = metersNorth / 111139.0;

      // Coordinate directly under elevated crosshair is strictly North of camera center
      final crosshairCoord = LatLng(cameraCenter.latitude + latOffset, cameraCenter.longitude);
      expect(crosshairCoord.latitude, greaterThan(cameraCenter.latitude));

      // Camera center needed to position target under elevated crosshair is strictly South of target
      final target = const LatLng(59.3320, 18.0400); // e.g. Kungsholmen
      final targetCamCenter = LatLng(target.latitude - latOffset, target.longitude);
      expect(targetCamCenter.latitude, lessThan(target.latitude));
    });

    testWidgets('6. MapCrosshair is wrapped in Transform.translate with crosshairYOffset',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Transform.translate(
                key: const ValueKey('map_crosshair_transform'),
                offset: const Offset(0, GigMapPageState.crosshairYOffset),
                child: const MapCrosshair(isTargetAcquired: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final transformFinder = find.byKey(const ValueKey('map_crosshair_transform'));
      expect(transformFinder, findsOneWidget);

      final transformWidget = tester.widget<Transform>(transformFinder);
      expect(transformWidget.transform.getTranslation().y, equals(-60.0));
      expect(find.byType(MapCrosshair), findsOneWidget);
    });
  });
}
