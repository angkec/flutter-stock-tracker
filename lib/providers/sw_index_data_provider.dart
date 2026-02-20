import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/repository/sw_index_repository.dart';

class SwIndexDataProvider extends ChangeNotifier {
  final SwIndexRepository _repository;

  bool _isLoading = false;
  String? _lastError;
  int _cacheCodeCount = 0;
  int _dataVersion = 0;
  List<String> _lastFetchedCodes = const [];

  SwIndexDataProvider({required SwIndexRepository repository})
    : _repository = repository;

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  int get cacheCodeCount => _cacheCodeCount;
  int get dataVersion => _dataVersion;
  List<String> get lastFetchedCodes => _lastFetchedCodes;

  Future<void> refreshStats() async {
    final stats = await _repository.getCacheStats();
    _cacheCodeCount = stats.codeCount;
    _dataVersion = stats.dataVersion;
    notifyListeners();
  }

  Future<void> syncIncremental({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    await _runSync(
      () =>
          _repository.syncMissingDaily(tsCodes: tsCodes, dateRange: dateRange),
    );
  }

  Future<void> syncRefetch({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    await _runSync(
      () => _repository.refetchDaily(tsCodes: tsCodes, dateRange: dateRange),
    );
  }

  Future<void> _runSync(Future<SwIndexSyncResult> Function() runner) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await runner();
      _lastFetchedCodes = result.fetchedCodes;
      final stats = await _repository.getCacheStats();
      _cacheCodeCount = stats.codeCount;
      _dataVersion = stats.dataVersion;
    } catch (error) {
      _lastError = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
