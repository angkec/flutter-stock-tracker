import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';

void main() {
  group('MarketDataRepository', () {
    late MarketDataRepository repository;

    setUp(() {
      repository = MarketDataRepository();
    });

    tearDown(() async {
      await repository.dispose();
    });

    test('should implement DataRepository interface', () {
      expect(repository, isA<DataRepository>());
    });

    test('should provide status stream', () {
      expect(repository.statusStream, isA<Stream<DataStatus>>());
    });

    test('should emit initial status', () async {
      final status = await repository.statusStream.first;
      expect(status, isA<DataStatus>());
    });
  });
}
