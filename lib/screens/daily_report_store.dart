import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 하루치 점수 스냅샷 (건강/위험도/에너지/수면).
/// 측정·조회가 끝날 때마다 해당 날짜 레코드에 병합 저장된다.
class DailyReport {
  final double? wellShort;   // 건강점수 단기 (24h)
  final double? wellLong;    // 건강점수 장기 (28일)
  final int? news2Total;     // 건강 위험도 총점
  final String? news2Action; // recordOnly / observe24h / immediateAlert
  final double? energy;      // 삼성 에너지 점수
  final int? sleep;          // 삼성 수면 점수

  /// 데이터 수집용 세부 측정값(raw value). 예:
  /// { "spo2": {"avg":.., "min":.., "max":.., "values":[..]},
  ///   "hr": {...}, "skinTemp": {...}, "news2Items": {...},
  ///   "totalSleepMinutes": .., "deepSleepMinutes": .., "sleepHR": .. }
  final Map<String, dynamic>? details;

  const DailyReport({
    this.wellShort,
    this.wellLong,
    this.news2Total,
    this.news2Action,
    this.energy,
    this.sleep,
    this.details,
  });

  bool get isEmpty =>
      wellShort == null &&
      wellLong == null &&
      news2Total == null &&
      energy == null &&
      sleep == null &&
      (details == null || details!.isEmpty);

  /// 비어있지 않은 필드만 덮어쓰며 병합한다(증분 업데이트용).
  /// details는 key 단위로 병합(같은 key는 새 값으로 덮어씀).
  DailyReport merge(DailyReport o) {
    final Map<String, dynamic>? mergedDetails =
        (details == null && o.details == null)
            ? null
            : {...?details, ...?o.details};
    return DailyReport(
      wellShort: o.wellShort ?? wellShort,
      wellLong: o.wellLong ?? wellLong,
      news2Total: o.news2Total ?? news2Total,
      news2Action: o.news2Action ?? news2Action,
      energy: o.energy ?? energy,
      sleep: o.sleep ?? sleep,
      details: mergedDetails,
    );
  }

  Map<String, dynamic> toJson() => {
        if (wellShort != null) 'wellShort': wellShort,
        if (wellLong != null) 'wellLong': wellLong,
        if (news2Total != null) 'news2Total': news2Total,
        if (news2Action != null) 'news2Action': news2Action,
        if (energy != null) 'energy': energy,
        if (sleep != null) 'sleep': sleep,
        if (details != null && details!.isNotEmpty) 'details': details,
      };

  factory DailyReport.fromJson(Map<String, dynamic> j) => DailyReport(
        wellShort: (j['wellShort'] as num?)?.toDouble(),
        wellLong: (j['wellLong'] as num?)?.toDouble(),
        news2Total: (j['news2Total'] as num?)?.toInt(),
        news2Action: j['news2Action'] as String?,
        energy: (j['energy'] as num?)?.toDouble(),
        sleep: (j['sleep'] as num?)?.toInt(),
        details: (j['details'] as Map?)?.cast<String, dynamic>(),
      );
}

String dailyKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class DailyReportStore extends ChangeNotifier {
  static const _prefsKey = 'daily_reports';

  final Map<String, DailyReport> _reports = {};
  Map<String, DailyReport> get reports => _reports;

  DailyReport? forDay(DateTime day) => _reports[dailyKey(day)];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _reports.clear();
      decoded.forEach((k, v) {
        _reports[k] = DailyReport.fromJson(v as Map<String, dynamic>);
      });
      notifyListeners();
    } catch (_) {
      // 손상된 데이터는 무시
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _reports.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  /// 오늘 날짜 레코드에 점수를 증분 병합한다.
  /// 건강점수는 VitalSignsService, 에너지/수면은 SamsungHealthService에서 호출.
  Future<void> mergeToday({
    double? wellShort,
    double? wellLong,
    int? news2Total,
    String? news2Action,
    double? energy,
    int? sleep,
    Map<String, dynamic>? details,
  }) async {
    final incoming = DailyReport(
      wellShort: wellShort,
      wellLong: wellLong,
      news2Total: news2Total,
      news2Action: news2Action,
      energy: energy,
      sleep: sleep,
      details: details,
    );
    if (incoming.isEmpty) return;

    final key = dailyKey(DateTime.now());
    _reports[key] = (_reports[key] ?? const DailyReport()).merge(incoming);
    notifyListeners();
    await _persist();
  }
}
