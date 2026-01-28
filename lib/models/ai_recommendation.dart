/// AI 推荐结果
class AIRecommendation {
  final String stockCode;
  final String stockName;
  final String reason;

  const AIRecommendation({
    required this.stockCode,
    required this.stockName,
    required this.reason,
  });

  factory AIRecommendation.fromJson(Map<String, dynamic> json) {
    return AIRecommendation(
      stockCode: json['code'] as String,
      stockName: json['name'] as String,
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': stockCode,
    'name': stockName,
    'reason': reason,
  };
}
