import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'vital_signs_service.dart';

class VitalSignsPage extends StatefulWidget {
  const VitalSignsPage({super.key});

  @override
  State<VitalSignsPage> createState() => _VitalSignsPageState();
}

class _VitalSignsPageState extends State<VitalSignsPage> {
  bool _isLoading = false;

  Future<void> _handleLoadButton() async {
    setState(() => _isLoading = true);
    try {
      await Provider.of<VitalSignsService>(context, listen: false)
          .fetchVitalSigns();
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'NO_DATA') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('측정 데이터 없음', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text(
              '최근 24시간 내 바이탈 데이터가 없습니다.\n\nApple Watch에서 산소포화도, 심박수, 피부 온도를 측정한 후 다시 조회해 주세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인', style: TextStyle(color: Color(0xFFFB755B))),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 조회 실패: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('데이터 조회 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          '바이탈 사인',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Consumer<VitalSignsService>(
            builder: (context, service, _) {
              if (!service.hasData) {
                return _EmptyState();
              }
              return _DataView(service: service);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFF8F9FA).withOpacity(0),
                    const Color(0xFFF8F9FA),
                  ],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFB755B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  onPressed: _isLoading ? null : _handleLoadButton,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          '데이터 조회',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
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
                      '바이탈 데이터를 조회하고 있어요\n잠시만 기다려주세요',
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
            '측정된 바이탈 데이터가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '워치에서 ECG를 측정하면\nSpO2, 심박수, 피부 온도가 표시됩니다',
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

  const _DataView({required this.service});

  @override
  Widget build(BuildContext context) {
    final timeStr = service.lastUpdated != null
        ? DateFormat('yyyy.MM.dd HH:mm').format(service.lastUpdated!)
        : '-';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            const Icon(Icons.access_time, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              '마지막 측정: $timeStr',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (service.wellnessScore != null) ...[
          _WellnessScoreCard(score: service.wellnessScore!),
          const SizedBox(height: 14),
        ],

        if (service.lastNews2Result != null) ...[
          _News2Card(result: service.lastNews2Result!),
          const SizedBox(height: 14),
        ],

        _VitalCard(
          title: '산소포화도 (SpO2)',
          icon: Icons.air,
          iconColor: const Color(0xFF4E9AF1),
          currentValue: '${service.spo2Last}%',
          unit: '%',
          avg: service.spo2Avg,
          min: service.spo2Min.toDouble(),
          max: service.spo2Max.toDouble(),
          dataPoints: service.spo2Data.map((e) => e.toDouble()).toList(),
          lineColor: const Color(0xFF4E9AF1),
          minY: (service.spo2Min - 3).toDouble().clamp(80, 94),
          maxY: 101,
        ),
        const SizedBox(height: 14),

        _VitalCard(
          title: '심박수 (Heart Rate)',
          icon: Icons.favorite,
          iconColor: const Color(0xFFFB755B),
          currentValue: '${service.hrLast}',
          unit: 'bpm',
          avg: service.hrAvg,
          min: service.hrMin.toDouble(),
          max: service.hrMax.toDouble(),
          dataPoints: service.heartRateData.map((e) => e.toDouble()).toList(),
          lineColor: const Color(0xFFFB755B),
          minY: (service.hrMin - 5).toDouble().clamp(30, 50),
          maxY: (service.hrMax + 5).toDouble(),
        ),
        const SizedBox(height: 14),

        _VitalCard(
          title: '피부 온도 (Skin Temp)',
          icon: Icons.thermostat,
          iconColor: const Color(0xFFFF9500),
          currentValue: service.tempLast.toStringAsFixed(1),
          unit: '°C',
          avg: service.tempAvg,
          min: service.tempMin,
          max: service.tempMax,
          dataPoints: service.skinTempData,
          lineColor: const Color(0xFFFF9500),
          minY: (service.tempMin - 1).clamp(25.0, 30.0),
          maxY: service.tempMax + 1,
          isDouble: true,
        ),
      ],
    );
  }
}

// ─── Wellness Score Card ─────────────────────────────────────────────

class _WellnessScoreCard extends StatelessWidget {
  final WellnessScore score;

