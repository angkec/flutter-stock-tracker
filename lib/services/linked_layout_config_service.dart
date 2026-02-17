import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';

class LinkedLayoutConfigService extends ChangeNotifier {
  static const String storageKey = 'linked_layout_config_v1';

  LinkedLayoutConfig _config = const LinkedLayoutConfig.balanced();

  LinkedLayoutConfig get config => _config;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _config = const LinkedLayoutConfig.balanced();
      } else {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _config = LinkedLayoutConfig.fromJson(decoded).normalize();
      }
    } catch (_) {
      _config = const LinkedLayoutConfig.balanced();
    }
    notifyListeners();
  }

  Future<void> update(LinkedLayoutConfig next) async {
    _config = next.normalize();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(_config.toJson()));
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _config = const LinkedLayoutConfig.balanced();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    notifyListeners();
  }
}
