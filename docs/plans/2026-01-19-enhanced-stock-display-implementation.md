# 增强股票显示功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为股票列表新增"当日涨跌幅"和"申万行业"两列，并优化表格性能。

**Architecture:** IndustryService 从 assets 加载行业数据，StockService 计算涨跌幅并注入行业，StockTable 使用 ListView.builder 实现虚拟化列表。

**Tech Stack:** Flutter, Provider, JSON assets

---

## Task 1: 配置 assets

**Files:**
- Modify: `pubspec.yaml`

**Step 1: 添加 assets 配置**

在 `pubspec.yaml` 的 `flutter:` 部分添加：

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/
```

**Step 2: 验证配置正确**

Run: `flutter pub get`
Expected: 成功

**Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: configure assets folder in pubspec.yaml"
```

---

## Task 2: 创建 IndustryService

**Files:**
- Create: `lib/services/industry_service.dart`
- Test: `test/services/industry_service_test.dart`

**Step 1: 编写测试**

```dart
// test/services/industry_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

void main() {
  group('IndustryService', () {
    test('getIndustry returns correct industry for known code', () {
      final service = IndustryService();
      // 手动设置测试数据
      service.setTestData({'000001': '银行', '600519': '食品饮料'});

      expect(service.getIndustry('000001'), equals('银行'));
      expect(service.getIndustry('600519'), equals('食品饮料'));
    });

    test('getIndustry returns null for unknown code', () {
      final service = IndustryService();
      service.setTestData({'000001': '银行'});

      expect(service.getIndustry('999999'), isNull);
    });
  });
}
```

**Step 2: 运行测试验证失败**

Run: `flutter test test/services/industry_service_test.dart`
Expected: FAIL (文件不存在)

**Step 3: 实现 IndustryService**

```dart
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

  /// 仅用于测试
  void setTestData(Map<String, String> data) {
    _data = data;
  }
}
```

**Step 4: 运行测试验证通过**

Run: `flutter test test/services/industry_service_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/industry_service.dart test/services/industry_service_test.dart
git commit -m "feat: add IndustryService for Shenwan industry lookup"
```

---

## Task 3: 扩展 StockMonitorData

**Files:**
- Modify: `lib/services/stock_service.dart`

**Step 1: 更新 StockMonitorData 类**

修改 `lib/services/stock_service.dart` 中的 `StockMonitorData` 类：

```dart
/// 股票监控数据
class StockMonitorData {
  final Stock stock;
  final double ratio;          // 涨跌量比
  final double changePercent;  // 当日涨跌幅 (%)
  final String? industry;      // 申万行业

  StockMonitorData({
    required this.stock,
    required this.ratio,
    required this.changePercent,
    this.industry,
  });
}
```

**Step 2: 添加涨跌幅计算方法**

在 `StockService` 类中添加静态方法：

```dart
/// 计算涨跌幅
/// 返回 (最新价 - 昨收价) / 昨收价 * 100
static double? calculateChangePercent(List<KLine> todayBars, double preClose) {
  if (todayBars.isEmpty || preClose <= 0) return null;
  final lastClose = todayBars.last.close;
  return (lastClose - preClose) / preClose * 100;
}
```

**Step 3: 更新 batchGetMonitorData 方法签名**

添加 `IndustryService` 参数并更新 `processStockBars` 函数：

```dart
Future<List<StockMonitorData>> batchGetMonitorData(
  List<Stock> stocks, {
  IndustryService? industryService,
  void Function(int current, int total)? onProgress,
  void Function(List<StockMonitorData> results)? onData,
}) async {
```

**Step 4: 更新 processStockBars 内部处理**

在 `processStockBars` 函数中计算涨跌幅并查询行业：

```dart
void processStockBars(int index, List<KLine> bars) {
  completed++;
  onProgress?.call(completed, total);

  final todayBars = bars.where((bar) =>
      bar.datetime.year == today.year &&
      bar.datetime.month == today.month &&
      bar.datetime.day == today.day).toList();

  if (todayBars.isEmpty) return;

  final ratio = calculateRatio(todayBars);
  if (ratio == null) return;

  final changePercent = calculateChangePercent(todayBars, stocks[index].preClose);

  results.add(StockMonitorData(
    stock: stocks[index],
    ratio: ratio,
    changePercent: changePercent ?? 0.0,
    industry: industryService?.getIndustry(stocks[index].code),
  ));

  // ... 后续代码不变
}
```

**Step 5: 运行现有测试确保不破坏**

Run: `flutter test`
Expected: All tests passed

**Step 6: Commit**

```bash
git add lib/services/stock_service.dart
git commit -m "feat: add changePercent and industry to StockMonitorData"
```

---

