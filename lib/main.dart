import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'screens/ecg_data_service.dart';
import 'screens/ecg_page.dart';
import 'screens/api_client.dart';
import 'screens/login_page.dart';
import 'screens/setting_page.dart';
import 'screens/ecg_detail_page.dart';
import 'screens/survey_page.dart';
import 'screens/vital_signs_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/main_tab_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  ApiClient().setupTokenListener();



  final ecgService = EcgDataService();
  await ecgService.loadInitialData();

  final vitalSignsService = VitalSignsService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ecgService),
        ChangeNotifierProvider.value(value: vitalSignsService),
      ],
      child: const HealthApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (Platform.isAndroid) {
      debugPrint("🟢 Android 환경 - setupWatchListener 실행");
      setupWatchListener();

      final context = navigatorKey.currentContext!;
      final ecgService = Provider.of<EcgDataService>(context, listen: false);
      await preloadSavedEcgFiles(ecgService);
    } else {
      debugPrint("🟡 ECG 초기화 생략 (iOS)");
    }
  });
}

void setupWatchListener() {
  const MethodChannel platform = MethodChannel('com.example.xalute/watch');

  platform.setMethodCallHandler((call) async {
    debugPrint("👂 MethodChannel received call: ${call.method}");

    if (call.method == 'getFirebaseToken') {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("❌ Firebase 토큰 요청 실패: 로그인되지 않음");
        return null;
      }
      final token = await user.getIdToken(true); // true = 강제 갱신
      debugPrint("✅ Firebase 토큰 반환 완료");
      return token;
    }

    if (call.method == 'onEcgFileReceived') {
      final Map<String, dynamic> data = jsonDecode(call.arguments);

      final String fileContent = data['fileContent'];
      final String result = data['result'];
      final int timestamp = data['timestamp'];
      final Map<String, dynamic> resultJson = jsonDecode(data['result_json']);

      await saveReceivedEcg(fileContent, result, timestamp, resultJson);

      debugPrint("📈 R-peaks: ${resultJson['result']['r_peaks']}");
      debugPrint("📉 distance_from_median: ${resultJson['result']['distance_from_median']}");

      // 바이탈 사인 데이터 파싱 및 저장
      try {
        final List<dynamic> spo2Raw = jsonDecode(data['spo2_data'] ?? '[]');
        final List<dynamic> hrRaw = jsonDecode(data['heart_rate_data'] ?? '[]');
        final List<dynamic> tempRaw = jsonDecode(data['skin_temp_data'] ?? '[]');

        final context = navigatorKey.currentContext!;
        final vitalService = Provider.of<VitalSignsService>(context, listen: false);
        vitalService.updateData(
          spo2: spo2Raw.map((e) => (e as num).toInt()).toList(),
          heartRate: hrRaw.map((e) => (e as num).toInt()).toList(),
          skinTemp: tempRaw.map((e) => (e as num).toDouble()).toList(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal(),
        );
        debugPrint("✅ 바이탈 데이터 업데이트 완료 - SpO2: ${spo2Raw.length}개, HR: ${hrRaw.length}개, Temp: ${tempRaw.length}개");
      } catch (e) {
        debugPrint("⚠️ 바이탈 데이터 파싱 실패: $e");
      }
    }
  });
}

Future<void> saveReceivedEcg(
    String content,
    String result,
    int timestamp,
    Map<String, dynamic> resultJson,
    ) async {
  final dir = await getApplicationDocumentsDirectory();

  final timestampStr = DateFormat('yyyyMMddHHmmss').format(
    DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal(),
  );

  final fileName = 'ecg_${timestampStr}_$result.txt';
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content);
  debugPrint("✅ ECG 텍스트 저장 완료: ${file.path}");

  final jsonFileName = 'ecg_${timestampStr}_$result.json';
  final jsonFile = File('${dir.path}/$jsonFileName');
  await jsonFile.writeAsString(jsonEncode(resultJson));
  debugPrint("✅ 분석 결과 JSON 저장 완료: ${jsonFile.path}");

  final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  final mappedResult = result.toLowerCase() == 'normal' ? '정상' : '이상 소견 의심';

  final context = navigatorKey.currentContext!;
  final ecgService = Provider.of<EcgDataService>(context, listen: false);

  ecgService.addEntry(EcgEntry(
    dateTime: dateTime,
    result: mappedResult,
    color: mappedResult == '정상' ? Colors.green : const Color(0xFFFB755B),
    content: content,
    txtPath: file.path,
    jsonPath: jsonFile.path,
    deviceType: Platform.isIOS ? 'iOS' : 'Android',
  ));

  debugPrint("📂 저장된 파일 이름(txt): $fileName");
  debugPrint("📂 저장된 파일 이름(json): $jsonFileName");

}

