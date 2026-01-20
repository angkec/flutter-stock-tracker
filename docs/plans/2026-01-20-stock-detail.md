# Stock Detail Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现股票详情页，展示 K 线图（日线/周线切换）和 20 天量比历史列表。

**Architecture:** 点击 StockTable 行后 Navigator.push 推入 StockDetailScreen。页面上下布局：K 线图在上（CustomPaint 绘制），量比历史列表在下。数据通过 StockService 从 TDX 服务器获取。

**Tech Stack:** Flutter, CustomPaint, TDX Protocol

---

### Task 1: Create DailyRatio Model

**Files:**
- Create: `lib/models/daily_ratio.dart`

**Step 1: Create the model file**

```dart
/// 每日量比数据
class DailyRatio {
  final DateTime date;
  final double? ratio; // null 表示无法计算（涨停/跌停等）

  DailyRatio({
    required this.date,
    this.ratio,
  });
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/models/daily_ratio.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/models/daily_ratio.dart
git commit -m "feat: add DailyRatio model"
```

---

### Task 2: Add getKLines Method to StockService

**Files:**
- Modify: `lib/services/stock_service.dart`

**Step 1: Add getKLines method**

在 `StockService` class 末尾添加：

```dart
  /// 获取 K 线数据
  /// [stock] 股票
  /// [category] K线类型 (klineTypeDaily=4, klineTypeWeekly=5)
  /// [count] 获取数量
  Future<List<KLine>> getKLines({
    required Stock stock,
    required int category,
    int count = 30,
  }) async {
    final client = _pool._clients.first;
    return client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: category,
      start: 0,
      count: count,
    );
  }
```

**Step 2: Expose _clients in TdxPool**

修改 `lib/services/tdx_pool.dart`，添加 getter：

```dart
  /// 获取第一个可用的 client（供单个请求使用）
  TdxClient? get firstClient => _clients.isNotEmpty ? _clients.first : null;
```

**Step 3: Update getKLines to use firstClient**

更新 `lib/services/stock_service.dart` 中的 getKLines：

```dart
  Future<List<KLine>> getKLines({
    required Stock stock,
    required int category,
    int count = 30,
  }) async {
    final client = _pool.firstClient;
    if (client == null) throw StateError('Not connected');
    return client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: category,
      start: 0,
      count: count,
    );
  }
```

**Step 4: Run analyze**

Run: `flutter analyze lib/services/`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/services/tdx_pool.dart lib/services/stock_service.dart
git commit -m "feat: add getKLines method to StockService"
```

---

### Task 3: Add getRatioHistory Method to StockService

**Files:**
- Modify: `lib/services/stock_service.dart`

**Step 1: Add import for DailyRatio**

在文件顶部添加：

```dart
import 'package:stock_rtwatcher/models/daily_ratio.dart';
```

**Step 2: Add getRatioHistory method**

在 `StockService` class 末尾添加：

```dart
  /// 获取量比历史（最近 N 天）
  /// [stock] 股票
  /// [days] 天数（默认 20 天）
  Future<List<DailyRatio>> getRatioHistory({
    required Stock stock,
    int days = 20,
  }) async {
    final client = _pool.firstClient;
    if (client == null) throw StateError('Not connected');

    // 每天约 240 根分钟线，请求足够的数据
    // 分批请求，每次最多 800 根
    final allBars = <KLine>[];
    final totalBars = days * 240;
    var fetched = 0;

    while (fetched < totalBars) {
      final count = (totalBars - fetched).clamp(0, 800);
      final bars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineType1Min,
        start: fetched,
        count: count,
      );
      if (bars.isEmpty) break;
      allBars.addAll(bars);
      fetched += bars.length;
      if (bars.length < count) break; // 没有更多数据
    }

    // 按日期分组
    final Map<String, List<KLine>> grouped = {};
    for (final bar in allBars) {
      final dateKey = '${bar.datetime.year}-${bar.datetime.month.toString().padLeft(2, '0')}-${bar.datetime.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(bar);
    }

    // 计算每天的量比
    final results = <DailyRatio>[];
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); // 降序

    for (final dateKey in sortedKeys.take(days)) {
      final dayBars = grouped[dateKey]!;
      final ratio = calculateRatio(dayBars);
      final parts = dateKey.split('-');
      results.add(DailyRatio(
        date: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
        ratio: ratio,
      ));
    }

    return results;
  }
```

**Step 3: Run analyze**

Run: `flutter analyze lib/services/stock_service.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/services/stock_service.dart
git commit -m "feat: add getRatioHistory method to StockService"
```

---

### Task 4: Create KLineChart Widget

**Files:**
- Create: `lib/widgets/kline_chart.dart`

**Step 1: Create the widget file**

```dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// K 线图颜色
const Color kUpColor = Color(0xFFFF4444);   // 涨 - 红
const Color kDownColor = Color(0xFF00AA00); // 跌 - 绿

