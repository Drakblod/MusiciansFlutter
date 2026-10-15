import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/config/feature_flags.dart';

void main() {
  group('Feature Flags SEND-LIVE-01 Isolation Tests', () {
    test('1. enableRealLiveBroadcasts is enabled for live audio broadcasting testing', () {
      expect(FeatureFlags.enableRealLiveBroadcasts, isTrue,
          reason: 'Real LiveKit streaming is activated for live testing.');
    });

    test('2. enableMockLiveRehearsals remains enabled (non-breaking preservation)', () {
      expect(FeatureFlags.enableMockLiveRehearsals, isTrue,
          reason: 'Mock rehearsal prototype on Discovery Map must remain active.');
    });
  });
}
