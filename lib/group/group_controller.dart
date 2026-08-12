/// Group lifecycle for the trip (ADR-002): create, join, restore, end.
///
/// Holds the active [GroupCredentials] and this device's [SessionRole], backed
/// by a [CredentialStore] so a relaunch mid-trip auto-restores the group
/// without re-scanning. Pure Dart, no native calls: the hotspot/session wiring
/// reads [credentials]/[role] and drives the bridge separately (UI layer).
library;

import 'package:flutter/foundation.dart';

import 'package:toice/audio/voice_session.dart';
import 'package:toice/group/credential_store.dart';
import 'package:toice/group/group_credentials.dart';

class GroupController extends ChangeNotifier {
  GroupController({CredentialStore? store})
    : _store = store ?? CredentialStore();

  final CredentialStore _store;

  GroupCredentials? _credentials;
  SessionRole? _role;

  GroupCredentials? get credentials => _credentials;
  SessionRole? get role => _role;
  bool get hasActiveTrip => _credentials != null;

  /// Create a new group: fresh fixed credentials, this device hosts.
  Future<GroupCredentials> create() async {
    final creds = GroupCredentials.generate();
    await _store.save(creds);
    _set(creds, SessionRole.host);
    return creds;
  }

  /// Join an existing group from scanned or entered credentials, as a client.
  Future<void> joinWith(GroupCredentials creds) async {
    await _store.save(creds);
    _set(creds, SessionRole.client);
  }

  /// Restore a persisted trip on launch (returns false if none). Role is
  /// unknown across a relaunch, so restore comes back as a client; election
  /// (ADR-003) promotes a device to host at runtime regardless.
  Future<bool> restore() async {
    final creds = await _store.load();
    if (creds == null) return false;
    _set(creds, SessionRole.client);
    return true;
  }

  /// End the trip: drop the persisted credentials and clear state.
  Future<void> endTrip() async {
    await _store.clear();
    _set(null, null);
  }

  void _set(GroupCredentials? creds, SessionRole? role) {
    _credentials = creds;
    _role = role;
    notifyListeners();
  }
}
