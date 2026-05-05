import Flutter
import UIKit
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let healthStore = HKHealthStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // super를 먼저 호출해 window/rootViewController가 초기화된 뒤에 채널 설정
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return result
    }

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
          flutterResult(FlutterError(
            code: "UNSUPPORTED",
            message: "ECG requires iOS 14.0 or later",
            details: nil
          ))
        }
      } else {
        flutterResult(FlutterMethodNotImplemented)
      }
    }

    return result
  }

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
          flutterResult(FlutterError(
            code: "AUTH_FAILED",
            message: error?.localizedDescription ?? "HealthKit 접근 권한이 거부되었습니다",
            details: nil
          ))
        }
        return
      }
      self.queryECGSamples(flutterResult: flutterResult)
    }
  }

  @available(iOS 14.0, *)
  private func queryECGSamples(flutterResult: @escaping FlutterResult) {
    let ecgType = HKObjectType.electrocardiogramType()
    let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

    let sampleQuery = HKSampleQuery(
      sampleType: ecgType,
      predicate: nil,
      limit: 50,
      sortDescriptors: [sortDescriptor]
    ) { [weak self] _, samples, error in
      guard let self = self else { return }
      if let error = error {
        DispatchQueue.main.async {
          flutterResult(FlutterError(code: "QUERY_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      guard let ecgs = samples as? [HKElectrocardiogram], !ecgs.isEmpty else {
        DispatchQueue.main.async { flutterResult([]) }
        return
      }
      self.fetchVoltageSamples(ecgs: ecgs, flutterResult: flutterResult)
    }
    healthStore.execute(sampleQuery)
  }

  @available(iOS 14.0, *)
  private func fetchVoltageSamples(ecgs: [HKElectrocardiogram], flutterResult: @escaping FlutterResult) {
    var results: [[String: Any]] = []
    let group = DispatchGroup()
    let lock = NSLock()
    let dateFormatter = ISO8601DateFormatter()
    let mVUnit = HKUnit(from: "mV")

    for ecg in ecgs {
      group.enter()

      // 각 ECG마다 독립적인 배열 — 클로저가 자신의 배열만 접근하므로 락 불필요
      var voltageSamples = [Double]()

      let voltageQuery = HKElectrocardiogramQuery(ecg) { _, voltageResult in
        switch voltageResult {
        case .measurement(let measurement):
          if let qty = measurement.quantity(for: .appleWatchSimilarToLeadI) {
            voltageSamples.append(qty.doubleValue(for: mVUnit))
          }
        case .done:
          let prediction: String
          switch ecg.classification {
          case .sinusRhythm: prediction = "정상"
          default:           prediction = "이상 소견 의심"
          }
          let entry: [String: Any] = [
            "date": dateFormatter.string(from: ecg.startDate),
            "prediction": prediction,
            "samples": voltageSamples,
            "samplingRate": 512,
          ]
          lock.lock()
          results.append(entry)
          lock.unlock()
          group.leave()
        case .error(let err):
          print("ECG voltage query error: \(err)")
          group.leave()
        @unknown default:
          group.leave()
        }
      }
      healthStore.execute(voltageQuery)
    }

    group.notify(queue: .main) {
      flutterResult(results)
    }
  }
}
