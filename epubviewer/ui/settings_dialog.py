from __future__ import annotations

from dataclasses import replace

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QFont
from PySide6.QtWidgets import (
    QCheckBox,
    QColorDialog,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFontComboBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from ..dialogue_rules import DialogueConfig, QuotePair
from ..settings import THEMES, AppSettings

COLUMN_OPEN, COLUMN_CLOSE, COLUMN_COLOR, COLUMN_ENABLED = range(4)
DEFAULT_NEW_COLOR = "#1a5fb4"


class SettingsDialog(QDialog):
    """"Viewer Settings" dialog: font, theme/colors, and the configurable dialogue quote-pair table."""

    settings_applied = Signal(object)  # emits an AppSettings

    def __init__(self, settings: AppSettings, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Viewer Settings")
        self.resize(480, 440)

        self._working = replace(
            settings,
            dialogue_config=DialogueConfig(
                pairs=[QuotePair(p.open, p.close, p.color, p.enabled) for p in settings.dialogue_config.pairs]
            ),
        )

        layout = QVBoxLayout(self)

        font_row = QHBoxLayout()
        font_row.addWidget(QLabel("Content Font:"))
        self.font_combo = QFontComboBox()
        self.font_combo.setCurrentFont(QFont(self._working.font_family))
        font_row.addWidget(self.font_combo, 1)
        font_row.addWidget(QLabel("Size:"))
        self.size_spin = QSpinBox()
        self.size_spin.setRange(8, 48)
        self.size_spin.setValue(self._working.font_size)
        font_row.addWidget(self.size_spin)
        layout.addLayout(font_row)

        ui_font_row = QHBoxLayout()
        ui_font_row.addWidget(QLabel("UI Font Size:"))
        self.ui_size_spin = QSpinBox()
        self.ui_size_spin.setRange(7, 24)
        self.ui_size_spin.setValue(self._working.ui_font_size)
        ui_font_row.addWidget(self.ui_size_spin)

        ui_font_row.addWidget(QLabel("Content Padding (px):"))
        self.padding_spin = QSpinBox()
        self.padding_spin.setRange(0, 200)
        self.padding_spin.setValue(self._working.content_padding)
        ui_font_row.addWidget(self.padding_spin)

        ui_font_row.addStretch(1)
        layout.addLayout(ui_font_row)

        theme_row = QHBoxLayout()
        theme_row.addWidget(QLabel("Theme:"))
        self.theme_combo = QComboBox()
        self.theme_combo.addItems([*THEMES.keys(), "Custom"])
        self.theme_combo.setCurrentText(self._working.theme_name if self._working.theme_name in THEMES else "Custom")
        self.theme_combo.currentTextChanged.connect(self._on_theme_changed)
        theme_row.addWidget(self.theme_combo)

        self.text_color_button = QPushButton("Text Color")
        self.text_color_button.clicked.connect(self._pick_text_color)
        theme_row.addWidget(self.text_color_button)

        self.bg_color_button = QPushButton("Background Color")
        self.bg_color_button.clicked.connect(self._pick_bg_color)
        theme_row.addWidget(self.bg_color_button)
        layout.addLayout(theme_row)
        self._update_color_buttons()

        layout.addWidget(QLabel("Dialogue quote markers:"))
        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["Open", "Close", "Color", "Enabled"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        layout.addWidget(self.table)
        for pair in self._working.dialogue_config.pairs:
            self._add_row(pair)

        table_buttons = QHBoxLayout()
        add_button = QPushButton("Add")
        add_button.clicked.connect(lambda: self._add_row(QuotePair("", "", DEFAULT_NEW_COLOR, True)))
        remove_button = QPushButton("Remove Selected")
        remove_button.clicked.connect(self._remove_selected_rows)
        table_buttons.addWidget(add_button)
        table_buttons.addWidget(remove_button)
        table_buttons.addStretch(1)
        layout.addLayout(table_buttons)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel
            | QDialogButtonBox.StandardButton.Apply
        )
        buttons.accepted.connect(self._on_ok)
        buttons.rejected.connect(self.reject)
        buttons.button(QDialogButtonBox.StandardButton.Apply).clicked.connect(self._on_apply)
        layout.addWidget(buttons)

    def _add_row(self, pair: QuotePair) -> None:
        row = self.table.rowCount()
        self.table.insertRow(row)
        self.table.setItem(row, COLUMN_OPEN, QTableWidgetItem(pair.open))
        self.table.setItem(row, COLUMN_CLOSE, QTableWidgetItem(pair.close))

        color_button = QPushButton()
        self._set_button_color(color_button, pair.color)
        color_button.clicked.connect(lambda checked=False, b=color_button: self._pick_row_color(b))
        self.table.setCellWidget(row, COLUMN_COLOR, color_button)

        checkbox = QCheckBox()
        checkbox.setChecked(pair.enabled)
        container = QWidget()
        box = QHBoxLayout(container)
        box.addWidget(checkbox)
        box.setAlignment(Qt.AlignmentFlag.AlignCenter)
        box.setContentsMargins(0, 0, 0, 0)
        self.table.setCellWidget(row, COLUMN_ENABLED, container)

    def _remove_selected_rows(self) -> None:
        rows = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in rows:
            self.table.removeRow(row)

    @staticmethod
    def _set_button_color(button: QPushButton, color_hex: str) -> None:
        button.setProperty("color_hex", color_hex)
        button.setStyleSheet(f"background-color: {color_hex};")
        button.setText(color_hex)

    def _pick_row_color(self, button: QPushButton) -> None:
        current = QColor(button.property("color_hex") or DEFAULT_NEW_COLOR)
        color = QColorDialog.getColor(current, self, "Choose Dialogue Color")
        if color.isValid():
            self._set_button_color(button, color.name())

    def _pick_text_color(self) -> None:
        color = QColorDialog.getColor(QColor(self._working.text_color), self, "Choose Text Color")
        if color.isValid():
            self._working.text_color = color.name()
            self._working.theme_name = "Custom"
            self.theme_combo.setCurrentText("Custom")
            self._update_color_buttons()

    def _pick_bg_color(self) -> None:
        color = QColorDialog.getColor(QColor(self._working.background_color), self, "Choose Background Color")
        if color.isValid():
            self._working.background_color = color.name()
            self._working.theme_name = "Custom"
            self.theme_combo.setCurrentText("Custom")
            self._update_color_buttons()

    def _on_theme_changed(self, theme_name: str) -> None:
        if theme_name in THEMES:
            self._working.apply_theme(theme_name)
            self._update_color_buttons()

    def _update_color_buttons(self) -> None:
        self.text_color_button.setStyleSheet(
            f"background-color: {self._working.text_color}; color: {self._contrast(self._working.text_color)};"
        )
        self.bg_color_button.setStyleSheet(
            f"background-color: {self._working.background_color}; "
            f"color: {self._contrast(self._working.background_color)};"
        )

    @staticmethod
    def _contrast(hex_color: str) -> str:
        color = QColor(hex_color)
        luminance = 0.299 * color.red() + 0.587 * color.green() + 0.114 * color.blue()
        return "#000000" if luminance > 140 else "#ffffff"

    def _collect_settings(self) -> AppSettings:
        self._working.font_family = self.font_combo.currentFont().family()
        self._working.font_size = self.size_spin.value()
        self._working.ui_font_size = self.ui_size_spin.value()
        self._working.content_padding = self.padding_spin.value()

        pairs: list[QuotePair] = []
        for row in range(self.table.rowCount()):
            open_item = self.table.item(row, COLUMN_OPEN)
            close_item = self.table.item(row, COLUMN_CLOSE)
            open_marker = open_item.text() if open_item else ""
            close_marker = close_item.text() if close_item else ""
            if not open_marker or not close_marker:
                continue
            color_button = self.table.cellWidget(row, COLUMN_COLOR)
            color_hex = color_button.property("color_hex") if color_button else DEFAULT_NEW_COLOR
            enabled_container = self.table.cellWidget(row, COLUMN_ENABLED)
            checkbox = enabled_container.findChild(QCheckBox) if enabled_container else None
            enabled = checkbox.isChecked() if checkbox else True
            pairs.append(QuotePair(open_marker, close_marker, color_hex, enabled))
        self._working.dialogue_config = DialogueConfig(pairs=pairs)
        return self._working

    def _on_apply(self) -> None:
        self.settings_applied.emit(self._collect_settings())

    def _on_ok(self) -> None:
        self._on_apply()
        self.accept()
