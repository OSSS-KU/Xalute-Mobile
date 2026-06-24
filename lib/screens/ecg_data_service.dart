import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EcgEntry {
  final DateTime dateTime;
  final String result;
  final Color color;
  final String content;
  final String txtPath;
  final String jsonPath;
  final String deviceType;

  EcgEntry({
    required this.dateTime,
    required this.result,
    required this.color,
    required this.content,
    required this.txtPath,
    required this.jsonPath,
    required this.deviceType,
  });
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



class EcgDataService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.health/ecg');
  static const _baseUrl = 'http://35.216.60.242:9101';

  // ECG Founder 분석 결과 캐시 (txtPath → '정상'/'이상 소견 의심')
  final Map<String, String> _diagnosisResults = {};

  void updateDiagnosisResult(String txtPath, String result) {
    _diagnosisResults[txtPath] = result;
    notifyListeners();
  }

  String diagnosisResultFor(EcgEntry entry) =>
      _diagnosisResults[entry.txtPath] ?? entry.result;

  EcgDataService() {
    loadInitialData().then((_) => loadFromLocalFiles());
  }

  final List<EcgEntry> _entries = [];
  final userToken = _getIdToken();

  String _userName = 'User';
  String? _profileImagePath;
  bool _isLoading = true;
  bool _isSurveyCompleted = false;
  String? _birthDate;
  String? _phoneNumber;
  String? _address;
  String? _detailedAddress;
  String _totalScore = "50";

  String? get birthDate => _birthDate;
  List<EcgEntry> get entries => _entries;
  String get userName => _userName;
  String? get profileImagePath => _profileImagePath;
  bool get isLoading => _isLoading;
  bool get isSurveyCompleted => _isSurveyCompleted;
  String? get phoneNumber => _phoneNumber;
  String? get address => _address;
  String? get detailedAddress => _detailedAddress;
  String get totalScore => _totalScore;

  void setUserName(String name) {
    _userName = name.isEmpty ? "User" : name;
    _saveToPrefs('username', _userName);
    notifyListeners();
  }

  void setBirthDate(String? date) {
    _birthDate = date;
    if (date != null) {
      _saveToPrefs('birthDate', date);
    } else {
      _removeFromPrefs('birthDate');
    }
    notifyListeners();
  }

  void setPhoneNumber(String? number) {
    _phoneNumber = number;
    if (number != null) {
      _saveToPrefs('phoneNumber', number);
    } else {
      _removeFromPrefs('phoneNumber');
    }
    notifyListeners();
  }

  void setAddress(String? addr) {
    _address = addr;
    if (addr != null) {
      _saveToPrefs('address', addr);
    } else {
      _removeFromPrefs('address');
    }
    notifyListeners();
  }

  void setDetailedAddress(String? dAddr) {
    _detailedAddress = dAddr;
    if (dAddr != null) {
      _saveToPrefs('detailedAddress', dAddr);
    } else {
      _removeFromPrefs('detailedAddress');
    }
    notifyListeners();
  }


  void setProfileImagePath(String? path) {
    _profileImagePath = path;
    if (path != null) {
      _saveToPrefs('profileImagePath', path);
    } else {
      _removeFromPrefs('profileImagePath');
    }
    notifyListeners();
  }

  Future<void> completeSurvey() async { 
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isSurveyCompleted', true);
      print("설문 조사 완료");
      notifyListeners();
  }

  Future<void> updateHealthScores({
    required int smoking,
    required int drinking,
    required int activity,
    required double height,
    required double weight,
  }) async {
    // 1. BMI 계산 및 점수 환산
    double bmi = weight / ((height / 100) * (height / 100));
    int bScore;
    if (bmi < 18.5) {
      bScore = 10;
    } else if (bmi < 23.0) {
      bScore = 25;
    } else if (bmi < 25.0) {
      bScore = 15;
    } else if (bmi < 30.0) {
      bScore = 5;
    } else {
      bScore = 0;
    }

    // 2. 총합 계산 (int로 계산 후 String으로 변환)
    int calculatedTotal = smoking + drinking + activity + bScore;
    _totalScore = calculatedTotal.toString();

    // 3. SharedPreferences에 한 번에 저장 (await 사용)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('smokingScore', smoking);
    await prefs.setInt('drinkingScore', drinking);
    await prefs.setInt('bmiScore', bScore);
    await prefs.setInt('activityScore', activity);
    await prefs.setString('totalScore', _totalScore); // 서비스 변수 형식에 맞춰 String으로 저장

    // 4. 리스너들에게 알림 (UI 즉시 반영)
    notifyListeners();

    print("건강 점수 업데이트 완료: $_totalScore점");
  }
  
  Future<void> loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('username') ?? 'User';
    _profileImagePath = prefs.getString('profileImagePath');
    _birthDate = prefs.getString('birthDate');
    _phoneNumber = prefs.getString('phoneNumber');
    _address = prefs.getString('address');
    _detailedAddress = prefs.getString('detailedAddress');
    _totalScore = prefs.getString('totalScore') ?? "50";
    _isSurveyCompleted = prefs.getBool('isSurveyCompleted') ?? false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveToPrefs(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _removeFromPrefs(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Map<DateTime, List<String>> get statusMap {
    final map = <DateTime, List<String>>{};
    for (var e in _entries) {
      final dayKey = DateTime.utc(e.dateTime.year, e.dateTime.month, e.dateTime.day);
      map.putIfAbsent(dayKey, () => []);
      map[dayKey]!.add(e.result);
    }
    return map;
  }

  void addEntry(EcgEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  List<EcgEntry> entriesForDay(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return _entries.where((e) {
      final ed = DateTime.utc(e.dateTime.year, e.dateTime.month, e.dateTime.day);
      return ed == d;
    }).toList();
  }

  Future<void> fetchEcgData() async {
    try {
      final List<dynamic> raw = await _channel.invokeMethod('getECGData');
      if (raw.isEmpty) return;

      final dir = await getApplicationDocumentsDirectory();

      for (final item in raw) {
        final dateTime = DateTime.parse(item['date'] as String);
        final resultStr = item['prediction'] as String;
        final samples = (item['samples'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
        final samplingRate = (item['samplingRate'] as num?)?.toInt() ?? 512;

        final timestamp = dateTime.millisecondsSinceEpoch;
        final resultKey = resultStr == 'Normal' ? 'normal' : 'abnormal';
        final txtPath = '${dir.path}/ecg_${timestamp}_$resultKey.txt';
        final jsonPath = '${dir.path}/ecg_${timestamp}_$resultKey.json';

        // 중복 방지: 이미 저장된 파일이면 스킵
        if (File(txtPath).existsSync()) continue;

        // Android watch 포맷과 동일하게 저장: "(voltage, timeInSeconds) ..."
        // HealthKit 전압은 mV 단위 — Android watch 데이터와 스케일 차이가 있을 수 있으므로
        // API 응답이 Android와 다르게 보일 수 있음
        final buffer = StringBuffer();
        for (int i = 0; i < samples.length; i++) {
          if (i > 0) buffer.write(' ');
          buffer.write('(${samples[i]}, ${i / samplingRate})');
        }
        await File(txtPath).writeAsString(buffer.toString());
        // HealthKit에는 r_peaks/distance 정보가 없으므로 빈 JSON
        await File(jsonPath).writeAsString('{}');

        final color = resultStr == 'Abnormality suspected' ? const Color(0xFFFB755B) : Colors.grey[700]!;
        _entries.add(EcgEntry(
          dateTime: dateTime,
          result: resultStr,
          content: buffer.toString(),
          color: color,
          txtPath: txtPath,
          jsonPath: jsonPath,
          deviceType: 'Apple Watch',
        ));
      }
      notifyListeners();
    } on PlatformException catch (e) {
      throw 'HealthKit request failed: ${e.message}';
    }
  }

  Future<void> loadFromLocalFiles() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = docDir;
    if (!dir.existsSync()) return;

    final files = dir.listSync();

    for (var file in files) {
      if (file is File && file.path.endsWith('.txt')) {
        final jsonPath = file.path.replaceAll('.txt', '.json');
        final jsonFile = File(jsonPath);
        if (!jsonFile.existsSync()) continue;

        final fileName = file.uri.pathSegments.last;
        final parts = fileName.split('_');
        if (parts.length < 3) continue;

        final timestampStr = parts[1];
        final resultStr = parts[2].replaceAll('.txt', '');

        final timestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(timestampStr));
        final result = resultStr == 'normal' ? 'Normal'
            : resultStr == 'abnormal' ? 'Abnormality suspected'
            : 'Analyzing';
        final color = resultStr == 'normal' ? Colors.grey[700]!
            : resultStr == 'abnormal' ? const Color(0xFFFB755B)
            : Colors.grey;
        final txtContent = await file.readAsString();

        final entry = EcgEntry(
          dateTime: timestamp,
          result: result,
          color: color,
          content: txtContent,
          txtPath: file.path,
          jsonPath: jsonPath,
          deviceType: Platform.isIOS ? 'iOS' : 'Android',
        );

        _entries.add(entry);
      }
    }
    notifyListeners();
  }

  Future<void> fetchFromServer() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    final response = await http.post(
      Uri.parse('$_baseUrl/query/ecgData'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'page': 1,
        'limit': 100,
        'uid': {'eq': user.uid},
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('❌ ECG 서버 조회 실패: ${response.statusCode}');
      return;
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    final dir = await getApplicationDocumentsDirectory();

    for (final item in list) {
      final createdAt = DateTime.parse(item['createdAt'] as String).toLocal();
      final abnormal = (item['abnormal'] as num?)?.toInt() ?? -1;
      final insertId = item['insertId'] as String? ?? item['id'] as String? ?? '';

      final resultKey = abnormal == 0 ? 'normal' : abnormal == 1 ? 'abnormal' : 'unknown';
      final result = abnormal == 0 ? 'Normal' : abnormal == 1 ? 'Abnormality suspected' : 'Analyzing';
      final color = abnormal == 0 ? Colors.grey[700]!
          : abnormal == 1 ? const Color(0xFFFB755B)
          : Colors.grey;

      final timestampStr = DateFormat('yyyyMMddHHmmss').format(createdAt);
      final txtPath = '${dir.path}/ecg_${timestampStr}_$resultKey.txt';
      final jsonPath = '${dir.path}/ecg_${timestampStr}_$resultKey.json';

      // 이미 로컬 파일로 로드된 항목이면 스킵
      final alreadyLoaded = _entries.any((e) {
        final diff = e.dateTime.difference(createdAt).abs();
        return diff.inSeconds < 60;
      });
      if (alreadyLoaded) continue;

      // data 필드: 배열 / JSON 문자열 / GCS URL 세 가지 케이스 처리
      final rawDataRaw = item['data'];
      List<dynamic>? rawData;
      if (rawDataRaw is List) {
        rawData = rawDataRaw;
      } else if (rawDataRaw is String) {
        if (rawDataRaw.startsWith('http')) {
          try {
            final gcsRes = await http.get(Uri.parse(rawDataRaw));
            if (gcsRes.statusCode == 200) {
              rawData = jsonDecode(gcsRes.body) as List<dynamic>;
            }
          } catch (e) {
            debugPrint('⚠️ GCS 데이터 다운로드 실패: $e');
          }
        } else {
          try {
            rawData = jsonDecode(rawDataRaw) as List<dynamic>;
          } catch (_) {}
        }
      }
      String content = '';
      if (rawData != null && rawData.isNotEmpty) {
        final buffer = StringBuffer();
        final firstTs = (rawData[0] as List<dynamic>)[1] as num;
        final isUnixMs = firstTs > 1e12;
        final isUnixSec = !isUnixMs && firstTs > 1e9;
        for (int i = 0; i < rawData.length; i++) {
          if (i > 0) buffer.write(' ');
          final point = rawData[i] as List<dynamic>;
          final ts = (point[1] as num);
          final double timeSeconds;
          if (isUnixMs) {
            timeSeconds = (ts - firstTs) / 1000.0;
          } else if (isUnixSec) {
            timeSeconds = (ts - firstTs).toDouble();
          } else {
            timeSeconds = ts.toDouble();
          }
          buffer.write('(${point[0]}, $timeSeconds)');
        }
        content = buffer.toString();
        if (!File(txtPath).existsSync()) {
          await File(txtPath).writeAsString(content);
          await File(jsonPath).writeAsString('{}');
        }
      }

      _entries.add(EcgEntry(
        dateTime: createdAt,
        result: result,
        color: color,
        content: content,
        txtPath: File(txtPath).existsSync() ? txtPath : '',
        jsonPath: File(jsonPath).existsSync() ? jsonPath : '',
        deviceType: 'Server',
      ));

      debugPrint('✅ 서버 ECG 항목 추가: $insertId ($createdAt)');
    }

    _entries.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    notifyListeners();
  }

  Future<void> saveToServer(String fileContent, String resultKey, int timestampMs) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    // "(voltage, time) ..." 포맷 파싱
    final regex = RegExp(r'\(([^,]+),\s*([^)]+)\)');
    final matches = regex.allMatches(fileContent);
    final dataPoints = matches.map((m) => [
      double.tryParse(m.group(1)!.trim()) ?? 0.0,
      double.tryParse(m.group(2)!.trim()) ?? 0.0,
    ]).toList();

    if (dataPoints.isEmpty) return;

    final effectiveDateTime = DateTime.fromMillisecondsSinceEpoch(timestampMs).toUtc();

    final body = jsonEncode({
      'entry': [
        {
          'resource': {
            'effectiveDateTime': effectiveDateTime.toIso8601String(),
            'component': [
              {
                'valueSampledData': {
                  'origin': {'value': 0},
                  'dimension': 1,
                  'period': 2,
                  'data': dataPoints,
                }
              }
            ]
          }
        }
      ]
    });

    final response = await http.post(
      Uri.parse('$_baseUrl/mutation/addEcgData'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    debugPrint(response.statusCode == 200 || response.statusCode == 201
        ? '✅ ECG 서버 저장 완료'
        : '❌ ECG 서버 저장 실패: ${response.statusCode}');
  }
}
