# PySide6 EPUB Viewer (archived reference)

This is the original PySide6 (Python/Qt) implementation of the EPUB viewer. It runs on
both Windows desktop and Android from one codebase and is fully functional.

**Status: reference-only / unmaintained.** The project has moved to a Flutter rewrite (at
the repo root) because the PySide6 Android build was ~674 MB — the Qt payload dominates and
can't be trimmed cheaply. Flutter produces much smaller binaries (~20–40 MB) for both
Windows and Android.

Kept here so the original logic can be consulted while porting:

- `epubviewer/dialogue_rules.py` — configurable quote-pair dialogue detection
  (`find_dialogue_spans`)
- `epubviewer/epub_model.py` — EPUB parsing (spine, TOC, chapters)
- `epubviewer/content_processor.py` — HTML cleaning + dialogue-span injection
- `epubviewer/paginator.py` — viewport-slice pagination + char-weighted percentage
- `epubviewer/settings.py` — settings model, recent books, reading progress
- `epubviewer/ui/` — the Qt widgets (menu, reader view, TOC, settings, status bar)

## Running the old version (if ever needed)

```
cd backup/pyside6
pip install -r requirements.txt
python main.py
```
