// lib/screens/watchlist_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';
import 'package:stock_rtwatcher/services/ocr_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/screens/ai_settings_screen.dart';
import 'package:stock_rtwatcher/widgets/ai_analysis_sheet.dart';
import 'package:stock_rtwatcher/widgets/holdings_confirm_dialog.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

class WatchlistScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const WatchlistScreen({super.key, this.onIndustryTap});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 初始化时同步自选股代码到 MarketDataProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWatchlistCodes();
    });
  }

  void _syncWatchlistCodes() {
    final watchlistService = context.read<WatchlistService>();
    final holdingsService = context.read<HoldingsService>();
    final marketProvider = context.read<MarketDataProvider>();
    // 合并自选股和持仓代码
    final allCodes = <String>{
      ...watchlistService.watchlist,
      ...holdingsService.holdings,
    };
    marketProvider.setWatchlistCodes(allCodes);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _tabController.dispose();
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

  Future<void> _importFromScreenshot() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Recognize stock codes from image
      final imageFile = File(pickedFile.path);
      final recognizedCodes = await OcrService.recognizeStockCodes(imageFile);

      // Dismiss loading indicator
      if (!mounted) return;
      Navigator.of(context).pop();

      if (recognizedCodes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未识别到股票代码')),
        );
        return;
      }

      // Show confirmation dialog
      final confirmedCodes = await HoldingsConfirmDialog.show(
        context,
        recognizedCodes,
      );

      if (confirmedCodes != null && confirmedCodes.isNotEmpty) {
        // Save to holdings service
        final holdingsService = context.read<HoldingsService>();
        await holdingsService.setHoldings(confirmedCodes);
        _syncWatchlistCodes();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${confirmedCodes.length} 只股票')),
        );
      }
    } catch (e) {
      // Dismiss loading indicator if still showing
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const StatusBar(),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(key: ValueKey<String>('watchlist_tab'), text: '自选'),
              Tab(key: ValueKey<String>('holdings_tab'), text: '持仓'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWatchlistTab(),
                _buildHoldingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistTab() {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 从共享数据中过滤自选股
    final watchlistData = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .toList();

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return Column(
      children: [
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
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: '设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AISettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ),
        // 自选股列表
        Expanded(
          child: watchlistData.isEmpty
              ? _buildWatchlistEmptyState(watchlistService)
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
    );
  }

  Widget _buildHoldingsTab() {
    final holdingsService = context.watch<HoldingsService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 从共享数据中过滤持仓股
    final holdingsData = marketProvider.allData
        .where((d) => holdingsService.contains(d.stock.code))
        .toList();

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return Column(
      children: [
        // 导入按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _importFromScreenshot,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('从截图导入'),
                ),
              ),
            ],
          ),
        ),
        // 持仓列表
        Expanded(
          child: holdingsData.isEmpty
              ? _buildHoldingsEmptyState(holdingsService)
              : RefreshIndicator(
                  onRefresh: () => marketProvider.refresh(),
                  child: StockTable(
                    stocks: holdingsData,
                    isLoading: marketProvider.isLoading,
                    onIndustryTap: widget.onIndustryTap,
                    industryTrendData: trendService.trendData,
                    todayTrendData: todayTrend,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWatchlistEmptyState(WatchlistService watchlistService) {
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

  Widget _buildHoldingsEmptyState(HoldingsService holdingsService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无持仓',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '点击上方按钮从截图导入持仓',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
