import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan: bawaan dari assets/gw/defaults.json (sama dengan ekstensi laptop),
/// ditimpa oleh pilihan pengguna yang disimpan di HP.
class Settings {
  Settings._(this.defaults, this.overrides);

  final Map<String, dynamic> defaults;
  final Map<String, dynamic> overrides;

  static const _key = 'gw_settings';

  static Future<Settings> load() async {
    final defaults = jsonDecode(await rootBundle.loadString('assets/gw/defaults.json')) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final overrides = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return Settings._(defaults, overrides);
  }

  dynamic operator [](String key) => overrides.containsKey(key) ? overrides[key] : defaults[key];

  void set(String key, dynamic value) {
    if (value == defaults[key]) {
      overrides.remove(key);
    } else {
      overrides[key] = value;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(overrides));
  }

  Future<void> reset() async {
    overrides.clear();
    await save();
  }

  /// Semua pengaturan (bawaan + pilihan pengguna) untuk disuntikkan ke halaman.
  Map<String, dynamic> get merged => {...defaults, ...overrides};
}
