import 'package:flutter/material.dart';

import 'home_screen.dart';

class ToiceApp extends StatelessWidget {
  const ToiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toice',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomeScreen(),
    );
  }
}
