import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';

/// 生成一根K线
KLine makeBar({
  required DateTime date,
  required double open,
  required double close,
  required double high,
  required double low,
  required double volume,
}) {
  return KLine(
    datetime: date,
    open: open,
    close: close,
    high: high,
    low: low,
    volume: volume,
    amount: 0,
  );
}

/// 生成基础K线数据（用于计算均量等）
/// 返回6根普通K线，价格10-11，成交量100
List<KLine> generateBaseData({DateTime? startDate}) {
  final start = startDate ?? DateTime(2024, 1, 1);
  return List.generate(6, (i) => makeBar(
    date: start.add(Duration(days: i)),
    open: 10.0,
    close: 10.5,
    high: 11.0,
    low: 10.0,
    volume: 100.0,
  ));
}

void main() {
  group('BreakoutService - findBreakoutDays', () {
    late BreakoutService service;

    setUp(() {
      service = BreakoutService();
    });

    test('需要至少6根K线', () {
      final bars = generateBaseData().sublist(0, 5); // 只有5根
      final result = service.findBreakoutDays(bars);
      expect(result, isEmpty);
    });

    test('非上涨日不会被选中', () {
      final bars = generateBaseData();
      // 添加一根下跌日（close < open）但放量
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 12.0,
        close: 11.0, // 下跌
        high: 12.5,
        low: 10.5,
        volume: 200.0, // 放量
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse); // index 6 不应该被选中
    });

    test('不放量不会被选中', () {
      final bars = generateBaseData();
      // 添加一根上涨日但不放量
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 11.0, // 上涨
        high: 11.5,
        low: 9.5,
        volume: 100.0, // 不放量（等于均量，需要 > 1.5倍）
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse);
    });

    test('放量上涨日且有有效回踩会被选中', () {
      service.updateConfig(const BreakoutConfig(
        breakVolumeMultiplier: 1.5,
        maBreakDays: 0,
        highBreakDays: 0,
        maxUpperShadowRatio: 0,
        minPullbackDays: 1,
        maxPullbackDays: 3,
        maxTotalDrop: 0.10, // 10%
        maxSingleDayDrop: 0,
        maxSingleDayGain: 0,
        maxTotalGain: 0,
        dropReferencePoint: DropReferencePoint.breakoutClose,
        maxAvgVolumeRatio: 1.0,
      ));

      final bars = generateBaseData(); // 0-5
      // index 6: 突破日 - 放量上涨
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0, // 上涨
        high: 12.5,
        low: 10.0,
        volume: 200.0, // 2倍量，> 1.5倍
      ));
      // index 7: 回踩日1 - 小幅回落
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.5, // 相对12.0跌了4.2%，< 10%
        high: 12.0,
        low: 11.0,
        volume: 80.0, // 量比 80/200 = 0.4 < 1.0
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isTrue, reason: '突破日应该被选中');
    });
  });

  group('BreakoutService - 回踩天数逻辑', () {
    late BreakoutService service;

    setUp(() {
      service = BreakoutService();
      service.updateConfig(const BreakoutConfig(
        breakVolumeMultiplier: 1.5,
        maBreakDays: 0,
        highBreakDays: 0,
        maxUpperShadowRatio: 0,
        minPullbackDays: 1,
        maxPullbackDays: 5,
        maxTotalDrop: 0.10, // 10%
        maxSingleDayDrop: 0,
        maxSingleDayGain: 0,
        maxTotalGain: 0,
        dropReferencePoint: DropReferencePoint.breakoutClose,
        maxAvgVolumeRatio: 1.0,
      ));
    });

    test('minPullbackDays=1, maxPullbackDays=5: T+1满足条件即可', () {
      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): 有效回踩
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.5, // -4.2%
        high: 12.0,
        low: 11.0,
        volume: 80.0,
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isTrue, reason: 'T+1有效回踩，突破日应被选中');
    });

    test('minPullbackDays=2: 只有T+1数据时不满足最小天数要求', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 2,
        maxPullbackDays: 5,
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): 只有一天数据
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.5,
        high: 12.0,
        low: 11.0,
        volume: 80.0,
      ));

      // 只有T+1数据，没有T+2，不满足min=2的最小天数要求
      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse, reason: 'min=2但只有T+1数据，不应被选中');
    });

    test('minPullbackDays=2: T+1和T+2一起作为2天回踩期检测', () {
      // 此测试验证：当min=2时，T+1和T+2的数据是累计计算的
      // 比如平均量比 = (T+1量 + T+2量) / 2 / 突破日量
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 2,
        maxPullbackDays: 2,
        maxAvgVolumeRatio: 0.5, // 回踩期平均量不能超过突破日的50%
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): 量比较大 80/200=0.4
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.8,
        high: 12.0,
        low: 11.5,
        volume: 80.0,
      ));

      // index 8 (T+2): 量也较大 130/200=0.65
      // T+1+T+2平均量 = (80+130)/2 = 105, 量比 105/200 = 0.525 > 0.5
      bars.add(makeBar(
        date: DateTime(2024, 1, 9),
        open: 11.8,
        close: 11.6,
        high: 11.8,
        low: 11.3,
        volume: 130.0,
      ));

      // 平均量比=0.525 > 0.5，不满足
      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse, reason: '2天平均量比0.525超过max0.5');

      // 降低T+2的量使平均量比<=0.5
      bars[8] = makeBar(
        date: DateTime(2024, 1, 9),
        open: 11.8,
        close: 11.6,
        high: 11.8,
        low: 11.3,
        volume: 100.0, // 平均量=(80+100)/2=90, 量比90/200=0.45<=0.5
      );

      final result2 = service.findBreakoutDays(bars);
      expect(result2.contains(6), isTrue, reason: '2天平均量比0.45满足<=0.5');
    });

    test('minPullbackDays=2: 需要T+2才能成功', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 2,
        maxPullbackDays: 5,
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1)
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.8,
        high: 12.0,
        low: 11.5,
        volume: 80.0,
      ));

      // index 8 (T+2): 有效回踩点
      bars.add(makeBar(
        date: DateTime(2024, 1, 9),
        open: 11.8,
        close: 11.5, // 相对12.0跌了4.2%
        high: 11.8,
        low: 11.0,
        volume: 70.0, // 平均量 (80+70)/2=75, 量比 75/200=0.375
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isTrue, reason: 'min=2, T+2有效回踩，应被选中');
    });

    test('maxPullbackDays=3: T+4及之后不再检测', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 1,
        maxPullbackDays: 3,
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7-9 (T+1 到 T+3): 都不满足回踩条件（跌太多）
      for (int i = 0; i < 3; i++) {
        bars.add(makeBar(
          date: DateTime(2024, 1, 8 + i),
          open: 12.0 - i * 0.5,
          close: 10.0, // 跌了16.7%，超过10%
          high: 12.0 - i * 0.5,
          low: 9.5,
          volume: 80.0,
        ));
      }

      // index 10 (T+4): 满足条件但不应该被检测（超过max=3）
      bars.add(makeBar(
        date: DateTime(2024, 1, 11),
        open: 11.5,
        close: 11.5, // 回到正常
        high: 11.5,
        low: 11.0,
        volume: 50.0,
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse, reason: 'max=3, T+1到T+3都不满足，T+4不检测');
    });

    test('回踩期间跌幅过大则失败', () {
      service.updateConfig(service.config.copyWith(
        maxTotalDrop: 0.05, // 5%
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): 跌了8.3%，超过5%
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.0, // (12-11)/12 = 8.3%
        high: 12.0,
        low: 10.5,
        volume: 80.0,
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse, reason: '跌幅8.3%超过max5%');
    });

    test('回踩期间量比过大则失败', () {
      service.updateConfig(service.config.copyWith(
        maxAvgVolumeRatio: 0.5, // 回踩期平均量不能超过突破日的50%
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): 量太大
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.8,
        high: 12.0,
        low: 11.5,
        volume: 150.0, // 150/200 = 0.75 > 0.5
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isFalse, reason: '量比0.75超过max0.5');
    });
  });

  group('BreakoutService - 回踩天数边界测试', () {
    late BreakoutService service;

    /// 创建一个标准的突破+回踩场景
    /// 返回的bars中，index 6是突破日
    List<KLine> createBreakoutScenario({
      required int pullbackDays,
      bool validPullback = true,
    }) {
      final bars = generateBaseData(); // 0-5

      // index 6: 突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // 添加回踩日
      for (int i = 0; i < pullbackDays; i++) {
        bars.add(makeBar(
          date: DateTime(2024, 1, 8 + i),
          open: 12.0 - i * 0.1,
          close: validPullback ? 11.5 : 10.0, // 有效回踩4.2%，无效回踩16.7%
          high: 12.0 - i * 0.1,
          low: validPullback ? 11.0 : 9.5,
          volume: 60.0, // 量比 60/200 = 0.3
        ));
      }

      return bars;
    }

    setUp(() {
      service = BreakoutService();
      service.updateConfig(const BreakoutConfig(
        breakVolumeMultiplier: 1.5,
        maBreakDays: 0,
        highBreakDays: 0,
        maxUpperShadowRatio: 0,
        minPullbackDays: 1,
        maxPullbackDays: 5,
        maxTotalDrop: 0.10,
        maxSingleDayDrop: 0,
        maxSingleDayGain: 0,
        maxTotalGain: 0,
        dropReferencePoint: DropReferencePoint.breakoutClose,
        maxAvgVolumeRatio: 1.0,
      ));
    });

    test('边界: min=1, max=1 只检测T+1', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 1,
        maxPullbackDays: 1,
      ));

      // T+1有效
      var bars = createBreakoutScenario(pullbackDays: 1, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isTrue);

      // T+1无效
      bars = createBreakoutScenario(pullbackDays: 1, validPullback: false);
      expect(service.findBreakoutDays(bars).contains(6), isFalse);
    });

    test('边界: min=3, max=3 只检测T+3', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 3,
        maxPullbackDays: 3,
      ));

      // 只有2天回踩数据
      var bars = createBreakoutScenario(pullbackDays: 2, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isFalse,
          reason: '只有T+1,T+2数据，无法检测T+3');

      // 有3天回踩数据
      bars = createBreakoutScenario(pullbackDays: 3, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isTrue,
          reason: '有T+3数据且有效');
    });

    test('min=1, max=5: T+1和T+2失败，T+3成功', () {
      // 验证：从min开始逐个检测，直到找到第一个成功的周期
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 1,
        maxPullbackDays: 5,
        maxTotalDrop: 0.05, // 5% - 用于控制失败/成功
      ));

      final bars = generateBaseData(); // 0-5

      // index 6: 突破日，close=12.0
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));

      // index 7 (T+1): close=11.0, 跌幅=(12-11)/12=8.3% > 5% → 失败
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.0,
        high: 12.0,
        low: 10.8,
        volume: 60.0,
      ));

      // index 8 (T+2): close=10.8, 跌幅=(12-10.8)/12=10% > 5% → 2天周期也失败
      bars.add(makeBar(
        date: DateTime(2024, 1, 9),
        open: 11.0,
        close: 10.8,
        high: 11.0,
        low: 10.5,
        volume: 50.0,
      ));

      // index 9 (T+3): close=11.5, 跌幅=(12-11.5)/12=4.2% < 5% → 3天周期成功!
      bars.add(makeBar(
        date: DateTime(2024, 1, 10),
        open: 10.8,
        close: 11.5, // 反弹回来
        high: 11.6,
        low: 10.8,
        volume: 40.0,
      ));

      final result = service.findBreakoutDays(bars);
      expect(result.contains(6), isTrue,
          reason: 'T+1失败(8.3%), T+2失败(10%), 但T+3成功(4.2%), 应被选中');
    });

    test('验证检测点: min=2, max=4 应该检测T+2,T+3,T+4', () {
      service.updateConfig(service.config.copyWith(
        minPullbackDays: 2,
        maxPullbackDays: 4,
      ));

      // 只有T+1数据 - 不应成功
      var bars = createBreakoutScenario(pullbackDays: 1, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isFalse,
          reason: 'min=2, 只有T+1不够');

      // 有T+2数据 - 应该成功（在T+2检测点成功）
      bars = createBreakoutScenario(pullbackDays: 2, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isTrue,
          reason: 'min=2, T+2应该被检测');

      // 有T+3数据 - 应该成功
      bars = createBreakoutScenario(pullbackDays: 3, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isTrue);

      // 有T+4数据 - 应该成功
      bars = createBreakoutScenario(pullbackDays: 4, validPullback: true);
      expect(service.findBreakoutDays(bars).contains(6), isTrue);

      // 有T+5数据但max=4 - T+5不应被检测
      // 如果T+2到T+4都无效，T+5有效也不行
      bars = generateBaseData();
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));
      // T+1到T+4都无效（跌太多）
      for (int i = 0; i < 4; i++) {
        bars.add(makeBar(
          date: DateTime(2024, 1, 8 + i),
          open: 12.0,
          close: 10.0, // 跌16.7%
          high: 12.0,
          low: 9.5,
          volume: 60.0,
        ));
      }
      // T+5有效
      bars.add(makeBar(
        date: DateTime(2024, 1, 12),
        open: 11.5,
        close: 11.5,
        high: 11.5,
        low: 11.0,
        volume: 50.0,
      ));
      expect(service.findBreakoutDays(bars).contains(6), isFalse,
          reason: 'max=4, T+5不应被检测');
    });
  });

  group('BreakoutService - findNearMissBreakoutDays', () {
    late BreakoutService service;

    setUp(() {
      service = BreakoutService();
      service.updateConfig(const BreakoutConfig(
        breakVolumeMultiplier: 1.5,
        maBreakDays: 0,
        highBreakDays: 10,
        maxUpperShadowRatio: 0,
        minPullbackDays: 1,
        maxPullbackDays: 5,
        maxTotalDrop: 0.10,
        maxSingleDayDrop: 0,
        maxSingleDayGain: 0,
        maxTotalGain: 0,
        dropReferencePoint: DropReferencePoint.breakoutClose,
        maxAvgVolumeRatio: 1.0,
      ));
    });

    test('完全满足条件的不在近似命中中', () {
      final bars = generateBaseData();
      // 完美突破日
      bars.add(makeBar(
        date: DateTime(2024, 1, 7),
        open: 10.0,
        close: 12.0,
        high: 12.5,
        low: 10.0,
        volume: 200.0,
      ));
      // 有效回踩
      bars.add(makeBar(
        date: DateTime(2024, 1, 8),
        open: 12.0,
        close: 11.5,
        high: 12.0,
        low: 11.0,
        volume: 80.0,
      ));

      final nearMisses = service.findNearMissBreakoutDays(bars);
      expect(nearMisses.containsKey(6), isFalse);
    });

    test('差1个条件的应该在近似命中中', () {
      // 设置需要突破前10日高点
      service.updateConfig(service.config.copyWith(
        highBreakDays: 10,
      ));

      // 创建11根基础数据，其中有一根高点是12.0
      final bars = <KLine>[];
      for (int i = 0; i < 11; i++) {
        bars.add(makeBar(
          date: DateTime(2024, 1, 1 + i),
          open: 10.0,
          close: 10.5,
          high: i == 5 ? 12.0 : 11.0, // 第5根的高点是12
          low: 10.0,
          volume: 100.0,
        ));
      }

      // index 11: 放量上涨但没突破前10日高点(12.0)
      bars.add(makeBar(
        date: DateTime(2024, 1, 12),
        open: 10.0,
        close: 11.8, // 上涨，但 < 12.0
        high: 11.9,
        low: 10.0,
        volume: 200.0,
      ));

      // index 12: 有效回踩
      bars.add(makeBar(
        date: DateTime(2024, 1, 13),
        open: 11.8,
        close: 11.5,
        high: 11.8,
        low: 11.0,
        volume: 80.0,
      ));

      final nearMisses = service.findNearMissBreakoutDays(bars);
      // 应该找到index 11，差1个条件（前高突破）
      expect(nearMisses.containsKey(11), isTrue);
      expect(nearMisses[11], equals(1));
    });
  });
}
