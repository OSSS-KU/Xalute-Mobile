import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'ecg_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String gender = "M";

  bool hasHealthCheck = false;
  String healthCheckDate = "";

  List<DiseaseHistory> diseaseHistory = [];

  //q1_1_regular_clinic
  bool receive_regular_care = false;
  String clinics = "";
  String q1_1_other = "";

  //q1_2_medication_adherence
  bool follow_prescription = true;
  int main_reason = 0;
  String q1_2_other = "";

  String familyDisease = "";
  String medicines = "";

  //q2_bp_knowledge
  int know_recent_bp = 1;
  String q2_bp_measurement_frequency = "";
  double q2_count = 0;

  //q3_bg_knowledge
  int know_recent_bg = 1;
  String q3_bp_measurement_frequency = "";
  double q3_count = 0.0;

  //q4_chronic_education_experience
  bool has_education = true;

  //q5_smoking
  int q5_answer = 1;
  bool no_smoke = false;
  bool ever_smoked_over_5packs = false;
  String current_status = "daily";
  List<String> current_types = [];
  String q5_other = "";
  String pattern = "";
  int avg_cigs_per_day = 0;
  int avg_cigs_per_month = 0;
  int smoking_years = 0;

  //q6_quit_intention
  String q6_quit_intention = "none";

  //q7_alcohol
  bool drank = true;
  String frequency = "2_4_per_month";
  int amount_per_occasion_glasses = 0;
  double avg = 0.0;

  //q8_sitting_time
  double hours_per_day = 0.0;
  double minutes_per_day = 0.0;

  //q9_physical_activity
  List<double> work_high = [0.0, 0.0, 0.0];
  List<double> work_mid = [0.0, 0.0, 0.0];
  List<double> transport_walk_cycle = [0.0, 0.0, 0.0];
  List<double> leisure_high = [0.0, 0.0, 0.0];
  List<double> leisure_mid = [0.0, 0.0, 0.0];

  //q9_1_physical_activity
  String stage_of_change = "no_intention";
  String no_activity_main_reason = "disease";
  String q9_1_other = "";

  //q10_weight_change_last_6m
  String status = "loss";
  double kg = 0.0;

  //q11_self_body_image
  String q11_self_body_image = "very_thin";

  //q12_weight_control_effort
  String q12_weight_control_effort = "lose";

  //q13_breakfast_frequency_per_week
  int q13_breakfast_frequency_per_week = 5;

  //q14_diet_score
  bool grain_diversity = false;
  bool vegetable_variety = false;
  bool daily_fruit = false;
  bool daily_dairy = false;
  bool regular_3_meals = false;
  bool balanced_korean_meal = false;
  bool low_salt = false;
  bool no_extra_salt = false;
  bool remove_meat_fat = false;
  bool low_fried_food = false;
  int q14_total_score = 0;

  //q15_why_poor_diet
  String q15_why_poor_diet = "economic";
  String q15_other = "";

  //q16_sleep_hours
  int weekday = 0;
  int weekend = 0;

  //q17_depression_score
  int depressed_mood = 0;
  int loss_of_interest = 0;
  int sleep_problem = 0;
  int appetite_change = 0;
  int psychomotor_change = 0;
  int fatigue = 0;
  int worthlessness = 0;
  int concentration = 0;
  int suicidal_ideation = 0;
  int q17_total_score = 0;

  //demographics
  String marry = "married_with_spouse";
  int household_size = 1;
  String insurance_type = "nhis";
  String education_level = "primary_or_less";
  int monthly_household_income = 200;

  int _calculateHealthScore(){
    int base = 0;

    if(no_smoke){
      base += 25;
    } else if(current_status == "past_only"){
      if(!ever_smoked_over_5packs) {
        base += 15;
      } else {
        base += 10;
      }
    }

    return base;

  }



  Map<String, dynamic> _activityToJson(List<double> v) {
    return {
      "days": v[0],
      "hours_per_day": v[1],
      "minutes_per_day": v[2],
    };
  }

  Map<String, dynamic> toJson() {
    return {
      "gender": gender,

      // health_check_last_6m
      "health_check_last_6m": {
        "has_experience": hasHealthCheck,
        "date": hasHealthCheck ? healthCheckDate : "",
      },

      // q1_disease_history
      "q1_disease_history": diseaseHistory.map((d) =>
      {
        "disease_code": d.disease_code,
        "doctor_diagnosed": d.doctor_diagnosed,
        "has_prescription": d.has_prescription,
        "med_intake": d.med_intake,
        "regular_med_intake": d.regular_med_intake,
        "duration_years": d.duration_years,
        if (d.disease_code == "기타질환") "name": d.name,
      }).toList(),

      // q1_1_regular_clinic
      "q1_1_regular_clinic": {
        "receive_regular_care": receive_regular_care,
        "clinics": receive_regular_care ? clinics : "",
        "other": (receive_regular_care && clinics == "기타")
            ? q1_1_other
            : "",
      },

      // q1_2_medication_adherence
      "q1_2_medication_adherence": {
        "follow_prescription": follow_prescription,
        "main_reason": follow_prescription ? "" : main_reason,
        "other": (follow_prescription || main_reason != "기타")
            ? ""
            : q1_2_other,
      },

      // q2_bp_knowledge
      "q2_bp_knowledge": {
        "know_recent_bp": know_recent_bp,
        "bp_measurement_frequency":
        know_recent_bp == 3 ? "" : q2_bp_measurement_frequency,
        "count": q2_count,
      },

      // q3_bg_knowledge
      "q3_bg_knowledge": {
        "know_recent_bg": know_recent_bg,
        "bp_measurement_frequency":
        know_recent_bg == 3 ? "" : q3_bp_measurement_frequency,
        "count": q3_count,
      },

      // q4_chronic_education_experience
      "q4_chronic_education_experience": {
        "has_education": has_education,
      },

      // q5_smoking
      "q5_smoking": {
        "no_smoke": no_smoke,
        "ever_smoked_over_5packs": ever_smoked_over_5packs,
        "current_status": no_smoke ? "" : current_status,
        "current_types": no_smoke ? [] : current_types,
        "other": no_smoke ? "" : q5_other,
        "past_detail": no_smoke
            ? {}
            : {
          "pattern": pattern,
          "avg_cigs_per_day": avg_cigs_per_day,
          "avg_cigs_per_month": avg_cigs_per_month,
          "smoking_years": smoking_years,
        },
      },

      // q6_quit_intention
      "q6_quit_intention": q6_quit_intention,

      // q7_alcohol
      "q7_alcohol": {
        "drank": drank,
        "frequency": drank ? frequency : "",
        "amount_per_occasion_glasses":
        drank ? amount_per_occasion_glasses : 0,
        "avg": (drank && amount_per_occasion_glasses == 10)
            ? avg
            : 0.0,
      },

      // q8_sitting_time
      "q8_sitting_time": {
        "hours_per_day": hours_per_day,
        "minutes_per_day": minutes_per_day,
      },

      // q9_physical_activity
      "q9_physical_activity": {
        "work_high": _activityToJson(work_high),
        "work_mid": _activityToJson(work_mid),
        "transport_walk_cycle": _activityToJson(transport_walk_cycle),
        "leisure_high": _activityToJson(leisure_high),
        "leisure_mid": _activityToJson(leisure_mid),
      },

      // q9_1_physical_activity
      "q9_1_physical_activity": {
        "stage_of_change": stage_of_change,
        "no_activity_main_reason": stage_of_change == "no_intention"
            ? no_activity_main_reason
            : "",
        "other": no_activity_main_reason == "other"
            ? q9_1_other
            : "",
      },

      // q10_weight_change_last_6m
      "q10_weight_change_last_6m": {
        "status": status,
        "kg": status.isEmpty ? 0 : kg,
      },

      // q11_self_body_image
      "q11_self_body_image": q11_self_body_image,

      // q12_weight_control_effort
      "q12_weight_control_effort": q12_weight_control_effort,

      // q13_breakfast_frequency_per_week
      "q13_breakfast_frequency_per_week":
      q13_breakfast_frequency_per_week,

      // q14_diet_score
      "q14_diet_score": {
        "grain_diversity": grain_diversity,
        "vegetable_variety": vegetable_variety,
        "daily_fruit": daily_fruit,
        "daily_dairy": daily_dairy,
        "regular_3_meals": regular_3_meals,
        "balanced_korean_meal": balanced_korean_meal,
        "low_salt": low_salt,
        "no_extra_salt": no_extra_salt,
        "remove_meat_fat": remove_meat_fat,
        "low_fried_food": low_fried_food,
        "total_score": q14_total_score,
      },

      // q15_why_poor_diet
      "q15_why_poor_diet": q15_why_poor_diet,
      "q15_other": q15_why_poor_diet == "other" ? q15_other : "",

      // q16_sleep_hours
      "q16_sleep_hours": {
        "weekday": weekday.toDouble(),
        "weekend": weekend.toDouble(),
      },

      // q17_depression_score
      "q17_depression_score": {
        "items": {
          "depressed_mood": depressed_mood,
          "loss_of_interest": loss_of_interest,
          "sleep_problem": sleep_problem,
          "appetite_change": appetite_change,
          "psychomotor_change": psychomotor_change,
          "fatigue": fatigue,
          "worthlessness": worthlessness,
          "concentration": concentration,
          "suicidal_ideation": suicidal_ideation,
        },
        "total_score": q17_total_score,
      },

      // demographics
      "demographics": {
        "marry": marry,
        "household_size": household_size,
        "insurance_type": insurance_type,
        "education_level": education_level,
        "monthly_household_income": monthly_household_income,
      },
    };
  }
}


