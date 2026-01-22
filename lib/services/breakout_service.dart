import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// 放量突破检测服务
class BreakoutService extends ChangeNotifier {
  static const String _storageKey = 'breakout_config';

  BreakoutConfig _config = BreakoutConfig.defaults;

  /// 当前配置
  BreakoutConfig get config => _config;

  /// 从 SharedPreferences 加载配置
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = BreakoutConfig.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load breakout config: $e');
    }
  }

  /// 更新配置并保存
  Future<void> updateConfig(BreakoutConfig newConfig) async {
    _config = newConfig;
    notifyListeners();
    await _save();
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    _config = BreakoutConfig.defaults;
    notifyListeners();
    await _save();
  }

  /// 保存配置到 SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('Failed to save breakout config: $e');
    }
  }

  /// 检测是否符合放量突破后回踩
  /// [dailyBars] 需要最近N天日K数据（按时间升序，最早的在前）
  /// [minuteRatio] 今日分钟涨跌量比
  /// [todayChangePercent] 今日涨跌幅（用于过滤暴涨）
  /// 返回 true 表示符合条件
  bool isBreakoutPullback(List<KLine> dailyBars, double minuteRatio, [double? todayChangePercent]) {
    // 需要至少 5 + maxPullbackDays + 1 根K线
    // 5 for avg volume + max pullback days + breakout day
    final minBars = 5 + _config.maxPullbackDays + 1;
    if (dailyBars.length < minBars) {
      return false;
    }

    // 搜索突破日（从 bars.length - minPullbackDays - 1 到 bars.length - maxPullbackDays - 1）
    // 最后一根是今日，所以突破日索引范围：
    // 最近的突破日: bars.length - minPullbackDays - 1 (回踩天数最少)
    // 最远的突破日: bars.length - maxPullbackDays - 1 (回踩天数最多)
    final latestBreakoutIdx = dailyBars.length - _config.minPullbackDays - 1;
    final earliestBreakoutIdx = dailyBars.length - _config.maxPullbackDays - 1;

    for (int breakoutIdx = latestBreakoutIdx;
        breakoutIdx >= earliestBreakoutIdx;
        breakoutIdx--) {
      // 确保有足够的前5日数据计算均量
      if (breakoutIdx < 5) {
        continue;
      }

      final breakoutBar = dailyBars[breakoutIdx];

      // 1. 突破日必须是上涨日（close > open）
      if (!breakoutBar.isUp) {
        continue;
      }

      // 2. 计算前5日均量
      final prev5 = dailyBars.sublist(breakoutIdx - 5, breakoutIdx);
      final avg5Volume =
          prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;

      // 突破日成交量 > 前5日均量 × breakVolumeMultiplier
      if (breakoutBar.volume <= avg5Volume * _config.breakVolumeMultiplier) {
        continue;
      }

      // 3. 如果 maBreakDays > 0，检查收盘价 > N日均线
      if (_config.maBreakDays > 0) {
        if (breakoutIdx < _config.maBreakDays) {
          continue;
        }
        final maStart = breakoutIdx - _config.maBreakDays;
        final maBars = dailyBars.sublist(maStart, breakoutIdx);
        final ma = maBars.map((b) => b.close).reduce((a, b) => a + b) /
            _config.maBreakDays;
        if (breakoutBar.close <= ma) {
          continue;
        }
      }

      // 4. 如果 highBreakDays > 0，检查收盘价 > 前N日最高价
      if (_config.highBreakDays > 0) {
        if (breakoutIdx < _config.highBreakDays) {
          continue;
        }
        final highStart = breakoutIdx - _config.highBreakDays;
        final highBars = dailyBars.sublist(highStart, breakoutIdx);
        final maxHigh =
            highBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        if (breakoutBar.close <= maxHigh) {
          continue;
        }
      }

      // 5. 检查突破日质量（上引线/实体比例）
      if (_config.maxUpperShadowRatio > 0) {
        final bodyLength = (breakoutBar.close - breakoutBar.open).abs();
        final upperShadow = breakoutBar.high - breakoutBar.close;
        if (bodyLength > 0) {
          final ratio = upperShadow / bodyLength;
          if (ratio > _config.maxUpperShadowRatio) {
            continue;
          }
        }
      }

      // 6. 验证回踩期间（从突破日+1到今日）
      final pullbackBars = dailyBars.sublist(breakoutIdx + 1);
      final pullbackDays = pullbackBars.length;

      // 回踩天数必须在 [minPullbackDays, maxPullbackDays] 范围内
      if (pullbackDays < _config.minPullbackDays ||
          pullbackDays > _config.maxPullbackDays) {
        continue;
      }

      // 7. 计算总跌幅：今日收盘价相对参考价的跌幅
      final todayBar = dailyBars.last;
      final referencePrice = _config.dropReferencePoint == DropReferencePoint.breakoutClose
          ? breakoutBar.close
          : breakoutBar.high;
      final totalDrop = (referencePrice - todayBar.close) / referencePrice;
      if (totalDrop > _config.maxTotalDrop) {
        continue;
      }

      // 8. 平均量比：回踩期间平均成交量 / 突破日成交量 <= maxAvgVolumeRatio
      final avgPullbackVolume =
          pullbackBars.map((b) => b.volume).reduce((a, b) => a + b) /
              pullbackDays;
      final avgVolumeRatio = avgPullbackVolume / breakoutBar.volume;
      if (avgVolumeRatio > _config.maxAvgVolumeRatio) {
        continue;
      }

      // 9. 今日分钟量比 >= minMinuteRatio
      if (minuteRatio < _config.minMinuteRatio) {
        continue;
      }

      // 10. 过滤回踩后暴涨
      if (_config.filterSurgeAfterPullback && todayChangePercent != null) {
        if (todayChangePercent > _config.surgeThreshold) {
          continue;
        }
      }

      // 所有条件都满足
      return true;
    }

    // 没有找到符合条件的突破日
    return false;
  }

  /// 检测哪些K线是突破日（符合放量突破条件）
  /// 返回符合条件的K线索引列表
  Set<int> findBreakoutDays(List<KLine> dailyBars) {
    final breakoutIndices = <int>{};

    // 需要至少6根K线（5根算均量 + 1根突破日）
    if (dailyBars.length < 6) {
      return breakoutIndices;
    }

    for (int i = 5; i < dailyBars.length; i++) {
      final bar = dailyBars[i];

      // 1. 必须是上涨日（close > open）
      if (!bar.isUp) {
        continue;
      }

      // 2. 计算前5日均量
      final prev5 = dailyBars.sublist(i - 5, i);
      final avg5Volume = prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;

      // 成交量 > 前5日均量 × breakVolumeMultiplier
      if (bar.volume <= avg5Volume * _config.breakVolumeMultiplier) {
        continue;
      }

      // 3. 如果 maBreakDays > 0，检查收盘价 > N日均线
      if (_config.maBreakDays > 0) {
        if (i < _config.maBreakDays) {
          continue;
        }
        final maStart = i - _config.maBreakDays;
        final maBars = dailyBars.sublist(maStart, i);
        final ma = maBars.map((b) => b.close).reduce((a, b) => a + b) / _config.maBreakDays;
        if (bar.close <= ma) {
          continue;
        }
      }

      // 4. 如果 highBreakDays > 0，检查收盘价 > 前N日最高价
      if (_config.highBreakDays > 0) {
        if (i < _config.highBreakDays) {
          continue;
        }
        final highStart = i - _config.highBreakDays;
        final highBars = dailyBars.sublist(highStart, i);
        final maxHigh = highBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        if (bar.close <= maxHigh) {
          continue;
        }
      }

      // 5. 检查上引线/实体比例
      if (_config.maxUpperShadowRatio > 0) {
        final bodyLength = (bar.close - bar.open).abs();
        final upperShadow = bar.high - bar.close;
        if (bodyLength > 0) {
          final ratio = upperShadow / bodyLength;
          if (ratio > _config.maxUpperShadowRatio) {
            continue;
          }
        }
      }

      // 所有突破条件都满足
      breakoutIndices.add(i);
    }

    return breakoutIndices;
  }
}
