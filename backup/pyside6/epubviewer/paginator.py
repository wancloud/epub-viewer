from __future__ import annotations

import math
from typing import TYPE_CHECKING

from PySide6.QtCore import QPointF, QSizeF, Qt
from PySide6.QtGui import QTextCursor, QTextDocument

if TYPE_CHECKING:
    from .epub_model import EpubBook


class Paginator:
    """Wraps a QTextDocument to compute page counts and page<->character-offset mappings.

    Qt's QTextDocument.setPageSize() lays the document out as a stack of fixed-height
    pages in document coordinates: page N occupies the vertical band
    [N * page_height, (N + 1) * page_height). We rely on that to turn "which page is
    currently shown" into a scroll offset (and back), instead of manually slicing HTML
    into page-sized chunks.
    """

    def __init__(self, document: QTextDocument):
        self.document = document

    def _layout(self, viewport_size: QSizeF) -> float:
        width = max(1.0, viewport_size.width())
        height = max(1.0, viewport_size.height())
        self.document.setTextWidth(width)
        self.document.setPageSize(QSizeF(width, height))
        return height

    def page_count(self, viewport_size: QSizeF) -> int:
        page_height = self._layout(viewport_size)
        content_height = self.document.size().height()
        return max(1, math.ceil(content_height / page_height))

    def scroll_offset_for_page(self, page_index: int, viewport_size: QSizeF) -> int:
        page_height = self._layout(viewport_size)
        return int(page_index * page_height)

    def char_offset_for_page(self, page_index: int, viewport_size: QSizeF) -> int:
        """Character offset at the top of `page_index`, used to re-anchor after resize."""
        page_height = self._layout(viewport_size)
        position = self.document.documentLayout().hitTest(
            QPointF(0, page_index * page_height), Qt.HitTestAccuracy.FuzzyHit
        )
        return max(0, position)

    def page_for_char_offset(self, char_offset: int, viewport_size: QSizeF) -> int:
        """Which page currently contains `char_offset`, after the layout is recomputed.

        Uses line-level (not just block-level) position: a single paragraph/block commonly
        spans many wrapped lines and can straddle a page boundary, so resolving only to the
        block's top would misplace the page for text past the first line of a long block.
        """
        page_height = self._layout(viewport_size)
        max_pos = max(0, self.document.characterCount() - 1)
        cursor = QTextCursor(self.document)
        cursor.setPosition(min(max(0, char_offset), max_pos))
        block = cursor.block()
        block_top = self.document.documentLayout().blockBoundingRect(block).top()
        line_y = 0.0
        layout = block.layout()
        if layout is not None:
            line = layout.lineForTextPosition(cursor.position() - block.position())
            if line.isValid():
                line_y = line.y()
        page_index = int((block_top + line_y) // page_height)
        page_count = self.page_count(viewport_size)
        return max(0, min(page_index, page_count - 1))


def overall_percentage(book: "EpubBook", chapter_index: int, char_offset_in_chapter: int) -> float:
    """Percentage through the whole book, weighted by plain-text character counts.

    Character-count weighting (rather than cumulative page counts) is used because page
    counts shift whenever font size or window size changes, which would make a page-based
    percentage jump around; character position is stable across those changes.
    """
    chars_before = sum(c.plain_text_len for c in book.chapters[:chapter_index])
    return (chars_before + char_offset_in_chapter) / book.total_length * 100
