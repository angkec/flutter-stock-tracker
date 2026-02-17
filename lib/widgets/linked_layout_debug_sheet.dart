import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';

class LinkedLayoutDebugSheet extends StatefulWidget {
  const LinkedLayoutDebugSheet({super.key});

  @override
  State<LinkedLayoutDebugSheet> createState() => _LinkedLayoutDebugSheetState();
}

class _LinkedLayoutDebugSheetState extends State<LinkedLayoutDebugSheet> {
  late final TextEditingController _mainMinController;
  late final TextEditingController _subMinController;

  double? _lastMainMin;
  double? _lastSubMin;

  @override
  void initState() {
    super.initState();
    _mainMinController = TextEditingController();
    _subMinController = TextEditingController();
  }

  @override
  void dispose() {
    _mainMinController.dispose();
    _subMinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LinkedLayoutConfigService>();
    _syncControllersIfNeeded(service);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('联动布局调试', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('linked_layout_main_min_input'),
              controller: _mainMinController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '主图最小高度',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('linked_layout_sub_min_input'),
              controller: _subMinController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '附图最小高度',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await service.update(
                        service.config.copyWith(
                          mainMinHeight:
                              double.tryParse(_mainMinController.text) ??
                              service.config.mainMinHeight,
                          subMinHeight:
                              double.tryParse(_subMinController.text) ??
                              service.config.subMinHeight,
                        ),
                      );
                    },
                    child: const Text('应用'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    await service.resetToDefaults();
                  },
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _syncControllersIfNeeded(LinkedLayoutConfigService service) {
    final main = service.config.mainMinHeight;
    final sub = service.config.subMinHeight;

    if (_lastMainMin == main && _lastSubMin == sub) {
      return;
    }

    _mainMinController.text = main.toStringAsFixed(0);
    _subMinController.text = sub.toStringAsFixed(0);
    _lastMainMin = main;
    _lastSubMin = sub;
  }
}
