import Flutter
import UIKit
import GoogleMaps
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyBS1D-EnW4WfEmXCSklbsJQCYqMliqzBoE")
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let notifications = FlutterMethodChannel(
        name: "musicians/notifications", binaryMessenger: controller.binaryMessenger
      )
      notifications.setMethodCallHandler { call, result in
        guard call.method == "clearDelivered" else {
          result(FlutterMethodNotImplemented)
          return
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(nil)
      }
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
