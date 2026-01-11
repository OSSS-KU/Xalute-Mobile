/** Main **/
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'ecg_data_service.dart';
import '../main.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EcgPage extends StatefulWidget {
  const EcgPage({super.key});

  @override
  State<EcgPage> createState() => _EcgPageState();
}

class _EcgPageState extends State<EcgPage> {
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;
  bool isLoading = false;

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

  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("Not logged in");
    }

    final token = await user.getIdToken();
    if (token == null) {
      throw Exception("Failed to get ID token");
    }

    return token;
  }

  Future<SharedPreferences> getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  void _handleMeasureButton() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.example.xalute/watch');
      try {
        final bool isConnected = await platform.invokeMethod(
            'isWatchConnected');
        if (!isConnected) {
          showDialog(
            context: context,
            builder: (context) =>
                AlertDialog(
                  content: const Text("워치와의 연결을 확인해주세요."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text("확인"))
                  ],
                ),
          );
          return;
        }

        final ecgService = Provider.of<EcgDataService>(context, listen: false);
        final name = ecgService.userName ?? "User";
        final birthDate = ecgService.birthDate ?? "";
        final phoneNumber = ecgService.phoneNumber ?? "";
        final address = ecgService.address ?? "";
        final token = await _getIdToken();

        showDialog(
          context: context,
          builder: (context) =>
              AlertDialog(
                content: const Text("워치에서 ECG 측정을 진행하시겠습니까?"),
                actions: [
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        await platform.invokeMethod('launchWatchApp', {
                          'name': name,
                          'birthDate': birthDate,
                          'token': token,
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("워치 앱 실행됨")));
                      } catch (e) {
          // 콘솔에 상세 에러 로그 출력
          debugPrint("에러 발생 상세 내용: $e");
          if (context.mounted) { // context가 유효한지 확인하는 것이 권장됩니다.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("워치 앱 실행 실패: ${e.toString()}")),
            );
          }
        }
                    },
                    child: const Text("확인"),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text("취소")),
                ],
              ),
        );
      } on PlatformException catch (e) {
        debugPrint("플랫폼 오류: ${e.message}");
      }
    } else {
      setState(() => isLoading = true);
      try {
        await Provider.of<EcgDataService>(context, listen: false)
            .fetchEcgData();
      } catch (e, stack) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('데이터 조회 실패: $e')));
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ecgService = Provider.of<EcgDataService>(context);
    final selected = selectedDay ?? DateTime.now();
    final normalizedSelected = DateTime.utc(
        selected.year, selected.month, selected.day);
    final selectedResults = ecgService.entriesForDay(normalizedSelected);
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
                                    "건강점수는 ${ecgService.totalScore}점",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 24,
                                      height: 32 / 24, // line-height 계산
                                      letterSpacing: 0.0,
                                      color: Color(0xFFFB755B),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.chevron_right),
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
                        Align(
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: _openSettings,
                            child: Consumer<EcgDataService>(
                              builder: (context, ecgService, child) {
                                return CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage: ecgService
                                      .profileImagePath != null
                                      ? FileImage(
                                      File(ecgService.profileImagePath!))
                                      : const AssetImage(
                                      'assets/icon/profile.png') as ImageProvider,
                                );
                              },
                            ),
                          ),
                        ),
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
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: selectedResults.map((entry) {
                        final formatted = DateFormat('M월 d일 HH시 mm분').format(
                            entry.dateTime);
                        final isAbnormal = entry.result == '이상 소견 의심';

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
                                      entry.result,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isAbnormal ? const Color(
                                            0xFFFB755B) : Colors.grey[700],
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFB755B),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _handleMeasureButton,
                        child: Text(
                          Platform.isIOS ? "데이터 조회" : "측정 시작",
                          style: const TextStyle(fontSize: 16,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Lottie.asset(
                      'assets/lottie/Animation.json',
                      width: 100,
                      height: 100,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ECG 데이터를 조회하고 있어요\n앱을 끄지 말고 잠시만 기다려주세요',
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