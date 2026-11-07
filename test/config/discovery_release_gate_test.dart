import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:musicians_flutter/main.dart';
import 'package:musicians_flutter/views/gig_map_page.dart';

void main() {
  const mapEnabled = bool.fromEnvironment('ENABLE_MAP_VIEW');
  const liveEnabled = bool.fromEnvironment('ENABLE_LIVE_BROADCASTS');

  for (final path in ['/gig-map', '/live', '/go-live', '/live-broadcast/old-id']) {
    testWidgets('$path resolves through the discovery availability gate',
        (tester) async {
      final isMap = path == '/gig-map';
      final enabled = mapEnabled && (isMap || liveEnabled);
      if (enabled) {
        final route = MyApp.buildDiscoveryRoute(RouteSettings(name: path))
            as MaterialPageRoute<void>;
        // Inspect the enabled route without mounting its real network services.
        Widget? destination;
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            destination = route.builder(context);
            return const SizedBox.shrink();
          }),
        ));
        expect(destination, isA<GigMapPage>());
        return;
      }

      // Deliberately leave Firebase uninitialized. Mounting the Map or Live
      // implementation here would attempt to access its platform services.
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: MyApp.buildDiscoveryRoute,
        routes: {
          '/': (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/ordinary'),
              child: const Text('Open another screen'),
            ),
          ),
          '/ordinary': (_) => const Scaffold(body: Text('Ordinary route')),
        },
        initialRoute: path,
      ));
      await tester.pumpAndSettle();
      expect(
        find.text(isMap
            ? 'Map View currently unavailable.'
            : 'Live broadcasts currently unavailable.'),
        findsOneWidget,
      );
      expect(find.byType(GigMapPage), findsNothing);
      expect(find.byType(GoogleMap), findsNothing);
      expect(find.textContaining('Go Live'), findsNothing);
      expect(find.textContaining('Upload Map View Pin'), findsNothing);
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.byType(Scaffold)))
          .popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open another screen'));
      await tester.pumpAndSettle();
      expect(find.text('Ordinary route'), findsOneWidget);
    });
  }
}
