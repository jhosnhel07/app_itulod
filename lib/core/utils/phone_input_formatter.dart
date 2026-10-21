import 'package:flutter/services.dart';

/// Formats a PH mobile number as it is typed: `0917 123 4567` (web twin:
/// formatPhoneMobile + attachInputMask in js/utils.js). Digits only, at most
/// 11; a pasted "9171234567" gets its leading 0. Save it with
/// Validators.normalizePhone, which strips the spaces again.
class PhPhoneInputFormatter extends TextInputFormatter {
  const PhPhoneInputFormatter();

  static String format(String value) {
    var d = value.replaceAll(RegExp(r'\D'), '');
    if (d.isNotEmpty && d[0] != '0') d = '0$d';
    if (d.length > 11) d = d.substring(0, 11);
    final parts = [
      d.substring(0, d.length.clamp(0, 4)),
      if (d.length > 4) d.substring(4, d.length.clamp(4, 7)),
      if (d.length > 7) d.substring(7),
    ];
    return parts.where((p) => p.isNotEmpty).join(' ');
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    // Keep the cursor after the same number of digits it was after.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    var digitsBefore = newValue.text.substring(0, cursor).replaceAll(RegExp(r'\D'), '').length;
    if (newValue.text.isNotEmpty && !newValue.text.startsWith(RegExp(r'\D*0')) && digitsBefore > 0) {
      digitsBefore++; // the 0 that format() added in front
    }
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < digitsBefore) {
      if (text[offset] != ' ') seen++;
      offset++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
