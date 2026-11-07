import 'package:flutter/foundation.dart';

class FeatureToggles {
  // Set to 'false' to instantly rollback the experimental dynamic home view design
  static const bool useExperimentalHomeView = true;

  // Set to 'false' to instantly revert Map View icon back to inside Gigs list page
  static const bool showMapInTopBar = true;

  // Demo calendar data is available only in local debug builds.
  static const bool useMockPublicEventCalendar = kDebugMode;

  // Set to 'false' to hide Edit Band from the regular Settings menu until complete
  static const bool showEditBandInSettings = true;
}
