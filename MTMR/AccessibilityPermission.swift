//
//  AccessibilityPermission.swift
//  Stripe
//
//  Buttons that simulate keys (media keys, Esc, keyPress/hidKey actions) need
//  Accessibility permission. Stripe checks quietly at launch and only asks when
//  such a button is used without it, at most once per session, instead of
//  prompting on every launch.
//

import Cocoa

enum AccessibilityPermission {
    private static var askedThisSession = false

    static var isGranted: Bool {
        return AXIsProcessTrusted()
    }

    /// Shows the system prompt if permission is missing and we haven't asked yet.
    static func requestIfNeeded() {
        guard !isGranted, !askedThisSession else { return }
        askedThisSession = true
        request()
    }

    /// Always shows the system prompt (or does nothing if already granted).
    static func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as NSDictionary)
    }
}
