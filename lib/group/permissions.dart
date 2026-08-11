/// Runtime permission gating for host/join (ADR-002).
///
/// Android splits WiFi permissions by version: NEARBY_WIFI_DEVICES on 33+,
/// location on 32 and below. permission_handler maps both; request the pair and
/// let the OS ignore the one that does not apply.
library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Request the permissions needed before hosting or joining a hotspot.
/// Returns false only if a permission was permanently denied (needs Settings);
/// a permission not applicable to this OS version does not block.
Future<bool> ensureHotspotPermissions() async {
  if (!Platform.isAndroid) return true; // iOS joins via system Camera QR.

  final statuses = await [
    Permission.nearbyWifiDevices,
    Permission.locationWhenInUse,
  ].request();

  return statuses.values.every((s) => !s.isPermanentlyDenied);
}
