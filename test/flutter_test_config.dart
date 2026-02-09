import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbRoot = await Directory.systemTemp.createTemp(
    'sqflite_flutter_test_',
  );
  await databaseFactory.setDatabasesPath(dbRoot.path);

  try {
    await testMain();
  } finally {
    if (await dbRoot.exists()) {
      await dbRoot.delete(recursive: true);
    }
  }
}
