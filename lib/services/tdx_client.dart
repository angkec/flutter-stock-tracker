import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/utils/volume_decoder.dart';

/// TDX 协议客户端
class TdxClient {
  Socket? _socket;
  bool _isConnected = false;
  final BytesBuilder _buffer = BytesBuilder();
  Completer<void>? _dataCompleter;
  StreamSubscription<Uint8List>? _subscription;

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

      // 设置数据监听
      _setupSocketListener();

      // 发送握手命令
      await _sendSetupCommands();

      _isConnected = true;
      return true;
    } catch (e) {
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
        _dataCompleter?.completeError(error);
        _dataCompleter = null;
      },
      onDone: () {
        _dataCompleter?.completeError(StateError('Connection closed'));
        _dataCompleter = null;
      },
    );
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

  /// 发送命令并接收响应
  Future<Uint8List> sendCommand(Uint8List packet) async {
    if (_socket == null || !_isConnected) {
      throw StateError('Not connected');
    }
    return _sendPacket(packet);
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
      final name = _decodeGbk(nameBytes);

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
}