/// K 线图组件
class KLineChart extends StatelessWidget {
  final List<KLine> bars;
  final double height;

  const KLineChart({
    super.key,
    required this.bars,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('暂无数据')),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _KLinePainter(bars: bars),
          );
        },
      ),
    );
  }
}

class _KLinePainter extends CustomPainter {
  final List<KLine> bars;

  _KLinePainter({required this.bars});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    const double topPadding = 10;
    const double bottomPadding = 25; // 留空间给日期
    const double sidePadding = 5;

    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width - sidePadding * 2;

    // 计算价格范围
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    for (final bar in bars) {
      if (bar.low < minPrice) minPrice = bar.low;
      if (bar.high > maxPrice) maxPrice = bar.high;
    }

    // 上下留 5% 边距
    final priceRange = maxPrice - minPrice;
    final margin = priceRange * 0.05;
    minPrice -= margin;
    maxPrice += margin;
    final adjustedRange = maxPrice - minPrice;

    // K 线宽度
    final barWidth = chartWidth / bars.length * 0.8;
    final barSpacing = chartWidth / bars.length;

    // 绘制每根 K 线
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;

      // 价格转 Y 坐标（Y 轴反转）
      double priceToY(double price) {
        return topPadding + (1 - (price - minPrice) / adjustedRange) * chartHeight;
      }

      final openY = priceToY(bar.open);
      final closeY = priceToY(bar.close);
      final highY = priceToY(bar.high);
      final lowY = priceToY(bar.low);

      final color = bar.close >= bar.open ? kUpColor : kDownColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;