class _SurveyPageState extends State<SurveyPage> {
  // 기존 코드의 SurveyState 인스턴스를 유지
  final SurveyState state = SurveyState();

  int currentStep = -1;

  List<int> stack = [];

  final int totalSteps = 31;
  // 서버 전송 로직
  void _nextStep() {
    setState(() {
      if (currentStep == 3 && state.know_recent_bp == 3) {
        stack.add(currentStep);
        currentStep = 5;
      }
      else if (currentStep == 5 && state.know_recent_bg == 3) {
        stack.add(currentStep);
        currentStep = 7;
      }
      // 예: 비흡연자라면 금연 계획 질문을 건너뜀
      else if (currentStep == 8 && state.no_smoke) {
        stack.add(currentStep);
        currentStep = 13;
      }
      else if (currentStep == 16 && state.stage_of_change != "no_intention") {
        stack.add(currentStep);
        currentStep = 18;
      }
      else {
        if (currentStep < totalSteps - 1) {
          stack.add(currentStep);
          currentStep++;
        } else {
          //_submitData();
          _printData();
        }
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

// --- 서버 제출 로직 ---
  Future<void> _submitData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.post(
        Uri.parse('https://api.your-server.com/v1/surveys'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(state.toJson()),
      );

      if (!mounted) return;
      Navigator.pop(context); // 로딩 닫기

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSuccessDialog();
      } else {
        throw Exception("Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("실패: $e")));
    }
  }

  Future<void> _printData() async {
    // 1. 로딩 인디케이터 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // 1. SharedPreferences에 설문 완료 상태 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSurveyCompleted', true);

    try {
      // 2. state 데이터 콘솔 출력
      debugPrint("--- Survey Data JSON ---");
      debugPrint(jsonEncode(state.toJson()));
      debugPrint("------------------------");

      // 3. (옵션) 서버 전송 로직이 필요하다면 여기에 추가 가능
      // await ApiClient().submitSurvey(state.toJson());

// 2. "설문이 완료되었습니다" 알림창 띄우기
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
                "설문이 완료되었습니다.",
                style: TextStyle(fontFamily: 'SeoulNam', fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      print(state.toJson());

      // 3. 2초 대기
      await Future.delayed(const Duration(seconds: 2));
      // 5. EcgPage로 이동
      // 스택을 모두 비우고 메인 페이지(EcgPage)로 가려면 pushAndRemoveUntil을 사용합니다.

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const EcgPage()),
              (route) => false, // 이전의 모든 경로(설문 페이지 등)를 제거
        );
      }
    } catch (e) {
      // 에러 발생 시 다이얼로그 닫고 알림
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("데이터 처리 중 오류가 발생했습니다: $e")),
        );
      }
    }
  }

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
      case -1:
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
      case 0:
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
      case 1:
        return _buildNestedQuestion<bool>(
          question: "1-1. 표시한 질환에 대해 정기적으로 진료받고 있는 의료기관은 어디입니까? (중복 선택 가능)",
          groupValue: state.receive_regular_care,
          onChanged: (val) => setState(() => state.receive_regular_care = val!),
          options: [
            {
              "title": "정기 진료를 받지 않는다",
              "value": false,
              "nestedChild": null,
            },
            {
              "title": "정기적으로 진료를 받는다",
              "value": true,
              // Wrap 대신 Column을 사용하여 세로 배열
              "nestedChild": Column(
                children: ["보건소", "동네 병·의원", "종합병원", "기타"].map((place) {
                  bool isPlaceSelected = state.clinics.contains(place);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (!isPlaceSelected) {
                          state.clinics += "$place,";
                        } else {
                          state.clinics = state.clinics.replaceAll("$place,", "");
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          // 체크박스 스타일 (주황색 테마 적용)
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isPlaceSelected,
                              activeColor: const Color(0xFFFB755B),
                              onChanged: (v) {
                                setState(() {
                                  if (v!) {
                                    state.clinics += "$place,";
                                  } else {
                                    state.clinics = state.clinics.replaceAll("$place,", "");
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            place,
                            style: TextStyle(
                              fontSize: 15,
                              fontFamily: 'SeoulNam',
                              color: isPlaceSelected ? const Color(0xFFFB755B) : Colors.black87,
                              fontWeight: isPlaceSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          // 기타 선택 시 입력창 노출
                          if (place == "기타" && isPlaceSelected) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                style: const TextStyle(fontSize: 15, fontFamily: 'SeoulNam'),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                                  hintText: "의료기관명 입력",
                                  hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFFFB755B)),
                                  ),
                                ),
                                onChanged: (v) => setState(() => state.q1_1_other = v),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            },
          ],
        );
      case 2:
        return _buildNestedQuestion<bool>(
          question: "1-2. 의사 처방에 따라 규칙적으로 약을 복용하고 있습니까? 의사 처방대로 약을 복용하지 않는다면 가장 큰 이유는 무엇입니까?",
          groupValue: state.follow_prescription,
          onChanged: (val) => setState(() => state.follow_prescription = val!),
          options: [
            {
              "title": "의사 처방대로 약을 규칙적으로 먹는다",
              "value": true,
              "nestedChild": null,
            },
            {
              "title": "의사 처방대로 약을 먹지 않는다",
              "value": false,
              "nestedChild": Column(
                children: [
                  "증상이 없어서(불편하지 않아서)",
                  "효과가 별로 없어서",
                  "부작용이 나타나서",
                  "약 먹는 것을 잊어버려서",
                  "약을 먹으면 몸에 나쁠까 봐",
                  "한번 약을 먹기 시작하면 평생 먹을까 봐",
                  "스스로 생활습관(운동, 영양 등)을 바꿔서 질병을 고쳐보고 싶어서",
                  "기타"
                ].asMap().entries.map((entry) {
                  int idx = entry.key + 1;
                  String label = entry.value;
                  bool isItemSelected = state.main_reason == idx;

                  return InkWell(
                    onTap: () => setState(() => state.main_reason = idx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0), // 터치 영역을 위해 패딩 약간 증가
                      child: Row(
                        children: [
                          Icon(
                            isItemSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 20,
                            color: isItemSelected ? const Color(0xFFFB755B) : Colors.grey[400],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label, // 1. 여기서 "$idx. " 부분을 제거했습니다.
                              style: TextStyle(
                                fontSize: 15, // 가독성을 위해 크기 살짝 조정
                                fontFamily: 'SeoulNam',
                                fontWeight: isItemSelected ? FontWeight.bold : FontWeight.normal,
                                color: isItemSelected ? const Color(0xFFFB755B) : Colors.black87,
                              ),
                            ),
                          ),
                          if (label == "기타" && isItemSelected) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120, // 입력창 너비 소폭 확장
                              child: TextField(
                                style: const TextStyle(fontSize: 15, fontFamily: 'SeoulNam'),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                                  hintText: "사유 입력",
                                  hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
                                  // 주황색 포인트에 맞춘 언더라인
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFFFB755B)),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFFFB755B), width: 2),
                                  ),
                                ),
                                onChanged: (v) => setState(() => state.q1_2_other = v),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            },
          ],
        );
      case 3:
        return _buildDynamicQuestion<int>(
          question: "2. 최근(6개월 이내) 본인의 혈압 수치를 알고 계십니까?",
          groupValue: state.know_recent_bp,
          options: [
            {"title": "알고 있다", "value": 1},
            {"title": "모른다", "value": 2},
            {"title": "측정한 적이 없다", "value": 3},
          ],
          onChanged: (val) => setState(() => state.know_recent_bp = val!),
        );
      case 4: // 혈압 측정 빈도 질문
        return _buildDynamicInputQuestion<int>(
          question: "2-1. 최근 혈압을 얼마나 자주 측정하셨습니까?",
          groupValue: state.know_recent_bp, // 상태 저장용 변수 필요
          currentInputText: state.q2_count == 0 ? "" : state.q2_count.toInt().toString(),
          options: [
            {"title": "매일 혹은 매주", "value": 1, "unit": "회", "showInput": true},
            {"title": "매월", "value": 2, "unit": "회", "showInput": true},
            {"title": "가끔(6개월간)", "value": 3, "unit": "회", "showInput": true},
          ],
          onRadioChanged: (val) => setState(() => state.know_recent_bp = val!),
          onTextChanged: (val) => setState(() => state.q2_count = double.tryParse(val) ?? 0),
        );
      case 5:
        return _buildDynamicQuestion<int>(
          question: "3. 최근(6개월 이내) 본인의 혈당 수치를 알고 계십니까?",
          groupValue: state.know_recent_bg,
          options: [
            {"title": "알고 있다", "value": 1},
            {"title": "모른다", "value": 2},
            {"title": "측정한 적이 없다", "value": 3},
          ],
          onChanged: (val) => setState(() => state.know_recent_bg = val!),
        );
      case 6:
        return _buildDynamicInputQuestion<int>(
          question: "3-1. 최근 혈당을 얼마나 자주 측정하셨습니까?",
          groupValue: state.know_recent_bg, // 상태 저장용 변수 필요
          currentInputText: state.q3_count == 0 ? "" : state.q3_count.toInt().toString(),
          options: [
            {"title": "매일 혹은 매주", "value": 1, "unit": "회", "showInput": true},
            {"title": "매월", "value": 2, "unit": "회", "showInput": true},
            {"title": "가끔(6개월간)", "value": 3, "unit": "회", "showInput": true},
          ],
          onRadioChanged: (val) => setState(() => state.know_recent_bg = val!),
          onTextChanged: (val) => setState(() => state.q3_count = double.tryParse(val) ?? 0),
        );
      case 7:
        return _buildDynamicQuestion<bool>(
          question: "4. 고혈압, 당뇨병, 고지혈증(이상지질혈증) 등 만성질환 관련 교육을 받은 적이 있습니까?",
          groupValue: state.has_education,
          options: [
            {"title": "예", "value": true},
            {"title": "아니요", "value": false},
          ],
          onChanged: (val) => setState(() => state.has_education = val!),
        );
      case 8:
      return _buildDynamicQuestion<int>(
        question: "5. 지금까지 살아오는 동안 피운 담배의 양은 총 얼마나 됩니까?",
        groupValue: state.q5_answer,
        options: [
          {"title": "5갑(100개비) 미만", "value": 1},
          {"title": "5갑(100개비) 이상", "value": 2},
          {"title": "피워본 적이 없다", "value": 3},
        ],
        onChanged: (val) {
          if (val == null) return;
          state.q5_answer = val;
          setState(() {
            if (val == 1) {
              state.no_smoke = false;
              state.ever_smoked_over_5packs = false;
            } else if (val == 2) {
              state.no_smoke = false;
              state.ever_smoked_over_5packs = true;
            } else {
              state.no_smoke = true;
              state.ever_smoked_over_5packs = false;
            }
          });
        },
      );
      case 9:
        return _buildDynamicQuestion<String>(
          question: "5-1. 현재 담배를 피우십니까?",
          groupValue: state.current_status,
          options: [
            {"title": "매일 피운다", "value": "daily"},
            {"title": "가끔 피운다", "value": "sometimes"},
            {"title": "과거에 피웠으나 현재 피우지 않는다", "value": "past_only"},
          ],
          onChanged: (val) => setState(() => state.current_status = val!),
        );
      case 10:
        return _buildMultiCheckInputQuestion(
          question: "5-2. 현재 피우시는 담배의 종류는 무엇입니까?",
          selectedValues: state.current_types, // List<String>
          currentInputText: state.q5_other,
          options: [
            {"title": "일반담배(궐련)", "value": "cigarette"},
            {"title": "궐련형 전자담배(아이코스, 글로, 릴 등)", "value": "heated"},
            {"title": "액상형 전자담배(카트리지형, 주입형)", "value": "e_cig"},
            {"title": "기타 담배", "value": "other", "showInput": true},
          ],
          onValuesChanged: (newList) {
            setState(() {
              state.current_types = newList;
              if (!newList.contains("other")) {
                state.q5_other = "";
              }
            });
          },
          onTextChanged: (val) => setState(() => state.q5_other = val),
        );
      case 11:
        return _buildSmokingDetailQuestion();
      case 12:
      return _buildDynamicQuestion<String>(
        question: "6. 앞으로 담배를 끊을 계획이 있습니까?",
        groupValue: state.q6_quit_intention,
        options: [
          {"title": "현재로서는 전혀 금연할 생각이 없다", "value": "none"},
          {"title": "1개월 안에 금연할 계획이 있다", "value": "within_1m"},
          {"title": "6개월 안에 금연할 계획이 있다", "value": "within_6m"},
          {"title": "6개월 이내는 아니지만 언젠가는 금연할 생각이 있다.", "value": "someday"},
        ],
        onChanged: (val) => setState(() => state.q6_quit_intention = val!),
      );
      case 13:
      return _questionWrapper(
        title: "7. 최근 1년 동안 술을 마신 빈도는 어느 정도입니까?",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 마시고 있다 (상세 옵션 포함)
            _buildAlcoholSelectionCard(
              title: "마시고 있다",
              isSelected: state.drank == true,
              onTap: () => setState(() => state.drank = true),
              child: state.drank == true
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  const Text("마시는 빈도", style: TextStyle(fontFamily: 'SeoulNam', fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // 빈도 선택 라디오 리스트 (dense 스타일)
                  ...[
                    {"title": "한 달에 1번 미만", "value": "lt_1_per_month"},
                    {"title": "한 달에 1번 정도", "value": "1_per_month"},
                    {"title": "한 달에 2~4회 정도", "value": "2_4_per_month"},
                    {"title": "일주일에 2~3회 정도", "value": "2_3_per_week"},
                    {"title": "일주일에 4회 이상", "value": "4plus_per_week"},
                  ].map((opt) => RadioListTile<String>(
                    title: Text(opt["title"] as String, style: const TextStyle(fontSize: 15)),
                    value: opt["value"] as String,
                    groupValue: state.frequency,
                    activeColor: const Color(0xFFFB755B),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (val) => setState(() => state.frequency = val!),
                  )),
                  const SizedBox(height: 16),
                  const Text("한 번에 마시는 양", style: TextStyle(fontFamily: 'SeoulNam', fontSize: 15, fontWeight: FontWeight.bold)),
                  const Text("술 종류에 구분없이 각각의 술잔으로 계산, 단 캔맥주 1개(355cc)는 맥주 1.6잔과 같음", style: TextStyle(fontFamily: 'SeoulNam', fontSize: 15, color: Colors.grey)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text("평균 ", style: TextStyle(fontFamily: 'SeoulNam')),
                      _buildUnderlineInput(
                        width: 50,
                        value: state.amount_per_occasion_glasses == 0
                            ? "" : state.amount_per_occasion_glasses.toString(),
                        onChanged: (v) {
                          if (v.isEmpty) {
                            setState(() {
                              state.amount_per_occasion_glasses = 0;
                              state.avg = 0.0;
                            });
                            return;
                          }
                          int? inputNum = int.tryParse(v);
                          if (inputNum != null) {
                            int calculatedValue = inputNum;
                            if (calculatedValue > 10) {
                            }
                            else if (calculatedValue % 2 == 0 && calculatedValue > 0) {
                              calculatedValue = calculatedValue - 1;
                            }
                            if (calculatedValue < 0) calculatedValue = 0;
                            setState(() {
                              if (calculatedValue > 10) {
                                state.amount_per_occasion_glasses = 10;
                                state.avg = calculatedValue.toDouble();
                              }
                              state.amount_per_occasion_glasses = calculatedValue;
                            });
                          }
                        },
                      ),
                      const Text(" 잔"),
                    ],
                  ),
                ],
              )
                  : null,
            ),
            const SizedBox(height: 12),
            // 2. 전혀 마시지 않는다
            _buildAlcoholSelectionCard(
              title: "최근 6개월간 전혀 마시지 않았다",
              isSelected: state.drank == false,
              onTap: () => setState(() {
                state.drank = false;
                state.frequency = "never";
                state.amount_per_occasion_glasses = 0;
              }),
            ),
          ],
        ),
      );
      case 14:
      return _buildTimeInputQuestion(
        question: "8. 수면 시간을 제외하고, 깨어있는 시간 동안 앉거나 누워 있는 시간은 어느 정도 되십니까?",
        // double 데이터를 String으로 변환 (0일 경우 빈 문자열 표시)
        hourValue: state.hours_per_day == 0 ? "" : state.hours_per_day.toInt().toString(),
        minuteValue: state.minutes_per_day == 0 ? "" : state.minutes_per_day.toInt().toString(),
        // String 입력을 double로 변환하여 저장
        onHourChanged: (v) => setState(() => state.hours_per_day = double.tryParse(v) ?? 0),
        onMinuteChanged: (v) => setState(() => state.minutes_per_day = double.tryParse(v) ?? 0),
      );
      case 15:
        return _questionWrapper(
          title: "9. 최근 1주일 동안 신체활동을 한 날은 며칠입니까? 보통 하루에 몇 분간 했습니까?",
          description: "• 고강도: 격렬한 신체활동으로 숨이 많이 차거나 심장이 매우 빠르게 뛰는 활동\n• 중강도: 중간 정도의 신체활동으로, 숨이 차거나 심장이 약간 빠르게 뛰는 활동",
          child: Column(
            children: [
              // --- 직업형 섹션 ---
              _buildActivitySectionHeader("직업형 신체활동"),
              _buildActivityRow(
                title: "평소 일과 관련된 고강도 신체활동",
                subtitle: "(예: 무거운 것 들어 올리거나 나르는일, 건설 현장에서의 노동 등)",
                weekValue: state.work_high[0] == 0 ? "" : state.work_high[0].toInt().toString(),
                hourValue: state.work_high[1] == 0 ? "" : state.work_high[1].toInt().toString(),
                minValue: state.work_high[2] == 0 ? "" : state.work_high[2].toInt().toString(),
                onWeekChanged: (v) => setState(() => state.work_high[0] = double.tryParse(v) ?? 0),
                onHourChanged: (v) => setState(() => state.work_high[1] = double.tryParse(v) ?? 0),
                onMinChanged: (v) => setState(() => state.work_high[2] = double.tryParse(v) ?? 0),
              ),
              _buildActivityRow(
                title: "평소 일과 관련된 중강도 신체활동",
                subtitle: "(예: 빠르게 걷기, 가벼운 물건 나르기 등)",
                weekValue: state.work_mid[0] == 0 ? "" : state.work_mid[0].toInt().toString(),
                hourValue: state.work_mid[1] == 0 ? "" : state.work_mid[1].toInt().toString(),
                minValue: state.work_mid[2] == 0 ? "" : state.work_mid[2].toInt().toString(),
                onWeekChanged: (v) => setState(() => state.work_mid[0] = double.tryParse(v) ?? 0),
                onHourChanged: (v) => setState(() => state.work_mid[1] = double.tryParse(v) ?? 0),
                onMinChanged: (v) => setState(() => state.work_mid[2] = double.tryParse(v) ?? 0),
              ),
              // --- 이동형 섹션 ---
              _buildActivitySectionHeader("이동형 신체활동"),
              _buildActivityRow(
                title: "평소 장소를 이동할 때 걷거나 자전거 이용",
                subtitle: "(예: 일하러 갈 때, 쇼핑 갈 때 등)",
                weekValue: state.transport_walk_cycle[0] == 0 ? "" : state.transport_walk_cycle[0].toInt().toString(),
                hourValue: state.transport_walk_cycle[1] == 0 ? "" : state.transport_walk_cycle[1].toInt().toString(),
                minValue: state.transport_walk_cycle[2] == 0 ? "" : state.transport_walk_cycle[2].toInt().toString(),
                onWeekChanged: (v) => setState(() => state.transport_walk_cycle[0] = double.tryParse(v) ?? 0),
                onHourChanged: (v) => setState(() => state.transport_walk_cycle[1] = double.tryParse(v) ?? 0),
                onMinChanged: (v) => setState(() => state.transport_walk_cycle[2] = double.tryParse(v) ?? 0),
              ),
              // --- 여가형 섹션 ---
              _buildActivitySectionHeader("여가형 신체활동"),
              _buildActivityRow(
                title: "평소 고강도의 스포츠, 운동 및 여가 활동",
                subtitle: "(예: 달리기, 등산, 수영 등)",
                weekValue: state.leisure_high[0] == 0 ? "" : state.leisure_high[0].toInt().toString(),
                hourValue: state.leisure_high[1] == 0 ? "" : state.leisure_high[1].toInt().toString(),
                minValue: state.leisure_high[2] == 0 ? "" : state.leisure_high[2].toInt().toString(),
                onWeekChanged: (v) => setState(() => state.leisure_high[0] = double.tryParse(v) ?? 0),
                onHourChanged: (v) => setState(() => state.leisure_high[1] = double.tryParse(v) ?? 0),
                onMinChanged: (v) => setState(() => state.leisure_high[2] = double.tryParse(v) ?? 0),
              ),
              _buildActivityRow(
                title: "평소 중강도의 스포츠, 운동 및 여가 활동",
                subtitle: "(예: 빠르게 걷기, 웨이트 트레이닝, 골프 등)",
                weekValue: state.leisure_mid[0] == 0 ? "" : state.leisure_mid[0].toInt().toString(),
                hourValue: state.leisure_mid[1] == 0 ? "" : state.leisure_mid[1].toInt().toString(),
                minValue: state.leisure_mid[2] == 0 ? "" : state.leisure_mid[2].toInt().toString(),
                onWeekChanged: (v) => setState(() => state.leisure_mid[0] = double.tryParse(v) ?? 0),
                onHourChanged: (v) => setState(() => state.leisure_mid[1] = double.tryParse(v) ?? 0),
                onMinChanged: (v) => setState(() => state.leisure_mid[2] = double.tryParse(v) ?? 0),
              ),
            ],
          ),
        );

      case 16:
        return _buildDynamicQuestion<String>(
          question: "9-1. 건강을 위해서 신체활동을 실천할 계획이 있습니까?",
          groupValue: state.stage_of_change,
          options: [
            {"title": "앞으로 규칙적인 신체활동을 실천할 생각이 없다", "value": "no_intention"},
            {"title": "앞으로 규칙적인 신체활동을 실천할 생각이 있다", "value": "intention"},
            {"title": "규칙적인 신체활동에 가끔 참여하고 있다", "value": "sometimes"},
            {"title": "6개월 미만 규칙적으로 신체활동을 실천하였다", "value": "less_6m_regular"},
            {"title": "6개월 이상 규칙적으로 신체활동을 실천하였다", "value": "more_6m_regular"},
          ],
          onChanged: (val) => setState(() => state.stage_of_change = val!),
        );
      case 17:
        return _buildDynamicInputQuestion<String>(
          question: "9-2. 신체활동을 실천할 계획이 없다면 가장 큰 이유는 무엇입니까?",
          groupValue: state.no_activity_main_reason,
          currentInputText: state.q9_1_other,
          options: [
            {"title": "질환으로 거동이 불편해서", "value": "disease"},
            {"title": "게으름 또는 관심이 없어서", "value": "low_will"},
            {"title": "경제적 여유가 없어서", "value": "economic"},
            {"title": "시간적 여유가 없어서", "value": "time"},
            {"title": "운동할 장소 및 시설이 없어서", "value": "place"},
            {"title": "기타", "value": "other", "unit": "", "showInput": true},
          ],
          onRadioChanged: (val) => setState(() => state.no_activity_main_reason = val!),
          onTextChanged: (val) => setState(() => state.q9_1_other = val),
        );
      case 18:
        return _buildDynamicInputQuestion<String>(
          question: "10. 최근 6개월 전과 비교해 보았을 때 몸무게에 변화가 있었습니까? 몸무게가 줄거나 늘었다면 어느 정도였습니까?",
          groupValue: state.status,
          currentInputText: state.kg == 0 ? "" : state.kg.toInt().toString(),
          options: [
            {"title": "변화가 없었다(0kg 이상 ~ 3kg 미만 증가 및 감소 포함)", "value": ""},
            {"title": "몸무게가 줄었다.", "value": "loss", "showInput": true, "unit": "kg"},
            {"title": "몸무게가 늘었다.", "value": "gain", "showInput": true, "unit": "kg"},
          ],
            onRadioChanged: (val) => setState(() => state.status = val!),
            onTextChanged: (val) => setState(() => state.kg = double.tryParse(val) ?? 0),
            );
      case 19:
        return _buildDynamicQuestion<String>(
          question: "11. 현재 본인의 체형이 어떻다고 생각하십니까?",
          groupValue: state.q11_self_body_image,
          options: [
            {"title": "매우 마른 편이다", "value": "very_thin"},
            {"title": "약간 마른 편이다", "value": "slightly_thin"},
            {"title": "보통이다", "value": "normal"},
            {"title": "약간 비만이다", "value": "slightly_obese"},
            {"title": "매우 비만이다", "value": "very_obese"},
        ],
        onChanged: (val) => setState(() => state.q11_self_body_image = val!)
        );
      case 20:
        return _buildDynamicQuestion<String>(
          question: "12. 최근 6개월 동안 몸무게를 조절하려고 노력한 적이 있습니까?",
          groupValue: state.q12_weight_control_effort,
          options: [
            {"title": "몸무게를 줄이려고 노력했다", "value": "lose"},
            {"title": "몸무게를 유지하려고 노력했다", "value": "maintain"},
            {"title": "몸무게를 늘리려고 노력했다", "value": "gain"},
            {"title": "몸무게를 조절하기 위해 노력해 본 적 없다", "value": "none"},
          ],
          onChanged: (val) => setState(() => state.q12_weight_control_effort = val!),
          );
      case 21:
        return _buildDynamicQuestion<int>(
          question: "13. 최근 6개월 동안 아침식사를 일주일에 몇 회 하셨습니까?",
          groupValue: state.q13_breakfast_frequency_per_week,
          options: [
            {"title": "주 5~7회", "value": 5},
            {"title": "주 3~4회", "value": 3},
            {"title": "주 1~2회", "value": 1},
            {"title": "거의 안한다(주 0회)", "value": 0},
          ],
          onChanged: (val) => setState(() => state.q13_breakfast_frequency_per_week = val!),
        );
      case 22:
      return _buildDynamicCheckboxQuestion<String>(
        question: "14. 지난 1주일 동안 다음 식생활 항목을 실천하셨는지 표시 해주시길 바랍니다.",
        description: "주 5회 이상 실천했을 경우 '예', 주 4회 이하의 경우 '아니오'.",
        options: [
          {"title": "곡류를 다양하게 먹고 전곡을 많이 먹습니다(현미, 잡곡 등)", "value": "grain"},
          {"title": "여러 가지 색깔의 채소를 매끼 2가지 이상 먹습니다", "value": "vege"},
          {"title": "다양한 제철과일을 매일 먹습니다.", "value": "fruit"},
          {"title": "우유, 요구르트, 치즈와 같은 유제품을 매일 먹습니다", "value": "dairy"},
          {"title": "매일 세끼 식사를 규칙적으로 합니다", "value": "meals"},
          {"title": "밥과 댜앙한 반찬으로 균형 잡힌 식생활을 합니다(한식 위주)", "value": "balanced"},
          {"title": "짠 음식, 짠 국물을 적게 먹습니다", "value": "low_salt"},
          {"title": "음식을 먹을 때 소금, 간장을 더 넣지 않습니다", "value": "no_extra_salt"},
          {"title": "고기를 먹을 때 기름을 떼어내고 먹습니다", "value": "no_fat"},
          {"title": "튀긴 음식(전이나 부침 포함)을 적게 먹습니다", "value": "low_fried"},
        ],
        // 현재 각 변수의 상태를 직접 전달
        isSelected: (val) {
          switch (val) {
            case "grain": return state.grain_diversity;
            case "vege": return state.vegetable_variety;
            case "fruit": return state.daily_fruit;
            case "dairy": return state.daily_dairy;
            case "meals": return state.regular_3_meals;
            case "balanced": return state.balanced_korean_meal;
            case "low_salt": return state.low_salt;
            case "no_extra_salt": return state.no_extra_salt;
            case "no_fat": return state.remove_meat_fat;
            case "low_fried": return state.low_fried_food;
            default: return false;
          }
        },
        onChanged: (val, isChecked) {
          setState(() {
            // 1. 개별 bool 변수 업데이트
            switch (val) {
              case "grain": state.grain_diversity = isChecked; break;
              case "vege": state.vegetable_variety = isChecked; break;
              case "fruit": state.daily_fruit = isChecked; break;
              case "dairy": state.daily_dairy = isChecked; break;
              case "meals": state.regular_3_meals = isChecked; break;
              case "balanced": state.balanced_korean_meal = isChecked; break;
              case "low_salt": state.low_salt = isChecked; break;
              case "no_extra_salt": state.no_extra_salt = isChecked; break;
              case "no_fat": state.remove_meat_fat = isChecked; break;
              case "low_fried": state.low_fried_food = isChecked; break;
            }

            // 2. 점수 합산 로직 (bool이 true인 것만 카운트)
            state.q14_total_score = [
              state.grain_diversity, state.vegetable_variety, state.daily_fruit,
              state.daily_dairy, state.regular_3_meals, state.balanced_korean_meal,
              state.low_salt, state.no_extra_salt, state.remove_meat_fat, state.low_fried_food
            ].where((e) => e == true).length;
          });
        },
      );
      case 23:
        return _buildDynamicInputQuestion<String>(
          question: "15. 바람직한 식생활이 되지 않는 가장 큰 이유는 무엇입니까? (한 가지만 선택하세요)",
          groupValue: state.q15_why_poor_diet,
          currentInputText: state.q15_other,
          options: [
            {"title": "경제적으로 힘들어서", "value": "economic"},
            {"title": "식사준비를 도와주는 사람이 없어서", "value": "no_helper"},
            {"title": "의지가 약해서", "value": "low_will"},
            {"title": "치아결손 등의 문제로 씹기가 힘들어서", "value": "chewing_problem"},
            {"title": "영양정보를 몰라서", "value": "lack_info"},
            {"title": "입맛(식욕)이 없어서", "value": "low_appetite"},
            {"title": "기타", "value": "other", "unit": "","showInput": true},
          ],
          onRadioChanged: (val) => setState(() => state.q15_why_poor_diet = val!),
          onTextChanged: (val) => setState(() => state.q15_other = val!),
        );
      case 24:
        return _questionWrapper(
          title: "16. 하루에 보통 몇 시간 주무십니까?",
          child: Column(
            children: [
              _buildSleepInputRow(
                label: "주중(또는 일하는 날)",
                value: state.weekday == 0 ? "" : state.weekday.toString(),
                onChanged: (v) => setState(() => state.weekday = int.tryParse(v) ?? 0),
              ),
              const SizedBox(height: 16),
              _buildSleepInputRow(
                label: "주말(또는 일하지 않는 날, 일하지 않는 전날)",
                value: state.weekend == 0 ? "" : state.weekend.toString(),
                onChanged: (v) => setState(() => state.weekend = int.tryParse(v) ?? 0),
              ),
            ],
          ),
        );
      case 25:
      List<Map<String, String>> _phq9Options() => [
        {"key": "depressed_mood", "title": "① 기분이 가라앉거나, 우울하거나 희망이 없다고 느꼈다"},
        {"key": "loss_of_interest", "title": "② 평소 하던 일에 대한 흥미가 없어지거나 즐거움을 느끼지 못했다"},
        {"key": "sleep_problem", "title": "③ 잠들기가 어렵거나 자주 깼다 / 혹은 너무 많이 잤다"},
        {"key": "appetite_change", "title": "④ 평소보다 식욕이 줄었다 / 혹은 평소보다 많이 먹었다"},
        {"key": "psychomotor_change", "title": "⑤ 남들이 알아챌 정도로 평소보다 말과 행동이 느려졌다 / 혹은 너무 안절부절 하지 못해서 가만히 앉아 있을 수 없었다"},
        {"key": "fatigue", "title": "⑥ 피곤하거나 기운이 없었다"},
        {"key": "worthlessness", "title": "⑦ 내가 잘못했거나 실패했다는 생각이 들었다 / 혹은 자신과 가족을 실망시켰다고 생각했다"},
        {"key": "concentration", "title": "⑧ 신문을 읽거나 TV를 보는 것과 같은 일상적인 일에도 집중할 수가 없었다"},
        {"key": "suicidal_ideation", "title": "⑨ 차라리 죽는 것이 낫겠다고 생각했다 / 혹은 자해 할 생각을 했다"},
      ];
      return _questionWrapper(
        title: "17. 최근 2주일 동안 자신에게 해당된다고 생각하는 곳에 체크해주세요.",
        child: Column(
          children: [
            // 상단 헤더
            _buildScoreHeader(),
            const SizedBox(height: 8),
            // 질문 리스트 빌드
            ..._phq9Options().map((option) {
              final String key = option['key']!;

              // 1. 현재 변수 값 가져오기 (getter 대용)
              int currentValue;
              switch (key) {
                case "depressed_mood": currentValue = state.depressed_mood; break;
                case "loss_of_interest": currentValue = state.loss_of_interest; break;
                case "sleep_problem": currentValue = state.sleep_problem; break;
                case "appetite_change": currentValue = state.appetite_change; break;
                case "psychomotor_change": currentValue = state.psychomotor_change; break;
                case "fatigue": currentValue = state.fatigue; break;
                case "worthlessness": currentValue = state.worthlessness; break;
                case "concentration": currentValue = state.concentration; break;
                case "suicidal_ideation": currentValue = state.suicidal_ideation; break;
                default: currentValue = 0;
              }

              return _buildPhqRow(
                title: option['title']!,
                currentValue: currentValue,
                onChanged: (score) {
                  setState(() {
                    // 2. 개별 변수 직접 업데이트 (setter 대용)
                    switch (key) {
                      case "depressed_mood": state.depressed_mood = score; break;
                      case "loss_of_interest": state.loss_of_interest = score; break;
                      case "sleep_problem": state.sleep_problem = score; break;
                      case "appetite_change": state.appetite_change = score; break;
                      case "psychomotor_change": state.psychomotor_change = score; break;
                      case "fatigue": state.fatigue = score; break;
                      case "worthlessness": state.worthlessness = score; break;
                      case "concentration": state.concentration = score; break;
                      case "suicidal_ideation": state.suicidal_ideation = score; break;
                    }

                    // 3. 총점 실시간 합산
                    state.q17_total_score =
                        state.depressed_mood + state.loss_of_interest + state.sleep_problem +
                            state.appetite_change + state.psychomotor_change + state.fatigue +
                            state.worthlessness + state.concentration + state.suicidal_ideation;
                  });
                },
              );
            }),
            // 하단 총점 표시 영역
            _buildTotalScoreFooter(state.q17_total_score),
          ],
        ),
      );
      case 26:
        return _buildDynamicQuestion<String>(
          question: "18. 혼인상태가 어떻게 되십니까?",
          groupValue: state.marry,
          options: [
            {"title": "기혼(배우자 유)", "value": "married_with_spouse"},
            {"title": "기혼(배우자 무)", "value": "married_no_spouse"},
            {"title": "미혼", "value": "single"},
            {"title": "무응답", "value": "no_answer"},
          ],
          onChanged: (val) => setState(() => state.marry = val!),
        );
      case 27:
        return _buildDynamicQuestion<int>(
          question: "19. 현재 살고 계신 댁에 본인을 포함하여 총 몇 명이서 살고 계십니까?",
          groupValue: state.household_size,
          options: [
            {"title": "1인", "value": 1},
            {"title": "2인", "value": 2},
            {"title": "3인", "value": 3},
            {"title": "4인 이상", "value": 4},
            {"title": "무응답", "value": 0},
          ],
          onChanged: (val) => setState(() => state.household_size = val!),
        );
      case 28:
        return _buildDynamicQuestion<String>(
          question: "20. 건강보험 가입형태가 어떻게 되십니까?",
          groupValue: state.insurance_type,
          options: [
            {"title": "건강보험(지역/직장)", "value": "nhis"},
            {"title": "의료급여(1종/2종)", "value": "medical_aid"},
            {"title": "미가입", "value": "none"},
            {"title": "무응답", "value": "no_answer"},
          ],
          onChanged: (val) => setState(() => state.insurance_type = val!),
        );
      case 29:
        //education_level
        return _buildDynamicQuestion<String>(
          question: "21. 최종학력이 어떻게 되십니까?",
          groupValue: state.education_level,
          options: [
            {"title": "초등학교 졸업 이하", "value": "primary_or_less"},
            {"title": "중학교 졸업", "value": "middle"},
            {"title": "고등학교 졸업", "value": "high_school"},
            {"title": "대학(전문대) 졸업 이상", "value": "college_or_more"},
            {"title": "무응답", "value": "no_answer"},
          ],
          onChanged: (val) => setState(() => state.education_level = val!),
        );
      case 30:
        return _buildDynamicQuestion<int>(
          question: "22. 현재 월 가구소득은 어떻게 되십니까?",
          groupValue: state.monthly_household_income,
          options: [
            {"title": "200만원 미만", "value": 200},
            {"title": "200~400만원 미만", "value": 300},
            {"title": "400~600만원 미만", "value": 500},
            {"title": "600만원 이상", "value": 600},
            {"title": "무응답", "value": 0},
          ],
          onChanged: (val) => setState(() => state.monthly_household_income = val!),
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
  }Widget _buildDynamicInputQuestion<T>({
    required String question,
    required T? groupValue,
    required List<Map<String, dynamic>> options,
    required String currentInputText,
    required ValueChanged<T?> onRadioChanged,
    required ValueChanged<String> onTextChanged,
  }) {
    return _questionWrapper(
      title: question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...options.map((option) {
            bool isSelected = groupValue == option['value'];
            bool canShowInput = option['showInput'] ?? false;
            // 각 옵션에서 unit을 가져옴 (없을 경우 기본값 "")
            String unitText = option['unit'] ?? "";

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFB755B) : Colors.grey[200]!,
                  width: 1.5,
                ),
              ),
              child: RadioListTile<T>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Row(
                  children: [
                    // 1. 항목 제목
                    Flexible(
                      flex: 3,
                      child: Text(
                        textAlign: TextAlign.justify,
                        softWrap: true,
                        option['title'],
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'SeoulNam',
                          color: isSelected ? const Color(0xFFFB755B) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),

                    // 2. 입력창 영역
                    if (isSelected && canShowInput) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFB755B),
                            fontFamily: 'SeoulNam',
                          ),
                          controller: TextEditingController.fromValue(
                            TextEditingValue(
                              text: currentInputText,
                              selection: TextSelection.collapsed(offset: currentInputText.length),
                            ),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "입력",
                            // 1. 힌트 스타일을 입력 텍스트 스타일과 동일하게 설정
                            hintStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey, // 색상 통일
                              fontFamily: 'SeoulNam',
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFFB755B)),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFFB755B), width: 2),
                            ),
                          ),
                          onChanged: onTextChanged,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 2. 동적으로 단위를 표시
                      Text(
                        unitText,
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                            fontFamily: 'SeoulNam'
                        ),
                      ),
                    ],
                  ],
                ),
                value: option['value'] as T,
                groupValue: groupValue,
                onChanged: onRadioChanged,
                activeColor: const Color(0xFFFB755B),
                controlAffinity: ListTileControlAffinity.trailing,
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

  Widget _buildMultiCheckInputQuestion({
    required String question,
    required List<String> selectedValues, // state.current_types (List<String>)
    required List<Map<String, dynamic>> options,
    required String currentInputText,
    required Function(List<String>) onValuesChanged, // 리스트 변경 콜백
    required ValueChanged<String> onTextChanged,
  }) {
    return _questionWrapper(
      title: question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...options.map((option) {
            String value = option['value'] as String;
            bool isSelected = selectedValues.contains(value);
            bool canShowInput = option['showInput'] ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFB755B) : Colors.grey[200]!,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            softWrap: true,
                            textAlign: TextAlign.justify,
                            option['title'],
                            style: TextStyle(
                              fontSize: 15,
                              fontFamily: 'SeoulNam',
                              color: isSelected ? const Color(0xFFFB755B) : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        // 체크되었고, 입력창이 필요한 옵션(기타)인 경우 1라인에 표시
                        if (isSelected && canShowInput) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80, // 기타 입력창은 보통 글자가 들어가므로 조금 더 넓게 설정
                            child: TextField(
                              key: ValueKey("input_$value"),
                              controller: TextEditingController.fromValue(
                                TextEditingValue(
                                  text: currentInputText,
                                  selection: TextSelection.collapsed(offset: currentInputText.length),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFB755B),
                              ),
                              decoration: const InputDecoration(
                                hintText: "이름 입력",
                                hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFFB755B)),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Color(0xFFFB755B), width: 2),
                                ),
                              ),
                              onChanged: onTextChanged,
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: isSelected,
                    activeColor: const Color(0xFFFB755B),
                    checkColor: Colors.white,
                    controlAffinity: ListTileControlAffinity.trailing,
                    onChanged: (bool? checked) {
                      List<String> newList = List.from(selectedValues);
                      if (checked == true) {
                        if (!newList.contains(value)) newList.add(value);
                      } else {
                        newList.remove(value);
                      }
                      onValuesChanged(newList);
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildNestedQuestion<T>({
    required String question,
    required T? groupValue,
    required List<Map<String, dynamic>> options, // { "title": "...", "value": T, "nestedChild": Widget? }
    required ValueChanged<T?> onChanged,
  }) {
    return _questionWrapper(
      title: question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: options.map((option) {
          bool isSelected = groupValue == option['value'];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFFFB755B) : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                RadioListTile<T>(
                  title: Text(
                    textAlign: TextAlign.justify,
                    softWrap: true,
                    option['title'],
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'SeoulNam',
                      color: isSelected ? const Color(0xFFFB755B) : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  value: option['value'] as T,
                  groupValue: groupValue,
                  onChanged: onChanged,
                  activeColor: const Color(0xFFFB755B),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
                // 핵심: 선택되었고, 하위 위젯(nestedChild)이 정의되어 있다면 표시
                if (isSelected && option['nestedChild'] != null)
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    width: double.infinity,
                    child: option['nestedChild'],
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
  Widget _buildSmokingDetailQuestion() {
    return _questionWrapper(
      title: "5-3. 현재 혹은 과거 담배를 피웠을 때 평균 흡연량과 흡연기간은 얼마입니까?",
      description: "※ 매일 피움/가끔 피움 중 하나를 선택하여 기입",
      child: Column(
        children: [
          // 테이블 헤더 스타일 (주황색 강조)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFB755B).withOpacity(0.1), // 연한 주황 배경
              border: const Border(top: BorderSide(color: Color(0xFFFB755B), width: 2)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text("구분", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                Expanded(flex: 5, child: Text("흡연량 및 빈도", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                Expanded(flex: 3, child: Text("흡연기간", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              ],
            ),
          ),

          // 1. 매일 피움 행
          _buildSmokingRow(
            label: "매일\n피움",
            inputRow: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("하루 평균 ", style: TextStyle(fontSize: 15)),
                _buildSmallInputField(
                  onChanged: (v) => setState(() => state.avg_cigs_per_day = int.tryParse(v) ?? 0),
                  initialValue: state.avg_cigs_per_day.toString(),
                ),
                const Text(" 개비", style: TextStyle(fontSize: 15)),
              ],
            ),
            durationInput: _buildDurationField(),
          ),

          // 2. 가끔 피움 행 (Wrap이나 FittedBox를 사용하여 오버플로우 방지)
          _buildSmokingRow(
            label: "가끔\n피움",
            inputRow: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox( // 텍스트가 넘치면 자동으로 크기 조절
                  fit: BoxFit.scaleDown,
                  child: Row(
                    children: [
                      const Text("하루 평균 ", style: TextStyle(fontSize: 15)),
                      _buildSmallInputField(
                        onChanged: (v) => setState(() => state.avg_cigs_per_day = int.tryParse(v) ?? 0),
                      ),
                      const Text(" 개비", style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("1달간 ", style: TextStyle(fontSize: 15)),
                    _buildSmallInputField(
                      onChanged: (v) => setState(() => state.avg_cigs_per_month = int.tryParse(v) ?? 0),
                    ),
                    const Text(" 일", style: TextStyle(fontSize: 15)),
                  ],
                ),
              ],
            ),
            durationInput: _buildDurationField(),
          ),
        ],
      ),
    );
  }

  // 행 빌더
  Widget _buildSmokingRow({required String label, required Widget inputRow, required Widget durationInput}) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 라벨 배경색 주황색 계열로 변경
            Expanded(flex: 2, child: Container(alignment: Alignment.center, color: const Color(0xFFFB755B).withOpacity(0.05), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(flex: 5, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), child: inputRow)),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(4.0), child: durationInput)),
          ],
        ),
      ),
    );
  }

  // 작은 입력칸 빌더 (주황색 테두리 적용)
  Widget _buildSmallInputField({required Function(String) onChanged, String initialValue = ""}) {
    return Container(
      width: 35, // 너비를 살짝 줄임
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: TextField(
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFB755B)),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFB755B))),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        ),
        onChanged: onChanged,
      ),
    );
  }

  // 흡연기간 입력칸
  Widget _buildDurationField() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSmallInputField(onChanged: (v) => setState(() => state.smoking_years = int.tryParse(v) ?? 0)),
        const Text(" 년", style: TextStyle(fontSize: 15)),
      ],
    );
  }

  Widget _buildTimeInputQuestion({
    required String question,
    required String hourValue,
    required String minuteValue,
    required ValueChanged<String> onHourChanged,
    required ValueChanged<String> onMinuteChanged,
  }) {
    return _questionWrapper(
      title: question,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, // 가운데 정렬
        children: [
          const Text("하루  ", style: TextStyle(fontSize: 15)),
          _buildUnderlineInput(width: 60, value: hourValue, onChanged: onHourChanged),
          const Text("  시간  ", style: TextStyle(fontSize: 15)),
          _buildUnderlineInput(width: 60, value: minuteValue, onChanged: onMinuteChanged),
          const Text("  분", style: TextStyle(fontSize: 15)),
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


// 섹션 헤더 (주황색 테마 적용)
  Widget _buildActivitySectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFB755B).withOpacity(0.1), // 연한 주황색 배경
        border: const Border(
          top: BorderSide(color: Color(0xFFFB755B), width: 1),
          bottom: BorderSide(color: Color(0xFFFB755B), width: 1),
        ),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFFFB755B),
          fontFamily: 'SeoulNam',
        ),
      ),
    );
  }

