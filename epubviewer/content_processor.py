from __future__ import annotations

import base64
from typing import TYPE_CHECKING

from bs4 import BeautifulSoup, Comment

from .dialogue_rules import DialogueConfig, find_dialogue_spans

if TYPE_CHECKING:
    from .epub_model import EpubBook

# Deliberately ignore book-embedded CSS/classes/ids: QTextDocument's HTML subset renders
# arbitrary book CSS inconsistently, so a single app-controlled stylesheet (from
# AppSettings) is applied uniformly instead. Only structural tags survive.
ALLOWED_TAGS = {
    "html", "head", "body", "p", "br", "hr", "b", "i", "em", "strong", "u", "s",
    "h1", "h2", "h3", "h4", "h5", "h6", "img", "blockquote", "div", "span",
    "ul", "ol", "li", "sub", "sup", "center", "table", "tr", "td", "th", "tbody", "thead",
}

STRIP_ENTIRELY = {"script", "style", "title", "meta", "link"}


def process_chapter_html(
    raw_html: str, dialogue_config: DialogueConfig, book: "EpubBook", chapter_href: str
) -> str:
    """Clean a chapter's raw (X)HTML and inject dialogue-color spans, ready for QTextBrowser.setHtml()."""
    soup = BeautifulSoup(raw_html, "lxml")

    for tag in soup.find_all(list(STRIP_ENTIRELY)):
        tag.decompose()

    _strip_disallowed_tags(soup)
    _resolve_images(soup, book, chapter_href)
    _inject_dialogue_spans(soup, dialogue_config)

    body = soup.body
    # Keep the <body> wrapper (not just its inner contents): the app's stylesheet
    # targets "body"/"*" selectors, which never match anything if there is no actual
    # <body> element in the HTML handed to QTextDocument.setHtml().
    return str(body) if body is not None else str(soup)


def _strip_disallowed_tags(soup: BeautifulSoup) -> None:
    for tag in soup.find_all(True):
        if tag.name not in ALLOWED_TAGS:
            tag.unwrap()
            continue
        if tag.name == "img":
            tag.attrs = {k: v for k, v in tag.attrs.items() if k in ("src", "alt")}
        else:
            tag.attrs = {}


def _resolve_images(soup: BeautifulSoup, book: "EpubBook", chapter_href: str) -> None:
    for img in soup.find_all("img"):
        src = img.get("src")
        if not src:
            img.decompose()
            continue
        data = book.resolve_image(src, chapter_href)
        if data is None:
            img.decompose()
            continue
        b64 = base64.b64encode(data).decode("ascii")
        img["src"] = f"data:{_guess_media_type(src)};base64,{b64}"
        # Cap to the content area's width (never upscale smaller images) instead of
        # rendering at native pixel size, which could overflow a narrow reader viewport.
        # Qt's rich-text layout re-resolves this on every relayout, so it also tracks
        # window resizes automatically without needing to reprocess the chapter HTML.
        img["style"] = "max-width:100%;"


def _guess_media_type(src: str) -> str:
    lower = src.lower()
    if lower.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith(".gif"):
        return "image/gif"
    if lower.endswith(".svg"):
        return "image/svg+xml"
    return "image/png"


def _inject_dialogue_spans(soup: BeautifulSoup, dialogue_config: DialogueConfig) -> None:
    if not dialogue_config.enabled_pairs():
        return
    for text_node in list(soup.find_all(string=True)):
        if isinstance(text_node, Comment) or text_node.parent is None:
            continue
        text = str(text_node)
        spans = find_dialogue_spans(text, dialogue_config)
        if not spans:
            continue

        cursor = 0
        replacement_nodes = []
        for start, end, color in spans:
            if start > cursor:
                replacement_nodes.append(soup.new_string(text[cursor:start]))
            span_tag = soup.new_tag("span", style=f"color:{color}")
            span_tag.string = text[start:end]
            replacement_nodes.append(span_tag)
            cursor = end
        if cursor < len(text):
            replacement_nodes.append(soup.new_string(text[cursor:]))

        text_node.replace_with(*replacement_nodes)
