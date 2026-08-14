/// Local persistence for X3 profiles via `shared_preferences`.
///
/// The app auto-saves the current profile on every change and reloads it on
/// startup, so a user never loses their setup. Named profiles are stored as a
/// single JSON map so they survive across app launches too.
///
/// The mouse cannot report its own settings, so the profile that was last
/// successfully applied is stored separately as the source of truth; Apply
/// sends only what changed since that copy (everything the first time).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'x3_profile.dart';

class X3Prefs {
  static const _currentKey = 'x3.current_profile';
  static const _appliedKey = 'x3.applied_profile';
  static const _profilesKey = 'x3.named_profiles';

  /// Load the last-used profile, or the factory defaults if none saved.
  Future<X3Profile> loadCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentKey);
    if (raw == null) return X3Profile.defaults();
    return X3Profile.fromJsonString(raw) ?? X3Profile.defaults();
  }

  /// Persist the current profile (called on every change).
  Future<void> saveCurrent(X3Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey, jsonEncode(profile.toJson()));
  }

  /// Clear the saved current profile (used by "Reset to defaults").
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentKey);
  }

  /// Load the last successfully applied profile (what the mouse is believed
  /// to have), or null if the mouse has never been configured by this app.
  Future<X3Profile?> loadApplied() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_appliedKey);
    if (raw == null) return null;
    return X3Profile.fromJsonString(raw);
  }

  /// Record the profile that was successfully applied to the mouse.
  Future<void> saveApplied(X3Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appliedKey, jsonEncode(profile.toJson()));
  }

  Future<List<String>> profileNames() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readProfiles(prefs);
    return map.keys.toList()..sort();
  }

  Future<void> saveNamed(String name, X3Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readProfiles(prefs);
    map[name] = profile.toJson();
    await prefs.setString(_profilesKey, jsonEncode(map));
  }

  Future<X3Profile?> loadNamed(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _readProfiles(prefs)[name];
    if (data is! Map) return null;
    return X3Profile.fromJson(data.cast<String, dynamic>());
  }

  Future<void> deleteNamed(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readProfiles(prefs);
    map.remove(name);
    await prefs.setString(_profilesKey, jsonEncode(map));
  }

  Map<String, dynamic> _readProfiles(SharedPreferences prefs) {
    final raw = prefs.getString(_profilesKey);
    if (raw == null) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, dynamic>{};
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }
}
