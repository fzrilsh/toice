import 'package:flutter/material.dart';

import 'package:toice/group/group_controller.dart';
import 'package:toice/group/group_credentials.dart';
import 'package:toice/native_bridge/native_bridge.g.dart';
import 'package:toice/group/permissions.dart';
import 'package:toice/ui/call_screen.dart';
import 'package:toice/ui/create_screen.dart';
import 'package:toice/ui/scan_screen.dart';
import 'package:toice/ui/transitions.dart';

/// Landing screen (ADR-002, Phase 4): create a group (host) or join one
/// (client), replacing the Phase 0 PoC. A persisted trip auto-restores on
/// launch so a mid-ride relaunch rejoins without re-scanning.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller, this.hotspot});

  final GroupController? controller;

  /// Injected for tests; defaults to the real bridge.
  final HotspotApi? hotspot;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final GroupController _group = widget.controller ?? GroupController();
  late final HotspotApi _hotspot = widget.hotspot ?? HotspotApi();

  @override
  void initState() {
    super.initState();
    _group.restore();
  }

  @override
  void dispose() {
    // Only dispose a controller we created ourselves.
    if (widget.controller == null) _group.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!await ensureHotspotPermissions()) {
      _notify('WiFi permission is needed to host. Enable it in Settings.');
      return;
    }
    final creds = await _group.create();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(toiceRoute(CreateScreen(credentials: creds, hotspot: _hotspot)));
  }

  Future<void> _join() async {
    if (!await ensureHotspotPermissions()) {
      _notify('WiFi permission is needed to join. Enable it in Settings.');
      return;
    }
    if (!mounted) return;
    final creds = await Navigator.of(
      context,
    ).push<GroupCredentials>(toiceRoute(ScanScreen()));
    if (creds == null || !mounted) return;
    await _group.joinWith(creds);
    try {
      await _hotspot.joinAsClient(creds.toHotspotCredentials());
    } catch (_) {
      // Device-only bridge (or iOS, which joins via system Camera). The call
      // screen still opens over the mock session; surface it so a real join
      // failure isn't silent.
      _notify(
        'Could not join the WiFi network automatically. '
        'Join Toice-${creds.groupId} from WiFi settings, then continue.',
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      toiceRoute(
        CallScreen(
          session: mockClientSession(),
          newSignaling: mockSignaling,
          speakerSource: mockSpeakerSource(),
        ),
      ),
    );
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Toice')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedBuilder(
              animation: _group,
              builder: (context, _) => _group.hasActiveTrip
                  ? _activeTripBanner()
                  : _welcome(context),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create group'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _join,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Join group'),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty state: no active trip yet. Point the rider at the one next action
  /// instead of showing a bare pair of buttons.
  Widget _welcome(BuildContext context) => Column(
    children: [
      Icon(
        Icons.motorcycle,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'Ride connected',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      Text(
        'Create a group to host the intercom, or join one from the '
        'leader\'s QR code.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ],
  );

  Widget _activeTripBanner() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Active trip: ${_group.credentials!.ssid}'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await _group.endTrip();
              try {
                await _hotspot.leave();
              } catch (_) {}
            },
            child: const Text('End trip'),
          ),
        ],
      ),
    ),
  );
}
