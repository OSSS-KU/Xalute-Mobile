import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'vital_signs_service.dart';
import 'samsung_health_service.dart';
import 'ecg_data_service.dart';
import 'ecg_preview_card.dart';
import 'main_tab_page.dart' as tabs;

// ── 데모용 목업 ──────────────────────────────────────────────────────
// 데모 이미지를 위해 실제 데이터가 없을 때 건강/에너지/수면 점수를
// "말이 되는" 임의값으로 채운다. 운영 배포 시 false로 끄면 된다.
const bool _demoMockSamsung = false;
const _mockSamsungSummary = SamsungHealthSummary(
  energyScore: 78,
  sleepScore: 84,
  totalSleepMinutes: 462, // 7시간 42분
  deepSleepMinutes: 92,
  remSleepMinutes: 110,
  lightSleepMinutes: 240,
  awakeDuringMinutes: 20,
  sleepCycleCount: 5,
  physicalRecoveryScore: 95,
  mentalRecoveryScore: 90,
  sleepHR: 56,
);

// 건강점수(웰니스) + 위험도 목업
const _mockWellness = WellnessScore(
  shortTerm: 86,
  longTerm: 81,
  usingPersonalBaseline: true,
);
final _mockNews2 = News2Result(
  total: 0,
  items: const {'spo2': 0, 'hr': 0, 'skinTemp': 0},
  singleItem3: false,
  action: News2Action.recordOnly,
  measuredAt: DateTime(2026, 1, 1),
);
const double _mockSpo2 = 98;
const double _mockHr = 72;     // 정상 안정 시 심박수 (bpm)
const double _mockTemp = 36.5;  // 정상 체온 (°C)

// 오늘 날짜의 최신 ECG 측정 항목 (없으면 null)
EcgEntry? _latestTodayEcg(EcgDataService s) {
  final list = s.entriesForDay(DateTime.now());
  if (list.isEmpty) return null;
  list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
  return list.first;
}

class VitalSignsPage extends StatefulWidget {
  /// 탭 활성화 시 자동 갱신을 위해 주입 (선택)
  final tabs.TabController? controller;
  final int? tabIndex;

  const VitalSignsPage({super.key, this.controller, this.tabIndex});

  @override
  State<VitalSignsPage> createState() => _VitalSignsPageState();
}

