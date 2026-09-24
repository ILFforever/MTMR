//
//  SettingsView.swift
//  Stripe
//
//  The editor window: the live, editable Touch Bar on top, the items in a
//  sidebar grouped by position (groups and popovers expand in place), and the
//  selected item's settings on the right.
//

import SwiftUI

/// UI state for the editor window, kept outside the views (see the note on
/// `State` in EditorFields.swift).
final class EditorSession: ObservableObject {
    @Published var selection: UUID?
    @Published var expanded = Set<UUID>()
    /// What's being dragged, recorded when the drag starts (see BarCanvas.swift).
    @Published var dragging: DragPayload?
    /// Which drop zone is highlighted: "left", "center", "right" or "library".
    @Published var targetZone: String?
    /// The left pane: the item library ("library") or the outline of items ("outline").
    @Published var leftPane = "library"
    /// Filters the library tiles or the outline rows.
    @Published var search = ""
}

struct SettingsView: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var session: EditorSession
    let snapshots: ItemSnapshotModel

    private static let sections = [("left", "Left"), ("center", "Center"), ("right", "Right")]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                stage
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            HSplitView {
                leftPane
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 440)
                    .background(SidebarBackground())
                detail
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 680)
        // The header sits in the title bar, beside the window buttons.
        .edgesIgnoringSafeArea(.top)
    }

    /// The bar, drawn from live pictures of the real items, and edited in place.
    private var stage: some View {
        VStack(alignment: .leading, spacing: 6) {
            StageCaption(title: "Your Touch Bar", live: true,
                         hint: "Drag to reorder · drag into the library to remove · click to edit")
            BarCanvas(document: document, session: session, snapshots: snapshots)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(placeholder: session.leftPane == "library" ? "Search items" : "Search your bar",
                            text: $session.search)
                Picker("", selection: $session.leftPane) {
                    Image(systemName: "square.grid.2x2").help("Library: every item you can add").tag("library")
                    Image(systemName: "list.bullet").help("Outline: the items on your bar").tag("outline")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if session.leftPane == "library" {
                ItemLibrary(document: document, session: session)
            } else {
                sidebar
            }
        }
    }

    // MARK: Header

    /// Lives in the (transparent) title bar: preset on the left after the window
    /// buttons, then undo/redo, save status and the file button on the right.
    private var header: some View {
        HStack(spacing: 10) {
            presetMenu
            Spacer()
            Group {
                if let error = document.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                } else if let saved = document.lastSaved {
                    Text("Saved \(saved.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.secondary)
                } else {
                    Text("Changes apply as you edit").foregroundColor(.secondary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            HStack(spacing: 2) {
                Button(action: document.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!document.canUndo)
                    .help("Undo the last change")
                Button(action: document.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!document.canRedo)
                    .help("Redo")
            }
            Button(action: openInEditor) { Image(systemName: "doc.text") }
                .help("Open the preset file in a text editor")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 78) // clear of the window buttons
        .padding(.trailing, 12)
        .frame(height: 30)     // the standard title bar height, level with the window buttons
        .padding(.bottom, 6)
    }

    private var presetMenu: some View {
        Menu {
            Button("All apps") { document.open(path: standardConfigPath) }
            let appPresets = PresetLibrary.appPresets()
            if !appPresets.isEmpty {
                Divider()
                ForEach(appPresets, id: \.path) { preset in
                    Button(preset.name) { document.open(path: preset.path) }
                }
            }
            Divider()
            Menu("New Preset for App") {
                ForEach(PresetLibrary.runningApps(), id: \.bundleId) { app in
                    Button(app.name) {
                        if let path = PresetLibrary.createAppPreset(bundleId: app.bundleId) {
                            document.open(path: path)
                        }
                    }
                }
            }
            if document.path != standardConfigPath {
                Button("Delete This Preset…") { deleteCurrentPreset() }
            }
        } label: {
            Label(document.displayName, systemImage: document.path == standardConfigPath ? "rectangle.3.group" : "app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Which bar you're editing: the main one, or one for a specific app")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $session.selection) {
            ForEach(SettingsView.sections, id: \.0) { align, title in
                let items = document.items(aligned: align).filter(matchesSearch)
                // While searching, sections with no matches are left out.
                if session.search.isEmpty || !items.isEmpty {
                    Section(header: Text(title)) {
                        ForEach(items) { item in
                            row(item)
                        }
                        .onMove { document.move(inSection: align, from: $0, to: $1) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let item = document.find(session.selection) { delete(item) }
        }
    }

    /// An item matches if its name, type or any of its children's do.
    private func matchesSearch(_ item: EditorItem) -> Bool {
        let query = session.search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [item.displayName, item.info.name, item.type].contains { $0.localizedCaseInsensitiveContains(query) }
            || (item.children ?? []).contains(where: matchesSearch)
    }

    @ViewBuilder
    private func row(_ item: EditorItem) -> some View {
        if item.isContainer {
            DisclosureGroup(isExpanded: expandedBinding(item)) {
                ForEach(item.children ?? []) { child in
                    ItemRow(item: child)
                        .tag(child.id)
                        .contextMenu { contextMenu(for: child) }
                }
                .onMove { document.move(in: item, from: $0, to: $1) }
            } label: {
                ItemRow(item: item)
                    .contextMenu { contextMenu(for: item) }
            }
            .tag(item.id)
        } else {
            ItemRow(item: item)
                .tag(item.id)
                .contextMenu { contextMenu(for: item) }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: EditorItem) -> some View {
        Button("Duplicate") { document.duplicate(item) }
        if document.items.contains(where: { $0 === item }) {
            Menu("Move To") {
                ForEach(SettingsView.sections, id: \.0) { align, title in
                    Button(title) { item.align = align }.disabled(item.align == align)
                }
            }
        }
        Divider()
        Button("Delete") { delete(item) }
    }

    private func expandedBinding(_ item: EditorItem) -> Binding<Bool> {
        Binding(get: { session.expanded.contains(item.id) },
                set: { if $0 { session.expanded.insert(item.id) } else { session.expanded.remove(item.id) } })
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let item = document.find(session.selection) {
            ItemInspector(item: item, isTopLevel: document.items.contains { $0 === item }, selection: $session.selection)
                .id(item.id) // fresh field state per item
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hand.point.up.left").font(.system(size: 36)).foregroundColor(.secondary)
                Text("Select an item on the bar to edit it").font(.title3)
                Text("Drag items from the Library onto the bar to add them. Right-click an item for more options.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private func delete(_ item: EditorItem) {
        if session.selection == item.id { session.selection = nil }
        document.remove(item)
    }

    private func deleteCurrentPreset() {
        let alert = NSAlert()
        alert.messageText = "Delete the preset for \(document.displayName)?"
        alert.informativeText = "That app will use the main bar again."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(atPath: document.path)
        document.open(path: standardConfigPath)
        TouchBarController.shared.reloadAfterEdit()
    }

    private func openInEditor() {
        document.flushSave()
        NSWorkspace.shared.open(URL(fileURLWithPath: document.path))
    }
}

struct ItemRow: View {
    @ObservedObject var item: EditorItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.displaySymbol)
                .frame(width: 18)
                .foregroundColor(.accentColor)
            Text(item.displayName).lineLimit(1)
            if item.displayName != item.info.name {
                Text(item.info.name).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if item.fields["when"] != nil {
                Image(systemName: "eye").foregroundColor(.secondary).help("Only shows under some conditions")
            }
        }
    }
}

// MARK: - Presets on disk

enum PresetLibrary {
    static var appsDirectory: String { appSupportDirectory.appending("/apps") }

    static func appPresets() -> [(name: String, path: String)] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: appsDirectory)) ?? []
        return files.filter { $0.hasSuffix(".json") }.sorted().map { file in
            let bundleId = String(file.dropLast(5))
            return (PresetDocument.appName(for: bundleId) ?? bundleId, appsDirectory + "/" + file)
        }
    }

    static func runningApps() -> [(name: String, bundleId: String)] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var seen = Set<String>()
        return apps.compactMap { app in
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (app.localizedName ?? id, id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Starts an app's preset as a copy of the main bar, so it can be tweaked from there.
    static func createAppPreset(bundleId: String) -> String? {
        let path = appsDirectory + "/\(bundleId).json"
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: appsDirectory, withIntermediateDirectories: true)
            do {
                try FileManager.default.copyItem(atPath: standardConfigPath, toPath: path)
            } catch {
                NSLog("Stripe: couldn't create app preset: \(error)")
                return nil
            }
        }
        return path
    }
}
