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
