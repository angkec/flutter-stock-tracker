import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/adaptive_weekly_config.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/industry_buildup_list.dart';

class _DummyRepository implements DataRepository {
  final _statusController = StreamController<DataStatus>.broadcast();
  final _updatedController = StreamController<DataUpdatedEvent>.broadcast();

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {}

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async => 0;

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async => const MissingDatesResult(
    missingDates: [],
    incompleteDates: [],
    completeDates: [],
  );

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async => {};

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async => {};

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async => [];

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );
}

class _FakeIndustryBuildUpService extends IndustryBuildUpService {
  bool _fakeIsCalculating = false;
  String _fakeStageLabel = '空闲';
  int _fakeProgressCurrent = 0;
  int _fakeProgressTotal = 0;
  String? _fakeErrorMessage;
  DateTime? _fakeLatestResultDate;
  List<IndustryBuildupBoardItem> _fakeBoard = const [];
  bool _fakeHasPreviousDate = false;
  bool _fakeHasNextDate = false;
  IndustryBuildupTagConfig _fakeTagConfig = IndustryBuildupTagConfig.defaults;
  AdaptiveWeeklyConfig? _fakeWeeklyConfig;
  int previousTapCount = 0;
  int nextTapCount = 0;

  _FakeIndustryBuildUpService()
    : super(repository: _DummyRepository(), industryService: IndustryService());

  @override
  bool get isCalculating => _fakeIsCalculating;

  @override
  String get stageLabel => _fakeStageLabel;

  @override
  int get progressCurrent => _fakeProgressCurrent;

  @override
  int get progressTotal => _fakeProgressTotal;

  @override
  String? get errorMessage => _fakeErrorMessage;

  @override
  DateTime? get latestResultDate => _fakeLatestResultDate;

  @override
  List<IndustryBuildupBoardItem> get latestBoard =>
      List.unmodifiable(_fakeBoard);

  @override
  bool get hasPreviousDate => _fakeHasPreviousDate;

  @override
  bool get hasNextDate => _fakeHasNextDate;

  @override
  IndustryBuildupTagConfig get tagConfig => _fakeTagConfig;

  @override
  AdaptiveWeeklyConfig? get latestWeeklyAdaptiveConfig => _fakeWeeklyConfig;

  void setUiState({
    bool? isCalculating,
    String? stageLabel,
    int? progressCurrent,
    int? progressTotal,
    String? errorMessage,
    DateTime? latestResultDate,
    List<IndustryBuildupBoardItem>? board,
    bool? hasPreviousDate,
    bool? hasNextDate,
    AdaptiveWeeklyConfig? weeklyConfig,
  }) {
    if (isCalculating != null) {
      _fakeIsCalculating = isCalculating;
    }
    if (stageLabel != null) {
      _fakeStageLabel = stageLabel;
    }
    if (progressCurrent != null) {
      _fakeProgressCurrent = progressCurrent;
    }
    if (progressTotal != null) {
      _fakeProgressTotal = progressTotal;
    }
    _fakeErrorMessage = errorMessage;
    _fakeLatestResultDate = latestResultDate ?? _fakeLatestResultDate;
    if (board != null) {
      _fakeBoard = board;
    }
    if (hasPreviousDate != null) {
      _fakeHasPreviousDate = hasPreviousDate;
    }
    if (hasNextDate != null) {
      _fakeHasNextDate = hasNextDate;
    }
    _fakeWeeklyConfig = weeklyConfig ?? _fakeWeeklyConfig;
    notifyListeners();
  }

  @override
  Future<void> recalculate({bool force = false}) async {}

  @override
  Future<void> showPreviousDateBoard() async {
    previousTapCount++;
  }

  @override
  Future<void> showNextDateBoard() async {
    nextTapCount++;
  }

  @override
  void updateTagConfig(IndustryBuildupTagConfig config) {
    _fakeTagConfig = config;
    notifyListeners();
  }

  @override
  void resetTagConfig() {
    _fakeTagConfig = IndustryBuildupTagConfig.defaults;
    notifyListeners();
  }
}

IndustryBuildupBoardItem _boardItem({
  required String industry,
  required double zRel,
  required double breadth,
  required double q,
  double rawScore = 0.0,
  double scoreEma = 0.0,
  int rank = 1,
  int rankChange = 0,
  String rankArrow = '→',
  List<double> scoreEmaTrend = const [],
  List<double> rankTrend = const [],
}) {
  return IndustryBuildupBoardItem(
    record: IndustryBuildupDailyRecord(
      date: DateTime(2026, 2, 6),
      industry: industry,
      zRel: zRel,
      breadth: breadth,
      q: q,
      rawScore: rawScore,
      scoreEma: scoreEma,
      xI: 0.1,
      xM: 0.05,
      passedCount: 10,
      memberCount: 20,
      rank: rank,
      rankChange: rankChange,
      rankArrow: rankArrow,
      updatedAt: DateTime(2026, 2, 6, 15),
    ),
    zRelTrend: const [0.1, 0.2, 0.3],
    scoreEmaTrend: scoreEmaTrend,
    rankTrend: rankTrend,
  );
}

