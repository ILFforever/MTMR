//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

struct ItemAction {
    typealias TriggerClosure = (() -> Void)?
    
    let trigger: Action.Trigger
    let closure: TriggerClosure
    
    init(trigger: Action.Trigger, _ closure: TriggerClosure) {
        self.trigger = trigger
        self.closure = closure
    }
}

class CustomButtonTouchBarItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    
    var actions: [ItemAction] = [] {
        didSet {
            multiClick.isDoubleClickEnabled = actions.filter({ $0.trigger == .doubleTap }).count > 0
            multiClick.isTripleClickEnabled = actions.filter({ $0.trigger == .tripleTap }).count > 0
            longClick.isEnabled = actions.filter({ $0.trigger == .longTap }).count > 0
        }
    }
    var finishViewConfiguration: ()->() = {}
    
    private var button: NSButton!
    private var longClick: LongPressGestureRecognizer!
    private var multiClick: MultiClickGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, title: String) {
        attributedTitle = title.defaultTouchbarAttributedString

        super.init(identifier: identifier)
        button = CustomHeightButton(title: title, target: nil, action: nil)

        longClick = LongPressGestureRecognizer(target: self, action: #selector(handleGestureLong))
        longClick.isEnabled = false
        longClick.allowedTouchTypes = .direct
        longClick.delegate = self
        
        multiClick = MultiClickGestureRecognizer(
            target: self,
            action: #selector(handleGestureSingleTap),
            doubleAction: #selector(handleGestureDoubleTap),
            tripleAction: #selector(handleGestureTripleTap)
        )
        multiClick.allowedTouchTypes = .direct
        multiClick.delegate = self
        multiClick.isDoubleClickEnabled = false
        multiClick.isTripleClickEnabled = false

        reinstallButton()
        button.attributedTitle = displayedTitle
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isBordered: Bool = true {
        didSet {
            reinstallButton()
        }
    }

    /// Room kept for a multi-line title, so the key doesn't resize as its text changes.
    var minimumTitleWidth: CGFloat = 0 {
        didSet { (button as? CustomHeightButton)?.minimumTitleWidth = minimumTitleWidth }
    }

    var backgroundColor: NSColor? {
        didSet {
            reinstallButton()
        }
    }

    /// Extra space on each side of the content, for items whose content would
    /// otherwise sit tight against the key's edges (e.g. the battery).
    var contentPadding: CGFloat = 0 {
        didSet { reinstallButton() }
    }

    var style = ItemStyle() {
        didSet {
            if let symbolImage = style.symbolImage {
                image = symbolImage
            }
            reinstallButton()
            button.attributedTitle = displayedTitle
        }
    }

    /// The title as drawn: `attributedTitle` with the item's style applied.
    var displayedTitle: NSAttributedString {
        return style.apply(to: attributedTitle)
    }

    var title: String {
        get {
            return attributedTitle.string
        }
        set {
            attributedTitle = newValue.defaultTouchbarAttributedString
        }
    }

    var attributedTitle: NSAttributedString {
        didSet {
            button?.imagePosition = attributedTitle.length > 0 ? .imageLeading : .imageOnly
            button?.attributedTitle = displayedTitle
            if isAwaitingFirstTitle, attributedTitle.length > 0 { reveal() }
        }
    }

    /// True while hidden by `hideUntilFirstTitle`.
    private(set) var isAwaitingFirstTitle = false

    /// For items whose title comes from a script or a reading: stay invisible
    /// until the first title arrives, then fade in, instead of showing a
    /// placeholder. Fades in after two seconds regardless.
    func hideUntilFirstTitle() {
        isAwaitingFirstTitle = true
        button.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.reveal() }
    }

    private func reveal() {
        guard isAwaitingFirstTitle else { return }
        isAwaitingFirstTitle = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            button.animator().alphaValue = 1
        }
    }

    var image: NSImage? {
        didSet {
            button.image = image
        }
    }

    private func reinstallButton() {
        let title = button.attributedTitle
        let image = button.image
        let cell = CustomButtonCell(parentItem: self)
        button.cell = cell
        (button as? CustomHeightButton)?.horizontalPadding = max(style.cornerRadius != nil ? 10 : 0, contentPadding)
        button.wantsLayer = style.cornerRadius != nil
        button.layer?.cornerRadius = style.cornerRadius ?? 0
        button.layer?.backgroundColor = nil
        if let color = backgroundColor, let radius = style.cornerRadius {
            // Custom-radius background: draw it on the layer, not with a bezel.
            button.isBordered = false
            button.bezelStyle = .inline
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = radius
        } else if let color = backgroundColor {
            cell.isBordered = true
            button.bezelColor = color
            button.bezelStyle = .rounded
            cell.backgroundColor = color
        } else {
            button.isBordered = isBordered
            button.bezelStyle = isBordered ? .rounded : .inline
        }
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.attributedTitle = title
        button?.imagePosition = title.length > 0 ? .imageLeading : .imageOnly
        button.image = image
        view = button

        view.addGestureRecognizer(longClick)
        // view.addGestureRecognizer(singleClick)
        view.addGestureRecognizer(multiClick)
        finishViewConfiguration()
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer == multiClick && otherGestureRecognizer == longClick
            || gestureRecognizer == longClick && otherGestureRecognizer == multiClick // need it
        {
            return false
        }
        return true
    }
    
    func callActions(for trigger: Action.Trigger) {
        let itemActions = self.actions.filter { $0.trigger == trigger }
        for itemAction in itemActions {
            itemAction.closure?()
        }
    }
    
    @objc func handleGestureSingleTap() {
        callActions(for: .singleTap)
    }
    
    @objc func handleGestureDoubleTap() {
        callActions(for: .doubleTap)
    }
    
    @objc func handleGestureTripleTap() {
        callActions(for: .tripleTap)
    }

    @objc func handleGestureLong(gr: NSPressGestureRecognizer) {
        switch gr.state {
        case .possible: // tiny hack because we're calling action manually
            callActions(for: .longTap)
            break
        default:
            break
        }
    }
}

