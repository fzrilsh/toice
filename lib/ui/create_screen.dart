import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:toice/group/group_credentials.dart';
import 'package:toice/native_bridge/native_bridge.g.dart';
import 'package:toice/ui/call_screen.dart';

/// Host screen (ADR-002, Phase 4): the group is already created with fixed
/// credentials; this device hosts the hotspot and shows the QR every other
/// rider scans once. Absorbs the Phase 0 host PoC (native start/stop, manual
/// fallback) into the real create flow. [credentials] come from
/// `GroupController.create`. The call screen still runs the mock session; real
/// audio is Phase 6.
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key, required this.credentials, this.hotspot});

  final GroupCredentials credentials;

  /// Injected for tests; defaults to the real bridge.
  final HotspotApi? hotspot;

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> implements HotspotEvents {
  late final HotspotApi _hotspot = widget.hotspot ?? HotspotApi();
  final _log = <String>[];
  bool _manualRequired = false;

  @override
  void initState() {
    super.initState();
    HotspotEvents.setUp(this);
    _startHost();
  }

  void _append(String line) => setState(
    () => _log.insert(0, '${DateTime.now().toIso8601String()}  $line'),
  );

  Future<void> _startHost() async {
    try {
      final mode = await _hotspot.startHost(
        widget.credentials.toHotspotCredentials(),
      );
      _append('startHost -> ${mode.name}');
      setState(() => _manualRequired = mode == HostStartMode.manualRequired);
    } catch (e) {
      // Device-only bridge; absent in widget tests. Log, keep showing the QR.
      _append('startHost error: $e');
    }
  }

  void _openCall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          session: mockHostSession(),
          newSignaling: mockSignaling,
          speakerSource: mockSpeakerSource(),
        ),
      ),
    );
  }

  @override
  void onHostStopped(String reason) => _append('event onHostStopped: $reason');

  @override
  void onClientStateChanged(bool connected) =>
      _append('event onClientStateChanged: $connected');

  /// The Trip PIN, shown large (riders type it) plus a small PIN-only QR that
  /// Android clients can scan to auto-fill it. The PIN is the app-layer secret
  /// that gates the voice session (Phase 4.5); it is deliberately not in the
  /// WiFi QR (Option B).
  Widget _tripPinCard(BuildContext context, String pin) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Trip PIN', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Riders enter this after joining the WiFi.'),
          const SizedBox(height: 8),
          SelectableText(
            pin,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              letterSpacing: 8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          QrImageView(data: widget.credentials.pinQrPayload(), size: 120),
          const SizedBox(height: 4),
          Text(
            'Android riders can scan this to fill the PIN.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final creds = widget.credentials;
    return Scaffold(
      appBar: AppBar(title: const Text('Host group')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Have every rider scan this once before departure.'),
          const SizedBox(height: 12),
          Center(child: QrImageView(data: creds.toWifiQrPayload(), size: 220)),
          const SizedBox(height: 12),
          SelectableText(
            'SSID: ${creds.ssid}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SelectableText(
            'Password: ${creds.password}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _tripPinCard(context, creds.tripPin),
          if (_manualRequired) ...[
            const SizedBox(height: 12),
            const Text(
              'This device cannot start the hotspot automatically. Open '
              'Settings, create a hotspot with the SSID and password above, '
              'then have others scan the QR.',
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _hotspot.openTetherSettings(),
              child: const Text('Open hotspot settings'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _openCall, child: const Text('Start call')),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Log', style: Theme.of(context).textTheme.titleMedium),
            for (final line in _log)
              Text(line, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
