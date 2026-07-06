import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/epub_book.dart';
import 'dialogue_rules.dart';

/// Turns a chapter's raw (X)HTML into a flat list of renderable blocks, with dialogue
/// coloring overlaid onto the text runs.
///
/// Port of the PySide6 app's `epubviewer/content_processor.py` (see backup/pyside6/).
/// Same philosophy: ignore book-embedded CSS/classes, keep only structural elements, and
/// let the app apply font/size/color uniformly. Here the output is a widget-friendly
/// model (blocks of inline runs) instead of cleaned HTML.

enum BlockKind { paragraph, heading, image }

/// A contiguous run of text sharing the same styling within a block.
class InlineRun {
  final String text;
  final String? color; // hex string from dialogue detection, or null for normal text
  final bool bold;
  final bool italic;
  const InlineRun(this.text, {this.color, this.bold = false, this.italic = false});
}

class ContentBlock {
  final BlockKind kind;
  final List<InlineRun> runs; // for paragraph/heading
  final int headingLevel; // 1..6 for heading, else 0
  final List<int>? imageBytes; // for image

  const ContentBlock.paragraph(this.runs)
      : kind = BlockKind.paragraph,
        headingLevel = 0,
        imageBytes = null;
  const ContentBlock.heading(this.runs, this.headingLevel)
      : kind = BlockKind.heading,
        imageBytes = null;
  const ContentBlock.image(this.imageBytes)
      : kind = BlockKind.image,
        runs = const [],
        headingLevel = 0;
}

const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
const _textBlockTags = {'p', 'li', 'blockquote', 'dd', 'dt', 'figcaption'};
const _skipTags = {'script', 'style', 'title', 'meta', 'link', 'head'};

List<ContentBlock> buildChapterBlocks(
    String rawHtml, DialogueConfig config, EpubBook book, String chapterHref) {
  final doc = html_parser.parse(rawHtml);
  final root = doc.body ?? doc.documentElement;
  final blocks = <ContentBlock>[];
  if (root != null) {
    _walk(root, config, book, chapterHref, blocks);
  }
  return blocks;
}

void _walk(dom.Node node, DialogueConfig config, EpubBook book, String chapterHref,
    List<ContentBlock> out) {
  for (final child in node.nodes) {
    if (child is dom.Element) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag)) continue;

      if (tag == 'img') {
        final block = _imageBlock(child, book, chapterHref);
        if (block != null) out.add(block);
        continue;
      }
      if (_headingTags.contains(tag)) {
        final runs = _inlineRuns(child, config);
        if (runs.isNotEmpty) out.add(ContentBlock.heading(runs, int.parse(tag[1])));
        continue;
      }
      if (_textBlockTags.contains(tag)) {
        final runs = _inlineRuns(child, config);
        if (runs.isNotEmpty) out.add(ContentBlock.paragraph(runs));
        // still recurse for nested images inside the block
        for (final img in child.querySelectorAll('img')) {
          final block = _imageBlock(img, book, chapterHref);
          if (block != null) out.add(block);
        }
        continue;
      }
      // Container (div, section, ul, ol, body, ...): recurse.
      _walk(child, config, book, chapterHref, out);
    } else if (child is dom.Text) {
      // Bare text directly under a container: wrap as a paragraph if non-trivial.
      final text = child.text;
      if (text.trim().isNotEmpty) {
        final runs = _colorize(text, [_StyledChar.plain], config, text);
        if (runs.isNotEmpty) out.add(ContentBlock.paragraph(runs));
      }
    }
  }
}

ContentBlock? _imageBlock(dom.Element img, EpubBook book, String chapterHref) {
  final src = img.attributes['src'];
  if (src == null || src.isEmpty) return null;
  final bytes = book.resolveImage(src, chapterHref);
  if (bytes == null) return null;
  return ContentBlock.image(bytes);
}

/// Build inline runs for a block: collect text with bold/italic flags, then overlay
/// dialogue colors by character offset and coalesce adjacent same-style characters.
List<InlineRun> _inlineRuns(dom.Element element, DialogueConfig config) {
  final buf = StringBuffer();
  final styles = <_StyledChar>[];
  _collectInline(element, false, false, buf, styles);
  final text = buf.toString();
  if (text.trim().isEmpty) return [];
  return _colorize(text, styles, config, text);
}

void _collectInline(dom.Node node, bool bold, bool italic, StringBuffer buf,
    List<_StyledChar> styles) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      for (final ch in child.text.split('')) {
        buf.write(ch);
        styles.add(_StyledChar(bold, italic));
      }
    } else if (child is dom.Element) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (_skipTags.contains(tag) || tag == 'img') continue;
      if (tag == 'br') {
        buf.write('\n');
        styles.add(_StyledChar(bold, italic));
        continue;
      }
      final nb = bold || tag == 'b' || tag == 'strong';
      final ni = italic || tag == 'i' || tag == 'em';
      _collectInline(child, nb, ni, buf, styles);
    }
  }
}

List<InlineRun> _colorize(
    String text, List<_StyledChar> styles, DialogueConfig config, String fullText) {
  // Per-character color from dialogue detection.
  final colors = List<String?>.filled(text.length, null);
  for (final span in findDialogueSpans(text, config)) {
    for (var i = span.start; i < span.end && i < text.length; i++) {
      colors[i] = span.color;
    }
  }
  // If styles wasn't tracked per-char (bare text path), treat as all-plain.
  _StyledChar styleAt(int i) => i < styles.length ? styles[i] : const _StyledChar(false, false);

  final runs = <InlineRun>[];
  final chars = text.split('');
  var start = 0;
  while (start < chars.length) {
    final s0 = styleAt(start);
    final c0 = colors[start];
    var end = start + 1;
    while (end < chars.length) {
      final s = styleAt(end);
      if (s.bold != s0.bold || s.italic != s0.italic || colors[end] != c0) break;
      end++;
    }
    runs.add(InlineRun(chars.sublist(start, end).join(),
        color: c0, bold: s0.bold, italic: s0.italic));
    start = end;
  }
  return runs;
}

class _StyledChar {
  final bool bold;
  final bool italic;
  const _StyledChar(this.bold, this.italic);
  static const plain = _StyledChar(false, false);
}
