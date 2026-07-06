import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/content_builder.dart';
import '../logic/paginator.dart';
import '../models/epub_book.dart';
import '../models/settings.dart';
import 'color_utils.dart';
import 'reader_view.dart';
import 'settings_screen.dart';
import 'status_bar.dart';
import 'toc_screen.dart';

const _chapterConfirmDuration = Duration(seconds: 2);

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Main window: menu (Open / Change Chapter / Viewer Settings), reader surface, and
/// status bar. Port of `epubviewer/ui/main_window.py` (see backup/pyside6/).
class ReaderScreen extends StatefulWidget {
  final AppSettings settings;
  const ReaderScreen({super.key, required this.settings});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  late AppSettings _settings = widget.settings;
  EpubBook? _book;
  int _chapterIndex = 0;
  int _pageIndex = 0;
  int _pageCount = 1;
  int _charOffset = 0;
  List<ContentBlock> _blocks = [];
  int _chapterKey = 0;
  Paginator? _paginator;

  int? _pendingCharOffset;
  bool _goToLastPageAfterMeasure = false;
  int? _pendingDirection;
  Timer? _confirmTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLastSession());
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _persist();
    }
  }

  Future<void> _persist() async {
    if (_isDesktop) {
      try {
        final size = await windowManager.getSize();
        _settings.windowWidth = size.width;
        _settings.windowHeight = size.height;
      } catch (_) {/* window manager unavailable */}
    }
    await _settings.save();
  }

  Future<void> _restoreLastSession() async {
    if (_settings.recentBooks.isEmpty) return;
    final entry = _settings.recentBooks.first;
    await _openPath(entry.path,
        chapterIndex: entry.chapterIndex, charOffset: entry.charOffset);
  }

  // ---- opening books ----

  Future<void> _openFileDialog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;
    await _loadBook(file.path ?? file.name, bytes);
  }

  Future<void> _openPath(String path, {int chapterIndex = 0, int charOffset = 0}) async {
    try {
      final bytes = await File(path).readAsBytes();
      await _loadBook(path, bytes, chapterIndex: chapterIndex, charOffset: charOffset);
    } catch (e) {
      // A saved path can become unreadable (e.g. Android cache eviction). Drop it.
      _settings.recentBooks.removeWhere((b) => b.path == path);
      await _settings.save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reopen "${path.split(RegExp(r"[\\/]")).last}"')),
        );
      }
    }
  }

  Future<void> _loadBook(String path, List<int> bytes,
      {int chapterIndex = 0, int charOffset = 0}) async {
    EpubBook book;
    try {
      book = await EpubBook.loadFromBytes(path, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to open EPUB: $e')));
      }
      return;
    }
    _book = book;
    final ci = chapterIndex.clamp(0, book.chapters.length - 1);
    _settings.recordBookOpened(path, book.title,
        chapterIndex: ci, charOffset: charOffset);
    await _settings.save();
    _loadChapter(ci, charOffset: charOffset);
  }

  // ---- chapter / page navigation ----

  void _loadChapter(int index, {int charOffset = 0, bool toLastPage = false}) {
    final book = _book;
    if (book == null) return;
    _confirmTimer?.cancel();
    _pendingDirection = null;
    final chapter = book.chapters[index];
    setState(() {
      _chapterIndex = index;
      _blocks = buildChapterBlocks(chapter.rawHtml, _settings.dialogueConfig, book, chapter.href);
      _chapterKey++;
      _pageIndex = 0;
      _pageCount = 1;
      _pendingCharOffset = toLastPage ? null : charOffset;
      _goToLastPageAfterMeasure = toLastPage;
      _charOffset = charOffset;
    });
  }

  void _onMeasured(double contentHeight, double viewportHeight) {
    final book = _book;
    if (book == null) return;
    final paginator = Paginator(contentHeight, viewportHeight);
    final chapterLen = book.chapters[_chapterIndex].plainTextLen;
    var page = _pageIndex;
    if (_goToLastPageAfterMeasure) {
      page = paginator.pageCount - 1;
      _goToLastPageAfterMeasure = false;
    } else if (_pendingCharOffset != null) {
      page = paginator.pageForCharOffset(_pendingCharOffset!, chapterLen);
      _pendingCharOffset = null;
    }
    page = page.clamp(0, paginator.pageCount - 1);
    setState(() {
      _paginator = paginator;
      _pageCount = paginator.pageCount;
      _pageIndex = page;
      _charOffset = paginator.charOffsetForPage(page, chapterLen);
    });
    _recordProgress();
  }

  void _goToPage(int page) {
    final book = _book;
    if (book == null || _paginator == null) return;
    final clamped = page.clamp(0, _pageCount - 1);
    setState(() {
      _pageIndex = clamped;
      _charOffset =
          _paginator!.charOffsetForPage(clamped, book.chapters[_chapterIndex].plainTextLen);
    });
    _recordProgress();
  }

  void _recordProgress() {
    final book = _book;
    if (book == null) return;
    _settings.updateReadingProgress(book.path, _chapterIndex, _charOffset);
  }

  // Navigation with a 2-second chapter-boundary confirm (ported from reader_view.py):
  // within a chapter each intent turns a page immediately; at a boundary the first intent
  // only arms a pending direction, and only a second intent in the same direction within
  // the window actually changes chapter, so one overscroll doesn't skip chapters.
  void _navigate(int direction) {
    if (_book == null) return;
    if (direction > 0) {
      _forward();
    } else {
      _backward();
    }
  }

  void _cancelPending() {
    _confirmTimer?.cancel();
    _pendingDirection = null;
  }

  void _forward() {
    if (_pageIndex + 1 < _pageCount) {
      _cancelPending();
      _goToPage(_pageIndex + 1);
      return;
    }
    if (_pendingDirection == 1) {
      _cancelPending();
      if (_chapterIndex + 1 < _book!.chapters.length) _loadChapter(_chapterIndex + 1);
      return;
    }
    _armPending(1);
  }

  void _backward() {
    if (_pageIndex > 0) {
      _cancelPending();
      _goToPage(_pageIndex - 1);
      return;
    }
    if (_pendingDirection == -1) {
      _cancelPending();
      if (_chapterIndex > 0) _loadChapter(_chapterIndex - 1, toLastPage: true);
      return;
    }
    _armPending(-1);
  }

  void _armPending(int direction) {
    _pendingDirection = direction;
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_chapterConfirmDuration, () => _pendingDirection = null);
  }

  // ---- menu actions ----

  Future<void> _openChangeChapter() async {
    final book = _book;
    if (book == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Open an EPUB first.')));
      return;
    }
    final index = await TocScreen.show(context, book.toc, _chapterIndex);
    if (index != null) _loadChapter(index);
  }

  Future<void> _openSettings() async {
    final updated = await SettingsScreen.show(context, _settings);
    if (updated == null) return;
    setState(() => _settings = updated);
    await _settings.save();
    // Re-render current chapter (dialogue config / colors may have changed), re-anchoring
    // to the current reading position.
    if (_book != null) _loadChapter(_chapterIndex, charOffset: _charOffset);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final chapterTitle = book != null ? book.chapters[_chapterIndex].title : '';
    final percent = book != null ? overallPercentage(book, _chapterIndex, _charOffset) : 0.0;
    final scale = (_settings.uiFontSize / 9.0).clamp(0.7, 2.7);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(book != null ? 'EPUB Viewer — ${book.title}' : 'EPUB Viewer',
              overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                tooltip: 'Open EPUB', icon: const Icon(Icons.folder_open), onPressed: _openFileDialog),
            IconButton(
                tooltip: 'Change chapter', icon: const Icon(Icons.list), onPressed: _openChangeChapter),
            PopupMenuButton<String>(
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'open', child: Text('Open…')),
                const PopupMenuItem(value: 'toc', child: Text('Change Chapter…')),
                const PopupMenuItem(value: 'settings', child: Text('Viewer Settings…')),
                if (_settings.recentBooks.isNotEmpty) const PopupMenuDivider(),
                for (final b in _settings.recentBooks)
                  PopupMenuItem(
                    value: 'recent:${b.path}',
                    child: Text(b.title.isEmpty ? b.path.split(RegExp(r'[\\/]')).last : b.title,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onSelected: (v) {
                if (v == 'open') {
                  _openFileDialog();
                } else if (v == 'toc') {
                  _openChangeChapter();
                } else if (v == 'settings') {
                  _openSettings();
                } else if (v.startsWith('recent:')) {
                  final path = v.substring('recent:'.length);
                  final entry = _settings.recentBooks.firstWhere((b) => b.path == path);
                  _openPath(entry.path,
                      chapterIndex: entry.chapterIndex, charOffset: entry.charOffset);
                }
              },
            ),
          ],
        ),
        body: Container(
          color: hexToColor(_settings.backgroundColor),
          child: book == null
              ? const Center(child: Text('Open an EPUB file to start reading.'))
              : ReaderView(
                  blocks: _blocks,
                  settings: _settings,
                  pageIndex: _pageIndex,
                  chapterKey: _chapterKey,
                  onMeasured: _onMeasured,
                  onNavigate: _navigate,
                ),
        ),
        bottomNavigationBar: ReaderStatusBar(
          chapterTitle: chapterTitle,
          pageIndex: _pageIndex,
          pageCount: _pageCount,
          percentage: percent,
          hasBook: book != null,
        ),
      ),
    );
  }
}
