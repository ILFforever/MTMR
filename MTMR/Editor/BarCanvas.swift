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

extension EditorSession {
    /// Clears drag state and lets the document save what the drag changed.
    func endDrag(_ document: PresetDocument) {
        dragging = nil
        set(\.targetZone, nil)
        set(\.dropSlot, nil)
        document.holdsSaves = false
    }

    /// Whether to outline an item: the selection normally, but during a drag only
    /// the item being moved, so an earlier selection doesn't look like the target.
    func outlines(_ item: EditorItem) -> Bool {
        switch dragging {
        case let .move(id)?: return id == item.id
        case .new?: return false
        case nil: return selection == item.id
        }
    }
}

/// A position in one of the bar's sections.
struct DropSlot: Equatable {
    let align: String
    let index: Int
}

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

    /// The drop's payload: straight from the session when the drag started in this
    /// window, so the drop lands at once; otherwise read from the drag (slower).
    static func resolve(_ info: DropInfo, session: EditorSession, _ completion: @escaping (DragPayload) -> Void) -> Bool {
        if let known = session.dragging {
            completion(known)
            return true
        }
        return load(from: info, completion)
    }

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
        let slot = session.dropSlot?.align == align ? session.dropSlot?.index : nil
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if items.isEmpty && slot == nil {
                    Text(align.capitalizedFirst)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if slot == index { dropPlaceholder }
                    BarChip(item: item, snapshot: snapshots.images[item.id], isSelected: session.outlines(item))
                        .opacity(snapshots.hidden.contains(item.id) ? 0.4 : 1)
                        // Positions are reported as preferences, which SwiftUI recomputes
                        // on every layout (onAppear/onChange missed some).
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ChipFramesKey.self, value: [
                                item.id: ChipFrames(global: geometry.frame(in: .global),
                                                    zone: geometry.frame(in: .named(align))),
                            ])
                        })
                        .contextMenu { chipMenu(item) }
                        .onDrag {
                            session.set(\.selection, item.id)
                            session.dragging = .move(id: item.id)
                            document.holdsSaves = true
                            return DragPayload.move(id: item.id).provider
                        }
                }
                if let slot = slot, slot >= items.count { dropPlaceholder }
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
        }
        .coordinateSpace(name: align)
        .onPreferenceChange(ChipFramesKey.self) { frames in
            for (id, frame) in frames {
                session.chipFrames[id] = frame.global
                session.zoneFrames[id] = frame.zone
            }
        }
        .frame(minWidth: items.isEmpty ? 70 : nil)
        .background(RoundedRectangle(cornerRadius: 7)
            // The item or gap inside carries the blue outline; the section just brightens.
            .strokeBorder(Color.white.opacity(targeted ? 0.5 : 0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .onDrop(of: [.plainText], delegate: ZoneDropDelegate(document: document, session: session,
                                                             snapshots: snapshots, align: align))
        .fixedSize(horizontal: align != "center", vertical: false)
    }

    private var dropPlaceholder: some View {
        DropPlaceholder(preview: snapshots.preview)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}

/// Where a new item from the library will land, drawn as it will look.
struct DropPlaceholder: View {
    @ObservedObject var preview: DragPreviewModel

    var body: some View {
        Group {
            if let image = preview.image {
                Image(nsImage: image).frame(width: image.size.width, height: image.size.height)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.22)).frame(width: 60, height: 30)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2).padding(-2))
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

struct ChipFrames: Equatable {
    let global: CGRect
    let zone: CGRect
}

struct ChipFramesKey: PreferenceKey {
    static var defaultValue: [UUID: ChipFrames] = [:]
    static func reduce(value: inout [UUID: ChipFrames], nextValue: () -> [UUID: ChipFrames]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Adds a dropped library item where the bar made room for it.
private func addNewItem(_ type: String, align: String, at index: Int, document: PresetDocument,
                        session: EditorSession, snapshots: ItemSnapshotModel) {
    let item = ItemCatalog.newItem(type, align: align, document: document)
    snapshots.adoptPreview(for: item.id)
    withAnimation(.easeInOut(duration: 0.15)) {
        session.dropSlot = nil
        document.place(item, align: align, at: index)
    }
    snapshots.endPreview()
    session.selection = item.id
}

/// Dropping on a zone's empty space puts the item at the end of that zone.
struct ZoneDropDelegate: DropDelegate {
    let document: PresetDocument
    let session: EditorSession
    let snapshots: ItemSnapshotModel
    let align: String

    func dropEntered(info: DropInfo) {
        session.set(\.targetZone, align)
        reposition(at: info.location.x)
    }

    /// Where the dragged item goes is the number of items whose middle is left of
    /// the pointer. It settles rather than bouncing: after a move, the neighbour
    /// slides past the pointer in the direction that agrees with the new order.
    private func reposition(at x: CGFloat) {
        session.dropTouched = Date()
        let section = document.items(aligned: align)
        func isLeft(_ item: EditorItem) -> Bool {
            guard let frame = session.zoneFrames[item.id] else { return false }
            return frame.midX < x
        }
        switch session.dragging {
        case let .move(id)?:
            guard let item = document.items.first(where: { $0.id == id }) else { return }
            let others = section.filter { $0 !== item }
            let desired = others.filter(isLeft).count
            // Already there: its index in the section counts the others before it.
            if item.align == align, section.firstIndex(where: { $0 === item }) == desired { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                document.place(item, align: align, at: desired)
            }
        case .new?:
            let slot = DropSlot(align: align, index: section.filter(isLeft).count)
            if session.dropSlot != slot {
                withAnimation(.easeInOut(duration: 0.15)) { session.dropSlot = slot }
            }
        case nil:
            break
        }
    }

    func dropExited(info _: DropInfo) {
        if session.targetZone == align { session.set(\.targetZone, nil) }
        // Entering an item inside the section also exits the section; only close
        // the gap if nothing claimed the drag right after (i.e. it left the bar).
        let exited = Date()
        DispatchQueue.main.async {
            // Letting go also exits; keep the gap open so the drop fills it seamlessly.
            guard NSEvent.pressedMouseButtons != 0 else { return }
            if session.dropTouched < exited, session.dropSlot?.align == align {
                withAnimation(.easeInOut(duration: 0.15)) { session.dropSlot = nil }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        reposition(at: info.location.x)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        session.set(\.targetZone, nil)
        let index = session.dropSlot?.align == align ? session.dropSlot?.index ?? .max : .max
        return DragPayload.resolve(info, session: session) { payload in
            switch payload {
            case let .new(type):
                addNewItem(type, align: align, at: index, document: document, session: session, snapshots: snapshots)
            case let .move(id):
                if let item = document.items.first(where: { $0.id == id }), item.align != align {
                    withAnimation { document.place(item, align: align, at: .max) }
                }
            }
            session.endDrag(document)
        }
    }
}

// MARK: - The library

struct ItemLibrary: View {
    /// Not observed: the library only adds to it, and redrawing every tile on
    /// each edit (including each reorder during a drag) is wasted work.
    let document: PresetDocument
    @ObservedObject var session: EditorSession
    let snapshots: ItemSnapshotModel

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
                                    LibraryTile(info: info, preview: snapshots.preview, onHover: { hovering in
                                        hoverChanged(info.type, hovering)
                                    })
                                    .onDrag({
                                        session.dragging = .new(type: info.type)
                                        document.holdsSaves = true
                                        snapshots.beginPreview(of: info.type)
                                        return DragPayload.new(type: info.type).provider
                                    }, preview: {
                                        LibraryDragImage(info: info, preview: snapshots.preview)
                                    })
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

    /// Pointing at a tile builds its preview, so a drag from it shows the item's
    /// real look from the start; it's dropped again if no drag follows.
    private func hoverChanged(_ type: String, _ hovering: Bool) {
        let delay = hovering ? 0.12 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if hovering {
                snapshots.beginPreview(of: type)
            } else if session.dragging == nil, snapshots.preview.type == type {
                snapshots.endPreview()
            }
        }
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
        snapshots.beginPreview(of: type)
        snapshots.adoptPreview(for: item.id)
        snapshots.endPreview()
        withAnimation { document.place(item, align: "center", at: .max) }
        session.selection = item.id
    }
}

/// What follows the pointer while dragging from the library: the item as it will
/// look on the bar, or its tile until that picture is ready.
struct LibraryDragImage: View {
    let info: ItemTypeInfo
    @ObservedObject var preview: DragPreviewModel

    var body: some View {
        if preview.type == info.type, let image = preview.image {
            Image(nsImage: image)
                .frame(width: image.size.width, height: image.size.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
        } else {
            Image(systemName: info.symbol)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 44, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.22)))
        }
    }
}

struct LibraryTile: View {
    let info: ItemTypeInfo
    @ObservedObject var preview: DragPreviewModel
    let onHover: (Bool) -> Void
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
        .onHover { inside in
            hovering.wrappedValue = inside
            onHover(inside)
        }
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
        if case .move? = session.dragging { session.set(\.targetZone, "library") }
    }

    func dropExited(info _: DropInfo) {
        if session.targetZone == "library" { session.set(\.targetZone, nil) }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        session.set(\.targetZone, nil)
        return DragPayload.resolve(info, session: session) { payload in
            if case let .move(id) = payload, let item = document.find(id) {
                if session.selection == id { session.selection = nil }
                withAnimation { document.remove(item) }
            }
            session.endDrag(document)
        }
    }
}
