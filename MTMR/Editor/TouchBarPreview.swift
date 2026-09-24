//
//  TouchBarPreview.swift
//  Stripe
//
//  Shows a live screenshot of the actual Touch Bar in the editor, so edits can
//  be checked even when the Mac is used over Screen Sharing and the bar itself
//  is out of sight. Uses `screencapture -b`, which captures only the Touch Bar.
//

import SwiftUI

final class TouchBarPreviewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var unavailable = false

    private var timer: Timer?
    private var capturing = false
    private let file = NSTemporaryDirectory() + "stripe-touchbar-preview.png"

    func start() {
        guard timer == nil else { return }
        capture()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.capture() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func capture() {
        guard !capturing else { return }
        capturing = true
        let file = self.file
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-b", "-x", "-t", "png", file]
            try? task.run()
            task.waitUntilExit()
            let image = NSImage(contentsOfFile: file)
            try? FileManager.default.removeItem(atPath: file)
            DispatchQueue.main.async {
                self.capturing = false
                self.unavailable = image == nil
                if let image = image { self.image = image }
            }
        }
    }
}

struct TouchBarPreviewView: View {
    @ObservedObject var model: TouchBarPreviewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black)
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 14)
            } else {
                Text(model.unavailable
                     ? "Touch Bar preview unavailable. Allow Stripe under Privacy & Security → Screen Recording."
                     : "Loading preview…")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(height: 44)
        .help("Live view of your Touch Bar")
    }
}

/// Owns the editor window. Closing it just hides it; the app keeps running.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    let document = PresetDocument(path: standardConfigPath)
    let session = EditorSession()
    private let preview = TouchBarPreviewModel()

    func show() {
        if window == nil {
            // Refresh the preview as soon as the bar has redrawn after a save.
            document.onSaved = { [weak preview] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { preview?.capture() }
            }
            let view = SettingsView(document: document, session: session, preview: preview)
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
        preview.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        document.flushSave()
        preview.stop()
    }
}
