class ProgressWatchdog {
  ProgressWatchdog({
    required Duration stallThreshold,
    required DateTime Function() now,
  }) : _stallThreshold = stallThreshold,
       _now = now;

  final Duration _stallThreshold;
  DateTime Function() _now;
  DateTime? _lastProgressAt;
  String _lastSignal = '';

  void markProgress(String signal) {
    if (signal == _lastSignal) {
      return;
    }
    _lastSignal = signal;
    _lastProgressAt = _now();
  }

  void assertNotStalled() {
    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) {
      return;
    }

    final elapsed = _now().difference(lastProgressAt);
    if (elapsed > _stallThreshold) {
      throw ProgressStalledException(
        'No business progress for ${elapsed.inSeconds}s, lastSignal=$_lastSignal',
      );
    }
  }

  DateTime? get lastProgressAt => _lastProgressAt;
  String get lastSignal => _lastSignal;
}

class ProgressStalledException implements Exception {
  ProgressStalledException(this.message);

  final String message;

  @override
  String toString() => message;
}
