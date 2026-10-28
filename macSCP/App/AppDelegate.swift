//
//  AppDelegate.swift
//  macSCP
//
//  Receives macOS application events that the SwiftUI scene lifecycle cannot
//  handle reliably, currently: the "open URL" Apple event for the macscp://
//  scheme. Cold launches deliver the event before any scene exists, so
//  onOpenURL cannot be used.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            logInfo("ExternalLaunch: received URL \(ExternalLaunchRequest.sanitized(url))", category: .app)
            ExternalLaunchQueue.shared.enqueue(url)
        }

        if ExternalLaunchQueue.mainWindowAlive {
            // A main window can consume the queue right away.
            NotificationCenter.default.post(name: ExternalLaunchQueue.pokeNotification, object: nil)
        } else {
            reopenMainWindow()
        }
    }

    /// When the app runs with no main window, macOS delivers the URL event but
    /// SwiftUI does not recreate the default WindowGroup window on its own.
    /// `newWindowForTab` is the established way to make SwiftUI open the first
    /// declared WindowGroup (our main connection list). If the selector ever
    /// stops working, the request simply stays queued and is consumed the next
    /// time a main window appears — nothing is lost.
    private func reopenMainWindow() {
        logInfo("ExternalLaunch: no main window alive, reopening it", category: .app)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
    }
}
