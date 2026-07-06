import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/dialogue_rules.dart';

/// App settings, recent-books list, and reading progress.
///
/// Port of the PySide6 app's `epubviewer/settings.py` (see backup/pyside6/). Persistence
/// uses shared_preferences (cross-platform: Windows + Android) instead of a JSON file.

const int kMaxRecentBooks = 10;
const String _prefsKey = 'epub_viewer_settings';

/// Named color themes; each sets text + background. Mirrors settings.py THEMES.
const Map<String, Map<String, String>> kThemes = {
  'Light': {'text_color': '#1a1a1a', 'background_color': '#ffffff'},
  'Dark': {'text_color': '#e8e8e8', 'background_color': '#1e1e1e'},
  'Sepia': {'text_color': '#3b2f2f', 'background_color': '#f4ecd8'},
};

DialogueConfig _defaultDialogueConfig() => const DialogueConfig(pairs: [
      QuotePair(open: '「', close: '」', color: '#1a5fb4', enabled: true),
      QuotePair(open: '"', close: '"', color: '#1a5fb4', enabled: true),
      QuotePair(open: "'", close: "'", color: '#1a5fb4', enabled: false),
      QuotePair(open: '«', close: '»', color: '#1a5fb4', enabled: false),
    ]);

class RecentBook {
  final String path;
  final String title;
  int chapterIndex;
  int charOffset;

  RecentBook({
    required this.path,
    this.title = '',
    this.chapterIndex = 0,
    this.charOffset = 0,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'chapter_index': chapterIndex,
        'char_offset': charOffset,
      };

  factory RecentBook.fromJson(Map<String, dynamic> d) => RecentBook(
        path: d['path'] as String,
        title: d['title'] as String? ?? '',
        chapterIndex: d['chapter_index'] as int? ?? 0,
        charOffset: d['char_offset'] as int? ?? 0,
      );
}

class AppSettings {
  String fontFamily;
  int fontSize;
  String textColor;
  String backgroundColor;
  String themeName;
  int uiFontSize;
  int contentPadding;
  DialogueConfig dialogueConfig;
  List<RecentBook> recentBooks;
  double? windowWidth;
  double? windowHeight;

  AppSettings({
    this.fontFamily = 'Yu Gothic',
    this.fontSize = 14,
    this.textColor = '#1a1a1a',
    this.backgroundColor = '#ffffff',
    this.themeName = 'Light',
    this.uiFontSize = 9,
    this.contentPadding = 20,
    DialogueConfig? dialogueConfig,
    List<RecentBook>? recentBooks,
    this.windowWidth,
    this.windowHeight,
  })  : dialogueConfig = dialogueConfig ?? _defaultDialogueConfig(),
        recentBooks = recentBooks ?? [];

  void applyTheme(String name) {
    final colors = kThemes[name];
    if (colors == null) return;
    themeName = name;
    textColor = colors['text_color']!;
    backgroundColor = colors['background_color']!;
  }

  /// Move [path] to the front of the recent list, trimmed to kMaxRecentBooks.
  void recordBookOpened(String path, String title,
      {int chapterIndex = 0, int charOffset = 0}) {
    recentBooks.removeWhere((b) => b.path == path);
    recentBooks.insert(
        0,
        RecentBook(
            path: path,
            title: title,
            chapterIndex: chapterIndex,
            charOffset: charOffset));
    if (recentBooks.length > kMaxRecentBooks) {
      recentBooks.removeRange(kMaxRecentBooks, recentBooks.length);
    }
  }

  void updateReadingProgress(String path, int chapterIndex, int charOffset) {
    for (final b in recentBooks) {
      if (b.path == path) {
        b.chapterIndex = chapterIndex;
        b.charOffset = charOffset;
        return;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'font_family': fontFamily,
        'font_size': fontSize,
        'text_color': textColor,
        'background_color': backgroundColor,
        'theme_name': themeName,
        'ui_font_size': uiFontSize,
        'content_padding': contentPadding,
        'dialogue_config': dialogueConfig.toJson(),
        'recent_books': recentBooks.map((b) => b.toJson()).toList(),
        'window_width': windowWidth,
        'window_height': windowHeight,
      };

  factory AppSettings.fromJson(Map<String, dynamic> d) {
    final defaults = AppSettings();
    return AppSettings(
      fontFamily: d['font_family'] as String? ?? defaults.fontFamily,
      fontSize: d['font_size'] as int? ?? defaults.fontSize,
      textColor: d['text_color'] as String? ?? defaults.textColor,
      backgroundColor: d['background_color'] as String? ?? defaults.backgroundColor,
      themeName: d['theme_name'] as String? ?? defaults.themeName,
      uiFontSize: d['ui_font_size'] as int? ?? defaults.uiFontSize,
      contentPadding: d['content_padding'] as int? ?? defaults.contentPadding,
      dialogueConfig: d['dialogue_config'] != null
          ? DialogueConfig.fromJson(d['dialogue_config'] as Map<String, dynamic>)
          : defaults.dialogueConfig,
      recentBooks: ((d['recent_books'] as List?) ?? [])
          .map((b) => RecentBook.fromJson(b as Map<String, dynamic>))
          .toList(),
      windowWidth: (d['window_width'] as num?)?.toDouble(),
      windowHeight: (d['window_height'] as num?)?.toDouble(),
    );
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // fall through to defaults on corrupt data
      }
    }
    return AppSettings();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }
}
