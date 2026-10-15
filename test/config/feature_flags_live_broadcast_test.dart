import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/config/feature_flags.dart';

void main() {
  group('Feature Flags SEND-LIVE-01 Isolation Tests', () {
    test('1. enableRealLiveBroadcasts defaults strictly to false', () {
      expect(FeatureFlags.enableRealLiveBroadcasts, isFalse,
          reason: 'Real LiveKit streaming must be disabled by default during SEND-LIVE-01 MVP foundation.');
    });

    test('2. enableMockLiveRehearsals remains enabled (non-breaking preservation)', () {
      expect(FeatureFlags.enableMockLiveRehearsals, isTrue,
          reason: 'Mock rehearsal prototype on Discovery Map must remain active.');
    });
  });
}
