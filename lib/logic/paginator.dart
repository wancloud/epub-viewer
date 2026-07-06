import 'dart:math' as math;

import '../models/epub_book.dart';

/// Pagination math + overall-percentage, ported from the PySide6 app's
/// `epubviewer/paginator.py` (see backup/pyside6/).
///
/// Flutter can't measure rendered text height purely, so the widget supplies the measured
/// [contentHeight] (from a ScrollController's maxScrollExtent + viewport) and this class
/// does the page<->offset arithmetic — the same "content is one tall column, a page is a
/// viewport-height slice, turn pages by scrolling" approach as reader_view.py.
///
/// Character-offset anchoring is fraction-based (offset within content maps proportionally
/// to a character position in the chapter's plain text). This keeps the reading position
/// stable across font-size / window-size changes, like the Qt version's char-offset
/// re-anchoring, without needing exact glyph hit-testing.
class Paginator {
  final double contentHeight; // total laid-out height of the chapter
  final double viewportHeight; // visible height (one page)

  const Paginator(this.contentHeight, this.viewportHeight);

  int get pageCount {
    if (viewportHeight <= 0) return 1;
    return math.max(1, (contentHeight / viewportHeight).ceil());
  }

  /// Ideal scroll offset for the top of [pageIndex]. Callers should clamp to the
  /// scroll view's maxScrollExtent.
  double scrollOffsetForPage(int pageIndex) => pageIndex * viewportHeight;

  /// Approximate character offset at the top of [pageIndex], for progress + re-anchoring.
  int charOffsetForPage(int pageIndex, int chapterPlainTextLen) {
    if (contentHeight <= 0) return 0;
    final fraction = (pageIndex * viewportHeight) / contentHeight;
    return (fraction.clamp(0.0, 1.0) * chapterPlainTextLen).round();
  }

  /// Which page currently contains [charOffset], after a re-layout (resize / font change).
  int pageForCharOffset(int charOffset, int chapterPlainTextLen) {
    if (chapterPlainTextLen <= 0 || viewportHeight <= 0) return 0;
    final fraction = charOffset / chapterPlainTextLen;
    final targetScroll = fraction.clamp(0.0, 1.0) * contentHeight;
    final page = (targetScroll / viewportHeight).floor();
    return math.max(0, math.min(page, pageCount - 1));
  }
}

/// Percentage through the whole book, weighted by plain-text character counts
/// (stable across font/window changes, unlike page-count weighting). Ported verbatim
/// from paginator.py's overall_percentage.
double overallPercentage(EpubBook book, int chapterIndex, int charOffsetInChapter) {
  var charsBefore = 0;
  for (var i = 0; i < chapterIndex && i < book.chapters.length; i++) {
    charsBefore += book.chapters[i].plainTextLen;
  }
  return (charsBefore + charOffsetInChapter) / book.totalLength * 100;
}
