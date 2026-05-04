import 'package:flutter/material.dart';

class VitalSignsService extends ChangeNotifier {
  List<int> spo2Data = [];
  List<int> heartRateData = [];
  List<double> skinTempData = [];
  DateTime? lastUpdated;

  bool get hasData =>
      spo2Data.isNotEmpty ||
      heartRateData.isNotEmpty ||
      skinTempData.isNotEmpty;

  void updateData({
    required List<int> spo2,
    required List<int> heartRate,
    required List<double> skinTemp,
    required DateTime timestamp,
  }) {
    spo2Data = spo2;
    heartRateData = heartRate;
    skinTempData = skinTemp;
    lastUpdated = timestamp;
    notifyListeners();
  }

  // 정수 리스트 통계
  double _avg(List<int> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;
  int _min(List<int> list) => list.isEmpty ? 0 : list.reduce((a, b) => a < b ? a : b);
  int _max(List<int> list) => list.isEmpty ? 0 : list.reduce((a, b) => a > b ? a : b);

  // double 리스트 통계
  double _avgD(List<double> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;
  double _minD(List<double> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a < b ? a : b);
  double _maxD(List<double> list) =>
      list.isEmpty ? 0 : list.reduce((a, b) => a > b ? a : b);

  int get spo2Last => spo2Data.isEmpty ? 0 : spo2Data.last;
  double get spo2Avg => _avg(spo2Data);
  int get spo2Min => _min(spo2Data);
  int get spo2Max => _max(spo2Data);

  int get hrLast => heartRateData.isEmpty ? 0 : heartRateData.last;
  double get hrAvg => _avg(heartRateData);
  int get hrMin => _min(heartRateData);
  int get hrMax => _max(heartRateData);

  double get tempLast => skinTempData.isEmpty ? 0 : skinTempData.last;
  double get tempAvg => _avgD(skinTempData);
  double get tempMin => _minD(skinTempData);
  double get tempMax => _maxD(skinTempData);
}
