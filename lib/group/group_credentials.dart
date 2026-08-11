/// Group WiFi credential generation and QR payload encoding (ADR-002).
///
/// Fixed for the life of a trip: generated once at group creation, reused by
/// every subsequent host so devices auto-rejoin without re-pairing. This is the
/// generation primitive only; persistence and QR rendering live elsewhere.
library;

import 'dart:math';

import 'package:toice/native_bridge/native_bridge.g.dart';

/// Crockford base32 alphabet minus I/L/O/U: unambiguous when read aloud or
/// typed by hand for the Android manual-hotspot fallback (Task 4). Also free of
/// the `\ ; , : "` characters that the WIFI: QR format requires escaping, so
/// [GroupCredentials.toWifiQrPayload] needs no escaping.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

const _groupIdLength = 8; // SSID "Toice-XXXXXXXX" = 14 bytes, well under 32.
const _passwordLength = 16; // Valid WPA2 range is 8-63 chars.

/// Fixed group credentials plus the standard-format QR payload.
///
/// ponytail: no nonce field yet (ADR-002 mentions one for the QR). Add when QR
/// hardening lands in Phase 4; unused at Phase 0.
class GroupCredentials {
  const GroupCredentials({
    required this.ssid,
    required this.password,
    required this.groupId,
  });

  final String ssid;
  final String password;
  final String groupId;

  /// Generate fresh credentials from a cryptographic RNG.
  factory GroupCredentials.generate([Random? rng]) {
    final random = rng ?? Random.secure();
    final groupId = _randomString(random, _groupIdLength);
    return GroupCredentials(
      ssid: 'Toice-$groupId',
      password: _randomString(random, _passwordLength),
      groupId: groupId,
    );
  }

  /// Pigeon type crossing the native bridge (ADR-006).
  HotspotCredentials toHotspotCredentials() =>
      HotspotCredentials(ssid: ssid, password: password, groupId: groupId);

  /// Standard WiFi QR payload read natively by iOS 11+ / Android 9+ cameras
  /// (ADR-002 addendum). No escaping needed: [_alphabet] excludes the format's
  /// reserved characters.
  String toWifiQrPayload() => 'WIFI:S:$ssid;T:WPA;P:$password;;';
}

String _randomString(Random random, int length) => String.fromCharCodes(
  Iterable.generate(
    length,
    (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
  ),
);
