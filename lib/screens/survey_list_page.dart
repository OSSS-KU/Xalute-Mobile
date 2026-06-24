import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'survey_page.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SurveyListPage extends StatefulWidget {
  const SurveyListPage({super.key});

  @override
  State<SurveyListPage> createState() => _SurveyListPageState();
}

class _SurveyListPageState extends State<SurveyListPage> {
  bool _isLoading = true;
  List<dynamic> _surveys = [];

  @override
  void initState() {
    super.initState();
    _fetchSurveyList();
  }

  // Firebase 토큰 가져오기 (ecg_page.dart 로직 참고)
  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Login required.");
    final token = await user.getIdToken();
    if (token == null) throw Exception("Failed to get token.");
    return token;
  }Future<void> _fetchSurveyList() async {
    print("로그: 설문 리스트 불러오기 시작"); // 확인용 로그
    setState(() => _isLoading = true);

    try {
      final token = await _getIdToken();
      print("로그: 토큰 획득 성공");

      // ★ 여기 주소를 실제 서버 주소로 반드시 바꿔주세요!
      final url = Uri.parse('http://35.216.60.242:9101/user/survey/list');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10)); // 10초 지나면 강제 종료

      print("로그: 응답 코드 = ${response.statusCode}");

      if (response.statusCode == 200) {
        print("서버 응답 데이터: ${response.body}");
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            _surveys = responseData['data'];
            _surveys.sort((a, b) => b['createdAt'].compareTo(a['createdAt']));
          });
        }
      } else {
        print("로그: 서버 에러 발생 - ${response.body}");
      }
    } catch (e) {
      print("로그: 에러 발생 상세내용 -> $e"); // 콘솔에 에러 내용 출력
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred: $e")),
        );
      }
    } finally {
      print("로그: 로딩 종료");
      if (mounted) setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      appBar: AppBar(
        title: const Text(
          "Survey History",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFB755B)))
          : Stack( // 버튼을 하단에 고정하기 위해 Stack 사용
        children: [
          _surveys.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
            onRefresh: _fetchSurveyList,
            color: const Color(0xFFFB755B),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // 버튼 공간 확보를 위해 하단 패딩 추가
              itemCount: _surveys.length,
              itemBuilder: (context, index) {
                return _buildSurveyItem(_surveys[index]);
              },
            ),
          ),

          // 하단 고정 버튼 부분
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFAFBFF).withOpacity(0),
                    const Color(0xFFFAFBFF),
                  ],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFB755B), // survey_page와 동일한 포인트 컬러
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  onPressed: () {
                    // SurveyPage로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SurveyPage()),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        "Start a new survey",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 데이터가 없을 때 표시할 화면
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_late_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "No survey records yet.",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // 리스트 아이템 위젯
  Widget _buildSurveyItem(Map<String, dynamic> survey) {
    // 날짜 포맷팅 (2026-03-02T13:30:42.963Z -> 2026년 3월 2일 22:30)
    DateTime createdAt = DateTime.parse(survey['createdAt']).toLocal();
    String formattedDate = DateFormat('yyyy.MM.dd HH:mm', 'en_US').format(createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFEEEA),
          child: Icon(Icons.description, color: Color(0xFFFB755B)),
        ),
        title: const Text(
          "Health survey completed",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            formattedDate,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          // 결과 URL을 확인하거나 상세 페이지로 이동하는 로직을 넣을 수 있습니다.
          _showSurveyDetail(survey['url']);
        },
      ),
    );
  }void _showSurveyDetail(String url) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FutureBuilder(
        future: http.get(Uri.parse(url)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFB755B)));
          }

          if (snapshot.hasData && snapshot.data!.statusCode == 200) {
            try {
              print("상세 데이터 원본: ${snapshot.data!.body}");

              final Map<String, dynamic> data = json.decode(utf8.decode(snapshot.data!.bodyBytes));

              final int smokingScore  = (data['smoking']  as num?)?.toInt() ?? 0;
              final int drinkingScore = (data['drinking'] as num?)?.toInt() ?? 0;
              final int activityScore = (data['activity'] as num?)?.toInt() ?? 0;

              final double height = (data['height'] as num?)?.toDouble() ?? 0;
              final double weight = (data['weight'] as num?)?.toDouble() ?? 0;

              int bScore = 0;
              if (height > 0 && weight > 0) {
                final double bmi = weight / ((height / 100) * (height / 100));
                if (bmi < 18.5)      bScore = 10;
                else if (bmi < 23.0) bScore = 25;
                else if (bmi < 25.0) bScore = 15;
                else if (bmi < 30.0) bScore = 5;
                else                 bScore = 0;
              }

              final int score = smokingScore + drinkingScore + activityScore + bScore;

              String status = "Excellent";
              Color statusColor = Colors.green;
              if (score < 40) {
                status = "At risk";
                statusColor = Colors.red;
              } else if (score < 60) {
                status = "Caution";
                statusColor = Colors.orange;
              } else if (score < 80) {
                status = "Good";
                statusColor = Colors.blue;
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text("Survey Result Analysis", style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Your health score, calculated from"),
                    const Text("the data recorded at that time."),
                    const SizedBox(height: 20),
                    // 점수 디자인... (이전 코드와 동일)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Column(
                        children: [
                          Text("$score", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: statusColor)),
                          Text("pts", style: TextStyle(fontSize: 18, color: statusColor)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text("Status: $status", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: statusColor)),
                    const Divider(height: 30),
                    _buildDetailRow("Height/Weight", "${data['height'] ?? '-'}cm / ${data['weight'] ?? '-'}kg"),
                    _buildDetailRow("Smoking score", "+$smokingScore pts"),
                    _buildDetailRow("Drinking score", "+$drinkingScore pts"),
                    _buildDetailRow("Physical activity score", "+$activityScore pts"),
                    _buildDetailRow("BMI score", "+${bScore} pts"),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
                ],
              );
            } catch (e) {
              // 에러 발생 시 콘솔에 어떤 에러인지 출력합니다.
              print("데이터 파싱 에러 발생: $e");
              return AlertDialog(
                content: Text("An error occurred while parsing data.\nError: $e"),
              );
            }
          }
          return const AlertDialog(content: Text("Unable to load data."));
        },
      ),
    );
  }
  // 정보 표시를 위한 보조 위젯
  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}