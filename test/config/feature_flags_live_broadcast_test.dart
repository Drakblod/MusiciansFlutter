import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/config/feature_flags.dart';

void main() {
  group('Feature Flags SEND-LIVE-01 Isolation Tests', () {
    test('1. Real Live broadcasts require an explicit build opt-in', () {
      expect(FeatureFlags.enableRealLiveBroadcasts,
          const bool.fromEnvironment('ENABLE_LIVE_BROADCASTS'));
    });

    test('2. enableMockLiveRehearsals remains enabled (non-breaking preservation)', () {
      expect(FeatureFlags.enableMockLiveRehearsals, isTrue,
          reason: 'Mock rehearsal prototype on Discovery Map must remain active.');
    });
  });
}