  const _WellnessScoreCard({required this.score});

  Color _scoreColor(double s) {
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF30B0C7);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  String _scoreLabel(double s) {
    if (s >= 80) return '좋음';
    if (s >= 60) return '양호';
    if (s >= 40) return '주의';
    return '나쁨';
  }

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
                  color: const Color(0xFF34C759).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.spa, color: Color(0xFF34C759), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                '건강점수 (Wellness Score)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (!score.usingPersonalBaseline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    '인구 기준',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ScoreCircle(
                  label: '단기 (24h)',
                  score: score.shortTerm,
                  color: _scoreColor(score.shortTerm),
                  statusLabel: _scoreLabel(score.shortTerm),
                ),
              ),
              Container(
                width: 1,
                height: 80,
                color: Colors.grey.shade100,
              ),
              Expanded(
                child: _ScoreCircle(
                  label: '장기 (28일)',
                  score: score.longTerm,
                  color: _scoreColor(score.longTerm),
                  statusLabel: _scoreLabel(score.longTerm),
                ),
              ),
            ],
          ),
          if (!score.usingPersonalBaseline) ...[
            const SizedBox(height: 10),
            Text(
              '7일 이상 데이터 누적 시 개인 baseline이 적용됩니다',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  final String label;
  final double score;
  final Color color;
  final String statusLabel;

  const _ScoreCircle({
    required this.label,
    required this.score,
    required this.color,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: score / 100.0,
                strokeWidth: 7,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(
              score.round().toString(),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          statusLabel,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

// ─── NEWS2 Card ──────────────────────────────────────────────────────

class _News2Card extends StatelessWidget {
  final News2Result result;

  const _News2Card({required this.result});

  Color get _actionColor {
    switch (result.action) {
      case News2Action.recordOnly:     return const Color(0xFF34C759);
      case News2Action.observe24h:    return const Color(0xFFFF9500);
      case News2Action.immediateAlert: return const Color(0xFFFF3B30);
    }
  }

  IconData get _actionIcon {
    switch (result.action) {
      case News2Action.recordOnly:     return Icons.check_circle_outline;
      case News2Action.observe24h:    return Icons.schedule;
      case News2Action.immediateAlert: return Icons.warning_amber_rounded;
    }
  }

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
                  color: _actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_actionIcon, color: _actionColor, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                '건강 위험도',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  result.action.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _actionColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${result.total}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: _actionColor,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '점',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (result.items.containsKey('spo2'))
                    _News2ItemRow(label: 'SpO2', score: result.items['spo2']!),
                  if (result.items.containsKey('hr'))
                    _News2ItemRow(label: '심박수', score: result.items['hr']!),
                  if (result.items.containsKey('skinTemp'))
                    _News2ItemRow(label: '체온', score: result.items['skinTemp']!),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _actionColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: _actionColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result.action.description,
                    style: TextStyle(fontSize: 12, color: _actionColor),
                  ),
                ),
              ],
            ),
          ),
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

// ─── Vital Sign Detail Card ──────────────────────────────────────────

class _VitalCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String currentValue;
  final String unit;
  final double avg;
  final double min;
  final double max;
  final List<double> dataPoints;
  final Color lineColor;
  final double minY;
  final double maxY;
  final bool isDouble;

  const _VitalCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.currentValue,
    required this.unit,
    required this.avg,
    required this.min,
    required this.max,
    required this.dataPoints,
    required this.lineColor,
    required this.minY,
    required this.maxY,
    this.isDouble = false,
  });

  String _fmt(double v) =>
      isDouble ? v.toStringAsFixed(1) : v.round().toString();

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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currentValue,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 16,
                    color: iconColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatRow(label: '평균', value: '${_fmt(avg)} $unit'),
                  _StatRow(label: '최저', value: '${_fmt(min)} $unit'),
                  _StatRow(label: '최고', value: '${_fmt(max)} $unit'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (dataPoints.length >= 2)
            SizedBox(
              height: 80,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: dataPoints
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      color: lineColor,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: lineColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 6),
          Text(
            '총 ${dataPoints.length}개 측정값',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            '$label  ',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
