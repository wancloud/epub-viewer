import 'dart:io';

import 'package:epub_viewer/logic/content_builder.dart';
import 'package:epub_viewer/models/epub_book.dart';
import 'package:epub_viewer/models/settings.dart';
import 'package:flutter_test/flutter_test.dart';

// End-to-end pipeline test on the real bundled demo.epub (Japanese 「」 + English ""
// dialogue): parse with epubx -> build renderable blocks -> confirm dialogue coloring is
// applied. Headless, so it runs without a desktop GUI (which needs Windows Developer Mode).
void main() {
  test('parses demo.epub and applies dialogue coloring', () async {
    final bytes = await File('assets/demo.epub').readAsBytes();
    final book = await EpubBook.loadFromBytes('assets/demo.epub', bytes);

    expect(book.title.isNotEmpty, true);
    expect(book.chapters, isNotEmpty);
    expect(book.totalLength, greaterThan(0));

    final settings = AppSettings(); // default quote pairs: 「」 and "" enabled
    // Find any chapter that produces at least one dialogue-colored run.
    var coloredRuns = 0;
    var totalBlocks = 0;
    for (final chapter in book.chapters) {
      final blocks =
          buildChapterBlocks(chapter.rawHtml, settings.dialogueConfig, book, chapter.href);
      totalBlocks += blocks.length;
      for (final b in blocks) {
        for (final r in b.runs) {
          if (r.color != null) coloredRuns++;
        }
      }
    }

    expect(totalBlocks, greaterThan(0), reason: 'chapters should render to blocks');
    expect(coloredRuns, greaterThan(0),
        reason: 'demo.epub contains 「」/"" dialogue that must be colored');
  });
}
