import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  @override
  State<IndustryScreen> createState() => _IndustryScreenState();
}

class _IndustryScreenState extends State<IndustryScreen> {
  List<IndustryStats> _stats = [];
  String? _updateTime;
  int _progress = 0;
  int _total = 0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// 计算行业统计
  Map<String, IndustryStats> _calculateStats(List<StockMonitorData> data) {
    final Map<String, List<StockMonitorData>> grouped = {};

    for (final stock in data) {
      final industry = stock.industry ?? '未知';
      grouped.putIfAbsent(industry, () => []).add(stock);
    }

    final result = <String, IndustryStats>{};
    for (final entry in grouped.entries) {
      int up = 0, down = 0, flat = 0, ratioAbove = 0, ratioBelow = 0;

      for (final stock in entry.value) {
        // 涨跌统计
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        // 量比统计
        if (stock.ratio >= 1.0) {
          ratioAbove++;
        } else {
          ratioBelow++;
        }
      }

      result[entry.key] = IndustryStats(
        name: entry.key,
        upCount: up,
        downCount: down,
        flatCount: flat,
        ratioAbove: ratioAbove,
        ratioBelow: ratioBelow,
      );
    }

    return result;
  }

  Future<void> _refresh() async {
    if (_isLoading) return;

    final pool = context.read<TdxPool>();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connected = await pool.ensureConnected();
      if (!mounted) return;

      if (!connected) {
        setState(() {
          _isLoading = false;
          _errorMessage = '无法连接到服务器';
        });
        return;
      }

      final stockService = context.read<StockService>();
      final industryService = context.read<IndustryService>();

      // 获取股票列表
      final stocks = await stockService.getAllStocks();
      if (!mounted) return;

      setState(() {
        _total = stocks.length;
      });

      // 获取监控数据
      final data = await stockService.batchGetMonitorData(
        stocks,
        industryService: industryService,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progress = current;
              _total = total;
            });
          }
        },
      );

      if (!mounted) return;

      // 计算行业统计
      final statsMap = _calculateStats(data);
      final statsList = statsMap.values.toList()
        ..sort((a, b) => b.ratioSortValue.compareTo(a.ratioSortValue));

      setState(() {
        _stats = statsList;
        _updateTime = _formatTime();
        _isLoading = false;
        _progress = 0;
        _total = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '获取数据失败: $e';
        _isLoading = false;
        _progress = 0;
        _total = 0;
      });
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StatusBar(
              updateTime: _updateTime,
              progress: _progress > 0 ? _progress : null,
              total: _total > 0 ? _total : null,
              isLoading: _isLoading,
              errorMessage: _errorMessage,
            ),
            Expanded(
              child: _stats.isEmpty && !_isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无数据',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击刷新按钮获取数据',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _stats.length,
                        itemExtent: 48,
                        itemBuilder: (context, index) =>
                            _buildRow(context, _stats[index], index),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _refresh,
        tooltip: '刷新数据',
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildRow(BuildContext context, IndustryStats stats, int index) {
    const upColor = Color(0xFFFF4444);
    const downColor = Color(0xFF00AA00);

    return GestureDetector(
      onTap: widget.onIndustryTap != null
          ? () => widget.onIndustryTap!(stats.name)
          : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: index.isOdd
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 行业名
            SizedBox(
              width: 80,
              child: Text(
                stats.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 涨跌进度条
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      if (stats.upCount > 0)
                        Expanded(
                          flex: stats.upCount,
                          child: Container(height: 8, color: upColor),
                        ),
                      if (stats.downCount > 0)
                        Expanded(
                          flex: stats.downCount,
                          child: Container(height: 8, color: downColor),
                        ),
                      if (stats.upCount == 0 && stats.downCount == 0)
                        Expanded(
                          child: Container(
                            height: 8,
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 涨跌数字
            SizedBox(
              width: 70,
              child: Text(
                '涨${stats.upCount} 跌${stats.downCount}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            // 量比数字
            SizedBox(
              width: 70,
              child: Text(
                '>1:${stats.ratioAbove} <1:${stats.ratioBelow}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
