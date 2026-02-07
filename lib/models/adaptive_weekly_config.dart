enum AdaptiveWeeklyStatus { strong, weak, none }

class AdaptiveIndustryDayRecord {
  final String industry;
  final DateTime day;
  final double? z;
  final double? q;
  final double? breadth;

  const AdaptiveIndustryDayRecord({
    required this.industry,
    required this.day,
    required this.z,
    required this.q,
    required this.breadth,
  });
}

class AdaptiveCandidate {
  final String industry;
  final DateTime day;
  final double z;
  final double q;
  final double breadth;
  final double score;

  const AdaptiveCandidate({
    required this.industry,
    required this.day,
    required this.z,
    required this.q,
    required this.breadth,
    required this.score,
  });

  Map<String, dynamic> toJson() {
    return {
      'industry': industry,
      'day': _dateOnlyString(day),
      'z': z,
      'q': q,
      'breadth': breadth,
      'score': score,
    };
  }
}

class AdaptiveThresholds {
  final double z;
  final double q;
  final double breadth;

  const AdaptiveThresholds({
    required this.z,
    required this.q,
    required this.breadth,
  });

  Map<String, dynamic> toJson() {
    return {'z': z, 'q': q, 'breadth': breadth};
  }
}

class AdaptiveFloors {
  final double z;
  final double q;
  final double breadth;

  const AdaptiveFloors({this.z = 0.8, this.q = 0.5, this.breadth = 0.2});

  AdaptiveThresholds asThresholds() {
    return AdaptiveThresholds(z: z, q: q, breadth: breadth);
  }

  Map<String, dynamic> toJson() {
    return {'z': z, 'q': q, 'breadth': breadth};
  }
}

class AdaptiveBuffers {
  final double z;
  final double q;
  final double breadth;

  const AdaptiveBuffers({this.z = 0.05, this.q = 0.02, this.breadth = 0.02});
}

class AdaptiveTopKParams {
  final int k;
  final double b0;
  final double b1;
  final double minGate;
  final double maxGate;
  final AdaptiveFloors floors;
  final AdaptiveBuffers buffers;
  final double winnerRatio;
  final double winnerDiff;
  final double zP95Threshold;
  final int minRecords;

  const AdaptiveTopKParams({
    this.k = 3,
    this.b0 = 0.25,
    this.b1 = 0.50,
    this.minGate = 0.5,
    this.maxGate = 1.0,
    this.floors = const AdaptiveFloors(),
    this.buffers = const AdaptiveBuffers(),
    this.winnerRatio = 1.15,
    this.winnerDiff = 0.15,
    this.zP95Threshold = 1.0,
    int? minRecords,
  }) : minRecords = minRecords ?? k;
}

class AdaptiveWeeklyConfig {
  final String week;
  final String mode;
  final int k;
  final AdaptiveFloors floors;
  final AdaptiveThresholds thresholds;
  final List<AdaptiveCandidate> candidates;
  final AdaptiveWeeklyStatus status;

  const AdaptiveWeeklyConfig({
    required this.week,
    this.mode = 'adaptive_topk',
    required this.k,
    required this.floors,
    required this.thresholds,
    required this.candidates,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return {
      'week': week,
      'mode': mode,
      'k': k,
      'floors': floors.toJson(),
      'thresholds': thresholds.toJson(),
      'candidates': candidates.map((item) => item.toJson()).toList(),
      'status': status.name,
    };
  }
}

String _dateOnlyString(DateTime day) {
  final normalized = DateTime(day.year, day.month, day.day);
  return '${normalized.year.toString().padLeft(4, '0')}-'
      '${normalized.month.toString().padLeft(2, '0')}-'
      '${normalized.day.toString().padLeft(2, '0')}';
}
