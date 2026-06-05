import Foundation
import UserNotifications

/// Manages macOS system notifications for incoming permission requests.
/// Posts a banner when a new request arrives while the tray is closed,
/// and handles Allow / Open actions from the notification.
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    private static let categoryIdentifier = "PERMISSION_REQUEST"
    private static let allowActionIdentifier = "ALLOW"
    private static let openActionIdentifier = "OPEN"

    /// Called when the user taps "Allow" on a notification banner.
    /// Receives the `requestId`.
    var onAllowAction: ((String) -> Void)?

    /// Called when the user taps "Open Vibe Island" on a notification banner.
    var onOpenTrayAction: (() -> Void)?

    /// Closure that returns `true` when the tray is currently open.
    /// Set by the app delegate at launch.
    var isTrayOpen: (() -> Bool)?

    /// Registry used to look up agent display labels.
    weak var agentRegistry: AgentRegistry?

    /// Active re-notification timers keyed by requestId.
    private var renotifyTimers: [String: Timer] = [:]
    private let lock = NSLock()

    /// Pending request metadata for re-notification.
    private var pendingRequests: [String: PermissionRequest] = [:]

    private override init() {
        super.init()
        registerCategory()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Request notification authorization. Call once at app launch.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("AgentVibeIsland: Notification auth error: \(error.localizedDescription)")
            }
            NSLog("AgentVibeIsland: Notification permission \(granted ? "granted" : "denied")")
        }
    }

    // MARK: - Post / Cancel

    /// Post a system notification for a permission request.
    /// Only posts if the tray is currently closed.
    func postIfTrayIsClosed(for request: PermissionRequest) {
        if isTrayOpen?() == true { return }
        postNotification(for: request)
        startRenotifyTimer(for: request)
    }

    /// Post a notification unconditionally.
    private func postNotification(for request: PermissionRequest) {
        let content = UNMutableNotificationContent()
        let label = agentRegistry?.state(for: request.agent)?.agent.agentLabel ?? request.agent.capitalized
        content.title = "\(label) is waiting"
        content.body = "\(request.actionLabel) · \(request.scope)"
        content.sound = .none
        content.categoryIdentifier = Self.categoryIdentifier

        let req = UNNotificationRequest(identifier: request.requestId,
                                         content: content,
                                         trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                NSLog("AgentVibeIsland: Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    /// Cancel a notification for a resolved request and stop its re-notification timer.
    func cancelNotification(requestId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
        stopRenotifyTimer(requestId: requestId)
    }

    // MARK: - Re-notification timer

    private func startRenotifyTimer(for request: PermissionRequest) {
        lock.lock()
        pendingRequests[request.requestId] = request
        lock.unlock()

        // If a timer already exists for this request, don't duplicate
        lock.lock()
        let existing = renotifyTimers[request.requestId]
        lock.unlock()
        guard existing == nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                let req = self.pendingRequests[request.requestId]
                self.lock.unlock()

                guard let req = req else { return }
                // Only re-notify if tray is still closed
                if self.isTrayOpen?() != true {
                    self.postNotification(for: req)
                }
            }
            self.lock.lock()
            self.renotifyTimers[request.requestId] = timer
            self.lock.unlock()
        }
    }

    private func stopRenotifyTimer(requestId: String) {
        lock.lock()
        let timer = renotifyTimers.removeValue(forKey: requestId)
        pendingRequests.removeValue(forKey: requestId)
        lock.unlock()

        DispatchQueue.main.async {
            timer?.invalidate()
        }
    }

    // MARK: - Category registration

    private func registerCategory() {
        let allowAction = UNNotificationAction(
            identifier: Self.allowActionIdentifier,
            title: "Allow",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "Open Vibe Island",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [allowAction, openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is in the foreground.
    /// Suppress display if tray is already open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if isTrayOpen?() == true {
            completionHandler([])
        } else {
            completionHandler([.banner])
        }
    }

    /// Called when the user interacts with a notification action.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestId = response.notification.request.identifier

        switch response.actionIdentifier {
        case Self.allowActionIdentifier:
            DispatchQueue.main.async { [weak self] in
                self?.onAllowAction?(requestId)
            }
            cancelNotification(requestId: requestId)

        case Self.openActionIdentifier:
            DispatchQueue.main.async { [weak self] in
                self?.onOpenTrayAction?()
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body itself — open tray
            DispatchQueue.main.async { [weak self] in
                self?.onOpenTrayAction?()
            }

        default:
            break
        }

        completionHandler()
    }
}
