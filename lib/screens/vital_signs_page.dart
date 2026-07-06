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
import 'ecg_page.dart';
import 'main_tab_page.dart' as tabs;

// ── 데모용 목업 ──────────────────────────────────────────────────────
// 데모 이미지를 위해 실제 데이터가 없을 때 건강/에너지/수면 점수를
// "말이 되는" 임의값으로 채운다. 운영 배포 시 false로 끄면 된다.
const bool






_demoMockSamsung = false;
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

// 현재 버전에서는 Health 점수만 노출하고 Energy/Sleep 점수 카드는 숨긴다.
// (점수 설명은 AppBar의 ? 버튼으로 대체)
const bool _showEnergyScore = false;
const bool _showSleepScore = false;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'About your scores',
            onPressed: () => _showScoreHelp(
              context,
              'About your scores',
              const Color(0xFF34C759),
              _scoreHelpEntries,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Consumer<VitalSignsService>(
            builder: (context, service, _) {
              final todayEcg =
                  _latestTodayEcg(Provider.of<EcgDataService>(context));
              if (!service.hasData && todayEcg == null && !_demoMockSamsung) {
                return _EmptyState(
                  isLoading: _isLoading,
                  onMeasure: _handleMeasure,
                );
              }
              return _DataView(
                service: service,
                todayEcg: todayEcg,
                isLoading: _isLoading,
                onMeasure: _handleMeasure,
              );
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
  final bool isLoading;
  final VoidCallback onMeasure;

  const _EmptyState({required this.isLoading, required this.onMeasure});

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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: _MeasureEcgButton(isLoading: isLoading, onMeasure: onMeasure),
          ),
        ],
      ),
    );
  }
}

/// Measure ECG 버튼 + 옆의 (?) 설명 버튼. Daily Report 하단에 인라인으로 붙는다.
class _MeasureEcgButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onMeasure;

  const _MeasureEcgButton({required this.isLoading, required this.onMeasure});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onMeasure,
            icon: const Icon(Icons.monitor_heart, color: Colors.white),
            label: Text(
              Platform.isIOS ? 'Fetch ECG' : 'Measure ECG',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFB755B),
              disabledBackgroundColor: const Color(0xFFFB755B).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          height: 48,
          child: OutlinedButton(
            onPressed: () => _showScoreHelp(
              context,
              'Measuring ECG',
              const Color(0xFFFB755B),
              _ecgHelpEntries,
            ),
            style: OutlinedButton.styleFrom(
              shape: const CircleBorder(),
              side: const BorderSide(color: Color(0xFFFB755B)),
              foregroundColor: const Color(0xFFFB755B),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.help_outline),
          ),
        ),
      ],
    );
  }
}

class _DataView extends StatelessWidget {
  final VitalSignsService service;
  final EcgEntry? todayEcg;
  final bool isLoading;
  final VoidCallback onMeasure;

