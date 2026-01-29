# Holdings Import Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Holdings tab to the watchlist screen that imports stocks from East Money screenshots via OCR.

**Architecture:** New HoldingsService for persistence (SharedPreferences), OcrService for text recognition (Google ML Kit), TabBar in WatchlistScreen to switch between Watchlist and Holdings tabs.

**Tech Stack:** Flutter, google_mlkit_text_recognition, image_picker, SharedPreferences

---

## Task 1: Add Dependencies

**Files:**
- Modify: `pubspec.yaml:30-42`

**Step 1: Add image_picker and google_mlkit_text_recognition dependencies**

Add after line 42 (`http: ^1.2.0`):

```yaml
  image_picker: ^1.1.2
  google_mlkit_text_recognition: ^0.14.0
```

**Step 2: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies resolved successfully

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add image_picker and google_mlkit_text_recognition dependencies"
```

---

## Task 2: Create HoldingsService

**Files:**
- Create: `lib/services/holdings_service.dart`
- Test: `test/services/holdings_service_test.dart`

**Step 1: Write the failing test**

Create `test/services/holdings_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';

void main() {
  group('HoldingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts with empty holdings', () {
      final service = HoldingsService();
      expect(service.holdings, isEmpty);
    });

    test('setHoldings replaces all holdings', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519', '000001']);
      expect(service.holdings, ['600519', '000001']);

      await service.setHoldings(['300750']);
      expect(service.holdings, ['300750']);
    });

    test('load restores holdings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'holdings': ['600519', '000001'],
      });
      final service = HoldingsService();
      await service.load();
      expect(service.holdings, ['600519', '000001']);
    });

    test('contains returns true for existing stock', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519']);
      expect(service.contains('600519'), isTrue);
      expect(service.contains('000001'), isFalse);
    });

    test('clear removes all holdings', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519', '000001']);
      await service.clear();
      expect(service.holdings, isEmpty);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/holdings_service_test.dart`
Expected: FAIL - cannot find holdings_service.dart

**Step 3: Write the implementation**

Create `lib/services/holdings_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持仓服务 - 管理用户从截图导入的持仓列表
class HoldingsService extends ChangeNotifier {
  static const String _storageKey = 'holdings';

  final List<String> _holdings = [];

  /// 获取持仓列表
  List<String> get holdings => List.unmodifiable(_holdings);

  /// 从 SharedPreferences 加载持仓列表
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList(_storageKey);
    _holdings.clear();
    if (stored != null) {
      _holdings.addAll(stored);
    }
    notifyListeners();
  }

  /// 设置持仓列表（替换模式）
  Future<void> setHoldings(List<String> codes) async {
    _holdings.clear();
    _holdings.addAll(codes);
    await _save();
    notifyListeners();
  }

  /// 清空持仓列表
  Future<void> clear() async {
    _holdings.clear();
    await _save();
    notifyListeners();
  }

  /// 检查股票是否在持仓列表中
  bool contains(String code) {
    return _holdings.contains(code);
  }

  /// 保存持仓列表到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _holdings);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/holdings_service_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/services/holdings_service.dart test/services/holdings_service_test.dart
git commit -m "feat: add HoldingsService for managing imported holdings"
```

---

## Task 3: Create OcrService

**Files:**
- Create: `lib/services/ocr_service.dart`
- Test: `test/services/ocr_service_test.dart`

**Step 1: Write the failing test for stock code extraction logic**

Create `test/services/ocr_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/ocr_service.dart';

void main() {
  group('OcrService.extractStockCodes', () {
    test('extracts valid 6-digit stock codes', () {
      final text = '''
        贵州茅台 600519
        平安银行 000001
        宁德时代 300750
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, containsAll(['600519', '000001', '300750']));
    });

    test('filters out invalid prefixes', () {
      final text = '''
        600519 valid
        123456 invalid prefix
        999999 invalid prefix
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('ignores non-6-digit numbers', () {
      final text = '''
        600519
        12345
        1234567
        2024
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('removes duplicates', () {
      final text = '''
        600519 贵州茅台
        600519 again
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('handles empty text', () {
      final codes = OcrService.extractStockCodes('');
      expect(codes, isEmpty);
    });

    test('extracts all valid market prefixes', () {
      final text = '''
        000001 深圳主板
        001979 深圳主板
        002415 深圳中小板
        300750 创业板
        301269 创业板
        600519 上海主板
        601318 上海主板
        603288 上海主板
        605117 上海主板
        688981 科创板
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes.length, 10);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/ocr_service_test.dart`
Expected: FAIL - cannot find ocr_service.dart

**Step 3: Write the implementation**

Create `lib/services/ocr_service.dart`:

```dart
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

/// OCR服务 - 从截图识别股票代码
class OcrService {
  static final _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.chinese,
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
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/ocr_service_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/services/ocr_service.dart test/services/ocr_service_test.dart
git commit -m "feat: add OcrService for extracting stock codes from screenshots"
```

---

## Task 4: Register HoldingsService in Provider

**Files:**
- Modify: `lib/main.dart`

**Step 1: Add import**

Add after line with `watchlist_service.dart` import:

```dart
import 'package:stock_rtwatcher/services/holdings_service.dart';
```

**Step 2: Add HoldingsService provider**

Find the `WatchlistService` provider registration and add HoldingsService after it:

```dart
ChangeNotifierProvider(create: (_) {
  final service = HoldingsService();
  service.load();
  return service;
}),
```

**Step 3: Verify app builds**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register HoldingsService in provider"
```

---

## Task 5: Create Holdings Confirm Dialog

**Files:**
- Create: `lib/widgets/holdings_confirm_dialog.dart`

**Step 1: Create the confirmation dialog widget**

Create `lib/widgets/holdings_confirm_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';

/// 持仓识别确认对话框
class HoldingsConfirmDialog extends StatefulWidget {
  final List<String> recognizedCodes;

  const HoldingsConfirmDialog({
    super.key,
    required this.recognizedCodes,
  });

  /// 显示确认对话框，返回用户确认的股票代码列表
  static Future<List<String>?> show(
    BuildContext context,
    List<String> recognizedCodes,
  ) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HoldingsConfirmDialog(recognizedCodes: recognizedCodes),
    );
  }

  @override
  State<HoldingsConfirmDialog> createState() => _HoldingsConfirmDialogState();
}

class _HoldingsConfirmDialogState extends State<HoldingsConfirmDialog> {
  late Set<String> _selectedCodes;
  final _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCodes = widget.recognizedCodes.toSet();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  void _addManualCode() {
    final code = _manualController.text.trim();
    if (code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _selectedCodes.add(code);
      });
      _manualController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.read<MarketDataProvider>();
    final stockDataMap = marketProvider.stockDataMap;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '识别结果',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '已识别 ${widget.recognizedCodes.length} 只股票，已选择 ${_selectedCodes.length} 只',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // 股票列表
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: widget.recognizedCodes.length,
                  itemBuilder: (context, index) {
                    final code = widget.recognizedCodes[index];
                    final stockData = stockDataMap[code];
                    final name = stockData?.stock.name ?? '未知';
                    final isSelected = _selectedCodes.contains(code);

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedCodes.add(code);
                          } else {
                            _selectedCodes.remove(code);
                          }
                        });
                      },
                      title: Text('$code $name'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),

              // 手动添加
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      decoration: const InputDecoration(
                        hintText: '手动添加股票代码',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      onSubmitted: (_) => _addManualCode(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addManualCode,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 确认按钮
              ElevatedButton(
                onPressed: _selectedCodes.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selectedCodes.toList()),
                child: Text('导入 ${_selectedCodes.length} 只股票'),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

**Step 2: Verify app builds**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

**Step 3: Commit**

```bash
git add lib/widgets/holdings_confirm_dialog.dart
git commit -m "feat: add HoldingsConfirmDialog for reviewing OCR results"
```

---

## Task 6: Refactor WatchlistScreen to Support Tabs

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: Add imports**

Add at the top of the file:

```dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';
import 'package:stock_rtwatcher/services/ocr_service.dart';
import 'package:stock_rtwatcher/widgets/holdings_confirm_dialog.dart';
```

**Step 2: Convert to TabBar structure**

Replace the entire `WatchlistScreen` class with:

```dart
class WatchlistScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const WatchlistScreen({super.key, this.onIndustryTap});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWatchlistCodes();
    });
  }

  void _syncWatchlistCodes() {
    final watchlistService = context.read<WatchlistService>();
    final holdingsService = context.read<HoldingsService>();
    final marketProvider = context.read<MarketDataProvider>();

    // 合并自选股和持仓的代码
    final allCodes = <String>{
      ...watchlistService.watchlist,
      ...holdingsService.holdings,
    };
    marketProvider.setWatchlistCodes(allCodes);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _addStock() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final watchlistService = context.read<WatchlistService>();
    if (!WatchlistService.isValidCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的股票代码')),
      );
      return;
    }

    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该股票已在自选列表中')),
      );
      return;
    }

    watchlistService.addStock(code);
    _codeController.clear();
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 $code')),
    );
  }

  void _removeStock(String code) {
    final watchlistService = context.read<WatchlistService>();
    watchlistService.removeStock(code);
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 $code')),
    );
  }

  void _showAIAnalysis() {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();

    final stocks = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .map((d) => d.stock)
        .toList();

    if (stocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加自选股')),
      );
      return;
    }

    AIAnalysisSheet.show(context, stocks);
  }

  Future<void> _importFromScreenshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // 显示加载指示器
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final codes = await OcrService.recognizeStockCodes(File(image.path));
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载指示器

      if (codes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未识别到股票代码')),
        );
        return;
      }

      final confirmedCodes = await HoldingsConfirmDialog.show(context, codes);
      if (confirmedCodes != null && confirmedCodes.isNotEmpty) {
        final holdingsService = context.read<HoldingsService>();
        await holdingsService.setHoldings(confirmedCodes);
        _syncWatchlistCodes();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${confirmedCodes.length} 只股票')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载指示器
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败: $e')),
      );
    }
  }

  void _removeHolding(String code) {
    final holdingsService = context.read<HoldingsService>();
    final newHoldings = holdingsService.holdings.where((c) => c != code).toList();
    holdingsService.setHoldings(newHoldings);
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 $code')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const StatusBar(),
          // TabBar
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '自选'),
              Tab(text: '持仓'),
            ],
          ),
          // Tab内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWatchlistTab(),
                _buildHoldingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistTab() {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    final watchlistData = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .toList();

    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return Column(
      children: [
        // 添加股票输入框
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    hintText: '输入股票代码',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: (_) => _addStock(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addStock,
                child: const Text('添加'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'AI 分析',
                onPressed: _showAIAnalysis,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: '设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AISettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ),
        // 自选股列表
        Expanded(
          child: watchlistData.isEmpty
              ? _buildEmptyWatchlistState(watchlistService)
              : RefreshIndicator(
                  onRefresh: () => marketProvider.refresh(),
                  child: StockTable(
                    stocks: watchlistData,
                    isLoading: marketProvider.isLoading,
                    onLongPress: (data) => _removeStock(data.stock.code),
                    onIndustryTap: widget.onIndustryTap,
                    industryTrendData: trendService.trendData,
                    todayTrendData: todayTrend,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHoldingsTab() {
    final holdingsService = context.watch<HoldingsService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    final holdingsData = marketProvider.allData
        .where((d) => holdingsService.contains(d.stock.code))
        .toList();

    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return Column(
      children: [
        // 导入按钮栏
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _importFromScreenshot,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('从截图导入'),
              ),
            ],
          ),
        ),
        // 持仓列表
        Expanded(
          child: holdingsData.isEmpty
              ? _buildEmptyHoldingsState()
              : RefreshIndicator(
                  onRefresh: () => marketProvider.refresh(),
                  child: StockTable(
                    stocks: holdingsData,
                    isLoading: marketProvider.isLoading,
                    onLongPress: (data) => _removeHolding(data.stock.code),
                    onIndustryTap: widget.onIndustryTap,
                    industryTrendData: trendService.trendData,
                    todayTrendData: todayTrend,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyWatchlistState(WatchlistService watchlistService) {
    if (watchlistService.watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无自选股',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '在上方输入股票代码添加',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.refresh,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '点击刷新按钮获取数据',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildEmptyHoldingsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '从东方财富截图导入持仓',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _importFromScreenshot,
            icon: const Icon(Icons.photo_library),
            label: const Text('选择截图'),
          ),
        ],
      ),
    );
  }
}
```

**Step 3: Verify app builds**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

**Step 4: Commit**

```bash
git add lib/screens/watchlist_screen.dart
git commit -m "feat: add Holdings tab with OCR import to WatchlistScreen"
```

---

## Task 7: Add iOS Permission Configuration

**Files:**
- Modify: `ios/Runner/Info.plist`

**Step 1: Add photo library permission**

Add before the closing `</dict>` tag:

```xml
	<key>NSPhotoLibraryUsageDescription</key>
	<string>需要访问相册以导入持仓截图</string>
	<key>NSCameraUsageDescription</key>
	<string>需要访问相机以拍摄持仓截图</string>
```

**Step 2: Commit**

```bash
git add ios/Runner/Info.plist
git commit -m "feat: add photo library and camera permissions for iOS"
```

---

## Task 8: Integration Test

**Step 1: Run app and verify**

Run: `flutter run`

Manual test checklist:
- [ ] WatchlistScreen shows two tabs: 自选 and 持仓
- [ ] 自选 tab works as before (add, remove stocks)
- [ ] 持仓 tab shows empty state with import button
- [ ] Clicking import opens image picker
- [ ] After selecting image, OCR runs and shows confirmation dialog
- [ ] Confirmation dialog allows selecting/deselecting stocks
- [ ] Confirming import replaces holdings list
- [ ] Holdings list displays correctly with stock data

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat: complete holdings import feature

- Add HoldingsService for persistent holdings storage
- Add OcrService for recognizing stock codes from screenshots
- Add HoldingsConfirmDialog for reviewing OCR results
- Refactor WatchlistScreen with TabBar (自选/持仓)
- Add iOS photo/camera permissions"
```

---

## Summary

| Task | Description | Estimated LOC |
|------|-------------|---------------|
| 1 | Add dependencies | 2 |
| 2 | Create HoldingsService | 50 + 50 test |
| 3 | Create OcrService | 40 + 60 test |
| 4 | Register provider | 5 |
| 5 | Create confirm dialog | 150 |
| 6 | Refactor WatchlistScreen | 250 |
| 7 | iOS permissions | 4 |
| 8 | Integration test | 0 |

**Total: ~550 lines of production code + ~110 lines of test code**
