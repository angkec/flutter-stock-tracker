class LinkedPaneLayoutResult {
  const LinkedPaneLayoutResult({
    required this.mainChartHeight,
    required this.subchartHeights,
  });

  final double mainChartHeight;
  final List<double> subchartHeights;
}

class LinkedLayoutResult {
  const LinkedLayoutResult({
    required this.containerHeight,
    required this.top,
    required this.bottom,
  });

  final double containerHeight;
  final LinkedPaneLayoutResult top;
  final LinkedPaneLayoutResult bottom;
}
