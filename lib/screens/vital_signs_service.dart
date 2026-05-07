import 'dart:math';
import 'package:flutter/material.dart';

// ─── Data Models ────────────────────────────────────────────────────

class VitalMeasurement {
  final DateTime timestamp;
  final double? spo2;
  final double? hr;
  final double? skinTemp;
  final double? rr;
  final double? rrResting;
  final double? hrvRmssd;
  final double? activityLevel;

  const VitalMeasurement({
    required this.timestamp,
    this.spo2,
    this.hr,
    this.skinTemp,
    this.rr,
    this.rrResting,
    this.hrvRmssd,
    this.activityLevel,
  });
}

class BaselineStats {
  final double mean;
  final double std;
  final double p10;
  final double p25;
  final double p50;
  final double p75;
  final double p90;
  final int nSamples;
  final int windowDays;

  const BaselineStats({
    required this.mean,
    required this.std,
    required this.p10,
    required this.p25,
    required this.p50,
    required this.p75,
    required this.p90,
    required this.nSamples,
    required this.windowDays,
  });

  factory BaselineStats.fromValues(List<double> values, int windowDays) {
    final n = values.length;
    final sorted = List<double>.from(values)..sort();
    final mean = values.fold(0.0, (s, v) => s + v) / n;
    final variance = values.fold(0.0, (s, v) => s + pow(v - mean, 2)) / n;
    final std = max(sqrt(variance), 1e-9);

    double pct(double p) {
      if (n == 1) return sorted[0];
      final idx = p / 100.0 * (n - 1);
      final lo = idx.floor(), hi = idx.ceil();
      return lo == hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
    }

    return BaselineStats(
      mean: mean, std: std,
      p10: pct(10), p25: pct(25), p50: pct(50), p75: pct(75), p90: pct(90),
      nSamples: n, windowDays: windowDays,
    );
  }
}

// Population norms — fallback when personal baseline < 7 days
const _normHr   = BaselineStats(mean: 70,   std: 12,  p10: 55,   p25: 62,   p50: 70,   p75: 78,   p90: 85,   nSamples: 0, windowDays: 0);
const _normSpo2 = BaselineStats(mean: 97.5, std: 1.2, p10: 96.0, p25: 97.0, p50: 98.0, p75: 99.0, p90: 99.0, nSamples: 0, windowDays: 0);
const _normTemp = BaselineStats(mean: 33.0, std: 1.2, p10: 31.5, p25: 32.5, p50: 33.0, p75: 33.8, p90: 34.5, nSamples: 0, windowDays: 0);

// ─── Wellness Score ──────────────────────────────────────────────────

class WellnessScore {
  final double shortTerm;           // 24h, 0–100
  final double longTerm;            // 28d, 0–100
  final bool usingPersonalBaseline; // false → population norm fallback

  const WellnessScore({
    required this.shortTerm,
    required this.longTerm,
    required this.usingPersonalBaseline,
  });
}

// ─── Improved NEWS2 ──────────────────────────────────────────────────

enum News2Action { recordOnly, observe24h, immediateAlert }

extension News2ActionExt on News2Action {
  String get label {
    switch (this) {
      case News2Action.recordOnly:     return '정상';
      case News2Action.observe24h:    return '경과 관찰';
      case News2Action.immediateAlert: return '즉시 경고';
    }
  }

  String get description {
    switch (this) {
      case News2Action.recordOnly:     return '결과만 기록합니다.';
      case News2Action.observe24h:    return '24시간 후 재측정을 권장합니다.';
      case News2Action.immediateAlert: return '추가 측정 및 전문가 상담을 권장합니다.';
    }
  }
}

class News2Result {
  final int total;
  final Map<String, int> items;
  final bool singleItem3;
  final News2Action action;
  final DateTime measuredAt;

  const News2Result({
    required this.total,
    required this.items,
    required this.singleItem3,
    required this.action,
    required this.measuredAt,
  });
}

// ─── Service ────────────────────────────────────────────────────────

class VitalSignsService extends ChangeNotifier {
  // Current session (per ECG measurement)
  List<int> spo2Data = [];
  List<int> heartRateData = [];
  List<double> skinTempData = [];
  DateTime? lastUpdated;

  // Rolling 28-day history for baseline computation
  final List<VitalMeasurement> _history = [];

