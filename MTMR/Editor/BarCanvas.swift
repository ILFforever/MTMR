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
    @ObservedObject var snapshots: ItemSnapshotModel

    private static let positions = [("left", "Left"), ("center", "Center"), ("right", "Right")]

    @ViewBuilder
    private func chipMenu(_ item: EditorItem) -> some View {
        Button("Edit") { session.selection = item.id }
        Button("Duplicate") { document.duplicate(item) }
        Menu("Move To") {
            ForEach(BarCanvas.positions, id: \.0) { align, title in
                Button(title) { withAnimation { document.place(item, align: align, at: .max) } }
                    .disabled(item.align == align)
            }
        }
        Divider()
        Button("Remove") {
            if session.selection == item.id { session.selection = nil }
            withAnimation { document.remove(item) }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            zone("left")
            zone("center").frame(maxWidth: .infinity)
            zone("right")
        }
        .padding(6)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: EditorStyle.barRadius).fill(Color.black))
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
                    BarChip(item: item, snapshot: snapshots.images[item.id], isSelected: session.selection == item.id)
                        .opacity(snapshots.hidden.contains(item.id) ? 0.4 : 1)
                        .onTapGesture { session.selection = item.id }
                        .contextMenu { chipMenu(item) }
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
            .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.18),
                          style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [4, 3])))
        .onDrop(of: [.plainText], delegate: ZoneDropDelegate(document: document, session: session, align: align))
        .fixedSize(horizontal: align != "center", vertical: false)
    }
}

/// The item as it looks on the bar: a live snapshot of the real item when there
/// is one, otherwise an approximation (icon, label, background).
struct BarChip: View {
    @ObservedObject var item: EditorItem
    let snapshot: NSImage?
    let isSelected: Bool

    private var background: Color? {
        (item.fields["background"]?.string?.namedOrHexColor).map { Color(nsColor: $0) }
    }

    private var radius: CGFloat {
        if item.fields["style"]?.string == "pill" { return 15 }
        return CGFloat(item.fields["cornerRadius"]?.number ?? 6)
    }

    /// Media keys and the like read best as icons; everything else gets a short
    /// label so similar icons (CPU, memory…) can be told apart.
    private var label: String? {
        if let title = item.fields["title"]?.string, !title.isEmpty { return title }
        return item.info.isIconOnly || item.isContainer ? nil : item.shortName
    }

    var body: some View {
        if let snapshot = snapshot {
            Image(nsImage: snapshot)
                .frame(width: snapshot.size.width, height: snapshot.size.height)
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(-2))
                .contentShape(Rectangle())
                .help(item.displayName)
        } else {
            approximation
        }
    }

    private var approximation: some View {
        HStack(spacing: 5) {
            Image(systemName: item.displaySymbol)
                .foregroundColor((item.fields["iconColor"]?.string?.namedOrHexColor).map { Color(nsColor: $0) } ?? .white)
            if let label = label {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110)
                    .foregroundColor((item.fields["textColor"]?.string?.namedOrHexColor).map { Color(nsColor: $0) } ?? .white)
            }
            if item.isContainer {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                    .help("Opens more items")
            }
            if item.fields["when"] != nil {
                Image(systemName: "eye").font(.system(size: 9)).foregroundColor(.gray)
                    .help("Only shows under some conditions")
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if matches.isEmpty {
                        Text("No items match \u{201C}\(session.search)\u{201D}")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(ItemCatalog.categories.filter { category in matches.contains { $0.category == category } },
                            id: \.self) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                ForEach(matches.filter { $0.category == category }, id: \.type) { info in
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            Divider()
            Label(targeted ? "Release to remove" : "Drag onto the bar to add, or double-click",
                  systemImage: targeted ? "trash" : "hand.draw")
                .font(.system(size: 11))
                .foregroundColor(targeted ? .red : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .background(targeted ? Color.red.opacity(0.08) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.red.opacity(targeted ? 0.6 : 0), lineWidth: 2)
            .padding(4))
        .onDrop(of: [.plainText], delegate: LibraryDropDelegate(document: document, session: session))
    }

    /// Item types whose name, type or category contain the search text.
    private var matches: [ItemTypeInfo] {
        let query = session.search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return ItemCatalog.all }
        return ItemCatalog.all.filter { info in
            [info.name, info.type, info.category].contains { $0.localizedCaseInsensitiveContains(query) }
        }
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
    private let hovering = State(initialValue: false)

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: info.symbol)
                .font(.system(size: 17))
                .frame(height: 20)
            Text(info.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(hovering.wrappedValue ? 0.1 : 0.05)))
        .contentShape(Rectangle())
        .onHover { hovering.wrappedValue = $0 }
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
