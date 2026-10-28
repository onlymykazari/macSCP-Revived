//
//  ExternalLaunchQueue.swift
//  macSCP
//
//  Buffers external launch requests between the AppDelegate (which receives
//  the macOS "open URL" event, possibly before any window exists) and the
//  main window's view model, which consumes them once it is ready.
//
//  Everything here is MainActor: the AppDelegate runs on the main thread and
//  the consumer is a MainActor view model, so there is no cross-thread access.
//

import Foundation

enum ExternalLaunchOutcome: Equatable {
    case request(ExternalLaunchRequest)
    case rejected(message: String, url: String)
}

@MainActor
final class ExternalLaunchQueue {
    static let shared = ExternalLaunchQueue()

    /// Posted after enqueueing while a main window is alive, so the window can
    /// consume the queue immediately instead of waiting for its next task.
    static let pokeNotification = Notification.Name("ExternalLaunchQueuePoke")

    /// Whether a main (connection list) window currently exists. Maintained by
    /// ConnectionListView's onAppear/onDisappear; read by the AppDelegate to
    /// decide whether it must reopen the main window after an external launch.
    static var mainWindowAlive = false

    private var pending: [ExternalLaunchOutcome] = []

    private init() {}

    func enqueue(_ url: URL) {
        switch ExternalLaunchRequest.parse(url) {
        case .success(let request):
            pending.append(.request(request))
        case .failure(let error):
            pending.append(.rejected(message: error.message, url: ExternalLaunchRequest.sanitized(url)))
        }
    }

    /// Returns and clears everything queued so far, in arrival order.
    func drain() -> [ExternalLaunchOutcome] {
        let outcomes = pending
        pending.removeAll()
        return outcomes
    }
}
