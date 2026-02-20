import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';
import 'package:stock_rtwatcher/models/sw_industry_l1_member.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

class SwIndustryIndexMappingService {
  SwIndustryIndexMappingService({required this.client, required this.store});

  final TushareClient client;
  final SwIndustryL1MappingStore store;

  Future<Map<String, String>> refreshFromTushare({String isNew = 'Y'}) async {
    var rows = await client.fetchSwIndustryMembers(isNew: isNew);
    var mapping = _buildMapping(rows);

    if (mapping.isEmpty && isNew.trim().toUpperCase() == 'Y') {
      rows = await client.fetchSwIndustryMembers(isNew: null);
      mapping = _buildMapping(rows);
    }

    if (mapping.isEmpty) {
      throw StateError('未获取到申万一级行业映射，请检查 Tushare Token 权限后重试');
    }

    await store.saveAll(mapping);
    return mapping;
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

  Future<String?> resolveTsCodeByIndustry(String industry) async {
    final industryName = industry.trim();
    if (industryName.isEmpty) {
      return null;
    }

    final mapping = await store.loadAll();
    return mapping[industryName];
  }
}
