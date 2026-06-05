import Foundation

protocol RequestQueueObserver: AnyObject {
    func requestQueueDidChange(_ queue: RequestQueue)
}

final class RequestQueue {
    private var pendingRequests: [PermissionRequest] = []
    private var completionHandlers: [String: (PermissionDecision) -> Void] = [:]
    private let lock = NSLock()

    private struct WeakObserver {
        weak var value: RequestQueueObserver?
    }
    private var observers: [WeakObserver] = []

    // MARK: - Public API

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.count
    }

    var requests: [PermissionRequest] {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests
    }

    func addObserver(_ observer: RequestQueueObserver) {
        lock.lock()
        observers.append(WeakObserver(value: observer))
        lock.unlock()
    }

    func removeObserver(_ observer: RequestQueueObserver) {
        lock.lock()
        observers.removeAll { $0.value === observer }
        lock.unlock()
    }

    /// Enqueue a permission request. The completion handler is called when the request is resolved.
    func enqueue(_ request: PermissionRequest, completion: @escaping (PermissionDecision) -> Void) {
        lock.lock()
        pendingRequests.append(request)
        completionHandlers[request.requestId] = completion
        lock.unlock()

        NotificationManager.shared.postIfTrayIsClosed(for: request)
        notifyObservers()
    }

    /// Resolve a pending request with a decision. Calls the completion handler and removes from queue.
    func resolve(requestId: String, decision: PermissionDecision) {
        lock.lock()
        let handler = completionHandlers.removeValue(forKey: requestId)
        pendingRequests.removeAll { $0.requestId == requestId }
        lock.unlock()

        NotificationManager.shared.cancelNotification(requestId: requestId)
        handler?(decision)
        notifyObservers()
    }

    // MARK: - Private

    private func notifyObservers() {
        lock.lock()
        let active = observers.compactMap { $0.value }
        lock.unlock()

        for observer in active {
            observer.requestQueueDidChange(self)
        }
    }
}
