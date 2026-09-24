//
//  PopoverBarItem.swift
//  Stripe
//
//  A collapsible item, like the volume and brightness buttons in Apple's Control
//  Strip: a compact button that expands into a sub-bar with a close button, and
//  optionally supports press-and-hold, where holding the button and sliding
//  sideways adjusts the first child (e.g. a volume slider) without lifting.
//
//    {
//      "type": "popover", "symbol": "speaker.wave.2.fill",
//      "items": [ { "type": "volume" }, { "type": "mute" } ],
//      "pressAndHold": true,   // hold + slide adjusts the first item
//      "autoClose": 4          // seconds of inactivity before collapsing (optional)
//    }
//
//  The expanded controls open on the same side as the button (a right-aligned
//  button expands at the right, with ✕ at the far right where the finger already
//  is), and tapping the empty rest of the bar closes them.
//
//  Apple's NSPopoverTouchBarItem can't open from a system-modal bar like ours, and
//  only one system-modal bar shows at a time, so the sub-bar takes over the main bar.
//  The button is "expanded" while the main bar shows this item's children.
//

import Cocoa

/// A child item whose value press-and-hold sliding can adjust.
protocol SlidableItem: AnyObject {
    /// 0...1
    var sliderValue: Double { get set }
}

class PopoverBarItem: CustomButtonTouchBarItem, NSTouchBarDelegate {
    private let autoClose: TimeInterval?
    private let align: Align
    private let expandedIdentifier = NSTouchBarItem.Identifier("com.ilfforever.stripe.popover.expanded." + UUID().uuidString)
    private var childIdentifiers: [NSTouchBarItem.Identifier] = []
    private var childDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    private var childItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    private let closeIdentifier = NSTouchBarItem.Identifier("com.ilfforever.stripe.popover.close." + UUID().uuidString)
    private var autoCloseTimer: Timer?

