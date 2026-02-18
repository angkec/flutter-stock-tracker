import 'dart:io';

typedef AtomicWritePreRenameHook = Future<void> Function(File tempFile);
typedef AtomicRenameHook = Future<void> Function(File tempFile, String targetPath);

class AtomicFileWriter {
  const AtomicFileWriter();

  Future<void> writeAtomic({
    required File targetFile,
    required List<int> content,
    AtomicWritePreRenameHook? onBeforeRenameForTest,
    AtomicRenameHook? renameForTest,
  }) async {
    await targetFile.parent.create(recursive: true);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempFile = File('${targetFile.path}.$timestamp.tmp');

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
      } catch (_) {}
      rethrow;
    }
  }
}
