import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tushare_token_service.dart';

void main() {
  group('TushareTokenService', () {
    test('defaults to empty token state', () {
      final service = TushareTokenService();
      expect(service.hasToken, isFalse);
      expect(service.token, isNull);
      expect(service.maskedToken, isNull);
    });

    test(
      'supports save/delete and temp override using injected storage',
      () async {
        final fake = _FakeTokenStorage();
        final service = TushareTokenService(storage: fake);

        await service.load();
        expect(service.hasToken, isFalse);

        await service.saveToken('saved_token_1234');
        expect(service.hasToken, isTrue);
        expect(service.token, 'saved_token_1234');
        expect(service.maskedToken, 'save****1234');

        service.setTempToken('temp_token');
        expect(service.token, 'temp_token');

        service.clearTempToken();
        expect(service.token, 'saved_token_1234');

        await service.deleteToken();
        expect(service.hasToken, isFalse);
        expect(service.token, isNull);
        expect(service.maskedToken, isNull);
      },
    );
  });
}

class _FakeTokenStorage implements TokenStorage {
  String? _value;

  @override
  Future<void> delete(String key) async {
    _value = null;
  }

  @override
  Future<String?> read(String key) async {
    return _value;
  }

  @override
  Future<void> write(String key, String value) async {
    _value = value;
  }
}
