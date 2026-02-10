import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/industry_buildup_storage.dart';
import 'package:stock_rtwatcher/models/adaptive_weekly_config.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';
import 'package:stock_rtwatcher/services/adaptive_topk_calibrator.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_computer.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_loader.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_pipeline_models.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_writer.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

class IndustryBuildUpService extends ChangeNotifier {
  static const String _tagConfigStorageKey = 'industry_buildup_tag_config';

  static const int _adaptiveLookbackTradingDays = 5;

  final DataRepository _repository;
  final IndustryService _industryService;
  final IndustryBuildUpStorage _storage;
  final IndustryBuildUpLoader _loader;
  final IndustryBuildUpComputer _computer;
  final IndustryBuildUpWriter _writer;
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
  final Map<String, List<IndustryBuildupDailyRecord>> _industryHistory = {};
  final Set<String> _industryHistoryLoaded = {};
  final Set<String> _industryHistoryLoading = {};
  bool _hasPreviousDate = false;
  bool _hasNextDate = false;
  IndustryBuildupTagConfig _tagConfig = IndustryBuildupTagConfig.defaults;
  AdaptiveTopKParams _adaptiveTopKParams = const AdaptiveTopKParams();
  AdaptiveWeeklyConfig? _latestWeeklyAdaptiveConfig;
  IndustryScoreConfig _scoreConfig = const IndustryScoreConfig();

