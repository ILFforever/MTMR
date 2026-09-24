//
//  SettingsWindow.swift
//  Stripe
//
//  The editor window's controller.
//

import SwiftUI

/// Owns the editor window. Closing it just hides it; the app keeps running.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    let document = PresetDocument(path: standardConfigPath)
    let session = EditorSession()
    private lazy var snapshots = ItemSnapshotModel(document: document)

    func show() {
        if window == nil {
            // Show the new items as soon as the bar has redrawn after a save.
            document.onSaved = { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.snapshots.refresh() }
            }
            let view = SettingsView(document: document, session: session, snapshots: snapshots)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "\(Brand.name) Settings"
            // A unified title bar that the SwiftUI header draws into.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // No NSToolbar: it would sit over the header and swallow its clicks.
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("StripeSettings")
            window.delegate = self
            if !window.setFrameUsingName("StripeSettings") { window.center() }
            self.window = window
        } else {
            document.load() // pick up edits made elsewhere while the window was closed
        }
        snapshots.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        document.flushSave()
        snapshots.stop()
    }
}
