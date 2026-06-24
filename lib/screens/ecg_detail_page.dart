import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'ecg_data_service.dart';

class EcgDetailPage extends StatefulWidget {
  final String txtPath;
  final String jsonPath;
  final DateTime timestamp;
  final String result;
  final String deviceType;

  const EcgDetailPage({
    super.key,
    required this.txtPath,
    required this.jsonPath,
    required this.timestamp,
    required this.result,
    required this.deviceType,
  });

  @override
  State<EcgDetailPage> createState() => _EcgDetailPageState();
}

class _EcgDetailPageState extends State<EcgDetailPage> {
  int selectedLead = 0;
  List<List<FlSpot>> leadData = List.generate(12, (_) => []);
  List<int> rPeaks = [];
  List<double> distances = [];
  bool isLoading = true;
  double zoomScale = 1.0;
  final ScrollController _scrollController = ScrollController();
  final TransformationController _transformationController = TransformationController();
  List<String> highProbabilityDiagnoses = []; // 추가

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  String sanitizeJson(String jsonString) {
    return jsonString
        .replaceAll(RegExp(r'\bNaN\b'), 'null')
        .replaceAll(RegExp(r'\bInfinity\b'), 'null')
        .replaceAll(RegExp(r'-Infinity\b'), 'null');
  }

