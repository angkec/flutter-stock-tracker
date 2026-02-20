// lib/services/industry_service.dart
import 'dart:convert';
import 'package:flutter/services.dart';

class IndustryService {
  Map<String, String> _data = {};
  bool _isLoaded = false;

  // Industry -> stockCodes index for O(k) lookups
  Map<String, List<String>> _industryIndex = {};

  /// 是否已加载
  bool get isLoaded => _isLoaded;

  /// 从 assets 加载行业数据
  Future<void> load() async {
    final jsonStr = await rootBundle.loadString('assets/sw_industry.json');
    final Map<String, dynamic> json = jsonDecode(jsonStr);
    _data = json.map((k, v) => MapEntry(k, v.toString()));
    _isLoaded = true;
    _rebuildIndex();
  }

  /// 重建行业->股票索引
  void _rebuildIndex() {
    _industryIndex = {};
    for (final entry in _data.entries) {
      final industry = entry.value;
      _industryIndex.putIfAbsent(industry, () => []).add(entry.key);
    }
  }

  /// 根据股票代码获取行业
  String? getIndustry(String code) => _data[code];

  /// 获取所有唯一行业名称
  Set<String> get allIndustries => _data.values.toSet();

  /// 获取指定行业的所有股票代码
  List<String> getStocksByIndustry(String industry) {
    return List<String>.from(_industryIndex[industry] ?? []);
  }

  /// 仅用于测试
  void setTestData(Map<String, String> data) {
    _data = data;
    _rebuildIndex();
  }
}
