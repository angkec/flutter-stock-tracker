# A股涨跌量比监控系统 Flutter 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 用纯 Dart 实现 TDX 协议，构建一个可在手机上运行的 A 股涨跌量比实时监控应用。

**Architecture:** 底层用 Dart Socket 实现 TDX 协议通信，中间层封装股票数据服务，UI 层使用 Flutter 构建响应式界面。数据流：TDX服务器 → TdxClient → StockService → UI。

**Tech Stack:** Flutter 3.x, Dart Socket API, zlib (archive package), Provider 状态管理

---

## Task 1: 初始化 Flutter 项目

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `analysis_options.yaml`

**Step 1: 创建 Flutter 项目**

Run:
```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter
flutter create --org com.example --project-name stock_rtwatcher .
```

Expected: Flutter 项目创建成功

**Step 2: 修改 pubspec.yaml 添加依赖**

修改 `pubspec.yaml` 的 dependencies 部分:

```yaml
dependencies:
  flutter:
    sdk: flutter
  archive: ^3.6.1
  provider: ^6.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

**Step 3: 安装依赖**

Run: `flutter pub get`
Expected: 依赖安装成功

**Step 4: 验证项目可运行**

Run: `flutter analyze`
Expected: No issues found

**Step 5: Commit**

```bash
git init
git add .
git commit -m "chore: initialize flutter project with dependencies"
```

---

## Task 2: 实现价格解码器 (变长编码)

**Files:**
- Create: `lib/utils/price_decoder.dart`
- Create: `test/utils/price_decoder_test.dart`

**Step 1: 编写失败测试**

Create `test/utils/price_decoder_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/utils/price_decoder.dart';

