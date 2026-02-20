# 个股详情主图 K 线逐根变色支持研究（2026-02-19）

## 目标

支持在个股详情主图中按“每根 K 线”应用指标驱动颜色，而不是仅使用现有涨跌红绿色。

## 现状链路（主图渲染路径）

1. 详情页构建主图：`lib/screens/stock_detail_screen.dart:881`
2. 主图容器转发到 K 线组件：`lib/widgets/kline_chart_with_subcharts.dart:91`
3. 真实蜡烛绘制在 Painter：`lib/widgets/kline_chart.dart:951`
4. 颜色决策逻辑在绘制循环中按涨跌判断：`lib/widgets/kline_chart.dart:1169`, `lib/widgets/kline_chart.dart:1184`

联动模式下，周/日主图分别在同一容器内独立渲染：

- `lib/widgets/linked_dual_kline_view.dart:180`
- `lib/widgets/linked_dual_kline_view.dart:222`

## 当前能力与限制

### 已有能力

- 可传入标记索引（突破、近似命中）做额外标注，不改变蜡烛底色：
  - `lib/widgets/kline_chart.dart:19`
  - `lib/widgets/kline_chart.dart:20`
- 可叠加 EMA 线，但不参与 K 线实体颜色决策：`lib/widgets/kline_chart.dart:1305`

### 关键限制

- `KLine` 模型未携带颜色字段：`lib/models/kline.dart:2`
- `KLineChart` 构造参数没有逐根颜色回调：`lib/widgets/kline_chart.dart:35`
- Painter 内部颜色由 `kUpColor/kDownColor` + 选中态分支硬编码：
  - 常量定义：`lib/widgets/kline_chart.dart:11`
  - 选中态分支：`lib/widgets/kline_chart.dart:1174`
  - 普通态分支：`lib/widgets/kline_chart.dart:1184`

## 推荐方案（低风险）

### 方案 A（推荐）：新增可选颜色解析回调

在 `KLineChart` 增加可选参数（示意）：

```dart
Color? Function(KLine bar, int globalIndex)? candleColorResolver
```

渲染优先级：

1. 若 resolver 返回颜色，使用该颜色（指标驱动逐根变色）
2. 否则回退到现有涨跌红绿逻辑（兼容旧行为）

推荐理由：

- 对现有调用点兼容（可选参数）
- 不改数据模型，不影响存储/同步层
- 修改集中在 UI 渲染链路，回归范围可控

### 方案 B：在 `KLine` 增加可选颜色字段

例如新增 `colorHex` 或颜色对象，再由 painter 优先读取。

优点：颜色语义进入数据层，天然可持久化。

缺点：

- 需要修改模型与序列化逻辑
- 影响面大于方案 A

## 联动与窗口映射注意点

- 图表存在窗口起点 `_startIndex`，需按全量索引或日期映射颜色，避免把“可见局部索引”误用于全量数据：`lib/widgets/kline_chart.dart:65`
- 联动模式下周/日图应分别提供对应 resolver，避免跨周期索引混用：
  - `lib/widgets/linked_dual_kline_view.dart:180`
  - `lib/widgets/linked_dual_kline_view.dart:222`

## 测试建议

1. 回归测试：不传 resolver 时，颜色行为与当前一致
2. 新增测试：传 resolver 时，指定 index 的蜡烛使用覆写颜色
3. 联动模式测试：周图与日图分别使用各自 resolver，不互相污染

## 结论

当前主图不具备逐根变色扩展点。优先采用“可选颜色解析回调（方案 A）”最稳妥，能够以最小改动支持指标驱动的每根 K 线变色，并保持现有页面与数据链路兼容。
