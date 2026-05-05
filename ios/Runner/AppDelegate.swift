import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
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

    // HealthKit 임시 제거 — dyld 크래시 원인 격리용
    ecgChannel.setMethodCallHandler { _, flutterResult in
      flutterResult(NSArray())
    }

    return result
  }
}