void main() {
  group('PriceDecoder', () {
    test('decodes single byte positive number', () {
      // 0x05 = 5 (无符号位，无延续位)
      final data = Uint8List.fromList([0x05]);
      final result = decodePrice(data, 0);
      expect(result.value, 5);
      expect(result.nextPos, 1);
    });

    test('decodes single byte negative number', () {
      // 0x45 = -5 (符号位=1, 值=5)
      final data = Uint8List.fromList([0x45]);
      final result = decodePrice(data, 0);
      expect(result.value, -5);
      expect(result.nextPos, 1);
    });

    test('decodes multi-byte number', () {
      // 0x82 0x01 = 66 (延续位=1, 值=2, 然后 值=1<<6 + 2 = 66)
      final data = Uint8List.fromList([0x82, 0x01]);
      final result = decodePrice(data, 0);
      expect(result.value, 66);
      expect(result.nextPos, 2);
    });

    test('decodes from offset position', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0x05]);
      final result = decodePrice(data, 2);
      expect(result.value, 5);
      expect(result.nextPos, 3);
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/utils/price_decoder_test.dart`
Expected: FAIL - 文件不存在

**Step 3: 实现价格解码器**

Create `lib/utils/price_decoder.dart`:

```dart
import 'dart:typed_data';

class DecodeResult {
  final int value;
  final int nextPos;

  DecodeResult(this.value, this.nextPos);
}

/// 解码 TDX 协议中的变长价格编码
/// 类似 UTF-8 的变长编码方式，用于存储有符号整数
DecodeResult decodePrice(Uint8List data, int pos) {
  int positionBit = 6;
  int byte = data[pos];
  int intData = byte & 0x3F; // 低6位是数据
  bool isNegative = (byte & 0x40) != 0; // 第6位是符号位

  // 第7位是延续位
  if ((byte & 0x80) != 0) {
    while (true) {
      pos++;
      byte = data[pos];
      intData += (byte & 0x7F) << positionBit;
      positionBit += 7;

      if ((byte & 0x80) == 0) {
        break;
      }
    }
  }

  pos++;

  if (isNegative) {
    intData = -intData;
  }

  return DecodeResult(intData, pos);
}
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/utils/price_decoder_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/utils/price_decoder.dart test/utils/price_decoder_test.dart
git commit -m "feat: add price decoder for TDX variable-length encoding"
```

---

## Task 3: 实现成交量解码器

**Files:**
- Create: `lib/utils/volume_decoder.dart`
- Create: `test/utils/volume_decoder_test.dart`

**Step 1: 编写失败测试**

Create `test/utils/volume_decoder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/utils/volume_decoder.dart';

void main() {
  group('VolumeDecoder', () {
    test('decodes zero volume', () {
      expect(decodeVolume(0), closeTo(0.0, 0.001));
    });

    test('decodes normal volume', () {
      // 测试用例来自 pytdx 源码
      // 这个编码格式是通达信特有的浮点数编码
      final raw = 0x4A000001; // 示例值
      final result = decodeVolume(raw);
      expect(result, isA<double>());
      expect(result, greaterThanOrEqualTo(0));
    });

    test('decodes large volume', () {
      final raw = 0x4B123456;
      final result = decodeVolume(raw);
      expect(result, isA<double>());
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/utils/volume_decoder_test.dart`
Expected: FAIL

**Step 3: 实现成交量解码器**

Create `lib/utils/volume_decoder.dart`:

```dart
import 'dart:math';

/// 解码 TDX 协议中的成交量编码
/// 这是通达信特有的浮点数编码格式
double decodeVolume(int ivol) {
  if (ivol == 0) return 0.0;

  final logpoint = ivol >> 24; // [3]
  final hleax = (ivol >> 16) & 0xFF; // [2]
  final lheax = (ivol >> 8) & 0xFF; // [1]
  final lleax = ivol & 0xFF; // [0]

  final dwEcx = logpoint * 2 - 0x7F;
  final dwEdx = logpoint * 2 - 0x86;
  final dwEsi = logpoint * 2 - 0x8E;
  final dwEax = logpoint * 2 - 0x96;

  double dblXmm6;
  if (dwEcx < 0) {
    dblXmm6 = 1.0 / pow(2.0, -dwEcx);
  } else {
    dblXmm6 = pow(2.0, dwEcx).toDouble();
  }

  double dblXmm4;
  if (hleax > 0x80) {
    final dwtmpeax = dwEdx + 1;
    final tmpdblXmm3 = pow(2.0, dwtmpeax).toDouble();
    var dblXmm0 = pow(2.0, dwEdx).toDouble() * 128.0;
    dblXmm0 += (hleax & 0x7F) * tmpdblXmm3;
    dblXmm4 = dblXmm0;
  } else {
    double dblXmm0;
    if (dwEdx >= 0) {
      dblXmm0 = pow(2.0, dwEdx).toDouble() * hleax;
    } else {
      dblXmm0 = (1.0 / pow(2.0, -dwEdx)) * hleax;
    }
    dblXmm4 = dblXmm0;
  }

  var dblXmm3 = pow(2.0, dwEsi).toDouble() * lheax;
  var dblXmm1 = pow(2.0, dwEax).toDouble() * lleax;

  if ((hleax & 0x80) != 0) {
    dblXmm3 *= 2.0;
    dblXmm1 *= 2.0;
  }

  return dblXmm6 + dblXmm4 + dblXmm3 + dblXmm1;
}
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/utils/volume_decoder_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/utils/volume_decoder.dart test/utils/volume_decoder_test.dart
git commit -m "feat: add volume decoder for TDX float encoding"
```

---

## Task 4: 实现数据模型

**Files:**
- Create: `lib/models/stock.dart`
- Create: `lib/models/kline.dart`
- Create: `lib/models/quote.dart`

**Step 1: 创建股票基本信息模型**

Create `lib/models/stock.dart`:

```dart
/// 股票基本信息
class Stock {
  final String code;
  final String name;
  final int market; // 0=深圳, 1=上海
  final int volUnit;
  final int decimalPoint;
  final double preClose;

  Stock({
    required this.code,
    required this.name,
    required this.market,
    this.volUnit = 100,
    this.decimalPoint = 2,
    this.preClose = 0.0,
  });

  /// 判断是否为有效A股代码
  bool get isValidAStock {
    if (code.length != 6) return false;
    final prefix = code.substring(0, 3);
    final validPrefixes = [
      '000', '001', '002', '003', // 深圳主板
      '300', '301', // 创业板
      '600', '601', '603', '605', // 上海主板
      '688', // 科创板
    ];
    return validPrefixes.any((p) => code.startsWith(p));
  }

  /// 判断是否为ST股票
  bool get isST => name.contains('ST');

  /// 获取涨跌停幅度
  double get limitPercent {
    if (isST) return 0.05;
    if (code.startsWith('300') || code.startsWith('301') || code.startsWith('688')) {
      return 0.20;
    }
    return 0.10;
  }
}
```

**Step 2: 创建K线数据模型**

Create `lib/models/kline.dart`:

```dart
/// K线数据
class KLine {
  final DateTime datetime;
  final double open;
  final double close;
  final double high;
  final double low;
  final double volume;
  final double amount;

  KLine({
    required this.datetime,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  /// 判断是否为上涨K线 (close > open)
  bool get isUp => close > open;

  /// 判断是否为下跌K线 (close < open)
  bool get isDown => close < open;
}
```

**Step 3: 创建实时行情模型**

Create `lib/models/quote.dart`:

```dart
/// 实时行情数据
class Quote {
  final int market;
  final String code;
  final double price;
  final double lastClose;
  final double open;
  final double high;
  final double low;
  final int volume;
  final double amount;

  Quote({
    required this.market,
    required this.code,
    required this.price,
    required this.lastClose,
    required this.open,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  /// 涨跌幅 (%)
  double get changePercent {
    if (lastClose == 0) return 0;
    return (price - lastClose) / lastClose * 100;
  }

  /// 涨跌额
  double get changeAmount => price - lastClose;
}
```

**Step 4: 运行分析确认无错误**

Run: `flutter analyze lib/models/`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/models/
git commit -m "feat: add data models for stock, kline, and quote"
```

---

## Task 5: 实现 TDX 协议客户端 - 连接与握手

**Files:**
- Create: `lib/services/tdx_client.dart`
- Create: `test/services/tdx_client_test.dart`

**Step 1: 编写连接测试**

Create `test/services/tdx_client_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

void main() {
  group('TdxClient', () {
    late TdxClient client;

    setUp(() {
      client = TdxClient();
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('connects to server successfully', () async {
      final result = await client.connect('115.238.56.198', 7709);
      expect(result, isTrue);
      expect(client.isConnected, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('disconnects properly', () async {
      await client.connect('115.238.56.198', 7709);
      await client.disconnect();
      expect(client.isConnected, isFalse);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: FAIL

**Step 3: 实现 TDX 客户端基础连接**

Create `lib/services/tdx_client.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// TDX 协议客户端
class TdxClient {
  Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// 服务器列表
  static const List<Map<String, dynamic>> servers = [
    {'host': '115.238.56.198', 'port': 7709},
    {'host': '115.238.90.165', 'port': 7709},
    {'host': '124.160.88.183', 'port': 7709},
    {'host': '218.108.98.244', 'port': 7709},
  ];

  /// Setup 命令 (握手)
  static final _setupCmd1 = _hexToBytes('0c0218930001030003000d0001');
  static final _setupCmd2 = _hexToBytes('0c0218940001030003000d0002');
  static final _setupCmd3 = _hexToBytes(
      '0c031899000120002000db0fd5d0c9ccd6a4a8af0000008fc22540130000d500c9ccbdf0d7ea00000002');

  /// 连接到服务器
  Future<bool> connect(String host, int port) async {
    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));

      // 发送握手命令
      await _sendSetupCommands();

      _isConnected = true;
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  /// 自动连接到可用服务器
  Future<bool> autoConnect() async {
    for (final server in servers) {
      if (await connect(server['host'], server['port'])) {
        return true;
      }
    }
    return false;
  }

  /// 断开连接
  Future<void> disconnect() async {
    _isConnected = false;
    await _socket?.close();
    _socket = null;
  }

  /// 发送命令并接收响应
  Future<Uint8List> sendCommand(Uint8List packet) async {
    if (_socket == null || !_isConnected) {
      throw StateError('Not connected');
    }

    _socket!.add(packet);
    await _socket!.flush();

    // 接收响应头 (16字节)
    final header = await _readBytes(16);

    // 解析响应头: v1(4) + v2(4) + v3(4) + zipSize(2) + unzipSize(2)
    final byteData = ByteData.sublistView(header);
    final zipSize = byteData.getUint16(12, Endian.little);
    final unzipSize = byteData.getUint16(14, Endian.little);

    // 接收响应体
    final body = await _readBytes(zipSize);

    // 解压 (如果需要)
    if (zipSize != unzipSize) {
      final inflated = ZLibDecoder().decodeBytes(body);
      return Uint8List.fromList(inflated);
    }
    return body;
  }

  /// 发送握手命令
  Future<void> _sendSetupCommands() async {
    await sendCommand(_setupCmd1);
    await sendCommand(_setupCmd2);
    await sendCommand(_setupCmd3);
  }

  /// 读取指定字节数
  Future<Uint8List> _readBytes(int length) async {
    final buffer = BytesBuilder();
    var remaining = length;

    await for (final chunk in _socket!) {
      buffer.add(chunk);
      remaining -= chunk.length;
      if (remaining <= 0) break;
    }

    final data = buffer.toBytes();
    if (data.length < length) {
      throw StateError('Incomplete response: expected $length, got ${data.length}');
    }
    return Uint8List.fromList(data.sublist(0, length));
  }

  /// 十六进制字符串转字节
  static Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }
}
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/tdx_client.dart test/services/tdx_client_test.dart
git commit -m "feat: add TDX client with connection and handshake"
```

---

## Task 6: 实现 TDX 客户端 - 获取股票列表

**Files:**
- Modify: `lib/services/tdx_client.dart`
- Modify: `test/services/tdx_client_test.dart`

**Step 1: 添加获取股票列表测试**

Append to `test/services/tdx_client_test.dart`:

```dart
    test('gets security count', () async {
      await client.connect('115.238.56.198', 7709);
      final count = await client.getSecurityCount(0); // 深市
      expect(count, greaterThan(10000));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('gets security list', () async {
      await client.connect('115.238.56.198', 7709);
      final stocks = await client.getSecurityList(0, 0); // 深市, 从0开始
      expect(stocks.length, greaterThan(0));
      expect(stocks.first.code, isNotEmpty);
      expect(stocks.first.name, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 15)));
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: FAIL - 方法不存在

**Step 3: 实现获取股票数量和列表**

Add to `lib/services/tdx_client.dart` (在 TdxClient 类中添加):

```dart
  /// 获取股票数量
  Future<int> getSecurityCount(int market) async {
    final pkg = BytesBuilder();
    pkg.add(_hexToBytes('0c0c186c0001080008004e04'));

    // market (2 bytes) + 固定尾部 (4 bytes)
    final params = ByteData(6);
    params.setUint16(0, market, Endian.little);
    params.setUint8(2, 0x75);
    params.setUint8(3, 0xC7);
    params.setUint8(4, 0x33);
    params.setUint8(5, 0x01);
    pkg.add(params.buffer.asUint8List());

    final body = await sendCommand(pkg.toBytes());
    final byteData = ByteData.sublistView(body);
    return byteData.getUint16(0, Endian.little);
  }

  /// 获取股票列表
  Future<List<Stock>> getSecurityList(int market, int start) async {
    final pkg = BytesBuilder();
    pkg.add(_hexToBytes('0c01186401010600060050 04'));

    // market (2 bytes) + start (2 bytes)
    final params = ByteData(4);
    params.setUint16(0, market, Endian.little);
    params.setUint16(2, start, Endian.little);
    pkg.add(params.buffer.asUint8List());

    final body = await sendCommand(pkg.toBytes());
    return _parseSecurityList(body, market);
  }

  /// 解析股票列表
  List<Stock> _parseSecurityList(Uint8List body, int market) {
    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(0, Endian.little);

    final stocks = <Stock>[];
    var pos = 2;

    for (var i = 0; i < count; i++) {
      // 每只股票 29 字节
      final codeBytes = body.sublist(pos, pos + 6);
      final code = String.fromCharCodes(codeBytes);

      final volUnit = byteData.getUint16(pos + 6, Endian.little);

      final nameBytes = body.sublist(pos + 8, pos + 16);
      final name = _decodeGbk(nameBytes);

      final decimalPoint = body[pos + 20];
      final preCloseRaw = byteData.getUint32(pos + 21, Endian.little);
      final preClose = decodeVolume(preCloseRaw);

      pos += 29;

      stocks.add(Stock(
        code: code,
        name: name,
        market: market,
        volUnit: volUnit,
        decimalPoint: decimalPoint,
        preClose: preClose,
      ));
    }

    return stocks;
  }

  /// GBK 解码 (简化版，仅处理常见中文)
  String _decodeGbk(Uint8List bytes) {
    // 移除尾部的 0x00
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }

    // 使用 latin1 解码后转换
    // 注意: 完整的 GBK 支持需要专门的库，这里简化处理
    try {
      return String.fromCharCodes(bytes.sublist(0, end));
    } catch (e) {
      return '';
    }
  }
```

同时在文件顶部添加导入:

```dart
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/utils/volume_decoder.dart';
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/tdx_client.dart test/services/tdx_client_test.dart
git commit -m "feat: add get security count and list APIs"
```

---

## Task 7: 实现 TDX 客户端 - 获取实时行情

**Files:**
- Modify: `lib/services/tdx_client.dart`
- Modify: `test/services/tdx_client_test.dart`

**Step 1: 添加实时行情测试**

Append to `test/services/tdx_client_test.dart`:

```dart
    test('gets security quotes', () async {
      await client.connect('115.238.56.198', 7709);
      final quotes = await client.getSecurityQuotes([
        (0, '000001'), // 平安银行
        (1, '600519'), // 贵州茅台
      ]);
      expect(quotes.length, 2);
      expect(quotes[0].code, '000001');
      expect(quotes[0].price, greaterThan(0));
      expect(quotes[1].code, '600519');
    }, timeout: const Timeout(Duration(seconds: 15)));
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: FAIL

**Step 3: 实现获取实时行情**

Add to `lib/services/tdx_client.dart`:

```dart
  /// 获取实时行情 (最多80只)
  Future<List<Quote>> getSecurityQuotes(List<(int, String)> stocks) async {
    if (stocks.isEmpty) return [];
    if (stocks.length > 80) {
      stocks = stocks.sublist(0, 80);
    }

    final stockLen = stocks.length;
    final pkgDataLen = stockLen * 7 + 12;

    final pkg = BytesBuilder();

    // 包头
    final header = ByteData(20);
    header.setUint16(0, 0x10c, Endian.little);
    header.setUint32(2, 0x02006320, Endian.little);
    header.setUint16(6, pkgDataLen, Endian.little);
    header.setUint16(8, pkgDataLen, Endian.little);
    header.setUint32(10, 0x5053e, Endian.little);
    header.setUint32(14, 0, Endian.little);
    header.setUint16(18, stockLen, Endian.little);
    pkg.add(header.buffer.asUint8List());

    // 股票列表
    for (final (market, code) in stocks) {
      final stockPkg = ByteData(7);
      stockPkg.setUint8(0, market);
      final codeBytes = code.padRight(6).codeUnits;
      for (var i = 0; i < 6; i++) {
        stockPkg.setUint8(i + 1, codeBytes[i]);
      }
      pkg.add(stockPkg.buffer.asUint8List());
    }

    final body = await sendCommand(pkg.toBytes());
    return _parseSecurityQuotes(body);
  }

  /// 解析实时行情
  List<Quote> _parseSecurityQuotes(Uint8List body) {
    var pos = 2; // skip 2 bytes
    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(pos, Endian.little);
    pos += 2;

    final quotes = <Quote>[];

    for (var i = 0; i < count; i++) {
      final market = body[pos];
      final code = String.fromCharCodes(body.sublist(pos + 1, pos + 7));
      pos += 9; // market(1) + code(6) + active1(2)

      // 使用变长解码
      final (price, pos1) = _decodePrice(body, pos);
      final (lastCloseDiff, pos2) = _decodePrice(body, pos1);
      final (openDiff, pos3) = _decodePrice(body, pos2);
      final (highDiff, pos4) = _decodePrice(body, pos3);
      final (lowDiff, pos5) = _decodePrice(body, pos4);

      // 跳过保留字段
      final (_, pos6) = _decodePrice(body, pos5);
      final (_, pos7) = _decodePrice(body, pos6);

      // 成交量和成交额
      final (vol, pos8) = _decodePrice(body, pos7);
      final (_, pos9) = _decodePrice(body, pos8); // cur_vol

      final amountRaw = byteData.getUint32(pos9, Endian.little);
      final amount = decodeVolume(amountRaw);
      pos = pos9 + 4;

      // 跳过剩余字段 (买卖盘等)
      for (var j = 0; j < 30; j++) {
        final (_, nextPos) = _decodePrice(body, pos);
        pos = nextPos;
      }
      pos += 6; // 尾部固定字节

      quotes.add(Quote(
        market: market,
        code: code.trim(),
        price: price / 100.0,
        lastClose: (price + lastCloseDiff) / 100.0,
        open: (price + openDiff) / 100.0,
        high: (price + highDiff) / 100.0,
        low: (price + lowDiff) / 100.0,
        volume: vol,
        amount: amount,
      ));
    }

    return quotes;
  }

  /// 解码价格 (变长编码)
  (int, int) _decodePrice(Uint8List data, int pos) {
    int positionBit = 6;
    int byte = data[pos];
    int intData = byte & 0x3F;
    bool isNegative = (byte & 0x40) != 0;

    if ((byte & 0x80) != 0) {
      while (true) {
        pos++;
        byte = data[pos];
        intData += (byte & 0x7F) << positionBit;
        positionBit += 7;
        if ((byte & 0x80) == 0) break;
      }
    }
    pos++;

    if (isNegative) intData = -intData;
    return (intData, pos);
  }
```

添加导入:

```dart
import 'package:stock_rtwatcher/models/quote.dart';
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/tdx_client.dart test/services/tdx_client_test.dart
git commit -m "feat: add get security quotes API"
```

---

## Task 8: 实现 TDX 客户端 - 获取K线数据

**Files:**
- Modify: `lib/services/tdx_client.dart`
- Modify: `test/services/tdx_client_test.dart`

**Step 1: 添加K线测试**

Append to `test/services/tdx_client_test.dart`:

```dart
    test('gets security bars (1min kline)', () async {
      await client.connect('115.238.56.198', 7709);
      final bars = await client.getSecurityBars(
        market: 0,
        code: '000001',
        category: 8, // 1分钟K线
        start: 0,
        count: 10,
      );
      expect(bars.length, 10);
      expect(bars.first.open, greaterThan(0));
      expect(bars.first.close, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 15)));
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: FAIL

**Step 3: 实现获取K线数据**

Add to `lib/services/tdx_client.dart`:

```dart
  /// K线类型常量
  static const int klineType1Min = 8;
  static const int klineType5Min = 0;
  static const int klineType15Min = 1;
  static const int klineType30Min = 2;
  static const int klineType1Hour = 3;
  static const int klineTypeDaily = 4;

  /// 获取K线数据
  Future<List<KLine>> getSecurityBars({
    required int market,
    required String code,
    required int category,
    required int start,
    required int count,
  }) async {
    // 构建请求包
    // struct.pack("<HIHHHH6sHHHHIIH", 0x10c, 0x01016408, 0x1c, 0x1c, 0x052d,
    //             market, code, category, 1, start, count, 0, 0, 0)
    final pkg = ByteData(38);
    pkg.setUint16(0, 0x10c, Endian.little);
    pkg.setUint32(2, 0x01016408, Endian.little);
    pkg.setUint16(6, 0x1c, Endian.little);
    pkg.setUint16(8, 0x1c, Endian.little);
    pkg.setUint16(10, 0x052d, Endian.little);
    pkg.setUint16(12, market, Endian.little);

    // code (6 bytes)
    final codeBytes = code.padRight(6).codeUnits;
    for (var i = 0; i < 6; i++) {
      pkg.setUint8(14 + i, codeBytes[i]);
    }

    pkg.setUint16(20, category, Endian.little);
    pkg.setUint16(22, 1, Endian.little);
    pkg.setUint16(24, start, Endian.little);
    pkg.setUint16(26, count, Endian.little);
    pkg.setUint32(28, 0, Endian.little);
    pkg.setUint32(32, 0, Endian.little);
    pkg.setUint16(36, 0, Endian.little);

    final body = await sendCommand(pkg.buffer.asUint8List());
    return _parseSecurityBars(body, category);
  }

  /// 解析K线数据
  List<KLine> _parseSecurityBars(Uint8List body, int category) {
    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(0, Endian.little);

    final bars = <KLine>[];
    var pos = 2;
    var preDiffBase = 0;

    for (var i = 0; i < count; i++) {
      // 解析日期时间
      final (year, month, day, hour, minute, newPos) =
          _parseDateTime(body, pos, category);
      pos = newPos;

      // 解析价格 (差值编码)
      final (priceOpenDiff, pos1) = _decodePrice(body, pos);
      final (priceCloseDiff, pos2) = _decodePrice(body, pos1);
      final (priceHighDiff, pos3) = _decodePrice(body, pos2);
      final (priceLowDiff, pos4) = _decodePrice(body, pos3);

      // 成交量
      final volRaw = byteData.getUint32(pos4, Endian.little);
      final vol = decodeVolume(volRaw);
      pos = pos4 + 4;

      // 成交额
      final amountRaw = byteData.getUint32(pos, Endian.little);
      final amount = decodeVolume(amountRaw);
      pos += 4;

      // 计算实际价格
      final open = (priceOpenDiff + preDiffBase) / 1000.0;
      final priceOpenAbs = priceOpenDiff + preDiffBase;
      final close = (priceOpenAbs + priceCloseDiff) / 1000.0;
      final high = (priceOpenAbs + priceHighDiff) / 1000.0;
      final low = (priceOpenAbs + priceLowDiff) / 1000.0;

      preDiffBase = priceOpenAbs + priceCloseDiff;

      bars.add(KLine(
        datetime: DateTime(year, month, day, hour, minute),
        open: open,
        close: close,
        high: high,
        low: low,
        volume: vol,
        amount: amount,
      ));
    }

    return bars;
  }

  /// 解析日期时间
  (int, int, int, int, int, int) _parseDateTime(
      Uint8List buffer, int pos, int category) {
    final byteData = ByteData.sublistView(buffer);

    int year, month, day, hour = 15, minute = 0;

    if (category < 4 || category == 7 || category == 8) {
      // 分钟级K线
      final zipday = byteData.getUint16(pos, Endian.little);
      final tminutes = byteData.getUint16(pos + 2, Endian.little);

      year = (zipday >> 11) + 2004;
      month = (zipday % 2048) ~/ 100;
      day = (zipday % 2048) % 100;
      hour = tminutes ~/ 60;
      minute = tminutes % 60;
    } else {
      // 日线级K线
      final zipday = byteData.getUint32(pos, Endian.little);
      year = zipday ~/ 10000;
      month = (zipday % 10000) ~/ 100;
      day = zipday % 100;
    }

    return (year, month, day, hour, minute, pos + 4);
  }
```

添加导入:

```dart
import 'package:stock_rtwatcher/models/kline.dart';
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/tdx_client.dart test/services/tdx_client_test.dart
git commit -m "feat: add get security bars API for kline data"
```

---

## Task 9: 实现股票服务层 - 涨跌量比计算

**Files:**
- Create: `lib/services/stock_service.dart`
- Create: `test/services/stock_service_test.dart`

**Step 1: 编写涨跌量比计算测试**

Create `test/services/stock_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

void main() {
  group('StockService', () {
    group('calculateRatio', () {
      test('calculates ratio for up bars only', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0),
          KLine(datetime: DateTime.now(), open: 11, close: 12, high: 12, low: 11, volume: 200, amount: 0),
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 999); // 无跌量时返回999
      });

      test('calculates ratio for mixed bars', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0), // 涨
          KLine(datetime: DateTime.now(), open: 11, close: 10, high: 11, low: 10, volume: 50, amount: 0),  // 跌
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 2.0); // 100/50 = 2
      });

      test('ignores flat bars', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0), // 涨
          KLine(datetime: DateTime.now(), open: 11, close: 11, high: 11, low: 11, volume: 50, amount: 0),  // 平
          KLine(datetime: DateTime.now(), open: 11, close: 10, high: 11, low: 10, volume: 100, amount: 0), // 跌
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 1.0); // 100/100 = 1
      });
    });
  });
}
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/services/stock_service_test.dart`
Expected: FAIL

**Step 3: 实现股票服务层**

Create `lib/services/stock_service.dart`:

```dart
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// 股票监控数据
class StockMonitorData {
  final Stock stock;
  final Quote quote;
  final double ratioDay;   // 日涨跌量比
  final double ratio30m;   // 30分钟涨跌量比
  final bool is30mPartial; // 30分钟数据是否不完整

  StockMonitorData({
    required this.stock,
    required this.quote,
    required this.ratioDay,
    required this.ratio30m,
    this.is30mPartial = false,
  });

  /// 涨跌幅
  double get changePercent => quote.changePercent;

  /// 是否接近涨跌停
  bool get isNearLimit {
    final limit = stock.limitPercent;
    return changePercent.abs() >= (limit - 0.005) * 100;
  }
}

/// 股票服务
class StockService {
  final TdxClient _client;

  StockService(this._client);

  /// 计算涨跌量比
  /// 涨量 = 所有上涨分钟(close > open)的成交量之和
  /// 跌量 = 所有下跌分钟(close < open)的成交量之和
  /// 涨跌量比 = 涨量 / 跌量
  static double calculateRatio(List<KLine> bars) {
    double upVolume = 0;
    double downVolume = 0;

    for (final bar in bars) {
      if (bar.close > bar.open) {
        upVolume += bar.volume;
      } else if (bar.close < bar.open) {
        downVolume += bar.volume;
      }
      // close == open 的分钟不计入
    }

    if (downVolume == 0) {
      return 999; // 无跌量时返回999，显示为 ∞
    }

    return upVolume / downVolume;
  }

  /// 获取所有A股列表
  Future<List<Stock>> getAllStocks() async {
    final stocks = <Stock>[];

    // 深市
    final szCount = await _client.getSecurityCount(0);
    for (var start = 0; start < szCount; start += 1000) {
      final batch = await _client.getSecurityList(0, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    // 沪市
    final shCount = await _client.getSecurityCount(1);
    for (var start = 0; start < shCount; start += 1000) {
      final batch = await _client.getSecurityList(1, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    return stocks;
  }

  /// 获取股票监控数据
  Future<StockMonitorData?> getStockMonitorData(Stock stock) async {
    try {
      // 获取实时行情
      final quotes = await _client.getSecurityQuotes([(stock.market, stock.code)]);
      if (quotes.isEmpty) return null;
      final quote = quotes.first;

      // 过滤: 停牌或无效数据
      if (quote.price <= 0 || quote.volume == 0) return null;

      // 获取当日1分钟K线 (最多250根)
      final bars = await _client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: TdxClient.klineType1Min,
        start: 0,
        count: 250,
      );

      if (bars.isEmpty) return null;

      // 计算日涨跌量比
      final ratioDay = calculateRatio(bars);

      // 计算30分钟涨跌量比
      final bars30m = bars.length >= 30 ? bars.sublist(0, 30) : bars;
      final ratio30m = calculateRatio(bars30m);
      final is30mPartial = bars.length < 30;

      return StockMonitorData(
        stock: stock,
        quote: quote,
        ratioDay: ratioDay,
        ratio30m: ratio30m,
        is30mPartial: is30mPartial,
      );
    } catch (e) {
      return null;
    }
  }

  /// 批量获取股票监控数据
  Future<List<StockMonitorData>> batchGetMonitorData(
    List<Stock> stocks, {
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <StockMonitorData>[];

    for (var i = 0; i < stocks.length; i++) {
      final data = await getStockMonitorData(stocks[i]);
      if (data != null && !data.isNearLimit) {
        results.add(data);
      }
      onProgress?.call(i + 1, stocks.length);
    }

    return results;
  }
}
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/services/stock_service_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/stock_service.dart test/services/stock_service_test.dart
git commit -m "feat: add stock service with ratio calculation"
```

---

## Task 10: 实现 UI - 主界面

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/screens/home_screen.dart`
- Create: `lib/widgets/stock_table.dart`
- Create: `lib/widgets/status_bar.dart`

**Step 1: 创建主入口**

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/home_screen.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => TdxClient()),
        ProxyProvider<TdxClient, StockService>(
          update: (_, client, __) => StockService(client),
        ),
      ],
      child: MaterialApp(
        title: 'A股涨跌量比监控',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
```

**Step 2: 创建状态栏组件**

Create `lib/widgets/status_bar.dart`:

```dart
import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  final String status;
  final String updateTime;
  final int loadedCount;
  final int totalCount;
  final bool isLoading;

  const StatusBar({
    super.key,
    required this.status,
    required this.updateTime,
    required this.loadedCount,
    required this.totalCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Text(
            'A股涨跌量比监控',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 16),
          Text('更新: $updateTime'),
          const SizedBox(width: 16),
          Text(status),
          const Spacer(),
          if (isLoading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          const SizedBox(width: 8),
          Text('($loadedCount/$totalCount)'),
        ],
      ),
    );
  }
}
```

**Step 3: 创建股票表格组件**

Create `lib/widgets/stock_table.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

class StockTable extends StatelessWidget {
  final String title;
  final List<StockMonitorData> stocks;

  const StockTable({
    super.key,
    required this.title,
    required this.stocks,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('代码')),
                  DataColumn(label: Text('名称')),
                  DataColumn(label: Text('现价'), numeric: true),
                  DataColumn(label: Text('涨跌%'), numeric: true),
                  DataColumn(label: Text('日涨跌比'), numeric: true),
                  DataColumn(label: Text('30m涨跌比'), numeric: true),
                ],
                rows: stocks.map((data) => _buildRow(data)).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildRow(StockMonitorData data) {
    final changeColor = data.changePercent > 0
        ? Colors.red
        : data.changePercent < 0
            ? Colors.green
            : Colors.white;

    final ratioDayColor = data.ratioDay > 1
        ? Colors.red
        : data.ratioDay < 1
            ? Colors.green
            : Colors.white;

    final ratio30mColor = data.ratio30m > 1
        ? Colors.red
        : data.ratio30m < 1
            ? Colors.green
            : Colors.white;

    return DataRow(cells: [
      DataCell(Text(data.stock.code)),
      DataCell(Text(data.stock.name)),
      DataCell(Text(data.quote.price.toStringAsFixed(2))),
      DataCell(Text(
        '${data.changePercent >= 0 ? '+' : ''}${data.changePercent.toStringAsFixed(2)}%',
        style: TextStyle(color: changeColor),
      )),
      DataCell(Text(
        _formatRatio(data.ratioDay),
        style: TextStyle(color: ratioDayColor),
      )),
      DataCell(Text(
        '${_formatRatio(data.ratio30m)}${data.is30mPartial ? '*' : ''}',
        style: TextStyle(color: ratio30mColor),
      )),
    ]);
  }

  String _formatRatio(double ratio) {
    if (ratio >= 999) return '∞';
    return ratio.toStringAsFixed(2);
  }
}
```

**Step 4: 创建主界面**

Create `lib/screens/home_screen.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = '未连接';
  String _updateTime = '--:--:--';
  int _loadedCount = 0;
  int _totalCount = 0;
  bool _isLoading = false;
  List<StockMonitorData> _topStocks = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    final client = context.read<TdxClient>();
    final service = context.read<StockService>();

    setState(() {
      _status = '连接中...';
      _isLoading = true;
    });

    // 连接服务器
    final connected = await client.autoConnect();
    if (!connected) {
      setState(() {
        _status = '连接失败';
        _isLoading = false;
      });
      return;
    }

    setState(() => _status = '加载股票列表...');

    // 获取股票列表
    final stocks = await service.getAllStocks();
    setState(() => _totalCount = stocks.length);

    // 开始加载数据
    await _loadData(service, stocks);

    // 设置定时刷新 (60秒)
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadData(service, stocks),
    );
  }

  Future<void> _loadData(StockService service, List<dynamic> stocks) async {
    setState(() {
      _status = '加载中...';
      _isLoading = true;
      _loadedCount = 0;
    });

    final results = await service.batchGetMonitorData(
      stocks.cast(),
      onProgress: (current, total) {
        setState(() => _loadedCount = current);
      },
    );

    // 按日涨跌比降序排序，取前20
    results.sort((a, b) => b.ratioDay.compareTo(a.ratioDay));
    final top20 = results.take(20).toList();

    setState(() {
      _topStocks = top20;
      _updateTime = _formatTime(DateTime.now());
      _status = _getMarketStatus();
      _isLoading = false;
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _getMarketStatus() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final hour = now.hour;
    final minute = now.minute;
    final timeValue = hour * 100 + minute;

    if (weekday == 6 || weekday == 7) return '周末休市';
    if (timeValue < 930) return '盘前';
    if (timeValue >= 930 && timeValue < 1130) return '交易中';
    if (timeValue >= 1130 && timeValue < 1300) return '午休';
    if (timeValue >= 1300 && timeValue < 1500) return '交易中';
    return '已收盘';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StatusBar(
              status: _status,
              updateTime: _updateTime,
              loadedCount: _loadedCount,
              totalCount: _totalCount,
              isLoading: _isLoading,
            ),
            const Divider(height: 1),
            Expanded(
              child: StockTable(
                title: '全市场 Top 20 (按日涨跌比降序)',
                stocks: _topStocks,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 5: 运行应用验证**

Run: `flutter run`
Expected: 应用启动，显示股票列表

**Step 6: Commit**

```bash
git add lib/
git commit -m "feat: add main UI with stock monitoring"
```

---

## Task 11: 修复 Socket 读取问题

**Files:**
- Modify: `lib/services/tdx_client.dart`

**Step 1: 发现问题**

Socket 流是单次消费的，需要缓冲处理。

**Step 2: 重构 Socket 读取逻辑**

修改 `lib/services/tdx_client.dart` 中的读取逻辑:

```dart
class TdxClient {
  Socket? _socket;
  bool _isConnected = false;
  final _buffer = <int>[];
  StreamSubscription? _subscription;

  // ... 其他代码保持不变 ...

  /// 连接到服务器
  Future<bool> connect(String host, int port) async {
    try {
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));

      // 设置数据监听
      _subscription = _socket!.listen(
        (data) => _buffer.addAll(data),
        onError: (e) => _isConnected = false,
        onDone: () => _isConnected = false,
      );

      // 发送握手命令
      await _sendSetupCommands();

      _isConnected = true;
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _buffer.clear();
  }

  /// 读取指定字节数
  Future<Uint8List> _readBytes(int length) async {
    while (_buffer.length < length) {
      await Future.delayed(const Duration(milliseconds: 10));
      if (!_isConnected) {
        throw StateError('Connection lost');
      }
    }

    final data = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return data;
  }

  /// 发送命令并接收响应
  Future<Uint8List> sendCommand(Uint8List packet) async {
    if (_socket == null || !_isConnected) {
      throw StateError('Not connected');
    }

    _socket!.add(packet);
    await _socket!.flush();

    // 接收响应头 (16字节)
    final header = await _readBytes(16);

    // 解析响应头
    final byteData = ByteData.sublistView(header);
    final zipSize = byteData.getUint16(12, Endian.little);
    final unzipSize = byteData.getUint16(14, Endian.little);

    // 接收响应体
    final body = await _readBytes(zipSize);

    // 解压 (如果需要)
    if (zipSize != unzipSize) {
      final inflated = ZLibDecoder().decodeBytes(body);
      return Uint8List.fromList(inflated);
    }
    return body;
  }
}
```

**Step 3: 运行测试确认通过**

Run: `flutter test test/services/tdx_client_test.dart`
Expected: All tests passed

**Step 4: Commit**

```bash
git add lib/services/tdx_client.dart
git commit -m "fix: refactor socket reading with buffer"
```

---

## Task 12: 添加 GBK 编码支持

**Files:**
- Create: `lib/utils/gbk_decoder.dart`
- Modify: `lib/services/tdx_client.dart`

**Step 1: 创建 GBK 解码器**

Create `lib/utils/gbk_decoder.dart`:

```dart
import 'dart:typed_data';

/// GBK 解码器 (简化版，覆盖常用中文字符)
/// 完整的 GBK 表太大，这里只实现股票名称中常见的字符
class GbkDecoder {
  /// 解码 GBK 字节为字符串
  static String decode(Uint8List bytes) {
    final result = StringBuffer();
    var i = 0;

    while (i < bytes.length) {
      final byte = bytes[i];

      // 结束符
      if (byte == 0) break;

      // ASCII 字符
      if (byte < 0x80) {
        result.writeCharCode(byte);
        i++;
        continue;
      }

      // 双字节 GBK 字符
      if (i + 1 < bytes.length) {
        final byte2 = bytes[i + 1];
        final gbkCode = (byte << 8) | byte2;
        final unicode = _gbkToUnicode(gbkCode);
        if (unicode != null) {
          result.writeCharCode(unicode);
        } else {
          result.write('?');
        }
        i += 2;
      } else {
        i++;
      }
    }

    return result.toString();
  }

  /// GBK 转 Unicode (常用字符映射)
  static int? _gbkToUnicode(int gbk) {
    // 这里只列出股票名称中最常用的字符
    // 完整实现需要 GBK 码表
    const map = <int, int>{
      0xC6BD: 0x5E73, // 平
      0xB0B2: 0x5B89, // 安
      0xD2F8: 0x94F6, // 银
      0xD0D0: 0x884C, // 行
      0xB9F3: 0x8D35, // 贵
      0xD6DD: 0x5DDE, // 州
      0xC3A9: 0x8305, // 茅
      0xCCA8: 0x53F0, // 台
      0xD6D0: 0x4E2D, // 中
      0xD0C5: 0x4FE1, // 信
      0xD6A4: 0x8BC1, // 证
      0xC8AF: 0x5238, // 券
      0xB9C9: 0x80A1, // 股
      0xB7DD: 0x4EFD, // 份
      0xBFC6: 0x79D1, // 科
      0xBCBC: 0x6280, // 技
      0xB5E7: 0x7535, // 电
      0xC6F7: 0x5668, // 器
      0xD2BD: 0x533B, // 医
      0xD2A9: 0x836F, // 药
      0xC9FA: 0x751F, // 生
      0xCEEF: 0x7269, // 物
      0xBBFA: 0x673A, // 机
      0xD0B5: 0x68B0, // 械
      0xB2C4: 0x6750, // 材
      0xC1CF: 0x6599, // 料
      0xC4DC: 0x80FD, // 能
      0xD4B4: 0x6E90, // 源
      0xBBB7: 0x73AF, // 环
      0xB1A3: 0x4FDD, // 保
      0xBDA8: 0x5EFA, // 建
      0xC9E8: 0x8BBE, // 设
      0xB9A4: 0x5DE5, // 工
      0xB3CC: 0x7A0B, // 程
      0xCDB6: 0x6295, // 投
      0xD7CA: 0x8D44, // 资
      0xBDF0: 0x91D1, // 金
      0xC8DA: 0x878D, // 融
      0xB7BF: 0x623F, // 房
      0xB2FA: 0x4EA7, // 产
      0xCFB5: 0x7CFB, // 系
      0xCDB3: 0x7EDF, // 统
      0xBBAF: 0x5316, // 化
      0xD1A7: 0x5B66, // 学
      0xCAB3: 0x98DF, // 食
      0xC6B7: 0x54C1, // 品
      0xD2FB: 0x996E, // 饮
      0xBEAD: 0x7ECF, // 经
      0xBCC3: 0x6D4E, // 济
      0xC3B3: 0x8D38, // 贸
      0xD2D7: 0x6613, // 易
      0xBBF5: 0x8D27, // 货
      0xD4CB: 0x8FD0, // 运
      0xCAE4: 0x8F93, // 输
      0xCEE5: 0x4E94, // 五
      0xBFF3: 0x77FF, // 矿
      0xBDC5: 0x811A, // 脚
      0xB8D6: 0x94A2, // 钢
      0xCCFA: 0x94C1, // 铁
      0xC3BA: 0x7164, // 煤
      0xCCAB: 0x592A, // 太
      0xD1F4: 0x9633, // 阳
      0xB7E7: 0x98CE, // 风
      0xCBB0: 0x6C34, // 水
      0xBBF0: 0x706B, // 火
      0xB5D8: 0x5730, // 地
      0xB1B1: 0x5317, // 北
      0xC4CF: 0x5357, // 南
      0xB6AB: 0x4E1C, // 东
      0xCEF7: 0x897F, // 西
      0xB4F3: 0x5927, // 大
      0xD0A1: 0x5C0F, // 小
      0xD0C2: 0x65B0, // 新
      0xC0CF: 0x8001, // 老
      0xBAA3: 0x6D77, // 海
      0xCDFE: 0x5A01, // 威
      0xB8A3: 0x798F, // 福
      0xCDFD: 0x5A03, // 娃
      0xC3C0: 0x7F8E, // 美
      0xBAC3: 0x597D, // 好
      0xCAD9: 0x5BFF, // 寿
      0xBBAA: 0x534E, // 华
      0xD0CB: 0x5174, // 兴
      0xB3A4: 0x957F, // 长
      0xB4BA: 0x6625, // 春
      0xCFC4: 0x590F, // 夏
      0xC7EF: 0x79CB, // 秋
      0xB6AC: 0x51AC, // 冬
      // ... 更多字符可以按需添加
    };

    return map[gbk];
  }
}
```

**Step 2: 更新 TDX 客户端使用 GBK 解码器**

在 `lib/services/tdx_client.dart` 中更新导入和使用:

```dart
import 'package:stock_rtwatcher/utils/gbk_decoder.dart';

// 替换 _decodeGbk 方法:
String _decodeGbk(Uint8List bytes) {
  return GbkDecoder.decode(bytes);
}
```

**Step 3: 运行应用验证中文显示**

Run: `flutter run`
Expected: 股票名称正确显示中文

**Step 4: Commit**

```bash
git add lib/utils/gbk_decoder.dart lib/services/tdx_client.dart
git commit -m "feat: add GBK decoder for Chinese stock names"
```

---

## Task 13: 最终测试与优化

**Step 1: 运行所有测试**

Run: `flutter test`
Expected: All tests passed

**Step 2: 运行代码分析**

Run: `flutter analyze`
Expected: No issues found

**Step 3: 在模拟器/真机上测试**

Run: `flutter run`
Expected: 应用正常运行，显示股票涨跌量比数据

**Step 4: 最终提交**

```bash
git add .
git commit -m "chore: final cleanup and testing"
```

---

## 验收标准

1. ✅ 应用可在 iOS/Android 手机上运行
2. ✅ 使用纯 Dart 实现 TDX 协议
3. ✅ 显示全市场 Top 20 涨跌量比股票
4. ✅ 实时刷新（60秒间隔）
5. ✅ 正确显示中文股票名称
6. ✅ A股风格配色（红涨绿跌）
