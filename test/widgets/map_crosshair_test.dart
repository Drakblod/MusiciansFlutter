import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/widgets/map_crosshair.dart';

void main() {
  group('MAP-01 MapCrosshair Widget Presentation Tests', () {
    testWidgets('1. Mobile layout renders responsive 56x56 crosshair', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: MapCrosshair())),
        ),
      );

      final size = tester.getSize(find.byType(MapCrosshair));
      expect(size.width, equals(56.0));
      expect(size.height, equals(56.0));

      expect(find.byType(IgnorePointer), findsWidgets);
    });

    testWidgets('2. Desktop/Web layout renders responsive 64x64 crosshair', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: MapCrosshair())),
        ),
      );

      final size = tester.getSize(find.byType(MapCrosshair));
      expect(size.width, equals(64.0));
      expect(size.height, equals(64.0));
    });

    testWidgets(
      '3. Target acquired state updates styling without altering layout size',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: MapCrosshair(isTargetAcquired: false)),
            ),
          ),
        );

        final sizeNormal = tester.getSize(find.byType(MapCrosshair));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: MapCrosshair(isTargetAcquired: true)),
            ),
          ),
        );

        final sizeAcquired = tester.getSize(find.byType(MapCrosshair));
        expect(sizeNormal, equals(sizeAcquired));
        expect(sizeAcquired.width, equals(56.0));
      },
    );
  });
}
