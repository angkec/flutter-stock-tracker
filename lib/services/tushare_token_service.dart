import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;

  const SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}

class TushareTokenService extends ChangeNotifier {
  static const String _tokenStorageKey = 'tushare_token';

  final TokenStorage _storage;
  String? _savedToken;
  String? _tempToken;

  TushareTokenService({TokenStorage? storage})
    : _storage = storage ?? const SecureTokenStorage();

  String? get token => _tempToken ?? _savedToken;

  bool get hasToken => token != null && token!.isNotEmpty;

  String? get maskedToken {
    final value = _savedToken;
    if (value == null || value.length < 8) {
      return null;
    }
    return '${value.substring(0, 4)}****${value.substring(value.length - 4)}';
  }

  Future<void> load() async {
    _savedToken = await _storage.read(_tokenStorageKey);
    notifyListeners();
  }

  Future<void> saveToken(String value) async {
    await _storage.write(_tokenStorageKey, value);
    _savedToken = value;
    _tempToken = null;
    notifyListeners();
  }

  void setTempToken(String value) {
    _tempToken = value;
    notifyListeners();
  }

  void clearTempToken() {
    _tempToken = null;
    notifyListeners();
  }

  Future<void> deleteToken() async {
    await _storage.delete(_tokenStorageKey);
    _savedToken = null;
    _tempToken = null;
    notifyListeners();
  }
}