  const _DataView({
    required this.service,
    this.todayEcg,
    required this.isLoading,
    required this.onMeasure,
  });

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
        // ECG 미리보기 (plot + 의심 질환) — 최상단. 탭하면 ECG 리서치 페이지로.
        if (todayEcg != null) ...[
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcgResearchPage()),
            ),
            child: TodayEcgCard(entry: todayEcg!),
          ),
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

        // 메인에는 "오늘의 점수"만 요약해서 보여주고,
        // 탭하면 세부 지표 페이지로 이동한다.
        // 현재 버전에서는 Health 점수만 노출한다.
        if (wellness != null) ...[
          _ScoreSummaryCard(
            icon: Icons.spa,
            iconColor: const Color(0xFF34C759),
            title: 'Health Score',
            subtitle: 'Short-term · Vital Signs',
            score: wellness.shortTerm.round(),
            onTap: () => _openDetail(
              context,
              'Health Score',
              _WellnessScoreCard(
                score: wellness,
                spo2: wSpo2,
                hr: wHr,
                temp: wTemp,
                news2: wNews2,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        if (shSummary != null) ...[
          // 에너지 점수는 Samsung Health 전용 지표 → iOS(HealthKit)에서는 표시하지 않음
          if (_showEnergyScore && !Platform.isIOS) ...[
            _ScoreSummaryCard(
              icon: Icons.bolt,
              iconColor: const Color(0xFF5E9BF0),
              title: 'Energy Score',
              subtitle: 'Samsung Health',
              score: shSummary.energyScore?.toInt(),
              onTap: () => _openDetail(
                context,
                'Energy Score',
                _EnergyScoreCard(summary: shSummary!),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_showSleepScore) ...[
            _ScoreSummaryCard(
              icon: Icons.bedtime,
              iconColor: const Color(0xFF7B61FF),
              title: 'Sleep Score',
              subtitle: Platform.isIOS ? 'Apple Health' : 'Samsung Health',
              score: shSummary.sleepScore,
              onTap: () => _openDetail(
                context,
                'Sleep Score',
                _SleepScoreCard(summary: shSummary!),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],

        // Measure ECG 버튼을 점수 카드 바로 아래에 붙인다.
        const SizedBox(height: 2),
        _MeasureEcgButton(isLoading: isLoading, onMeasure: onMeasure),
        const SizedBox(height: 10),
        // ECG 리서치(1-lead → 12-lead) + 과거 기록 진입
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EcgResearchPage()),
          ),
          icon: const Icon(Icons.biotech),
          label: const Text('ECG research & past records'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF5E5CE6),
            side: const BorderSide(color: Color(0xFF5E5CE6)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size.fromHeight(0),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, String title, Widget detailCard) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ScoreDetailPage(title: title, card: detailCard),
      ),
    );
  }
}

// ─── 요약 카드 (메인 리포트) ───────────────────────────────────────────
// "오늘의 점수"만 크게 보여주고, 탭하면 세부 페이지로 이동한다.

class _ScoreSummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final int? score;
  final VoidCallback onTap;

  const _ScoreSummaryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.onTap,
  });

  Color _scoreColor(int s) {
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF30B0C7);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  @override
  Widget build(BuildContext context) {
    final color = score != null ? _scoreColor(score!) : Colors.grey.shade300;

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  score != null ? '$score' : '--',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.0,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 4),
                  child: Text('/100',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 세부 지표 페이지 ──────────────────────────────────────────────────
// 요약 카드를 탭하면 열리며, 기존 상세 카드를 그대로 보여준다.

class _ScoreDetailPage extends StatelessWidget {
  final String title;
  final Widget card;

  const _ScoreDetailPage({required this.title, required this.card});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [card],
      ),
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
      help: const [
        _HelpEntry(
          'What it means',
          'A 0–100 wellness score based on your SpO2, heart rate and skin '
              'temperature. The closer your vitals are to your normal range, '
              'the higher the score.',
        ),
        _HelpEntry(
          'Short-term (24h)',
          'Your latest measurement compared with your own 28-day baseline. '
              'It reflects how you are doing right now.',
        ),
        _HelpEntry(
          'Long-term (28d)',
          'Your 28-day average compared with a healthy population norm. '
              'It reflects your overall recent trend.',
        ),
        _HelpEntry(
          'SpO2 · Heart Rate · Temperature',
          'The vital signs measured on your watch that feed the score. '
              'Values shown are session averages.',
        ),
        _HelpEntry(
          'Baseline',
          'Once you have enough measurements (5+ in the last 7 days) the score '
              'uses your personal baseline. Until then a population average is '
              'used.',
        ),
        _HelpEntry(
          'Health Risk',
          'An early-warning check. Each vital gets 0–3 points; the total '
              'suggests whether to simply record, observe for 24h, or seek '
              'attention right away.',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BigScoreCircle(
                score: score.shortTerm.round(),
                maxScore: 100,
                color: _scoreColor(score.shortTerm),
                label: 'Short-term 24h',
              ),
              _BigScoreCircle(
                score: score.longTerm.round(),
                maxScore: 100,
                color: _scoreColor(score.longTerm),
                label: 'Long-term 28d',
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 각 vital 지표를 막대로 표시(optimal 구간 + 현재값 마커)
          _MetricRangeBar(
            icon: Icons.air,
            label: 'SpO2',
            color: const Color(0xFF4E9AF1),
            value: widget.spo2,
            unit: '%',
            min: 90,
            max: 100,
            optimalLow: 95,
            optimalHigh: 100,
          ),
          _MetricRangeBar(
            icon: Icons.favorite,
            label: 'Heart Rate',
            color: const Color(0xFFFB755B),
            value: widget.hr,
            unit: ' bpm',
            min: 40,
            max: 130,
            optimalLow: 50,
            optimalHigh: 90,
          ),
          _MetricRangeBar(
            icon: Icons.thermostat,
            label: 'Temperature',
            color: const Color(0xFFFF9500),
            value: widget.temp,
            unit: '°C',
            min: 30,
            max: 39,
            optimalLow: 33,
            optimalHigh: 37,
            decimals: 1,
          ),
          const SizedBox(height: 2),
          _SubMetricRow(
            icon: Icons.groups,
            label: 'Baseline',
            value: score.usingPersonalBaseline ? 'Personal' : 'Population',
            note: score.usingPersonalBaseline
                ? 'Using personal baseline'
                : 'Personalizes after 7 days',
            color: score.usingPersonalBaseline
                ? const Color(0xFF34C759)
                : const Color(0xFFFF9500),
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
      help: const [
        _HelpEntry(
          'What it means',
          'A 0–100 score from Samsung Health estimating how much energy you '
              'have available today. Higher means you are better recovered and '
              'ready for activity.',
        ),
        _HelpEntry(
          'Activity',
          'Based on your activity and calories burned the previous day.',
        ),
        _HelpEntry(
          'Sleep',
          'Last night\'s total sleep time and sleep quality feed the score.',
        ),
        _HelpEntry(
          'Sleep HR',
          'Average heart rate during sleep. A lower resting heart rate usually '
              'means better recovery.',
        ),
        _HelpEntry(
          'Sleep HRV',
          'Heart-rate variability during sleep, a marker of nervous-system '
              'recovery. Shown as “--” when your device does not provide it.',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      value: 'Yesterday',
                      color: const Color(0xFF34C759),
                    ),
                    _SubMetricRow(
                      icon: Icons.bedtime,
                      label: 'Sleep',
                      value: totalSleep != null ? widget.summary.totalSleepStr : '--',
                      color: const Color(0xFF5E9BF0),
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
          const SizedBox(height: 14),
          // 수면 중 심박수 — optimal 구간 + 현재값 막대
          _MetricRangeBar(
            icon: Icons.favorite,
            label: 'Sleep HR',
            color: const Color(0xFFFB755B),
            value: sleepHR,
            unit: ' bpm',
            min: 40,
            max: 100,
            optimalLow: 45,
            optimalHigh: 65,
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
      help: [
        _HelpEntry(
          'What it means',
          'A 0–100 score for last night\'s sleep quality from '
              '${Platform.isIOS ? 'Apple Health' : 'Samsung Health'}. It combines '
              'how long and how well you slept.',
        ),
        const _HelpEntry(
          'Total sleep time',
          '7–9 hours scores highest. Sleeping too little or too much lowers '
              'the score.',
        ),
        const _HelpEntry(
          'Sleep cycles',
          'The number of times you entered REM sleep. More complete cycles '
              '(around 4–5) means more restorative sleep.',
        ),
        const _HelpEntry(
          'Awake / restless',
          'Time spent awake or restless during the night. Less is better.',
        ),
        const _HelpEntry(
          'Physical recovery (Deep)',
          'Share of deep sleep, which restores your body. About 20% of total '
              'sleep is ideal.',
        ),
        const _HelpEntry(
          'Mental recovery (REM)',
          'Share of REM sleep, which supports memory and mood. About 25% of '
              'total sleep is ideal.',
        ),
      ],
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
          const SizedBox(height: 4),
          // 회복 지표 — optimal 구간(권장 비율) + 현재값 막대
          _MetricRangeBar(
            icon: Icons.self_improvement,
            label: 'Physical recovery (Deep)',
            color: const Color(0xFF34C759),
            value: total > 0 ? deepPct : null,
            unit: '%',
            min: 0,
            max: 40,
            optimalLow: 15,
            optimalHigh: 25,
          ),
          _MetricRangeBar(
            icon: Icons.psychology,
            label: 'Mental recovery (REM)',
            color: const Color(0xFFFB755B),
            value: total > 0 ? remPct : null,
            unit: '%',
            min: 0,
            max: 40,
            optimalLow: 20,
            optimalHigh: 30,
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

  /// 헤더 우측 도움말(?) 버튼에서 보여줄 설명. null이면 버튼을 숨긴다.
  final List<_HelpEntry>? help;

  const _HealthCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    this.help,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  ],
                ),
              ),
              if (help != null)
                _ScoreHelpButton(
                  title: title,
                  accentColor: iconColor,
                  entries: help!,
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

// ─── 점수 설명(도움말) ─────────────────────────────────────────────────

/// 도움말 모달에 표시할 한 항목(제목 + 설명).
class _HelpEntry {
  final String title;
  final String description;
  const _HelpEntry(this.title, this.description);
}

/// ECG 측정이 무엇을 하는지 설명(Daily Report·기록 화면 상단 도움말 공용).
const _ecgHelpEntries = [
  _HelpEntry(
    'What it does',
    'Measuring an ECG on your watch records your heart\'s electrical activity '
        'to screen for irregular rhythms such as atrial fibrillation.',
  ),
  _HelpEntry(
    'Vital signs captured',
    'Each measurement also collects your SpO2, heart rate and skin '
        'temperature at the same time.',
  ),
  _HelpEntry(
    'Feeds your daily report',
    'These readings automatically update your Health Score, Health Risk and '
        'the rest of your daily report.',
  ),
  _HelpEntry(
    'Saved to records',
    'Every measurement is stored on the calendar under the Records tab, so '
        'you can track your heart health over time.',
  ),
];

/// Daily Report 상단 (?) 버튼에서 보여줄 점수 설명.
const _scoreHelpEntries = [
  _HelpEntry(
    'Health Score',
    'A 0–100 wellness score based on how close your SpO2, heart rate and skin '
        'temperature are to your normal range. Higher is better.',
  ),
  _HelpEntry(
    'Short-term (24h)',
    'Your latest measurement compared with your own baseline — how you are '
        'doing right now.',
  ),
  _HelpEntry(
    'Health Risk',
    'An early-warning check. Each vital gets 0–3 points; the total suggests '
        'whether to simply record, observe for 24h, or seek attention.',
  ),
  _HelpEntry(
    'Tip',
    'Tap the score card to open its detailed metrics and guidance.',
  ),
];

/// 카드 헤더 우측의 (?) 버튼. 탭하면 점수 설명 바텀시트를 연다.
class _ScoreHelpButton extends StatelessWidget {
  final String title;
  final Color accentColor;
  final List<_HelpEntry> entries;

  const _ScoreHelpButton({
    required this.title,
    required this.accentColor,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline, size: 20, color: Colors.grey.shade400),
      tooltip: 'About this score',
      splashRadius: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => _showScoreHelp(context, title, accentColor, entries),
    );
  }
}

void _showScoreHelp(
  BuildContext context,
  String title,
  Color accentColor,
  List<_HelpEntry> entries,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.help_outline, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries) ...[
                        Text(
                          e.title,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accentColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.description,
                          style: const TextStyle(
                              fontSize: 13, height: 1.45, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
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

/// 수치 + 막대로 지표를 표시한다.
/// 회색 트랙 위에 초록색 optimal 구간을 겹치고, 현재값을 원형 마커로 찍는다.
class _MetricRangeBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double? value;
  final String unit;
  final double min;
  final double max;
  final double optimalLow;
  final double optimalHigh;
  final int decimals;

  const _MetricRangeBar({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.optimalLow,
    required this.optimalHigh,
    this.decimals = 0,
  });

  static const _okColor = Color(0xFF34C759);
  static const _warnColor = Color(0xFFFF9500);

  double _frac(double v) =>
      max > min ? ((v - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

  String _fmt(double v) => v.toStringAsFixed(decimals);

  @override
  Widget build(BuildContext context) {
    final v = value;
    final inRange = v != null && v >= optimalLow && v <= optimalHigh;
    final valueColor = v == null ? Colors.grey : (inRange ? _okColor : _warnColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                v != null ? '${_fmt(v)}$unit' : '--',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: valueColor),
              ),
              if (v != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: valueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    inRange ? 'Optimal' : 'Check',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600, color: valueColor),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              const barH = 8.0;
              const markerSize = 14.0;
              final optLeft = _frac(optimalLow) * w;
              final optRight = _frac(optimalHigh) * w;
              final markerLeft = v != null
                  ? (_frac(v) * w - markerSize / 2).clamp(0.0, w - markerSize)
                  : 0.0;
              return SizedBox(
                height: markerSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 전체 트랙
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (markerSize - barH) / 2,
                      child: Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // optimal 구간
                    Positioned(
                      left: optLeft,
                      top: (markerSize - barH) / 2,
                      child: Container(
                        width: (optRight - optLeft).clamp(0.0, w),
                        height: barH,
                        decoration: BoxDecoration(
                          color: _okColor.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 현재값 마커
                    if (v != null)
                      Positioned(
                        left: markerLeft,
                        top: 0,
                        child: Container(
                          width: markerSize,
                          height: markerSize,
                          decoration: BoxDecoration(
                            color: valueColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_fmt(min)}$unit',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              Text('Optimal ${_fmt(optimalLow)}–${_fmt(optimalHigh)}$unit',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _okColor,
                      fontWeight: FontWeight.w600)),
              Text('${_fmt(max)}$unit',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ],
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
