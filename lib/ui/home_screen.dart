import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:toice/audio/voice_session.dart';
import 'package:toice/group/group_credentials.dart';
import 'package:toice/group/permissions.dart';
import 'package:toice/native_bridge/native_bridge.g.dart';
import 'package:toice/ui/call_screen.dart';

/// Phase 0 PoC screen (ADR-002): host a fixed-credential hotspot or join one.
/// Not the final UI (that is Phase 4); this exists to validate the native
/// hotspot bridge on real devices.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> implements HotspotEvents {
  final _hotspot = HotspotApi();
  final _log = <String>[];
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  GroupCredentials? _hosting;
  bool _manualRequired = false;

  @override
  void initState() {
    super.initState();
    HotspotEvents.setUp(this);
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _append(String line) => setState(
    () => _log.insert(0, '${DateTime.now().toIso8601String()}  $line'),
  );

  Future<void> _host() async {
    if (!await ensureHotspotPermissions()) {
      _append('permissions denied');
      return;
    }
    final creds = GroupCredentials.generate();
    setState(() {
      _hosting = creds;
      _manualRequired = false;
    });
    try {
      final mode = await _hotspot.startHost(creds.toHotspotCredentials());
      _append('startHost -> ${mode.name} (ssid=${creds.ssid})');
      setState(() => _manualRequired = mode == HostStartMode.manualRequired);
    } catch (e) {
      _append('startHost error: $e');
    }
  }

  Future<void> _stopHost() async {
    try {
      await _hotspot.stopHost();
      _append('stopHost ok');
      setState(() {
        _hosting = null;
        _manualRequired = false;
      });
    } catch (e) {
      _append('stopHost error: $e');
    }
  }

  Future<void> _join() async {
    if (!await ensureHotspotPermissions()) {
      _append('permissions denied');
      return;
    }
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (ssid.isEmpty || pass.isEmpty) {
      _append('join: enter ssid and password');
      return;
    }
    try {
      await _hotspot.joinAsClient(
        HotspotCredentials(ssid: ssid, password: pass, groupId: ssid),
      );
      _append('joinAsClient requested (ssid=$ssid)');
    } catch (e) {
      _append('joinAsClient error: $e');
    }
  }

  Future<void> _leave() async {
    try {
      await _hotspot.leave();
      _append('leave ok');
    } catch (e) {
      _append('leave error: $e');
    }
  }

  /// Phase 1: open the call screen. The hotspot bridge (host/join above) forms
  /// the network; the call screen runs the WebRTC session over it. Wired to the
  /// mock session/signaling for now (ADR-004); swap for the device stack when
  /// validating audio on hardware.
  void _openCall(SessionRole role) {
    final session = role == SessionRole.host
        ? mockHostSession()
        : mockClientSession();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CallScreen(session: session, newSignaling: mockSignaling),
      ),
    );
  }

  // HotspotEvents (native -> Dart).
  @override
  void onHostStopped(String reason) => _append('event onHostStopped: $reason');

  @override
  void onClientStateChanged(bool connected) =>
      _append('event onClientStateChanged: $connected');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Toice - Phase 0 PoC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hostCard(),
          const SizedBox(height: 16),
          _joinCard(),
          const SizedBox(height: 16),
          _logCard(),
        ],
      ),
    );
  }

  Widget _hostCard() {
    final creds = _hosting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Host', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _host,
              child: const Text('Create group & host'),
            ),
            if (creds != null) ...[
              const SizedBox(height: 12),
              Center(
                child: QrImageView(data: creds.toWifiQrPayload(), size: 200),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'SSID: ${creds.ssid}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SelectableText(
                'Password: ${creds.password}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_manualRequired) ...[
                const SizedBox(height: 8),
                const Text(
                  'This device cannot set the hotspot automatically. Open '
                  'Settings and create a hotspot with the SSID and password '
                  'above, then have others scan the QR.',
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _hotspot.openTetherSettings(),
                  child: const Text('Open hotspot settings'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _openCall(SessionRole.host),
                child: const Text('Open call screen (host)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _stopHost,
                child: const Text('Stop hosting'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _ssidCtrl,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _join,
                    child: const Text('Join'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _leave, child: const Text('Leave')),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _openCall(SessionRole.client),
              child: const Text('Open call screen (client)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final line in _log)
              Text(line, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
