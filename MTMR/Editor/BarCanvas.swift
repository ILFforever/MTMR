//
//  BarCanvas.swift
//  Stripe
//
//  Drag-and-drop editing, like macOS's "Customize Touch Bar": a mock of the bar
//  with Left / Center / Right zones, and a library of every item type.
//
//  - Drag a library tile onto the bar to add it where it's dropped.
//  - Drag items along the bar to reorder them or move them between zones.
//  - Drag an item off the bar into the library to remove it.
//
//  Drags carry "stripe:new:<type>" or "stripe:move:<uuid>" as plain text. The
//  item being dragged is also recorded in EditorSession when the drag starts,
//  so the bar can reorder live while hovering, before the drop.
//

import SwiftUI
import UniformTypeIdentifiers

enum DragPayload {
    case new(type: String)
    case move(id: UUID)

    private static let prefix = "stripe:"

    var string: String {
        switch self {
        case let .new(type): return "\(DragPayload.prefix)new:\(type)"
        case let .move(id): return "\(DragPayload.prefix)move:\(id.uuidString)"
        }
    }

    init?(_ string: String) {
        guard string.hasPrefix(DragPayload.prefix) else { return nil }
        let body = string.dropFirst(DragPayload.prefix.count)
        if body.hasPrefix("new:") {
            self = .new(type: String(body.dropFirst(4)))
        } else if body.hasPrefix("move:"), let id = UUID(uuidString: String(body.dropFirst(5))) {
            self = .move(id: id)
        } else {
            return nil
        }
    }

    var provider: NSItemProvider { NSItemProvider(object: string as NSString) }

    /// Reads a payload from a drop, then calls back on the main thread.
    static func load(from info: DropInfo, _ completion: @escaping (DragPayload) -> Void) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let payload = DragPayload(text) else { return }
            DispatchQueue.main.async { completion(payload) }
        }
        return true
    }
}

// MARK: - The bar

struct BarCanvas: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Your bar").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Spacer()
                Text("Drag to reorder · drag into the library to remove · click to edit")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                zone("left")
                zone("center").frame(maxWidth: .infinity)
                zone("right")
            }
            .padding(6)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
        }
    }

    private func zone(_ align: String) -> some View {
        let items = document.items(aligned: align)
        let targeted = session.targetZone == align
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if items.isEmpty {
                    Text(align.capitalizedFirst)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    BarChip(item: item, isSelected: session.selection == item.id)
                        .onTapGesture { session.selection = item.id }
                        .onDrag {
                            session.dragging = .move(id: item.id)
                            return DragPayload.move(id: item.id).provider
                        }
                        .onDrop(of: [.plainText], delegate: ChipDropDelegate(
                            document: document, session: session, align: align, index: index, target: item))
                }
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: items.isEmpty ? 70 : nil)
        .background(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(targeted ? Color.accentColor : Color.gray.opacity(0.35),
                          style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [4, 3])))
        .onDrop(of: [.plainText], delegate: ZoneDropDelegate(document: document, session: session, align: align))
        .fixedSize(horizontal: align != "center", vertical: false)
    }
}

/// An approximation of how the item looks on the bar: icon, label, background.
struct BarChip: View {
    @ObservedObject var item: EditorItem
    let isSelected: Bool

    private var background: Color? {
        (item.fields["background"]?.string?.namedOrHexColor).map { Color(nsColor: $0) }
    }

    private var radius: CGFloat {
        if item.fields["style"]?.string == "pill" { return 15 }
        return CGFloat(item.fields["cornerRadius"]?.number ?? 6)
    }

    private var label: String? {
        if let title = item.fields["title"]?.string, !title.isEmpty { return title }
        // Icon-only items (media keys, sliders' popovers…) show just the icon.
        if item.fields["symbol"] != nil || item.info.category == "Media" || item.info.category == "Keys" { return nil }
        return item.info.name
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.displaySymbol)
                .foregroundColor((item.fields["iconColor"]?.string?.namedOrHexColor).map { Color(nsColor: $0) } ?? .white)
            if let label = label {
                Text(label)
                    .lineLimit(1)
                    .foregroundColor((item.fields["textColor"]?.string?.namedOrHexColor).map { Color(nsColor: $0) } ?? .white)
            }
            if item.fields["when"] != nil {
                Image(systemName: "eye").font(.system(size: 9)).foregroundColor(.gray)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(minWidth: 30)
        .background(RoundedRectangle(cornerRadius: radius)
            .fill(background ?? (item.fields["bordered"]?.bool == false ? Color.clear : Color(white: 0.22))))
        .overlay(RoundedRectangle(cornerRadius: radius)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .help(item.displayName)
    }
}

/// Hovering over a chip reorders live for moves; dropping a new item inserts it before the chip.
struct ChipDropDelegate: DropDelegate {
    let document: PresetDocument
    let session: EditorSession
    let align: String
    let index: Int
    let target: EditorItem