      // 绘制影线
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);

      // 绘制实体
      final bodyTop = openY < closeY ? openY : closeY;
      final bodyBottom = openY > closeY ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).clamp(1.0, double.infinity);

      if (bar.close >= bar.open) {
        // 阳线 - 空心或实心（这里用实心）
        paint.style = PaintingStyle.fill;
      } else {
        // 阴线 - 实心
        paint.style = PaintingStyle.fill;
      }

      canvas.drawRect(
        Rect.fromLTWH(x - barWidth / 2, bodyTop, barWidth, bodyHeight),
        paint,
      );
    }

    // 绘制底部日期（每隔几根显示一个）
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final interval = (bars.length / 5).ceil(); // 大约显示 5 个日期

    for (var i = 0; i < bars.length; i += interval) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;
      final dateStr = '${bar.datetime.month}/${bar.datetime.day}';

      textPainter.text = TextSpan(
        text: dateStr,
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KLinePainter oldDelegate) {
    return oldDelegate.bars != bars;
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/widgets/kline_chart.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/widgets/kline_chart.dart
git commit -m "feat: add KLineChart widget with CustomPaint"
```

---

### Task 5: Create RatioHistoryList Widget

**Files:**
- Create: `lib/widgets/ratio_history_list.dart`

**Step 1: Create the widget file**

```dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';

/// 量比颜色
const Color _upColor = Color(0xFFFF4444);   // ≥1 红
const Color _downColor = Color(0xFF00AA00); // <1 绿

/// 星期名称
const List<String> _weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 量比历史列表组件
class RatioHistoryList extends StatelessWidget {
  final List<DailyRatio> ratios;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const RatioHistoryList({
    super.key,
    required this.ratios,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      );
    }

    if (ratios.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无数据')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '量比历史',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...ratios.map((r) => _buildRow(context, r)),
      ],
    );
  }

  Widget _buildRow(BuildContext context, DailyRatio ratio) {
    final dateStr = '${ratio.date.month.toString().padLeft(2, '0')}-${ratio.date.day.toString().padLeft(2, '0')}';
    final weekday = _weekdays[ratio.date.weekday];
    final ratioStr = ratio.ratio != null ? ratio.ratio!.toStringAsFixed(2) : '-';
    final color = ratio.ratio != null
        ? (ratio.ratio! >= 1.0 ? _upColor : _downColor)
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$dateStr $weekday',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Text(
            ratioStr,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/widgets/ratio_history_list.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/widgets/ratio_history_list.dart
git commit -m "feat: add RatioHistoryList widget"
```

---

### Task 6: Create StockDetailScreen

**Files:**
- Create: `lib/screens/stock_detail_screen.dart`

**Step 1: Create the screen file**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/ratio_history_list.dart';

/// 股票详情页
class StockDetailScreen extends StatefulWidget {
  final Stock stock;

  const StockDetailScreen({super.key, required this.stock});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<KLine> _dailyBars = [];
  List<KLine> _weeklyBars = [];
  List<DailyRatio> _ratioHistory = [];

  bool _isLoadingKLine = true;
  bool _isLoadingRatio = true;
  String? _klineError;
  String? _ratioError;

  bool _showDaily = true; // true=日线, false=周线

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final stockService = context.read<StockService>();

    // 并行加载日线、周线、量比历史
    await Future.wait([
      _loadKLines(stockService),
      _loadRatioHistory(stockService),
    ]);
  }

  Future<void> _loadKLines(StockService stockService) async {
    setState(() {
      _isLoadingKLine = true;
      _klineError = null;
    });

    try {
      final daily = await stockService.getKLines(
        stock: widget.stock,
        category: klineTypeDaily,
        count: 30,
      );
      final weekly = await stockService.getKLines(
        stock: widget.stock,
        category: klineTypeWeekly,
        count: 30,
      );

      if (!mounted) return;
      setState(() {
        _dailyBars = daily;
        _weeklyBars = weekly;
        _isLoadingKLine = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _klineError = '加载 K 线失败: $e';
        _isLoadingKLine = false;
      });
    }
  }

  Future<void> _loadRatioHistory(StockService stockService) async {
    setState(() {
      _isLoadingRatio = true;
      _ratioError = null;
    });

    try {
      final history = await stockService.getRatioHistory(
        stock: widget.stock,
        days: 20,
      );

      if (!mounted) return;
      setState(() {
        _ratioHistory = history;
        _isLoadingRatio = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ratioError = '加载量比历史失败: $e';
        _isLoadingRatio = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stock.name} (${widget.stock.code})'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // K 线图区域
              _buildKLineSection(),
              const Divider(),
              // 量比历史区域
              RatioHistoryList(
                ratios: _ratioHistory,
                isLoading: _isLoadingRatio,
                errorMessage: _ratioError,
                onRetry: () => _loadRatioHistory(context.read<StockService>()),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKLineSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 切换按钮
          Row(
            children: [
              Text(
                'K 线图',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('日线')),
                  ButtonSegment(value: false, label: Text('周线')),
                ],
                selected: {_showDaily},
                onSelectionChanged: (selected) {
                  setState(() => _showDaily = selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // K 线图
          if (_isLoadingKLine)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_klineError != null)
            SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 8),
                    Text(_klineError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _loadKLines(context.read<StockService>()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            KLineChart(bars: _showDaily ? _dailyBars : _weeklyBars),
        ],
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/screens/stock_detail_screen.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/screens/stock_detail_screen.dart
git commit -m "feat: add StockDetailScreen"
```

---

### Task 7: Add Navigation from StockTable

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**Step 1: Add import**

在文件顶部添加：

```dart
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';
```

**Step 2: Add onDoubleTap parameter**

在 `StockTable` class 中添加参数：

```dart
  final void Function(StockMonitorData data)? onDoubleTap;
```

更新 constructor：

```dart
  const StockTable({
    super.key,
    required this.stocks,
    this.isLoading = false,
    this.highlightCodes = const {},
    this.onLongPress,
    this.onTap,
    this.onDoubleTap,
    this.onIndustryTap,
  });
```

**Step 3: Update _buildRow to handle double tap**

在 `_buildRow` 方法中，将 `GestureDetector` 修改为：

```dart
    return GestureDetector(
      onLongPress: onLongPress != null ? () => onLongPress!(data) : null,
      onTap: onTap != null ? () => onTap!(data) : null,
      onDoubleTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StockDetailScreen(stock: data.stock),
          ),
        );
      },
      child: Container(
```

**Step 4: Run analyze**

Run: `flutter analyze lib/widgets/stock_table.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/widgets/stock_table.dart
git commit -m "feat: add double-tap navigation to stock detail"
```

---

### Task 8: Manual Testing

**Step 1: Run the app**

Run: `flutter run -d macos`

**Step 2: Test the feature**

1. 点击刷新按钮加载数据
2. 双击任意股票行
3. 验证详情页显示：
   - AppBar 显示股票名称和代码
   - K 线图正常显示（日线）
   - 切换到周线，K 线图更新
   - 量比历史列表显示 20 天数据
4. 下拉刷新，数据重新加载
5. 返回列表页

**Step 3: Commit verification**

```bash
git commit --allow-empty -m "test: verified stock detail page feature"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Create DailyRatio model | `feat: add DailyRatio model` |
| 2 | Add getKLines to StockService | `feat: add getKLines method to StockService` |
| 3 | Add getRatioHistory to StockService | `feat: add getRatioHistory method to StockService` |
| 4 | Create KLineChart widget | `feat: add KLineChart widget with CustomPaint` |
| 5 | Create RatioHistoryList widget | `feat: add RatioHistoryList widget` |
| 6 | Create StockDetailScreen | `feat: add StockDetailScreen` |
| 7 | Add navigation from StockTable | `feat: add double-tap navigation to stock detail` |
| 8 | Manual testing | `test: verified stock detail page feature` |
