import 'package:flutter/material.dart';

/// Bottom status bar: chapter title, page N/total in chapter, overall percentage.
/// Port of `epubviewer/ui/status_bar.py` (see backup/pyside6/).
class ReaderStatusBar extends StatelessWidget {
  final String chapterTitle;
  final int pageIndex;
  final int pageCount;
  final double percentage;
  final bool hasBook;

  const ReaderStatusBar({
    super.key,
    required this.chapterTitle,
    required this.pageIndex,
    required this.pageCount,
    required this.percentage,
    required this.hasBook,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasBook ? chapterTitle : 'No book loaded',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (hasBook) ...[
            Text('Page ${pageIndex + 1} / $pageCount', style: style),
            const SizedBox(width: 16),
            Text('${percentage.toStringAsFixed(1)}%', style: style),
          ],
        ],
      ),
    );
  }
}
