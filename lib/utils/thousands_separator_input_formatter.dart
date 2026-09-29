import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats numeric input with comma thousands separators (e.g. 1500 -> 1,500)
/// while maintaining a stable cursor position and returning integer values.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###', 'en_US');

  static String format(int? value) {
    if (value == null) return '';
    if (value == 0) return '0';
    return _formatter.format(value);
  }

  static int? parse(String? text) {
    if (text == null) return null;
    final digits = text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final intVal = int.tryParse(digits);
    if (intVal == null) {
      return oldValue;
    }

    final newFormatted = _formatter.format(intVal);

    // Calculate number of digits to the left of the cursor in newValue
    final int baseOffset = newValue.selection.baseOffset;
    final int safeOffset = baseOffset < 0
        ? newValue.text.length
        : baseOffset.clamp(0, newValue.text.length);
    final int digitsBeforeCursor = newValue.text
        .substring(0, safeOffset)
        .replaceAll(RegExp(r'[^\d]'), '')
        .length;

    // Find the offset in newFormatted that contains exactly digitsBeforeCursor digits
    int newCursorOffset = 0;
    int countedDigits = 0;
    for (int i = 0; i < newFormatted.length; i++) {
      if (RegExp(r'\d').hasMatch(newFormatted[i])) {
        countedDigits++;
      }
      if (countedDigits == digitsBeforeCursor) {
        newCursorOffset = i + 1;
        break;
      }
    }

    if (digitsBeforeCursor == 0) {
      newCursorOffset = 0;
    } else if (newCursorOffset == 0) {
      newCursorOffset = newFormatted.length;
    }

    return TextEditingValue(
      text: newFormatted,
      selection: TextSelection.collapsed(
        offset: newCursorOffset.clamp(0, newFormatted.length),
      ),
    );
  }
}