class CustomHeightButton: NSButton {
    /// Extra width on each side, so text isn't flush against a pill's edges.
    var horizontalPadding: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Side margin for multi-line titles; small text needs less room than a label.
    static let multilineInset: CGFloat = 4

    /// See CustomButtonTouchBarItem.minimumTitleWidth.
    var minimumTitleWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = 30
        let imageWidth = image.map { $0.size.width + 4 } ?? 0
        // NSButton measures a multi-line title as one long line; use the widest line.
        if attributedTitle.string.contains("\n") {
            let textWidth = ceil(attributedTitle.boundingRect(
                with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]).width)
            size.width = max(textWidth, minimumTitleWidth) + imageWidth + 2 * CustomHeightButton.multilineInset
        } else if minimumTitleWidth > 0 {
            // Holds the space before the first title arrives, too.
            size.width = max(size.width, minimumTitleWidth + imageWidth + 2 * CustomHeightButton.multilineInset)
        }
        size.width += horizontalPadding * 2
        return size
    }
}

class CustomButtonCell: NSButtonCell {
    weak var parentItem: CustomButtonTouchBarItem?

    init(parentItem: CustomButtonTouchBarItem) {
        super.init(textCell: "")
        self.parentItem = parentItem
    }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        if !isBordered {
            if flag {
                setAttributedTitle(attributedTitle, withColor: .lightGray)
            } else if let parentItem = self.parentItem {
                attributedTitle = parentItem.displayedTitle
            }
        }
    }
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return rect // need that so content may better fit in button with very limited width
    }

    /// NSButtonCell lays a title out as one line, so a second line would hang off
    /// the bottom of the key. Draw multi-line titles as a block centered in the key.
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        guard title.string.contains("\n") else {
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
        let size = title.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin]).size
        let bounds = controlView.bounds
        // With an icon, stay in the space beside it; otherwise use the whole key.
        let midX = image == nil ? bounds.midX : frame.midX
        let rect = NSRect(x: midX - ceil(size.width) / 2,
                          y: bounds.midY - ceil(size.height) / 2,
                          width: ceil(size.width), height: ceil(size.height))
        title.draw(with: rect, options: [.usesLineFragmentOrigin])
        return rect
    }

    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedTitle(_ title: NSAttributedString, withColor color: NSColor) {
        let attrTitle = NSMutableAttributedString(attributedString: title)
        attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
        attributedTitle = attrTitle
    }
}

