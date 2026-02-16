abstract class TradingClock {
  DateTime now();
}

class SystemTradingClock implements TradingClock {
  const SystemTradingClock();

  @override
  DateTime now() => DateTime.now();
}
