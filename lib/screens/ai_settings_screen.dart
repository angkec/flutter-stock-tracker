import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';

/// AI 设置页面
class AISettingsScreen extends StatefulWidget {
  const AISettingsScreen({super.key});

  @override
  State<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends State<AISettingsScreen> {
  final _controller = TextEditingController();
  bool _obscureText = true;
  bool _isEditing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _controller.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _controller.clear();
    });
  }

  Future<void> _saveApiKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    await context.read<AIAnalysisService>().saveApiKey(key);
    setState(() {
      _isEditing = false;
      _controller.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 已保存')),
      );
    }
  }

  Future<void> _deleteApiKey() async {
    final aiService = context.read<AIAnalysisService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除已保存的 API Key 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await aiService.deleteApiKey();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('API Key 已删除')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiService = context.watch<AIAnalysisService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'DeepSeek API Key',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _controller,
                    obscureText: _obscureText,
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxx',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureText = !_obscureText),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _cancelEditing,
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveApiKey,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ListTile(
              title: Text(
                aiService.hasApiKey ? aiService.maskedApiKey ?? '已配置' : '未配置',
              ),
              subtitle: const Text('用于 AI 选股分析'),
              trailing: aiService.hasApiKey
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _startEditing,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: _deleteApiKey,
                        ),
                      ],
                    )
                  : FilledButton(
                      onPressed: _startEditing,
                      child: const Text('配置'),
                    ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '说明：\n'
              '• API Key 用于调用 DeepSeek AI 进行股票分析\n'
              '• 获取地址: platform.deepseek.com\n'
              '• Key 会加密保存在本地，不会上传到任何服务器',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
