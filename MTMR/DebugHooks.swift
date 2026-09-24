//
//  DebugHooks.swift
//  Stripe
//
//  Lets a developer drive the bar without touching it (e.g. when working on a
//  headless Mac, paired with `screencapture -b` to see the result). Only active
//  when launched with STRIPE_DEBUG=1:
//
//    open --env STRIPE_DEBUG=1 build/Stripe.app
//    swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.ilfforever.stripe.debug"), object: "popover", deliverImmediately: true)'
//
//  Commands: "popover" (expand the first popover), "group" (open the first group),
//  "dismiss" (return to the main bar), "settings" (open the editor window),
//  "select N" (select the Nth top-level item in the editor), "tap NAME" (tap the
//  first item whose identifier contains NAME, e.g. "tap battery").
//

import Cocoa

enum DebugHooks {
    static let notification = Notification.Name("com.ilfforever.stripe.debug")

    static func installIfRequested() {
        guard ProcessInfo.processInfo.environment["STRIPE_DEBUG"] == "1" else { return }
        NSLog("Stripe debug hooks enabled")
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            handle(command: note.object as? String ?? "")
        }
    }

    private static func handle(command: String) {
        let items = TouchBarController.shared.items.values
        NSLog("Stripe debug command: \(command)")
        switch command {
        case "popover":
            (items.first { $0 is PopoverBarItem } as? PopoverBarItem)?.expand()
        case "group":
            (items.first { $0 is GroupBarItem } as? GroupBarItem)?.showPopover(nil)
        case "settings":
            SettingsWindowController.shared.show()
        case let select where select.hasPrefix("select "):
            // "select 3" selects the 4th top-level item in the editor.
            let editor = SettingsWindowController.shared
            if let index = Int(select.dropFirst(7)), editor.document.items.indices.contains(index) {
                editor.session.selection = editor.document.items[index].id
            }
        case let pane where pane.hasPrefix("pane "):
            // "pane outline" or "pane library" switches the editor's left pane.
            SettingsWindowController.shared.session.leftPane = String(pane.dropFirst(5))
        case let search where search.hasPrefix("search "):
            // "search vol" types into the editor's sidebar search.
            SettingsWindowController.shared.session.search = String(search.dropFirst(7))
        case let tap where tap.hasPrefix("tap "):
            // "tap battery" taps the first item whose identifier contains "battery".
            let name = tap.dropFirst(4).lowercased()
            let match = TouchBarController.shared.items
                .first { $0.key.rawValue.lowercased().contains(name) }?.value as? CustomButtonTouchBarItem
            match?.callActions(for: .singleTap)
        case "dismiss":
            for case let item as PopoverBarItem in items {
                item.collapse()
            }
            TouchBarController.shared.restoreMainBar()
        default:
            NSLog("Stripe debug: unknown command \(command)")
        }
    }
}
