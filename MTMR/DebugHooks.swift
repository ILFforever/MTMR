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
//  "dismiss" (return to the main bar).
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
