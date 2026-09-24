//
//  ItemInspector.swift
//  Stripe
//
//  The right-hand pane: every setting of the selected item, in collapsible
//  sections. Section open/closed state is remembered across items.
//

import SwiftUI

struct ItemInspector: View {
    @ObservedObject var item: EditorItem
    let isTopLevel: Bool

    @AppStorage("inspector.layout") private var layoutOpen = true
    @AppStorage("inspector.appearance") private var appearanceOpen = true
    @AppStorage("inspector.content") private var contentOpen = true
    @AppStorage("inspector.actions") private var actionsOpen = true
    @AppStorage("inspector.visibility") private var visibilityOpen = false
    @AppStorage("inspector.json") private var jsonOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                InspectorSection(title: "Layout", symbol: "rectangle.split.3x1", isExpanded: $layoutOpen) {
                    if isTopLevel {
                        FieldRow(label: "Position") {
                            Picker("", selection: Binding(get: { item.align }, set: { item.align = $0 })) {
                                Text("Left").tag("left")
                                Text("Center").tag("center")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                    }
                    if !item.info.fields.contains(where: { $0.path == "title" }) {
                        TextFieldRow(label: "Title", placeholder: "None", text: string("title"))
                    }
                    NumberFieldRow(label: "Width", placeholder: "Auto", help: "Points; the bar is about 1000 wide", value: number("width"))
                }

                InspectorSection(title: "Appearance", symbol: "paintpalette", isExpanded: $appearanceOpen) {
                    SymbolRow(label: "Icon", value: string("symbol"))
                    ColorRow(label: "Icon color", value: string("iconColor"))
                    ColorRow(label: "Background", value: string("background"))
                    ToggleRow(label: "Pill shape", help: "Rounded ends; needs a background",
                              defaultValue: false,
                              value: Binding(get: { item[string: "style"] == "pill" },
                                             set: { item[string: "style"] = ($0 ?? false) ? "pill" : nil }))
                    NumberFieldRow(label: "Corner radius", placeholder: "Default", value: number("cornerRadius"))
                    ToggleRow(label: "Border", help: "The standard gray button background",
                              defaultValue: true, value: bool("bordered"))
                    NumberFieldRow(label: "Font size", placeholder: "15", value: number("fontSize"))
                    ChoiceRow(label: "Font weight",
                              options: ["ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"],
                              value: string("fontWeight"))
                    ColorRow(label: "Text color", value: string("textColor"))
                    ToggleRow(label: "Fixed-width digits", help: "Stops changing numbers from jittering",
                              defaultValue: false, value: bool("monospacedDigits"))
                }

                if !item.info.fields.isEmpty {
                    InspectorSection(title: item.info.name, symbol: item.info.symbol, isExpanded: $contentOpen) {
                        ForEach(item.info.fields) { field in
                            fieldView(field)
                        }
                    }
                }

                if !item.info.isContainer {
                    InspectorSection(title: "Actions", symbol: "hand.tap", isExpanded: $actionsOpen) {
                        ActionsEditor(item: item)
                    }
                }

                InspectorSection(title: "Visibility", symbol: "eye", isExpanded: $visibilityOpen) {
                    Text("Only show this item when all of these are true. Leave blank to always show it.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.vertical, 6)
                    TextFieldRow(label: "App is", placeholder: "Any app", help: "Regex on name or bundle ID", text: string("when.app"))
                    TextFieldRow(label: "App is not", placeholder: "—", help: "Regex on name or bundle ID", text: string("when.notApp"))
                    TextFieldRow(label: "Time is", placeholder: "Any time", help: "e.g. 09:00-18:00", text: string("when.time"))
                    TextFieldRow(label: "Command succeeds", placeholder: "—", help: "Shown while it exits 0", text: string("when.script"))
                    NumberFieldRow(label: "Check command every", placeholder: "10", help: "Seconds", value: number("when.every"))
                }

                InspectorSection(title: "JSON", symbol: "curlybraces", isExpanded: $jsonOpen) {
                    RawJSONEditor(item: item)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: item.displaySymbol)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.title2.weight(.semibold))
                Text(item.info.name + (item.info.isContainer ? " · \(item.children?.count ?? 0) items" : ""))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: FieldSpec) -> some View {
        switch field.kind {
        case let .text(placeholder):
            TextFieldRow(label: field.label, placeholder: placeholder, text: string(field.path))
        case .multiline:
            MultilineRow(label: field.label, text: string(field.path))
        case let .number(placeholder):
            NumberFieldRow(label: field.label, placeholder: placeholder, value: number(field.path))
        case .toggle:
            ToggleRow(label: field.label, defaultValue: false, value: bool(field.path))
        case let .choice(options):
            ChoiceRow(label: field.label, options: options, value: string(field.path))
        }
    }

    // Bindings into the item's JSON; empty values remove the key.

    private func string(_ path: String) -> Binding<String> {
        Binding(get: { item[string: path] ?? "" }, set: { item[string: path] = $0 })
    }

    private func number(_ path: String) -> Binding<Double?> {
        Binding(get: { item[number: path] }, set: { item[number: path] = $0 })
    }

    private func bool(_ path: String) -> Binding<Bool?> {
        Binding(get: { item[bool: path] }, set: { item[bool: path] = $0 })
    }
}

// MARK: - Actions

struct ActionsEditor: View {
    @ObservedObject var item: EditorItem

