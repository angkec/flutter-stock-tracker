import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';

class ForcedFailure implements Exception {
  final String message;

  const ForcedFailure(this.message);

  @override
  String toString() => 'ForcedFailure: $message';
}

void main() {
  late AtomicFileWriter writer;
  late Directory testDir;

  setUp(() async {
    writer = const AtomicFileWriter();
    testDir = await Directory.systemTemp.createTemp('atomic_file_writer_test_');
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  File targetFileForTest() => File('${testDir.path}/state.json');

  Future<void> writeInitialContent(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('original', flush: true);
  }

  Future<List<FileSystemEntity>> tmpArtifacts() async {
    return testDir
        .list()
        .where((entity) => entity.path.endsWith('.tmp'))
        .toList();
  }

  test('writeAtomic writes new content successfully', () async {
    final file = targetFileForTest();

    await writer.writeAtomic(targetFile: file, content: utf8.encode('next'));

    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), 'next');
  });

  test('existing file remains unchanged if write fails before rename', () async {
    final file = targetFileForTest();
    await writeInitialContent(file);

    await expectLater(
      writer.writeAtomic(
        targetFile: file,
        content: utf8.encode('updated'),
        onBeforeRenameForTest: (_) async {
          throw const ForcedFailure('before rename');
        },
      ),
      throwsA(isA<ForcedFailure>()),
    );

    expect(await file.readAsString(), 'original');
    expect(await tmpArtifacts(), isEmpty);
  });

  test('existing file remains unchanged if rename throws', () async {
    final file = targetFileForTest();
    await writeInitialContent(file);

    await expectLater(
      writer.writeAtomic(
        targetFile: file,
        content: utf8.encode('updated'),
        renameForTest: (_, __) async {
          throw const ForcedFailure('rename');
        },
      ),
      throwsA(isA<ForcedFailure>()),
    );

    expect(await file.readAsString(), 'original');
    expect(await tmpArtifacts(), isEmpty);
  });

  test('repeated writes do not leave tmp artifacts', () async {
    final file = targetFileForTest();

    await Future.wait(
      List.generate(
        50,
        (index) => writer.writeAtomic(
          targetFile: file,
          content: utf8.encode('value-$index'),
          tempTokenForTest: (attempt) {
            if (attempt == 0) {
              return 'forced-collision';
            }
            return 'forced-collision-$index-$attempt';
          },
        ),
      ),
    );

    expect(await file.exists(), isTrue);
    expect(await tmpArtifacts(), isEmpty);
  });
}
