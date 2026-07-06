import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/settings.dart';
import 'ui/color_utils.dart';
import 'ui/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();

  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) {
    await windowManager.ensureInitialized();
    final width = settings.windowWidth ?? 900;
    final height = settings.windowHeight ?? 700;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(size: Size(width, height), title: 'EPUB Viewer'),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(EpubViewerApp(settings: settings));
}

/// Build the whole-app theme from the reader's chosen colors so the menu bar, status bar,
/// dialogs and settings screen follow the selected theme (e.g. Dark), not just the content
/// area. Brightness is inferred from the background color's luminance.
ThemeData buildAppTheme(AppSettings settings) {
  final bg = hexToColor(settings.backgroundColor);
  final fg = hexToColor(settings.textColor, fallback: Colors.black);
  final brightness =
      bg.computeLuminance() < 0.5 ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);
  // A subtly contrasting bar color blended toward the text color keeps chrome legible on
  // both light and dark backgrounds without introducing an unrelated accent.
  final barColor = Color.alphaBlend(fg.withValues(alpha: 0.08), bg);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme.copyWith(surface: bg),
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    appBarTheme: AppBarTheme(backgroundColor: barColor, foregroundColor: fg),
    popupMenuTheme: PopupMenuThemeData(color: barColor),
  );
}

class EpubViewerApp extends StatefulWidget {
  final AppSettings settings;
  const EpubViewerApp({super.key, required this.settings});

  @override
  State<EpubViewerApp> createState() => _EpubViewerAppState();
}

class _EpubViewerAppState extends State<EpubViewerApp> {
  late final AppSettings _settings = widget.settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Viewer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_settings),
      home: ReaderScreen(
        settings: _settings,
        // Settings are mutated in place, so rebuilding here re-derives the app theme.
        onSettingsChanged: () => setState(() {}),
      ),
    );
  }
}
