import BackgroundTasks
import Flutter
import UIKit
import UserNotifications

/// Local reminder alerts (MOBILE.md §3). Each notification's identifier is the
/// reminder id, so an APNs push with the same collapse id replaces it rather
/// than showing twice. Dart (`features/notifications/reminder_alerts.dart`)
/// decides what to schedule; this file only talks to iOS.
///
/// Done / Snooze 1h and background refresh run as Dart "jobs": in the app's
/// engine when it is attached, otherwise in a headless engine started here, so
/// they work with the app closed. iOS is told the action finished only after
/// the job does.
final class ReminderNotifications: NSObject, UNUserNotificationCenterDelegate {
  static let shared = ReminderNotifications()
  static let refreshTaskId = "com.ezyreminder.app.refresh"
  private static let channelName = "ezyreminder/notifications"
  private static let jobLibrary = "package:ezyreminder/features/notifications/notification_jobs.dart"
  private static let jobEntrypoint = "notificationJobsMain"
  private static let jobTimeout: TimeInterval = 25

  private let center = UNUserNotificationCenter.current()
  private var mainChannel: FlutterMethodChannel?
  private var mainAttached = false
  private var headless: FlutterEngine?
  private var headlessChannel: FlutterMethodChannel?
  private var headlessAttached = false
  private var headlessWaiting: [(args: [String: Any], done: () -> Void)] = []
  private var headlessRunning = 0
  private var pendingOpen: String?

