import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

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

  Future<void> _loadData() async {
    try {
      final txtFile = File(widget.txtPath);
      if (!txtFile.existsSync()) {
        debugPrint('❌ TXT 파일이 존재하지 않음');
      } else {
        // Signal 1: txt에서 읽기
        final txtContent = await txtFile.readAsString();
        final rawRecords = txtContent.trim().split(') (');

        List<FlSpot> txtSpots = [];
        for (final record in rawRecords) {
          final clean = record.replaceAll('(', '').replaceAll(')', '');
          final parts = clean.split(',');
          if (parts.length == 2) {
            final y = double.tryParse(parts[0].trim());
            final x = double.tryParse(parts[1].trim()); // 이미 초 단위임
            if (x != null && y != null) {
              txtSpots.add(FlSpot(x, y));
            }
          }
        }

        txtSpots.sort((a, b) => a.x.compareTo(b.x));

        final baseX = txtSpots.first.x;
        final convertedSpots = txtSpots.map((spot) {
          return FlSpot(spot.x - baseX, spot.y); // 0초부터 시작
        }).toList();

        leadData[0] = convertedSpots;

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://34.69.44.173:7000/predict12lead'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', txtFile.path));
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final jsonData = jsonDecode(response.body);
          final resultArray = jsonData['result'];
          final leads = resultArray[0][0].sublist(3, 14); // signal 2~12
          for (int i = 0; i < 11; i++) {
            leadData[i + 1] = List.generate(
              leads[i].length,
                  (j) => FlSpot(j * (10.0 / 512.0), leads[i][j].toDouble()), // ✅ 10초 분포
            );
          }
        } else {
          debugPrint('❌ 서버 오류: ${response.reasonPhrase}');
        }
      }

      // JSON에서 r_peaks, distances 불러오기
      if (widget.jsonPath.isNotEmpty && File(widget.jsonPath).existsSync()) {
        final jsonStr = await File(widget.jsonPath).readAsString();
        final jsonData = jsonDecode(jsonStr);
        if (jsonData['result'] is Map<String, dynamic>) {
          distances = List<double>.from(jsonData['result']['distance_from_median'] ?? []);
          rPeaks = List<int>.from(jsonData['result']['r_peaks'] ?? []);
        }
      }
    } catch (e) {
      debugPrint('❌ 오류: $e');
    }

    setState(() => isLoading = false);
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
      return const Center(child: Text('해당 리드에 대한 데이터가 없습니다.', style: TextStyle(fontSize: 14)));
    }

    final adjustedSpots = spots;

    final xMax = adjustedSpots.last.x;
    final yMin = adjustedSpots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    final yMax = adjustedSpots.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    final chartWidth = xMax * 50 * zoomScale;

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
                minX: 0,
                maxX: xMax,
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
                        final rounded = value.round();
                        return (value - rounded).abs() < 0.05
                            ? Text('${rounded}s', style: const TextStyle(fontSize: 10))
                            : const SizedBox.shrink();
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
                    if (rPeaks.length <= i * 2 + 1 || rPeaks[i * 2 + 1] >= spots.length) return null;
                    final x1 = spots[rPeaks[i * 2]].x;
                    final x2 = spots[rPeaks[i * 2 + 1]].x;

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
        title: const Text('측정 결과', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          //padding: const EdgeInsets.all(10),
          //padding: const EdgeInsets.symmetric(vertical: 10),
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
                  const Text('날짜', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateFormat('yyyy.MM.dd (E) HH시 mm분', 'ko_KR').format(widget.timestamp)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('결과', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.result),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('측정 기기', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(widget.deviceType),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}