Future<void> preloadSavedEcgFiles(EcgDataService service) async {
  final dir = await getApplicationDocumentsDirectory();
  final files = dir.listSync();

  int loadedCount = 0;

  for (var file in files) {
    if (file is! File) continue;

    final fileName = file.uri.pathSegments.last;

    if (!RegExp(r'^ecg_\d{14}_(normal|abnormal)\.txt$').hasMatch(fileName)) {
      debugPrint("⚠️ 무시된 파일: $fileName");
      continue;
    }

    try {
      final fileNameWithoutExt = fileName.substring(0, fileName.length - 4);
      final parts = fileNameWithoutExt.split('_');

      final timestampStr = parts[1];
      if (timestampStr.length != 14) {
        debugPrint("⚠️ 잘못된 timestamp 길이: $fileName");
        continue;
      }

      final year = int.parse(timestampStr.substring(0, 4));
      final month = int.parse(timestampStr.substring(4, 6));
      final day = int.parse(timestampStr.substring(6, 8));
      final hour = int.parse(timestampStr.substring(8, 10));
      final minute = int.parse(timestampStr.substring(10, 12));
      final second = int.parse(timestampStr.substring(12, 14));
      final dateTime = DateTime(year, month, day, hour, minute, second);

      final resultCode = parts[2];
      debugPrint("⚠️ resultCode: $resultCode");
      final result = resultCode == 'normal' ? '정상' : '이상 소견 의심';
      final color = result == '정상' ? Colors.green : const Color(0xFFFB755B);
      final content = await file.readAsString();

      final isDuplicate = service.entries.any((entry) =>
      entry.dateTime == dateTime && entry.content == content);
      if (isDuplicate) {
        debugPrint("🔁 중복 생략: $fileName");
        continue;
      }

      final jsonFilePath = '${dir.path}/ecg_${timestampStr}_$resultCode.json';

      service.addEntry(EcgEntry(
        dateTime: dateTime,
        result: result,
        color: color,
        content: content,
        txtPath: file.path,
        jsonPath: File(jsonFilePath).existsSync() ? jsonFilePath : '',
        deviceType: Platform.isIOS ? 'iOS' : 'Android',
      ));

      loadedCount++;
    } catch (e) {
      debugPrint("❌ 파일 처리 실패: $fileName / $e");
    }
  }

  debugPrint("✅ 로딩 완료: $loadedCount개 ECG 파일 불러옴");
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Xalute',
      theme: ThemeData(
        fontFamily: "Pretendard",
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: _AuthCheckScreen(),
      routes: {
        '/ecg': (context) => const EcgPage(),
        '/login': (context) => const LoginPage(),
        '/settings': (context) => const SettingPage(),
        '/survey' : (context) => const SurveyPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/ecgDetail') {
          final entry = settings.arguments as EcgEntry;
          return MaterialPageRoute(
            builder: (context) => EcgDetailPage(
              txtPath: entry.txtPath,
              jsonPath: entry.jsonPath,
              timestamp: entry.dateTime,
              result: entry.result,
              deviceType: entry.deviceType,
              ),
          );
        }

        return null;
      },
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('ko', 'KR'),
      ],
    );
  }
}


class _AuthCheckScreen extends StatelessWidget {
  // 세션과 설문 상태를 동시에 체크하는 함수
  Future<Map<String, dynamic>> _checkAllStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    // 1. 로그인 여부 (기존 hasSession 로직)
    bool hasSession = user != null;

    // 2. 설문 완료 여부 (SharedPref에서 가져옴, 없으면 false)
    bool isSurveyCompleted = prefs.getBool('isSurveyCompleted') ?? false;

    return {
      'hasSession': hasSession,
      'isSurveyCompleted': isSurveyCompleted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkAllStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final bool hasSession = snapshot.data?['hasSession'] ?? false;
        final bool isSurveyCompleted = snapshot.data?['isSurveyCompleted'] ?? false;

        // [체크 1] 로그인 안 됨 -> 로그인 페이지
        //if (!hasSession) {
        //  return const LoginPage();
        //}

        // [체크 2] 로그인은 됐는데 설문은 안 함 -> 설문 페이지
        //if (!isSurveyCompleted) {
        //  return SurveyPage();
        //}

        // [체크 3] 둘 다 완료 -> 메인 페이지
        return const MainTabPage();
      },
    );
  }
}