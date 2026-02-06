import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/industry_buildup_storage.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

class IndustryBuildUpService extends ChangeNotifier {
  static const double _tau = 0.001;
  static const int _zWindow = 20;
  static const int _expectedMinutes = 240;
  static const double _minDailyAmount = 2e7;
  static const double _minMinuteCoverage = 0.9;
  static const double _maxMinuteVolShare = 0.12;
  static const double _weightCap = 0.08;
  static const double _breadthLow = 0.30;
  static const double _breadthHigh = 0.55;
  static const int _minPassedMembers = 8;
  static const double _hhi0 = 0.06;
  static const double _concLambda = 12.0;
  static const int _persistLookback = 5;
  static const double _persistZ = 1.0;
  static const int _persistNeed = 3;
  static const double _eps = 1e-9;

  final DataRepository _repository;
  final IndustryService _industryService;
  final IndustryBuildUpStorage _storage;
  StreamSubscription? _dataUpdatedSubscription;

  bool _isCalculating = false;
  bool _isStale = false;
  String _stageLabel = '空闲';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String? _errorMessage;
  DateTime? _latestResultDate;
  DateTime? _lastComputedAt;
  int _calculatedFromVersion = -1;
  List<IndustryBuildupBoardItem> _latestBoard = [];

  IndustryBuildUpService({
    required DataRepository repository,
    required IndustryService industryService,
    IndustryBuildUpStorage? storage,
  }) : _repository = repository,
       _industryService = industryService,
       _storage = storage ?? IndustryBuildUpStorage() {
    _dataUpdatedSubscription = _repository.dataUpdatedStream.listen((_) {
      _isStale = true;
      notifyListeners();
    });
  }

  bool get isCalculating => _isCalculating;
  bool get isStale => _isStale;
  String get stageLabel => _stageLabel;
  int get progressCurrent => _progressCurrent;
  int get progressTotal => _progressTotal;
  String? get errorMessage => _errorMessage;
  DateTime? get latestResultDate => _latestResultDate;
  DateTime? get lastComputedAt => _lastComputedAt;
  List<IndustryBuildupBoardItem> get latestBoard =>
      List.unmodifiable(_latestBoard);

  Future<void> load() async {
    await _reloadLatestBoard();
  }

