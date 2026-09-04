import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow, UNUserNotificationCenterDelegate {
  private let notificationCategoryIdentifier = "SEIL_TERMINAL_ATTENTION"
  private var terminalNotificationsChannel: FlutterMethodChannel?
  private var pendingLaunchTarget: [String: String]?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    minSize = NSSize(width: 420, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)
    configurePlatformChannels(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func configurePlatformChannels(binaryMessenger: FlutterBinaryMessenger) {
    configureExternalFileChannel(binaryMessenger: binaryMessenger)
    configureTerminalNotificationChannel(binaryMessenger: binaryMessenger)
  }

  private func configureExternalFileChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.zarathu.seil/external_file",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard ["open", "reveal"].contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(
          code: "invalid_path",
          message: "File path is empty.",
          details: nil
        ))
        return
      }
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(
          code: "missing_file",
          message: "File does not exist.",
          details: nil
        ))
        return
      }

      let fileURL = URL(fileURLWithPath: path)
      if call.method == "reveal" {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        result(nil)
        return
      }

      let opened = NSWorkspace.shared.open(fileURL)
      if opened {
        result(nil)
      } else {
        result(FlutterError(
          code: "no_viewer",
          message: "No application can open this file.",
          details: nil
        ))
      }
    }
  }

  private func configureTerminalNotificationChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "com.zarathu.seil/terminal_notifications",
      binaryMessenger: binaryMessenger
    )
    terminalNotificationsChannel = channel

    let one = UNNotificationAction(
      identifier: "one",
      title: "1",
      options: [.foreground]
    )
    let two = UNNotificationAction(
      identifier: "two",
      title: "2",
      options: [.foreground]
    )
    let escape = UNNotificationAction(
      identifier: "escape",
      title: "Esc",
      options: [.foreground]
    )
    let category = UNNotificationCategory(
      identifier: notificationCategoryIdentifier,
      actions: [one, two, escape],
      intentIdentifiers: [],
      options: []
    )
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.setNotificationCategories([category])
    notificationCenter.delegate = self

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "window_unavailable",
          message: "The SEIL window is unavailable.",
          details: nil
        ))
        return
      }

      switch call.method {
      case "requestPermission":
        notificationCenter.requestAuthorization(options: [.alert, .sound]) {
          granted, _ in
          DispatchQueue.main.async {
            result(granted)
          }
        }

      case "consumeLaunchTarget":
        result(self.consumeLaunchTarget())

      case "show":
        self.showTerminalNotification(
          arguments: call.arguments,
          center: notificationCenter,
          result: result
        )

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func showTerminalNotification(
    arguments: Any?,
    center: UNUserNotificationCenter,
    result: @escaping FlutterResult
  ) {
    guard
      let values = arguments as? [String: Any],
      let connectionFingerprint = values["connectionFingerprint"] as? String,
      !connectionFingerprint.isEmpty,
      let tmuxSessionName = values["tmuxSessionName"] as? String,
      !tmuxSessionName.isEmpty
    else {
      result(FlutterError(
        code: "invalid_target",
        message: "The notification target is missing.",
        details: nil
      ))
      return
    }

    let notificationID = (values["notificationId"] as? NSNumber)?.intValue ?? 4201
    let title = values["title"] as? String ?? "SEIL"
    let body = values["body"] as? String ?? title

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = notificationCategoryIdentifier
    content.userInfo = [
      "connectionFingerprint": connectionFingerprint,
      "tmuxSessionName": tmuxSessionName,
    ]

    let request = UNNotificationRequest(
      identifier: "seil-terminal-\(notificationID)",
      content: content,
      trigger: nil
    )
    center.add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "notification_failed",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private func consumeLaunchTarget() -> [String: String]? {
    let target = pendingLaunchTarget
    pendingLaunchTarget = nil
    return target
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }

    if response.actionIdentifier == UNNotificationDismissActionIdentifier {
      return
    }

    let userInfo = response.notification.request.content.userInfo
    guard
      let connectionFingerprint = userInfo["connectionFingerprint"] as? String,
      !connectionFingerprint.isEmpty,
      let tmuxSessionName = userInfo["tmuxSessionName"] as? String,
      !tmuxSessionName.isEmpty
    else {
      return
    }

    var target = [
      "connectionFingerprint": connectionFingerprint,
      "tmuxSessionName": tmuxSessionName,
    ]
    if ["one", "two", "escape"].contains(response.actionIdentifier) {
      target["action"] = response.actionIdentifier
    }

    pendingLaunchTarget = target
    terminalNotificationsChannel?.invokeMethod(
      "notificationTapped",
      arguments: target
    )
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(self)
  }
}