  News2Result? lastNews2Result;
  WellnessScore? wellnessScore;

  bool get hasData =>
      spo2Data.isNotEmpty || heartRateData.isNotEmpty || skinTempData.isNotEmpty;

  // True when at least 5 personal measurements exist within the last 7 days
  bool get hasEnoughBaseline {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _history.where((m) => m.timestamp.isAfter(cutoff)).length >= 5;
  }

  void updateData({
    required List<int> spo2,
    required List<int> heartRate,
    required List<double> skinTemp,
    required DateTime timestamp,
  }) {
    spo2Data = spo2;
    heartRateData = heartRate;
    skinTempData = skinTemp;
    lastUpdated = timestamp;

    _addToHistory(VitalMeasurement(
      timestamp: timestamp,
      spo2:     spo2.isNotEmpty      ? _avgI(spo2)     : null,
      hr:       heartRate.isNotEmpty ? _avgI(heartRate) : null,
      skinTemp: skinTemp.isNotEmpty  ? _avgD(skinTemp)  : null,
    ));

    _computeScores();
    notifyListeners();
  }

  void _addToHistory(VitalMeasurement m) {
    _history.add(m);
    final cutoff = DateTime.now().subtract(const Duration(days: 28));
    _history.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }

  // ── Baseline ──────────────────────────────────────────────────────

  Map<String, BaselineStats> _computeBaseline(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final window = _history.where((m) => m.timestamp.isAfter(cutoff)).toList();
    final result = <String, BaselineStats>{};

    final hrs   = window.map((m) => m.hr).whereType<double>().toList();
    final spo2s = window.map((m) => m.spo2).whereType<double>().toList();
    final temps = window.map((m) => m.skinTemp).whereType<double>().toList();

    if (hrs.length >= 3)   result['hr']       = BaselineStats.fromValues(hrs,   days);
    if (spo2s.length >= 3) result['spo2']     = BaselineStats.fromValues(spo2s, days);
    if (temps.length >= 3) result['skinTemp'] = BaselineStats.fromValues(temps, days);
    return result;
  }

  BaselineStats _bl(Map<String, BaselineStats> computed, String key) =>
      computed[key] ??
      (key == 'hr' ? _normHr : key == 'spo2' ? _normSpo2 : _normTemp);

  // ── Wellness Score ─────────────────────────────────────────────────

  // Maps σ-distance from baseline to 0–100 score (100 = at baseline)
  double _devScore(double value, BaselineStats b) =>
      (100.0 - (value - b.mean).abs() / b.std * 25.0).clamp(0.0, 100.0);

  void _computeScores() {
    final bl28 = _computeBaseline(28);

    // Short-term (24h): current session vs 28-day baseline
    // Weights per spec (rr/hrv unavailable from current sensors → normalise remaining)
    double shortSum = 0, shortW = 0;
    if (spo2Data.isNotEmpty) {
      shortSum += _devScore(_avgI(spo2Data), _bl(bl28, 'spo2')) * 0.15;
      shortW   += 0.15;
    }
    if (heartRateData.isNotEmpty) {
      shortSum += _devScore(_avgI(heartRateData), _bl(bl28, 'hr')) * 0.25;
      shortW   += 0.25;
    }
    if (skinTempData.isNotEmpty) {
      shortSum += _devScore(_avgD(skinTempData), _bl(bl28, 'skinTemp')) * 0.10;
      shortW   += 0.10;
    }

    // Long-term (28d): history averages vs population norms
    double longSum = 0, longW = 0;
    final allSpo2 = _history.map((m) => m.spo2).whereType<double>().toList();
    final allHr   = _history.map((m) => m.hr).whereType<double>().toList();
    final allTemp = _history.map((m) => m.skinTemp).whereType<double>().toList();
    if (allSpo2.isNotEmpty) { longSum += _devScore(allSpo2.fold(0.0, (s, v) => s + v) / allSpo2.length, _normSpo2) * 0.15; longW += 0.15; }
    if (allHr.isNotEmpty)   { longSum += _devScore(allHr.fold(0.0, (s, v) => s + v)   / allHr.length,   _normHr)   * 0.25; longW += 0.25; }
    if (allTemp.isNotEmpty) { longSum += _devScore(allTemp.fold(0.0, (s, v) => s + v) / allTemp.length,  _normTemp)  * 0.10; longW += 0.10; }

    wellnessScore = WellnessScore(
      shortTerm:            shortW > 0 ? shortSum / shortW : 0.0,
      longTerm:             longW  > 0 ? longSum  / longW  : 0.0,
      usingPersonalBaseline: hasEnoughBaseline,
    );

    lastNews2Result = _computeNews2(bl28);
  }

