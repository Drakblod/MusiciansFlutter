import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectVisibleTabLabels(WidgetTester tester, List<String> expected) {
  final bar = find.byType(TabBar);
  expect(bar, findsOneWidget);
  final labels = tester
      .widgetList<Text>(find.descendant(of: bar, matching: find.byType(Text), skipOffstage: false))
      .map((text) => text.data ?? text.textSpan?.toPlainText())
      .whereType<String>()
      .toList();
  final orderingPrefix = RegExp(r'^\s*\d+(?:[.):,–—-]|\s+)');
  expect(labels.where(orderingPrefix.hasMatch), isEmpty);
  expect(labels, expected);
}
