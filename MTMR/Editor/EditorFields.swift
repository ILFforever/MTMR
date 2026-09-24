//
//  EditorFields.swift
//  Stripe
//
//  Reusable inspector rows, styled after System Settings: a label on the left,
//  a control on the right, grouped into collapsible rounded sections.
//

import SwiftUI

// Note on state: in current SDKs `@State` is a macro whose compiler plugin ships
// only with Xcode, not the Command Line Tools this project builds with. Views
// here declare `State<Value>` properties directly instead, which SwiftUI treats
// exactly like `@State` (it's what the wrapper expands to).

/// A collapsible group of rows in a rounded box, like a System Settings section.
struct InspectorSection<Content: View>: View {
    let title: String
    let symbol: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: symbol)
                        .foregroundColor(.accentColor)
                        .frame(width: 18)
                    Text(title).font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
        }
    }
}

/// Label on the left, control on the right, separator below.
struct FieldRow<Control: View>: View {
    let label: String
    var help: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let help = help {
                        Text(help).font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(width: 170, alignment: .leading)
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 7)
            Divider().opacity(0.5)
        }
    }
}

struct TextFieldRow: View {
    let label: String
    var placeholder = ""
    var help: String? = nil
    @Binding var text: String

    var body: some View {
        FieldRow(label: label, help: help) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// A number field that keeps what the user types (e.g. "1.") while editing and
/// only writes valid numbers back. Empty means "not set".
struct NumberFieldRow: View {
    let label: String
    var placeholder = ""
    var help: String? = nil
    @Binding var value: Double?
    private let textState = State(initialValue: "")
    private var text: String {
        get { textState.wrappedValue }
        nonmutating set { textState.wrappedValue = newValue }
    }

    var body: some View {
        FieldRow(label: label, help: help) {
            TextField(placeholder, text: textState.projectedValue)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
                .onAppear { text = value.map(NumberFieldRow.format) ?? "" }
                .onChange(of: text) { newText in
                    let trimmed = newText.trimmingCharacters(in: .whitespaces)
                    // Only write real changes; setting the initial text must not save.
                    if trimmed.isEmpty {
                        if value != nil { value = nil }
                    } else if let number = Double(trimmed), number != value {
                        value = number
                    }
                }
        }
    }

    static func format(_ value: Double) -> String {
        return value.rounded() == value ? String(Int64(value)) : String(value)
    }
}

/// A switch that shows the default when the key isn't set.
struct ToggleRow: View {
    let label: String
    var help: String? = nil
    let defaultValue: Bool
    @Binding var value: Bool?

    var body: some View {
        FieldRow(label: label, help: help) {
            Toggle("", isOn: Binding(get: { value ?? defaultValue }, set: { value = $0 }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct ChoiceRow: View {
    let label: String
    let options: [String]
    var defaultLabel = "Default"
    @Binding var value: String

    var body: some View {
        FieldRow(label: label) {
            Picker("", selection: $value) {
                Text(defaultLabel).tag("")
                ForEach(options, id: \.self) { Text($0.capitalizedFirst).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }
}

struct MultilineRow: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            Divider().opacity(0.5)
        }
        .padding(.vertical, 7)
    }
}

/// A color well plus a text field that accepts hex ("#FF9500") or a system
/// color name ("orange"), with a button to clear back to the default.
struct ColorRow: View {
    let label: String
    @Binding var value: String

    var body: some View {
        FieldRow(label: label) {
            HStack(spacing: 6) {
                TextField("Default", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: value.namedOrHexColor ?? .clear) },
                    set: { value = NSColor($0).hexString }
                ), supportsOpacity: false)
                    .labelsHidden()
                if !value.isEmpty {
                    Button(action: { value = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Use the default")
                }
            }
        }
    }
}

/// A text field for an SF Symbol name with a live preview and a picker grid.
struct SymbolRow: View {
    let label: String
    @Binding var value: String
    private let showingPicker = State(initialValue: false)

    var body: some View {
        FieldRow(label: label, help: "Any SF Symbol name") {
            HStack(spacing: 6) {
                Image(systemName: value.isEmpty ? "square.dashed" : value)
                    .frame(width: 22)
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                TextField("None", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 170)
                Button("Choose…") { showingPicker.wrappedValue.toggle() }
                    .popover(isPresented: showingPicker.projectedValue, arrowEdge: .bottom) {
                        SymbolPicker(selection: $value, isPresented: showingPicker.projectedValue)
                    }
            }
        }
    }
}

struct SymbolPicker: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    private let filterState = State(initialValue: "")
    private var filter: String { filterState.wrappedValue }

    private var symbols: [String] {
        let all = ItemCatalog.suggestedSymbols
        return filter.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter", text: filterState.projectedValue).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    ForEach(symbols, id: \.self) { name in
                        Button(action: { selection = name; isPresented = false }) {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 32)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(selection == name ? Color.accentColor.opacity(0.3) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 230)
        }
        .padding(12)
        .frame(width: 350)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