    static let triggers = [("singleTap", "Tap"), ("doubleTap", "Double tap"), ("tripleTap", "Triple tap"), ("longTap", "Press and hold")]
    static let kinds = [("shellScript", "Run shell command"), ("appleScript", "Run AppleScript"), ("openUrl", "Open URL"),
                        ("keyPress", "Press key"), ("hidKey", "Media / system key")]
    static let hidKeys: [(Int, String)] = [(0, "Volume up"), (1, "Volume down"), (7, "Mute"), (2, "Brightness up"),
                                           (3, "Brightness down"), (16, "Play / pause"), (17, "Next"), (18, "Previous"),
                                           (21, "Keyboard light up"), (22, "Keyboard light down")]

    private var actions: [[String: JSONValue]] {
        item.fields["actions"]?.array?.compactMap { $0.object } ?? []
    }

    private var hasLegacyActions: Bool {
        item.fields["action"] != nil || item.fields["longAction"] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasLegacyActions {
                Label("This item also uses older \"action\"/\"longAction\" keys. Edit those in the JSON section.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundColor(.secondary)
            }
            if actions.isEmpty {
                Text(hasBuiltInAction ? "Uses its built-in action. Add one to override it." : "No actions yet.")
                    .foregroundColor(.secondary)
            }
            ForEach(actions.indices, id: \.self) { index in
                actionCard(index)
            }
            Button(action: addAction) {
                Label("Add Action", systemImage: "plus")
            }
            .padding(.bottom, 6)
        }
        .padding(.top, 8)
    }

    private var hasBuiltInAction: Bool {
        ["escape", "delete", "volumeUp", "volumeDown", "mute", "play", "next", "previous", "brightnessUp",
         "brightnessDown", "sleep", "displaySleep", "cpu", "dnd", "nightShift", "darkMode", "close"].contains(item.type)
    }

