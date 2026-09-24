//
//  ItemSnapshots.swift
//  Stripe
//
//  Live pictures of the real bar items for the editor's bar. The bar builds its
//  items in preset order, so the editor's Nth item is the bar's Nth item, as long
//  as the editor's file is the one on the bar and has no unsaved edits. When
//  those don't hold, the previous pictures stay and the rest fall back to drawn
//  chips.
//

import AppKit

final class ItemSnapshotModel: ObservableObject {
    @Published private(set) var images: [UUID: NSImage] = [:]
    /// Items the bar isn't showing right now, e.g. because of a "when" condition.
    @Published private(set) var hidden = Set<UUID>()

    private let document: PresetDocument
    private var timer: Timer?

    init(document: PresetDocument) {
        self.document = document
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let bar = TouchBarController.shared
        let identifiers = bar.orderedIdentifiers
        guard bar.currentPresetPath == document.path, !document.hasPendingSave,
              identifiers.count == document.items.count else { return }

        var images: [UUID: NSImage] = [:]
        var hidden = Set<UUID>()
        for (item, identifier) in zip(document.items, identifiers) {
            guard let view = bar.items[identifier]?.view else {
                hidden.insert(item.id)
                continue
            }
            if let image = ItemSnapshotModel.snapshot(of: view) {
                images[item.id] = image
            }
        }
        self.images = images
        self.hidden = hidden
    }

    static func snapshot(of view: NSView) -> NSImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
