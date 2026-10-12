/// Formats monetary values using Swedish separators and an ISO currency code.
///
/// Example: `1000000` becomes `1.000.000,00 SEK`.
class CurrencyFormatter {
  const CurrencyFormatter._();

  static String format(num amount, {String currencyCode = 'SEK'}) {
    return formatMinorUnits((amount * 100).round(), currencyCode: currencyCode);
  }

  static String formatMinorUnits(
    int minorUnits, {
    String currencyCode = 'SEK',
  }) {
    final isNegative = minorUnits < 0;
    final absoluteMinorUnits = minorUnits.abs();
    final wholeUnits = absoluteMinorUnits ~/ 100;
    final decimals = (absoluteMinorUnits % 100).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';
    final code = currencyCode.trim().isEmpty
        ? 'SEK'
        : currencyCode.trim().toUpperCase();

    return '$sign${formatWholeUnits(wholeUnits)},$decimals $code';
  }

  static String formatWholeUnits(int amount) {
    final isNegative = amount < 0;
    final digits = amount.abs().toString();
    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[index]);
    }

    return '${isNegative ? '-' : ''}$buffer';
  }

  /// Parses Swedish input such as `1.000.000,50`.
  ///
  /// Plain values and the common decimal-dot form (`4500.50`) are accepted as
  /// well, so existing listings can be edited without changing their value.
  static double? parse(String? text) {
    if (text == null || text.trim().isEmpty) return null;

    var value = text.trim().replaceAll(RegExp(r'[^0-9,\.\-]'), '');
    if (value.isEmpty || value == '-') return null;

    final isNegative = value.startsWith('-');
    value = value.replaceAll('-', '');
    if (value.isEmpty) return null;

    final commaCount = ','.allMatches(value).length;
    final dotCount = '.'.allMatches(value).length;
    String normalized;

    if (commaCount > 0 && dotCount > 0) {
      final decimalSeparator = value.lastIndexOf(',') > value.lastIndexOf('.')
          ? ','
          : '.';
      final thousandsSeparator = decimalSeparator == ',' ? '.' : ',';
      normalized = value.replaceAll(thousandsSeparator, '');
      normalized = normalized.replaceAll(decimalSeparator, '.');
    } else if (commaCount > 0 || dotCount > 0) {
      final separator = commaCount > 0 ? ',' : '.';
      final separatorCount = commaCount > 0 ? commaCount : dotCount;
      final lastSeparator = value.lastIndexOf(separator);
      final fractionLength = value.length - lastSeparator - 1;

      if (separatorCount > 1 || fractionLength == 3) {
        normalized = value.replaceAll(separator, '');
      } else {
        normalized = value.replaceAll(separator, '.');
      }
    } else {
      normalized = value;
    }

    final parsed = double.tryParse('${isNegative ? '-' : ''}$normalized');
    return parsed?.isFinite == true ? parsed : null;
  }
}
