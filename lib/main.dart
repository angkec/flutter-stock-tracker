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
