import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_kline_mapper.dart';

void main() {
  test('keeps range unchanged when anchor in range', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 12,
      paddingRatio: 0.08,
    );

    expect(range.minPrice, 10);
    expect(range.maxPrice, 15);
  });

  test('expands range when anchor below min', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 8,
      paddingRatio: 0.08,
    );

    expect(range.minPrice, lessThanOrEqualTo(8));
    expect(range.maxPrice, greaterThan(15));
  });

  test('expands range when anchor above max', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 18,
      paddingRatio: 0.08,
    );

    expect(range.maxPrice, greaterThanOrEqualTo(18));
    expect(range.minPrice, lessThan(10));
  });
}
