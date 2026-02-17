import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class FrameTimingProbeSummary {
  const FrameTimingProbeSummary({
    required this.totalFrames,
    required this.slowFrameCount,
    required this.severeFrameCount,
    required this.freezeFrameCount,
    required this.maxFrameMs,
    required this.p95FrameMs,
  });

  final int totalFrames;
  final int slowFrameCount;
  final int severeFrameCount;
  final int freezeFrameCount;
  final int maxFrameMs;
  final int p95FrameMs;

  String toLogString() {
    return 'frames=$totalFrames,slow=$slowFrameCount,severe=$severeFrameCount,'
        'freeze=$freezeFrameCount,maxMs=$maxFrameMs,p95Ms=$p95FrameMs';
  }
}

class FrameTimingProbe {
  FrameTimingProbe({
    this.slowFrameThresholdMs = 50,
    this.severeFrameThresholdMs = 100,
    this.freezeFrameThresholdMs = 700,
  });

  final int slowFrameThresholdMs;
  final int severeFrameThresholdMs;
  final int freezeFrameThresholdMs;

  final List<FrameTiming> _timings = <FrameTiming>[];
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  FrameTimingProbeSummary stop() {
    if (_started) {
      WidgetsBinding.instance.removeTimingsCallback(_onTimings);
      _started = false;
    }
    return _buildSummary();
  }

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
  }

  FrameTimingProbeSummary _buildSummary() {
    if (_timings.isEmpty) {
      return const FrameTimingProbeSummary(
        totalFrames: 0,
        slowFrameCount: 0,
        severeFrameCount: 0,
        freezeFrameCount: 0,
        maxFrameMs: 0,
        p95FrameMs: 0,
      );
    }

    final frameCosts = _timings
        .map((timing) => timing.buildDuration + timing.rasterDuration)
        .map((duration) => duration.inMilliseconds)
        .toList(growable: false);

    var slowCount = 0;
    var severeCount = 0;
    var freezeCount = 0;
    var maxFrameMs = 0;

    for (final frameMs in frameCosts) {
      maxFrameMs = max(maxFrameMs, frameMs);
      if (frameMs >= slowFrameThresholdMs) {
        slowCount++;
      }
      if (frameMs >= severeFrameThresholdMs) {
        severeCount++;
      }
      if (frameMs >= freezeFrameThresholdMs) {
        freezeCount++;
      }
    }

    final sorted = List<int>.from(frameCosts)..sort();
    final p95Index = ((sorted.length - 1) * 0.95).round();
    final p95FrameMs = sorted[p95Index.clamp(0, sorted.length - 1)];

    return FrameTimingProbeSummary(
      totalFrames: sorted.length,
      slowFrameCount: slowCount,
      severeFrameCount: severeCount,
      freezeFrameCount: freezeCount,
      maxFrameMs: maxFrameMs,
      p95FrameMs: p95FrameMs,
    );
  }
}
