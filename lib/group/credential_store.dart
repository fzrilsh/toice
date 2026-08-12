/// Trip-lifetime persistence for the group credentials (ADR-002).
///
/// The credentials generated at bootstrap are reused for every host handoff, so
/// each device must persist them for the life of the trip and clear them at
/// teardown. One JSON blob under one key; no schema, no migration (the whole
/// value is discarded on [clear]).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:toice/group/group_credentials.dart';

class CredentialStore {
  static const _key = 'toice.group_credentials';

  /// Persist the active group credentials, replacing any previous set.
  Future<void> save(GroupCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(creds.toJson()));
  }

  /// The persisted credentials, or null if none saved (or the blob is corrupt).
  Future<GroupCredentials?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return GroupCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Corrupt/partial blob (bad JSON, missing or wrong-typed keys): treat as
      // no trip rather than crash on launch.
      return null;
    }
  }

  /// Drop the credentials (trip end / explicit group teardown).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
