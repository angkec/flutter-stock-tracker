# StockTable 表头排序功能设计

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 StockTable 添加通用的表头排序功能，所有使用该组件的页面自动获得排序能力。

**Architecture:** StockTable 从 StatelessWidget 改为 StatefulWidget，内部管理排序状态。点击表头切换排序，首次点击默认降序。当前排序列的表头文字变成主题色 + 显示箭头。

**Tech Stack:** Flutter, Dart

---

## 概述

**核心变更：**
- `StockTable` 从 `StatelessWidget` 改为 `StatefulWidget`
- 内部管理排序状态（排序列、排序方向）
- 点击表头切换排序，首次点击默认降序
- 当前排序列的表头文字变成主题色 + 显示 ▲/▼ 箭头

**影响的页面（自动生效）：**
- 自选列表 (watchlist_screen)
- 多日回踩 (breakout_screen)
- 行业详情 (industry_detail_screen)
- 单日回踩 (pullback_screen)
- 全市场 (market_screen)

---

## 数据结构

**排序列枚举：**
```dart
enum SortColumn {
  code,        // 代码
  name,        // 名称
  change,      // 涨跌幅
  ratio,       // 量比
  industry,    // 行业
}
```

**排序状态：**
```dart
SortColumn? _sortColumn;      // null 表示默认排序
bool _ascending = false;      // false = 降序（首次点击）
```

---

## 排序逻辑

**排序行为：**
- 点击未选中的列 → 该列降序排序
- 点击已选中的列 → 切换升序/降序
- 不提供"取消排序"（二态切换）

**各列排序规则：**

| 列 | 排序字段 | 降序含义 |
|---|---|---|
| 代码 | `stock.code` | Z→A（字母序反向）|
| 名称 | `stock.name` | 拼音序反向 |
| 涨跌幅 | `changePercent` | 涨幅最高在前 |
| 量比 | `ratio` | 量比最高在前 |
| 行业 | `industry` | 字母序反向 |

**排序实现：**
```dart
List<StockMonitorData> _sortStocks(List<StockMonitorData> stocks) {
  if (_sortColumn == null) return stocks;

  final sorted = [...stocks];
  sorted.sort((a, b) {
    int result;
    switch (_sortColumn!) {
      case SortColumn.code:
        result = a.stock.code.compareTo(b.stock.code);
      case SortColumn.name:
        result = a.stock.name.compareTo(b.stock.name);
      case SortColumn.change:
        result = a.changePercent.compareTo(b.changePercent);
      case SortColumn.ratio:
        result = a.ratio.compareTo(b.ratio);
      case SortColumn.industry:
        result = (a.industry ?? '').compareTo(b.industry ?? '');
    }
    return _ascending ? result : -result;
  });
  return sorted;
}
```

---

## 表头 UI 变更

**表头单元格改造：**

将 `_buildHeaderCell` 改为可点击的交互组件：

```dart
Widget _buildHeaderCell(
  String text,
  double width,
  SortColumn column, {
  bool numeric = false,
}) {
  final isActive = _sortColumn == column;
  final color = isActive
      ? Theme.of(context).colorScheme.primary
      : null;

  return GestureDetector(
    onTap: () => _onHeaderTap(column),
    child: SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Text(
                _ascending ? '▲' : '▼',
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
```

**点击处理：**
```dart
void _onHeaderTap(SortColumn column) {
  setState(() {
    if (_sortColumn == column) {
      _ascending = !_ascending;
    } else {
      _sortColumn = column;
      _ascending = false; // 首次点击降序
    }
  });
}
```

---

## 与现有功能的兼容

**优先显示突破回踩 (`prioritizeBreakout`) 的处理：**

当前逻辑会将突破回踩股票排在前面。排序功能启用后：
- 如果用户点击了排序 → 使用用户指定的排序，忽略 `prioritizeBreakout`
- 如果用户未点击排序 (`_sortColumn == null`) → 保持原有的 `prioritizeBreakout` 逻辑

```dart
List<StockMonitorData> _getDisplayStocks() {
  // 用户指定了排序，优先使用
  if (_sortColumn != null) {
    return _sortStocks(widget.stocks);
  }

  // 未排序时，保持原有的 prioritizeBreakout 逻辑
  if (widget.prioritizeBreakout && widget.stocks.any((s) => s.isBreakout)) {
    return [...widget.stocks]..sort((a, b) {
      if (a.isBreakout == b.isBreakout) return 0;
      return a.isBreakout ? -1 : 1;
    });
  }

  return widget.stocks;
}
```

**静态方法 `buildStandaloneHeader` 的处理：**

保留静态方法但不支持排序交互（仅显示用途），实际排序功能通过 `showHeader: true` 的内置表头实现。

---

## 文件变更汇总

**修改文件：**
- `lib/widgets/stock_table.dart`

**变更内容：**

1. 添加 `SortColumn` 枚举
2. `StockTable` 从 `StatelessWidget` 改为 `StatefulWidget`
3. 添加状态变量 `_sortColumn` 和 `_ascending`
4. 改造 `_buildHeaderCell` 为可点击组件，显示高亮和箭头
5. 添加 `_onHeaderTap` 处理点击切换
6. 添加 `_sortStocks` 排序逻辑
7. 修改 `build` 方法中的 `displayStocks` 获取逻辑

**无需修改的文件：**
- 所有调用方（`pullback_screen.dart`、`breakout_screen.dart` 等）无需任何修改

---

## 测试计划

- 手动测试各页面的排序功能
- 验证各列点击后排序正确
- 验证升序/降序切换
- 验证表头高亮和箭头显示
- 验证 `prioritizeBreakout` 在未排序时仍生效
