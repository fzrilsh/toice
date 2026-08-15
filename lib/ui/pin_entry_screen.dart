import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:toice/group/group_credentials.dart';

/// Trip PIN entry (Phase 4.5). Shown after the client has joined the WiFi but
/// before the voice session: the rider proves they know the host's PIN, which
/// gates the app-layer handshake (the PIN is deliberately not in the WiFi QR,
/// Option B). Pops the entered 4-6 digit PIN, or null if the rider backs out.
///
/// Android riders can scan the host's optional PIN-only QR to auto-fill; iOS
/// riders type it. [platformIsAndroid] is injected so the branch is testable.
class PinEntryScreen extends StatefulWidget {
  PinEntryScreen({super.key, bool? platformIsAndroid})
    : platformIsAndroid = platformIsAndroid ?? Platform.isAndroid;

  final bool platformIsAndroid;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _ctrl.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Enter the 4 to 6 digit Trip PIN from the host.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  Future<void> _scanPin() async {
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _PinScanner()));
    if (scanned != null) {
      _ctrl.text = scanned;
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Trip PIN')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ask the host for the Trip PIN shown on their screen.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(letterSpacing: 12),
              decoration: const InputDecoration(counterText: ''),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('Join call')),
            if (widget.platformIsAndroid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _scanPin,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan PIN QR instead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Android-only: scan the host's PIN-only QR (TOICE-PIN:...) and pop the digits.
class _PinScanner extends StatefulWidget {
  const _PinScanner();

  @override
  State<_PinScanner> createState() => _PinScannerState();
}

class _PinScannerState extends State<_PinScanner> {
  final _controller = MobileScannerController();
  bool _handled = false;

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
        final pin = GroupCredentials.pinFromQr(raw);
        _handled = true;
        Navigator.of(context).pop(pin);
        return;
      } on FormatException {
        // Not a Toice PIN QR: keep scanning.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan PIN QR')),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
