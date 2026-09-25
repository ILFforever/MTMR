//
//  Theme.swift
//  Stripe
//
//  How Stripe draws what it draws itself. Two themes:
//
//  - Stripe: the current look.
//  - MTMR: the classic look, restoring how MTMR drew the things it had: a text
//    battery ("⚡️64%" with the time raised beside it), "⏳" placeholders while
//    widgets load, static play/pause and mute icons, and plain sliders.
//
//  Chosen per item ("theme": "mtmr"; Stripe when unset), in Settings on the
//  item's Style tab. Features new in Stripe (groups, popovers, the Battery
//  Overview…) look the same in both, and styles set on an item in the preset
//  always win over the theme.
//

import AppKit

struct Theme {
    enum Name: String, CaseIterable {
        case stripe, mtmr

        var title: String {
            switch self {
            case .stripe: return "Stripe"
            case .mtmr: return "MTMR"
            }
        }
    }

    let name: Name

    /// The battery as a drawn icon (Stripe) rather than text (MTMR).
    var drawnBattery = true
    /// Widgets stay hidden until their first value, then fade in (Stripe),
    /// rather than showing "⏳" meanwhile (MTMR).
    var fadeInFirstTitle = true
    /// Play/pause lights the half a tap will do (Stripe); MTMR's icon is static.
    var litPlayPause = true
    /// Mute's icon follows the volume (Stripe); MTMR's is a static mute icon.
    var liveMuteIcon = true
    /// Sliders sit on a panel with icons at each end (Stripe); MTMR's are plain.
    var sliderPanels = true

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
    static let stripe = Theme(
        name: .stripe,
        closeButton: CloseButton(
            background: NSColor(srgbRed: 0xC0 / 255, green: 0xC0 / 255, blue: 0xC0 / 255, alpha: 1),
            glyph: .black,
            diameter: 22,
            glyphSize: 10,
            gap: 20
        )
    )

    static let mtmr = Theme(name: .mtmr, drawnBattery: false, fadeInFirstTitle: false, litPlayPause: false,
                            liveMuteIcon: false, sliderPanels: false, closeButton: stripe.closeButton)

    static func named(_ name: Name) -> Theme {
        return name == .mtmr ? mtmr : stripe
    }

    /// The theme of the item being built (TouchBarController.createItem sets
    /// it around each item), else Stripe's. Items keep the one they were built
    /// with (CustomButtonTouchBarItem.theme).
    static var current: Theme {
        return building ?? stripe
    }

    static var building: Theme?
}
