import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'data layer real e2e (full stock, real network)',
    () async {
      SharedPreferences.setMockInitialValues({});
      fail('TODO: implement real data-layer e2e');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
