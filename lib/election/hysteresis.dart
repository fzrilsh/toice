/// Handoff hysteresis gate (ADR-003).
///
/// Prevents host flapping: a challenger must beat the current host by a score
/// [margin] *and* keep beating it for a sustained [duration] before a switch is
/// authorized. A single lucky sample, or a challenger that only briefly edges
/// ahead, never triggers a handoff. Clock is injected so the gate is testable
/// without real time.
library;

// Named constructor params cannot be private, so `_clock` is assigned from the
// public `clock` param in the initializer list; that trips this lint.
// ignore_for_file: prefer_initializing_formals

/// Decides when a host handoff is justified, resisting transient swings.
///
/// Feed it one [evaluate] call per election round with the current host's score
/// and the best challenger. It returns true only once the challenger has led by
/// at least [margin] continuously for [duration]. Any round where the lead
/// lapses resets the timer.
class HysteresisGate {
  HysteresisGate({
    required this.margin,
    required this.duration,
    required DateTime Function() clock,
  }) : _clock = clock;

  /// Minimum score advantage a challenger needs over the current host.
  final double margin;

  /// How long that advantage must hold continuously before a switch fires.
  final Duration duration;

  final DateTime Function() _clock;

  /// Device the pending lead belongs to, and when the lead began. Null when no
  /// challenger currently clears the margin.
  String? _leaderId;
  DateTime? _leadingSince;

  /// The challenger currently accumulating time toward a switch, if any.
  String? get pendingLeader => _leaderId;

  /// Evaluate one round. Returns true if a handoff to [challengerId] is now
  /// authorized. [currentHostScore] may be null when there is no current host
  /// (bootstrap): any qualifying challenger then starts its timer immediately.
  bool evaluate({
    required String? challengerId,
    required double? challengerScore,
    required double? currentHostScore,
  }) {
    // No challenger, or it is the current host: nothing to hand off. Reset.
    if (challengerId == null || challengerScore == null) {
      _reset();
      return false;
    }
    final clears =
        currentHostScore == null ||
        challengerScore - currentHostScore >= margin;
    if (!clears) {
      _reset();
      return false;
    }
    final now = _clock();
    // A different challenger than last round restarts the sustained window.
    if (_leaderId != challengerId) {
      _leaderId = challengerId;
      _leadingSince = now;
      return false;
    }
    final elapsed = now.difference(_leadingSince!);
    return elapsed >= duration;
  }

  /// Clear pending state, e.g. after a switch completes or the topology resets.
  void reset() => _reset();

  void _reset() {
    _leaderId = null;
    _leadingSince = null;
  }
}