// 각 활동별 입력 행 (Overflow 방지 로직 적용)
  Widget _buildActivityRow({
    required String title,
    required String subtitle,
    required String weekValue,
    required String hourValue,
    required String minValue,
    required ValueChanged<String> onWeekChanged,
    required ValueChanged<String> onHourChanged,
    required ValueChanged<String> onMinChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽: 활동 설명 (flex 비율 조정)
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'SeoulNam')),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 15, color: Colors.grey[600], fontFamily: 'SeoulNam')),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 오른쪽: 입력 영역 (FittedBox로 넘침 방지)
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text("주 ", style: TextStyle(fontSize: 15, fontFamily: 'SeoulNam')),
                      _buildUnderlineInput(width: 30, value: weekValue, onChanged: onWeekChanged),
                      const Text(" 일", style: TextStyle(fontSize: 15, fontFamily: 'SeoulNam')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text("하루 ", style: TextStyle(fontSize: 15, fontFamily: 'SeoulNam')),
                      _buildUnderlineInput(width: 30, value: hourValue, onChanged: onHourChanged),
                      const Text(" 시간  ", style: TextStyle(fontSize: 15, fontFamily: 'SeoulNam')),
                      _buildUnderlineInput(width: 30, value: minValue, onChanged: onMinChanged),
                      const Text(" 분", style: TextStyle(fontSize: 15, fontFamily: 'SeoulNam')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
// 셀 빌더 (체크박스 영역)
  Widget _buildCheckCell({required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      flex: 2,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 60, // 터치 영역 확보
          alignment: Alignment.center,
          child: Icon(
            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
            color: isSelected ? const Color(0xFFFB755B) : Colors.grey[400],
            size: 24,
          ),
        ),
      ),
    );
  }


