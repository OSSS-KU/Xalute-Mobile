import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'daily_report_store.dart';

// ─── 데이터 모델 ──────────────────────────────────────────────────────

class SamsungHealthSummary {
  final double? energyScore;

  final int? sleepScore;
  final int? totalSleepMinutes;
  final int? deepSleepMinutes;
  final int? remSleepMinutes;
  final int? lightSleepMinutes;
  final int? awakeDuringMinutes;
  final int? sleepCycleCount;

  // 삼성 헬스 수면 점수 서브컴포넌트 (자체 계산)
  final int? physicalRecoveryScore;
  final int? mentalRecoveryScore;

  final double? sleepHR;

  const SamsungHealthSummary({
    this.energyScore,
    this.sleepScore,
    this.totalSleepMinutes,
    this.deepSleepMinutes,
    this.remSleepMinutes,
    this.lightSleepMinutes,
    this.awakeDuringMinutes,
    this.sleepCycleCount,
    this.physicalRecoveryScore,
    this.mentalRecoveryScore,
    this.sleepHR,
  });

  factory SamsungHealthSummary.fromMap(Map<dynamic, dynamic> m) {
    return SamsungHealthSummary(
      energyScore:           (m['energyScore'] as num?)?.toDouble(),
      sleepScore:            (m['sleepScore'] as num?)?.toInt(),
      totalSleepMinutes:     (m['totalSleepMinutes'] as num?)?.toInt(),
      deepSleepMinutes:      (m['deepSleepMinutes'] as num?)?.toInt(),
      remSleepMinutes:       (m['remSleepMinutes'] as num?)?.toInt(),
      lightSleepMinutes:     (m['lightSleepMinutes'] as num?)?.toInt(),
      awakeDuringMinutes:    (m['awakeDuringMinutes'] as num?)?.toInt(),
      sleepCycleCount:       (m['sleepCycleCount'] as num?)?.toInt(),
      physicalRecoveryScore: (m['physicalRecoveryScore'] as num?)?.toInt(),
      mentalRecoveryScore:   (m['mentalRecoveryScore'] as num?)?.toInt(),
      sleepHR:               (m['sleepHR'] as num?)?.toDouble(),
    );
  }

  // 총 수면 시간 기반 점수 (7-9시간 = 100점)
  int get totalSleepScore {
    final mins = totalSleepMinutes;
    if (mins == null) return 0;
    final h = mins / 60.0;
    if (h >= 7 && h <= 9) return 100;
    if (h >= 6 && h < 7)  return 80;
    if (h > 9 && h <= 10) return 80;
    if (h >= 5 && h < 6)  return 60;
    if (h > 10 && h <= 11) return 60;
    return 30;
  }

  // 수면 주기 점수 (REM 완료 5회 = 100점)
  int get cycleScore {
    final c = sleepCycleCount ?? 0;
    if (c >= 5) return 100;
    if (c == 4) return 85;
    if (c == 3) return 70;
    if (c == 2) return 50;
    if (c == 1) return 30;
    return 0;
  }

  // 뒤척임 점수 (총수면의 5% 미만 = 100점)
  int get awakenessScore {
    final awake = awakeDuringMinutes ?? 0;
    final total = totalSleepMinutes ?? 1;
    final pct = awake / total * 100;
    if (pct < 5)  return 100;
    if (pct < 10) return 80;
    if (pct < 20) return 60;
    return 30;
  }

