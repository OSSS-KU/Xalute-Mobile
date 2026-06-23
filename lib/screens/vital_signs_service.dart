import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'daily_report_store.dart';

// ─── Data Models ────────────────────────────────────────────────────

class VitalMeasurement {
  final DateTime timestamp;
  final double? spo2;
  final double? hr;
  final double? skinTemp;
  final double? rr;
  final double? rrResting;
  final double? hrvRmssd;
  final double? sleepHrMin;
  final double? activityLevel;

  const VitalMeasurement({
    required this.timestamp,
    this.spo2,
    this.hr,
    this.skinTemp,
    this.rr,
    this.rrResting,
    this.hrvRmssd,
    this.sleepHrMin,
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
// 야간 RMSSD 성인 대략치 (개인 baseline 7일 미만 시 fallback) — 높을수록 좋음
const _normHrv  = BaselineStats(mean: 40.0, std: 20.0, p10: 18.0, p25: 26.0, p50: 38.0, p75: 52.0, p90: 68.0, nSamples: 0, windowDays: 0);

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
  static const _baseUrl = 'http://35.216.60.242:9101';

  // Current session (per ECG measurement)
  List<int> spo2Data = [];
  List<int> heartRateData = [];
  List<double> skinTempData = [];
  DateTime? lastUpdated;

  // 수면 측정값 (워치 SleepHrvService 회복 창에서 산출)
  double? sleepHrMin;     // 수면 최저심박 (bpm)
  double? hrvRmssd;       // 회복 창 RMSSD (ms)
  List<double> sleepHrSeries = [];
  List<double> sleepRmssdSeries = [];

  // Rolling 28-day history for baseline computation
  final List<VitalMeasurement> _history = [];

  News2Result? lastNews2Result;
  WellnessScore? wellnessScore;

  // 날짜별 점수 스냅샷 저장소 (main.dart에서 주입)
  DailyReportStore? dailyStore;

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

    saveToBackend(spo2: spo2, heartRate: heartRate, skinTemp: skinTemp, timestamp: timestamp)
        .catchError((e) => debugPrint('⚠️ 바이탈 서버 저장 실패: $e'));
  }

  Future<void> fetchVitalSigns() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다');

    final uid = user.uid;
    final token = await user.getIdToken();

    final uri = Uri.parse('$_baseUrl/query/vitalSigns?uid=${Uri.encodeComponent(uid)}&limit=1');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('서버 오류: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>;

    if (data.isEmpty) {
      throw PlatformException(code: 'NO_DATA');
    }

    final latest = data[0] as Map<String, dynamic>;
    final components = latest['component'] as List<dynamic>;
    final effectiveDateTime = DateTime.parse(latest['effectiveDateTime'] as String).toLocal();

    List<int> spo2 = [];
    List<int> heartRate = [];
    List<double> skinTemp = [];
    double? sleepHrMinVal;
    double? hrvRmssdVal;
    List<double> hrSeries = const [];
    List<double> rmssdSeries = const [];

    for (final comp in components) {
      final code = comp['code'] as String;
      final values = comp['values'] as List<dynamic>;
      switch (code) {
        case 'SpO2':
          spo2 = values.map((e) => (e as num).toInt()).toList();
          break;
        case 'HeartRate':
          heartRate = values.map((e) => (e as num).toInt()).toList();
          break;
        case 'SkinTemperature':
          skinTemp = values.map((e) => (e as num).toDouble()).toList();
          break;
        case 'SleepHeartRateMin':
          if (values.isNotEmpty) sleepHrMinVal = (values.first as num).toDouble();
          break;
        case 'SleepHRV_RMSSD':
          if (values.isNotEmpty) hrvRmssdVal = (values.first as num).toDouble();
          break;
        case 'SleepHR_Series':
          hrSeries = values.map((e) => (e as num).toDouble()).toList();
          break;
        case 'SleepHRV_RMSSD_Series':
          rmssdSeries = values.map((e) => (e as num).toDouble()).toList();
          break;
      }
    }

    if (spo2.isNotEmpty || heartRate.isNotEmpty || skinTemp.isNotEmpty) {
      updateData(spo2: spo2, heartRate: heartRate, skinTemp: skinTemp, timestamp: effectiveDateTime);
    }
    if (sleepHrMinVal != null && hrvRmssdVal != null) {
      // 서버에서 읽어온 값이므로 재저장 안 함(persist:false)
      ingestSleepHrv(
        sleepHrMin: sleepHrMinVal, hrvRmssd: hrvRmssdVal, timestamp: effectiveDateTime,
        hrSeries: hrSeries, rmssdSeries: rmssdSeries,
      );
    }
  }

  Future<void> saveToBackend({
    required List<int> spo2,
    required List<int> heartRate,
    required List<double> skinTemp,
    required DateTime timestamp,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final components = <Map<String, dynamic>>[];
    if (spo2.isNotEmpty) components.add({'code': 'SpO2', 'unit': '%', 'values': spo2});
    if (heartRate.isNotEmpty) components.add({'code': 'HeartRate', 'unit': 'bpm', 'values': heartRate});
    if (skinTemp.isNotEmpty) components.add({'code': 'SkinTemperature', 'unit': '°C', 'values': skinTemp});
    if (components.isEmpty) return;

    final token = await user.getIdToken();

    final requestBody = jsonEncode({
      'entry': [
        {
          'resource': {
            'effectiveDateTime': timestamp.toUtc().toIso8601String(),
            'component': components,
          }
        }
      ]
    });

    await http.post(
      Uri.parse('$_baseUrl/mutation/addVitalSigns'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: requestBody,
    );
  }

  // ── 수면 HR / HRV ─────────────────────────────────────────────────

  /// 워치에서 받은 수면 측정값을 반영(+ 선택적으로 서버 저장).
  /// 워치가 이미 서버로 직접 전송한 경우엔 persist:false 로 호출.
  void ingestSleepHrv({
    required double sleepHrMin,
    required double hrvRmssd,
    required DateTime timestamp,
    List<double> hrSeries = const [],
    List<double> rmssdSeries = const [],
    bool persist = false,
  }) {
    this.sleepHrMin = sleepHrMin;
    this.hrvRmssd = hrvRmssd;
    sleepHrSeries = hrSeries;
    sleepRmssdSeries = rmssdSeries;
    lastUpdated = timestamp;

    _addToHistory(VitalMeasurement(
      timestamp: timestamp,
      sleepHrMin: sleepHrMin,
      hrvRmssd: hrvRmssd,
    ));

    _computeScores();
    notifyListeners();

    if (persist) {
      saveSleepHrvToBackend(
        sleepHrMin: sleepHrMin, hrvRmssd: hrvRmssd, timestamp: timestamp,
        hrSeries: hrSeries, rmssdSeries: rmssdSeries,
      ).catchError((e) => debugPrint('⚠️ 수면 HRV 서버 저장 실패: $e'));
    }
  }

  /// 워치 SleepHrvService 와 동일한 component 코드로 서버에 저장.
  Future<void> saveSleepHrvToBackend({
    required double sleepHrMin,
    required double hrvRmssd,
    required DateTime timestamp,
    List<double> hrSeries = const [],
    List<double> rmssdSeries = const [],
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final components = <Map<String, dynamic>>[
      {'code': 'SleepHeartRateMin', 'unit': 'bpm', 'values': [sleepHrMin]},
      {'code': 'SleepHRV_RMSSD', 'unit': 'ms', 'values': [hrvRmssd]},
    ];
    if (hrSeries.isNotEmpty) {
      components.add({'code': 'SleepHR_Series', 'unit': 'bpm', 'values': hrSeries});
    }
    if (rmssdSeries.isNotEmpty) {
      components.add({'code': 'SleepHRV_RMSSD_Series', 'unit': 'ms', 'values': rmssdSeries});
    }

    final token = await user.getIdToken();

    final requestBody = jsonEncode({
      'entry': [
        {
          'resource': {
            'effectiveDateTime': timestamp.toUtc().toIso8601String(),
            'component': components,
          }
        }
      ]
    });

    await http.post(
      Uri.parse('$_baseUrl/mutation/addVitalSigns'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: requestBody,
    );
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
    final hrvs  = window.map((m) => m.hrvRmssd).whereType<double>().toList();

    if (hrs.length >= 3)   result['hr']       = BaselineStats.fromValues(hrs,   days);
    if (spo2s.length >= 3) result['spo2']     = BaselineStats.fromValues(spo2s, days);
    if (temps.length >= 3) result['skinTemp'] = BaselineStats.fromValues(temps, days);
    if (hrvs.length >= 3)  result['hrv']      = BaselineStats.fromValues(hrvs,  days);
    return result;
  }

  BaselineStats _bl(Map<String, BaselineStats> computed, String key) =>
      computed[key] ??
      (key == 'hr' ? _normHr
        : key == 'spo2' ? _normSpo2
        : key == 'hrv' ? _normHrv
        : _normTemp);

  // ── Wellness Score ─────────────────────────────────────────────────

  // Maps σ-distance from baseline to 0–100 score (100 = at baseline)
  double _devScore(double value, BaselineStats b) =>
      (100.0 - (value - b.mean).abs() / b.std * 25.0).clamp(0.0, 100.0);

  // HRV: 높을수록 좋음 → baseline 이상이면 만점, 이하일수록만 감점 (단측)
  double _hrvScore(double rmssd, BaselineStats b) {
    if (rmssd >= b.mean) return 100.0;
    return (100.0 - (b.mean - rmssd) / b.std * 25.0).clamp(0.0, 100.0);
  }

  void _computeScores() {
    final bl28 = _computeBaseline(28);

    // Short-term (24h): current session vs 28-day baseline
    // 측정 가능한 항목만 가중합 후 정규화 (없는 항목은 제외)
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
    if (hrvRmssd != null) {
      shortSum += _hrvScore(hrvRmssd!, _bl(bl28, 'hrv')) * 0.20;
      shortW   += 0.20;
    }

    // Long-term (28d): history averages vs population norms
    double longSum = 0, longW = 0;
    final allSpo2 = _history.map((m) => m.spo2).whereType<double>().toList();
    final allHr   = _history.map((m) => m.hr).whereType<double>().toList();
    final allTemp = _history.map((m) => m.skinTemp).whereType<double>().toList();
    final allHrv  = _history.map((m) => m.hrvRmssd).whereType<double>().toList();
    if (allSpo2.isNotEmpty) { longSum += _devScore(allSpo2.fold(0.0, (s, v) => s + v) / allSpo2.length, _normSpo2) * 0.15; longW += 0.15; }
    if (allHr.isNotEmpty)   { longSum += _devScore(allHr.fold(0.0, (s, v) => s + v)   / allHr.length,   _normHr)   * 0.25; longW += 0.25; }
    if (allTemp.isNotEmpty) { longSum += _devScore(allTemp.fold(0.0, (s, v) => s + v) / allTemp.length,  _normTemp)  * 0.10; longW += 0.10; }
    if (allHrv.isNotEmpty)  { longSum += _hrvScore(allHrv.fold(0.0, (s, v) => s + v)  / allHrv.length,  _normHrv)  * 0.20; longW += 0.20; }

    wellnessScore = WellnessScore(
      shortTerm:            shortW > 0 ? shortSum / shortW : 0.0,
      longTerm:             longW  > 0 ? longSum  / longW  : 0.0,
      usingPersonalBaseline: hasEnoughBaseline,
    );

    lastNews2Result = _computeNews2(bl28);

    // 오늘 날짜 스냅샷 저장 (달력 누적용 + 데이터 수집용 세부값)
    final details = <String, dynamic>{
      if (spo2Data.isNotEmpty)
        'spo2': {'avg': spo2Avg, 'min': spo2Min, 'max': spo2Max, 'n': spo2Data.length, 'values': spo2Data},
      if (heartRateData.isNotEmpty)
        'hr': {'avg': hrAvg, 'min': hrMin, 'max': hrMax, 'n': heartRateData.length, 'values': heartRateData},
      if (skinTempData.isNotEmpty)
        'skinTemp': {'avg': tempAvg, 'min': tempMin, 'max': tempMax, 'n': skinTempData.length, 'values': skinTempData},
      if (lastNews2Result != null) 'news2Items': lastNews2Result!.items,
      if (lastUpdated != null) 'measuredAt': lastUpdated!.toIso8601String(),
    };

    dailyStore?.mergeToday(
      wellShort: wellnessScore?.shortTerm,
      wellLong: wellnessScore?.longTerm,
      news2Total: lastNews2Result?.total,
      news2Action: lastNews2Result?.action.name,
      details: details.isEmpty ? null : details,
    );
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

  bool get hasSleepData => sleepHrMin != null && hrvRmssd != null;
  double get sleepHrMinValue => sleepHrMin ?? 0;
  double get hrvRmssdValue => hrvRmssd ?? 0;
}
