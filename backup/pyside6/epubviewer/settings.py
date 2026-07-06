from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PySide6.QtCore import QStandardPaths

from .dialogue_rules import DialogueConfig


def _package_dir() -> Path:
    # When frozen by PyInstaller, this module's __file__ lives inside the bundled
    # archive and has no real on-disk directory, so shipped data files must instead
    # be located via sys._MEIPASS (set to wherever --add-data content was extracted to).
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS) / "epubviewer"
    return Path(__file__).resolve().parent


_DEFAULTS_PATH = _package_dir() / "resources" / "default_settings.json"

THEMES: dict[str, dict[str, str]] = {
    "Light": {"text_color": "#1a1a1a", "background_color": "#ffffff"},
    "Dark": {"text_color": "#e8e8e8", "background_color": "#1e1e1e"},
    "Sepia": {"text_color": "#3b2f2f", "background_color": "#f4ecd8"},
}

MAX_RECENT_BOOKS = 10


@dataclass
class RecentBook:
    path: str
    title: str = ""
    chapter_index: int = 0
    char_offset: int = 0

    def to_dict(self) -> dict:
        return {
            "path": self.path,
            "title": self.title,
            "chapter_index": self.chapter_index,
            "char_offset": self.char_offset,
        }

    @staticmethod
    def from_dict(data: dict) -> "RecentBook":
        return RecentBook(
            path=data["path"],
            title=data.get("title", ""),
            chapter_index=data.get("chapter_index", 0),
            char_offset=data.get("char_offset", 0),
        )


@dataclass
class AppSettings:
    font_family: str = "Yu Gothic"
    font_size: int = 14
    text_color: str = "#1a1a1a"
    background_color: str = "#ffffff"
    theme_name: str = "Light"
    ui_font_size: int = 9
    content_padding: int = 20
    dialogue_config: DialogueConfig = field(default_factory=lambda: DialogueConfig(pairs=[]))
    recent_books: list[RecentBook] = field(default_factory=list)
    window_geometry: str | None = None  # base64-encoded QMainWindow.saveGeometry()

    def apply_theme(self, theme_name: str) -> None:
        colors = THEMES.get(theme_name)
        if colors is None:
            return
        self.theme_name = theme_name
        self.text_color = colors["text_color"]
        self.background_color = colors["background_color"]

    def record_book_opened(self, path: str, title: str, chapter_index: int = 0, char_offset: int = 0) -> None:
        """Moves `path` to the front of the recent-books list, trimmed to MAX_RECENT_BOOKS."""
        self.recent_books = [b for b in self.recent_books if b.path != path]
        self.recent_books.insert(0, RecentBook(path=path, title=title, chapter_index=chapter_index, char_offset=char_offset))
        del self.recent_books[MAX_RECENT_BOOKS:]

    def update_reading_progress(self, path: str, chapter_index: int, char_offset: int) -> None:
        for book in self.recent_books:
            if book.path == path:
                book.chapter_index = chapter_index
                book.char_offset = char_offset
                return

    def to_dict(self) -> dict:
        return {
            "font_family": self.font_family,
            "font_size": self.font_size,
            "text_color": self.text_color,
            "background_color": self.background_color,
            "theme_name": self.theme_name,
            "ui_font_size": self.ui_font_size,
            "content_padding": self.content_padding,
            "dialogue_config": self.dialogue_config.to_dict(),
            "recent_books": [b.to_dict() for b in self.recent_books],
            "window_geometry": self.window_geometry,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "AppSettings":
        defaults = cls()
        dialogue_config = defaults.dialogue_config
        if "dialogue_config" in data:
            dialogue_config = DialogueConfig.from_dict(data["dialogue_config"])
        recent_books = [RecentBook.from_dict(b) for b in data.get("recent_books", [])]
        return cls(
            font_family=data.get("font_family", defaults.font_family),
            font_size=data.get("font_size", defaults.font_size),
            text_color=data.get("text_color", defaults.text_color),
            background_color=data.get("background_color", defaults.background_color),
            theme_name=data.get("theme_name", defaults.theme_name),
            ui_font_size=data.get("ui_font_size", defaults.ui_font_size),
            content_padding=data.get("content_padding", defaults.content_padding),
            dialogue_config=dialogue_config,
            recent_books=recent_books,
            window_geometry=data.get("window_geometry"),
        )

    @staticmethod
    def config_path() -> Path:
        base = QStandardPaths.writableLocation(QStandardPaths.AppConfigLocation)
        if not base:
            base = str(Path.home() / ".epubviewer")
        return Path(base) / "EpubViewer" / "settings.json"

    @classmethod
    def load(cls) -> "AppSettings":
        path = cls.config_path()
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                return cls.from_dict(data)
            except (json.JSONDecodeError, OSError):
                pass
        data = json.loads(_DEFAULTS_PATH.read_text(encoding="utf-8"))
        return cls.from_dict(data)

    def save(self) -> None:
        path = self.config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")
