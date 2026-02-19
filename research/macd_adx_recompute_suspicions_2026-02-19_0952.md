# MACD/ADX 设置页重算未生效的可能原因（猜测）

## 背景
怀疑设置页的 MACD/ADX“重算”未真正发生，显示结果一直来自“日K强制拉取后”的预热缓存。

## 可能原因与依据（从高到低）

1. **MACD 设置页重算并非强制重算**
   - `MacdSettingsScreen._recompute` 传入 `forceRecompute: false`。
   - 若缓存签名（sourceSignature）与配置一致，会直接复用缓存。
   - 强制拉取日K后已预热，设置页重算可能只是复用旧缓存。
   - 相关文件：`lib/screens/macd_settings_screen.dart`、`lib/services/macd_indicator_service.dart`

2. **参数修改未保存导致重算仍使用旧配置**
   - 设置页重算不会读取 UI 当前输入值，重算使用的是已保存配置。
   - 若只修改参数未点击保存，重算实际上还是旧配置，结果看起来“不变”。
   - 相关文件：`lib/screens/macd_settings_screen.dart`、`lib/screens/adx_settings_screen.dart`

3. **重算时拉取的日K为空，未覆盖旧缓存**
   - `prewarmFromRepository` 使用 `DateRange(now - 400 days, now)`。
   - 若 `DataRepository.getKlines` 返回空列表，`getOrComputeFromBars` 会返回空并不写入新缓存，旧缓存仍存在。
   - 相关文件：`lib/services/macd_indicator_service.dart`、`lib/services/adx_indicator_service.dart`、`lib/data/repository/market_data_repository.dart`

4. **重算发生但详情页未刷新读取新缓存**
   - `MacdSubChart/AdxSubChart` 仅在 `initState/didUpdateWidget` 时加载缓存。
   - 设置页重算完成后若详情页未触发重建，仍显示旧内存/旧文件数据。
   - 相关文件：`lib/widgets/macd_subchart.dart`、`lib/widgets/adx_subchart.dart`

5. **ADX 重算发生但输入数据一致导致结果相同**
   - ADX 设置页重算是 `forceRecompute: true`，会重算并覆盖。
   - 若与强制拉取日K后的输入数据完全一致，结果数值相同，看起来“没变”。
   - 相关文件：`lib/screens/adx_settings_screen.dart`、`lib/services/adx_indicator_service.dart`

## 初步验证方向
- 观察重算前后缓存文件更新时间是否变化。
- 在设置页重算前明确点击“保存”，再重算并比较。
- 打开日志或加临时日志，确认 `prewarmFromRepository` 是否真正执行并写盘。
