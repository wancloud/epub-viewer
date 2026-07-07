import 'package:flutter/material.dart';

import '../models/epub_book.dart';

/// "Change Chapter" dialog: shows the book's table of contents as an indented,
/// expandable tree. Returns the chosen chapter index (or null if cancelled).
/// Port of `epubviewer/ui/toc_dialog.py` (see backup/pyside6/).
class TocScreen extends StatelessWidget {
  final List<TocEntry> toc;
  final int currentChapterIndex;
  final double uiFontScale;

  const TocScreen({
    super.key,
    required this.toc,
    required this.currentChapterIndex,
    this.uiFontScale = 1.0,
  });

  static Future<int?> show(BuildContext context, List<TocEntry> toc,
      int currentChapterIndex, {double uiFontScale = 1.0}) {
    return showDialog<int>(
      context: context,
      builder: (_) => TocScreen(
          toc: toc, currentChapterIndex: currentChapterIndex, uiFontScale: uiFontScale),
    );
  }

  @override
  Widget build(BuildContext context) {
    // showDialog attaches to the root Navigator, above the reader's local MediaQuery
    // override, so the UI-font-size scaling wouldn't otherwise reach this dialog —
    // reapply it explicitly here.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(uiFontScale)),
      child: _buildDialog(context),
    );
  }

  Widget _buildDialog(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Change Chapter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            Flexible(
              child: toc.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('This book has no table of contents.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [for (final e in toc) _buildEntry(context, e, 0)],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, TocEntry entry, int depth) {
    final selectable = entry.chapterIndex >= 0;
    final isCurrent = entry.chapterIndex == currentChapterIndex;
    final tile = Padding(
      // spacing between chapters + indentation for nesting (mirrors the Qt padding/indent)
      padding: EdgeInsets.only(left: 8.0 + depth * 16, right: 8, top: 3, bottom: 3),
      child: InkWell(
        onTap: selectable ? () => Navigator.of(context).pop(entry.chapterIndex) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Text(
            entry.title.isEmpty ? '(untitled)' : entry.title,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: selectable ? null : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ),
    );
    if (entry.children.isEmpty) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        for (final c in entry.children) _buildEntry(context, c, depth + 1),
      ],
    );
  }
}
