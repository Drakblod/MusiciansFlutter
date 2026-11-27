// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/event_address_map.dart';
import 'package:musicians_flutter/widgets/open_event_address_button.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final opened = <Uri>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(Uri.parse(url));
    return true;
  }
}

void main() {
  test(
    'generic place fields link street addresses, not cities or online links',
    () {
      const address = 'Strandvägen 12B, Stockholm';
      expect(eventLocationMapUri(address)?.queryParameters['query'], address);
      for (final location in [
        null,
        '',
        'Stockholm, Sverige',
        '114 57 Stockholm',
        'https://example.com/meet/123',
        'Remote',
        '59.33, 18.07',
      ]) {
        expect(eventLocationMapUri(location), isNull, reason: '$location');
      }
      // The existing dedicated Street Address field retains its behavior.
      expect(
        eventAddressMapUri(
          'Turistvägen 3',
          city: 'Järvsö',
        )?.queryParameters['query'],
        'Turistvägen 3, Järvsö',
      );
    },
  );

  testWidgets(
    'preview follows edited text and opens only the current address',
    (tester) async {
      final launcher = _RecordingLauncher();
      final original = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = original);
      final controller = TextEditingController(text: 'Stockholm, Sverige');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EventAddressFieldLink(controller: controller)),
        ),
      );
      final button = find.text('Open in Google Maps');
      expect(button, findsNothing);
      controller.text = 'Strandvägen 12, Stockholm';
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(launcher.opened.single.host, 'www.google.com');
      expect(launcher.opened.single.queryParameters['query'], controller.text);
      controller.clear();
      await tester.pump();
      expect(button, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
