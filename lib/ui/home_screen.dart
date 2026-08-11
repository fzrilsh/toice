import 'package:flutter/material.dart';

/// Placeholder home screen. Real UI (group create/join, QR bootstrap, call
/// status) lands in Phase 4 (ADR-002 / CLAUDE.md delivery phases).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Toice')),
      body: const Center(
        child: Text('Scaffold ready. Core features start at Phase 0.'),
      ),
    );
  }
}
