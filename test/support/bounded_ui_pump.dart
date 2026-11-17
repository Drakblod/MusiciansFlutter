import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:musicians_flutter/models/canonical_location.dart';
import 'package:musicians_flutter/widgets/location_picker_field.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';

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

Future<void> selectBlues(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await pumpUiTransitions(tester);
  final sheet = find.byType(SearchableCategoryMultiSelectSheet);
  final search = find.descendant(of: sheet, matching: find.byType(TextField));
  await tester.enterText(search, 'Blues');
  await pumpUiTransitions(tester);
  final option = find.descendant(
    of: sheet,
    matching: find.byWidgetPredicate((widget) => widget is Text && widget.data == 'Blues'),
  );
  if (option.evaluate().isEmpty) {
    await tester.tap(find.descendant(
      of: sheet,
      matching: find.text('🎸 Rock, Pop, R&B, Hip Hop, etc'),
    ));
    await pumpUiTransitions(tester);
  }
  expect(option, findsOneWidget);
  await tester.ensureVisible(option);
  await tester.tap(option);
  await pumpUiTransitions(tester);
  expect(find.descendant(of: sheet, matching: find.textContaining('Selected')), findsOneWidget);
  await tester.tap(find.descendant(of: sheet, matching: find.textContaining('Done')));
  await pumpUiTransitions(tester);
}
