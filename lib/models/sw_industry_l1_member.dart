class SwIndustryL1Member {
  final String l1Code;
  final String l1Name;
  final String tsCode;
  final String stockName;
  final String isNew;

  const SwIndustryL1Member({
    required this.l1Code,
    required this.l1Name,
    required this.tsCode,
    required this.stockName,
    required this.isNew,
  });

  factory SwIndustryL1Member.fromTushareMap(Map<String, dynamic> map) {
    return SwIndustryL1Member(
      l1Code: map['l1_code']?.toString() ?? '',
      l1Name: map['l1_name']?.toString() ?? '',
      tsCode: map['ts_code']?.toString() ?? '',
      stockName: map['name']?.toString() ?? '',
      isNew: map['is_new']?.toString() ?? '',
    );
  }
}