  Future<Map<String, dynamic>> _postToEcgFounder(List<List<double>> rawData, int samplingRate) async {
    List<String> highProbabilityDiagnoses = [];
    List<List<FlSpot>> reconstructedLeads = List.generate(12, (_) => []);

    try {
      final url = Uri.parse('http://35.216.60.242:9102/ecg_founder/single_ecg');

      final body = jsonEncode({
        'sampling_rate': samplingRate,
        'data': rawData,
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final cleanedBody = sanitizeJson(response.body);
        final result = jsonDecode(cleanedBody);

        // 12-lead 재구성 데이터 파싱 (m_ecg_net_results: 12 x 512)
        if (result['m_ecg_net_results'] != null && result['m_ecg_net_results'] is List) {
          final leads = result['m_ecg_net_results'] as List;
          for (int i = 0; i < leads.length && i < 12; i++) {
            final samples = leads[i] as List;
            reconstructedLeads[i] = List.generate(
              samples.length,
              (j) => FlSpot(j * (10.0 / 512.0), (samples[j] as num).toDouble()),
            );
          }
        }

        // 진단 결과 파싱
        if (result['ecg_founder_results'] != null && result['ecg_founder_results'] is List) {
          final diagnosisResults = result['ecg_founder_results'] as List;
          for (var item in diagnosisResults) {
            if (item is Map<String, dynamic>) {
              final probability = item['probability'];
              final diagnosis = item['diagnosis'];
              if (probability != null && diagnosis != null) {
                final prob = (probability is num) ? probability.toDouble() : double.tryParse(probability.toString());
                const _targetDiseases = {'AMI', 'IMI', 'LMI'};
                if (prob != null && prob >= 0.7 && _targetDiseases.contains(diagnosis.toString())) {
                  highProbabilityDiagnoses.add(diagnosis.toString());
                }
              }
            }
          }
        }
      } else {
        debugPrint('❌ ECG Founder API Error: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ECG Founder Post Error: $e');
      debugPrint('StackTrace: $stackTrace');
    }

    return {
      'diagnoses': highProbabilityDiagnoses,
      'leads': reconstructedLeads,
    };
  }

  Future<void> _loadData() async {
    try {
      final txtFile = File(widget.txtPath);
      if (txtFile.existsSync()) {
        // 1. TXT 파일 처리
        final txtContent = await txtFile.readAsString();
        final rawRecords = txtContent.trim().split(') (');
        List<FlSpot> txtSpots = [];
        List<List<double>> rawData = []; // 2D 배열로 변경

        for (final record in rawRecords) {
          final clean = record.replaceAll('(', '').replaceAll(')', '');
          final parts = clean.split(',');
          if (parts.length == 2) {
            final y = double.tryParse(parts[0].trim());
            final x = double.tryParse(parts[1].trim());
            if (x != null && y != null) {
              txtSpots.add(FlSpot(x, y));
              rawData.add([y, x]); // [y값, x값(시간)] 형태로 저장
            }
          }
        }
        txtSpots.sort((a, b) => a.x.compareTo(b.x));
        final baseX = txtSpots.isNotEmpty ? txtSpots.first.x : 0;
        leadData[0] = txtSpots.map((s) => FlSpot(s.x - baseX, s.y)).toList();

        // 2. ECG Founder 실행 (12-lead 재구성 + 진단 결과 동시 처리)
        final ecgResult = await _postToEcgFounder(rawData, 512);

        // 상태 업데이트
        if (mounted) {
          final diagnoses = ecgResult['diagnoses'] as List<String>;
          setState(() {
            highProbabilityDiagnoses = diagnoses;
            final reconstructed = ecgResult['leads'] as List<List<FlSpot>>;
            for (int i = 1; i < 12; i++) {
              if (reconstructed[i].isNotEmpty) {
                leadData[i] = reconstructed[i];
              }
            }
          });
          // ECG Founder 결과를 리스트 페이지에 반영
          final diagnosisResult = diagnoses.isEmpty ? 'Normal' : 'Abnormality suspected';
          if (widget.txtPath.isNotEmpty) {
            Provider.of<EcgDataService>(context, listen: false)
                .updateDiagnosisResult(widget.txtPath, diagnosisResult);
          }
        }
      }

      // 4. 로컬 JSON 파일 처리 (r_peaks, distances)
      if (widget.jsonPath.isNotEmpty && File(widget.jsonPath).existsSync()) {
        final jsonStr = await File(widget.jsonPath).readAsString();
        final cleanedJsonStr = sanitizeJson(jsonStr);
        final jsonData = jsonDecode(cleanedJsonStr);

        var targetData = jsonData['result'] ?? jsonData;

        if (targetData is Map<String, dynamic>) {
          distances = List<double>.from(targetData['distance_from_median'] ?? [])
              .map((e) => (e as num).toDouble())
              .toList();
          rPeaks = List<int>.from(targetData['r_peaks'] ?? [])
              .map((e) => e as int)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('❌ 최종 오류 처리: $e');
    }

    if (mounted) setState(() => isLoading = false);
  }



  Widget _buildLeadButtons() {
    final leadLabels = ['I', 'II', 'III', 'aVR', 'aVL', 'aVF', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'];

    return Column(
      children: List.generate(3, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (colIndex) {
              final index = rowIndex * 4 + colIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: SizedBox(
                  width: 80,
                  height: 35,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedLead == index ? const Color(0xFFFB755B) : Colors.white,
                      foregroundColor: selectedLead == index ? Colors.white : Colors.black,
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        selectedLead = index;
                        zoomScale = 1.0;
                      });
                    },
                    child: Text(
                      leadLabels[index],
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  double baseScale = 1.0; // 클래스 바깥 or 클래스 맨 위에 추가

  Widget _buildChart() {
    final spots = leadData[selectedLead];
    final isFirstSignal = selectedLead == 0;

    if (spots.isEmpty) {
      return const Center(child: Text('No data for this lead.', style: TextStyle(fontSize: 14)));
    }

    final adjustedSpots = isFirstSignal
        ? spots.where((s) => s.x >= 5.0).toList()
        : spots;

    // 2. 차트 범위 설정
    final double minX = isFirstSignal ? 5.0 : adjustedSpots.first.x;
    final double maxX = isFirstSignal ? 30.0 : adjustedSpots.last.x;

    // --- [여기서부터 수정] ---

    // 1. Y값들만 추출해서 정렬 (중앙값과 사분위수를 구하기 위함)
    final List<double> yValues = spots.map((e) => e.y).toList()..sort();

    // 2. 사분위수 계산 (데이터의 상위 25%, 50%, 75% 지점)
    final double q1 = yValues[(yValues.length * 0.25).toInt()];
    final double q2 = yValues[(yValues.length * 0.5).toInt()]; // 중앙값
    final double q3 = yValues[(yValues.length * 0.75).toInt()];
    final double iqr = q3 - q1; // 데이터가 밀집된 구간의 폭

    // 3. 중앙값(q2)을 기준으로 '멀어지면 보이게' 스케일 설정
    // 보통 IQR의 5~8배 정도면 R-Peak까지 다 포함하고, -40 같은 노이즈는 무시합니다.
    final double k = 7.0;
    final double yMin = q2 - (iqr * k);
    final double yMax = q2 + (iqr * k);

    // --- [여기까지 수정] ---

    final chartWidth = (maxX - minX) * 50 * zoomScale;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        baseScale = zoomScale;
      },
      onScaleUpdate: (details) {
        setState(() {
          //final newScale = baseScale * details.scale;
          final newScale = baseScale * (1 + (details.scale - 1) * 10);
          zoomScale = newScale.clamp(1.0, 4.0);
        });
      },
      child: Container(
        height: 500,
        color: Colors.transparent,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal, // 좌우만 스크롤 가능
          physics: const ClampingScrollPhysics(), // bounce 제거
          child: SizedBox(
            width: chartWidth,
            height: 300,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: yMin,
                maxY: yMax,
                clipData: FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  verticalInterval: 1,
                  horizontalInterval: ((yMax - yMin) / 5).clamp(0.1, double.infinity),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: Colors.grey.shade300,
                    strokeWidth: 0.5,
                  ),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade300,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final displayValue = isFirstSignal ? (value - 5.0).round() : value.round();
                        if ((value - value.round()).abs() < 0.05 && displayValue >= 0) {
                          return Text('${displayValue}s', style: const TextStyle(fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(enabled: false),
                rangeAnnotations: isFirstSignal
                    ? RangeAnnotations(
                  verticalRangeAnnotations: List.generate(distances.length ~/ 2, (i) {
                    // 1. 거리가 0.31 미만이면 그리지 않음 (null 반환)
                    if (distances[i] < 0.31) return null;

                    // 2. rPeaks 인덱스 유효성 검사 (기존 로직 유지)
                    if (rPeaks.length <= i * 2 + 1 || rPeaks[i * 2 + 1] >= spots.length) return null;

                    final x1 = spots[rPeaks[i * 2]].x;
                    final x2 = spots[rPeaks[i * 2 + 1]].x;

                    // 3. 화면 범위 밖(5초 이전)이면 그리지 않음
                    if (x2 < 5.0) return null;

                    return VerticalRangeAnnotation(
                      x1: x1,
                      x2: x2,
                      color: const Color(0x33FB755B),
                    );
                  }).whereType<VerticalRangeAnnotation>().toList(),
                )
                    : const RangeAnnotations(),
                lineBarsData: [
                  if (isFirstSignal)
                    ...List.generate(distances.length ~/ 2, (i) {
                      final x1 = rPeaks[i * 2];
                      final x2 = rPeaks[i * 2 + 1];
                      if (x2 >= spots.length) return null;
                      final rangeSpots = spots
                          .where((e) => e.x >= spots[x1].x && e.x <= spots[x2].x)
                          .map((e) => FlSpot(e.x * zoomScale, e.y))
                          .toList();
                      return LineChartBarData(
                        spots: rangeSpots,
                        isCurved: false,
                        barWidth: 0,
                        color: Colors.transparent,
                        dotData: FlDotData(show: false),
                      );
                    }).whereType<LineChartBarData>(),

                  LineChartBarData(
                    spots: adjustedSpots,
                    isCurved: false,
                    barWidth: 1,
                    color: const Color(0xFFFB755B),
                    dotData: FlDotData(show: false),
                  ),

                  if (isFirstSignal)
                    LineChartBarData(
                      spots: rPeaks
                          .where((idx) => idx < spots.length && spots[idx].x >= 5.0)
                          .map((idx) => FlSpot(spots[idx].x, spots[idx].y))
                          .toList(),
                      isCurved: false,
                      color: Colors.transparent,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 2,
                          strokeWidth: 1,
                          color: const Color(0xFFF9FAFE),
                          strokeColor: const Color(0xFFFB755B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Measurement Result', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.7,
                child: _buildChart(),
              ),
              const SizedBox(height: 20),
              _buildLeadButtons(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateFormat('yyyy.MM.dd (E) HH:mm', 'en_US').format(widget.timestamp)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Device', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.deviceType),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Suspected conditions', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      highProbabilityDiagnoses.isEmpty
                          ? 'No suspected conditions'
                          : highProbabilityDiagnoses.join(', '),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: highProbabilityDiagnoses.isEmpty
                            ? Colors.black
                            : const Color(0xFFFB755B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}