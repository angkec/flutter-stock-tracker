import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

class SwIndustryIndexMappingService {
  SwIndustryIndexMappingService({required this.client, required this.store});

  final TushareClient client;
  final SwIndustryL1MappingStore store;

  Future<Map<String, String>> refreshFromTushare({String isNew = 'Y'}) async {
    final rows = await client.fetchSwIndustryMembers(isNew: isNew);
    final mapping = <String, String>{};

    for (final row in rows) {
      final industryName = row.l1Name.trim();
      final l1Code = row.l1Code.trim();
      if (industryName.isEmpty || l1Code.isEmpty) {
        continue;
      }
      mapping.putIfAbsent(industryName, () => l1Code);
    }

    await store.saveAll(mapping);
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
