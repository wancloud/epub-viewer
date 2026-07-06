import 'package:flutter/material.dart';

import '../logic/dialogue_rules.dart';
import '../models/settings.dart';
import 'color_utils.dart';

/// Viewer settings: content font family/size, UI font size, content padding, theme,
/// text/background colors, and the configurable dialogue quote-pair table.
/// Port of `epubviewer/ui/settings_dialog.py` (see backup/pyside6/).
///
/// Edits a working copy and returns the updated [AppSettings] on Save (null on Cancel).
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  static Future<AppSettings?> show(BuildContext context, AppSettings settings) {
    return Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(settings: settings)),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// Quick-pick suggestions only — the family is a free-text field, so any font the OS has
// (e.g. "Noto Sans TC") can be typed in even if it isn't listed here.
const _fontFamilies = [
  'Yu Gothic', 'Noto Sans', 'Noto Serif', 'Noto Sans TC', 'Noto Sans SC',
  'Noto Serif TC', 'Microsoft JhengHei', 'Roboto', 'Serif', 'Sans Serif', 'Monospace',
];

const _swatches = [
  '#1a1a1a', '#ffffff', '#e8e8e8', '#1e1e1e', '#3b2f2f', '#f4ecd8',
  '#1a5fb4', '#c01c28', '#2ec27e', '#e66100', '#9141ac', '#000000',
];

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _fontFamilyController;
  late int _fontSize;
  late int _uiFontSize;
  late int _contentPadding;
  late String _themeName;
  late String _textColor;
  late String _bgColor;
  late List<QuotePair> _pairs;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _fontFamilyController = TextEditingController(text: s.fontFamily);
    _fontSize = s.fontSize;
    _uiFontSize = s.uiFontSize;
    _contentPadding = s.contentPadding;
    _themeName = kThemes.containsKey(s.themeName) ? s.themeName : 'Custom';
    _textColor = s.textColor;
    _bgColor = s.backgroundColor;
    _pairs = s.dialogueConfig.pairs
        .map((p) => p.copyWith())
        .toList(); // shallow copies (QuotePair is immutable)
  }

  @override
  void dispose() {
    _fontFamilyController.dispose();
    super.dispose();
  }

  Future<String?> _pickColor(String current) {
    final customController = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose color'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hex in _swatches)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(hex),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: hexToColor(hex),
                          border: Border.all(
                              color: hex == current ? Colors.blue : Colors.grey,
                              width: hex == current ? 3 : 1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Custom hex:'),
              const SizedBox(height: 4),
              TextField(
                controller: customController,
                autofocus: false,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '#e18a24',
                ),
                onSubmitted: (v) {
                  final hex = normalizeHexColor(v);
                  if (hex != null) Navigator.of(ctx).pop(hex);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final hex = normalizeHexColor(customController.text);
              if (hex != null) {
                Navigator.of(ctx).pop(hex);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter a valid hex color like #e18a24')),
                );
              }
            },
            child: const Text('Use custom'),
          ),
        ],
      ),
    );
  }

  AppSettings _collect() {
    final s = widget.settings;
    final family = _fontFamilyController.text.trim();
    s.fontFamily = family.isEmpty ? s.fontFamily : family;
    s.fontSize = _fontSize;
    s.uiFontSize = _uiFontSize;
    s.contentPadding = _contentPadding;
    s.themeName = _themeName;
    s.textColor = _textColor;
    s.backgroundColor = _bgColor;
    s.dialogueConfig = DialogueConfig(
        pairs: _pairs.where((p) => p.open.isNotEmpty && p.close.isNotEmpty).toList());
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewer Settings'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_collect()),
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Content font'),
          Row(children: [
            const Text('Family:'),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _fontFamilyController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Noto Sans TC',
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down),
              tooltip: 'Common fonts',
              itemBuilder: (_) =>
                  [for (final f in _fontFamilies) PopupMenuItem(value: f, child: Text(f))],
              onSelected: (v) => _fontFamilyController.text = v,
            ),
          ]),
          _stepperRow('Size', _fontSize, 8, 48, (v) => setState(() => _fontSize = v)),
          _stepperRow('UI font size', _uiFontSize, 7, 24, (v) => setState(() => _uiFontSize = v)),
          _stepperRow('Content padding (px)', _contentPadding, 0, 200,
              (v) => setState(() => _contentPadding = v), step: 4),
          const Divider(height: 32),
          _sectionTitle('Theme & colors'),
          Row(children: [
            const Text('Theme:'),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _themeName,
              items: [
                for (final t in [...kThemes.keys, 'Custom'])
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() {
                _themeName = v!;
                final colors = kThemes[v];
                if (colors != null) {
                  _textColor = colors['text_color']!;
                  _bgColor = colors['background_color']!;
                }
              }),
            ),
          ]),
          Row(children: [
            _colorButton('Text', _textColor, (hex) => setState(() {
                  _textColor = hex;
                  _themeName = 'Custom';
                })),
            const SizedBox(width: 12),
            _colorButton('Background', _bgColor, (hex) => setState(() {
                  _bgColor = hex;
                  _themeName = 'Custom';
                })),
          ]),
          const Divider(height: 32),
          _sectionTitle('Dialogue quote markers'),
          for (var i = 0; i < _pairs.length; i++) _pairRow(i),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() =>
                  _pairs.add(const QuotePair(open: '', close: '', color: '#1a5fb4'))),
              icon: const Icon(Icons.add),
              label: const Text('Add pair'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

  Widget _stepperRow(String label, int value, int min, int max, ValueChanged<int> onChanged,
      {int step = 1}) {
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(
        icon: const Icon(Icons.remove),
        onPressed: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
      ),
      SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center)),
      IconButton(
        icon: const Icon(Icons.add),
        onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
      ),
    ]);
  }

  Widget _colorButton(String label, String hex, ValueChanged<String> onPicked) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () async {
          final picked = await _pickColor(hex);
          if (picked != null) onPicked(picked);
        },
        child: Row(children: [
          Container(width: 20, height: 20, color: hexToColor(hex)),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Widget _pairRow(int i) {
    final p = _pairs[i];
    // NB: the onChanged callbacks read _pairs[i] fresh (not the captured `p`). The Open and
    // Close fields don't trigger a rebuild, so a captured `p` would be stale — editing Close
    // after Open would copyWith off the pre-Open value and silently drop the Open marker.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        _markerField(p.open, (v) => _pairs[i] = _pairs[i].copyWith(open: v), 'Open'),
        const SizedBox(width: 8),
        _markerField(p.close, (v) => _pairs[i] = _pairs[i].copyWith(close: v), 'Close'),
        const SizedBox(width: 8),
        InkWell(
          onTap: () async {
            final picked = await _pickColor(_pairs[i].color);
            if (picked != null) setState(() => _pairs[i] = _pairs[i].copyWith(color: picked));
          },
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: hexToColor(p.color), border: Border.all(color: Colors.grey)),
          ),
        ),
        Switch(
          value: p.enabled,
          onChanged: (v) => setState(() => _pairs[i] = _pairs[i].copyWith(enabled: v)),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _pairs.removeAt(i)),
        ),
      ]),
    );
  }

  Widget _markerField(String value, ValueChanged<String> onChanged, String hint) {
    return SizedBox(
      width: 56,
      child: TextFormField(
        initialValue: value,
        textAlign: TextAlign.center,
        decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }
}
