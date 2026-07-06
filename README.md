# EPUB Viewer

A cross-platform EPUB reader for **Windows desktop and Android** from one Flutter codebase,
with configurable dialogue coloring (e.g. Japanese 「」 and English "" quotes rendered in a
distinct color).

## Why Flutter

Originally a PySide6 (Python/Qt) app — functional on both platforms, but the Android build
was ~674 MB (the Qt payload dominates). This Flutter rewrite produces much smaller binaries
(~20–40 MB) for both targets. The original PySide6 app is preserved for reference under
[`backup/pyside6/`](backup/pyside6/).

## Features

- Open `.epub` files; navigate by table of contents
- Configurable **dialogue detection**: quote-marker pairs (「」, "", «», …) each rendered in a
  chosen color
- Viewer settings: content font family/size, UI font size, content padding, Light/Dark/Sepia
  themes, custom text/background colors
- Paginated reading with a status bar (chapter title, page N/total, overall %)
- Recent books (last 10) with saved reading position; window size persisted (desktop)
- Touch tap-zones + swipe (mobile) and keyboard / mouse-wheel navigation (desktop), with a
  2-second confirm at chapter boundaries

## Architecture

Pure-Dart rendering (no WebView) so Windows + Android run identical code:
`epubx` parses the EPUB, and chapters render as Flutter `RichText` with dialogue-colored
runs. `lib/` maps 1:1 to the original Python modules (see `backup/pyside6/`).

## Develop

```
flutter pub get
flutter run -d windows      # or: flutter run -d chrome
flutter test
```

> Note: building the Windows desktop target with plugins requires Windows **Developer Mode**
> (Settings → For developers) for symlink support.

## Build

```
flutter build apk --release          # Android
flutter build windows --release      # Windows
```

CI (`.github/workflows/build.yml`) builds both on every push and uploads the APK and a
zipped Windows build as artifacts.