  String get totalSleepStr {
    final mins = totalSleepMinutes ?? 0;
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  // HealthKit처럼 자체 수면 점수가 없는 플랫폼에서 실측 단계 데이터로 계산하는 수면 점수.
  // 총 수면(40%) + 수면 주기(30%) + 뒤척임 적음(30%) 가중 평균.
  int get computedSleepScore =>
      (totalSleepScore * 0.4 + cycleScore * 0.3 + awakenessScore * 0.3).round();

  SamsungHealthSummary copyWith({
    double? energyScore,
    int? sleepScore,
    int? totalSleepMinutes,
    int? deepSleepMinutes,
    int? remSleepMinutes,
    int? lightSleepMinutes,
    int? awakeDuringMinutes,
    int? sleepCycleCount,
    int? physicalRecoveryScore,
    int? mentalRecoveryScore,
    double? sleepHR,
  }) {
    return SamsungHealthSummary(
      energyScore: energyScore ?? this.energyScore,
      sleepScore: sleepScore ?? this.sleepScore,
      totalSleepMinutes: totalSleepMinutes ?? this.totalSleepMinutes,
      deepSleepMinutes: deepSleepMinutes ?? this.deepSleepMinutes,
      remSleepMinutes: remSleepMinutes ?? this.remSleepMinutes,
      lightSleepMinutes: lightSleepMinutes ?? this.lightSleepMinutes,
      awakeDuringMinutes: awakeDuringMinutes ?? this.awakeDuringMinutes,
      sleepCycleCount: sleepCycleCount ?? this.sleepCycleCount,
      physicalRecoveryScore: physicalRecoveryScore ?? this.physicalRecoveryScore,
      mentalRecoveryScore: mentalRecoveryScore ?? this.mentalRecoveryScore,
      sleepHR: sleepHR ?? this.sleepHR,
    );
  }
}

// ─── 서비스 ──────────────────────────────────────────────────────────

class SamsungHealthService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.health/vitals');

  SamsungHealthSummary? summary;
  bool isLoading = false;
  String? errorMessage;

  // 날짜별 점수 스냅샷 저장소 (main.dart에서 주입)
  DailyReportStore? dailyStore;

  bool get isAndroid => Platform.isAndroid;

  Future<void> fetchSummary() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Android: Samsung Health Data SDK / iOS: HealthKit 수면 분석
      final method =
          Platform.isIOS ? 'getHealthSummary' : 'getSamsungHealthSummary';
      final raw = await _channel.invokeMethod<Map>(method);
      var parsed = raw != null ? SamsungHealthSummary.fromMap(raw) : null;

      // iOS HealthKit은 수면 점수를 제공하지 않으므로 실측 단계 데이터로 직접 계산한다.
      if (parsed != null &&
          Platform.isIOS &&
          parsed.sleepScore == null &&
          parsed.totalSleepMinutes != null) {
        parsed = parsed.copyWith(sleepScore: parsed.computedSleepScore);
      }
      summary = parsed;

      // 오늘 날짜 스냅샷 저장 (달력 누적용 + 데이터 수집용 세부값)
      if (summary != null) {
        final s = summary!;
        final details = <String, dynamic>{
          if (s.energyScore != null) 'energyScore': s.energyScore,
          if (s.sleepScore != null) 'sleepScore': s.sleepScore,
          if (s.totalSleepMinutes != null) 'totalSleepMinutes': s.totalSleepMinutes,
          if (s.deepSleepMinutes != null) 'deepSleepMinutes': s.deepSleepMinutes,
          if (s.remSleepMinutes != null) 'remSleepMinutes': s.remSleepMinutes,
          if (s.lightSleepMinutes != null) 'lightSleepMinutes': s.lightSleepMinutes,
          if (s.awakeDuringMinutes != null) 'awakeDuringMinutes': s.awakeDuringMinutes,
          if (s.sleepCycleCount != null) 'sleepCycleCount': s.sleepCycleCount,
          if (s.physicalRecoveryScore != null) 'physicalRecoveryScore': s.physicalRecoveryScore,
          if (s.mentalRecoveryScore != null) 'mentalRecoveryScore': s.mentalRecoveryScore,
          if (s.sleepHR != null) 'sleepHR': s.sleepHR,
        };
        dailyStore?.mergeToday(
          energy: s.energyScore,
          sleep: s.sleepScore,
          details: details.isEmpty ? null : details,
        );
      }
    } on PlatformException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
