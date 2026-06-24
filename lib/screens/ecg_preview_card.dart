import 'dart:convert';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'ecg_data_service.dart';

/// 리포트 최상단에 표시되는 "오늘의 ECG" 미리보기 카드.
/// ECG 상세(detail)에 나오는 lead I 파형 + 의심 질환(ECG Founder)을 압축해서 보여준다.
/// 탭하면 전체 상세 페이지로 이동.
class TodayEcgCard extends StatefulWidget {
  final EcgEntry entry;
  const TodayEcgCard({super.key, required this.entry});

  @override
  State<TodayEcgCard> createState() => _TodayEcgCardState();
}

class _TodayEcgCardState extends State<TodayEcgCard> {
  List<FlSpot> _spots = [];
  List<String> _diagnoses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _sanitize(String s) => s
      .replaceAll(RegExp(r'\bNaN\b'), 'null')
      .replaceAll(RegExp(r'-?\bInfinity\b'), 'null');

  Future<void> _load() async {
    try {
      final f = File(widget.entry.txtPath);
      if (widget.entry.txtPath.isNotEmpty && f.existsSync()) {
        final content = await f.readAsString();
        final records = content.trim().split(') (');
        final spots = <FlSpot>[];
        final raw = <List<double>>[];
        for (final r in records) {
          final clean = r.replaceAll('(', '').replaceAll(')', '');
          final parts = clean.split(',');
          if (parts.length == 2) {
            final y = double.tryParse(parts[0].trim());
            final x = double.tryParse(parts[1].trim());
            if (x != null && y != null) {
              spots.add(FlSpot(x, y));
              raw.add([y, x]);
            }
          }
        }
        spots.sort((a, b) => a.x.compareTo(b.x));
        final baseX = spots.isNotEmpty ? spots.first.x : 0.0;
        _spots = spots.map((s) => FlSpot(s.x - baseX, s.y)).toList();

        final diag = await _founderDiagnoses(raw, 512);
        if (diag != null) _diagnoses = diag;
      }
    } catch (e) {
      debugPrint('⚠️ TodayEcgCard 로드 실패: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<List<String>?> _founderDiagnoses(
      List<List<double>> rawData, int samplingRate) async {
    if (rawData.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('http://35.216.60.242:9102/ecg_founder/single_ecg'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sampling_rate': samplingRate, 'data': rawData}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      final result = jsonDecode(_sanitize(res.body));
      final out = <String>[];
      if (result['ecg_founder_results'] is List) {
        const targets = {'AMI', 'IMI', 'LMI'};
        for (final item in result['ecg_founder_results']) {
          if (item is Map<String, dynamic>) {
            final p = item['probability'];
            final d = item['diagnosis'];
            final prob = p is num ? p.toDouble() : double.tryParse('$p');
            if (prob != null && prob >= 0.7 && targets.contains('$d')) {
              out.add('$d');
            }
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('⚠️ ECG Founder 호출 실패: $e');
      return null;
    }
  }

  Widget _miniChart() {
    if (_spots.isEmpty) {
      return Center(
        child: Text('No waveform data',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      );
    }
    final maxXall = _spots.last.x;
    // 신호가 충분히 길면 5~13초(잡음 많은 도입부 제외) 구간만, 아니면 전체
    final winStart = maxXall > 15 ? 5.0 : _spots.first.x;
    final winEnd = maxXall > 15 ? 13.0 : maxXall;
    final visible =
        _spots.where((s) => s.x >= winStart && s.x <= winEnd).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final ys = visible.map((e) => e.y).toList()..sort();
    final q1 = ys[(ys.length * 0.25).toInt()];
    final q2 = ys[(ys.length * 0.5).toInt()];
    final q3 = ys[(ys.length * 0.75).toInt()];
    final iqr = (q3 - q1).abs();
    const k = 7.0;
    final yMin = q2 - iqr * k;
    final yMax = q2 + iqr * k;

    return LineChart(
      LineChartData(
        minX: winStart,
        maxX: winEnd,
        minY: yMin,
        maxY: yMax == yMin ? yMin + 1 : yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          verticalInterval: 0.2, // ECG 0.2초 격자
          horizontalInterval:
              ((yMax - yMin) / 8).clamp(0.1, double.infinity),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: Color(0x33FB755B), strokeWidth: 0.5),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0x33FB755B), strokeWidth: 0.5),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: visible,
            isCurved: false,
            barWidth: 1.2,
            color: const Color(0xFFFB755B),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cached = Provider.of<EcgDataService>(context, listen: false)
        .diagnosisResultFor(widget.entry);
    final hasDiag = _diagnoses.isNotEmpty;
    final abnormal = hasDiag || cached == 'Abnormality suspected';
    final diagText = hasDiag
        ? _diagnoses.join(', ')
        : (abnormal ? 'Abnormality suspected' : 'No suspected conditions');
    final accent = abnormal ? const Color(0xFFFF3B30) : const Color(0xFF34C759);

    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/ecgDetail', arguments: widget.entry),
      child: Container(
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
                    color: const Color(0xFFFB755B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.monitor_heart,
                      color: Color(0xFFFB755B), size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Today\'s ECG',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Color(0xFFFB755B)),
                      ),
                    )
                  : _miniChart(),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Suspected conditions',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_loading)
                  Text('Analyzing…',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade500))
                else
                  Flexible(
                    child: Text(
                      diagText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
