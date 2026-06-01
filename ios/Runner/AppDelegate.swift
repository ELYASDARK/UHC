import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "uhc/notification_settings",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "openNotificationSettings" {
          let settingsUrlString: String
          if #available(iOS 16.0, *) {
            settingsUrlString = UIApplication.openNotificationSettingsURLString
          } else {
            settingsUrlString = UIApplication.openSettingsURLString
          }

          if let url = URL(string: settingsUrlString),
             UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            result(nil)
          } else {
            result(FlutterError(
              code: "settings_unavailable",
              message: "Unable to open app settings.",
              details: nil
            ))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
