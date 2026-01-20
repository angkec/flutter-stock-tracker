import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/utils/volume_decoder.dart';
import 'package:stock_rtwatcher/utils/gbk_decoder.dart';

/// K-line type constants
const int klineType5Min = 0;
const int klineType15Min = 1;
const int klineType30Min = 2;
const int klineType1Hour = 3;
const int klineTypeDaily = 4;
const int klineTypeWeekly = 5;
const int klineTypeMonthly = 6;
const int klineType1Min = 7;
const int klineTypeQuarterly = 10;
const int klineTypeYearly = 11;

/// TDX 协议客户端
class TdxClient {
  Socket? _socket;
  bool _isConnected = false;
  final BytesBuilder _buffer = BytesBuilder();
  Completer<void>? _dataCompleter;
  StreamSubscription<Uint8List>? _subscription;

  // 请求锁，确保同一时间只有一个请求在处理
  Completer<void>? _requestLock;

  bool get isConnected => _isConnected;

  /// 服务器列表
  static const List<Map<String, dynamic>> servers = [
    {'host': '119.147.212.81', 'port': 7709},
    {'host': '112.95.140.74', 'port': 7709},
    {'host': '114.80.63.12', 'port': 7709},
    {'host': '221.194.181.176', 'port': 7709},
    {'host': '115.238.56.198', 'port': 7709},
    {'host': '115.238.90.165', 'port': 7709},
    {'host': '124.160.88.183', 'port': 7709},
    {'host': '218.108.98.244', 'port': 7709},
    {'host': '60.12.136.250', 'port': 7709},
    {'host': '218.75.126.9', 'port': 7709},
  ];

  /// Setup 命令 (握手)
  static final _setupCmd1 = _hexToBytes('0c0218930001030003000d0001');
  static final _setupCmd2 = _hexToBytes('0c0218940001030003000d0002');
  static final _setupCmd3 = _hexToBytes(
      '0c031899000120002000db0fd5d0c9ccd6a4a8af0000008fc22540130000d500c9ccbdf0d7ea00000002');

  /// 连接到服务器
  Future<bool> connect(String host, int port) async {
    try {
      developer.log(' Connecting to $host:$port...');
      _socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));

      // 设置数据监听
      _setupSocketListener();

      // 发送握手命令
      await _sendSetupCommands();

