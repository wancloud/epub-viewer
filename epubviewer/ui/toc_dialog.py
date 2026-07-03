from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QDialog, QDialogButtonBox, QTreeWidget, QTreeWidgetItem, QVBoxLayout

from ..epub_model import TocEntry

CHAPTER_INDEX_ROLE = Qt.ItemDataRole.UserRole


class TocDialog(QDialog):
    """"Change Chapter" dialog: shows the book's table of contents as a tree."""

    def __init__(self, toc: list[TocEntry], current_chapter_index: int, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Change Chapter")
        self.resize(380, 480)
        self.selected_chapter_index: int | None = None

        layout = QVBoxLayout(self)
        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.setIndentation(16)
        self.tree.setStyleSheet("QTreeWidget::item { padding: 6px 4px; }")
        layout.addWidget(self.tree)

        self._populate(toc, self.tree.invisibleRootItem(), current_chapter_index)
        self.tree.expandAll()
        self.tree.itemDoubleClicked.connect(self._on_item_activated)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _populate(self, entries: list[TocEntry], parent_item: QTreeWidgetItem, current_chapter_index: int) -> None:
        for entry in entries:
            item = QTreeWidgetItem(parent_item, [entry.title])
            item.setData(0, CHAPTER_INDEX_ROLE, entry.chapter_index)
            if entry.chapter_index == current_chapter_index:
                item.setSelected(True)
            self._populate(entry.children, item, current_chapter_index)

    def _on_item_activated(self, item: QTreeWidgetItem, _column: int) -> None:
        self._select_item(item)
        self.accept()

    def _on_accept(self) -> None:
        items = self.tree.selectedItems()
        if items:
            self._select_item(items[0])
        self.accept()

    def _select_item(self, item: QTreeWidgetItem) -> None:
        chapter_index = item.data(0, CHAPTER_INDEX_ROLE)
        if isinstance(chapter_index, int) and chapter_index >= 0:
            self.selected_chapter_index = chapter_index
