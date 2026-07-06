from __future__ import annotations

import base64
from pathlib import Path

from PySide6.QtCore import QByteArray, QSizeF, Qt, QTimer
from PySide6.QtGui import QAction, QCloseEvent, QFont, QKeySequence
from PySide6.QtWidgets import QApplication, QFileDialog, QMainWindow, QMessageBox

from ..content_processor import process_chapter_html
from ..epub_model import EpubBook
from ..paginator import Paginator, overall_percentage
from ..settings import AppSettings, RecentBook
from .reader_view import PagedTextBrowser
from .settings_dialog import SettingsDialog
from .status_bar import ReaderStatusBar
from .toc_dialog import TocDialog

RESIZE_DEBOUNCE_MS = 150
CHAPTER_SCROLL_CONFIRM_MS = 2000


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("EPUB Viewer")
        self.resize(900, 700)

        self.settings = AppSettings.load()
        self._restore_window_geometry()

        self.book: EpubBook | None = None
        self.chapter_index: int = 0
        self.page_index: int = 0
        self.page_count: int = 1
        self._char_offset: int = 0

        self.reader_view = PagedTextBrowser()
        self.reader_view.scrolled.connect(self._on_wheel_scrolled)
        self.setCentralWidget(self.reader_view)
        self.paginator = Paginator(self.reader_view.document())

        self.status_bar = ReaderStatusBar()
        self.setStatusBar(self.status_bar)

        self._build_menu()
        self._build_shortcuts()
        self._apply_style()
        self._apply_ui_font()

        self._resize_timer = QTimer(self)
        self._resize_timer.setSingleShot(True)
        self._resize_timer.timeout.connect(self._on_resize_settled)

        # At a chapter boundary, a scroll only arms a pending chapter change; it only
        # fires if a second scroll (in the same direction) arrives before the timer
        # elapses, so a single overscroll doesn't accidentally skip chapters.
        self._pending_chapter_direction: int | None = None
        self._chapter_scroll_timer = QTimer(self)
        self._chapter_scroll_timer.setSingleShot(True)
        self._chapter_scroll_timer.timeout.connect(self._on_chapter_scroll_timeout)

    def restore_last_session(self) -> None:
        """Reopen the most recently read book, resuming where it left off. Call this
        after the window is shown so the viewport has real dimensions for pagination
        (it is 0-sized before first show)."""
        if self.settings.recent_books:
            entry = self.settings.recent_books[0]
            self._try_open_path(entry.path, chapter_index=entry.chapter_index, char_offset=entry.char_offset)

    # ---- menu / shortcuts ----

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")
        open_action = QAction("&Open...", self)
        open_action.setShortcut(QKeySequence.StandardKey.Open)
        open_action.triggered.connect(self.open_file_dialog)
        file_menu.addAction(open_action)

        self.recent_menu = file_menu.addMenu("Recent Books")
        self._refresh_recent_menu()

        nav_menu = self.menuBar().addMenu("&Navigate")
        toc_action = QAction("&Change Chapter...", self)
        toc_action.triggered.connect(self.open_change_chapter_dialog)
        nav_menu.addAction(toc_action)

        view_menu = self.menuBar().addMenu("&View")
        settings_action = QAction("&Viewer Settings...", self)
        settings_action.triggered.connect(self.open_settings_dialog)
        view_menu.addAction(settings_action)

    def _build_shortcuts(self) -> None:
        next_action = QAction(self)
        next_action.setShortcuts([QKeySequence(Qt.Key.Key_PageDown), QKeySequence(Qt.Key.Key_Right)])
        next_action.triggered.connect(self.next_page)
        self.addAction(next_action)

        prev_action = QAction(self)
        prev_action.setShortcuts([QKeySequence(Qt.Key.Key_PageUp), QKeySequence(Qt.Key.Key_Left)])
        prev_action.triggered.connect(self.prev_page)
        self.addAction(prev_action)

    # ---- file open ----

    def open_file_dialog(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Open EPUB", "", "EPUB files (*.epub)")
        if path:
            self._try_open_path(path)

    def _try_open_path(self, path: str, chapter_index: int = 0, char_offset: int = 0) -> None:
        book = EpubBook(path)
        try:
            book.load()
        except Exception as exc:  # malformed EPUB, unsupported structure, etc.
            QMessageBox.critical(self, "Failed to Open EPUB", f"Could not open '{path}':\n{exc}")
            return
        self.book = book
        self.setWindowTitle(f"EPUB Viewer - {book.title}")

        chapter_index = min(max(0, chapter_index), len(book.chapters) - 1)
        self.settings.record_book_opened(path, book.title, chapter_index, char_offset)
        self.settings.save()
        self._refresh_recent_menu()

        self.load_chapter(chapter_index, char_offset=char_offset)

    def _open_recent(self, entry: RecentBook) -> None:
        self._try_open_path(entry.path, chapter_index=entry.chapter_index, char_offset=entry.char_offset)

    def _refresh_recent_menu(self) -> None:
        self.recent_menu.clear()
        if not self.settings.recent_books:
            empty_action = QAction("(No recent books)", self)
            empty_action.setEnabled(False)
            self.recent_menu.addAction(empty_action)
            return
        for entry in self.settings.recent_books:
            label = entry.title or Path(entry.path).name
            action = QAction(label, self)
            action.triggered.connect(lambda checked=False, e=entry: self._open_recent(e))
            self.recent_menu.addAction(action)

    # ---- chapter / page navigation ----

    def load_chapter(self, index: int, char_offset: int = 0) -> None:
        if self.book is None:
            return
        self._cancel_pending_chapter_scroll()
        chapter = self.book.get_chapter(index)
        html = process_chapter_html(chapter.raw_html, self.settings.dialogue_config, self.book, chapter.href)
        self.chapter_index = index

        self.reader_view.document().setDefaultStyleSheet(self._stylesheet())
        self.reader_view.setHtml(html)

        viewport_size = QSizeF(self.reader_view.viewport().size())
        self.page_count = self.paginator.page_count(viewport_size)
        target_page = self.paginator.page_for_char_offset(char_offset, viewport_size) if char_offset else 0
        self.go_to_page(target_page)

    def open_change_chapter_dialog(self) -> None:
        if self.book is None:
            QMessageBox.information(self, "No Book Loaded", "Open an EPUB file first.")
            return
        dialog = TocDialog(self.book.toc, self.chapter_index, self)
        if dialog.exec() == TocDialog.DialogCode.Accepted and dialog.selected_chapter_index is not None:
            self.load_chapter(dialog.selected_chapter_index)

    def open_settings_dialog(self) -> None:
        dialog = SettingsDialog(self.settings, self)
        dialog.settings_applied.connect(self._on_settings_applied)
        dialog.exec()

    def _on_settings_applied(self, new_settings: AppSettings) -> None:
        self.settings = new_settings
        self.settings.save()
        self._apply_style()
        self._apply_ui_font()
        if self.book is not None:
            self.load_chapter(self.chapter_index, char_offset=self._char_offset)

    def go_to_page(self, page_index: int) -> None:
        viewport_size = QSizeF(self.reader_view.viewport().size())
        page_index = max(0, min(page_index, self.page_count - 1))
        self.page_index = page_index
        offset = self.paginator.scroll_offset_for_page(page_index, viewport_size)
        self.reader_view.scroll_to_offset(offset)
        self._char_offset = self.paginator.char_offset_for_page(page_index, viewport_size)
        self._update_status_bar()
        self._record_progress()

    def _record_progress(self) -> None:
        # Kept in-memory only; flushed to disk on chapter change (_try_open_path/
        # load_chapter's settings.save() calls) and on app close (closeEvent), so we're
        # not writing settings.json on every single page turn.
        if self.book is not None:
            self.settings.update_reading_progress(self.book.path, self.chapter_index, self._char_offset)

    def next_page(self) -> None:
        if self.book is None:
            return
        if self.page_index + 1 < self.page_count:
            self.go_to_page(self.page_index + 1)
        elif self.chapter_index + 1 < len(self.book.chapters):
            self.load_chapter(self.chapter_index + 1)

    def prev_page(self) -> None:
        if self.book is None:
            return
        if self.page_index > 0:
            self.go_to_page(self.page_index - 1)
        elif self.chapter_index > 0:
            self.load_chapter(self.chapter_index - 1)
            self.go_to_page(self.page_count - 1)

    # ---- wheel-scroll navigation ----
    #
    # Within a chapter, each wheel notch turns one page immediately, same as the
    # keyboard shortcuts. At a chapter boundary, though, a scroll only *arms* a
    # pending chapter change; it's only committed if a second scroll in the same
    # direction arrives within CHAPTER_SCROLL_CONFIRM_MS, so one overscroll at the
    # end of a chapter doesn't accidentally skip into the next/previous one.

    def _on_wheel_scrolled(self, direction: int) -> None:
        if self.book is None:
            return
        if direction > 0:
            self._scroll_forward()
        else:
            self._scroll_backward()

    def _scroll_forward(self) -> None:
        if self.page_index + 1 < self.page_count:
            self._cancel_pending_chapter_scroll()
            self.go_to_page(self.page_index + 1)
            return
        if self._pending_chapter_direction == 1:
            self._cancel_pending_chapter_scroll()
            if self.chapter_index + 1 < len(self.book.chapters):
                self.load_chapter(self.chapter_index + 1)
            return
        self._pending_chapter_direction = 1
        self._chapter_scroll_timer.start(CHAPTER_SCROLL_CONFIRM_MS)

    def _scroll_backward(self) -> None:
        if self.page_index > 0:
            self._cancel_pending_chapter_scroll()
            self.go_to_page(self.page_index - 1)
            return
        if self._pending_chapter_direction == -1:
            self._cancel_pending_chapter_scroll()
            if self.chapter_index > 0:
                self.load_chapter(self.chapter_index - 1)
                self.go_to_page(self.page_count - 1)
            return
        self._pending_chapter_direction = -1
        self._chapter_scroll_timer.start(CHAPTER_SCROLL_CONFIRM_MS)

    def _on_chapter_scroll_timeout(self) -> None:
        self._pending_chapter_direction = None

    def _cancel_pending_chapter_scroll(self) -> None:
        self._chapter_scroll_timer.stop()
        self._pending_chapter_direction = None

    # ---- style / status ----

    def _stylesheet(self) -> str:
        # The universal selector forces our font/size/color onto every element (headings,
        # paragraphs, etc.), overriding whatever the EPUB's own markup would otherwise imply.
        # Dialogue-detection spans still win where they apply since their color comes from an
        # inline style="" attribute, which has higher CSS specificity than this rule.
        return (
            f"* {{ font-family: '{self.settings.font_family}'; font-size: {self.settings.font_size}pt; "
            f"color: {self.settings.text_color}; }}"
        )

    def _apply_style(self) -> None:
        self.reader_view.setStyleSheet(
            f"QTextBrowser {{ background-color: {self.settings.background_color}; "
            f"color: {self.settings.text_color}; border: none; }}"
        )
        self.reader_view.document().setDefaultStyleSheet(self._stylesheet())
        # Viewport margins (not document margin) so the padding is excluded from
        # viewport().size() automatically -- Paginator already derives page size from
        # that, so padding changes are picked up by pagination with no extra plumbing.
        padding = self.settings.content_padding
        self.reader_view.setViewportMargins(padding, padding, padding, padding)

    def _apply_ui_font(self) -> None:
        """Applies the UI font size (menus, dialogs, status bar) app-wide, distinct from the
        content viewer's font (which only affects the reader_view's text via _stylesheet())."""
        app = QApplication.instance()
        if app is None:
            return
        font = app.font()
        font.setPointSize(self.settings.ui_font_size)
        app.setFont(font)

    def _update_status_bar(self) -> None:
        if self.book is None:
            self.status_bar.clear_status()
            return
        chapter = self.book.get_chapter(self.chapter_index)
        percentage = overall_percentage(self.book, self.chapter_index, self._char_offset)
        self.status_bar.update_status(chapter.title, self.page_index, self.page_count, percentage)

    # ---- resize handling ----

    def resizeEvent(self, event) -> None:
        super().resizeEvent(event)
        self._resize_timer.start(RESIZE_DEBOUNCE_MS)

    def _on_resize_settled(self) -> None:
        if self.book is None:
            return
        anchor = self._char_offset
        viewport_size = QSizeF(self.reader_view.viewport().size())
        self.page_count = self.paginator.page_count(viewport_size)
        target_page = self.paginator.page_for_char_offset(anchor, viewport_size)
        self.go_to_page(target_page)

    # ---- window geometry persistence ----

    def _restore_window_geometry(self) -> None:
        if not self.settings.window_geometry:
            return
        try:
            self.restoreGeometry(QByteArray(base64.b64decode(self.settings.window_geometry)))
        except (ValueError, TypeError):
            pass  # corrupt/incompatible saved geometry -- fall back to the default size

    def closeEvent(self, event: QCloseEvent) -> None:
        self._record_progress()
        self.settings.window_geometry = base64.b64encode(bytes(self.saveGeometry())).decode("ascii")
        self.settings.save()
        super().closeEvent(event)
