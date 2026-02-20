import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';
import 'package:stock_rtwatcher/models/sw_industry_l1_member.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

typedef BundledMappingLoader = Future<Map<String, String>> Function();

class SwIndustryIndexMappingService {
  SwIndustryIndexMappingService({
    required this.client,
    required this.store,
    BundledMappingLoader? bundledMappingLoader,
  }) : _bundledMappingLoader = bundledMappingLoader;

  final TushareClient client;
  final SwIndustryL1MappingStore store;
  final BundledMappingLoader? _bundledMappingLoader;

  Future<Map<String, String>> seedFromBundledAssetIfEmpty() async {
    final existing = await store.loadAll();
    if (existing.isNotEmpty) {
      return existing;
    }

    final bundled = await loadBundledMapping();
    if (bundled.isNotEmpty) {
      await store.saveAll(bundled);
    }
    return bundled;
  }

  Future<Map<String, String>> loadBundledMapping() async {
    if (_bundledMappingLoader != null) {
      final loaded = await _bundledMappingLoader();
      return _sanitizeMapping(loaded);
    }

    try {
      final jsonStr = await rootBundle.loadString(
        'assets/sw_industry_l1_mapping.json',
      );
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map) {
        return const <String, String>{};
      }

      final mapping = <String, String>{};
      decoded.forEach((key, value) {
        mapping[key.toString()] = value?.toString() ?? '';
      });
      return _sanitizeMapping(mapping);
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<Map<String, String>> refreshFromTushare({String isNew = 'Y'}) async {
    try {
      var rows = await client.fetchSwIndustryMembers(isNew: isNew);
      var mapping = _buildMapping(rows);

      if (mapping.isEmpty && isNew.trim().toUpperCase() == 'Y') {
        rows = await client.fetchSwIndustryMembers(isNew: null);
        mapping = _buildMapping(rows);
      }

      if (mapping.isNotEmpty) {
        await store.saveAll(mapping);
        return mapping;
      }
    } catch (_) {
      // Fall through to local/bundled fallback.
    }

    final local = await store.loadAll();
    if (local.isNotEmpty) {
      return _sanitizeMapping(local);
    }

    final bundled = await seedFromBundledAssetIfEmpty();
    if (bundled.isNotEmpty) {
      return bundled;
    }

    throw StateError('未获取到申万一级行业映射，请检查 Tushare Token 权限后重试');
  }

  Map<String, String> _buildMapping(List<SwIndustryL1Member> rows) {
    final mapping = <String, String>{};
    for (final row in rows) {
      final industryName = row.l1Name.trim();
      final l1Code = row.l1Code.trim();
      if (industryName.isEmpty || l1Code.isEmpty) {
        continue;
      }
      mapping.putIfAbsent(industryName, () => l1Code);
    }

    return mapping;
  }

  Map<String, String> _sanitizeMapping(Map<String, String> source) {
    final cleaned = <String, String>{};
    for (final entry in source.entries) {
      final industryName = entry.key.trim();
      final l1Code = entry.value.trim();
      if (industryName.isEmpty || l1Code.isEmpty) {
        continue;
      }
      cleaned[industryName] = l1Code;
    }
    return cleaned;
  }

  Future<String?> resolveTsCodeByIndustry(String industry) async {
    final industryName = industry.trim();
    if (industryName.isEmpty) {
      return null;
    }

    final mapping = await seedFromBundledAssetIfEmpty();
    return mapping[industryName];
  }

  Future<List<String>> loadAllTsCodes() async {
    final mapping = await seedFromBundledAssetIfEmpty();
    final codes =
        mapping.values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return codes;
  }
}
