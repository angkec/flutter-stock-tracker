import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';

void main() {
  group('IndustryEmaBreadthPoint', () {
    test('creates with required fields', () {
      final point = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: 65.5,
        aboveCount: 30,
        validCount: 50,
        missingCount: 5,
      );
      expect(point.date, DateTime(2024, 1, 15));
      expect(point.percent, 65.5);
      expect(point.aboveCount, 30);
      expect(point.validCount, 50);
      expect(point.missingCount, 5);
    });

    test('percent can be null', () {
      final point = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: null,
        aboveCount: 0,
        validCount: 0,
        missingCount: 55,
      );
      expect(point.percent, isNull);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: 65.5,
        aboveCount: 30,
        validCount: 50,
        missingCount: 5,
      );
      final updated = original.copyWith(percent: 75.0, aboveCount: 35);
      expect(updated.percent, 75.0);
      expect(updated.aboveCount, 35);
      expect(updated.date, original.date);
      expect(updated.validCount, original.validCount);
    });

    test('toJson serializes correctly', () {
      final point = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: 65.5,
        aboveCount: 30,
        validCount: 50,
        missingCount: 5,
      );
      final json = point.toJson();
      expect(json['date'], '2024-01-15T00:00:00.000');
      expect(json['percent'], 65.5);
      expect(json['aboveCount'], 30);
      expect(json['validCount'], 50);
      expect(json['missingCount'], 5);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'date': '2024-01-15T00:00:00.000',
        'percent': 65.5,
        'aboveCount': 30,
        'validCount': 50,
        'missingCount': 5,
      };
      final point = IndustryEmaBreadthPoint.fromJson(json);
      expect(point.date, DateTime(2024, 1, 15));
      expect(point.percent, 65.5);
      expect(point.aboveCount, 30);
      expect(point.validCount, 50);
      expect(point.missingCount, 5);
    });

    test('fromJson handles null percent', () {
      final json = {
        'date': '2024-01-15T00:00:00.000',
        'percent': null,
        'aboveCount': 0,
        'validCount': 0,
        'missingCount': 55,
      };
      final point = IndustryEmaBreadthPoint.fromJson(json);
      expect(point.percent, isNull);
    });

    test('equality works correctly', () {
      final point1 = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: 65.5,
        aboveCount: 30,
        validCount: 50,
        missingCount: 5,
      );
      final point2 = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: 65.5,
        aboveCount: 30,
        validCount: 50,
        missingCount: 5,
      );
      expect(point1, point2);
      expect(point1.hashCode, point2.hashCode);
    });

    test('nullable percent round-trip serialization', () {
      final original = IndustryEmaBreadthPoint(
        date: DateTime(2024, 1, 15),
        percent: null,
        aboveCount: 0,
        validCount: 0,
        missingCount: 55,
      );
      final json = original.toJson();
      final restored = IndustryEmaBreadthPoint.fromJson(json);
      expect(restored.percent, isNull);
      expect(restored, original);
    });
  });

  group('IndustryEmaBreadthSeries', () {
    test('creates with required fields', () {
      final points = [
        IndustryEmaBreadthPoint(
          date: DateTime(2024, 1, 15),
          percent: 65.5,
          aboveCount: 30,
          validCount: 50,
          missingCount: 5,
        ),
      ];
      final series = IndustryEmaBreadthSeries(industry: '电子', points: points);
      expect(series.industry, '电子');
      expect(series.points.length, 1);
    });

    test('copyWith creates new instance with updated fields', () {
      final points = [
        IndustryEmaBreadthPoint(
          date: DateTime(2024, 1, 15),
          percent: 65.5,
          aboveCount: 30,
          validCount: 50,
          missingCount: 5,
        ),
      ];
      final original = IndustryEmaBreadthSeries(industry: '电子', points: points);
      final updated = original.copyWith(industry: '医药');
      expect(updated.industry, '医药');
      expect(updated.points, original.points);
    });

    test('toJson serializes correctly', () {
      final series = IndustryEmaBreadthSeries(
        industry: '电子',
        points: [
          IndustryEmaBreadthPoint(
            date: DateTime(2024, 1, 15),
            percent: 65.5,
            aboveCount: 30,
            validCount: 50,
            missingCount: 5,
          ),
        ],
      );
      final json = series.toJson();
      expect(json['industry'], '电子');
      expect((json['points'] as List).length, 1);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'industry': '电子',
        'points': [
          {
            'date': '2024-01-15T00:00:00.000',
            'percent': 65.5,
            'aboveCount': 30,
            'validCount': 50,
            'missingCount': 5,
          },
        ],
      };
      final series = IndustryEmaBreadthSeries.fromJson(json);
      expect(series.industry, '电子');
      expect(series.points.length, 1);
      expect(series.points.first.percent, 65.5);
    });

    test('sortedByDate returns points sorted ascending', () {
      final series = IndustryEmaBreadthSeries(
        industry: '电子',
        points: [
          IndustryEmaBreadthPoint(
            date: DateTime(2024, 1, 20),
            percent: 70.0,
            aboveCount: 35,
            validCount: 50,
            missingCount: 5,
          ),
          IndustryEmaBreadthPoint(
            date: DateTime(2024, 1, 15),
            percent: 65.5,
            aboveCount: 30,
            validCount: 50,
            missingCount: 5,
          ),
          IndustryEmaBreadthPoint(
            date: DateTime(2024, 1, 18),
            percent: 68.0,
            aboveCount: 32,
            validCount: 50,
            missingCount: 5,
          ),
        ],
      );
      final sorted = series.sortedByDate();
      expect(sorted.points[0].date, DateTime(2024, 1, 15));
      expect(sorted.points[1].date, DateTime(2024, 1, 18));
      expect(sorted.points[2].date, DateTime(2024, 1, 20));
    });

    test('equality works correctly', () {
      final points1 = [
        IndustryEmaBreadthPoint(
          date: DateTime(2024, 1, 15),
          percent: 65.5,
          aboveCount: 30,
          validCount: 50,
          missingCount: 5,
        ),
      ];
      final points2 = [
        IndustryEmaBreadthPoint(
          date: DateTime(2024, 1, 15),
          percent: 65.5,
          aboveCount: 30,
          validCount: 50,
          missingCount: 5,
        ),
      ];
      final series1 = IndustryEmaBreadthSeries(industry: '电子', points: points1);
      final series2 = IndustryEmaBreadthSeries(industry: '电子', points: points2);
      expect(series1, series2);
      expect(series1.hashCode, series2.hashCode);
    });
  });

  group('IndustryEmaBreadthConfig', () {
    test('creates with required fields', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      expect(config.upperThreshold, 80);
      expect(config.lowerThreshold, 20);
    });

    test('has correct defaults', () {
      final config = IndustryEmaBreadthConfig.defaults();
      expect(config.upperThreshold, 75);
      expect(config.lowerThreshold, 25);
    });

    test('isValid returns true for valid thresholds', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      expect(config.isValid, isTrue);
    });

    test('isValid returns false when lower >= upper', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 50,
        lowerThreshold: 50,
      );
      expect(config.isValid, isFalse);
    });

    test('isValid returns false when lower < 0', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: -10,
      );
      expect(config.isValid, isFalse);
    });

    test('isValid returns false when upper > 100', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 110,
        lowerThreshold: 20,
      );
      expect(config.isValid, isFalse);
    });

    test('copyWith creates new instance with updated fields', () {
      const original = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      final updated = original.copyWith(upperThreshold: 90);
      expect(updated.upperThreshold, 90);
      expect(updated.lowerThreshold, 20);
    });

    test('toJson serializes correctly', () {
      const config = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      final json = config.toJson();
      expect(json['upperThreshold'], 80);
      expect(json['lowerThreshold'], 20);
    });

    test('fromJson deserializes correctly', () {
      final json = {'upperThreshold': 80, 'lowerThreshold': 20};
      final config = IndustryEmaBreadthConfig.fromJson(json);
      expect(config.upperThreshold, 80);
      expect(config.lowerThreshold, 20);
    });

    test('fromJson uses defaults when values missing', () {
      final json = <String, dynamic>{};
      final config = IndustryEmaBreadthConfig.fromJson(json);
      expect(config.upperThreshold, 75);
      expect(config.lowerThreshold, 25);
    });

    test('fromJson falls back to defaults when invalid', () {
      final json = {'upperThreshold': 20, 'lowerThreshold': 80};
      final config = IndustryEmaBreadthConfig.fromJson(json);
      expect(config.upperThreshold, 75);
      expect(config.lowerThreshold, 25);
    });

    test('equality works correctly', () {
      const config1 = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      const config2 = IndustryEmaBreadthConfig(
        upperThreshold: 80,
        lowerThreshold: 20,
      );
      expect(config1, config2);
      expect(config1.hashCode, config2.hashCode);
    });
  });
}
