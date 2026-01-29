import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

/// 放量突破检测服务
class BreakoutService extends ChangeNotifier {
  static const String _storageKey = 'breakout_config';

  BreakoutConfig _config = BreakoutConfig.defaults;

  HistoricalKlineService? _historicalKlineService;

  /// 设置历史K线服务（用于获取突破日分钟量比）
  void setHistoricalKlineService(HistoricalKlineService service) {
    _historicalKlineService = service;
  }

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

  /// 检测是否符合放量突破后回踩（纯日K结构检测，与 findBreakoutDays 逻辑一致）
  /// [dailyBars] 需要最近N天日K数据（按时间升序，最早的在前）
  /// 返回 true 表示符合条件
  Future<bool> isBreakoutPullback(List<KLine> dailyBars, {String? stockCode}) async {
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

      // 6. 检测突破日分钟量比
      if (_config.minBreakoutMinuteRatio > 0 &&
          stockCode != null &&
          _historicalKlineService != null) {
        final ratio = await _historicalKlineService!.getDailyRatio(
          stockCode,
          breakoutBar.datetime,
        );
        if (ratio == null || ratio < _config.minBreakoutMinuteRatio) {
          continue;
        }
      }

      // 7. 验证回踩（复用 _hasValidPullbackAfter 逻辑，与 findBreakoutDays 一致）
      if (!_hasValidPullbackAfter(dailyBars, breakoutIdx, breakoutBar)) {
        continue;
      }

      // 所有条件都满足
      return true;
    }

