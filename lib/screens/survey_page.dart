import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'ecg_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // 1. Provider 패키지 임포트
import 'ecg_data_service.dart';// 2. EcgDataService가 정의된 파일 경로 (파일명이 다르면 수정)
import 'main_tab_page.dart';

class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key});

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

/// ==========================
/// Survey State
/// ==========================

class DiseaseHistory {
  String disease_code;
  bool doctor_diagnosed;
  bool has_prescription;
  bool med_intake;
  bool regular_med_intake;
  double duration_years;
  String name; // 기타질환

  DiseaseHistory({
    required this.disease_code,
    this.doctor_diagnosed = false,
    this.has_prescription = false,
    this.med_intake = false,
    this.regular_med_intake = false,
    this.duration_years = 0.0,
    this.name = "",
  });

  Map<String, dynamic> toJson() {
    return {
      "disease_code": disease_code,
      "doctor_diagnosed": doctor_diagnosed,
      "has_prescription": has_prescription,
      "med_intake": med_intake,
      "regular_med_intake": regular_med_intake,
      "duration_years": duration_years,
      if (disease_code == "기타질환") "name": name,
    };
  }
}

class SurveyState {
  int height = 0;
  int weight = 0;

  int smoking = -1;
  int drinking = -1;
  int activity = -1;


  String familyDisease = "";
  String medicines = "";

  List<DiseaseHistory> diseaseHistory = [];
}


class _SurveyPageState extends State<SurveyPage> {
  // 기존 코드의 SurveyState 인스턴스를 유지

  final SurveyState state = SurveyState();

  int currentStep = -2;

  List<int> stack = [];

  final int totalSteps = 4;

  String userName = "user";

  @override
  void initState() {
    super.initState();
    _loadUserName(); // 시작하자마자 이름 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSurveyStatus();
    });
  }
  void _checkSurveyStatus() {
    final ecgService = Provider.of<EcgDataService>(context, listen: false);

    setState(() {
      // 3. 서비스의 getter를 직접 참조 (Future 불필요)
      // 설문 완료 시 -2, 미완료 시 -1
      currentStep = ecgService.isSurveyCompleted ? -1 : -2;
    });

    print("🛠 현재 설문 상태에 따른 Step: $currentStep");
  }

  Future<void> _loadUserName() async {
    final name = await _getUserName();
    setState(() {
      userName = name; // 이름을 가져오면 화면 갱신
    });
  }


  void showMessage(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2), // 2초 동안 표시
        behavior: SnackBarBehavior.floating, // 화면에서 살짝 떠 있는 스타일
      ),
    );
  }

  void _nextStep() {
    setState(() {
      if (currentStep == 0){
        if(state.smoking == -1)
          {
            showMessage(context, "문항을 선택해주세요");
            return null;
          }
        else
          {
            stack.add(currentStep);
            currentStep++;
          }
      } else if (currentStep == 1){
        if(state.drinking == -1)
        {
          showMessage(context, "문항을 선택해주세요");
          return null;
        }
        else
        {
          stack.add(currentStep);
          currentStep++;
        }
      } else if (currentStep == 2){
        if(state.height == 0 || state.weight == 0)
        {
          showMessage(context, "값을 입력해주세요");
          return null;
        }
        else
        {
          stack.add(currentStep);
          currentStep++;
        }
      } else if (currentStep == 3){
        if(state.activity == -1)
        {
          showMessage(context, "문항을 선택해주세요");
          return null;
        }
        else
        {
          stack.add(currentStep);
          currentStep++;
        }
      } else if (currentStep < totalSteps - 1) {
          stack.add(currentStep);
          currentStep++;
        } else {
        _printData();
      }
      print(stack);
    });
  }
  void _prevStep() {
    if (currentStep > 0 ) {
      currentStep = stack.removeLast();
      setState(() => currentStep);
    }
  }


  // 점수를 계산하고 저장하는 함수
  Future<String> _getUserName() async {
    // 1. BMI 계산
    final prefs = await SharedPreferences.getInstance();
    final userName = await prefs.getString('username')?? "user";
    return userName;
  }

  // 설문 결과 화면 진입 시 또는 버튼 클릭 시
  void onSurveyComplete() {
    final ecgService = Provider.of<EcgDataService>(context, listen: false);

    ecgService.completeSurvey();

    ecgService.updateHealthScores(
      smoking: state.smoking,
      drinking: state.drinking,
      activity: state.activity,
      height: state.height.toDouble(),
      weight: state.weight.toDouble(),
    );
  }

  // 2. Firebase ID 토큰을 가져오는 함수 추가 (EcgPage와 동일 로직)
  Future<String> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("로그인이 필요합니다.");
    final token = await user.getIdToken();
    if (token == null) throw Exception("토큰을 가져올 수 없습니다.");
    return token;
  }

  Future<void> _printData() async {
    // 1. 로딩 인디케이터 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // 1. SharedPreferences에 설문 완료 상태 저장
    try {
      // A. 서버에 보낼 JSON 데이터 구성 (명세서의 설문지 JSON 구조)
      final surveyData = {
        "height": state.height,
        "weight": state.weight,
        "smoking": state.smoking,
        "drinking": state.drinking,
        "activity": state.activity,
        "familyDisease": state.familyDisease,
        "medicines": state.medicines,
        "diseaseHistory": state.diseaseHistory.map((d) => d.toJson()).toList(),
      };

      // B. 토큰 획득 및 서버 전송
      final token = await _getIdToken();

      // ★ 여기에 실제 서버 주소를 입력하세요 (예: http://10.0.2.2:3000/user/survey)
      final url = Uri.parse('http://35.216.60.242:9101/user/survey');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(surveyData),
      );

      // 로딩 다이얼로그 닫기
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200 || response.statusCode == 201) {
        // C. 성공 시 처리
        onSurveyComplete(); // 로컬 점수 업데이트

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle_outline, color: Color(0xFFFB755B), size: 60),
                  SizedBox(height: 16),
                  Text(
                    "설문이 성공적으로 업로드되었습니다.",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const MainTabPage()),
                  (route) => false,
            );
          }
        }
      } else {
        // 서버 에러 응답 처리
        throw Exception("서버 응답 오류: ${response.statusCode}");
      }
    } catch (e) {
      // 로딩 다이얼로그가 떠 있다면 닫기
      if (mounted && Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("제출 실패: $e")),
        );
      }
    }
  }

