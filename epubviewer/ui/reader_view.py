from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QWheelEvent
from PySide6.QtWidgets import QFrame, QTextBrowser


class PagedTextBrowser(QTextBrowser):
    """Read-only text browser that shows exactly one paginated "page" at a time.

    The scrollbar is hidden (page turning is driven programmatically by MainWindow +
    Paginator), but QTextEdit's internal vertical scrollbar still exists and controls
    which vertical slice of the flowed document is visible, so scroll_to_offset still works.
    """

    scrolled = Signal(int)  # +1 = forward/down, -1 = backward/up

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setOpenExternalLinks(False)
        self.setReadOnly(True)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setFrameShape(QFrame.Shape.NoFrame)

    def scroll_to_offset(self, offset: int) -> None:
        self.verticalScrollBar().setValue(offset)

    def wheelEvent(self, event: QWheelEvent) -> None:
        # Page turning is driven entirely by MainWindow/Paginator, so the wheel event is
        # consumed here rather than passed to QTextEdit's default free-scroll, which would
        # otherwise drift the view away from our page-aligned scroll offsets.
        delta = event.angleDelta().y()
        if delta < 0:
            self.scrolled.emit(1)
        elif delta > 0:
            self.scrolled.emit(-1)
        event.accept()
