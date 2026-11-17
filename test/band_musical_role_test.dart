import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/data/skills_taxonomy.dart';
import 'package:musicians_flutter/models/band.dart';
import 'package:musicians_flutter/models/user_profile.dart';
import 'package:musicians_flutter/widgets/band_musical_role_picker.dart';
import 'package:musicians_flutter/widgets/searchable_category_multi_select_sheet.dart';
import 'support/bounded_ui_pump.dart';

Finder inMusicalRolePicker(Finder matching) => find.descendant(
  of: find.byType(SearchableCategoryMultiSelectSheet),
  matching: matching,
);

Future<void> chooseMusicalRole(WidgetTester tester, String label) async {
  final search = inMusicalRolePicker(find.byType(TextField));
  await tester.enterText(search, label);
  await pumpUiTransitions(tester);
  final option = musicalRoleOption(label);
  await tester.ensureVisible(option);
  await tester.tap(option);
}

Finder musicalRoleOption(String label) => inMusicalRolePicker(
  find.byWidgetPredicate((widget) => widget is Text && widget.data == label),
);

void main() {
  test('server allowlist matches every exact value exposed by the picker', () {
    final clientValues = {
      SkillsTaxonomy.featuredRolePersistedValue,
      for (final labels in BandMusicalRolePicker.categories.values)
        for (final label in labels)
          SkillsTaxonomy.getPersistedValueForDisplayLabel(label),
    };
    final serverValues =
        (jsonDecode(
                  File(
                    'firebase_functions/band_musical_roles.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<String>();
    expect(serverValues, unorderedEquals(clientValues));
    expect(
      serverValues,
      containsAll(['BANDLEADER', 'Trumpet', 'Vocalist', 'Drums']),
    );
    for (final excluded in ['Leader', 'Admin', 'MOD', 'Other']) {
      expect(serverValues, isNot(contains(excluded)));
    }
  });

  test(
    'canonical role remains separate and legacy profile label is a fallback',
    () {
      final legacy = BandMember.fromJson({'Role': 'MOD'}, 'legacy');
      final profile = UserProfile(instruments: ['Electric Guitar']);
      expect(legacy.musicalRole, isNull);
      expect(legacy.toJson().containsKey('MusicalRole'), isFalse);
      expect(
        BandMusicalRolePicker.memberLabel(legacy, profile),
        'Electric Guitar',
      );
      expect(BandMusicalRolePicker.memberLabel(legacy, null), isEmpty);
      final updated = BandMember.fromJson({
        ...legacy.toJson(),
        'MusicalRole': 'BANDLEADER',
      }, 'legacy');
      expect(updated.toJson()['Role'], 'MOD');
      expect(updated.toJson()['MusicalRole'], 'BANDLEADER');
      expect(BandMusicalRolePicker.memberLabel(updated, profile), 'BANDLEADER');
      expect(BandMusicalRolePicker.canEdit(updated, legacy), isFalse);
    },
  );

  testWidgets(
    'band prompt and selection work on a narrow screen with the keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      String? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    value = await BandMusicalRolePicker.show(context, 'Alex'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Which instrument or role would you like Alex to take on in this particular band?',
        ),
        findsOneWidget,
      );
      final search = inMusicalRolePicker(find.byType(TextField));
      await tester.tap(search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 390);
      await tester.enterText(search, 'Trumpet');
      await tester.pumpAndSettle();
      final option = musicalRoleOption('Trumpet');
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      expect(option.hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(option).dy, lessThanOrEqualTo(178));
      expect(
        tester
            .widget<EditableText>(
              inMusicalRolePicker(find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(value, 'Trumpet');
      expect(tester.takeException(), isNull);
    },
  );
}
