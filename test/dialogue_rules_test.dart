import 'package:epub_viewer/logic/dialogue_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the cases proven for the PySide6 version's find_dialogue_spans.
void main() {
  const cfg = DialogueConfig(pairs: [
    QuotePair(open: '「', close: '」', color: '#1a5fb4'),
    QuotePair(open: '"', close: '"', color: '#c01c28'),
    QuotePair(open: '«', close: '»', color: '#2ec27e'),
  ]);

  List<String> matched(String text, DialogueConfig c) =>
      findDialogueSpans(text, c).map((s) => text.substring(s.start, s.end)).toList();

  test('detects Japanese corner-bracket dialogue', () {
    final text = '地の文「こんにちは」地の文';
    final spans = findDialogueSpans(text, cfg);
    expect(spans.length, 1);
    expect(text.substring(spans.first.start, spans.first.end), '「こんにちは」');
    expect(spans.first.color, '#1a5fb4');
  });

  test('same-char quotes toggle open/close', () {
    final text = 'He said "hello" and left.';
    expect(matched(text, cfg), ['"hello"']);
  });

  test('mixed Japanese + English dialogue in one line', () {
    final text = '「はい」said A, then "no" said B.';
    expect(matched(text, cfg), ['「はい」', '"no"']);
    final spans = findDialogueSpans(text, cfg);
    expect(spans[0].color, '#1a5fb4');
    expect(spans[1].color, '#c01c28');
  });

  test('distinct-char pairs may nest; outer span wins (non-overlapping)', () {
    final text = '«outer 「inner」 outer»';
    final spans = findDialogueSpans(text, cfg);
    // Outer «...» fully contains the inner span, so overlap removal keeps only the outer.
    expect(matched(text, cfg), ['«outer 「inner」 outer»']);
    expect(spans.first.color, '#2ec27e');
  });

  test('unmatched trailing open marker is left unstyled', () {
    final text = 'start 「no close here';
    expect(findDialogueSpans(text, cfg), isEmpty);
  });

  test('disabled and empty pairs are ignored', () {
    const c = DialogueConfig(pairs: [
      QuotePair(open: '「', close: '」', color: '#000000', enabled: false),
      QuotePair(open: '', close: '', color: '#000000'),
    ]);
    expect(findDialogueSpans('「x」', c), isEmpty);
  });

  test('empty text yields no spans', () {
    expect(findDialogueSpans('', cfg), isEmpty);
  });
}
