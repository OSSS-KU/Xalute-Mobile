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
    return '${mins ~/ 60}시간 ${mins % 60}분';
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
    if (!isAndroid) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final raw = await _channel.invokeMethod<Map>('getSamsungHealthSummary');
      summary = raw != null ? SamsungHealthSummary.fromMap(raw) : null;

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
