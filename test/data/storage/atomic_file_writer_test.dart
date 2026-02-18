import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';

class _ForcedFailure implements Exception {
  final String message;

  const _ForcedFailure(this.message);

  @override
  String toString() => 'ForcedFailure: $message';
}

void main() {
  late AtomicFileWriter writer;
  late Directory testDir;

  setUp(() async {
    writer = AtomicFileWriter();
    testDir = await Directory.systemTemp.createTemp('atomic_file_writer_test_');
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  File _targetFile() => File('${testDir.path}/state.json');

  Future<void> _writeInitialContent(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('original', flush: true);
  }

  Future<List<FileSystemEntity>> _tmpArtifacts() async {
    return testDir.list().where((entity) => entity.path.endsWith('.tmp')).toList();
  }

  test('writeAtomic writes new content successfully', () async {
    final file = _targetFile();

    await writer.writeAtomic(targetFile: file, content: utf8.encode('next'));

    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), 'next');
  });

  test('existing file remains unchanged if write fails before rename', () async {
    final file = _targetFile();
    await _writeInitialContent(file);

    await expectLater(
      writer.writeAtomic(
        targetFile: file,
        content: utf8.encode('updated'),
        onBeforeRenameForTest: (_) async {
          throw const _ForcedFailure('before rename');
        },
      ),
      throwsA(isA<_ForcedFailure>()),
    );

    expect(await file.readAsString(), 'original');
    expect(await _tmpArtifacts(), isEmpty);
  });

  test('existing file remains unchanged if rename throws', () async {
    final file = _targetFile();
    await _writeInitialContent(file);

    await expectLater(
      writer.writeAtomic(
        targetFile: file,
        content: utf8.encode('updated'),
        renameForTest: (_, __) async {
          throw const _ForcedFailure('rename');
        },
      ),
      throwsA(isA<_ForcedFailure>()),
    );

    expect(await file.readAsString(), 'original');
    expect(await _tmpArtifacts(), isEmpty);
  });
}
