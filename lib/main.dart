import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/settings.dart';
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

class EpubViewerApp extends StatelessWidget {
  final AppSettings settings;
  const EpubViewerApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: ReaderScreen(settings: settings),
    );
  }
}
