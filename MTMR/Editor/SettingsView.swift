//
//  SettingsView.swift
//  Stripe
//
//  The editor window: a live picture of the Touch Bar on top, the items in a
//  sidebar grouped by position (groups and popovers expand in place), and the
//  selected item's settings on the right.
//

import SwiftUI

/// UI state for the editor window, kept outside the views (see the note on
/// `State` in EditorFields.swift).
final class EditorSession: ObservableObject {
    @Published var selection: UUID?
    @Published var expanded = Set<UUID>()
}

struct SettingsView: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var session: EditorSession
    @ObservedObject var preview: TouchBarPreviewModel

    private static let sections = [("left", "Left"), ("center", "Center"), ("right", "Right")]

    var body: some View {
        VStack(spacing: 0) {
            header
            TouchBarPreviewView(model: preview)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 380)
                detail
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            presetMenu
            addMenu
            Spacer()
            if let error = document.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red).lineLimit(1)
            } else if let saved = document.lastSaved {
                Label("Saved \(saved.formatted(date: .omitted, time: .standard))", systemImage: "checkmark.circle")
                    .foregroundColor(.secondary)
            } else {
                Text("Changes apply to the Touch Bar as you edit").foregroundColor(.secondary)
            }
            Button(action: openInEditor) { Image(systemName: "doc.text") }
                .help("Open the preset file in a text editor")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        .frame(maxWidth: 220)
        .help("Which bar you're editing: the main one, or one for a specific app")
    }

    private var addMenu: some View {
        Menu {
            ForEach(ItemCatalog.categories, id: \.self) { category in
                Menu(category) {
                    ForEach(ItemCatalog.all.filter { $0.category == category }, id: \.type) { info in
                        Button(action: { add(info.type) }) {
                            Label(info.name, systemImage: info.symbol)
                        }
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .frame(maxWidth: 90)
        .help("Add an item after the selection, or inside the selected group or popover")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $session.selection) {
            ForEach(SettingsView.sections, id: \.0) { align, title in
                Section(header: Text(title)) {
                    ForEach(document.items(aligned: align)) { item in
                        row(item)
                    }
                    .onMove { document.move(inSection: align, from: $0, to: $1) }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let item = document.find(session.selection) { delete(item) }
        }
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
            ItemInspector(item: item, isTopLevel: document.items.contains { $0 === item })
                .id(item.id) // fresh field state per item
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hand.point.up.left").font(.system(size: 36)).foregroundColor(.secondary)
                Text("Select an item to edit it").font(.title3)
                Text("Drag items to reorder them. Right-click for more options.").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private func add(_ type: String) {
        let selected = document.find(session.selection)
        if let container = selected, container.isContainer {
            let item = ItemCatalog.newItem(type, align: "center", document: document)
            document.add(item, to: container)
            session.expanded.insert(container.id)
            session.selection = item.id
        } else {
            let item = ItemCatalog.newItem(type, align: selected?.align ?? "center", document: document)
            document.add(item, to: nil)
            if let selected = selected, let index = document.items.firstIndex(where: { $0 === selected }) {
                // Place it right after the selection rather than at the end.
                document.items.removeLast()
                document.items.insert(item, at: index + 1)
            }
            session.selection = item.id
        }
    }

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
