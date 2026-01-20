// lib/screens/market_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';
import 'package:stock_rtwatcher/widgets/market_stats_bar.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => MarketScreenState();
}

class MarketScreenState extends State<MarketScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StockMonitorData> _getFilteredData(List<StockMonitorData> allData) {
    if (_searchQuery.isEmpty) return allData;

    final query = _searchQuery.trim();
    final industryService = context.read<IndustryService>();

    // 如果是完整行业名，只按行业筛选
    if (industryService.allIndustries.contains(query)) {
      return allData.where((d) => d.industry == query).toList();
    }

    // 否则按代码/名称搜索
    final lowerQuery = query.toLowerCase();
    return allData
        .where((d) =>
            d.stock.code.contains(lowerQuery) ||
            d.stock.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// 按行业搜索（公开方法，供外部调用）
  void searchByIndustry(String industry) {
    _searchController.text = industry;
    setState(() => _searchQuery = industry);
  }

  void _addToWatchlist(String code, String name) {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();

    if (watchlistService.contains(code)) {
      watchlistService.removeStock(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从自选移除 $name ($code)')),
      );
    } else {
      watchlistService.addStock(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加到自选 $name ($code)')),
      );
    }
    // Sync watchlist codes to provider
    marketProvider.setWatchlistCodes(watchlistService.watchlist.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final filteredData = _getFilteredData(marketProvider.allData);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const StatusBar(),
                // 搜索框
                if (marketProvider.allData.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索代码、名称或行业',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 68),
                    child: RefreshIndicator(
                      onRefresh: () => marketProvider.refresh(),
                      child: StockTable(
                        stocks: filteredData,
                        isLoading: marketProvider.isLoading,
                        highlightCodes: watchlistService.watchlist.toSet(),
                        onLongPress: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                        onIndustryTap: searchByIndustry,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 底部统计条
            if (filteredData.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarketStatsBar(stocks: filteredData),
              ),
          ],
        ),
      ),
    );
  }
}
