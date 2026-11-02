import 'package:flutter/widgets.dart';

/// Choose the paragraph base direction without changing text or selection.
final _letter = RegExp(r'\p{L}', unicode: true);

TextDirection contentDirection(String text, TextDirection fallback) {
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    if (!_letter.hasMatch(character)) continue;
    return (rune >= 0x0590 && rune <= 0x08ff) ||
            (rune >= 0xfb1d && rune <= 0xfdff) ||
            (rune >= 0xfe70 && rune <= 0xfeff)
        ? TextDirection.rtl
        : TextDirection.ltr;
  }
  return RegExp(r'[0-9٠-٩۰-۹]').hasMatch(text) ? TextDirection.ltr : fallback;
}
