// test_driver/app.dart
// 用于 flutter drive 测试的应用入口

import 'package:flutter_driver/driver_extension.dart';
import 'package:stock_rtwatcher/main.dart' as app;

void main() {
  // 启用 Flutter Driver 扩展
  enableFlutterDriverExtension();

  // 运行应用
  app.main();
}