      _isConnected = true;
      developer.log(' Connected to $host:$port successfully');
      return true;
    } catch (e) {
      developer.log(' Failed to connect to $host:$port - $e');
      _isConnected = false;
      await _cleanup();
      return false;
    }
  }

  /// 设置 Socket 数据监听
  void _setupSocketListener() {
    _subscription = _socket!.listen(
      (data) {
        _buffer.add(data);
        _dataCompleter?.complete();
        _dataCompleter = null;
      },
      onError: (error) {
        _isConnected = false;
        _dataCompleter?.completeError(error);
        _dataCompleter = null;
      },
      onDone: () {
        _isConnected = false;
        _dataCompleter?.completeError(StateError('Connection closed'));
        _dataCompleter = null;
      },
    );
  }

  /// 自动连接到可用服务器
  Future<bool> autoConnect() async {
    developer.log(' Starting autoConnect, trying ${servers.length} servers...');
    for (var i = 0; i < servers.length; i++) {
      final server = servers[i];
      developer.log(' Trying server ${i + 1}/${servers.length}: ${server['host']}:${server['port']}');
      if (await connect(server['host'], server['port'])) {
        return true;
      }
    }
    developer.log(' All servers failed to connect');
    return false;
  }

  /// 断开连接
  Future<void> disconnect() async {
    _isConnected = false;
    await _cleanup();
  }

  /// 清理资源
  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _buffer.clear();
  }

  /// 发送命令并接收响应 (带请求锁)
  Future<Uint8List> sendCommand(Uint8List packet) async {
    if (_socket == null || !_isConnected) {
      throw StateError('Not connected');
    }

    // 等待获取锁
    while (_requestLock != null) {
      await _requestLock!.future;
    }

    // 获取锁
    _requestLock = Completer<void>();

    try {
      return await _sendPacket(packet);
    } finally {
      // 释放锁
      final lock = _requestLock;
      _requestLock = null;
      lock?.complete();
    }
  }

  /// 内部发送数据包方法 (不检查连接状态，用于握手)
  Future<Uint8List> _sendPacket(Uint8List packet) async {
    if (_socket == null) {
      throw StateError('Socket not initialized');
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
      final inflated = const ZLibDecoder().decodeBytes(body);
      return Uint8List.fromList(inflated);
    }
    return body;
  }

  /// 发送握手命令
  Future<void> _sendSetupCommands() async {
    await _sendPacket(_setupCmd1);
    await _sendPacket(_setupCmd2);
    await _sendPacket(_setupCmd3);
  }

  /// 读取指定字节数
  Future<Uint8List> _readBytes(int length) async {
    // 等待直到缓冲区有足够数据
    while (_buffer.length < length) {
      _dataCompleter = Completer<void>();
      await _dataCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Read timeout', const Duration(seconds: 10));
        },
      );
    }

    // 从缓冲区取出所需数据
    final allData = _buffer.toBytes();
    final result = Uint8List.fromList(allData.sublist(0, length));

    // 保留剩余数据在缓冲区
    _buffer.clear();
    if (allData.length > length) {
      _buffer.add(allData.sublist(length));
    }

    return result;
  }

  /// 十六进制字符串转字节
  static Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

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
    pkg.add(_hexToBytes('0c0118640101060006005004'));

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
    // Minimum body size: 2 bytes for count
    if (body.length < 2) {
      throw FormatException(
          'Invalid security list response: buffer too small (${body.length} bytes, need at least 2)');
    }

    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(0, Endian.little);

    final stocks = <Stock>[];
    var pos = 2;
    const recordSize = 29; // Each stock record is 29 bytes

    for (var i = 0; i < count; i++) {
      // Check if buffer has enough data for this record
      if (pos + recordSize > body.length) {
        // Buffer exhausted before reading all expected records
        break;
      }

      // 每只股票 29 字节
      final codeBytes = body.sublist(pos, pos + 6);
      final code = String.fromCharCodes(codeBytes);

      final volUnit = byteData.getUint16(pos + 6, Endian.little);

      final nameBytes = body.sublist(pos + 8, pos + 16);
      final name = GbkDecoder.decode(nameBytes);

      final decimalPoint = body[pos + 20];
      final preCloseRaw = byteData.getUint32(pos + 21, Endian.little);
      final preClose = decodeVolume(preCloseRaw);

      pos += recordSize;

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

  /// 获取实时行情 (最多80只)
  Future<List<Quote>> getSecurityQuotes(List<(int, String)> stocks) async {
    if (stocks.isEmpty) return [];
    if (stocks.length > 80) {
      stocks = stocks.sublist(0, 80);
    }

    final stockLen = stocks.length;
    final pkgDataLen = stockLen * 7 + 12;

    final pkg = BytesBuilder();

    // 包头 (20 bytes)
    final header = ByteData(20);
    header.setUint16(0, 0x10c, Endian.little);
    header.setUint32(2, 0x02006320, Endian.little);
    header.setUint16(6, pkgDataLen, Endian.little);
    header.setUint16(8, pkgDataLen, Endian.little);
    header.setUint32(10, 0x5053e, Endian.little);
    header.setUint32(14, 0, Endian.little);
    header.setUint16(18, stockLen, Endian.little);
    pkg.add(header.buffer.asUint8List());

    // 股票列表: market(1) + code(6) = 7 bytes per stock
    for (final (market, code) in stocks) {
      final stockData = ByteData(7);
      stockData.setUint8(0, market);
      final codeBytes = code.padRight(6).codeUnits;
      for (var i = 0; i < 6; i++) {
        stockData.setUint8(1 + i, codeBytes[i]);
      }
      pkg.add(stockData.buffer.asUint8List());
    }

    final body = await sendCommand(pkg.toBytes());
    return _parseSecurityQuotes(body);
  }

  /// 解析实时行情
  List<Quote> _parseSecurityQuotes(Uint8List body) {
    // Need at least 4 bytes: 2 bytes skip + 2 bytes count
    if (body.length < 4) {
      return [];
    }

    var pos = 2; // skip 2 bytes
    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(pos, Endian.little);
    pos += 2;

    final quotes = <Quote>[];

    for (var i = 0; i < count; i++) {
      if (pos + 9 > body.length) break; // bounds check

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
    if (pos >= data.length) return (0, pos);

    int positionBit = 6;
    int byte = data[pos];
    int intData = byte & 0x3F;
    bool isNegative = (byte & 0x40) != 0;
    pos++;

    if ((byte & 0x80) != 0) {
      while (pos < data.length) {
        byte = data[pos];
        intData += (byte & 0x7F) << positionBit;
        positionBit += 7;
        pos++;
        if ((byte & 0x80) == 0) break;
      }
    }

    if (isNegative) intData = -intData;
    return (intData, pos);
  }

  /// Valid K-line category values
  static const Set<int> _validCategories = {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11};

  /// 获取K线数据
  /// [market] 市场代码 (0=深市, 1=沪市)
  /// [code] 股票代码
  /// [category] K线类型 (0=5分钟, 1=15分钟, 2=30分钟, 3=1小时, 4=日线, 5=周线, 6=月线, 7=1分钟K线, 8=分时图, 10=季线, 11=年线)
  /// [start] 起始位置 (0=最新)
  /// [count] 获取数量
  Future<List<KLine>> getSecurityBars({
    required int market,
    required String code,
    required int category,
    required int start,
    required int count,
  }) async {
    if (!_validCategories.contains(category)) {
      throw ArgumentError.value(
        category,
        'category',
        'Invalid K-line category. Valid values are: ${_validCategories.toList()..sort()}',
      );
    }
    final pkg = BytesBuilder();

    // Build header: struct.pack("<HIHHHH6sHHHHIIH", ...)
    // 0x10c(2) + 0x01016408(4) + 0x1c(2) + 0x1c(2) + 0x052d(2) = 12 bytes
    final header = ByteData(12);
    header.setUint16(0, 0x10c, Endian.little);
    header.setUint32(2, 0x01016408, Endian.little);
    header.setUint16(6, 0x1c, Endian.little);
    header.setUint16(8, 0x1c, Endian.little);
    header.setUint16(10, 0x052d, Endian.little);
    pkg.add(header.buffer.asUint8List());

    // market(2) + code(6) + category(2) + 1(2) + start(2) + count(2) + 0(4) + 0(4) + 0(2) = 26 bytes
    final params = ByteData(26);
    params.setUint16(0, market, Endian.little);

    // Write code (6 bytes, padded with nulls)
    final codeBytes = code.padRight(6, '\x00').codeUnits;
    for (var i = 0; i < 6; i++) {
      params.setUint8(2 + i, codeBytes[i]);
    }

    params.setUint16(8, category, Endian.little);
    params.setUint16(10, 1, Endian.little); // unknown field, always 1
    params.setUint16(12, start, Endian.little);
    params.setUint16(14, count, Endian.little);
    params.setUint32(16, 0, Endian.little);
    params.setUint32(20, 0, Endian.little);
    params.setUint16(24, 0, Endian.little);
    pkg.add(params.buffer.asUint8List());

    final body = await sendCommand(pkg.toBytes());
    return _parseSecurityBars(body, category);
  }

  /// 解析K线数据
  List<KLine> _parseSecurityBars(Uint8List body, int category) {
    if (body.length < 2) {
      return [];
    }

    final byteData = ByteData.sublistView(body);
    final count = byteData.getUint16(0, Endian.little);
    var pos = 2;

    final bars = <KLine>[];
    int priceBase = 0; // For differential encoding

    for (var i = 0; i < count; i++) {
      if (pos + 4 > body.length) break;

      // Parse datetime based on category
      final yearOrDate = byteData.getUint16(pos, Endian.little);
      final minOrTime = byteData.getUint16(pos + 2, Endian.little);
      pos += 4;

      final datetime = _parseDateTime(yearOrDate, minOrTime, category);

      // Parse prices using differential encoding
      final (openDiff, pos1) = _decodePrice(body, pos);
      final (closeDiff, pos2) = _decodePrice(body, pos1);
      final (highDiff, pos3) = _decodePrice(body, pos2);
      final (lowDiff, pos4) = _decodePrice(body, pos3);

      // Open is diff from previous close (priceBase)
      final openRaw = priceBase + openDiff;
      // Close/High/Low are diffs from current open
      final closeRaw = openRaw + closeDiff;
      final highRaw = openRaw + highDiff;
      final lowRaw = openRaw + lowDiff;

      // Update priceBase for next bar
      priceBase = closeRaw;

      // Parse volume and amount
      if (pos4 + 8 > body.length) break;
      final volRaw = byteData.getUint32(pos4, Endian.little);
      final amountRaw = byteData.getUint32(pos4 + 4, Endian.little);
      pos = pos4 + 8;

      final volume = decodeVolume(volRaw);
      final amount = decodeVolume(amountRaw);

      bars.add(KLine(
        datetime: datetime,
        open: openRaw / 1000.0,
        close: closeRaw / 1000.0,
        high: highRaw / 1000.0,
        low: lowRaw / 1000.0,
        volume: volume,
        amount: amount,
      ));
    }

    return bars;
  }

  /// Default DateTime used when parsing fails
  static final DateTime _defaultDateTime = DateTime(2000, 1, 1);

  /// 解析日期时间
  /// For minute bars (category < 4 or 7 or 8): yearOrDate contains date, minOrTime contains minutes
  /// For day bars (category >= 4 except 7,8): yearOrDate contains year*10000+month*100+day
  DateTime _parseDateTime(int yearOrDate, int minOrTime, int category) {
    // Minute bars: category 0,1,2,3,7,8
    final isMinuteBar = category < 4 || category == 7 || category == 8;

    int year, month, day, hour, minute;

    if (isMinuteBar) {
      // yearOrDate format: (year-2004)*2048 + month*100 + day
      year = (yearOrDate ~/ 2048) + 2004;
      final monthDay = yearOrDate % 2048;
      month = monthDay ~/ 100;
      day = monthDay % 100;

      // minOrTime is minutes from midnight
      hour = minOrTime ~/ 60;
      minute = minOrTime % 60;
    } else {
      // Day bars: yearOrDate format is yyyymmdd
      year = yearOrDate ~/ 10000;
      month = (yearOrDate % 10000) ~/ 100;
      day = yearOrDate % 100;
      hour = 0;
      minute = 0;
    }

    // Validate month and day ranges
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return _defaultDateTime;
    }

    return DateTime(year, month, day, hour, minute);
  }
}