    private func actionCard(_ index: Int) -> some View {
        let action = actions[index]
        let kind = action["action"]?.string ?? "shellScript"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: binding(index, "trigger", default: "singleTap")) {
                    ForEach(ActionsEditor.triggers, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 140)
                Picker("", selection: binding(index, "action", default: "shellScript")) {
                    ForEach(ActionsEditor.kinds, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 190)
                Spacer()
                Button(action: { removeAction(index) }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove action")
            }
            switch kind {
            case "shellScript":
                if isShellCommandForm(action) {
                    TextField("Command, e.g. open -a Safari", text: shellCommand(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    TextField("Executable", text: binding(index, "executablePath", default: ""))
                        .textFieldStyle(.roundedBorder)
                    TextField("Arguments, separated by commas", text: arguments(index))
                        .textFieldStyle(.roundedBorder)
                }
            case "appleScript":
                TextEditor(text: nestedBinding(index, "actionAppleScript", "inline"))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            case "openUrl":
                TextField("https://…", text: binding(index, "url", default: ""))
                    .textFieldStyle(.roundedBorder)
            case "hidKey":
                Picker("Key", selection: keycode(index)) {
                    ForEach(ActionsEditor.hidKeys, id: \.0) { Text($0.1).tag($0.0) }
                }
                .frame(maxWidth: 260)
            default: // keyPress
                HStack {
                    Text("Key code")
                    TextField("53 = Esc", value: keycode(index), formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                    Text("macOS virtual key code").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
    }

    // MARK: Editing

    private func update(_ index: Int, _ change: (inout [String: JSONValue]) -> Void) {
        var list = actions
        guard list.indices.contains(index) else { return }
        change(&list[index])
        item.setRaw("actions", .array(list.map { .object($0) }))
    }

    private func addAction() {
        var list = actions
        let trigger = list.contains { $0["trigger"]?.string == "singleTap" } ? "longTap" : "singleTap"
        list.append(["trigger": .string(trigger), "action": .string("shellScript"),
                     "executablePath": .string("/bin/sh"), "shellArguments": .array([.string("-c"), .string("")])])
        item.setRaw("actions", .array(list.map { .object($0) }))
    }

    private func removeAction(_ index: Int) {
        var list = actions
        list.remove(at: index)
        item.setRaw("actions", list.isEmpty ? nil : .array(list.map { .object($0) }))
    }

    private func binding(_ index: Int, _ key: String, default fallback: String) -> Binding<String> {
        Binding(get: { actions.indices.contains(index) ? actions[index][key]?.string ?? fallback : fallback },
                set: { value in update(index) { $0[key] = .string(value) } })
    }

    private func nestedBinding(_ index: Int, _ key: String, _ subkey: String) -> Binding<String> {
        Binding(get: { actions.indices.contains(index) ? actions[index][key]?.object?[subkey]?.string ?? "" : "" },
                set: { value in update(index) { $0[key] = .object([subkey: .string(value)]) } })
    }

    private func keycode(_ index: Int) -> Binding<Int> {
        Binding(get: { Int(actions.indices.contains(index) ? actions[index]["keycode"]?.number ?? 0 : 0) },
                set: { value in update(index) { $0["keycode"] = .number(Double(value)) } })
    }

    /// Commands are stored as /bin/sh -c "<command>", shown as one field.
    private func isShellCommandForm(_ action: [String: JSONValue]) -> Bool {
        let exe = action["executablePath"]?.string ?? "/bin/sh"
        let args = action["shellArguments"]?.array?.compactMap { $0.string } ?? ["-c", ""]
        return exe == "/bin/sh" && args.count == 2 && args[0] == "-c"
    }

    private func shellCommand(_ index: Int) -> Binding<String> {
        Binding(get: { actions.indices.contains(index) ? actions[index]["shellArguments"]?.array?.last?.string ?? "" : "" },
                set: { value in update(index) {
                    $0["executablePath"] = .string("/bin/sh")
                    $0["shellArguments"] = .array([.string("-c"), .string(value)])
                } })
    }

    private func arguments(_ index: Int) -> Binding<String> {
        Binding(get: {
            guard actions.indices.contains(index) else { return "" }
            return actions[index]["shellArguments"]?.array?.compactMap { $0.string }.joined(separator: ", ") ?? ""
        }, set: { value in update(index) {
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            $0["shellArguments"] = .array(parts.map { .string($0) })
        } })
    }
}

// MARK: - Raw JSON

struct RawJSONEditor: View {
    @ObservedObject var item: EditorItem
    private let textState = State(initialValue: "")
    private let errorState = State<String?>(initialValue: nil)
    private var error: String? {
        get { errorState.wrappedValue }
        nonmutating set { errorState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: textState.projectedValue)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            if let error = error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption)
            }
            HStack {
                Button("Apply", action: apply).keyboardShortcut(.return, modifiers: .command)
                Button("Revert") { reload() }
                Spacer()
                Text("Every key is supported here, including ones without a control above.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear(perform: reload)
        .onChange(of: item.id) { _ in reload() }
    }

    private func reload() {
        textState.wrappedValue = item.json.pretty()
        error = nil
    }

    private func apply() {
        do {
            guard let object = try JSONValue.parse(textState.wrappedValue).object else {
                error = "An item must be a JSON object: { … }"
                return
            }
            guard object["type"]?.string != nil else {
                error = "The item needs a \"type\"."
                return
            }
            item.replaceAll(with: object)
            error = nil
        } catch {
            self.error = "Invalid JSON: \(error.localizedDescription)"
        }
    }
}