  /// Call from `didFinishLaunching`: iOS delivers lock-screen actions to the
  /// delegate set before launch ends, and refresh tasks must register then too.
  func launch() {
    center.delegate = self
    let done = UNNotificationAction(identifier: "DONE", title: "Done", options: [])
    let snooze = UNNotificationAction(identifier: "SNOOZE_1H", title: "Snooze 1h", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "REMINDER", actions: [done, snooze], intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "REMINDER_OPEN", actions: [snooze], intentIdentifiers: [], options: []),
    ])
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
      self.refresh(task)
    }
    scheduleRefresh()
    NotificationCenter.default.addObserver(
      self, selector: #selector(scheduleRefresh),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  func attachMain(_ messenger: FlutterBinaryMessenger) {
    mainChannel = install(on: messenger, main: true)
  }

  // MARK: Dart → iOS

  private func install(on messenger: FlutterBinaryMessenger, main: Bool) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "attach":
        if main { self.mainAttached = true } else { self.headlessAttached = true; self.drainHeadless() }
        result(nil)
        if main, self.pendingOpen != nil { channel.invokeMethod("opened", arguments: nil) }
      case "detach":
        if main { self.mainAttached = false }
        result(nil)
      case "permission":
        self.center.getNotificationSettings { settings in
          let status: String
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral: status = "allowed"
          case .denied: status = "denied"
          default: status = "notDetermined"
          }
          DispatchQueue.main.async { result(status) }
        }
      case "request":
        self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "replace":
        self.replace(Self.alerts(args["alerts"]), open: Set(args["open"] as? [String] ?? [])) { result(nil) }
      case "add":
        self.add(Self.alerts(args["alerts"])) { result(nil) }
      case "test":
        let alert: [String: Any] = [
          "id": "ezy-test", "title": "ezyReminder", "body": "Reminders will appear like this.",
          "fireAt": Date().addingTimeInterval(5).timeIntervalSince1970 * 1000,
          "thread": "test", "category": "", "kind": "test",
        ]
        self.add([alert]) { result(nil) }
      case "openSettings":
        let url: String
        if #available(iOS 16.0, *) {
          url = UIApplication.openNotificationSettingsURLString
        } else {
          url = UIApplication.openSettingsURLString
        }
        if let link = URL(string: url) { UIApplication.shared.open(link) }
        result(nil)
      case "takeOpened":
        result(self.pendingOpen)
        self.pendingOpen = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return channel
  }

  private static func alerts(_ value: Any?) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
  }

  private static func isOurs(_ request: UNNotificationRequest) -> Bool {
    request.content.userInfo["ezy"] as? String == "reminder"
  }

  private static func signature(_ alert: [String: Any]) -> String {
    ["fireAt", "title", "body", "thread", "category"]
      .map { "\(alert[$0] ?? "")" }.joined(separator: "\u{1F}")
  }

  /// Makes `alerts` the whole pending set; unchanged ones are left alone.
  /// Delivered alerts for reminders that are no longer open are cleared.
  private func replace(_ alerts: [[String: Any]], open: Set<String>, done: @escaping () -> Void) {
    center.getPendingNotificationRequests { pending in
      let wanted = Dictionary(alerts.compactMap { a in (a["id"] as? String).map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
      let current = Dictionary(pending.filter(Self.isOurs).map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
      let stale = current.keys.filter { wanted[$0] == nil }
      self.center.removePendingNotificationRequests(withIdentifiers: stale)
      let changed = wanted.values.filter { a in
        current[a["id"] as? String ?? ""]?.content.userInfo["sig"] as? String != Self.signature(a)
      }
      self.center.getDeliveredNotifications { delivered in
        let finished = delivered.map(\.request).filter { Self.isOurs($0) && !open.contains($0.identifier) }
        self.center.removeDeliveredNotifications(withIdentifiers: finished.map(\.identifier))
        self.add(Array(changed), done: done)
      }
    }
  }

  private func add(_ alerts: [[String: Any]], done: @escaping () -> Void) {
    let group = DispatchGroup()
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    for alert in alerts {
      guard let id = alert["id"] as? String, let ms = alert["fireAt"] as? Double ?? (alert["fireAt"] as? NSNumber)?.doubleValue
      else { continue }
      let content = UNMutableNotificationContent()
      content.title = alert["title"] as? String ?? ""
      content.body = alert["body"] as? String ?? ""
      content.sound = .default
      content.threadIdentifier = alert["thread"] as? String ?? ""
      content.categoryIdentifier = alert["category"] as? String ?? ""
      var info = alert
      info["ezy"] = alert["kind"] as? String ?? "reminder"
      info["sig"] = Self.signature(alert)
      content.userInfo = info
      // An absolute instant: travelling or changing the phone's zone can't move it.
      var when = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: ms / 1000))
      when.timeZone = utc.timeZone
      let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
      group.enter()
      center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in group.leave() }
    }
    group.notify(queue: .main, execute: done)
  }

  // MARK: iOS → Dart

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let request = response.notification.request
    guard Self.isOurs(request) else { return completionHandler() }
    switch response.actionIdentifier {
    case UNNotificationDefaultActionIdentifier:
      pendingOpen = request.identifier
      if mainAttached { mainChannel?.invokeMethod("opened", arguments: nil) }
      completionHandler()
    case "DONE", "SNOOZE_1H":
      var alert = request.content.userInfo as? [String: Any] ?? [:]
      alert["id"] = request.identifier
      run(["kind": "action", "action": response.actionIdentifier, "id": request.identifier, "alert": alert],
          done: completionHandler)
    default:
      completionHandler()
    }
  }

  @objc func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  private func refresh(_ task: BGTask) {
    scheduleRefresh()
    var finished = false
    let finish: (Bool) -> Void = { success in
      DispatchQueue.main.async {
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
      }
    }
    task.expirationHandler = { finish(false) }
    DispatchQueue.main.async { self.run(["kind": "sync"]) { finish(true) } }
  }

  /// Runs a job in the app's engine if attached, else headless. `done` is
  /// called exactly once, at the latest after `jobTimeout`.
  private func run(_ args: [String: Any], done: @escaping () -> Void) {
    var called = false
    let once = {
      guard !called else { return }
      called = true
      done()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.jobTimeout, execute: once)
    guard mainAttached, let channel = mainChannel else { return runHeadless(args, done: once) }
    channel.invokeMethod("job", arguments: args) { result in
      if (result as? NSObject) == FlutterMethodNotImplemented {
        self.runHeadless(args, done: once)
      } else {
        once()
      }
    }
  }

  private func runHeadless(_ args: [String: Any], done: @escaping () -> Void) {
    headlessWaiting.append((args, done))
    if headless == nil {
      let engine = FlutterEngine(name: "ezy-notification-jobs", project: nil, allowHeadlessExecution: true)
      engine.run(withEntrypoint: Self.jobEntrypoint, libraryURI: Self.jobLibrary)
      GeneratedPluginRegistrant.register(with: engine)
      headlessChannel = install(on: engine.binaryMessenger, main: false)
      headless = engine
    }
    drainHeadless()
  }

  private func drainHeadless() {
    guard headlessAttached, let channel = headlessChannel else { return }
    let jobs = headlessWaiting
    headlessWaiting.removeAll()
    for job in jobs {
      headlessRunning += 1
      channel.invokeMethod("job", arguments: job.args) { _ in
        job.done()
        self.headlessRunning -= 1
        self.stopHeadlessWhenIdle()
      }
    }
  }

  private func stopHeadlessWhenIdle() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
      guard self.headlessRunning == 0, self.headlessWaiting.isEmpty, let engine = self.headless else { return }
      self.headlessChannel?.setMethodCallHandler(nil)
      self.headlessChannel = nil
      self.headlessAttached = false
      self.headless = nil
      engine.destroyContext()
    }
  }
}
