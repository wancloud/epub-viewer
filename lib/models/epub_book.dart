import 'package:epubx/epubx.dart' as epubx;
import 'package:html/parser.dart' as html_parser;

/// Loads an .epub into an ordered list of chapters (spine order) plus a navigable TOC.
///
/// Port of the PySide6 app's `epubviewer/epub_model.py` (see backup/pyside6/), backed by
/// the pure-Dart `epubx` package so it runs identically on Windows + Android.

class Chapter {
  final int index;
  final String href; // manifest href, anchor stripped
  String title;
  final String rawHtml;
  final int plainTextLen;

  Chapter({
    required this.index,
    required this.href,
    required this.title,
    required this.rawHtml,
    required this.plainTextLen,
  });
}

class TocEntry {
  final String title;
  final String href;
  final int chapterIndex; // -1 if it doesn't map to a spine item
  final List<TocEntry> children;

  TocEntry({
    required this.title,
    required this.href,
    required this.chapterIndex,
    this.children = const [],
  });
}

String _stripFragment(String href) => href.split('#').first;

String _collapseWhitespace(String? text) {
  if (text == null) return '';
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Normalize a path relative to [baseDir] (posix-style, resolving `.` and `..`).
String _resolveRelative(String baseDir, String src) {
  final combined = baseDir.isEmpty ? src : '$baseDir/$src';
  final parts = <String>[];
  for (final seg in combined.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

class EpubBook {
  final String path;
  String title = '';
  List<Chapter> chapters = [];
  List<TocEntry> toc = [];
  int totalLength = 1;

  epubx.EpubBook? _book;
  // manifest href -> image bytes, and the chapter href each is resolvable from.
  Map<String, List<int>> _imagesByHref = {};

  EpubBook(this.path);

  static Future<EpubBook> loadFromBytes(String path, List<int> bytes) async {
    final model = EpubBook(path);
    await model._load(bytes);
    return model;
  }

  Future<void> _load(List<int> bytes) async {
    final book = await epubx.EpubReader.readBook(bytes);
    _book = book;

    title = _collapseWhitespace(book.Title);
    if (title.isEmpty) {
      title = path.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.epub$'), '');
    }

    final htmlByHref = book.Content?.Html ?? {};
    _imagesByHref = {
      for (final entry in (book.Content?.Images ?? {}).entries)
        if (entry.value.Content != null) entry.key: entry.value.Content!,
    };

    // Manifest id -> href, to resolve spine item refs.
    final idToHref = <String, String>{};
    for (final item in book.Schema?.Package?.Manifest?.Items ?? []) {
      if (item.Id != null && item.Href != null) idToHref[item.Id!] = item.Href!;
    }

    final hrefToIndex = <String, int>{};
    final chapters = <Chapter>[];
    for (final ref in book.Schema?.Package?.Spine?.Items ?? []) {
      final href = ref.IdRef != null ? idToHref[ref.IdRef!] : null;
      if (href == null) continue;
      final content = htmlByHref[href]?.Content;
      if (content == null) continue;
      final strippedHref = _stripFragment(href);
      final chapter = Chapter(
        index: chapters.length,
        href: strippedHref,
        title: '',
        rawHtml: content,
        plainTextLen: _plainTextLen(content),
      );
      hrefToIndex[strippedHref] = chapter.index;
      chapters.add(chapter);
    }

    if (chapters.isEmpty) {
      throw StateError('EPUB has no readable chapters in its spine.');
    }
    this.chapters = chapters;
    totalLength = chapters.fold<int>(0, (a, c) => a + c.plainTextLen);
    if (totalLength == 0) totalLength = 1;

    toc = _buildToc(book.Schema?.Navigation?.NavMap?.Points ?? [], hrefToIndex);
    _assignChapterTitlesFromToc();
  }

  int _plainTextLen(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    return (doc.body?.text ?? doc.documentElement?.text ?? '').length;
  }

  List<TocEntry> _buildToc(
      List<epubx.EpubNavigationPoint> points, Map<String, int> hrefToIndex) {
    final entries = <TocEntry>[];
    for (final p in points) {
      final rawSrc = p.Content?.Source ?? '';
      final href = _stripFragment(rawSrc);
      final label = _collapseWhitespace(
          p.NavigationLabels?.isNotEmpty == true ? p.NavigationLabels!.first.Text : '');
      entries.add(TocEntry(
        title: label,
        href: href,
        chapterIndex: hrefToIndex[href] ?? -1,
        children: _buildToc(p.ChildNavigationPoints ?? [], hrefToIndex),
      ));
    }
    return entries;
  }

  void _assignChapterTitlesFromToc() {
    void walk(List<TocEntry> entries) {
      for (final e in entries) {
        if (e.chapterIndex != -1 &&
            e.chapterIndex < chapters.length &&
            chapters[e.chapterIndex].title.isEmpty) {
          chapters[e.chapterIndex].title = e.title;
        }
        walk(e.children);
      }
    }

    walk(toc);
    for (final c in chapters) {
      if (c.title.isEmpty) c.title = 'Chapter ${c.index + 1}';
    }
  }

  /// Resolve an `<img src>` found in [baseHref]'s chapter to raw bytes, or null.
  List<int>? resolveImage(String src, String baseHref) {
    if (_book == null || src.startsWith('data:')) return null;
    final baseDir = baseHref.contains('/')
        ? baseHref.substring(0, baseHref.lastIndexOf('/'))
        : '';
    final resolved = _resolveRelative(baseDir, src);
    // Try exact resolved key, then a basename fallback (some books key differently).
    if (_imagesByHref.containsKey(resolved)) return _imagesByHref[resolved];
    final base = src.split('/').last;
    for (final entry in _imagesByHref.entries) {
      if (entry.key.split('/').last == base) return entry.value;
    }
    return null;
  }
}
