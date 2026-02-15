class KLineViewport {
  final int startIndex;
  final int visibleCount;
  final int totalCount;

  const KLineViewport({
    required this.startIndex,
    required this.visibleCount,
    required this.totalCount,
  });

  int get endIndex => (startIndex + visibleCount).clamp(0, totalCount);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KLineViewport &&
        other.startIndex == startIndex &&
        other.visibleCount == visibleCount &&
        other.totalCount == totalCount;
  }

  @override
  int get hashCode => Object.hash(startIndex, visibleCount, totalCount);
}
