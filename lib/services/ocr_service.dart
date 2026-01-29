import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

/// OCR服务 - 从截图识别股票代码
class OcrService {
  // 使用 latin 脚本即可识别数字（股票代码），无需加载中文模块
  static final _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// 从图片文件识别文字并提取股票代码
  static Future<List<String>> recognizeStockCodes(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    return extractStockCodes(recognizedText.text);
  }

  /// 从文本中提取有效的股票代码
  static List<String> extractStockCodes(String text) {
    // 匹配所有6位数字
    final regex = RegExp(r'\b(\d{6})\b');
    final matches = regex.allMatches(text);

    // 过滤有效的A股代码并去重
    final codes = <String>{};
    for (final match in matches) {
      final code = match.group(1)!;
      if (WatchlistService.isValidCode(code)) {
        codes.add(code);
      }
    }

    return codes.toList();
  }

  /// 释放资源
  static void dispose() {
    _textRecognizer.close();
  }
}