  // ── NEWS2 ──────────────────────────────────────────────────────────

  // σ-based score (0–3)
  int _sigmaScore(double v, BaselineStats b) {
    final s = (v - b.mean).abs() / b.std;
    if (s <= 1) return 0;
    if (s <= 2) return 1;
    if (s <= 3) return 2;
    return 3;
  }

  // Standard NEWS2 absolute floor rules
  int _absSpo2(double v) => v <= 91 ? 3 : v <= 93 ? 2 : v <= 95 ? 1 : 0;
  int _absHr(double v)   => (v <= 40 || v >= 131) ? 3 : (v <= 50 || v >= 111) ? 2 : v >= 91 ? 1 : 0;
  // Skin temp thresholds (adjusted from core-temp NEWS2)
  int _absTemp(double v) => (v <= 30 || v >= 39) ? 3 : (v <= 31 || v >= 38) ? 2 : (v <= 32 || v >= 37) ? 1 : 0;

  News2Result? _computeNews2(Map<String, BaselineStats> bl28) {
    final items = <String, int>{};

    if (spo2Data.isNotEmpty) {
      final avg = _avgI(spo2Data);
      items['spo2'] = max(_sigmaScore(avg, _bl(bl28, 'spo2')), _absSpo2(avg));
    }
    if (heartRateData.isNotEmpty) {
      final avg = _avgI(heartRateData);
      items['hr'] = max(_sigmaScore(avg, _bl(bl28, 'hr')), _absHr(avg));
    }
    if (skinTempData.isNotEmpty) {
      final avg = _avgD(skinTempData);
      items['skinTemp'] = max(_sigmaScore(avg, _bl(bl28, 'skinTemp')), _absTemp(avg));
    }
    if (items.isEmpty) return null;

    final total   = items.values.fold(0, (s, v) => s + v);
    final single3 = items.values.any((s) => s >= 3);
    final action  = (total >= 4 || single3)
        ? News2Action.immediateAlert
        : total >= 1 ? News2Action.observe24h : News2Action.recordOnly;

    return News2Result(
      total: total,
      items: items,
      singleItem3: single3,
      action: action,
      measuredAt: lastUpdated ?? DateTime.now(),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  double _avgI(List<int> list) =>
      list.fold(0, (s, v) => s + v) / list.length;
  double _avgD(List<double> list) =>
      list.fold(0.0, (s, v) => s + v) / list.length;

  // ── Public getters (used by VitalSignsPage) ───────────────────────

  int get spo2Last => spo2Data.isEmpty ? 0 : spo2Data.last;
  double get spo2Avg => spo2Data.isEmpty ? 0 : _avgI(spo2Data);
  int get spo2Min => spo2Data.isEmpty ? 0 : spo2Data.reduce((a, b) => a < b ? a : b);
  int get spo2Max => spo2Data.isEmpty ? 0 : spo2Data.reduce((a, b) => a > b ? a : b);

  int get hrLast => heartRateData.isEmpty ? 0 : heartRateData.last;
  double get hrAvg => heartRateData.isEmpty ? 0 : _avgI(heartRateData);
  int get hrMin => heartRateData.isEmpty ? 0 : heartRateData.reduce((a, b) => a < b ? a : b);
  int get hrMax => heartRateData.isEmpty ? 0 : heartRateData.reduce((a, b) => a > b ? a : b);

  double get tempLast => skinTempData.isEmpty ? 0 : skinTempData.last;
  double get tempAvg => skinTempData.isEmpty ? 0 : _avgD(skinTempData);
  double get tempMin => skinTempData.isEmpty ? 0 : skinTempData.reduce((a, b) => a < b ? a : b);
  double get tempMax => skinTempData.isEmpty ? 0 : skinTempData.reduce((a, b) => a > b ? a : b);
}
