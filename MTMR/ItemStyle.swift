//
//  ItemStyle.swift
//  Stripe
//
//  Per-item visual styling shared by every button-based item: font, text color,
//  SF Symbol icons and rounded "pill" backgrounds. Parsed from flat JSON keys:
//
//    "symbol": "cpu", "iconColor": "#34C759",
//    "fontSize": 13, "fontWeight": "semibold", "textColor": "orange",
//    "monospacedDigits": true, "cornerRadius": 8   // or "style": "pill"
//

import AppKit

struct ItemStyle {
    var fontSize: CGFloat?
    var fontWeight: NSFont.Weight?
    var textColor: NSColor?
    var monospacedDigits = false
    var cornerRadius: CGFloat?
    var symbol: String?
    var iconColor: NSColor?

    static let barHeight: CGFloat = 30
    static let defaultFontSize: CGFloat = 15

    var affectsText: Bool {
        return fontSize != nil || fontWeight != nil || textColor != nil || monospacedDigits
    }

    /// Restyles a title while keeping colors that widgets or ANSI output set
    /// deliberately: only the default white text takes `textColor`.
    func apply(to title: NSAttributedString) -> NSAttributedString {
        guard affectsText, title.length > 0 else { return title }
        let result = NSMutableAttributedString(attributedString: title)
        let whole = NSRange(location: 0, length: result.length)

        result.enumerateAttribute(.font, in: whole) { value, range, _ in
            let current = value as? NSFont ?? NSFont.systemFont(ofSize: ItemStyle.defaultFontSize)
            let size = fontSize ?? current.pointSize
            let weight = fontWeight ?? current.weight
            let font = monospacedDigits
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
            result.addAttribute(.font, value: font, range: range)
        }

        if let textColor = textColor {
            result.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
                let current = (value as? NSColor)?.usingColorSpace(.deviceRGB)
                if current == nil || current == NSColor.white.usingColorSpace(.deviceRGB) {
                    result.addAttribute(.foregroundColor, value: textColor, range: range)
                }
            }
        }
        return result
    }

    /// The SF Symbol icon, sized to sit alongside the title text.
    var symbolImage: NSImage? {
        guard let symbol = symbol,
              let base = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) else { return nil }
        var config = NSImage.SymbolConfiguration(pointSize: (fontSize ?? ItemStyle.defaultFontSize) + 1,
                                                 weight: fontWeight ?? .regular)
        if let iconColor = iconColor {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        }
        let image = base.withSymbolConfiguration(config)
        image?.isTemplate = iconColor == nil // template images render white on the Touch Bar
        return image
    }
}

extension ItemStyle: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fontSize, fontWeight, textColor, monospacedDigits, cornerRadius, symbol, iconColor, style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        fontWeight = try c.decodeIfPresent(String.self, forKey: .fontWeight).flatMap(NSFont.Weight.init(name:))
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)?.namedOrHexColor
        monospacedDigits = try c.decodeIfPresent(Bool.self, forKey: .monospacedDigits) ?? false
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        iconColor = try c.decodeIfPresent(String.self, forKey: .iconColor)?.namedOrHexColor
        if try c.decodeIfPresent(String.self, forKey: .style) == "pill", cornerRadius == nil {
            cornerRadius = ItemStyle.barHeight / 2
        }
    }
}

extension NSFont {
    var weight: NSFont.Weight {
        let traits = fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return (traits?[.weight] as? CGFloat).map { NSFont.Weight($0) } ?? .regular
    }
}

extension NSFont.Weight {
    init?(name: String) {
        switch name.lowercased() {
        case "ultralight": self = .ultraLight
        case "thin": self = .thin
        case "light": self = .light
        case "regular": self = .regular
        case "medium": self = .medium
        case "semibold": self = .semibold
        case "bold": self = .bold
        case "heavy": self = .heavy
        case "black": self = .black
        default: return nil
        }
    }
}

extension String {
    /// Accepts "#RRGGBB"-style hex or a macOS system color name ("green", "orange", "gray"…).
    var namedOrHexColor: NSColor? {
        let named: [String: NSColor] = [
            "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow,
            "green": .systemGreen, "mint": .systemMint, "teal": .systemTeal, "cyan": .systemCyan,
            "blue": .systemBlue, "indigo": .systemIndigo, "purple": .systemPurple,
            "pink": .systemPink, "brown": .systemBrown, "gray": .systemGray, "grey": .systemGray,
            "white": .white, "black": .black,
        ]
        return named[lowercased()] ?? hexColor
    }
}
