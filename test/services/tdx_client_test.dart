import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

void main() {
  group('TdxClient', () {
    late TdxClient client;

    setUp(() {
      client = TdxClient();
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('connects to server successfully', () async {
      final result = await client.connect('115.238.56.198', 7709);
      expect(result, isTrue);
      expect(client.isConnected, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('disconnects properly', () async {
      await client.connect('115.238.56.198', 7709);
      await client.disconnect();
      expect(client.isConnected, isFalse);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
