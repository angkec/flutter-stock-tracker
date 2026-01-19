# 增强股票显示功能设计

## 概述

为股票列表新增"当日涨跌幅"和"申万行业"两列，优化表格性能支持大数据量显示。

## 数据模型变更

### StockMonitorData 扩展

```dart
class StockMonitorData {
  final Stock stock;
  final double ratio;         // 涨跌量比
  final double changePercent; // 当日涨跌幅 (%)  ← 新增
  final String? industry;     // 申万行业        ← 新增
}
```

### 涨跌幅计算

从当日 K 线数据计算：`(最新价 - 昨收价) / 昨收价 * 100`
- 最新价 = 当日最后一根 K 线的 close
- 昨收价 = Stock.preClose

### 行业数据

- 数据来源：Tushare API（申万2021版一级行业分类）
- 存储方式：`assets/sw_industry.json`（5456 只股票，31 个行业）
- 加载方式：App 启动时加载到内存

## UI 变更

### 列布局

| 代码 | 名称 | 涨跌幅 | 量比 | 行业 |
|------|------|--------|------|------|
| 000001 | 平安银行 | +2.35% | 1.52 | 银行 |
| 600519 | 贵州茅台 | -0.82% | 0.87 | 食品饮料 |

### 列样式

- 代码：固定宽度，等宽字体，点击复制
- 名称：自适应，ST 股票橙色
- 涨跌幅：固定宽度，红涨绿跌，带 +/- 符号和 % 后缀
- 量比：固定宽度，红(≥1)绿(<1)
- 行业：自适应宽度，普通文本

### 窄屏处理

表格支持横向滚动，可左右滑动查看全部列。

## 性能优化

### 问题

DataTable + SingleChildScrollView 一次性构建所有行，5000+ 股票时性能差。

### 方案

改用 ListView.builder 虚拟化列表：
- 只构建可见区域的行
- 滚动时自动复用 Widget
- 内存占用恒定

### 实现结构

```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Column(
    children: [
      _buildHeader(),  // 固定表头
      Expanded(
        child: ListView.builder(  // 虚拟化数据行
          itemCount: stocks.length,
          itemBuilder: (context, index) => _buildRow(stocks[index]),
        ),
      ),
    ],
  ),
)
```

## 服务层变更

### 新增 IndustryService

```dart
class IndustryService {
  Map<String, String> _data = {};

  Future<void> load();              // 从 assets 加载 JSON
  String? getIndustry(String code); // 查询行业
}
```

### 数据流

```
App启动 → IndustryService.load()
        ↓
刷新数据 → StockService.batchGetMonitorData()
        ↓
        获取K线 → 计算量比 + 计算涨跌幅
        ↓
        查询行业 → 组装 StockMonitorData
        ↓
        返回给UI显示
```

## 文件变更

### 新增文件

| 文件 | 说明 |
|------|------|
| `assets/sw_industry.json` | 申万行业映射数据 |
| `lib/services/industry_service.dart` | 行业数据服务 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `pubspec.yaml` | 添加 assets 配置 |
| `lib/main.dart` | 注入 IndustryService |
| `lib/services/stock_service.dart` | StockMonitorData 增加字段，计算涨跌幅 |
| `lib/widgets/stock_table.dart` | 改用 ListView.builder，新增列 |
