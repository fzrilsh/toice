import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:toice/group/group_credentials.dart';

/// Join-a-group screen (ADR-002 addendum, Phase 4).
///
/// Android has no built-in scan-to-join, so the app scans the host's standard
/// `WIFI:` QR in-app (mobile_scanner) and pops the parsed [GroupCredentials].
/// iOS joins with the system Camera (zero entitlement), so there is no in-app
/// camera here; iOS gets manual SSID/password entry as the in-app fallback for
/// when the rider has the text but not the code. [platformIsAndroid] is injected
/// so the branch is widget-testable without a real platform or camera.
class ScanScreen extends StatelessWidget {
  ScanScreen({super.key, bool? platformIsAndroid})
    : platformIsAndroid = platformIsAndroid ?? Platform.isAndroid;

  final bool platformIsAndroid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join group')),
      body: platformIsAndroid
          ? _AndroidScanner()
          : const _ManualEntry(
              hint:
                  'On iOS, point the built-in Camera app at the group QR to '
                  'join. Or enter the SSID and password by hand below.',
            ),
    );
  }
}

class _AndroidScanner extends StatefulWidget {
  @override
  State<_AndroidScanner> createState() => _AndroidScannerState();
}

class _AndroidScannerState extends State<_AndroidScanner> {
  final _controller = MobileScannerController();
  bool _handled = false; // Ignore duplicate frames after the first valid scan.

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final creds = GroupCredentials.fromWifiQrPayload(raw);
        _handled = true;
        Navigator.of(context).pop(creds);
        return;
      } on FormatException {
        // Not a Toice QR: keep scanning, don't pop.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(controller: _controller, onDetect: _onDetect),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Point the camera at the group QR code.'),
        ),
        const Divider(height: 1),
        const Expanded(
          child: _ManualEntry(hint: 'Or enter the SSID and password by hand.'),
        ),
      ],
    );
  }
}

/// Manual SSID/password entry: the iOS in-app fallback and the Android
/// no-scan path. Pops the entered [GroupCredentials] (tripPin empty, same as a
/// scanned join) or does nothing on invalid input.
class _ManualEntry extends StatefulWidget {
  const _ManualEntry({required this.hint});

  final String hint;

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    try {
      final creds = GroupCredentials.fromWifiQrPayload(
        'WIFI:S:$ssid;T:WPA;P:$pass;;',
      );
      Navigator.of(context).pop(creds);
    } on FormatException {
      setState(
        () => _error = 'Enter a valid Toice SSID (Toice-...) and password.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.hint),
          const SizedBox(height: 8),
          TextField(
            controller: _ssidCtrl,
            decoration: const InputDecoration(labelText: 'SSID'),
          ),
          TextField(
            controller: _passCtrl,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          FilledButton(onPressed: _submit, child: const Text('Join')),
        ],
      ),
    );
  }
}
