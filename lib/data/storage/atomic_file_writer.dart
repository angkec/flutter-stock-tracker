import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

typedef AtomicWritePreRenameHook = Future<void> Function(File tempFile);
typedef AtomicRenameHook = Future<void> Function(File tempFile, String targetPath);
typedef AtomicTempTokenHook = String Function(int attempt);

class AtomicFileWriter {
  const AtomicFileWriter();

  static final Random _random = Random.secure();
  static int _sequence = 0;
  static const int _maxTempNameAttempts = 256;

  Future<void> writeAtomic({
    required File targetFile,
    required List<int> content,
    AtomicWritePreRenameHook? onBeforeRenameForTest,
    AtomicRenameHook? renameForTest,
    AtomicTempTokenHook? tempTokenForTest,
  }) async {
    await targetFile.parent.create(recursive: true);

    final tempFile = await _reserveTempFile(
      targetFile: targetFile,
      tempTokenForTest: tempTokenForTest,
    );

    try {
      await tempFile.writeAsBytes(content, flush: true);

      if (onBeforeRenameForTest != null) {
        await onBeforeRenameForTest(tempFile);
      }

      if (renameForTest != null) {
        await renameForTest(tempFile, targetFile.path);
      } else {
        await tempFile.rename(targetFile.path);
      }
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (cleanupError, cleanupStackTrace) {
        developer.log(
          'Failed to clean up temporary atomic write file: ${tempFile.path}',
          name: 'AtomicFileWriter',
          error: cleanupError,
          stackTrace: cleanupStackTrace,
        );
      }
      rethrow;
    }
  }

  Future<File> _reserveTempFile({
    required File targetFile,
    AtomicTempTokenHook? tempTokenForTest,
  }) async {
    for (var attempt = 0; attempt < _maxTempNameAttempts; attempt++) {
      final token = tempTokenForTest?.call(attempt) ?? _nextTempToken();
      final tempFile = File('${targetFile.path}.$token.tmp');
      try {
        await tempFile.create(exclusive: true);
        return tempFile;
      } on PathExistsException {
        continue;
      }
    }

    throw StateError(
      'Unable to allocate unique temp file for ${targetFile.path} after '
      '$_maxTempNameAttempts attempts',
    );
  }

  static String _nextTempToken() {
    _sequence = (_sequence + 1) & 0x7fffffff;
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final sequence = _sequence.toRadixString(16);
    final random = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$timestamp-$sequence-$random';
  }
}