  Future<void> recalculate({bool force = false}) async {
    if (_isCalculating) return;

    _isCalculating = true;
    _errorMessage = null;
    _setProgress('准备数据', 0, 1);

    try {
      final currentVersion = await _repository.getCurrentVersion();
      if (!force &&
          !_isStale &&
          _calculatedFromVersion == currentVersion &&
          _latestBoard.isNotEmpty) {
        _setProgress('完成', 1, 1);
        return;
      }

      final probeRange = DateRange(
        DateTime.now().subtract(const Duration(days: 60)),
        DateTime.now(),
      );
      final tradingDates = await _repository.getTradingDates(probeRange);
      if (tradingDates.isEmpty) {
        _errorMessage = '无交易日数据';
        _setProgress('准备数据', 1, 1);
        return;
      }

      final sortedTradingDates =
          tradingDates
              .map((d) => DateTime(d.year, d.month, d.day))
              .toSet()
              .toList()
            ..sort();
      final start = sortedTradingDates.first;
      final end = sortedTradingDates.last.add(const Duration(days: 1));
      final dateRange = DateRange(
        start,
        end.subtract(const Duration(milliseconds: 1)),
      );

      final industryStocks = _buildIndustryStocks();
      final stockCodes = industryStocks.values.expand((e) => e).toSet().toList()
        ..sort();
      if (stockCodes.isEmpty) {
        _errorMessage = '无行业股票映射';
        _setProgress('准备数据', 1, 1);
        return;
      }
      _setProgress('准备数据', 1, 1);

      final stockFeatures = <String, Map<int, _StockDayFeature>>{};
      _setProgress('预处理', 0, stockCodes.length);
      for (var i = 0; i < stockCodes.length; i++) {
        final code = stockCodes[i];
        final bars =
            (await _repository.getKlines(
              stockCodes: [code],
              dateRange: dateRange,
              dataType: KLineDataType.oneMinute,
            ))[code] ??
            [];
        stockFeatures[code] = _computeStockDayFeatures(bars);
        _setProgress('预处理', i + 1, stockCodes.length);
      }

      final intermediatesByIndustry =
          <String, List<_IndustryDayIntermediate>>{};
      final aggregationTotal =
          sortedTradingDates.length * industryStocks.length;
      var aggregationCurrent = 0;
      _setProgress('行业聚合', 0, max(1, aggregationTotal));
      for (final date in sortedTradingDates) {
        final dateKey = _dateKey(date);

        final marketFeatures = <_StockDayFeature>[];
        for (final code in stockCodes) {
          final feature = stockFeatures[code]?[dateKey];
          if (feature != null && feature.passed) {
            marketFeatures.add(feature);
          }
        }
        final xM = marketFeatures.isEmpty
            ? 0.0
            : marketFeatures.map((f) => f.xHat).reduce((a, b) => a + b) /
                  marketFeatures.length;

        for (final entry in industryStocks.entries) {
          aggregationCurrent++;
          final industry = entry.key;
          final memberCodes = entry.value;
          final memberCount = memberCodes.length;

          final features = <_StockDayFeature>[];
          for (final code in memberCodes) {
            final feature = stockFeatures[code]?[dateKey];
            if (feature != null && feature.passed) {
              features.add(feature);
            }
          }

          final passedCount = features.length;
          if (passedCount == 0 || memberCount == 0) {
            _setProgress('行业聚合', aggregationCurrent, max(1, aggregationTotal));
            continue;
          }

          final weights = _buildWeights(features);
          var xI = 0.0;
          var hhi = 0.0;
          var positiveCount = 0;
          for (var i = 0; i < features.length; i++) {
            final weight = weights[i];
            xI += weight * features[i].xHat;
            hhi += weight * weight;
            if (features[i].xHat > 0) {
              positiveCount++;
            }
          }
          final breadth = positiveCount / passedCount;

          intermediatesByIndustry.putIfAbsent(industry, () => []);
          intermediatesByIndustry[industry]!.add(
            _IndustryDayIntermediate(
              date: date,
              xI: xI,
              xM: xM,
              xRel: xI - xM,
              breadth: breadth,
              passedCount: passedCount,
              memberCount: memberCount,
              hhi: hhi,
            ),
          );
          _setProgress('行业聚合', aggregationCurrent, max(1, aggregationTotal));
        }
      }

      final now = DateTime.now();
      final recordsByDate = <int, List<IndustryBuildupDailyRecord>>{};
      _setProgress('计算评分', 0, max(1, intermediatesByIndustry.length));
      var scoringCurrent = 0;
      for (final entry in intermediatesByIndustry.entries) {
        final industry = entry.key;
        final series = entry.value..sort((a, b) => a.date.compareTo(b.date));
        final zSeries = <double>[];

        for (var i = 0; i < series.length; i++) {
          final windowStart = max(0, i - _zWindow + 1);
          final window = series.sublist(windowStart, i + 1);
          final xRelValues = window.map((d) => d.xRel).toList();
          final mu = xRelValues.reduce((a, b) => a + b) / xRelValues.length;
          var sigmaSquare = 0.0;
          for (final value in xRelValues) {
            final diff = value - mu;
            sigmaSquare += diff * diff;
          }
          final sigma = sqrt(sigmaSquare / xRelValues.length);
          final zRel = (series[i].xRel - mu) / (sigma + _eps);
          zSeries.add(zRel);

          final qCoverage = min(1.0, series[i].passedCount / _minPassedMembers);
          final qBreadth = _clip01(
            (series[i].breadth - _breadthLow) / (_breadthHigh - _breadthLow),
          );
          final qConc = exp(-_concLambda * max(0.0, series[i].hhi - _hhi0));

          final persistStart = max(0, zSeries.length - _persistLookback);
          final persistCount = zSeries
              .sublist(persistStart)
              .where((z) => z > _persistZ)
              .length;
          final qPersist = persistCount >= _persistNeed ? 1.0 : 0.6;
          final q = _clip01(qCoverage * qBreadth * qConc * qPersist);

          final record = IndustryBuildupDailyRecord(
            date: series[i].date,
            industry: industry,
            zRel: zRel,
            breadth: series[i].breadth,
            q: q,
            xI: series[i].xI,
            xM: series[i].xM,
            passedCount: series[i].passedCount,
            memberCount: series[i].memberCount,
            rank: 0,
            updatedAt: now,
          );

          recordsByDate.putIfAbsent(_dateKey(series[i].date), () => []);
          recordsByDate[_dateKey(series[i].date)]!.add(record);
        }

        scoringCurrent++;
        _setProgress(
          '计算评分',
          scoringCurrent,
          max(1, intermediatesByIndustry.length),
        );
      }

      final finalRecords = <IndustryBuildupDailyRecord>[];
      for (final entry in recordsByDate.entries) {
        final dayRecords = entry.value
          ..sort((a, b) => b.zRel.compareTo(a.zRel));
        for (var i = 0; i < dayRecords.length; i++) {
          final base = dayRecords[i];
          finalRecords.add(
            IndustryBuildupDailyRecord(
              date: base.date,
              industry: base.industry,
              zRel: base.zRel,
              breadth: base.breadth,
              q: base.q,
              xI: base.xI,
              xM: base.xM,
              passedCount: base.passedCount,
              memberCount: base.memberCount,
              rank: i + 1,
              updatedAt: base.updatedAt,
            ),
          );
        }
      }

      _setProgress('写入结果', 0, max(1, finalRecords.length));
      await _storage.upsertDailyResults(finalRecords);
      _setProgress(
        '写入结果',
        max(1, finalRecords.length),
        max(1, finalRecords.length),
      );

      _calculatedFromVersion = currentVersion;
      _lastComputedAt = now;
      _isStale = false;
      await _reloadLatestBoard();
      _setProgress('完成', 1, 1);
    } catch (e, stackTrace) {
      _errorMessage = e.toString();
      debugPrint('[IndustryBuildUp] recalculate failed: $e');
      debugPrint('$stackTrace');
    } finally {
      _isCalculating = false;
      notifyListeners();
    }
  }

