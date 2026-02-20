import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let privacyChannel = "ren/privacy_protection"
  private let privacyOverlayTag = 774401
  private var privacyOverlayEnabled = false
  private var antiCaptureEnabled = false
  private var isAppInactive = false
  private var isScreenCaptured = false
  private var captureObserverInstalled = false

  private func currentKeyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func installCaptureObserverIfNeeded() {
    if captureObserverInstalled {
      return
    }
    captureObserverInstalled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
  }

  @objc private func handleScreenCaptureChanged() {
    isScreenCaptured = UIScreen.main.isCaptured
    refreshPrivacyOverlay()
  }

  private func refreshPrivacyOverlay() {
    let shouldShow =
      (privacyOverlayEnabled && isAppInactive) ||
      (antiCaptureEnabled && isScreenCaptured)
    if shouldShow {
      showPrivacyOverlay()
    } else {
      hidePrivacyOverlay()
    }
  }

  private func showPrivacyOverlay() {
    guard let window = currentKeyWindow() else { return }
    if window.viewWithTag(privacyOverlayTag) != nil { return }

    let overlay = UIView(frame: window.bounds)
    overlay.tag = privacyOverlayTag
    overlay.backgroundColor = UIColor.systemBackground
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(overlay)
  }

  private func hidePrivacyOverlay() {
    currentKeyWindow()?.viewWithTag(privacyOverlayTag)?.removeFromSuperview()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: privacyChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "deallocated", message: nil, details: nil))
          return
        }
        guard call.method == "configure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing args", details: nil))
          return
        }

        self.privacyOverlayEnabled = (args["iosPrivacyOverlay"] as? Bool) ?? false
        self.antiCaptureEnabled = (args["iosAntiCapture"] as? Bool) ?? false
        if self.antiCaptureEnabled {
          self.installCaptureObserverIfNeeded()
          self.isScreenCaptured = UIScreen.main.isCaptured
        } else {
          self.isScreenCaptured = false
        }
        self.refreshPrivacyOverlay()
        result(nil)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    isAppInactive = true
    refreshPrivacyOverlay()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    isAppInactive = false
    if antiCaptureEnabled {
      isScreenCaptured = UIScreen.main.isCaptured
    } else {
      isScreenCaptured = false
    }
    refreshPrivacyOverlay()
  }
}
