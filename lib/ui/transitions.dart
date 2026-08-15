/// Shared page transition (Phase 4.5). One motion vocabulary across the app: a
/// short slide-up with a fade, so pushing into Host/Join/Call feels like one
/// flow rather than default platform cuts.
///
/// Respects the OS reduce-motion setting: when on, it degrades to a plain fade
/// (no slide) to meet the accessibility floor.
library;

import 'package:flutter/material.dart';

Route<T> toiceRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, animation, _, child) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final fade = FadeTransition(opacity: eased, child: child);
    if (MediaQuery.of(context).disableAnimations) return fade;
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(eased),
      child: fade,
    );
  },
);
