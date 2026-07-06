import 'package:flutter/material.dart';

/// Parse a `#rrggbb` (or `#aarrggbb`) hex string into a Color. Falls back to [fallback].
Color hexToColor(String hex, {Color fallback = Colors.black}) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'ff$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}

/// Validate/normalize a user-entered hex color (`#e18a24`, `e18a24`, or 3-digit `#e82`)
/// into canonical `#rrggbb`, or null if it isn't a valid hex color.
String? normalizeHexColor(String input) {
  var h = input.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length != 6 || int.tryParse(h, radix: 16) == null) return null;
  return '#${h.toLowerCase()}';
}

/// Serialize a Color back to a `#rrggbb` hex string (drops alpha).
String colorToHex(Color c) {
  int ch(double v) => (v * 255).round() & 0xff;
  final r = ch(c.r).toRadixString(16).padLeft(2, '0');
  final g = ch(c.g).toRadixString(16).padLeft(2, '0');
  final b = ch(c.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