    func dropEntered(info _: DropInfo) {
        session.targetZone = align
        guard case let .move(id)? = session.dragging, id != target.id,
              let item = document.items.first(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            document.place(item, align: align, at: index)
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        session.targetZone = nil
        return DragPayload.load(from: info) { payload in
            if case let .new(type) = payload {
                let item = ItemCatalog.newItem(type, align: align, document: document)
                withAnimation { document.place(item, align: align, at: index) }
                session.selection = item.id
            }
            session.dragging = nil
        }
    }
}

/// Dropping on a zone's empty space puts the item at the end of that zone.
struct ZoneDropDelegate: DropDelegate {
    let document: PresetDocument
    let session: EditorSession
    let align: String

    func dropEntered(info _: DropInfo) { session.targetZone = align }

    func dropExited(info _: DropInfo) {
        if session.targetZone == align { session.targetZone = nil }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        session.targetZone = nil
        return DragPayload.load(from: info) { payload in
            switch payload {
            case let .new(type):
                let item = ItemCatalog.newItem(type, align: align, document: document)
                withAnimation { document.place(item, align: align, at: .max) }
                session.selection = item.id
            case let .move(id):
                if let item = document.items.first(where: { $0.id == id }), item.align != align {
                    withAnimation { document.place(item, align: align, at: .max) }
                }
            }
            session.dragging = nil
        }
    }
}

// MARK: - The library

struct ItemLibrary: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var session: EditorSession

    var body: some View {
        let targeted = session.targetZone == "library"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Item Library").font(.headline)
                Spacer()
                Label(targeted ? "Release to remove" : "Drag onto the bar to add · drag here to remove",
                      systemImage: targeted ? "trash" : "hand.draw")
                    .font(.caption)
                    .foregroundColor(targeted ? .red : .secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ItemCatalog.categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                                ForEach(ItemCatalog.all.filter { $0.category == category }, id: \.type) { info in
                                    LibraryTile(info: info)
                                        .onDrag {
                                            session.dragging = .new(type: info.type)
                                            return DragPayload.new(type: info.type).provider
                                        }
                                        .onTapGesture(count: 2) { add(info.type) }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(targeted ? Color.red.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(targeted ? Color.red.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: targeted ? 2 : 0.5))
        .onDrop(of: [.plainText], delegate: LibraryDropDelegate(document: document, session: session))
    }

    /// Double-clicking a tile adds it to the end of the center section.
    private func add(_ type: String) {
        let item = ItemCatalog.newItem(type, align: "center", document: document)
        withAnimation { document.place(item, align: "center", at: .max) }
        session.selection = item.id
    }
}

struct LibraryTile: View {
    let info: ItemTypeInfo

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: info.symbol)
                .font(.system(size: 18))
                .frame(height: 22)
            Text(info.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 92, height: 64)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .contentShape(Rectangle())
        .help("Drag onto the bar, or double-click to add")
    }
}

/// Items dragged from the bar into the library are removed.
struct LibraryDropDelegate: DropDelegate {
    let document: PresetDocument
    let session: EditorSession

    func validateDrop(info _: DropInfo) -> Bool {
        if case .move? = session.dragging { return true }
        return false
    }

    func dropEntered(info _: DropInfo) {
        if case .move? = session.dragging { session.targetZone = "library" }
    }

    func dropExited(info _: DropInfo) {
        if session.targetZone == "library" { session.targetZone = nil }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        session.targetZone = nil
        return DragPayload.load(from: info) { payload in
            if case let .move(id) = payload, let item = document.find(id) {
                if session.selection == id { session.selection = nil }
                withAnimation { document.remove(item) }
            }
            session.dragging = nil
        }
    }
}
