/** Not USE **/
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {


  String username = "user";
  // dumy data
  int healthScore = 72;
  int healthDiff = 3;
  int monthlyCount = 6;
  int streakDays = 5;
  int todayCount = 2;
  int arrhythmiaCount = 3;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      healthScore = prefs.getInt('totalScore') ?? 75;
      username = prefs.getString('username') ?? "user";
    });
  }

  @override
  Widget build(BuildContext context) {
    TextStyle header = const TextStyle(fontSize: 20, fontWeight: FontWeight.w500);
    TextStyle number = const TextStyle(fontSize: 36, fontWeight: FontWeight.bold);
    TextStyle comment = const TextStyle(fontSize: 16);
    TextStyle highlight = const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Welcome. $username!", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("This is Xalute!", style: TextStyle(fontSize: 18)),
              const SizedBox(height: 32),
              Text("오늘의 건강 점수는", style: header),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("$healthScore", style: number),
                  const Text("점 입니다.", style: TextStyle(fontSize: 20)),
                ],
              ),
              Text("${healthDiff >= 0 ? "+" : "-"}$healthDiff 어제에 비해.", style: comment),
              const SizedBox(height: 32),
              Text("이번 달의 측정 횟수는", style: header),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("$monthlyCount", style: number),
                  const Text("회 입니다.", style: TextStyle(fontSize: 20)),
                ],
              ),
              Text("${streakDays}일 연속 측정 중.", style: comment),
              Text("오늘 측정 횟수 ${todayCount}회.", style: comment),
              const SizedBox(height: 32),
              Text("이번 달의 부정맥 의심 횟수는", style: header),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("$arrhythmiaCount", style: highlight),
                  const Text("회 입니다.", style: TextStyle(fontSize: 20)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