    init(identifier: NSTouchBarItem.Identifier, items: [BarItemDefinition], pressAndHold: Bool, autoClose: TimeInterval?, align: Align) {
        self.autoClose = autoClose
        self.align = align
        super.init(identifier: identifier, title: "")

        for definition in items {
            let id = NSTouchBarItem.Identifier(definition.type.identifierBase + UUID().uuidString)
            childIdentifiers.append(id)
            childDefinitions[id] = definition
        }

        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.expand() })

        if pressAndHold {
            let slide = HoldSlideGestureRecognizer(target: self, action: #selector(handleHoldSlide(_:)))
            slide.allowedTouchTypes = .direct
            // The button view is rebuilt whenever styling changes; re-attach each time.
            finishViewConfiguration = { [weak self] in self?.view.addGestureRecognizer(slide) }
            finishViewConfiguration()
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Expand / collapse

    private(set) var isExpanded = false

    @objc func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        TouchBarController.shared.showSubBar(identifiers: [expandedIdentifier], delegate: self)
        scheduleAutoClose()
    }

    @objc func collapse() {
        autoCloseTimer?.invalidate()
        guard isExpanded else { return }
        isExpanded = false
        TouchBarController.shared.restoreMainBar()
    }

    /// The whole expanded bar as one item (so it can span the full width, like
    /// the main bar): controls anchored on the button's side, and the empty
    /// remainder a tap target that closes it.
    private func makeExpandedItem() -> NSTouchBarItem {
        let close = makeItem(closeIdentifier)?.view.map { [$0] } ?? []
        let children = childIdentifiers.compactMap { makeItem($0)?.view }
        let dismiss = { [weak self] in self?.collapse() ?? () }
        let views: [NSView]
        switch align {
        case .right: // ✕ at the far right, where the button was
            views = [DismissArea(onTap: dismiss)] + children + close
        case .left:
            views = close + children + [DismissArea(onTap: dismiss)]
        case .center:
            views = [DismissArea(onTap: dismiss)] + close + children + [DismissArea(onTap: dismiss)]
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        if align == .center, let first = views.first, let last = views.last {
            first.widthAnchor.constraint(equalTo: last.widthAnchor).isActive = true
        }
        let item = NSCustomTouchBarItem(identifier: expandedIdentifier)
        item.view = stack
        return item
    }

    private func scheduleAutoClose() {
        autoCloseTimer?.invalidate()
        guard let autoClose = autoClose else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: autoClose, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    // MARK: Press-and-hold sliding

    private var slideStartValue: Double = 0

    /// Points of horizontal travel that sweep the full 0...1 range.
    private let slideTravel: CGFloat = 250

    @objc private func handleHoldSlide(_ recognizer: HoldSlideGestureRecognizer) {
        guard let slidable = firstSlidableChild() else { return }
        switch recognizer.state {
        case .began:
            slideStartValue = slidable.sliderValue
            expand()
            autoCloseTimer?.invalidate()
            HapticFeedback.instance.tap(type: .strong)
        case .changed:
            slidable.sliderValue = slideStartValue + Double(recognizer.translation / slideTravel)
        case .ended:
            collapse()
        case .cancelled, .failed:
            NSLog("Stripe: press-and-hold slide was cancelled (state \(recognizer.state.rawValue))")
            collapse()
        default:
            break
        }
    }

    private func firstSlidableChild() -> SlidableItem? {
        guard let first = childIdentifiers.first else { return nil }
        return makeChild(first) as? SlidableItem
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        return identifier == expandedIdentifier ? makeExpandedItem() : makeItem(identifier)
    }

    private var closeItem: NSTouchBarItem?

    private func makeItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == closeIdentifier {
            if let close = closeItem { return close }
            // A gray rounded key, like the close button on Apple's expanded controls.
            let close = CustomButtonTouchBarItem(identifier: identifier, title: "")
            close.style = ItemStyle(fontWeight: .semibold, cornerRadius: 8, symbol: "xmark")
            close.backgroundColor = NSColor(white: 1, alpha: 0.2)
            close.setWidth(value: 64)
            close.actions = [ItemAction(trigger: .singleTap) { [weak self] in self?.collapse() }]
            closeItem = close
            return close
        }
        return makeChild(identifier)
    }

    private func makeChild(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let item = childItems[identifier] {
            return item
        }
        guard let definition = childDefinitions[identifier],
              let item = TouchBarController.shared.createItem(forIdentifier: identifier, definition: definition) else { return nil }
        // Any interaction inside the expanded bar postpones auto-close.
        if let button = item as? CustomButtonTouchBarItem {
            button.actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.scheduleAutoClose() })
        }
        childItems[identifier] = item
        return item
    }
}

/// Recognizes a press held briefly without moving, then reports horizontal
/// travel until the finger lifts. Quick taps fail it, so they still reach the
/// button's own tap handling.
class HoldSlideGestureRecognizer: NSGestureRecognizer {
    var holdDuration: TimeInterval = 0.25
    private(set) var translation: CGFloat = 0
    private var startX: CGFloat = 0
    private var holdTimer: Timer?

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        guard let view = view, let touch = event.touches(matching: .began, in: view).first else { return }
        startX = touch.location(in: view).x
        translation = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.state = .began
        }
    }

    override func touchesMoved(with event: NSEvent) {
        super.touchesMoved(with: event)
        guard let view = view, let touch = event.touches(matching: .moved, in: view).first else { return }
        translation = touch.location(in: view).x - startX
        if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        holdTimer?.invalidate()
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(with event: NSEvent) {
        super.touchesCancelled(with: event)
        holdTimer?.invalidate()
        state = .cancelled
    }

    override func reset() {
        super.reset()
        holdTimer?.invalidate()
        translation = 0
    }
}

/// Fills the unused part of an expanded bar; tapping it closes the popover.
/// It has no intrinsic width, so the stack stretches it over the leftover space.
class DismissArea: NSView {
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        let tap = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        tap.allowedTouchTypes = .direct
        addGestureRecognizer(tap)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onTap()
    }
}
