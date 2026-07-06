from __future__ import annotations

import posixpath
import re
import warnings
from dataclasses import dataclass, field
from pathlib import Path

from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning
from ebooklib import epub

# EPUB chapter content is XHTML (carries an XML declaration) but we intentionally parse it
# with BeautifulSoup's HTML parser for rendering purposes, so this warning is expected noise.
warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)


def _clean_title(text: str | None) -> str:
    """Collapse whitespace (including embedded newlines from indented NCX/NAV markup) to
    single spaces, so titles render on one line in the window title, status bar, and TOC."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


@dataclass
class Chapter:
    index: int
    id: str
    title: str
    href: str
    raw_html: str
    plain_text_len: int


@dataclass
class TocEntry:
    title: str
    href: str
    chapter_index: int
    children: list["TocEntry"] = field(default_factory=list)


def _strip_fragment(href: str) -> str:
    return href.split("#", 1)[0]


def _plain_text_len(html: str) -> int:
    return len(BeautifulSoup(html, "lxml").get_text())


class EpubBook:
    """Loads an .epub file into an ordered list of chapters plus a navigable TOC tree."""

    def __init__(self, path: str):
        self.path = path
        self.title: str = ""
        self.chapters: list[Chapter] = []
        self.toc: list[TocEntry] = []
        self.total_length: int = 0
        self._book: epub.EpubBook | None = None

    def load(self) -> None:
        book = epub.read_epub(self.path, options={"ignore_ncx": False})
        self._book = book

        title_meta = book.get_metadata("DC", "title")
        self.title = _clean_title(title_meta[0][0]) if title_meta else Path(self.path).stem

        href_to_index: dict[str, int] = {}
        chapters: list[Chapter] = []
        for idref, _linear in book.spine:
            item = book.get_item_with_id(idref)
            if item is None:
                continue
            raw_html = item.get_content().decode("utf-8", errors="replace")
            href = _strip_fragment(item.get_name())
            chapter = Chapter(
                index=len(chapters),
                id=idref,
                title=_clean_title(getattr(item, "title", "")),
                href=href,
                raw_html=raw_html,
                plain_text_len=_plain_text_len(raw_html),
            )
            href_to_index[href] = chapter.index
            chapters.append(chapter)

        if not chapters:
            raise ValueError("EPUB has no readable chapters in its spine.")

        self.chapters = chapters
        self.total_length = sum(c.plain_text_len for c in chapters) or 1

        self.toc = self._build_toc(book.toc, href_to_index)
        self._assign_chapter_titles_from_toc()

    def _build_toc(self, nodes, href_to_index: dict[str, int]) -> list[TocEntry]:
        entries: list[TocEntry] = []
        for node in nodes:
            if isinstance(node, tuple):
                section, children = node
                href = _strip_fragment(getattr(section, "href", "") or "")
                entries.append(
                    TocEntry(
                        title=_clean_title(section.title),
                        href=href,
                        chapter_index=href_to_index.get(href, -1),
                        children=self._build_toc(children, href_to_index),
                    )
                )
            else:
                href = _strip_fragment(node.href or "")
                entries.append(
                    TocEntry(title=_clean_title(node.title), href=href, chapter_index=href_to_index.get(href, -1))
                )
        return entries

    def _assign_chapter_titles_from_toc(self) -> None:
        def walk(entries: list[TocEntry]) -> None:
            for entry in entries:
                if entry.chapter_index != -1 and not self.chapters[entry.chapter_index].title:
                    self.chapters[entry.chapter_index].title = entry.title
                walk(entry.children)

        walk(self.toc)
        for chapter in self.chapters:
            if not chapter.title:
                chapter.title = f"Chapter {chapter.index + 1}"

    def get_chapter(self, index: int) -> Chapter:
        return self.chapters[index]

    def resolve_image(self, src: str, base_href: str) -> bytes | None:
        """Resolve an <img src="..."> found in `base_href`'s chapter to raw bytes via the manifest."""
        if self._book is None or src.startswith("data:"):
            return None
        base_dir = posixpath.dirname(base_href)
        resolved = posixpath.normpath(posixpath.join(base_dir, src))
        item = self._book.get_item_with_href(resolved)
        if item is None:
            return None
        return item.get_content()
