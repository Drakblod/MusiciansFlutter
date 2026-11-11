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
        switch call.method {
        case "clearDelivered":
          UNUserNotificationCenter.current().removeAllDeliveredNotifications()
          result(nil)
        case "getSoundProfile":
          let sounds = [
            "notification_gig_request_v2",
            "notification_gig_response_v2",
            "notification_event_rsvp_v2",
            "notification_gig_confirmed_v2"
          ]
          let ready = sounds.allSatisfy {
            Bundle.main.url(forResource: $0, withExtension: "wav") != nil
          }
          result(ready ? "ios-v2" : nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