  Map<String, List<String>> _buildIndustryStocks() {
    final result = <String, List<String>>{};
    for (final industry in _industryService.allIndustries) {
      final stocks = _industryService.getStocksByIndustry(industry);
      if (stocks.isNotEmpty) {
        result[industry] = stocks;
      }
    }
    return result;
  }

  List<double> _buildWeights(List<_StockDayFeature> features) {
    if (features.isEmpty) return const [];
    final sumAmount = features.fold<double>(0, (sum, item) => sum + item.aSum);
    final raw = <double>[];
    if (sumAmount <= 0) {
      final equal = 1.0 / features.length;
      for (var i = 0; i < features.length; i++) {
        raw.add(equal);
      }
    } else {
      for (final feature in features) {
        raw.add(feature.aSum / sumAmount);
      }
    }

    final capped = raw.map((w) => min(w, _weightCap)).toList();
    final cappedSum = capped.fold<double>(0, (sum, item) => sum + item);
    if (cappedSum <= 0) {
      final equal = 1.0 / features.length;
      return List<double>.filled(features.length, equal);
    }
    return capped.map((w) => w / cappedSum).toList();
  }

  Map<int, _StockDayFeature> _computeStockDayFeatures(List<KLine> bars) {
    final byDate = <int, List<KLine>>{};
    for (final bar in bars) {
      byDate.putIfAbsent(_dateKey(bar.datetime), () => []);
      byDate[_dateKey(bar.datetime)]!.add(bar);
    }

    final result = <int, _StockDayFeature>{};
    for (final entry in byDate.entries) {
      final dayBars = entry.value
        ..sort((a, b) => a.datetime.compareTo(b.datetime));
      if (dayBars.isEmpty) continue;

      var pSum = 0.0;
      var vSum = 0.0;
      var aSum = 0.0;
      var maxV = 0.0;
      for (final bar in dayBars) {
        vSum += bar.volume;
        aSum += bar.amount;
        if (bar.volume > maxV) {
          maxV = bar.volume;
        }
      }

      for (var i = 1; i < dayBars.length; i++) {
        final prevClose = dayBars[i - 1].close;
        if (prevClose <= 0) continue;
        final r = log(dayBars[i].close / prevClose);
        final phi = _tanh(r / _tau);
        pSum += dayBars[i].volume * phi;
      }

      final xHat = pSum / (vSum + _eps);
      final coverage = dayBars.length / _expectedMinutes;
      final maxShare = maxV / (vSum + _eps);
      final passed =
          aSum >= _minDailyAmount &&
          coverage >= _minMinuteCoverage &&
          maxShare <= _maxMinuteVolShare;

      result[entry.key] = _StockDayFeature(
        xHat: xHat,
        vSum: vSum,
        aSum: aSum,
        maxShare: maxShare,
        minuteCount: dayBars.length,
        passed: passed,
      );
    }

    return result;
  }

  Future<void> _reloadLatestBoard() async {
    final latestDate = await _storage.getLatestDate();
    _latestResultDate = latestDate;
    if (latestDate == null) {
      _latestBoard = [];
      notifyListeners();
      return;
    }

    final records = await _storage.getLatestBoard(limit: 50);
    final boardItems = <IndustryBuildupBoardItem>[];
    for (final record in records) {
      final trend = await _storage.getIndustryTrend(record.industry, days: 20);
      boardItems.add(
        IndustryBuildupBoardItem(record: record, zRelTrend: trend),
      );
    }
    _latestBoard = boardItems;
    notifyListeners();
  }

  void _setProgress(String stage, int current, int total) {
    _stageLabel = stage;
    _progressCurrent = current;
    _progressTotal = total;
    notifyListeners();
  }

  int _dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;

  double _clip01(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  double _tanh(double x) {
    final e2x = exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }

  @override
  void dispose() {
    _dataUpdatedSubscription?.cancel();
    _dataUpdatedSubscription = null;
    super.dispose();
  }
}

class _StockDayFeature {
  final double xHat;
  final double vSum;
  final double aSum;
  final double maxShare;
  final int minuteCount;
  final bool passed;

  const _StockDayFeature({
    required this.xHat,
    required this.vSum,
    required this.aSum,
    required this.maxShare,
    required this.minuteCount,
    required this.passed,
  });
}

class _IndustryDayIntermediate {
  final DateTime date;
  final double xI;
  final double xM;
  final double xRel;
  final double breadth;
  final int passedCount;
  final int memberCount;
  final double hhi;

  const _IndustryDayIntermediate({
    required this.date,
    required this.xI,
    required this.xM,
    required this.xRel,
    required this.breadth,
    required this.passedCount,
    required this.memberCount,
    required this.hhi,
  });
}
