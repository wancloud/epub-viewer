import 'package:flutter/material.dart';

/// Parse a `#rrggbb` (or `#aarrggbb`) hex string into a Color. Falls back to [fallback].
Color hexToColor(String hex, {Color fallback = Colors.black}) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'ff$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}

/// Serialize a Color back to a `#rrggbb` hex string (drops alpha).
String colorToHex(Color c) {
  int ch(double v) => (v * 255).round() & 0xff;
  final r = ch(c.r).toRadixString(16).padLeft(2, '0');
  final g = ch(c.g).toRadixString(16).padLeft(2, '0');
  final b = ch(c.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
