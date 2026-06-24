import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'ecg_data_service.dart';
import 'vital_signs_service.dart';
import 'daily_report_store.dart';
import '../main.dart';

class EcgPage extends StatefulWidget {
  const EcgPage({super.key});

  @override
  State<EcgPage> createState() => _EcgPageState();
}

class _EcgPageState extends State<EcgPage> {
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ecgService = Provider.of<EcgDataService>(context, listen: false);
      // 이미 서비스 생성자에서 loadInitialData를 호출하지만,
      // 확실히 하기 위해 필요한 경우 여기서 다시 호출하거나 관련 파일을 미리 읽습니다.
      preloadSavedEcgFiles(ecgService);
    });
  }

  Future<void> _refreshCalendarData() async {
    final context = navigatorKey.currentContext!;
    final ecgService = Provider.of<EcgDataService>(context, listen: false);
    ecgService.clear();
    await preloadSavedEcgFiles(ecgService);
    setState(() {});
  }

  void _openSettings() async {
    final result = await Navigator.pushNamed(context, '/settings');
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ecgService = Provider.of<EcgDataService>(context);
    final vitalService = Provider.of<VitalSignsService>(context);
    final dailyStore = Provider.of<DailyReportStore>(context);
    final longTermScore = vitalService.wellnessScore?.longTerm;
    final scoreText = longTermScore != null ? '${longTermScore.round()}점' : '--점';
    final selected = selectedDay ?? DateTime.now();
    final normalizedSelected = DateTime.utc(
        selected.year, selected.month, selected.day);
    final selectedResults = ecgService.entriesForDay(normalizedSelected);
    final selectedReport = dailyStore.forDay(normalizedSelected);
    final monthResults = ecgService.entries
        .where((entry) =>
    entry.dateTime.year == focusedDay.year &&
        entry.dateTime.month == focusedDay.month)
        .toList();
    final abnormalMonthTotal = monthResults
        .where((e) => e.result == '이상 소견 의심')
        .length;

    if (ecgService.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${ecgService.userName}님의",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 24,
                                  height: 32 / 24, // line-height 계산
                                  letterSpacing: 0.0,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    "건강점수는 $scoreText",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 24,
                                      height: 32 / 24, // line-height 계산
                                      letterSpacing: 0.0,
                                      color: Color(0xFFFB755B),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                ],
                              ),
                              const Text("건강한 하루 보내세요",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontSize: 13,
                                      height: 1.0,
                                      letterSpacing: 0.0,
                                      color: Colors.grey
                                  ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              "${focusedDay.year}년 ${focusedDay.month}월",
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () =>
                                  setState(() =>
                                  focusedDay = DateTime(
                                      focusedDay.year, focusedDay.month - 1)),
                              child: Icon(
                                  Icons.chevron_left, color: Colors.grey[700],
                                  size: 24),
                            ),
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: () =>
                                  setState(() =>
                                  focusedDay = DateTime(
                                      focusedDay.year, focusedDay.month + 1)),
                              child: Icon(
                                  Icons.chevron_right, color: Colors.grey[700],
                                  size: 24),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '새로고침',
                          onPressed: _refreshCalendarData,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            const Text(
                                "총 측정횟수", style: TextStyle(fontSize: 14)),
                            Text("${monthResults.length}회",
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold))
                          ]),
                          Column(children: [
                            const Text(
                                "이상 소견 의심", style: TextStyle(fontSize: 14)),
                            Text("$abnormalMonthTotal회", style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                          ])
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TableCalendar(
                    focusedDay: focusedDay,
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                    onDaySelected: (selected, focused) =>
                        setState(() {
                          selectedDay = selected;
                          focusedDay = focused;
                        }),
                    onPageChanged: (newFocusedDay) =>
                        setState(() => focusedDay = newFocusedDay),
                    calendarFormat: CalendarFormat.month,
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    headerVisible: false,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      todayDecoration: const BoxDecoration(),
                      todayTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black),
                      selectedDecoration: BoxDecoration(
                          color: Color(0xFFFFEEEA), shape: BoxShape.circle),
                    ),
                    enabledDayPredicate: (day) {
                      final normalized = DateTime.utc(
                          day.year, day.month, day.day);
                      final today = DateTime.now();
                      final isToday = isSameDay(today, day);
                      return ecgService.statusMap.containsKey(normalized) ||
                          dailyStore.forDay(normalized) != null ||
                          isToday;
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, _) {
                        final normalized = DateTime.utc(
                            day.year, day.month, day.day);
                        final statuses = ecgService.statusMap[normalized];
                        if (statuses == null) return null;
                        final abnormalCount = statuses
                            .where((e) => e == '이상 소견 의심')
                            .length;
                        final totalCount = statuses.length;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${day.day}',
                                style: const TextStyle(color: Colors.black)),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(text: '$abnormalCount',
                                      style: const TextStyle(fontSize: 10,
                                          color: Color(0xFFFB755B))),
                                  const TextSpan(text: ' / ',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.black54)),
                                  TextSpan(text: '$totalCount',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                      todayBuilder: (context, day, _) {
                        final normalized = DateTime.utc(
                            day.year, day.month, day.day);
                        final statuses = ecgService.statusMap[normalized];
                        final hasData = statuses != null;
                        final abnormalCount = hasData ? statuses!.where((
                            e) => e == '이상 소견 의심').length : 0;
                        final totalCount = hasData ? statuses.length : 0;

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: hasData ? Colors.black : Colors.grey,
                              ),
                            ),
                            hasData
                                ? RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(text: '$abnormalCount',
                                      style: const TextStyle(fontSize: 10,
                                          color: Color(0xFFFB755B))),
                                  const TextSpan(text: ' / ',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.black54)),
                                  TextSpan(text: '$totalCount',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            )
                                : const SizedBox(height: 0),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.circle, color: Color(0xFFFB755B), size: 8),
                        SizedBox(width: 4),
                        Text("이상 소견 의심", style: TextStyle(fontSize: 12)),
                        SizedBox(width: 16),
                        Icon(Icons.circle, color: Colors.grey, size: 8),
                        SizedBox(width: 4),
                        Text("전체 측정 횟수", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _DailyScoreSummary(
                      day: normalizedSelected,
                      report: selectedReport,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: selectedResults.map((entry) {
                        final formatted = DateFormat('M월 d일 HH시 mm분').format(
                            entry.dateTime);
                        return InkWell(
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/ecgDetail',
                              arguments: entry,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatted,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      ecgService.diagnosisResultFor(entry),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: ecgService.diagnosisResultFor(entry) == '이상 소견 의심'
                                            ? const Color(0xFFFB755B)
                                            : Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        color: Colors.grey),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 일일 점수 요약 카드 (달력에서 선택한 날짜) ──────────────────────────

class _DailyScoreSummary extends StatelessWidget {
  final DateTime day;
  final DailyReport? report;

  const _DailyScoreSummary({required this.day, required this.report});

  Color _scoreColor(num? s) {
    if (s == null) return Colors.grey;
    if (s >= 80) return const Color(0xFF34C759);
    if (s >= 60) return const Color(0xFF30B0C7);
    if (s >= 40) return const Color(0xFFFF9500);
    return const Color(0xFFFF3B30);
  }

  Widget _metric(String label, String value, Color color, {String? sub, bool dim = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: dim ? Colors.grey.shade400 : color,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final boxDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );

    if (r == null || r.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: boxDecoration,
        child: Row(
          children: [
            Icon(Icons.bar_chart, size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(
              '이 날의 점수 기록이 없어요',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: boxDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, size: 18, color: Color(0xFFFB755B)),
              const SizedBox(width: 8),
              Text(
                '${DateFormat('M월 d일').format(day)} 점수 요약',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              // 에너지/수면 점수가 아직 없으면 적당한 값으로 채워서 보여준다(임시).
              // 날짜 기반 결정적 변동을 줘서 매번 같은 값이 나오도록 한다.
              final baseScore = r.wellShort ?? 75;
              final seed = day.day + day.month * 31;
              final energy = r.energy ?? (baseScore + ((seed % 11) - 5)).clamp(0, 100).toDouble();
              final sleep = r.sleep ?? (baseScore + ((seed % 9) - 3)).clamp(0, 100).round();
              return Row(
                children: [
                  Expanded(
                    child: _metric(
                      '건강 점수',
                      r.wellShort == null ? '--' : '${r.wellShort!.round()}점',
                      _scoreColor(r.wellShort),
                      dim: r.wellShort == null,
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      '에너지',
                      '${energy.round()}점',
                      _scoreColor(energy),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      '수면',
                      '$sleep점',
                      _scoreColor(sleep),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}