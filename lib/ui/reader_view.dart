import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/content_builder.dart';
import '../models/settings.dart';
import 'color_utils.dart';

/// Paged reader surface. Renders a chapter's blocks as one tall column inside a
/// non-user-scrollable viewport and shows page N by jumping the scroll offset to
/// N * viewportHeight — the same "scroll-to-offset" pagination as the PySide6
/// `reader_view.py`/`paginator.py`. Emits navigation intents (+1/-1) for tap zones,
/// swipes, mouse wheel, and keyboard; the parent applies them (with the chapter-boundary
/// confirm) and feeds back [pageIndex].
class ReaderView extends StatefulWidget {
  final List<ContentBlock> blocks;
  final AppSettings settings;
  final int pageIndex;

  /// Bumped by the parent whenever the chapter content changes, so we re-measure.
  final Object chapterKey;

  /// Reports measured geometry after layout so the parent can compute page count and
  /// re-anchor to a saved character offset.
  final void Function(double contentHeight, double viewportHeight) onMeasured;

  /// +1 = forward/next, -1 = backward/previous.
  final void Function(int direction) onNavigate;

  const ReaderView({
    super.key,
    required this.blocks,
    required this.settings,
    required this.pageIndex,
    required this.chapterKey,
    required this.onMeasured,
    required this.onNavigate,
  });

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  final _controller = ScrollController();
  final _focusNode = FocusNode();
  double _lastContentHeight = -1;
  double _lastViewportHeight = -1;
  Object? _lastChapterKey;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _afterLayout(double viewportHeight) {
    if (!_controller.hasClients) return;
    final maxExtent = _controller.position.maxScrollExtent;
    final contentHeight = maxExtent + viewportHeight;
    final chapterChanged = _lastChapterKey != widget.chapterKey;
    if (chapterChanged ||
        contentHeight != _lastContentHeight ||
        viewportHeight != _lastViewportHeight) {
      _lastContentHeight = contentHeight;
      _lastViewportHeight = viewportHeight;
      _lastChapterKey = widget.chapterKey;
      widget.onMeasured(contentHeight, viewportHeight);
    }
    _jumpToPage(viewportHeight);
  }

  void _jumpToPage(double viewportHeight) {
    if (!_controller.hasClients) return;
    final target = (widget.pageIndex * viewportHeight)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if ((_controller.offset - target).abs() > 0.5) {
      _controller.jumpTo(target);
    }
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.space) {
      widget.onNavigate(1);
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      widget.onNavigate(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final bg = hexToColor(s.backgroundColor);
    final pad = s.contentPadding.toDouble();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        _handleKey(event);
        return KeyEventResult.handled;
      },
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            widget.onNavigate(signal.scrollDelta.dy > 0 ? 1 : -1);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final w = context.size?.width ?? 0;
            final x = details.localPosition.dx;
            if (w <= 0) return;
            if (x < w / 3) {
              widget.onNavigate(-1);
            } else if (x > w * 2 / 3) {
              widget.onNavigate(1);
            }
          },
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -100) {
              widget.onNavigate(1); // swipe left -> next
            } else if (v > 100) {
              widget.onNavigate(-1); // swipe right -> previous
            }
          },
          child: Container(
            color: bg,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportHeight = constraints.maxHeight - 2 * pad;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _afterLayout(viewportHeight > 0 ? viewportHeight : constraints.maxHeight);
                });
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: ClipRect(
                    child: SingleChildScrollView(
                      controller: _controller,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildBlockWidgets(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBlockWidgets() {
    final s = widget.settings;
    final base = TextStyle(
      fontFamily: s.fontFamily,
      fontSize: s.fontSize.toDouble(),
      color: hexToColor(s.textColor),
      height: 1.5,
    );
    final paraGap = s.paragraphSpacing.toDouble();
    final widgets = <Widget>[];
    for (final block in widget.blocks) {
      switch (block.kind) {
        case BlockKind.image:
          if (block.imageBytes != null) {
            widgets.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.memory(
                Uint8List.fromList(block.imageBytes!),
                fit: BoxFit.scaleDown, // shrink oversized images to width, never upscale
                width: double.infinity,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            ));
          }
          break;
        case BlockKind.heading:
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text.rich(
              _spanFor(block.runs, base, headingLevel: block.headingLevel),
            ),
          ));
          break;
        case BlockKind.paragraph:
          widgets.add(Padding(
            padding: EdgeInsets.only(bottom: paraGap),
            child: Text.rich(_spanFor(block.runs, base)),
          ));
          break;
      }
    }
    return widgets;
  }

  TextSpan _spanFor(List<InlineRun> runs, TextStyle base, {int headingLevel = 0}) {
    var blockStyle = base;
    if (headingLevel > 0) {
      final scale = [1.8, 1.5, 1.3, 1.15, 1.05, 1.0][(headingLevel - 1).clamp(0, 5)];
      blockStyle = base.copyWith(
          fontSize: base.fontSize! * scale, fontWeight: FontWeight.bold);
    }
    return TextSpan(
      children: [
        for (final run in runs)
          TextSpan(
            text: run.text,
            style: blockStyle.copyWith(
              color: run.color != null ? hexToColor(run.color!) : blockStyle.color,
              fontWeight: run.bold ? FontWeight.bold : blockStyle.fontWeight,
              fontStyle: run.italic ? FontStyle.italic : null,
            ),
          ),
      ],
    );
  }
}
