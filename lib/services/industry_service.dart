// lib/services/industry_service.dart
import 'dart:convert';
import 'package:flutter/services.dart';

class IndustryService {
  Map<String, String> _data = {};

  /// 从 assets 加载行业数据
  Future<void> load() async {
    final jsonStr = await rootBundle.loadString('assets/sw_industry.json');
    final Map<String, dynamic> json = jsonDecode(jsonStr);
    _data = json.map((k, v) => MapEntry(k, v.toString()));
  }

  /// 根据股票代码获取行业
  String? getIndustry(String code) => _data[code];

  /// 获取所有唯一行业名称
  Set<String> get allIndustries => _data.values.toSet();

  /// 仅用于测试
  void setTestData(Map<String, String> data) {
    _data = data;
  }
}
