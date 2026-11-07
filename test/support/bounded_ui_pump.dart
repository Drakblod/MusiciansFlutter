import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/widgets/location_picker_field.dart';

/// A confirmed location fixture for publication tests. Picker behavior itself
/// is covered separately; these tests must not depend on removed geocoding
/// fallbacks or make external map/geocoding requests.
void confirmRequestLocations(WidgetTester tester) {
  for (final field in tester.widgetList<LocationPickerField>(find.byType(LocationPickerField))) {
    final label = field.controller.text.trim().isEmpty ? 'Stockholm' : field.controller.text.trim();
    field.controller.text = label;
    field.onLocationChanged?.call(CanonicalLocation(
      locationLabel: label, latitude: 59.3293, longitude: 18.0686,
      precision: field.effectiveCityOnly ? LocationPrecision.city : LocationPrecision.exact,
      status: LocationResolutionStatus.resolved,
    ));
  }
}

/// Advances the finite transitions used by these screens while their shared
/// navigation globe continues animating. Assertions still inspect the resulting
/// widgets and surface pending loading states or errors instead of waiting for
/// the decorative animation to become idle.
Future<void> pumpUiTransitions(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
