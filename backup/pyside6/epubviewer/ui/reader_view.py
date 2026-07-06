from __future__ import annotations

from PySide6.QtCore import QPoint, Qt, Signal
from PySide6.QtGui import QMouseEvent, QWheelEvent
from PySide6.QtWidgets import QFrame, QTextBrowser

SWIPE_MIN_DISTANCE_PX = 60
TAP_MAX_MOVEMENT_PX = 12


def classify_tap_or_swipe(dx: int, dy: int, release_x: int, viewport_width: int) -> int | None:
    """Classifies a completed press-release gesture into a page-turn direction.

    A clear horizontal drag is a swipe (left = forward, right = backward, e-reader
    convention). Otherwise, if the finger/cursor barely moved, treat it as a tap and use
    the left/right thirds of the viewport as page-turn zones (the middle third is a no-op,
    matching common e-reader apps). Anything else (an ambiguous partial drag) is ignored.
    """
    if abs(dx) >= SWIPE_MIN_DISTANCE_PX and abs(dx) > abs(dy):
        return 1 if dx < 0 else -1
    if abs(dx) <= TAP_MAX_MOVEMENT_PX and abs(dy) <= TAP_MAX_MOVEMENT_PX and viewport_width > 0:
        if release_x < viewport_width / 3:
            return -1
        if release_x > viewport_width * 2 / 3:
            return 1
    return None


class PagedTextBrowser(QTextBrowser):
    """Read-only text browser that shows exactly one paginated "page" at a time.

    The scrollbar is hidden (page turning is driven programmatically by MainWindow +
    Paginator), but QTextEdit's internal vertical scrollbar still exists and controls
    which vertical slice of the flowed document is visible, so scroll_to_offset still works.
    """

    scrolled = Signal(int)  # +1 = forward/next, -1 = backward/previous

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setOpenExternalLinks(False)
        self.setReadOnly(True)
        # No text selection/cursor: this is a page viewer, not an editable/selectable
        # text field, and selection dragging would otherwise fight with swipe gestures.
        self.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setFrameShape(QFrame.Shape.NoFrame)
        self._press_pos: QPoint | None = None

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

    def mousePressEvent(self, event: QMouseEvent) -> None:
        # On touch platforms (Android), a tap/swipe is delivered as a synthesized left-
        # button press+release, so tracking mouse events covers both mouse and touch input.
        if event.button() == Qt.MouseButton.LeftButton:
            self._press_pos = event.position().toPoint()
            event.accept()
            return
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton and self._press_pos is not None:
            release_pos = event.position().toPoint()
            delta = release_pos - self._press_pos
            self._press_pos = None
            direction = classify_tap_or_swipe(delta.x(), delta.y(), release_pos.x(), self.viewport().width())
            if direction is not None:
                self.scrolled.emit(direction)
            event.accept()
            return
        super().mouseReleaseEvent(event)