## Task 4: 注入 IndustryService

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/market_screen.dart`
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: 更新 main.dart 添加 IndustryService Provider**

```dart
import 'package:stock_rtwatcher/services/industry_service.dart';

// 在 providers 列表中添加：
Provider(create: (_) {
  final service = IndustryService();
  service.load(); // 异步加载，不阻塞启动
  return service;
}),
```

**Step 2: 更新 market_screen.dart**

在 `_fetchMonitorData` 中获取并传递 IndustryService：

```dart
final industryService = context.read<IndustryService>();

await service.batchGetMonitorData(
  _allStocks,
  industryService: industryService,
  onProgress: ...,
  onData: ...,
);
```

**Step 3: 更新 watchlist_screen.dart**

同样在 `_fetchData` 中传递 IndustryService：

```dart
final industryService = context.read<IndustryService>();

final data = await stockService.batchGetMonitorData(
  stocks,
  industryService: industryService,
);
```

**Step 4: 运行验证**

Run: `flutter analyze`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/main.dart lib/screens/market_screen.dart lib/screens/watchlist_screen.dart
git commit -m "feat: inject IndustryService into screens"
```

---

## Task 5: 重构 StockTable 使用 ListView.builder

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**Step 1: 添加格式化涨跌幅的函数**

```dart
/// 格式化涨跌幅
String formatChangePercent(double percent) {
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}
```

**Step 2: 定义列宽常量**

```dart
// 列宽定义
const double _codeWidth = 80;
const double _nameWidth = 100;
const double _changeWidth = 80;
const double _ratioWidth = 70;
const double _industryWidth = 90;
const double _rowHeight = 48;
```

**Step 3: 提取表头构建方法**

```dart
Widget _buildHeader(BuildContext context) {
  return Container(
    height: _rowHeight,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Row(
      children: [
        _buildHeaderCell('代码', _codeWidth),
        _buildHeaderCell('名称', _nameWidth),
        _buildHeaderCell('涨跌幅', _changeWidth),
        _buildHeaderCell('量比', _ratioWidth),
        _buildHeaderCell('行业', _industryWidth),
      ],
    ),
  );
}

Widget _buildHeaderCell(String text, double width) {
  return SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );
}
```

**Step 4: 提取数据行构建方法**

```dart
Widget _buildRow(BuildContext context, StockMonitorData data, int index) {
  final ratioColor = data.ratio >= 1 ? upColor : downColor;
  final changeColor = data.changePercent >= 0 ? upColor : downColor;
  final isHighlighted = highlightCodes.contains(data.stock.code);

  return Container(
    height: _rowHeight,
    color: isHighlighted
        ? Colors.amber.withValues(alpha: 0.15)
        : (index.isOdd
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : null),
    child: Row(
      children: [
        // 代码列 (可点击复制)
        GestureDetector(
          onTap: () => _copyToClipboard(context, data.stock.code, data.stock.name),
          child: SizedBox(
            width: _codeWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(data.stock.code, style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        // 名称列
        SizedBox(
          width: _nameWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              data.stock.name,
              style: TextStyle(color: data.stock.isST ? Colors.orange : null),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // 涨跌幅列
        SizedBox(
          width: _changeWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatChangePercent(data.changePercent),
              style: TextStyle(
                color: changeColor,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        // 量比列
        SizedBox(
          width: _ratioWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatRatio(data.ratio),
              style: TextStyle(
                color: ratioColor,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        // 行业列
        SizedBox(
          width: _industryWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              data.industry ?? '-',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),
  );
}
```

**Step 5: 重写 build 方法**

```dart
@override
Widget build(BuildContext context) {
  if (stocks.isEmpty && !isLoading) {
    // ... 空状态代码保持不变
  }

  final totalWidth = _codeWidth + _nameWidth + _changeWidth + _ratioWidth + _industryWidth;

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: totalWidth,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.builder(
              itemCount: stocks.length,
              itemExtent: _rowHeight,
              itemBuilder: (context, index) => _buildRow(context, stocks[index], index),
            ),
          ),
        ],
      ),
    ),
  );
}
```

**Step 6: 运行 flutter analyze**

Run: `flutter analyze lib/widgets/stock_table.dart`
Expected: No issues found

**Step 7: Commit**

```bash
git add lib/widgets/stock_table.dart
git commit -m "feat: refactor StockTable with ListView.builder and new columns"
```

---

## Task 6: 最终测试和清理

**Step 1: 运行全部测试**

Run: `flutter test`
Expected: All tests passed

**Step 2: 运行 flutter analyze**

Run: `flutter analyze`
Expected: No issues found

**Step 3: 最终 Commit**

```bash
git add -A
git commit -m "feat: complete enhanced stock display with industry and change percent"
```