class _VitalSignsPageState extends State<VitalSignsPage> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.controller?.index == widget.tabIndex) {
      _refresh();
    }
  }

  // 일일 리포트 진입/탭 시 바이탈 + 삼성헬스를 조용히(다이얼로그 없이) 갱신
  Future<void> _refresh() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        Provider.of<VitalSignsService>(context, listen: false)
            .fetchVitalSigns()
            .catchError((_) {}),
        if (Platform.isAndroid || Platform.isIOS)
          Provider.of<SamsungHealthService>(context, listen: false)
              .fetchSummary()
              .catchError((_) {}),
      ]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Login required');
    final token = await user.getIdToken();
    if (token == null) throw Exception('Failed to issue token');
    return token;
  }

  // 리포트 화면에서 ECG 측정 트리거 (Android: 워치 앱 실행 / iOS: HealthKit 조회)
  Future<void> _handleMeasure() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.example.xalute/watch');
      try {
        final bool isConnected =
            await platform.invokeMethod('isWatchConnected');
        if (!mounted) return;
        if (!isConnected) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              content: const Text('Please check your watch connection.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK')),
              ],
            ),
          );
          return;
        }

        final ecg = Provider.of<EcgDataService>(context, listen: false);
        final name = ecg.userName;
        final birthDate = ecg.birthDate ?? '';
        final token = await _getIdToken();
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (dctx) => AlertDialog(
            content: const Text('Do you want to measure ECG on your watch?'),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(dctx);
                  try {
                    await platform.invokeMethod('launchWatchApp', {
                      'name': name,
                      'birthDate': birthDate,
                      'token': token,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Watch app launched')));
                    }
                  } catch (e) {
                    debugPrint('워치 앱 실행 실패: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to launch watch app: $e')));
                    }
                  }
                },
                child: const Text('OK'),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('Cancel')),
            ],
          ),
        );
      } on PlatformException catch (e) {
        debugPrint('플랫폼 오류: ${e.message}');
      }
    } else {
      // iOS: HealthKit에서 ECG 조회
      setState(() => _isLoading = true);
      try {
        await Provider.of<EcgDataService>(context, listen: false).fetchEcgData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed to fetch data: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Daily Report',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _handleMeasure,
        backgroundColor: const Color(0xFFFB755B),
        icon: const Icon(Icons.monitor_heart, color: Colors.white),
        label: Text(
          Platform.isIOS ? 'Fetch ECG' : 'Measure ECG',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Consumer<VitalSignsService>(
            builder: (context, service, _) {
              final todayEcg =
                  _latestTodayEcg(Provider.of<EcgDataService>(context));
              if (!service.hasData && todayEcg == null && !_demoMockSamsung) {
                return _EmptyState();
              }
              return _DataView(service: service, todayEcg: todayEcg);
            },
          ),
          if (_isLoading)
            AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFB755B)),
                    SizedBox(height: 16),
                    Text(
                      'Updating your daily report\nPlease wait a moment',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No vital data measured yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Measure an ECG on your watch to see\nSpO2, heart rate, and skin temperature',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _DataView extends StatelessWidget {
  final VitalSignsService service;
  final EcgEntry? todayEcg;

  const _DataView({required this.service, this.todayEcg});

  @override
  Widget build(BuildContext context) {
    final timeStr = service.lastUpdated != null
        ? DateFormat('yyyy.MM.dd HH:mm').format(service.lastUpdated!)
        : '-';
    // Android: Samsung Health Data SDK / iOS: HealthKit 수면 요약
    final realSummary = (Platform.isAndroid || Platform.isIOS)
        ? Provider.of<SamsungHealthService>(context).summary
        : null;
    // 실제 요약이 있어도 에너지/수면 점수가 안 들어오는 경우가 있어
    // 비어 있는 점수만 목업값으로 채워서 UI에 표시한다(임시).
    SamsungHealthSummary? shSummary;
    if (realSummary != null) {
      shSummary = _demoMockSamsung
          ? realSummary.copyWith(
              energyScore: realSummary.energyScore ?? _mockSamsungSummary.energyScore,
              sleepScore: realSummary.sleepScore ?? _mockSamsungSummary.sleepScore,
              totalSleepMinutes: realSummary.totalSleepMinutes ?? _mockSamsungSummary.totalSleepMinutes,
              deepSleepMinutes: realSummary.deepSleepMinutes ?? _mockSamsungSummary.deepSleepMinutes,
              remSleepMinutes: realSummary.remSleepMinutes ?? _mockSamsungSummary.remSleepMinutes,
              lightSleepMinutes: realSummary.lightSleepMinutes ?? _mockSamsungSummary.lightSleepMinutes,
              awakeDuringMinutes: realSummary.awakeDuringMinutes ?? _mockSamsungSummary.awakeDuringMinutes,
              sleepCycleCount: realSummary.sleepCycleCount ?? _mockSamsungSummary.sleepCycleCount,
              sleepHR: realSummary.sleepHR ?? _mockSamsungSummary.sleepHR,
            )
          : realSummary;
    } else {
      shSummary = _demoMockSamsung ? _mockSamsungSummary : null;
    }

    // 건강점수: 실제값 우선, 비어 있는 항목은 데모 목업으로 채운다(임시).
    final realWellness = service.wellnessScore;
    final wellness = realWellness ?? (_demoMockSamsung ? _mockWellness : null);
    final double? wSpo2 = (realWellness != null && service.spo2Data.isNotEmpty)
        ? service.spo2Avg
        : (_demoMockSamsung ? _mockSpo2 : null);
    final double? wHr = (realWellness != null && service.heartRateData.isNotEmpty)
        ? service.hrAvg
        : (_demoMockSamsung ? _mockHr : null);
    final double? wTemp = (realWellness != null && service.skinTempData.isNotEmpty)
        ? service.tempAvg
        : (_demoMockSamsung ? _mockTemp : null);
    final News2Result? wNews2 =
        (realWellness != null && service.lastNews2Result != null)
            ? service.lastNews2Result
            : (_demoMockSamsung ? _mockNews2 : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ECG 미리보기 (plot + 의심 질환) — 최상단
        if (todayEcg != null) ...[
          TodayEcgCard(entry: todayEcg!),
          const SizedBox(height: 14),
        ],

        Row(
          children: [
            const Icon(Icons.access_time, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'Last measured: $timeStr',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (wellness != null) ...[
          _WellnessScoreCard(
            score: wellness,
            spo2: wSpo2,
            hr: wHr,
            temp: wTemp,
            news2: wNews2,
          ),
          const SizedBox(height: 14),
        ],

        if (shSummary != null) ...[
          // 에너지 점수는 Samsung Health 전용 지표 → iOS(HealthKit)에서는 표시하지 않음
          if (!Platform.isIOS) ...[
            _EnergyScoreCard(summary: shSummary),
            const SizedBox(height: 14),
          ],
          _SleepScoreCard(summary: shSummary),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

// ─── Wellness Score Card ─────────────────────────────────────────────

class _WellnessScoreCard extends StatefulWidget {
  final WellnessScore score;
  final double? spo2; // 평균값 (없으면 null)
  final double? hr;
  final double? temp;
  final News2Result? news2;

  const _WellnessScoreCard({
    required this.score,
    this.spo2,
    this.hr,
    this.temp,
    this.news2,
  });

  @override
  State<_WellnessScoreCard> createState() => _WellnessScoreCardState();
}

class _WellnessScoreCardState extends State<_WellnessScoreCard> {
  static const _accent = Color(0xFF34C759);

  Color _scoreColor(double s) {
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF30B0C7);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  Color _actionColor(News2Action a) {
    switch (a) {
      case News2Action.recordOnly:     return const Color(0xFF34C759);
      case News2Action.observe24h:     return const Color(0xFFFF9500);
      case News2Action.immediateAlert: return const Color(0xFFFF3B30);
    }
  }

  IconData _actionIcon(News2Action a) {
    switch (a) {
      case News2Action.recordOnly:     return Icons.check_circle_outline;
      case News2Action.observe24h:     return Icons.schedule;
      case News2Action.immediateAlert: return Icons.warning_amber_rounded;
    }
  }

  Widget _buildRiskSection(News2Result result) {
    final color = _actionColor(result.action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_actionIcon(result.action), color: color, size: 18),
            const SizedBox(width: 6),
            const Text(
              'Health Risk',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                result.action.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${result.total}',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: color, height: 1.0),
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: Text('pts', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (result.items.containsKey('spo2'))
                  _News2ItemRow(label: 'SpO2', score: result.items['spo2']!),
                if (result.items.containsKey('hr'))
                  _News2ItemRow(label: 'Heart Rate', score: result.items['hr']!),
                if (result.items.containsKey('skinTemp'))
                  _News2ItemRow(label: 'Temp', score: result.items['skinTemp']!),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.action.description,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;

    return _HealthCard(
      icon: Icons.spa,
      iconColor: _accent,
      title: 'Health Score',
      subtitle: 'Vital Signs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BigScoreCircle(
                    score: score.shortTerm.round(),
                    maxScore: 100,
                    color: _scoreColor(score.shortTerm),
                    label: 'Short-term 24h',
                  ),
                  const SizedBox(height: 12),
                  _BigScoreCircle(
                    score: score.longTerm.round(),
                    maxScore: 100,
                    color: _scoreColor(score.longTerm),
                    label: 'Long-term 28d',
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubMetricRow(
                      icon: Icons.air,
                      label: 'SpO2',
                      value: widget.spo2 != null ? '${widget.spo2!.round()}%' : '--',
                      color: const Color(0xFF4E9AF1),
                    ),
                    _SubMetricRow(
                      icon: Icons.favorite,
                      label: 'Heart Rate',
                      value: widget.hr != null ? '${widget.hr!.round()} bpm' : '--',
                      color: const Color(0xFFFB755B),
                    ),
                    _SubMetricRow(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      value: widget.temp != null ? '${widget.temp!.toStringAsFixed(1)}°C' : '--',
                      color: const Color(0xFFFF9500),
                    ),
                    _SubMetricRow(
                      icon: Icons.groups,
                      label: 'baseline',
                      value: score.usingPersonalBaseline ? 'Personal' : 'Population',
                      note: score.usingPersonalBaseline ? 'Using personal baseline' : 'Personalizes after 7 days',
                      color: score.usingPersonalBaseline
                          ? const Color(0xFF34C759)
                          : const Color(0xFFFF9500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.news2 != null) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 14),
            _buildRiskSection(widget.news2!),
          ],
        ],
      ),
    );
  }
}

class _News2ItemRow extends StatelessWidget {
  final String label;
  final int score;

  const _News2ItemRow({required this.label, required this.score});

  Color get _color {
    if (score == 0) return Colors.grey;
    if (score == 1) return const Color(0xFFFF9500);
    if (score == 2) return Colors.deepOrange;
    return const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Energy Score Card ────────────────────────────────────────────────

class _EnergyScoreCard extends StatefulWidget {
  final SamsungHealthSummary summary;
  const _EnergyScoreCard({required this.summary});

  @override
  State<_EnergyScoreCard> createState() => _EnergyScoreCardState();
}

class _EnergyScoreCardState extends State<_EnergyScoreCard> {
  static const _accent = Color(0xFF5E9BF0);

  Color _scoreColor(double s) {
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF5E9BF0);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.summary.energyScore;
    final sleepHR = widget.summary.sleepHR;
    final totalSleep = widget.summary.totalSleepMinutes;

    return _HealthCard(
      icon: Icons.bolt,
      iconColor: _accent,
      title: 'Energy Score',
      subtitle: 'Samsung Health',
      child: Row(
        children: [
          // 큰 점수 원형
          _BigScoreCircle(
            score: score?.toInt(),
            maxScore: 100,
            color: score != null ? _scoreColor(score) : Colors.grey.shade300,
            label: 'Today',
          ),
          const SizedBox(width: 20),
          // 서브 메트릭 목록 (실제 측정 value)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubMetricRow(
                  icon: Icons.directions_run,
                  label: 'Activity',
                  value: 'Based on yesterday\'s activity',
                  color: const Color(0xFF34C759),
                ),
                _SubMetricRow(
                  icon: Icons.bedtime,
                  label: 'Sleep',
                  value: totalSleep != null ? widget.summary.totalSleepStr : '--',
                  color: const Color(0xFF5E9BF0),
                ),
                _SubMetricRow(
                  icon: Icons.favorite,
                  label: 'Sleep HR',
                  value: sleepHR != null ? '${sleepHR.toStringAsFixed(0)} bpm' : '--',
                  color: const Color(0xFFFB755B),
                ),
                _SubMetricRow(
                  icon: Icons.waves,
                  label: 'Sleep HRV',
                  value: '--',
                  color: const Color(0xFFFF9500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sleep Score Card ─────────────────────────────────────────────────

class _SleepScoreCard extends StatefulWidget {
  final SamsungHealthSummary summary;
  const _SleepScoreCard({required this.summary});

  @override
  State<_SleepScoreCard> createState() => _SleepScoreCardState();
}

class _SleepScoreCardState extends State<_SleepScoreCard> {
  static const _accent = Color(0xFF7B61FF);

  Color _scoreColor(int s) {
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF7B61FF);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final total = s.totalSleepMinutes ?? 0;
    final deep = s.deepSleepMinutes ?? 0;
    final rem = s.remSleepMinutes ?? 0;
    final light = s.lightSleepMinutes ?? 0;
    final awake = s.awakeDuringMinutes ?? 0;
    final deepPct = total > 0 ? deep / total * 100 : 0.0;
    final remPct = total > 0 ? rem / total * 100 : 0.0;

    return _HealthCard(
      icon: Icons.bedtime,
      iconColor: _accent,
      title: 'Sleep Score',
      subtitle: Platform.isIOS ? 'Apple Health' : 'Samsung Health',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BigScoreCircle(
                score: s.sleepScore,
                maxScore: 100,
                color: s.sleepScore != null ? _scoreColor(s.sleepScore!) : Colors.grey.shade300,
                label: 'Last night',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 수면 단계 시각화 바
                    if (total > 0) ...[
                      _SleepStageBar(
                        deep: deep, rem: rem, light: light, awake: awake,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      'Total sleep  ${s.totalSleepStr}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deep ${deepPct.toStringAsFixed(0)}%  ·  REM ${remPct.toStringAsFixed(0)}%  ·  Cycles ${s.sleepCycleCount ?? 0}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5개 서브컴포넌트 — 실제 측정 value
          _SleepSubRow(
            label: 'Total sleep time',
            value: s.totalSleepStr,
            color: const Color(0xFF5E9BF0),
          ),
          _SleepSubRow(
            label: 'Sleep cycles',
            value: '${s.sleepCycleCount ?? 0}',
            color: _accent,
          ),
          _SleepSubRow(
            label: 'Awake / restless',
            value: '$awake min',
            color: const Color(0xFFFF9500),
          ),
          _SleepSubRow(
            label: 'Physical recovery (Deep)',
            value: '${deepPct.toStringAsFixed(0)}% · $deep min',
            color: const Color(0xFF34C759),
          ),
          _SleepSubRow(
            label: 'Mental recovery (REM)',
            value: '${remPct.toStringAsFixed(0)}% · $rem min',
            color: const Color(0xFFFB755B),
          ),
        ],
      ),
    );
  }
}

// ─── 공통 서브 위젯들 ─────────────────────────────────────────────────

class _HealthCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  const _HealthCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _BigScoreCircle extends StatelessWidget {
  final int? score;
  final int maxScore;
  final Color color;
  final String label;

  const _BigScoreCircle({
    required this.score,
    required this.maxScore,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = score != null ? score! / maxScore : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 6,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score != null ? '$score' : '--',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }
}

class _SubMetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Color color;

  const _SubMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    Text(value,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ],
                ),
                if (note != null)
                  Text(note!,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepSubRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SleepSubRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _SleepStageBar extends StatelessWidget {
  final int deep, rem, light, awake;

  const _SleepStageBar({
    required this.deep,
    required this.rem,
    required this.light,
    required this.awake,
  });

  @override
  Widget build(BuildContext context) {
    final total = (deep + rem + light + awake).toDouble();
    if (total == 0) return const SizedBox.shrink();

    Widget segment(int mins, Color color) => Expanded(
          flex: mins,
          child: Container(color: color, height: 8),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (deep > 0) segment(deep, const Color(0xFF3478F6)),
              if (rem > 0) segment(rem, const Color(0xFF7B61FF)),
              if (light > 0) segment(light, const Color(0xFF5AC8FA)),
              if (awake > 0) segment(awake, Colors.grey.shade300),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _LegendDot(color: const Color(0xFF3478F6), label: 'Deep'),
            _LegendDot(color: const Color(0xFF7B61FF), label: 'REM'),
            _LegendDot(color: const Color(0xFF5AC8FA), label: 'Light'),
            _LegendDot(color: Colors.grey.shade300, label: 'Awake'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
