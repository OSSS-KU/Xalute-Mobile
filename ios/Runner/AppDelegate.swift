import Flutter
import UIKit
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let healthStore = HKHealthStore()
  private var watchChannel: FlutterMethodChannel?
  private var observersSetUp = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return result
    }

    // ── ECG channel (existing) ──────────────────────────────────────
    let ecgChannel = FlutterMethodChannel(
      name: "com.example.health/ecg",
      binaryMessenger: controller.binaryMessenger
    )
    ecgChannel.setMethodCallHandler { [weak self] call, flutterResult in
      guard let self = self else { return }
      if call.method == "getECGData" {
        if #available(iOS 14.0, *) {
          self.fetchECGData(flutterResult: flutterResult)
        } else {
          flutterResult(FlutterError(code: "UNSUPPORTED", message: "ECG requires iOS 14.0 or later", details: nil))
        }
      } else {
        flutterResult(FlutterMethodNotImplemented)
      }
    }

    // ── Vital signs channel (same name as Android) ─────────────────
    let vitalChannel = FlutterMethodChannel(
      name: "com.example.xalute/watch",
      binaryMessenger: controller.binaryMessenger
    )
    self.watchChannel = vitalChannel
    vitalChannel.setMethodCallHandler { [weak self] call, flutterResult in
      guard let self = self else { return }
      if call.method == "fetchVitalSigns" {
        self.fetchVitalSigns(completion: flutterResult)
      } else {
        flutterResult(FlutterMethodNotImplemented)
      }
    }

    return result
  }

  // ─── Vital Signs ────────────────────────────────────────────────

  private func fetchVitalSigns(completion: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      completion(FlutterError(code: "UNAVAILABLE", message: "HealthKit을 사용할 수 없는 기기입니다", details: nil))
      return
    }

    var readTypes: Set<HKObjectType> = [
      HKQuantityType.quantityType(forIdentifier: .heartRate)!,
      HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
    ]
    if #available(iOS 16.0, *) {
      readTypes.insert(HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!)
    }

    healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
      guard let self = self else { return }
      guard success else {
        DispatchQueue.main.async {
          completion(FlutterError(code: "AUTH_FAILED", message: error?.localizedDescription ?? "HealthKit 권한 거부", details: nil))
        }
        return
      }
      if !self.observersSetUp {
        self.setupObservers()
        self.observersSetUp = true
      }
      self.queryVitalSigns { payload in
        DispatchQueue.main.async {
          if let payload = payload {
            completion(payload)
          } else {
            completion(FlutterError(code: "NO_DATA", message: "최근 24시간 내 바이탈 데이터가 없습니다", details: nil))
          }
        }
      }
    }
  }

  private func queryVitalSigns(completion: @escaping ([String: Any]?) -> Void) {
    let group = DispatchGroup()
    var hrSamples: [Int] = []
    var spo2Samples: [Int] = []
    var tempSamples: [Double] = []
    var latestDate: Date? = nil

    group.enter()
    querySamples(.heartRate, unit: HKUnit(from: "count/min"), limit: 20) { values, date in
      hrSamples = values.map { Int($0.rounded()) }
      if let d = date { latestDate = latestDate.map { max($0, d) } ?? d }
      group.leave()
    }

    group.enter()
    querySamples(.oxygenSaturation, unit: .percent(), limit: 20) { values, date in
      // HealthKit stores SpO2 as 0.0–1.0
      spo2Samples = values.map { Int(($0 * 100).rounded()) }
      if let d = date { latestDate = latestDate.map { max($0, d) } ?? d }
      group.leave()
    }

    if #available(iOS 16.0, *) {
      group.enter()
      querySamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), limit: 20) { values, date in
        tempSamples = values
        if let d = date { latestDate = latestDate.map { max($0, d) } ?? d }
        group.leave()
      }
    }

    group.notify(queue: .main) {
      guard !hrSamples.isEmpty || !spo2Samples.isEmpty || !tempSamples.isEmpty else {
        completion(nil)
        return
      }
      let ts = Int((latestDate ?? Date()).timeIntervalSince1970 * 1000)
      completion([
        "heart_rate_data": hrSamples,
        "spo2_data":       spo2Samples,
        "skin_temp_data":  tempSamples,
        "timestamp":       ts,
      ])
    }
  }

  private func querySamples(
    _ identifier: HKQuantityTypeIdentifier,
    unit: HKUnit,
    limit: Int,
    completion: @escaping ([Double], Date?) -> Void
  ) {
    guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
      completion([], nil)
      return
    }
    let since = Date().addingTimeInterval(-86400) // last 24h
    let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

    let query = HKSampleQuery(
      sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]
    ) { _, samples, _ in
      let typed = (samples as? [HKQuantitySample]) ?? []
      let values = typed.map { $0.quantity.doubleValue(for: unit) }
      completion(values, typed.first?.startDate)
    }
    healthStore.execute(query)
  }

  // Push new data to Flutter whenever HealthKit notifies of updates
  private func setupObservers() {
    let ids: [HKQuantityTypeIdentifier] = [.heartRate, .oxygenSaturation]
    for id in ids {
      guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
      let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
        guard error == nil else { return }
        self?.pushVitalSignsToFlutter()
      }
      healthStore.execute(query)
      // Hourly background delivery — enough for wellness/NEWS2 baseline
      healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }
  }

  private func pushVitalSignsToFlutter() {
    queryVitalSigns { [weak self] payload in
      guard let self = self, let payload = payload else { return }
      DispatchQueue.main.async {
        self.watchChannel?.invokeMethod("onVitalSignsReceived", arguments: payload)
      }
    }
  }

  // ─── ECG (existing, unchanged) ───────────────────────────────────

  @available(iOS 14.0, *)
  private func fetchECGData(flutterResult: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      flutterResult(FlutterError(code: "UNAVAILABLE", message: "HealthKit을 사용할 수 없는 기기입니다", details: nil))
      return
    }

    let ecgType = HKObjectType.electrocardiogramType()
    healthStore.requestAuthorization(toShare: nil, read: [ecgType]) { [weak self] success, error in
      guard let self = self else { return }
      guard success else {
        DispatchQueue.main.async {
          flutterResult(FlutterError(code: "AUTH_FAILED", message: error?.localizedDescription ?? "권한 거부", details: nil))
        }
        return
      }
      self.queryECGSamples(flutterResult: flutterResult)
    }
  }

  @available(iOS 14.0, *)
  private func queryECGSamples(flutterResult: @escaping FlutterResult) {
    let ecgType = HKObjectType.electrocardiogramType()
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

    let query = HKSampleQuery(sampleType: ecgType, predicate: nil, limit: 50, sortDescriptors: [sort]) { [weak self] _, samples, error in
      guard let self = self else { return }
      if let error = error {
        DispatchQueue.main.async {
          flutterResult(FlutterError(code: "QUERY_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      guard let ecgs = samples as? [HKElectrocardiogram], !ecgs.isEmpty else {
        DispatchQueue.main.async { flutterResult(NSArray()) }
        return
      }
      self.processECGsSequentially(ecgs: ecgs, index: 0, accumulated: [], flutterResult: flutterResult)
    }
    healthStore.execute(query)
  }

  @available(iOS 14.0, *)
  private func processECGsSequentially(
    ecgs: [HKElectrocardiogram],
    index: Int,
    accumulated: [[String: Any]],
    flutterResult: @escaping FlutterResult
  ) {
    guard index < ecgs.count else {
      DispatchQueue.main.async { flutterResult(accumulated) }
      return
    }

    let ecg = ecgs[index]
    let mVUnit = HKUnit(from: "mV")
    let formatter = ISO8601DateFormatter()

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      var samples = [Double]()

      let voltageQuery = HKElectrocardiogramQuery(ecg) { [weak self] _, voltageResult in
        guard let self = self else { return }
        switch voltageResult {
        case .measurement(let m):
          if let qty = m.quantity(for: .appleWatchSimilarToLeadI) {
            samples.append(qty.doubleValue(for: mVUnit))
          }
        case .done:
          let prediction: String
          switch ecg.classification {
          case .sinusRhythm: prediction = "정상"
          default:           prediction = "이상 소견 의심"
          }
          var next = accumulated
          next.append([
            "date": formatter.string(from: ecg.startDate),
            "prediction": prediction,
            "samples": samples,
            "samplingRate": 512,
          ])
          self.processECGsSequentially(ecgs: ecgs, index: index + 1, accumulated: next, flutterResult: flutterResult)
        case .error(let err):
          print("ECG voltage error at index \(index): \(err)")
          self.processECGsSequentially(ecgs: ecgs, index: index + 1, accumulated: accumulated, flutterResult: flutterResult)
        @unknown default:
          self.processECGsSequentially(ecgs: ecgs, index: index + 1, accumulated: accumulated, flutterResult: flutterResult)
        }
      }
      self.healthStore.execute(voltageQuery)
    }
  }
}
