import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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

class EcgDataService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.health/ecg');

  EcgDataService() {
    loadInitialData().then((_) => loadFromLocalFiles());
  }

  final List<EcgEntry> _entries = [];

  String _userName = 'User';
  String? _profileImagePath;
  bool _isLoading = true;
  String? _birthDate;
  String? _phoneNumber;
  String? _address;

  String? get birthDate => _birthDate;
  List<EcgEntry> get entries => _entries;
  String get userName => _userName;
  String? get profileImagePath => _profileImagePath;
  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;
  String? get address => _address;


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

  void setProfileImagePath(String? path) {
    _profileImagePath = path;
    if (path != null) {
      _saveToPrefs('profileImagePath', path);
    } else {
      _removeFromPrefs('profileImagePath');
    }
    notifyListeners();
  }

  Future<void> loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('username') ?? 'User';
    _profileImagePath = prefs.getString('profileImagePath');
    _birthDate = prefs.getString('birthDate');
    _phoneNumber = prefs.getString('phoneNumber');
    _address = prefs.getString('address');
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

      for (var item in raw) {
        final dateTime = DateTime.parse(item['date'] as String);
        final resultStr = item['prediction'] as String;
        final color = resultStr.contains('이상') ? const Color(0xFFFB755B) : Colors.grey[700]!;
        _entries.add(EcgEntry(
          dateTime: dateTime,
          result: resultStr,
          content: '',
          color: color,
          txtPath: '',
          jsonPath: '',
          deviceType: Platform.isIOS ? 'iOS' : 'Android',
        ));
      }
      notifyListeners();
    } on PlatformException catch (e) {
      throw 'HealthKit 요청 실패: ${e.message}';
    }
  }

  Future<void> loadFromLocalFiles() async {
    final dir = Directory('/data/user/0/com.example.xalute/app_flutter');
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
        final result = resultStr == 'abnormal' ? '이상 소견 의심' : '정상';
        final color = result == '이상 소견 의심' ? const Color(0xFFFB755B) : Colors.grey[700]!;
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
}
