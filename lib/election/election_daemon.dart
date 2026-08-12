/// Election daemon orchestration (ADR-003).
///
/// Ties the pure pieces together into the continuous election loop: collect peer
/// [ElectionBroadcast]s off a channel, prune stale ones, rank
/// ([rankCandidates]), run the [HysteresisGate], and when a switch is authorized
/// and *this* device is the winner, drive a [HandoffMachine] to take over.
///
/// The daemon owns no radio and no real timer. It talks to an [ElectionChannel]
/// (a mock in tests, a data channel over the hotspot on device) and is advanced
/// by explicit [tick] calls, so the whole loop is deterministic under test.
library;

import 'package:toice/election/broadcast.dart';
import 'package:toice/election/fitness_score.dart';
import 'package:toice/election/handoff.dart';
import 'package:toice/election/hysteresis.dart';
import 'package:toice/election/ranking.dart';

/// Control messages the daemon exchanges with peers, alongside broadcasts.
sealed class ElectionSignal {
  const ElectionSignal(this.senderId);
  final String senderId;
}

/// "I am taking over as host." Sent by the elected new host.
class HandoffIntent extends ElectionSignal {
  const HandoffIntent(super.senderId);
}

/// "Acknowledged, go ahead." Sent by each peer in reply to an intent.
class HandoffAck extends ElectionSignal {
  const HandoffAck(super.senderId, this.toHost);

  /// The new host this ack is addressed to.
  final String toHost;
}

/// The daemon's transport. Broadcasts and control signals go out via [emit] /
/// [emitSignal]; inbound ones are delivered by the daemon's owner calling
/// [ElectionDaemon.onBroadcast] / [ElectionDaemon.onSignal]. Deliberately not a
/// stream, so tests drive delivery synchronously.
abstract class ElectionChannel {
  void emit(ElectionBroadcast broadcast);
  void emitSignal(ElectionSignal signal);
}

/// What the daemon needs to perform an authorized switch. Implemented over the
/// native hotspot bridge on device; a fake in tests.
abstract class HostSwitcher {
  /// This device becomes host (start AP with the trip credentials).
  Future<void> becomeHost();

  /// This device stops hosting (old host during a handoff).
  Future<void> stopHosting();
}

/// Continuous host election for one device (ADR-003).
class ElectionDaemon {
  ElectionDaemon({
    required this.deviceId,
    required this.channel,
    required this.switcher,
    required DateTime Function() clock,
    this.staleAfter = const Duration(seconds: 6),
    double margin = 10,
    Duration hysteresisDuration = const Duration(seconds: 5),
    this.ackTimeout = const Duration(seconds: 2),
    this.weights = const FitnessWeights(),
  }) : _clock = clock,
       _gate = HysteresisGate(
         margin: margin,
         duration: hysteresisDuration,
         clock: clock,
       );

  final String deviceId;
  final ElectionChannel channel;
  final HostSwitcher switcher;
  final DateTime Function() _clock;

  /// Drop a peer's broadcast if no fresher one arrives within this window; a
  /// silent peer is assumed gone and stops counting as a candidate.
  final Duration staleAfter;
  final Duration ackTimeout;
  final FitnessWeights weights;

  final HysteresisGate _gate;

  /// Latest broadcast per sender and the local time it arrived (for staleness;
  /// senders' own clocks are not comparable across devices).
  final Map<String, ElectionBroadcast> _latest = {};
  final Map<String, DateTime> _seenAt = {};

  /// Device currently serving as host, as this daemon believes it. Null until a
  /// first election settles.
  String? _currentHost;
  String? get currentHost => _currentHost;

  HandoffMachine? _handoff;
  HandoffState get handoffState => _handoff?.state ?? HandoffState.stable;

  /// Whether this device is the acting host right now.
  bool get isHost => _currentHost == deviceId;

  /// Ingest a peer broadcast (called by the channel owner).
  void onBroadcast(ElectionBroadcast b) {
    if (b.senderId == deviceId) return; // ignore echoes of our own
    _latest[b.senderId] = b;
    _seenAt[b.senderId] = _clock();
  }

  /// Publish this device's own fitness so peers can rank it.
  void broadcastSelf(ElectionBroadcast self) {
    _latest[deviceId] = self;
    _seenAt[deviceId] = _clock();
    channel.emit(self);
  }

  /// Handle an inbound control signal (intent/ack).
  Future<void> onSignal(ElectionSignal s) async {
    switch (s) {
      case HandoffIntent():
        // A peer is claiming host. Ack it and defer; step down if we host.
        _currentHost = s.senderId;
        channel.emitSignal(HandoffAck(deviceId, s.senderId));
      case HandoffAck(:final toHost):
        if (toHost != deviceId || _handoff == null) return;
        await _apply(_handoff!.onAck(s.senderId));
    }
  }

  /// Advance the election one step. Prune stale peers, re-rank, and either drive
  /// an in-flight handoff or, if a switch just became justified and we won,
  /// start one.
  Future<void> tick() async {
    _pruneStale();

    if (_handoff != null) {
      await _apply(_handoff!.onTick());
      return;
    }

    final ranked = rankCandidates(_latest.values, weights: weights);
    if (ranked.isEmpty) return;
    final winner = ranked.first;
    final hostScore = _currentHost == null
        ? null
        : _scoreOf(_currentHost!, ranked);

    final authorized = _gate.evaluate(
      challengerId: winner.deviceId,
      challengerScore: winner.score,
      currentHostScore: hostScore,
    );
    if (!authorized) return;

    _gate.reset();
    if (winner.deviceId == deviceId) {
      // We won: run the handoff protocol to take over.
      final peers = _latest.keys.where((id) => id != deviceId).toSet();
      _handoff = HandoffMachine(
        newHostId: deviceId,
        expectedAckers: peers,
        ackTimeout: ackTimeout,
        clock: _clock,
      );
      await _apply(_handoff!.begin());
    } else {
      // A peer won; record it. That device drives its own handoff and will
      // announce intent, which we ack in onSignal.
      _currentHost = winner.deviceId;
    }
  }

  double? _scoreOf(String id, List<Ranked> ranked) {
    for (final r in ranked) {
      if (r.deviceId == id) return r.score;
    }
    return null; // current host no longer a candidate (gone/ineligible)
  }

  Future<void> _apply(HandoffStep step) async {
    switch (step.action) {
      case HandoffAction.broadcastIntent:
        channel.emitSignal(HandoffIntent(deviceId));
      case HandoffAction.performSwitch:
        if (_currentHost != null && _currentHost != deviceId) {
          await switcher.stopHosting();
        }
        await switcher.becomeHost();
        _currentHost = deviceId;
        await _apply(_handoff!.onSwitchComplete());
      case HandoffAction.complete:
        _handoff = null;
      case HandoffAction.none:
        break;
    }
  }

  void _pruneStale() {
    final now = _clock();
    _seenAt.removeWhere((id, at) {
      final stale = now.difference(at) > staleAfter;
      if (stale) _latest.remove(id);
      return stale;
    });
  }
}
