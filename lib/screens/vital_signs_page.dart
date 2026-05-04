import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'vital_signs_service.dart';

class VitalSignsPage extends StatelessWidget {
  const VitalSignsPage({super.key});

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
      body: Consumer<VitalSignsService>(
        builder: (context, service, _) {
          if (!service.hasData) {
            return _EmptyState();
          }
          return _DataView(service: service);
        },
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
          Icon(
            Icons.favorite_border,
            size: 72,
            color: Colors.grey.shade300,
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 마지막 측정 시각
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

        // SpO2 카드
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

        // 심박수 카드
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

        // 피부 온도 카드
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
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 행
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha:0.12),
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

          // 현재값 + 통계
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
                    color: iconColor.withValues(alpha:0.8),
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

          // 차트
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
                        color: lineColor.withValues(alpha:0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 데이터 포인트 수 표시
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
