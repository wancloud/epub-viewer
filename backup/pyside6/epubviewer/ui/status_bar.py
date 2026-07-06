from __future__ import annotations

from PySide6.QtWidgets import QLabel, QStatusBar


class ReaderStatusBar(QStatusBar):
    """Bottom bar: chapter title, page-in-chapter progress, and overall book percentage."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.chapter_label = QLabel("No book loaded")
        self.page_label = QLabel("")
        self.percent_label = QLabel("")
        self.addWidget(self.chapter_label, 1)
        self.addPermanentWidget(self.page_label)
        self.addPermanentWidget(self.percent_label)

    def update_status(self, chapter_title: str, page_index: int, page_count: int, percentage: float) -> None:
        self.chapter_label.setText(chapter_title)
        self.page_label.setText(f"Page {page_index + 1} / {page_count}")
        self.percent_label.setText(f"{percentage:.1f}%")

    def clear_status(self) -> None:
        self.chapter_label.setText("No book loaded")
        self.page_label.setText("")
        self.percent_label.setText("")