void main() {
  testWidgets('空榜单状态下显示重算进度与错误反馈', (tester) async {
    final service = _FakeIndustryBuildUpService();

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    service.setUiState(
      isCalculating: true,
      stageLabel: '预处理',
      progressCurrent: 3,
      progressTotal: 10,
      errorMessage: null,
      board: const [],
    );
    await tester.pump();

    expect(find.text('预处理 3/10'), findsWidgets);

    service.setUiState(
      isCalculating: false,
      errorMessage: '重算完成，但可用分钟线数据不足，未生成建仓雷达结果',
      board: const [],
    );
    await tester.pump();

    expect(find.textContaining('未生成建仓雷达结果'), findsOneWidget);
  });

  testWidgets('结果列表显示状态Tag', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 1.7, breadth: 0.45, q: 0.70)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.text('行业配置期'), findsOneWidget);
  });

  testWidgets('点击帮助按钮弹出解读说明', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 0.2, breadth: 0.2, q: 0.4)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.byTooltip('解读帮助'), findsOneWidget);
    await tester.tap(find.byTooltip('解读帮助'));
    await tester.pumpAndSettle();

    expect(find.text('建仓雷达解读指南'), findsOneWidget);
    expect(find.textContaining('Z 值'), findsWidgets);
    expect(find.textContaining('Q 值'), findsWidgets);
    expect(find.textContaining('早期建仓'), findsWidgets);
    expect(find.textContaining('行业配置期'), findsWidgets);
    expect(find.textContaining('情绪驱动'), findsWidgets);
    expect(find.textContaining('噪音信号'), findsWidgets);
    expect(find.textContaining('无异常'), findsWidgets);
    expect(find.textContaining('观察中'), findsWidgets);
    expect(find.textContaining('Z > 2.0'), findsWidgets);
    expect(find.textContaining('广度 > 0.55'), findsWidgets);
    expect(find.textContaining('其余不满足以上条件'), findsWidgets);
  });

  testWidgets('状态栏显示左右箭头并触发历史日期切换', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 1.7, breadth: 0.45, q: 0.70)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
      hasPreviousDate: true,
      hasNextDate: false,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.byTooltip('上一日'), findsOneWidget);
    expect(find.byTooltip('下一日'), findsOneWidget);

    await tester.tap(find.byTooltip('上一日'));
    await tester.pump();
    expect(service.previousTapCount, 1);

    await tester.tap(find.byTooltip('下一日'));
    await tester.pump();
    expect(service.nextTapCount, 0);
  });

  testWidgets('状态栏展示本周候选状态与阈值', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 1.7, breadth: 0.45, q: 0.70)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
      weeklyConfig: const AdaptiveWeeklyConfig(
        week: '2026-W06',
        k: 3,
        floors: AdaptiveFloors(z: 0.8, q: 0.5, breadth: 0.2),
        thresholds: AdaptiveThresholds(z: 1.27, q: 0.56, breadth: 0.27),
        candidates: [],
        status: AdaptiveWeeklyStatus.weak,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.textContaining('本周候选 观察'), findsOneWidget);
    expect(find.textContaining('Top-3'), findsOneWidget);
    expect(find.textContaining('Z≥1.27'), findsOneWidget);
    expect(find.textContaining('Q≥0.56'), findsOneWidget);
    expect(find.textContaining('广度≥0.27'), findsOneWidget);
  });

  testWidgets('展示本周候选榜 candidates 明细', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 1.7, breadth: 0.45, q: 0.70)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
      weeklyConfig: AdaptiveWeeklyConfig(
        week: '2026-W06',
        k: 3,
        floors: const AdaptiveFloors(z: 0.8, q: 0.5, breadth: 0.2),
        thresholds: const AdaptiveThresholds(z: 1.27, q: 0.56, breadth: 0.27),
        candidates: [
          AdaptiveCandidate(
            industry: '半导体',
            day: DateTime(2026, 2, 6),
            z: 1.62,
            q: 0.71,
            breadth: 0.41,
            score: 1.06,
          ),
          AdaptiveCandidate(
            industry: '军工',
            day: DateTime(2026, 2, 5),
            z: 1.44,
            q: 0.64,
            breadth: 0.33,
            score: 0.89,
          ),
        ],
        status: AdaptiveWeeklyStatus.strong,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.textContaining('本周候选榜 2026-W06'), findsOneWidget);
    expect(find.textContaining('1. 半导体'), findsWidgets);
    expect(find.textContaining('2. 军工'), findsWidgets);
    expect(find.textContaining('score 1.06'), findsOneWidget);
    expect(find.textContaining('score 0.89'), findsOneWidget);
  });

  testWidgets('指标配置可调整Z广度Q阈值并影响标签', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [_boardItem(industry: '半导体', zRel: 1.7, breadth: 0.45, q: 0.70)],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: IndustryBuildupList(fullHeight: true)),
        ),
      ),
    );

    expect(find.text('行业配置期'), findsOneWidget);
    expect(find.byTooltip('指标配置'), findsOneWidget);

    await tester.tap(find.byTooltip('指标配置'));
    await tester.pumpAndSettle();

    expect(find.text('建仓雷达阈值配置'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '行业配置期最小Z'), '2.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('观察中'), findsOneWidget);
  });

  testWidgets('雷达排名模式仅展示Top10趋势表并支持窗口切换', (tester) async {
    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [
        _boardItem(
          industry: '半导体',
          zRel: 1.6,
          breadth: 0.42,
          q: 0.72,
          rawScore: 1.12,
          scoreEma: 0.96,
          rank: 1,
          rankChange: 2,
          rankArrow: '↑',
          scoreEmaTrend: const [0.55, 0.66, 0.74, 0.82, 0.96],
          rankTrend: const [4, 3, 2, 2, 1],
        ),
        _boardItem(
          industry: '军工',
          zRel: 1.2,
          breadth: 0.35,
          q: 0.66,
          rawScore: 0.84,
          scoreEma: 0.78,
          rank: 2,
          rankChange: -1,
          rankArrow: '↓',
          scoreEmaTrend: const [0.48, 0.58, 0.61, 0.73, 0.78],
          rankTrend: const [2, 2, 3, 1, 2],
        ),
      ],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
      hasPreviousDate: true,
      hasNextDate: true,
      weeklyConfig: AdaptiveWeeklyConfig(
        week: '2026-W06',
        k: 3,
        floors: const AdaptiveFloors(z: 0.8, q: 0.5, breadth: 0.2),
        thresholds: const AdaptiveThresholds(z: 1.27, q: 0.56, breadth: 0.27),
        candidates: [
          AdaptiveCandidate(
            industry: '半导体',
            day: DateTime(2026, 2, 6),
            z: 1.62,
            q: 0.71,
            breadth: 0.41,
            score: 1.06,
          ),
        ],
        status: AdaptiveWeeklyStatus.strong,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: IndustryBuildupList(
              fullHeight: true,
              showRankingBoard: true,
              rankingTrendTableMode: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('20日趋势 Top10'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('5日'), findsOneWidget);
    expect(find.text('10日'), findsOneWidget);
    expect(find.text('20日'), findsOneWidget);
    expect(find.text('排名'), findsOneWidget);
    expect(find.text('行业'), findsOneWidget);
    expect(find.text('指标'), findsOneWidget);
    expect(find.text('变化'), findsOneWidget);
    expect(find.text('趋势'), findsOneWidget);

    expect(find.textContaining('本周候选榜'), findsNothing);
    expect(find.byTooltip('上一日'), findsNothing);
    expect(find.byTooltip('下一日'), findsNothing);
    expect(find.text('趋势最强'), findsNothing);
    expect(find.text('今日爆点'), findsNothing);

    await tester.tap(find.text('5日'));
    await tester.pump();

    expect(find.textContaining('EMA'), findsWidgets);
  });

  testWidgets('建仓雷达概览以全行业大表展示并可滚动查看全部行业', (tester) async {
    final service = _FakeIndustryBuildUpService();
    final board = List<IndustryBuildupBoardItem>.generate(
      10,
      (index) => _boardItem(
        industry: '行业${index + 1}',
        zRel: 1.0 + index * 0.1,
        breadth: 0.3 + index * 0.01,
        q: 0.6,
        rawScore: 0.5 + index * 0.05,
        scoreEma: 0.4 + index * 0.04,
        rank: index + 1,
      ),
    );
    service.setUiState(
      board: board,
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: IndustryBuildupList(
              fullHeight: true,
              showRankingBoard: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('建仓雷达概览表'), findsOneWidget);
    expect(find.text('行业/状态'), findsOneWidget);
    expect(find.text('EMA'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Z/Q/广'), findsOneWidget);
    expect(find.text('排名变动'), findsOneWidget);
    expect(find.text('趋势'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('行业10'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('行业10'), findsOneWidget);
  });

  testWidgets('建仓雷达概览表支持横向滚动查看右侧列', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeIndustryBuildUpService();
    service.setUiState(
      board: [
        _boardItem(
          industry: '半导体',
          zRel: 1.5,
          breadth: 0.42,
          q: 0.72,
          rawScore: 1.12,
          scoreEma: 0.96,
          rank: 1,
        ),
      ],
      isCalculating: false,
      errorMessage: null,
      latestResultDate: DateTime(2026, 2, 6),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<IndustryBuildUpService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: IndustryBuildupList(
              fullHeight: true,
              showRankingBoard: false,
            ),
          ),
        ),
      ),
    );

    final horizontalScroll = find.byKey(
      const ValueKey('industry_buildup_overview_hscroll'),
    );
    expect(horizontalScroll, findsOneWidget);
    final trendHeader = find.text('趋势').first;
    final before = tester.getTopLeft(trendHeader).dx;

    await tester.drag(horizontalScroll, const Offset(-180, 0));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(trendHeader).dx;
    expect(after, lessThan(before));
  });
}