  IndustryBuildUpService({
    required DataRepository repository,
    required IndustryService industryService,
    IndustryBuildUpStorage? storage,
    IndustryBuildUpLoader? loader,
    IndustryBuildUpComputer? computer,
    IndustryBuildUpWriter? writer,
  }) : _repository = repository,
       _industryService = industryService,
       _storage = storage ?? IndustryBuildUpStorage(),
       _loader = loader ?? DefaultIndustryBuildUpLoader(),
       _computer = computer ?? DefaultIndustryBuildUpComputer(),
       _writer = writer ?? DefaultIndustryBuildUpWriter() {
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
  bool get hasPreviousDate => _hasPreviousDate;
  bool get hasNextDate => _hasNextDate;
  IndustryBuildupTagConfig get tagConfig => _tagConfig;
  AdaptiveTopKParams get adaptiveTopKParams => _adaptiveTopKParams;
  AdaptiveWeeklyConfig? get latestWeeklyAdaptiveConfig =>
      _latestWeeklyAdaptiveConfig;
  IndustryScoreConfig get scoreConfig => _scoreConfig;
  List<IndustryBuildupBoardItem> get latestBoard =>
      List.unmodifiable(_latestBoard);
  bool hasIndustryHistory(String industry) =>
      _industryHistoryLoaded.contains(industry.trim());
  bool isIndustryHistoryLoading(String industry) =>
      _industryHistoryLoading.contains(industry.trim());
  List<IndustryBuildupDailyRecord> getIndustryHistory(String industry) =>
      List.unmodifiable(
        _industryHistory[industry.trim()] ??
            const <IndustryBuildupDailyRecord>[],
      );

  void updateTagConfig(IndustryBuildupTagConfig config) {
    _tagConfig = config;
    notifyListeners();
    _saveTagConfig();
  }

  void resetTagConfig() {
    _tagConfig = IndustryBuildupTagConfig.defaults;
    notifyListeners();
    _saveTagConfig();
  }

  Future<void> updateAdaptiveTopKParams(AdaptiveTopKParams params) async {
    _adaptiveTopKParams = params;
    final currentDate = _latestResultDate;
    if (currentDate != null) {
      _latestWeeklyAdaptiveConfig = await _buildWeeklyAdaptiveConfigForDate(
        currentDate,
      );
    }
    notifyListeners();
  }

  Future<void> updateScoreConfig(IndustryScoreConfig config) async {
    _scoreConfig = config;
    final currentDate = _latestResultDate;
    if (currentDate != null) {
      await recalculate(force: true);
    } else {
      notifyListeners();
    }
  }

  Future<void> loadIndustryHistory(
    String industry, {
    bool force = false,
  }) async {
    final normalizedIndustry = industry.trim();
    if (normalizedIndustry.isEmpty) return;
    if (!force && _industryHistoryLoaded.contains(normalizedIndustry)) return;
    if (_industryHistoryLoading.contains(normalizedIndustry)) return;

    _industryHistoryLoading.add(normalizedIndustry);
    notifyListeners();
    try {
      final records = await _storage.getIndustryHistory(normalizedIndustry);
      _industryHistory[normalizedIndustry] = records;
      _industryHistoryLoaded.add(normalizedIndustry);
    } catch (e, stackTrace) {
      debugPrint(
        '[IndustryBuildUp] loadIndustryHistory failed: $normalizedIndustry, $e',
      );
      debugPrint('$stackTrace');
    } finally {
      _industryHistoryLoading.remove(normalizedIndustry);
      notifyListeners();
    }
  }

  Future<void> load() async {
    await _loadTagConfig();
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

      final loadOutcome = await _loader.load(
        repository: _repository,
        industryService: _industryService,
        onTradingDateScanProgress: (current, total) {
          _setProgress('扫描交易日', current, total);
        },
        onPreprocessProgress: (current, total) {
          _setProgress('预处理', current, total);
        },
      );
      if (!loadOutcome.isSuccess) {
        _errorMessage = loadOutcome.errorMessage;
        _setProgress('准备数据', 1, 1);
        return;
      }
      final loadResult = loadOutcome.result!;
      final latestTradingDate = loadResult.latestTradingDate;
      final latestTradingDateKey = loadResult.latestTradingDateKey;

      _setProgress('准备数据', 1, 1);
      final now = DateTime.now();
      final computeResult = _computer.compute(
        loadResult: loadResult,
        scoreConfig: _scoreConfig,
        now: now,
        onAggregationProgress: (current, total) {
          _setProgress('行业聚合', current, total);
        },
        onScoringProgress: (current, total) {
          _setProgress('计算评分', current, total);
        },
      );
      final finalRecords = computeResult.finalRecords;

      final hasLatestTradingDayResult = computeResult.hasLatestTradingDayResult;
      if (!hasLatestTradingDayResult) {
        _errorMessage =
            '最近交易日(${_formatDate(latestTradingDate)})无可用分钟线，未生成建仓雷达结果';
        _setProgress('无结果', 1, 1);
        return;
      }

      if (finalRecords.isEmpty) {
        _errorMessage = '重算完成，但可用分钟线数据不足，未生成建仓雷达结果';
        _setProgress('无结果', 1, 1);
        return;
      }

      _setProgress('写入结果', 0, max(1, finalRecords.length));
      final writeResult = await _writer.write(
        storage: _storage,
        records: finalRecords,
      );
      _setProgress(
        '写入结果',
        max(1, writeResult.writtenCount),
        max(1, writeResult.writtenCount),
      );

      _calculatedFromVersion = currentVersion;
      _lastComputedAt = now;
      _isStale = false;
      _clearIndustryHistoryCache();
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

  Future<void> _reloadLatestBoard() async {
    final latestDate = await _storage.getLatestDate();
    if (latestDate == null) {
      _latestResultDate = null;
      _latestBoard = [];
      _latestWeeklyAdaptiveConfig = null;
      _hasPreviousDate = false;
      _hasNextDate = false;
      notifyListeners();
      return;
    }

    await _loadBoardForDate(latestDate);
  }

  Future<void> showPreviousDateBoard() async {
    final currentDate = _latestResultDate;
    if (_isCalculating || currentDate == null) return;
    final previousDate = await _storage.getPreviousDate(currentDate);
    if (previousDate == null) {
      if (_hasPreviousDate) {
        _hasPreviousDate = false;
        notifyListeners();
      }
      return;
    }
    await _loadBoardForDate(previousDate);
  }

  Future<void> showNextDateBoard() async {
    final currentDate = _latestResultDate;
    if (_isCalculating || currentDate == null) return;
    final nextDate = await _storage.getNextDate(currentDate);
    if (nextDate == null) {
      if (_hasNextDate) {
        _hasNextDate = false;
        notifyListeners();
      }
      return;
    }
    await _loadBoardForDate(nextDate);
  }

  Future<void> _loadBoardForDate(DateTime date) async {
    final records = await _storage.getBoardForDate(date, limit: 50);
    final boardItems = <IndustryBuildupBoardItem>[];
    for (final record in records) {
      final zRelTrend = await _storage.getIndustryTrend(
        record.industry,
        days: 20,
      );
      final rawScoreTrend = await _storage.getIndustryRawScoreTrend(
        record.industry,
        days: 20,
      );
      final scoreEmaTrend = await _storage.getIndustryScoreEmaTrend(
        record.industry,
        days: 20,
      );
      final rankTrend = await _storage.getIndustryRankTrend(
        record.industry,
        days: 20,
      );
      boardItems.add(
        IndustryBuildupBoardItem(
          record: record,
          zRelTrend: zRelTrend,
          rawScoreTrend: rawScoreTrend,
          scoreEmaTrend: scoreEmaTrend,
          rankTrend: rankTrend,
        ),
      );
    }
    _latestResultDate = DateTime(date.year, date.month, date.day);
    _hasPreviousDate =
        await _storage.getPreviousDate(_latestResultDate!) != null;
    _hasNextDate = await _storage.getNextDate(_latestResultDate!) != null;
    _latestBoard = boardItems;
    _latestWeeklyAdaptiveConfig = await _buildWeeklyAdaptiveConfigForDate(
      _latestResultDate!,
    );
    notifyListeners();
  }

  Future<AdaptiveWeeklyConfig> _buildWeeklyAdaptiveConfigForDate(
    DateTime date,
  ) async {
    final weeklyRecords = await _loadRecentTradingDayRecords(
      date,
      tradingDays: _adaptiveLookbackTradingDays,
    );

    final inputs = weeklyRecords
        .map(
          (record) => AdaptiveIndustryDayRecord(
            industry: record.industry,
            day: record.dateOnly,
            z: record.zRel,
            q: record.q,
            breadth: record.breadth,
          ),
        )
        .toList(growable: false);

    return buildWeeklyConfig(
      inputs,
      params: _adaptiveTopKParams,
      referenceDay: date,
    );
  }

  Future<List<IndustryBuildupDailyRecord>> _loadRecentTradingDayRecords(
    DateTime endDate, {
    required int tradingDays,
  }) async {
    final normalizedEndDate = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );
    final dates = <DateTime>[normalizedEndDate];
    var cursor = normalizedEndDate;
    while (dates.length < tradingDays) {
      final previous = await _storage.getPreviousDate(cursor);
      if (previous == null) break;
      final normalized = DateTime(previous.year, previous.month, previous.day);
      dates.add(normalized);
      cursor = normalized;
    }

    final records = <IndustryBuildupDailyRecord>[];
    for (final day in dates) {
      final dayRecords = await _storage.getBoardForDate(day, limit: 500);
      records.addAll(dayRecords);
    }
    return records;
  }

  void _setProgress(String stage, int current, int total) {
    _stageLabel = stage;
    _progressCurrent = current;
    _progressTotal = total;
    notifyListeners();
  }

  void _clearIndustryHistoryCache() {
    _industryHistory.clear();
    _industryHistoryLoaded.clear();
    _industryHistoryLoading.clear();
  }

  int _dateKey(DateTime date) => industryBuildUpDateKey(date);

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _dataUpdatedSubscription?.cancel();
    _dataUpdatedSubscription = null;
    super.dispose();
  }

  Future<void> _loadTagConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tagConfigStorageKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _tagConfig = IndustryBuildupTagConfig.fromJson(json);
      notifyListeners();
    } catch (e) {
      debugPrint('[IndustryBuildUp] load tag config failed: $e');
    }
  }

  Future<void> _saveTagConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _tagConfigStorageKey,
        jsonEncode(_tagConfig.toJson()),
      );
    } catch (e) {
      debugPrint('[IndustryBuildUp] save tag config failed: $e');
    }
  }
}