// _buildDynamicInputQuestion과 동일한 스타일의 카드 빌더
  Widget _buildAlcoholSelectionCard({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFFFB755B) : Colors.grey[200]!,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Theme(
            // RadioListTile의 기본 패딩 제거 및 스타일 통일
            data: ThemeData(unselectedWidgetColor: Colors.grey[400]),
            child: RadioListTile<bool>(
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'SeoulNam',
                  color: isSelected ? const Color(0xFFFB755B) : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: const Color(0xFFFB755B),
              controlAffinity: ListTileControlAffinity.trailing, // 라디오를 오른쪽으로
            ),
          ),
          if (child != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
  Widget _buildDynamicCheckboxQuestion<T>({
    required String question,
    String? description,
    required List<Map<String, dynamic>> options,
    required bool Function(T) isSelected, // 현재 변수 상태를 확인하는 함수
    required Function(T, bool) onChanged,
  }) {
    return _questionWrapper(
      title: question,
      description: description,
      child: Column(
        children: options.map((option) {
          final T value = option['value'] as T;
          final bool checked = isSelected(value); // 여기서 변수 상태 확인

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: checked ? const Color(0xFFFB755B) : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: CheckboxListTile(
              title: Text(
                option['title'],
                textAlign: TextAlign.justify,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'SeoulNam',
                  color: checked ? const Color(0xFFFB755B) : Colors.black87,
                  fontWeight: checked ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              value: checked,
              onChanged: (val) => onChanged(value, val ?? false),
              activeColor: const Color(0xFFFB755B),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          );
        }).toList(),
      ),
    );
  }

  // 수면 시간 전용 입력 행 위젯
  Widget _buildSleepInputRow({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // 라벨 영역 (글자가 길면 줄바꿈)
          Expanded(
            flex: 7,
            child: Text(
              "$label : ",
              style: const TextStyle(
                fontSize: 15,
                fontFamily: 'SeoulNam',
                color: Colors.black87,
              ),
            ),
          ),
          // 입력 영역
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text("", style: TextStyle(color: Colors.grey)),
                _buildUnderlineInput(
                  width: 40,
                  value: value,
                  onChanged: onChanged,
                ),
                const Text(" 시간",
                    style: TextStyle(fontFamily: 'SeoulNam', fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

// 1. 헤더 영역
  Widget _buildScoreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Expanded(flex: 4, child: Center(child: Text("최근 2주 간 나는", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
          _headerItem("없음\n(0점)"),
          _headerItem("며칠동안\n(1점)"),
          _headerItem("일주일이상\n(2점)"),
          _headerItem("거의 매일\n(3점)"),
        ],
      ),
    );
  }

  Widget _headerItem(String text) => Expanded(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)));

// 2. 질문 로우 (양옆 정렬 및 폰트 적용)
  Widget _buildPhqRow({required String title, required int currentValue, required Function(int) onChanged}) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
                title,
                textAlign: TextAlign.justify,
                style: const TextStyle(fontSize: 13, fontFamily: 'SeoulNam', height: 1.4, letterSpacing: -0.3)
            ),
          ),
          ...List.generate(4, (index) => Expanded(
            child: InkWell(
              onTap: () => onChanged(index),
              child: Icon(
                currentValue == index ? Icons.check_box : Icons.check_box_outline_blank,
                color: currentValue == index ? const Color(0xFFFB755B) : Colors.grey[300],
              ),
            ),
          )),
        ],
      ),
    );
  }

// 3. 총점 표시 푸터
  Widget _buildTotalScoreFooter(int total) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF4F2), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text("총 점 : ", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'SeoulNam')),
          Text("$total", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFB755B), fontSize: 18)),
          const Text(" 점", style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'SeoulNam')),
        ],
      ),
    );
  }
}
