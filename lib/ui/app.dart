import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'theme.dart';

class ToiceApp extends StatelessWidget {
  const ToiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toice',
      theme: toiceLightTheme(),
      darkTheme: toiceDarkTheme(),
      // Default to dark: outdoor riding is the primary context and the black
      // ground reads best in sun (Phase 4.5).
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
