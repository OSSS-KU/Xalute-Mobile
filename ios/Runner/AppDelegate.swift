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

    let controller = window?.rootViewController as! FlutterViewController
    let ecgChannel = FlutterMethodChannel(
      name: "com.example.health/ecg",
      binaryMessenger: controller.binaryMessenger
    )

    ecgChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "getECGData":
        if #available(iOS 14.0, *) {
          self.fetchECGData(flutterResult: result)
        } else {
          result(FlutterError(
            code: "UNSUPPORTED",
            message: "ECG requires iOS 14.0 or later",
            details: nil
          ))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @available(iOS 14.0, *)
  private func fetchECGData(flutterResult: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      flutterResult(FlutterError(code: "UNAVAILABLE", message: "HealthKit을 사용할 수 없는 기기입니다", details: nil))
      return
    }

    let ecgType = HKObjectType.electrocardiogramType()
    healthStore.requestAuthorization(toShare: nil, read: [ecgType]) { [weak self] success, error in
      guard let self = self, success else {
        flutterResult(FlutterError(
          code: "AUTH_FAILED",
          message: error?.localizedDescription ?? "HealthKit 접근 권한이 거부되었습니다",
          details: nil
        ))
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
      guard let ecgs = samples as? [HKElectrocardiogram], error == nil else {
        flutterResult(FlutterError(
          code: "QUERY_FAILED",
          message: error?.localizedDescription ?? "ECG 데이터를 가져오지 못했습니다",
          details: nil
        ))
        return
      }
      if ecgs.isEmpty {
        flutterResult([])
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
    // millivolt — matches the amplitude scale expected by the ECG analysis API
    let mVUnit = HKUnit(from: "mV")

    for ecg in ecgs {
      group.enter()
      var voltageSamples: [Double] = []

      let voltageQuery = HKElectrocardiogramQuery(ecg) { _, result in
        switch result {
        case .measurement(let measurement):
          if let voltage = measurement.quantity(for: .appleWatchSimilarToLeadI) {
            voltageSamples.append(voltage.doubleValue(for: mVUnit))
          }
        case .done:
          let prediction: String
          switch ecg.classification {
          case .sinusRhythm:
            prediction = "정상"
          default:
            // atrialFibrillation, inconclusive variants → 이상 소견 의심
            prediction = "이상 소견 의심"
          }
          lock.lock()
          results.append([
            "date": dateFormatter.string(from: ecg.startDate),
            "prediction": prediction,
            "samples": voltageSamples,
            "samplingRate": 512,
          ])
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
