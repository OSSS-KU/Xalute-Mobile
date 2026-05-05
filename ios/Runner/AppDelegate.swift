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
          flutterResult(FlutterError(code: "UNSUPPORTED", message: "ECG requires iOS 14.0 or later", details: nil))
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
        DispatchQueue.main.async { flutterResult([]) }
        return
      }
      // 병렬 처리 대신 순차 처리로 메모리 안전성 확보
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

    // HKElectrocardiogramQuery는 메인 스레드에서 생성·실행
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
