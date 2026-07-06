// Configurable quote-pair dialogue detection.
//
// Port of the PySide6 app's `epubviewer/dialogue_rules.py` (see backup/pyside6/).
// Pure logic, no Flutter dependency, so it is unit-testable in isolation.

/// A pair of quote markers that denotes dialogue, plus the color to render it in.
/// `color` is a hex string like `#1a5fb4` (kept as a string to match the persisted
/// settings format; the UI converts it to a Flutter Color).
class QuotePair {
  final String open;
  final String close;
  final String color;
  final bool enabled;

  const QuotePair({
    required this.open,
    required this.close,
    required this.color,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() =>
      {'open': open, 'close': close, 'color': color, 'enabled': enabled};

  factory QuotePair.fromJson(Map<String, dynamic> data) => QuotePair(
        open: data['open'] as String,
        close: data['close'] as String,
        color: data['color'] as String,
        enabled: data['enabled'] as bool? ?? true,
      );

  QuotePair copyWith({String? open, String? close, String? color, bool? enabled}) =>
      QuotePair(
        open: open ?? this.open,
        close: close ?? this.close,
        color: color ?? this.color,
        enabled: enabled ?? this.enabled,
      );
}

class DialogueConfig {
  final List<QuotePair> pairs;

  const DialogueConfig({this.pairs = const []});

  Map<String, dynamic> toJson() => {'pairs': pairs.map((p) => p.toJson()).toList()};

  factory DialogueConfig.fromJson(Map<String, dynamic> data) => DialogueConfig(
        pairs: ((data['pairs'] as List?) ?? [])
            .map((p) => QuotePair.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  List<QuotePair> enabledPairs() =>
      pairs.where((p) => p.enabled && p.open.isNotEmpty && p.close.isNotEmpty).toList();
}

/// A detected dialogue run: [start, end) offsets into the source text (end exclusive,
/// includes the marker characters) plus the hex color to render it in.
class DialogueSpan {
  final int start;
  final int end;
  final String color;
  const DialogueSpan(this.start, this.end, this.color);
}

/// Scan [text] for dialogue delimited by any enabled quote pair in [config].
///
/// Returns a sorted, non-overlapping list of spans.
///
/// Markers where open == close (e.g. plain " or ') are treated as toggles: the first
/// occurrence opens a span, the next occurrence of that same character closes it.
/// Markers with distinct open/close characters (e.g. 「」, «») are matched with a stack,
/// so different pair types may nest; an unmatched trailing open is left unstyled.
List<DialogueSpan> findDialogueSpans(String text, DialogueConfig config) {
  final pairs = config.enabledPairs();
  if (pairs.isEmpty || text.isEmpty) return [];

  final sameCharPairs = <String, QuotePair>{};
  final openToPair = <String, QuotePair>{};
  final closeToPair = <String, QuotePair>{};
  for (final p in pairs) {
    if (p.open == p.close) {
      sameCharPairs[p.open] = p;
    } else {
      openToPair[p.open] = p;
      closeToPair[p.close] = p;
    }
  }

  final spans = <DialogueSpan>[];
  final stack = <_OpenMark>[]; // distinct-char open markers awaiting a close
  final openSame = <String, int>{}; // same-char markers currently toggled open

  // Iterate by Unicode code unit index so offsets match Dart String indexing (which the
  // renderer also uses). Quote markers here are all in the BMP (single code units).
  final chars = text.split('');
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];

    if (sameCharPairs.containsKey(ch)) {
      if (openSame.containsKey(ch)) {
        final start = openSame.remove(ch)!;
        spans.add(DialogueSpan(start, i + 1, sameCharPairs[ch]!.color));
      } else {
        openSame[ch] = i;
      }
      continue;
    }

    if (openToPair.containsKey(ch)) {
      stack.add(_OpenMark(openToPair[ch]!, i));
      continue;
    }

    if (closeToPair.containsKey(ch)) {
      final pair = closeToPair[ch]!;
      for (var depth = stack.length - 1; depth >= 0; depth--) {
        if (identical(stack[depth].pair, pair)) {
          final start = stack[depth].index;
          stack.removeRange(depth, stack.length);
          spans.add(DialogueSpan(start, i + 1, pair.color));
          break;
        }
      }
    }
  }

  spans.sort((a, b) => a.start.compareTo(b.start));
  return _removeOverlaps(spans);
}

class _OpenMark {
  final QuotePair pair;
  final int index;
  const _OpenMark(this.pair, this.index);
}

List<DialogueSpan> _removeOverlaps(List<DialogueSpan> spans) {
  final result = <DialogueSpan>[];
  var lastEnd = -1;
  for (final s in spans) {
    if (s.start >= lastEnd) {
      result.add(s);
      lastEnd = s.end;
    }
  }
  return result;
}
