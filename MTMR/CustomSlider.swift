//
//  CustomSlider.swift
//  MTMR
//
//  Created by Anton Palgunov on 15/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class CustomSliderCell: NSSliderCell {
    var knobImage: NSImage!
    private var _currentKnobRect: NSRect!
    private var _barRect: NSRect!

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init() {
        super.init()
    }

    init(knob: NSImage?) {
        knobImage = knob
        super.init()
    }

    override func drawKnob(_ knobRect: NSRect) {
        if knobImage == nil {
            super.drawKnob(knobRect)
            return
        }

        _currentKnobRect = knobRect
        drawBar(inside: _barRect, flipped: true)

        let x = (knobRect.origin.x * (_barRect.size.width - (knobImage.size.width - knobRect.size.width)) / _barRect.size.width) + 1
        let y = knobRect.origin.y + 3

        knobImage.draw(
            at: NSPoint(x: x, y: y),
            from: NSZeroRect,
            operation: NSCompositingOperation.sourceOver,
            fraction: 1
        )
    }

    override func drawBar(inside aRect: NSRect, flipped _: Bool) {
        _barRect = aRect

        let barRadius = CGFloat(2)

        var bgRect = aRect
        bgRect.size.height = CGFloat(4)

        let bg = NSBezierPath(roundedRect: bgRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.lightGray.setFill()
        bg.fill()

        var activeRect = bgRect

        activeRect.size.width = CGFloat((Double(bgRect.size.width) / (maxValue - minValue)) * doubleValue)
        let active = NSBezierPath(roundedRect: activeRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.darkGray.setFill()
        active.fill()
    }
}

/// Draws a slider like Apple's Control Strip ones: a thin rounded track that is
/// white up to the value, and a round white knob.
class StripSliderCell: NSSliderCell {
    static let knobDiameter: CGFloat = 22
    static let trackHeight: CGFloat = 4

    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let d = StripSliderCell.knobDiameter
        let fraction = maxValue > minValue ? CGFloat((doubleValue - minValue) / (maxValue - minValue)) : 0
        let x = bar.minX + fraction * (bar.width - d)
        return NSRect(x: x, y: bar.midY - d / 2, width: d, height: d)
    }

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        let h = StripSliderCell.trackHeight
        let track = NSRect(x: aRect.minX, y: aRect.midY - h / 2, width: aRect.width, height: h)
        NSColor(white: 1, alpha: 0.3).setFill()
        NSBezierPath(roundedRect: track, xRadius: h / 2, yRadius: h / 2).fill()

        var filled = track
        filled.size.width = knobRect(flipped: flipped).midX - track.minX
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: h / 2, yRadius: h / 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let knob = NSBezierPath(ovalIn: knobRect.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSColor.white.setFill()
        knob.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSSlider {
    /// Wraps the slider in a row with small SF Symbols at each end, like the
    /// Control Strip's volume and brightness sliders.
    func withEndIcons(min minSymbol: String, max maxSymbol: String) -> NSView {
        func icon(_ name: String) -> NSImageView {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) ?? NSImage())
            view.contentTintColor = NSColor(white: 1, alpha: 0.7)
            view.setContentHuggingPriority(.required, for: .horizontal)
            return view
        }
        let row = NSStackView(views: [icon(minSymbol), self, icon(maxSymbol)])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        return row
    }
}

class CustomSlider: NSSlider {
    var currentValue: CGFloat = 0

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        if (cell?.isKind(of: CustomSliderCell.self)) == false {
            let cell: CustomSliderCell = CustomSliderCell()
            self.cell = cell
        }
    }

    convenience init(knob: NSImage) {
        self.init()
        cell = CustomSliderCell(knob: knob)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Without a custom knob image, use the Control Strip look.
        cell = StripSliderCell()
    }

    func knobImage() -> NSImage {
        let cell = self.cell as! CustomSliderCell
        return cell.knobImage
    }

    func setKnobImage(image: NSImage) {
        let cell = self.cell as! CustomSliderCell
        cell.knobImage = image
    }
}
