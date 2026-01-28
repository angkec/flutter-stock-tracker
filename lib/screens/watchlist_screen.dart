// lib/screens/watchlist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/widgets/ai_analysis_sheet.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

class WatchlistScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const WatchlistScreen({super.key, this.onIndustryTap});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始化时同步自选股代码到 MarketDataProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWatchlistCodes();
    });
  }

  void _syncWatchlistCodes() {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();
    marketProvider.setWatchlistCodes(watchlistService.watchlist.toSet());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _addStock() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final watchlistService = context.read<WatchlistService>();
    if (!WatchlistService.isValidCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的股票代码')),
      );
      return;
    }

    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该股票已在自选列表中')),
      );
      return;
    }

    watchlistService.addStock(code);
    _codeController.clear();
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 $code')),
    );
  }

  void _removeStock(String code) {
    final watchlistService = context.read<WatchlistService>();
    watchlistService.removeStock(code);
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 $code')),
    );
  }

  void _showAIAnalysis() {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();

    // 从 marketProvider 获取自选股的 Stock 对象
    final stocks = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .map((d) => d.stock)
        .toList();

    if (stocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加自选股')),
      );
      return;
    }

    AIAnalysisSheet.show(context, stocks);
  }

  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 从共享数据中过滤自选股
    final watchlistData = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .toList();

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return SafeArea(
      child: Column(
        children: [
          const StatusBar(),
          // 添加股票输入框
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: '输入股票代码',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) => _addStock(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addStock,
                  child: const Text('添加'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.auto_awesome),
                  tooltip: 'AI 分析',
                  onPressed: _showAIAnalysis,
                ),
              ],
            ),
          ),
          // 自选股列表
          Expanded(
            child: watchlistData.isEmpty
                ? _buildEmptyState(watchlistService)
                : RefreshIndicator(
                    onRefresh: () => marketProvider.refresh(),
                    child: StockTable(
                      stocks: watchlistData,
                      isLoading: marketProvider.isLoading,
                      onLongPress: (data) => _removeStock(data.stock.code),
                      onIndustryTap: widget.onIndustryTap,
                      industryTrendData: trendService.trendData,
                      todayTrendData: todayTrend,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WatchlistService watchlistService) {
    if (watchlistService.watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无自选股',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '在上方输入股票代码添加',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.refresh,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '点击刷新按钮获取数据',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
  }
}
