import 'package:flutter_test/flutter_test.dart';
import 'package:musicians_flutter/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats amounts with Swedish separators and two decimals', () {
      expect(CurrencyFormatter.format(0), '0,00 SEK');
      expect(CurrencyFormatter.format(1500), '1.500,00 SEK');
      expect(CurrencyFormatter.format(1000000), '1.000.000,00 SEK');
      expect(
        CurrencyFormatter.format(1234.5, currencyCode: 'eur'),
        '1.234,50 EUR',
      );
    });

    test('formats exact minor units', () {
      expect(CurrencyFormatter.formatMinorUnits(150050), '1.500,50 SEK');
    });

    test('parses Swedish and legacy numeric input', () {
      expect(CurrencyFormatter.parse('1.000.000,00 SEK'), 1000000);
      expect(CurrencyFormatter.parse('4 500,50'), 4500.5);
      expect(CurrencyFormatter.parse('4500.50'), 4500.5);
      expect(CurrencyFormatter.parse('1,500'), 1500);
      expect(CurrencyFormatter.parse('not a price'), isNull);
    });
  });
}
