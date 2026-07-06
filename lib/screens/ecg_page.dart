import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'ecg_data_service.dart';
import 'daily_report_store.dart';
import 'ecg_preview_card.dart';
import '../main.dart';

class EcgPage extends StatefulWidget {
  const EcgPage({super.key});

  @override
  State<EcgPage> createState() => _EcgPageState();
}

class _EcgPageState extends State<EcgPage> {
  // 리포트에서 보고 있는 달(월 단위). 상세 달력은 별도 페이지에서 관리한다.
  DateTime reportMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ecgService = Provider.of<EcgDataService>(context, listen: false);
      preloadSavedEcgFiles(ecgService);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ecgService = Provider.of<EcgDataService>(context);
    final dailyStore = Provider.of<DailyReportStore>(context);

    // 이번 달 / 지난 달 평균 통계 (Monthly Report 비교용)
    final prevMonth = DateTime(reportMonth.year, reportMonth.month - 1);
    final curStat =
        _monthStat(dailyStore, ecgService, reportMonth.year, reportMonth.month);
    final prevStat =
        _monthStat(dailyStore, ecgService, prevMonth.year, prevMonth.month);

    if (ecgService.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MonthlyReport(
                  month: reportMonth,
                  current: curStat,
                  previous: prevStat,
                  onInfo: () => _showEcgInfo(context),
                  onPrevMonth: () => setState(() => reportMonth =
                      DateTime(reportMonth.year, reportMonth.month - 1)),
                  onNextMonth: () => setState(() => reportMonth =
                      DateTime(reportMonth.year, reportMonth.month + 1)),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CalendarRecordsPage()),
                    ),
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('View calendar & records'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFB755B),
                      side: const BorderSide(color: Color(0xFFFB755B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 달력 · 상세 기록 페이지 ───────────────────────────────────────────
// 기존 기록 화면의 달력/일별 요약/측정 목록을 이 페이지로 옮겼다.

/// 달력 + 일별 요약 + 측정 목록을 보여주는 재사용 뷰(스캐폴드 없음).
/// Records Calendar 페이지와 ECG Research 페이지에서 공용으로 사용한다.
class CalendarRecordsView extends StatefulWidget {
  const CalendarRecordsView({super.key});

  @override
  State<CalendarRecordsView> createState() => _CalendarRecordsViewState();
}

class _CalendarRecordsViewState extends State<CalendarRecordsView> {
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay = DateTime.now();

  Future<void> _refreshCalendarData() async {
    final ecgService = Provider.of<EcgDataService>(context, listen: false);
    ecgService.clear();
    await preloadSavedEcgFiles(ecgService);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ecgService = Provider.of<EcgDataService>(context);
    final dailyStore = Provider.of<DailyReportStore>(context);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(
                              DateTime(focusedDay.year, focusedDay.month)),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => focusedDay = DateTime(
                              focusedDay.year, focusedDay.month - 1)),
                          child: Icon(Icons.chevron_left,
                              color: Colors.grey[700], size: 24),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: () => setState(() => focusedDay = DateTime(
                              focusedDay.year, focusedDay.month + 1)),
                          child: Icon(Icons.chevron_right,
                              color: Colors.grey[700], size: 24),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                          onPressed: _refreshCalendarData,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            Text("Total measurements",
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(height: 4),
                            Text("${monthResults.length}",
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700))
                          ]),
                          Column(children: [
                            Text("Abnormal findings",
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(height: 4),
                            Text("$abnormalMonthTotal",
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFB755B)))
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
                        final abnormalCount = hasData
                            ? statuses.where((e) => e == '이상 소견 의심').length
                            : 0;
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
                        Text("Abnormal", style: TextStyle(fontSize: 12)),
                        SizedBox(width: 16),
                        Icon(Icons.circle, color: Colors.grey, size: 8),
                        SizedBox(width: 4),
                        Text("Total measurements", style: TextStyle(fontSize: 12)),
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
                        final formatted = DateFormat('MMM d, HH:mm').format(
                            entry.dateTime);
                        final diagnosis = ecgService.diagnosisResultFor(entry);
                        final isAbnormal = diagnosis == '이상 소견 의심';
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
                                      isAbnormal ? 'Abnormal' : 'Normal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isAbnormal
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
    );
  }
}