    // 没有找到符合条件的突破日
    return false;
  }

  /// 获取指定日期的突破检测详细结果
  /// [dailyBars] 日K数据（按时间升序）
  /// [index] 要检测的K线索引
  /// [stockCode] 股票代码（用于分钟量比检测）
  Future<BreakoutDetectionResult?> getDetectionResult(
    List<KLine> dailyBars,
    int index, {
    String? stockCode,
  }) async {
    // 需要至少6根K线（5根算均量 + 当前日）
    if (dailyBars.length < 6 || index < 5 || index >= dailyBars.length) {
      return null;
    }

    final bar = dailyBars[index];

    // 1. 上涨日检测
    final isUpDay = DetectionItem(
      name: '上涨日',
      passed: bar.isUp,
      detail: bar.isUp ? '收盘 > 开盘' : '收盘 ≤ 开盘',
    );

    // 2. 放量检测
    final prev5 = dailyBars.sublist(index - 5, index);
    final avg5Volume = prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;
    final volumeMultiple = bar.volume / avg5Volume;
    final volumeCheck = DetectionItem(
      name: '放量',
      passed: volumeMultiple > _config.breakVolumeMultiplier,
      detail: '${volumeMultiple.toStringAsFixed(2)}倍 (需>${_config.breakVolumeMultiplier})',
    );

    // 3. 均线突破检测
    DetectionItem? maBreakCheck;
    if (_config.maBreakDays > 0) {
      if (index >= _config.maBreakDays) {
        final maStart = index - _config.maBreakDays;
        final maBars = dailyBars.sublist(maStart, index);
        final ma = maBars.map((b) => b.close).reduce((a, b) => a + b) / _config.maBreakDays;
        maBreakCheck = DetectionItem(
          name: '突破${_config.maBreakDays}日均线',
          passed: bar.close > ma,
          detail: '收盘${bar.close.toStringAsFixed(2)} ${bar.close > ma ? ">" : "≤"} MA${ma.toStringAsFixed(2)}',
        );
      } else {
        maBreakCheck = DetectionItem(
          name: '突破${_config.maBreakDays}日均线',
          passed: false,
          detail: '数据不足',
        );
      }
    }

    // 4. 前高突破检测
    DetectionItem? highBreakCheck;
    if (_config.highBreakDays > 0) {
      if (index >= _config.highBreakDays) {
        final highStart = index - _config.highBreakDays;
        final highBars = dailyBars.sublist(highStart, index);
        final maxHigh = highBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        highBreakCheck = DetectionItem(
          name: '突破前${_config.highBreakDays}日高点',
          passed: bar.close > maxHigh,
          detail: '收盘${bar.close.toStringAsFixed(2)} ${bar.close > maxHigh ? ">" : "≤"} 高点${maxHigh.toStringAsFixed(2)}',
        );
      } else {
        highBreakCheck = DetectionItem(
          name: '突破前${_config.highBreakDays}日高点',
          passed: false,
          detail: '数据不足',
        );
      }
    }

    // 5. 上引线检测
    DetectionItem? upperShadowCheck;
    if (_config.maxUpperShadowRatio > 0) {
      final bodyLength = (bar.close - bar.open).abs();
      final upperShadow = bar.high - bar.close.clamp(bar.open, bar.high);
      final ratio = bodyLength > 0 ? upperShadow / bodyLength : 0.0;
      upperShadowCheck = DetectionItem(
        name: '上引线比例',
        passed: ratio <= _config.maxUpperShadowRatio,
        detail: '${ratio.toStringAsFixed(2)} (需≤${_config.maxUpperShadowRatio})',
      );
    }

    // 6. 分钟量比检测
    DetectionItem? minuteRatioCheck;
    if (_config.minBreakoutMinuteRatio > 0 &&
        stockCode != null &&
        _historicalKlineService != null) {
      final ratio = await _historicalKlineService!.getDailyRatio(
        stockCode,
        bar.datetime,
      );
      minuteRatioCheck = DetectionItem(
        name: '分钟量比',
        passed: ratio != null && ratio >= _config.minBreakoutMinuteRatio,
        detail: ratio != null
            ? '${ratio.toStringAsFixed(2)} (需≥${_config.minBreakoutMinuteRatio})'
            : '数据不足',
      );
    }

    // 7. 如果突破日条件通过，检测回踩
    PullbackDetectionResult? pullbackResult;
    final breakoutPassed = isUpDay.passed &&
        volumeCheck.passed &&
        (maBreakCheck?.passed ?? true) &&
        (highBreakCheck?.passed ?? true) &&
        (upperShadowCheck?.passed ?? true) &&
        (minuteRatioCheck?.passed ?? true);

    if (breakoutPassed) {
      pullbackResult = _getPullbackDetectionResult(dailyBars, index, bar);
    }

    return BreakoutDetectionResult(
      isUpDay: isUpDay,
      volumeCheck: volumeCheck,
      maBreakCheck: maBreakCheck,
      highBreakCheck: highBreakCheck,
      upperShadowCheck: upperShadowCheck,
      minuteRatioCheck: minuteRatioCheck,
      pullbackResult: pullbackResult,
    );
  }

  /// 获取回踩阶段的检测结果
  PullbackDetectionResult? _getPullbackDetectionResult(
      List<KLine> dailyBars, int breakoutIdx, KLine breakoutBar) {
    final referencePrice = _config.dropReferencePoint == DropReferencePoint.breakoutClose
        ? breakoutBar.close
        : breakoutBar.high;

    // 检查每个可能的回踩结束日
    for (int pullbackDays = _config.minPullbackDays;
        pullbackDays <= _config.maxPullbackDays;
        pullbackDays++) {
      final endIdx = breakoutIdx + pullbackDays;

      if (endIdx >= dailyBars.length) {
        break;
      }

      final pullbackBars = dailyBars.sublist(breakoutIdx + 1, endIdx + 1);
      final lastBar = pullbackBars.last;

      // 总跌幅
      final totalDrop = (referencePrice - lastBar.close) / referencePrice;
      final totalDropCheck = DetectionItem(
        name: '总跌幅',
        passed: totalDrop <= _config.maxTotalDrop,
        detail: '${(totalDrop * 100).toStringAsFixed(1)}% (需≤${(_config.maxTotalDrop * 100).toStringAsFixed(1)}%)',
      );

      // 单日跌幅
      DetectionItem? singleDayDropCheck;
      if (_config.maxSingleDayDrop > 0) {
        double maxDayDrop = 0;
        for (final bar in pullbackBars) {
          final dayDrop = (referencePrice - bar.close) / referencePrice;
          if (dayDrop > maxDayDrop) maxDayDrop = dayDrop;
        }
        singleDayDropCheck = DetectionItem(
          name: '单日最大跌幅',
          passed: maxDayDrop <= _config.maxSingleDayDrop,
          detail: '${(maxDayDrop * 100).toStringAsFixed(1)}% (需≤${(_config.maxSingleDayDrop * 100).toStringAsFixed(1)}%)',
        );
      }

      // 单日涨幅
      DetectionItem? singleDayGainCheck;
      if (_config.maxSingleDayGain > 0) {
        double maxDayGain = 0;
        for (final bar in pullbackBars) {
          final dayGain = (bar.close - referencePrice) / referencePrice;
          if (dayGain > maxDayGain) maxDayGain = dayGain;
        }
        singleDayGainCheck = DetectionItem(
          name: '单日最大涨幅',
          passed: maxDayGain <= _config.maxSingleDayGain,
          detail: '${(maxDayGain * 100).toStringAsFixed(1)}% (需≤${(_config.maxSingleDayGain * 100).toStringAsFixed(1)}%)',
        );
      }

      // 总涨幅
      DetectionItem? totalGainCheck;
      if (_config.maxTotalGain > 0) {
        final maxHigh = pullbackBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        final totalGain = (maxHigh - referencePrice) / referencePrice;
        totalGainCheck = DetectionItem(
          name: '总涨幅',
          passed: totalGain <= _config.maxTotalGain,
          detail: '${(totalGain * 100).toStringAsFixed(1)}% (需≤${(_config.maxTotalGain * 100).toStringAsFixed(1)}%)',
        );
      }

      // 平均量比
      final avgPullbackVolume =
          pullbackBars.map((b) => b.volume).reduce((a, b) => a + b) / pullbackDays;
      final avgVolumeRatio = avgPullbackVolume / breakoutBar.volume;
      final avgVolumeCheck = DetectionItem(
        name: '平均量比',
        passed: avgVolumeRatio <= _config.maxAvgVolumeRatio,
        detail: '${avgVolumeRatio.toStringAsFixed(2)} (需≤${_config.maxAvgVolumeRatio})',
      );

      // 检查是否全部通过
      final allPassed = totalDropCheck.passed &&
          (singleDayDropCheck?.passed ?? true) &&
          (singleDayGainCheck?.passed ?? true) &&
          (totalGainCheck?.passed ?? true) &&
          avgVolumeCheck.passed;

      if (allPassed) {
        return PullbackDetectionResult(
          pullbackDays: pullbackDays,
          totalDropCheck: totalDropCheck,
          singleDayDropCheck: singleDayDropCheck,
          singleDayGainCheck: singleDayGainCheck,
          totalGainCheck: totalGainCheck,
          avgVolumeCheck: avgVolumeCheck,
        );
      }
    }

    // 没有找到有效回踩，返回最后一次检测结果
    final lastPullbackDays = (_config.maxPullbackDays).clamp(
        _config.minPullbackDays,
        dailyBars.length - breakoutIdx - 1);
    if (lastPullbackDays < _config.minPullbackDays) {
      return null;
    }

    final endIdx = breakoutIdx + lastPullbackDays;
    final pullbackBars = dailyBars.sublist(breakoutIdx + 1, endIdx + 1);
    final lastBar = pullbackBars.last;

    final totalDrop = (referencePrice - lastBar.close) / referencePrice;
    final totalDropCheck = DetectionItem(
      name: '总跌幅',
      passed: totalDrop <= _config.maxTotalDrop,
      detail: '${(totalDrop * 100).toStringAsFixed(1)}% (需≤${(_config.maxTotalDrop * 100).toStringAsFixed(1)}%)',
    );

    DetectionItem? singleDayDropCheck;
    if (_config.maxSingleDayDrop > 0) {
      double maxDayDrop = 0;
      for (final bar in pullbackBars) {
        final dayDrop = (referencePrice - bar.close) / referencePrice;
        if (dayDrop > maxDayDrop) maxDayDrop = dayDrop;
      }
      singleDayDropCheck = DetectionItem(
        name: '单日最大跌幅',
        passed: maxDayDrop <= _config.maxSingleDayDrop,
        detail: '${(maxDayDrop * 100).toStringAsFixed(1)}% (需≤${(_config.maxSingleDayDrop * 100).toStringAsFixed(1)}%)',
      );
    }

    DetectionItem? singleDayGainCheck;
    if (_config.maxSingleDayGain > 0) {
      double maxDayGain = 0;
      for (final bar in pullbackBars) {
        final dayGain = (bar.close - referencePrice) / referencePrice;
        if (dayGain > maxDayGain) maxDayGain = dayGain;
      }
      singleDayGainCheck = DetectionItem(
        name: '单日最大涨幅',
        passed: maxDayGain <= _config.maxSingleDayGain,
        detail: '${(maxDayGain * 100).toStringAsFixed(1)}% (需≤${(_config.maxSingleDayGain * 100).toStringAsFixed(1)}%)',
      );
    }

    DetectionItem? totalGainCheck;
    if (_config.maxTotalGain > 0) {
      final maxHigh = pullbackBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
      final totalGain = (maxHigh - referencePrice) / referencePrice;
      totalGainCheck = DetectionItem(
        name: '总涨幅',
        passed: totalGain <= _config.maxTotalGain,
        detail: '${(totalGain * 100).toStringAsFixed(1)}% (需≤${(_config.maxTotalGain * 100).toStringAsFixed(1)}%)',
      );
    }

    final avgPullbackVolume =
        pullbackBars.map((b) => b.volume).reduce((a, b) => a + b) / lastPullbackDays;
    final avgVolumeRatio = avgPullbackVolume / breakoutBar.volume;
    final avgVolumeCheck = DetectionItem(
      name: '平均量比',
      passed: avgVolumeRatio <= _config.maxAvgVolumeRatio,
      detail: '${avgVolumeRatio.toStringAsFixed(2)} (需≤${_config.maxAvgVolumeRatio})',
    );

    return PullbackDetectionResult(
      pullbackDays: lastPullbackDays,
      totalDropCheck: totalDropCheck,
      singleDayDropCheck: singleDayDropCheck,
      singleDayGainCheck: singleDayGainCheck,
      totalGainCheck: totalGainCheck,
      avgVolumeCheck: avgVolumeCheck,
    );
  }

  /// 检测哪些K线是突破日（符合放量突破条件，且后续有有效回踩）
  /// 返回符合条件的K线索引列表
  Future<Set<int>> findBreakoutDays(List<KLine> dailyBars, {String? stockCode}) async {
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

      // 6. 检测突破日分钟量比
      if (_config.minBreakoutMinuteRatio > 0 &&
          stockCode != null &&
          _historicalKlineService != null) {
        final ratio = await _historicalKlineService!.getDailyRatio(
          stockCode,
          bar.datetime,
        );
        if (ratio == null || ratio < _config.minBreakoutMinuteRatio) {
          continue;
        }
      }

      // 7. 验证后续是否有有效回踩（日K条件，不检查分钟量比）
      if (!_hasValidPullbackAfter(dailyBars, i, bar)) {
        continue;
      }

      // 所有条件都满足
      breakoutIndices.add(i);
    }

    return breakoutIndices;
  }

  /// 查找近似命中的突破日（差1-2个条件）
  /// 返回 Map<索引, 失败条件数>
  Map<int, int> findNearMissBreakoutDays(List<KLine> dailyBars, {int maxFailedConditions = 2}) {
    final nearMisses = <int, int>{};

    if (dailyBars.length < 6) {
      return nearMisses;
    }

    for (int i = 5; i < dailyBars.length; i++) {
      final bar = dailyBars[i];
      int failedCount = 0;

      // 1. 必须是上涨日（这是基本条件，不计入失败数）
      if (!bar.isUp) {
        continue;
      }

      // 2. 放量检测
      final prev5 = dailyBars.sublist(i - 5, i);
      final avg5Volume = prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;
      final volumeMultiple = bar.volume / avg5Volume;
      if (volumeMultiple <= _config.breakVolumeMultiplier) {
        // 如果量比太低（不到要求的60%），跳过
        if (volumeMultiple < _config.breakVolumeMultiplier * 0.6) {
          continue;
        }
        failedCount++;
      }

      // 3. 均线突破检测
      if (_config.maBreakDays > 0 && i >= _config.maBreakDays) {
        final maStart = i - _config.maBreakDays;
        final maBars = dailyBars.sublist(maStart, i);
        final ma = maBars.map((b) => b.close).reduce((a, b) => a + b) / _config.maBreakDays;
        if (bar.close <= ma) {
          failedCount++;
        }
      }

      // 4. 前高突破检测
      if (_config.highBreakDays > 0 && i >= _config.highBreakDays) {
        final highStart = i - _config.highBreakDays;
        final highBars = dailyBars.sublist(highStart, i);
        final maxHigh = highBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        if (bar.close <= maxHigh) {
          failedCount++;
        }
      }

      // 5. 上引线检测
      if (_config.maxUpperShadowRatio > 0) {
        final bodyLength = (bar.close - bar.open).abs();
        final upperShadow = bar.high - bar.close;
        if (bodyLength > 0) {
          final ratio = upperShadow / bodyLength;
          if (ratio > _config.maxUpperShadowRatio) {
            failedCount++;
          }
        }
      }

      // 6. 回踩检测
      if (!_hasValidPullbackAfter(dailyBars, i, bar)) {
        failedCount++;
      }

      // 如果失败条件数在1-maxFailedConditions之间，记录为近似命中
      if (failedCount >= 1 && failedCount <= maxFailedConditions) {
        nearMisses[i] = failedCount;
      }
    }

    return nearMisses;
  }

  /// 检查突破日后是否有符合条件的回踩
  /// [dailyBars] 日K数据
  /// [breakoutIdx] 突破日索引
  /// [breakoutBar] 突破日K线
  bool _hasValidPullbackAfter(List<KLine> dailyBars, int breakoutIdx, KLine breakoutBar) {
    // 计算参考价格
    final referencePrice = _config.dropReferencePoint == DropReferencePoint.breakoutClose
        ? breakoutBar.close
        : breakoutBar.high;

    // 检查每个可能的回踩结束日（从最短回踩天数到最长回踩天数）
    for (int pullbackDays = _config.minPullbackDays;
        pullbackDays <= _config.maxPullbackDays;
        pullbackDays++) {
      final endIdx = breakoutIdx + pullbackDays;

      // 确保不超出数据范围
      if (endIdx >= dailyBars.length) {
        break;
      }

      // 获取回踩期间的K线
      final pullbackBars = dailyBars.sublist(breakoutIdx + 1, endIdx + 1);
      final lastBar = pullbackBars.last;

      // 检查总跌幅
      final totalDrop = (referencePrice - lastBar.close) / referencePrice;
      if (totalDrop > _config.maxTotalDrop) {
        continue;
      }

      // 检查最大单日跌幅
      if (_config.maxSingleDayDrop > 0) {
        bool exceedsSingleDayDrop = false;
        for (final bar in pullbackBars) {
          final dayDrop = (referencePrice - bar.close) / referencePrice;
          if (dayDrop > _config.maxSingleDayDrop) {
            exceedsSingleDayDrop = true;
            break;
          }
        }
        if (exceedsSingleDayDrop) {
          continue;
        }
      }

      // 检查最大单日涨幅
      if (_config.maxSingleDayGain > 0) {
        bool exceedsSingleDayGain = false;
        for (final bar in pullbackBars) {
          final dayGain = (bar.close - referencePrice) / referencePrice;
          if (dayGain > _config.maxSingleDayGain) {
            exceedsSingleDayGain = true;
            break;
          }
        }
        if (exceedsSingleDayGain) {
          continue;
        }
      }

      // 检查最大总涨幅
      if (_config.maxTotalGain > 0) {
        final maxHigh = pullbackBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
        final totalGain = (maxHigh - referencePrice) / referencePrice;
        if (totalGain > _config.maxTotalGain) {
          continue;
        }
      }

      // 检查平均量比
      final avgPullbackVolume =
          pullbackBars.map((b) => b.volume).reduce((a, b) => a + b) / pullbackDays;
      final avgVolumeRatio = avgPullbackVolume / breakoutBar.volume;
      if (avgVolumeRatio > _config.maxAvgVolumeRatio) {
        continue;
      }

      // 找到一个有效的回踩
      return true;
    }

    // 没有找到有效回踩
    return false;
  }
}
