import 'package:flutter/foundation.dart';

class FeatureToggles {
  // Set to 'false' to instantly rollback the experimental dynamic home view design
  static const bool useExperimentalHomeView = true;

  // Map View is off in the default release build.
  static const bool enableMapView = bool.fromEnvironment('ENABLE_MAP_VIEW');

  // When Map View is enabled, this selects the top bar or Find Gigs entry.
  static const bool showMapInTopBar = true;

  // Demo calendar data is available only in local debug builds.
  static const bool useMockPublicEventCalendar = kDebugMode;

  // Set to 'false' to hide Edit Band from the regular Settings menu until complete
  static const bool showEditBandInSettings = true;
}