// Thanks to https://stackoverflow.com/a/49843893
final class MultiClickGestureRecognizer: NSClickGestureRecognizer {

    private let _action: Selector
    private let _doubleAction: Selector
    private let _tripleAction: Selector
    private var _clickCount: Int = 0
    
    public var isDoubleClickEnabled = true
    public var isTripleClickEnabled = true

    override var action: Selector? {
        get {
            return nil /// prevent base class from performing any actions
        } set {
            if newValue != nil { // if they are trying to assign an actual action
                fatalError("Only use init(target:action:doubleAction) for assigning actions")
            }
        }
    }

    required init(target: AnyObject, action: Selector, doubleAction: Selector, tripleAction: Selector) {
        _action = action
        _doubleAction = doubleAction
        _tripleAction = tripleAction
        super.init(target: target, action: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(target:action:doubleAction:tripleAction) is only support atm")
    }
    
    override func touchesBegan(with event: NSEvent) {
        HapticFeedback.instance.tap(type: .click)
        super.touchesBegan(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        HapticFeedback.instance.tap(type: .back)
        super.touchesEnded(with: event)
        _clickCount += 1
        
        var delayThreshold: TimeInterval // fine tune this as needed
        
        guard isDoubleClickEnabled || isTripleClickEnabled else {
            _ = target?.perform(_action)
            return
        }
        
        if (isTripleClickEnabled) {
            delayThreshold = 0.4
            perform(#selector(_resetAndPerformActionIfNecessary), with: nil, afterDelay: delayThreshold)
            if _clickCount == 3 {
                _ = target?.perform(_tripleAction)
            }
        } else {
            delayThreshold = 0.3
            perform(#selector(_resetAndPerformActionIfNecessary), with: nil, afterDelay: delayThreshold)
            if _clickCount == 2 {
                _ = target?.perform(_doubleAction)
            }
        }
    }

    @objc private func _resetAndPerformActionIfNecessary() {
        if _clickCount == 1 {
            _ = target?.perform(_action)
        }
        if isTripleClickEnabled && _clickCount == 2 {
            _ = target?.perform(_doubleAction)
        }
        _clickCount = 0
    }
}

class LongPressGestureRecognizer: NSPressGestureRecognizer {
    var recognizeTimeout = 0.4
    private var timer: Timer?
    
    override func touchesBegan(with event: NSEvent) {
        timerInvalidate()
        
        let touches = event.touches(for: self.view!)
        if touches.count == 1 { // to prevent it for built-in two/three-finger gestures
            timer = Timer.scheduledTimer(timeInterval: recognizeTimeout, target: self, selector: #selector(self.onTimer), userInfo: nil, repeats: false)
        }
        
        super.touchesBegan(with: event)
    }
    
    override func touchesMoved(with event: NSEvent) {
        timerInvalidate() // to prevent it for built-in two/three-finger gestures
        super.touchesMoved(with: event)
    }
    
    override func touchesCancelled(with event: NSEvent) {
        timerInvalidate()
        super.touchesCancelled(with: event)
    }
    
    override func touchesEnded(with event: NSEvent) {
        timerInvalidate()
        super.touchesEnded(with: event)
    }
    
    private func timerInvalidate() {
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }
    
    @objc private func onTimer() {
        if let target = self.target, let action = self.action {
            target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
            HapticFeedback.instance.tap(type: .strong)
        }
    }
    
    deinit {
        timerInvalidate()
    }
}

extension String {
    var defaultTouchbarAttributedString: NSAttributedString {
        let attrTitle = NSMutableAttributedString(string: self, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15, weight: .regular), .baselineOffset: 1])
        attrTitle.setAlignment(.center, range: NSRange(location: 0, length: count))
        return attrTitle
    }
}
