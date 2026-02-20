class SwIndustryIndexMapping {
  const SwIndustryIndexMapping({
    required this.industryName,
    required this.l1Code,
    this.updatedAt,
  });

  final String industryName;
  final String l1Code;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'industry_name': industryName,
      'l1_code': l1Code,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory SwIndustryIndexMapping.fromJson(Map<String, dynamic> json) {
    final updatedAtRaw = json['updated_at']?.toString();
    return SwIndustryIndexMapping(
      industryName: json['industry_name']?.toString() ?? '',
      l1Code: json['l1_code']?.toString() ?? '',
      updatedAt: updatedAtRaw == null || updatedAtRaw.isEmpty
          ? null
          : DateTime.tryParse(updatedAtRaw),
    );
  }
}
