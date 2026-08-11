/// Handoff state machine (ADR-003).
///
/// Once the [HysteresisGate] authorizes a switch, the elected new host must take
/// over without ever having two APs live at once (ADR-001 single-host
/// invariant). This FSM sequences that: announce intent, collect acks from the
/// other riders, then switch. If acks do not all arrive in time it still takes
/// over unilaterally, on the theory that a degraded single host beats a stalled
/// convoy. Pure logic: it emits [HandoffAction]s for the daemon to carry out and
/// never touches the radio itself.
library;

// `_clock`/`_expected` are private fields assigned from public named ctor params
// (named params cannot be private), which trips this lint.
// ignore_for_file: prefer_initializing_formals

/// Where a handoff is in its lifecycle (ADR-003).
enum HandoffState {
  /// No handoff in flight; a host is (or nobody is) serving.
  stable,

  /// The new host has broadcast its intent and is waiting to gather acks.
  awaitingAcks,

  /// Acks are in (or timed out); the old AP is being torn down and the new one
  /// brought up. No AP is live during this window, by design.
  switching,
}

/// A side effect the daemon must perform. The FSM decides *what*; the daemon
/// (over the real data channel + native bridge) decides *how*.
enum HandoffAction {
  none,

  /// Broadcast "I intend to become host" to all peers.
  broadcastIntent,

  /// Old host: stop the AP. New host: start it. Guarded so the two never
  /// overlap (single-host invariant).
  performSwitch,

  /// Handoff finished; resume normal election ticking.
  complete,
}

/// Result of feeding one event to the machine: the new state and the action to
/// take. Kept as a pair so callers get both atomically.
class HandoffStep {
  const HandoffStep(this.state, this.action);

  final HandoffState state;
  final HandoffAction action;
}

/// Drives one handoff attempt from intent to completion.
///
/// The device electing itself the new host constructs this with the set of peer
/// ids it expects acks from. Timeouts use the injected [clock] so the daemon can
/// tick it deterministically.
class HandoffMachine {
  HandoffMachine({
    required this.newHostId,
    required Set<String> expectedAckers,
    required this.ackTimeout,
    required DateTime Function() clock,
  }) : _expected = Set.of(expectedAckers),
       _clock = clock;

  /// Device that will become host if this handoff completes.
  final String newHostId;

  /// How long to wait for all acks before taking over unilaterally.
  final Duration ackTimeout;

  final DateTime Function() _clock;
  final Set<String> _expected;
  final Set<String> _acked = {};

  HandoffState _state = HandoffState.stable;
  DateTime? _intentAt;

  HandoffState get state => _state;

  /// Peers whose ack is still outstanding.
  Set<String> get pendingAckers => _expected.difference(_acked);

  /// Begin the handoff: announce intent and start the ack window. No-op (returns
  /// [HandoffAction.none]) if already in flight, so a repeated trigger is safe.
  HandoffStep begin() {
    if (_state != HandoffState.stable) {
      return HandoffStep(_state, HandoffAction.none);
    }
    // No peers to wait on (solo, or bootstrap): switch straight away.
    if (_expected.isEmpty) {
      _state = HandoffState.switching;
      return const HandoffStep(
        HandoffState.switching,
        HandoffAction.performSwitch,
      );
    }
    _state = HandoffState.awaitingAcks;
    _intentAt = _clock();
    return const HandoffStep(
      HandoffState.awaitingAcks,
      HandoffAction.broadcastIntent,
    );
  }

  /// Record an ack from [peerId]. When the last expected ack lands, advance to
  /// the switch. Acks from unexpected peers or after the window are ignored.
  HandoffStep onAck(String peerId) {
    if (_state != HandoffState.awaitingAcks) {
      return HandoffStep(_state, HandoffAction.none);
    }
    if (_expected.contains(peerId)) _acked.add(peerId);
    if (pendingAckers.isEmpty) {
      _state = HandoffState.switching;
      return const HandoffStep(
        HandoffState.switching,
        HandoffAction.performSwitch,
      );
    }
    return const HandoffStep(HandoffState.awaitingAcks, HandoffAction.none);
  }

  /// Call each tick. If the ack window has elapsed while still awaiting acks,
  /// take over unilaterally (ADR-003: a degraded single host beats a stall).
  HandoffStep onTick() {
    if (_state != HandoffState.awaitingAcks) {
      return HandoffStep(_state, HandoffAction.none);
    }
    if (_clock().difference(_intentAt!) >= ackTimeout) {
      _state = HandoffState.switching;
      return const HandoffStep(
        HandoffState.switching,
        HandoffAction.performSwitch,
      );
    }
    return const HandoffStep(HandoffState.awaitingAcks, HandoffAction.none);
  }

  /// The daemon reports the AP swap done. Return to [HandoffState.stable].
  /// Ignored unless currently switching, so a stray call cannot desync state.
  HandoffStep onSwitchComplete() {
    if (_state != HandoffState.switching) {
      return HandoffStep(_state, HandoffAction.none);
    }
    _state = HandoffState.stable;
    return const HandoffStep(HandoffState.stable, HandoffAction.complete);
  }
}
