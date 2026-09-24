//
//  Theme.swift
//  Stripe
//
//  Colors and sizes for Stripe's own controls, gathered here so themes can be
//  added later by providing another Theme value. Items styled from the preset
//  (background, textColor…) aren't affected; this is for built-in chrome.
//

import AppKit

struct Theme {
    struct CloseButton {
        var background: NSColor
        var glyph: NSColor
        var diameter: CGFloat
        var glyphSize: CGFloat
        /// Extra space between the close button and the controls it closes.
        var gap: CGFloat
    }

    var closeButton: CloseButton

    /// Matches macOS's own Touch Bar controls (measured from the system volume
    /// control): a small light-gray circle with a bold black ✕.
    static let standard = Theme(
        closeButton: CloseButton(
            background: NSColor(srgbRed: 0xC0 / 255, green: 0xC0 / 255, blue: 0xC0 / 255, alpha: 1),
            glyph: .black,
            diameter: 22,
            glyphSize: 10,
            gap: 20
        )
    )

    static var current = standard
}
