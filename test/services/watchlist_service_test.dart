import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

void main() {
  group('WatchlistService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts with empty watchlist', () async {
      final service = WatchlistService();
      await service.load();
      expect(service.watchlist, isEmpty);
    });

    test('adds stock to watchlist', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      expect(service.watchlist, contains('000001'));
    });

    test('removes stock from watchlist', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      await service.removeStock('000001');
      expect(service.watchlist, isNot(contains('000001')));
    });

    test('persists watchlist (load in new instance)', () async {
      final service1 = WatchlistService();
      await service1.load();
      await service1.addStock('000001');
      await service1.addStock('600519');

      final service2 = WatchlistService();
      await service2.load();
      expect(service2.watchlist, contains('000001'));
      expect(service2.watchlist, contains('600519'));
    });

    test('contains returns correct value', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      expect(service.contains('000001'), isTrue);
      expect(service.contains('600519'), isFalse);
    });

    group('isValidCode', () {
      test('000001 is valid', () {
        expect(WatchlistService.isValidCode('000001'), isTrue);
      });

      test('12345 is invalid (not 6 digits)', () {
        expect(WatchlistService.isValidCode('12345'), isFalse);
      });

      test('abc123 is invalid (contains letters)', () {
        expect(WatchlistService.isValidCode('abc123'), isFalse);
      });

      test('900001 is invalid (invalid prefix)', () {
        expect(WatchlistService.isValidCode('900001'), isFalse);
      });

      test('valid prefixes are accepted', () {
        // 深圳主板
        expect(WatchlistService.isValidCode('000001'), isTrue);
        expect(WatchlistService.isValidCode('001001'), isTrue);
        expect(WatchlistService.isValidCode('002001'), isTrue);
        expect(WatchlistService.isValidCode('003001'), isTrue);
        // 深圳创业板
        expect(WatchlistService.isValidCode('300001'), isTrue);
        expect(WatchlistService.isValidCode('301001'), isTrue);
        // 上海主板
        expect(WatchlistService.isValidCode('600001'), isTrue);
        expect(WatchlistService.isValidCode('601001'), isTrue);
        expect(WatchlistService.isValidCode('603001'), isTrue);
        expect(WatchlistService.isValidCode('605001'), isTrue);
        // 上海科创板
        expect(WatchlistService.isValidCode('688001'), isTrue);
      });
    });

    group('getMarket', () {
      test('000001 returns 0 (深圳)', () {
        expect(WatchlistService.getMarket('000001'), equals(0));
      });

      test('600519 returns 1 (上海)', () {
        expect(WatchlistService.getMarket('600519'), equals(1));
      });

      test('深圳市场 (0/3 prefix) returns 0', () {
        expect(WatchlistService.getMarket('000001'), equals(0));
        expect(WatchlistService.getMarket('001001'), equals(0));
        expect(WatchlistService.getMarket('002001'), equals(0));
        expect(WatchlistService.getMarket('003001'), equals(0));
        expect(WatchlistService.getMarket('300001'), equals(0));
        expect(WatchlistService.getMarket('301001'), equals(0));
      });

      test('上海市场 (6 prefix) returns 1', () {
        expect(WatchlistService.getMarket('600001'), equals(1));
        expect(WatchlistService.getMarket('601001'), equals(1));
        expect(WatchlistService.getMarket('603001'), equals(1));
        expect(WatchlistService.getMarket('605001'), equals(1));
        expect(WatchlistService.getMarket('688001'), equals(1));
      });
    });
  });
}