// ─── Records Calendar 페이지 (CalendarRecordsView 래퍼) ─────────────────

class CalendarRecordsPage extends StatelessWidget {
  const CalendarRecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Records Calendar',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 24),
        child: CalendarRecordsView(),
      ),
    );
  }
}

// ─── ECG Research 페이지 ───────────────────────────────────────────────
// 1-lead 미리보기 + Deep research(→ 12-lead) + 달력/과거 기록.

class EcgResearchPage extends StatelessWidget {
  const EcgResearchPage({super.key});

  EcgEntry? _latestEcg(EcgDataService s) {
    final today = s.entriesForDay(DateTime.now());
    final list = today.isNotEmpty ? today : List<EcgEntry>.from(s.entries);
    if (list.isEmpty) return null;
    list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    final ecgService = Provider.of<EcgDataService>(context);
    final latest = _latestEcg(ecgService);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('ECG Research',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // 1-lead 미리보기 (Daily Report와 동일)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: latest != null
                  ? TodayEcgCard(entry: latest)
                  : _emptyLeadCard(),
            ),
            const SizedBox(height: 14),
            // Deep research + ? → 12-lead reconstruction
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: latest == null
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TwelveLeadReconstructionPage(
                                      entry: latest),
                                ),
                              ),
                      icon: const Icon(Icons.biotech, color: Colors.white),
                      label: const Text('Deep research',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5E5CE6),
                        disabledBackgroundColor:
                            const Color(0xFF5E5CE6).withValues(alpha: 0.5),
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
                      onPressed: () => _showDeepResearchInfo(context),
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Color(0xFF5E5CE6)),
                        foregroundColor: const Color(0xFF5E5CE6),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.help_outline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Past records',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.3)),
            ),
            // 달력 + 과거 ECG (기록 탭과 동일)
            const CalendarRecordsView(),
          ],
        ),
      ),
    );
  }

  Widget _emptyLeadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
      child: Column(
        children: [
          Icon(Icons.monitor_heart_outlined,
              size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text('No ECG recorded yet',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Measure an ECG to enable deep research',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  void _showDeepResearchInfo(BuildContext context) {
    const accent = Color(0xFF5E5CE6);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
              const Row(
                children: [
                  Icon(Icons.biotech, color: accent, size: 20),
                  SizedBox(width: 8),
                  Text('Deep research',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Deep research reconstructs a full 12-lead ECG from your '
                'single-lead watch recording, so clinicians can review your '
                'heart from multiple angles.',
                style: TextStyle(fontSize: 13, height: 1.45, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 12-Lead Reconstruction 페이지 (뼈대) ──────────────────────────────

class TwelveLeadReconstructionPage extends StatelessWidget {
  final EcgEntry entry;
  const TwelveLeadReconstructionPage({super.key, required this.entry});

  static const _leads = [
    'I', 'II', 'III', 'aVR', 'aVL', 'aVF',
    'V1', 'V2', 'V3', 'V4', 'V5', 'V6',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('12-Lead Reconstruction',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF5E5CE6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Color(0xFF5E5CE6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reconstructed from your single-lead recording on '
                      '${DateFormat('MMM d, HH:mm').format(entry.dateTime)}.',
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.4, color: Color(0xFF3A3897)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 12개 리드 그리드 (플레이스홀더 파형)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final lead in _leads) _LeadTile(lead: lead),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Note: 12-lead reconstruction model is not connected yet — the '
              'waveforms above are placeholders.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadTile extends StatelessWidget {
  final String lead;
  const _LeadTile({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lead,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5E5CE6))),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _PlaceholderEcgPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 리서치 뼈대용 임시 ECG 파형(장식). 실제 재구성 데이터가 아니다.
class _PlaceholderEcgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFB755B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    final midY = size.height * 0.6;
    path.moveTo(0, midY);
    final n = 2; // 2 beats
    final beatW = size.width / n;
    for (var i = 0; i < n; i++) {
      final x0 = beatW * i;
      path.lineTo(x0 + beatW * 0.15, midY);
      path.lineTo(x0 + beatW * 0.22, midY - size.height * 0.08); // P
      path.lineTo(x0 + beatW * 0.30, midY);
      path.lineTo(x0 + beatW * 0.38, midY + size.height * 0.10); // Q
      path.lineTo(x0 + beatW * 0.44, midY - size.height * 0.55); // R
      path.lineTo(x0 + beatW * 0.50, midY + size.height * 0.20); // S
      path.lineTo(x0 + beatW * 0.62, midY);
      path.lineTo(x0 + beatW * 0.72, midY - size.height * 0.12); // T
      path.lineTo(x0 + beatW * 0.82, midY);
      path.lineTo(x0 + beatW, midY);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Monthly Report (한 달 평균 + 지난달 대비) ─────────────────────────

/// 한 달치 평균 통계. `avg[key]`에 지표별 평균(없으면 null)이 담긴다.
class _MonthStat {
  final Map<String, double?> avg;
  final int measures;  // ECG 측정 횟수
  final int abnormal;  // 이상 소견 의심 횟수

  const _MonthStat({
    required this.avg,
    required this.measures,
    required this.abnormal,
  });

  double? operator [](String key) => avg[key];
}

/// 특정 연/월의 지표별 평균 통계를 계산한다.
_MonthStat _monthStat(
    DailyReportStore store, EcgDataService ecg, int year, int month) {
  final acc = <String, List<double>>{};
  void add(String key, num? v) {
    if (v != null) (acc[key] ??= <double>[]).add(v.toDouble());
  }

  store.reports.forEach((key, r) {
    final parts = key.split('-');
    if (parts.length != 3) return;
    if (int.tryParse(parts[0]) != year || int.tryParse(parts[1]) != month) {
      return;
    }
    add('health', r.wellShort);
    add('energy', r.energy);
    add('sleep', r.sleep);
    final d = r.details;
    if (d != null) {
      add('totalSleep', d['totalSleepMinutes'] as num?);
      add('deep', d['deepSleepMinutes'] as num?);
      add('rem', d['remSleepMinutes'] as num?);
      add('sleepHR', d['sleepHR'] as num?);
      add('spo2', (d['spo2'] as Map?)?['avg'] as num?);
      add('hr', (d['hr'] as Map?)?['avg'] as num?);
      add('temp', (d['skinTemp'] as Map?)?['avg'] as num?);
    }
  });

  final monthEntries = ecg.entries
      .where((e) => e.dateTime.year == year && e.dateTime.month == month);
  final measures = monthEntries.length;
  final abnormal =
      monthEntries.where((e) => e.result == '이상 소견 의심').length;

  final avg = <String, double?>{};
  acc.forEach((k, xs) =>
      avg[k] = xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length);

  return _MonthStat(avg: avg, measures: measures, abnormal: abnormal);
}

class _MonthlyReport extends StatelessWidget {
  final DateTime month;
  final _MonthStat current;
  final _MonthStat previous;
  final VoidCallback onInfo;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthlyReport({
    required this.month,
    required this.current,
    required this.previous,
    required this.onInfo,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  static String _score(double v) => '${v.round()}';
  static String _mins(double v) {
    final m = v.round();
    final h = m ~/ 60;
    final mm = m % 60;
    return h > 0 ? '${h}h ${mm}m' : '${mm}m';
  }

  static String _bpm(double v) => '${v.round()} bpm';
  static String _pct(double v) => '${v.round()}%';
  static String _temp(double v) => '${v.toStringAsFixed(1)}°C';
  static String _count(double v) => '${v.round()}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: 연/월 + 이전/다음 달 이동 + 도움말
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${month.year}년 ${month.month}월',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                          height: 32 / 24,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onPrevMonth,
                        child: Icon(Icons.chevron_left,
                            color: Colors.grey[700], size: 24),
                      ),
                      GestureDetector(
                        onTap: onNextMonth,
                        child: Icon(Icons.chevron_right,
                            color: Colors.grey[700], size: 24),
                      ),
                    ],
                  ),
                  const Text(
                    'Monthly Report',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      height: 32 / 24,
                      color: Color(0xFFFB755B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monthly average · vs last month',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.grey),
              tooltip: 'About ECG measurement',
              onPressed: onInfo,
            ),
          ],
        ),
        const SizedBox(height: 16),

        _section(Icons.insights, const Color(0xFF34C759), 'Scores', [
          _bar('Health', 'health', const Color(0xFF34C759), _score, 100, 1),
          _bar('Energy', 'energy', const Color(0xFF5E9BF0), _score, 100, 1),
          _bar('Sleep', 'sleep', const Color(0xFF7B61FF), _score, 100, 1),
        ]),
        _section(Icons.bedtime, const Color(0xFF7B61FF), 'Sleep', [
          _bar('Total sleep', 'totalSleep', const Color(0xFF5E9BF0), _mins, 600, 1),
          _bar('Deep sleep', 'deep', const Color(0xFF3478F6), _mins, 180, 1),
          _bar('REM sleep', 'rem', const Color(0xFF7B61FF), _mins, 180, 1),
          _bar('Sleep HR', 'sleepHR', const Color(0xFFFB755B), _bpm, 100, -1),
        ]),
        _section(Icons.favorite, const Color(0xFFFB755B), 'Vitals', [
          _bar('SpO2', 'spo2', const Color(0xFF4E9AF1), _pct, 100, 1),
          _bar('Heart Rate', 'hr', const Color(0xFFFB755B), _bpm, 120, 0),
          _bar('Temperature', 'temp', const Color(0xFFFF9500), _temp, 40, 0),
        ]),
        _section(Icons.monitor_heart, const Color(0xFF4E9AF1), 'Activity', [
          _CompareBar(
            label: 'ECG measurements',
            color: const Color(0xFF4E9AF1),
            current: current.measures.toDouble(),
            previous: previous.measures.toDouble(),
            fmt: _count,
            scale: null,
            better: 0,
          ),
          _CompareBar(
            label: 'Abnormal findings',
            color: const Color(0xFFFF3B30),
            current: current.abnormal.toDouble(),
            previous: previous.abnormal.toDouble(),
            fmt: _count,
            scale: null,
            better: -1,
          ),
        ]),
      ],
    );
  }

  _CompareBar _bar(String label, String key, Color color,
      String Function(double) fmt, double scale, int better) {
    return _CompareBar(
      label: label,
      color: color,
      current: current[key],
      previous: previous[key],
      fmt: fmt,
      scale: scale,
      better: better,
    );
  }

  Widget _section(
      IconData icon, Color color, String title, List<_CompareBar> bars) {
    // 이번 달·지난 달 모두 데이터가 없는 지표는 숨긴다.
    final visible =
        bars.where((b) => b.current != null || b.previous != null).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      children.add(visible[i]);
      if (i != visible.length - 1) children.add(const SizedBox(height: 16));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _ReportCard(
        icon: icon,
        iconColor: color,
        title: title,
        subtitle: 'This month vs last month',
        children: children,
      ),
    );
  }
}

/// Daily Report의 카드와 동일한 스타일의 섹션 카드.
class _ReportCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ReportCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.children,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// 한 지표의 이번 달 / 지난 달 값을 두 개의 막대로 비교한다.
/// [better] 1: 클수록 좋음, -1: 작을수록 좋음, 0: 중립(회색 delta).
class _CompareBar extends StatelessWidget {
  final String label;
  final Color color;
  final double? current;
  final double? previous;
  final String Function(double) fmt;
  final double? scale; // null이면 두 값의 최대치로 자동 스케일
  final int better;

  const _CompareBar({
    required this.label,
    required this.color,
    required this.current,
    required this.previous,
    required this.fmt,
    required this.scale,
    required this.better,
  });

  @override
  Widget build(BuildContext context) {
    final cur = current;
    final prev = previous;
    final maxScale = scale ??
        () {
          final m = [cur ?? 0, prev ?? 0].reduce((a, b) => a > b ? a : b);
          return m <= 0 ? 1.0 : m * 1.15;
        }();

    Widget delta;
    if (cur == null || prev == null) {
      delta = Text('No data last month',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400));
    } else {
      final d = cur - prev;
      final flat = d.abs() < 0.05;
      final up = d > 0;
      Color c;
      if (flat || better == 0) {
        c = Colors.grey;
      } else {
        final good = (up && better == 1) || (!up && better == -1);
        c = good ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
      }
      // Daily Report의 배지(pill)와 동일한 스타일
      delta = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              flat
                  ? Icons.remove
                  : (up ? Icons.arrow_upward : Icons.arrow_downward),
              size: 13,
              color: c,
            ),
            const SizedBox(width: 2),
            Text(
              fmt(d.abs()),
              style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            delta,
          ],
        ),
        const SizedBox(height: 10),
        _MiniBar(
            tag: 'This month',
            value: cur,
            maxScale: maxScale,
            color: color,
            fmt: fmt),
        const SizedBox(height: 6),
        _MiniBar(
            tag: 'Last month',
            value: prev,
            maxScale: maxScale,
            color: Colors.grey.shade400,
            fmt: fmt),
      ],
    );
  }
}

/// 값 하나를 채워진 막대(오른쪽에 값 라벨)로 그린다.
class _MiniBar extends StatelessWidget {
  final String tag;
  final double? value;
  final double maxScale;
  final Color color;
  final String Function(double) fmt;

  const _MiniBar({
    required this.tag,
    required this.value,
    required this.maxScale,
    required this.color,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    final frac =
        (v == null || maxScale <= 0) ? 0.0 : (v / maxScale).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(tag,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: 8,
                    width: w * frac,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            v != null ? fmt(v) : '--',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ─── ECG 측정 안내(도움말) ────────────────────────────────────────────

class _EcgHelpEntry {
  final String title;
  final String description;
  const _EcgHelpEntry(this.title, this.description);
}

const _ecgHelpEntries = [
  _EcgHelpEntry(
    'What it does',
    'Measuring an ECG on your watch records your heart\'s electrical activity '
        'to screen for irregular rhythms such as atrial fibrillation.',
  ),
  _EcgHelpEntry(
    'Vital signs captured',
    'Each measurement also collects your SpO2, heart rate and skin '
        'temperature at the same time.',
  ),
  _EcgHelpEntry(
    'Feeds your daily report',
    'These readings automatically update your Health Score, Health Risk and '
        'the rest of your daily report.',
  ),
  _EcgHelpEntry(
    'Saved here',
    'Every measurement is stored on this calendar, so you can track your '
        'heart health over time.',
  ),
];

void _showEcgInfo(BuildContext context) {
  const accent = Color(0xFFFB755B);
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
                children: const [
                  Icon(Icons.monitor_heart, color: accent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Measuring ECG',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87),
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
                      for (final e in _ecgHelpEntries) ...[
                        Text(
                          e.title,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accent),
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
              'No score record for this day',
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
                '${DateFormat('MMM d').format(day)} · Score summary',
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
                      'Health',
                      r.wellShort == null ? '--' : '${r.wellShort!.round()}',
                      _scoreColor(r.wellShort),
                      dim: r.wellShort == null,
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Energy',
                      '${energy.round()}',
                      _scoreColor(energy),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Sleep',
                      '$sleep',
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