// ... (이하 동일)


  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("제출 완료"),
        content: const Text("설문이 완료되었습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인")),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Theme(
        data: ThemeData(
          useMaterial3: true,
          fontFamily: 'SeoulNam', // 폰트 적용
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFB755B),
            primary: const Color(0xFFFB755B),
          ),
          // 체크박스/라디오 버튼의 기본 색상 설정
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? const Color(0xFFFB755B) : null),
          ),
          radioTheme: RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? const Color(0xFFFB755B) : null),
          ),
          // 입력창 포커스 색상
          inputDecorationTheme: const InputDecorationTheme(
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFB755B), width: 2),
            ),
          ),
        ),
      child: Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      appBar: AppBar(
        title: const Text("건강 설문조사", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: _prevStep)
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (currentStep + 1) / totalSteps,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFFFB755B),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: _buildCurrentQuestion(),
              ),
            ),
            _buildBottomButtons(),
          ],
        ),
      ),
    ),
    );
  }

// --- 질문 단계별 분기 ---
  Widget _buildCurrentQuestion() {
    switch (currentStep) {
      case -2:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                textAlign: TextAlign.justify,
                textWidthBasis: TextWidthBasis.longestLine,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.6,
                    color: Colors.black,
                    fontFamily: 'SeoulNam',
                    fontWeight: FontWeight.w600, // 더 두껍게 설정
                  ),
                  children: [
                    TextSpan(
                      text: 'xalute',
                      style: const TextStyle(
                        fontSize: 24,
                        color: Color(0xFFFB755B),
                        fontWeight: FontWeight.w700, // 강조어는 가장 두껍게
                      ),
                    ),
                    const TextSpan(
                      text: ' 앱을 처음 사용하시나요?\n저희 앱은 만성질환 예방 및 관리를 위해 검진과 상담을 제공하고 있습니다.\n\n'
                          '본 설문지는 건강관리 서비스를 제공해 드리기 위한 기초자료로 향후 상담에 소중한 자료가 될 것입니다. '
                          '다음 문항들에 대하여 해당하는 부분에 대해 설문을 참여해 주세요.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case -1:
        return _questionWrapper(
          title: "1. 과거 치료받은 적이 있거나 현재 치료 중인 질환을 선택해주세요.",
          child: Column(
            children: [
              _buildDiseaseList(), // 기존 질병 체크박스 리스트
              const SizedBox(height: 16), // 리스트와 입력창 사이 간격
              _buildOtherDiseaseInput(),
              const SizedBox(height: 16), // 리스트와 입력창 사이 간격
              _buildFamilyDiseaseInput(),
              const SizedBox(height: 16), // 리스트와 입력창 사이 간격
              _buildMedicineInput(),
            ],
          ),
        );
      case 0:
        return _buildDynamicQuestion<int>(
          question: "2. 다음 중 본인의 흡연량에 해당하는 문항을 골라주세요",
          groupValue: state.smoking,
          options: [
            {"title": "피워본 적 없다", "value": 25},
            {"title": "금연 1년 이상", "value": 15},
            {"title": "금연 1년 미만", "value": 5},
            {"title": "현재 흡연", "value": 0},
          ],
          onChanged: (val) => setState(() => state.smoking = val!),
        );
      case 1:
        return _buildDynamicQuestion<int>(
          question: "3. 다음 중 본인의 음주 빈도에 해당하는 문항을 골라주세요",
          groupValue: state.drinking,
          options: [
            {"title": "전혀 마시지 않음 또는 월 1회 미만", "value": 25},
            {"title": "저위험 음주 (주 1~2회, 1회 1~4잔)", "value": 15},
            {"title": "중위험 음주 (주 1~2회, 1회 5~9잔)", "value": 10},
            {"title": "고위험 음주 (주 3회 이상)", "value": 5},
          ],
          onChanged: (val) => setState(() => state.drinking = val!),
        );
      case 2:
        return _buildHeightWeightQuestion(
          question: "4. 키와 몸무게를 입력해주세요",
          // double 데이터를 String으로 변환 (0일 경우 빈 문자열 표시)
          heightValue: state.height == 0 ? "" : state.height.toInt().toString(),
          weightValue: state.weight == 0 ? "" : state.weight.toInt().toString(),
          // String 입력을 double로 변환하여 저장
          onHeightChanged: (v) => setState(() => state.height = int.tryParse(v) ?? 0),
          onWeightChanged: (v) => setState(() => state.weight = int.tryParse(v) ?? 0),
        );
      case 3:
        return _buildDynamicQuestion<int>(
          question: "5. 다음 중 본인에게 해당되는 활동량을 골라주세요",
          groupValue: state.activity,
          options: [
            {"title": "주 150분 이상 또는 75분의 고강도 유산소 활동 이상", "value": 25},
            {"title": "주 75분-150분의 중강도 또는 30-75분의 고강도 유산소 활동", "value": 15},
            {"title": "규칙적인 활동을 하나 위 조건에 미치지 못하는 경우", "value": 5},
            {"title": "비활동", "value": 0},
          ],
          onChanged: (val) => setState(() => state.activity = val!),
        );
      case 4:
        String smokingScore = state.smoking.toString();
        String drinkingScore = state.drinking.toString();
        double bmi = state.weight/((state.height/100)*(state.height/100));
        int bScore;
        if (bmi < 18.5) {
          bScore = 10; // 저체중
        } else if (bmi < 23.0) {
          bScore = 25; // 정상 (18.5 이상 ~ 23.0 미만)
        } else if (bmi < 25.0) {
          bScore = 15; // 과체중 (23.0 이상 ~ 25.0 미만)
        } else if (bmi < 30.0) {
          bScore = 5;  // 비만 (25.0 이상 ~ 30.0 미만)
        } else {
          bScore = 0;  // 고도비만 (30.0 이상)
        }
        String bmiScore = bScore.toString();
        String activityScore = state.activity.toString();
        int tScore = (state.smoking + state.drinking + state.activity + bScore);
        String totalScore = (state.smoking + state.drinking + state.activity + bScore).toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // 메인 타이틀 (디자인 가이드 반영)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${userName}님의\n건강점수는 ',
                  style: TextStyle(
                    color: Color(0xFF212121), // 기본 검정색 계열
                  ),
                ),
                TextSpan(
                  text: '$totalScore',
                  style: const TextStyle(
                    color: Color(0xFFFB755B), // 요청하신 포인트 색상
                  ),
                ),
                const TextSpan(
                  text: '점입니다',
                  style: TextStyle(
                    color: Color(0xFF212121),
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
          const SizedBox(height: 32),

          // 상세 점수 내역 리스트
          _buildScoreRow("흡연 점수", "+$smokingScore점"),
          const SizedBox(height: 36), // 가이드의 gap 24px
          _buildScoreRow("음주 점수", "+$drinkingScore점"),
          const SizedBox(height: 36), // 가이드의 gap 24px
          _buildScoreRow("BMI 점수", "+$bmiScore점"),
          const SizedBox(height: 36), // 가이드의 gap 24px
          _buildScoreRow("신체활동 점수", "+$activityScore점"),
          const SizedBox(height: 36), // 가이드의 gap 24px

        ],
      );
      default:
        return const Center(child: Text("설문 내용을 모두 확인했습니다."));

    }
  }

  Widget _questionWrapper({
    required String title,
    String? description,
    required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Text를 Row와 Flexible로 감싸 가로 범위를 제한합니다.
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                softWrap: true,
                textWidthBasis: TextWidthBasis.longestLine,
                textAlign: TextAlign.justify, // 요청하신 양옆 정렬
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                  fontFamily: 'SeoulNam', // 폰트 적용
                  height: 1.3, // 줄간격 추가 (가독성)
                ),
              ),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description,
            softWrap: true,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              height: 1.4,
              fontFamily: 'SeoulNam',
            ),
          ),
        ],
        const SizedBox(height: 24),
        // 내부 child 영역
        Expanded(
          child: SingleChildScrollView(
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    bool isLast = currentStep == totalSteps - 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Colors.white),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB755B)),
          onPressed: _nextStep,
          child: Text(isLast ? "제출하기" : "다음", style: const TextStyle(color: Colors.white, fontSize: 20)),
        ),
      ),
    );
  }

  // --- 위젯 빌더 함수들 ---
  Widget _buildDynamicQuestion<T>({
    required String question,
    required T? groupValue,
    required List<Map<String, dynamic>> options, // [{ "title": "예", "value": 1 }, ...]
    required ValueChanged<T?> onChanged,
  }) {
// 개별 패딩을 제거하고 _questionWrapper를 호출하여 통일감을 줍니다.
    return _questionWrapper(
      title: question, // 이제 질문이 큰 제목(22pt)으로 들어갑니다.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...options.map((option) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8), // 항목 간 간격
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  // 선택된 항목이면 주황색 테두리, 아니면 연한 회색
                  color: groupValue == option['value']
                      ? const Color(0xFFFB755B)
                      : Colors.grey[200]!,
                  width: 1.5,
                ),
              ),
              child: RadioListTile<T>(
                title: Text(
                  textAlign: TextAlign.justify,
                  softWrap: true,
                  option['title'],
                  style: TextStyle(
                    fontSize: 15,
                    color: groupValue == option['value'] ? const Color(0xFFFB755B) : Colors.black87,
                    fontWeight: groupValue == option['value'] ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                value: option['value'] as T,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: const Color(0xFFFB755B), // 주황색 적용
                controlAffinity: ListTileControlAffinity.trailing, // 체크 표시를 오른쪽으로
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildDiseaseList() {
    final diseaseOptions = ["고혈압", "당뇨병", "이상지질혈증", "뇌졸중", "관상동맥질환", "만성콩팥병"];

    return Column(
      children: diseaseOptions.map((name) {
        // 해당 질환이 리스트에 있는지 확인
        int diseaseIndex = state.diseaseHistory.indexWhere((d) => d.disease_code == name);
        bool isSelected = diseaseIndex != -1;

        return Column(
          children: [
            CheckboxListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              value: isSelected,
              onChanged: (bool? checked) {
                setState(() {
                  if (checked == true) {
                    // 체크 시 객체 추가
                    state.diseaseHistory.add(DiseaseHistory(disease_code: name, doctor_diagnosed: true));
                  } else {
                    // 체크 해제 시 삭제
                    state.diseaseHistory.removeWhere((d) => d.disease_code == name);
                  }
                });
              },
            ),
            // [핵심] 선택되었을 때만 상세 항목 노출
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 10.0),
                child: Column(
                  children: [
                    // 각 항목을 체크박스로 변경
                    _buildSubDetailCheckbox("의사 진단 여부", state.diseaseHistory[diseaseIndex].doctor_diagnosed, (v) {
                      setState(() => state.diseaseHistory[diseaseIndex].doctor_diagnosed = v!);
                    }),
                    _buildSubDetailCheckbox("약물 처방 여부", state.diseaseHistory[diseaseIndex].has_prescription, (v) {
                      setState(() => state.diseaseHistory[diseaseIndex].has_prescription = v!);
                    }),
                    _buildSubDetailCheckbox("약 복용 여부", state.diseaseHistory[diseaseIndex].med_intake, (v) {
                      setState(() => state.diseaseHistory[diseaseIndex].med_intake = v!);
                    }),
                    _buildSubDetailCheckbox("규칙적 복용(월 20일 이상)", state.diseaseHistory[diseaseIndex].regular_med_intake, (v) {
                      setState(() => state.diseaseHistory[diseaseIndex].regular_med_intake = v!);
                    }),

                    // 유병 기간 레이블 색상 변경
                    Padding(
                      padding: const EdgeInsets.only(left: 12.0, top: 8.0),
                      child: Row(
                        children: [
                          const Text(
                            "질병이 지속된 기간: ",
                            style: TextStyle(color: Colors.black, fontSize: 15),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 60, // 입력창 너비
                            child: TextFormField(
                              keyboardType: TextInputType.number, // 숫자 키패드 노출
                              initialValue: state.diseaseHistory[diseaseIndex].duration_years.toInt().toString(),
                              style: const TextStyle(color: Colors.black), // 입력 글자 검은색
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8F9FA)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFF8F9FA), width: 2),
                                ),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  state.diseaseHistory[diseaseIndex].duration_years = double.tryParse(v) ?? 0;
                                });
                              },
                            ),
                          ),
                          const Text(
                            " 년",
                            style: TextStyle(color: Colors.black, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSubDetailCheckbox(String title, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.black, fontSize: 15), // 검은색 텍스트
      ),
      value: value,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading, // 체크박스를 왼쪽으로 배치
      contentPadding: EdgeInsets.zero, // 여백 조절
      dense: true, // 크기를 조금 더 콤팩트하게
      activeColor: Color(0xFFFB755B), // 체크되었을 때의 색상
    );
  }

  Widget _buildOtherDiseaseInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(
          labelText: "기타 질환을 입력하세요.(갑상선, 간질환 등)",
          labelStyle: TextStyle(fontSize: 15),
          border: OutlineInputBorder(),
        ),
        onChanged: (val) {
          int idx = state.diseaseHistory.indexWhere((d) => d.disease_code == "기타질환");
          if (idx != -1) state.diseaseHistory[idx].name = val;
        },
      ),
    );
  }

  Widget _buildFamilyDiseaseInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(
          labelText: "가족력이 있는 질환을 입력하세요",
          labelStyle: TextStyle(fontSize: 15),
          border: OutlineInputBorder(),
        ),
        onChanged: (val)
          => setState(() => state.familyDisease = val!))
    );
  }

  Widget _buildMedicineInput() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              labelText: "평소에 드시는 약이 있으면 입력하세요",
              labelStyle: TextStyle(fontSize: 15),
              border: OutlineInputBorder(),
            ),
            onChanged: (val)
            => setState(() => state.medicines = val!))
    );
  }
  Widget _buildScoreRow(String label, String point) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Color(0xFF000000),
          ),
        ),
        Text(
          point,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Color(0xFF1C0D0D),
          ),
        ),
      ],
    );
  }
  Widget _buildHeightWeightQuestion({
    required String question,
    required String heightValue,
    required String weightValue,
    required ValueChanged<String> onHeightChanged,
    required ValueChanged<String> onWeightChanged,
  }) {
    return _questionWrapper(
      title: question,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, // 가운데 정렬
        children: [
          const Text("키 : ", style: TextStyle(fontSize: 15)),
          _buildUnderlineInput(width: 60, value: heightValue, onChanged: onHeightChanged),
          const Text("      몸무게 : ", style: TextStyle(fontSize: 15)),
          _buildUnderlineInput(width: 60, value: weightValue, onChanged: onWeightChanged),
        ],
      ),
    );
  }

  Widget _buildUnderlineInput({
    required double width,
    required String value,
    required ValueChanged<String> onChanged
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        // controller를 통해 현재 String 값을 유지하고 커서 위치를 마지막으로 보냅니다.
        controller: TextEditingController.fromValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          ),
        ),
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFB755B)
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFB755B))
          ),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFB755B), width: 2)
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
