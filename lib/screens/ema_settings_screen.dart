import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';

class EmaSettingsScreen extends StatelessWidget {
  const EmaSettingsScreen({super.key, required this.dataType});

  final KLineDataType dataType;

  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}
