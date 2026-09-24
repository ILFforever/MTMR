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

/// Shared measurements for the editor window.
enum EditorStyle {
    /// Inspector boxes and library tiles.
    static let boxRadius: CGFloat = 10
    /// The two bar pictures at the top of the window.
    static let barRadius: CGFloat = 10
    /// Free-text fields; wider ones are hard to scan against the labels.
    static let fieldWidth: CGFloat = 260
}

/// A small caption above each bar picture, with an optional hint on the right.
struct StageCaption: View {
    let title: String
    var live = false
    var hint: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if live {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Spacer()
            if let hint = hint {
                Text(hint).font(.system(size: 11)).foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 2)
    }
}

/// A native search field (magnifying glass, clear button, Esc to clear).
struct SearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context _: Context) {
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { text.wrappedValue = field.stringValue }
        }
    }
}

/// The window's sidebar material, as in Finder or System Settings.
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

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
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text(title).font(.system(size: 13, weight: .semibold))
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
                // Rows draw a divider below themselves; hide the last one.
                .padding(.bottom, -1)
                .clipped()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: EditorStyle.boxRadius).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: EditorStyle.boxRadius)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let help = help {
                        Text(help).font(.caption).foregroundColor(.secondary)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 12)
                control()
            }
            .frame(minHeight: 36)
            .padding(.vertical, 3)
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
                .frame(maxWidth: EditorStyle.fieldWidth)
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
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
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
            .fixedSize()
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
/// color name ("orange"). While unset it shows an empty swatch (not black, which
/// would look like a chosen color); clicking it starts from `suggested`.
struct ColorRow: View {
    let label: String
    @Binding var value: String
    var suggested = "#3A3A3C"

    var body: some View {
        FieldRow(label: label) {
            ColorControl(value: $value, suggested: suggested)
        }
    }
}

struct ColorControl: View {
    @Binding var value: String
    var suggested = "#3A3A3C"

    var body: some View {
        HStack(spacing: 6) {
            TextField("Default", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            Group {
                if value.isEmpty {
                    Button(action: { value = suggested }) {
                        Circle()
                            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Choose a color")
                } else {
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: value.namedOrHexColor ?? .clear) },
                        set: { value = NSColor($0).hexString }
                    ), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .frame(width: 44)
            Button(action: { value = "" }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Use the default")
            .opacity(value.isEmpty ? 0 : 1)
            .disabled(value.isEmpty)
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
                    .frame(width: 150)
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
        guard !filter.isEmpty else { return all }
        var matches = all.filter { $0.localizedCaseInsensitiveContains(filter) }
        // Any other SF Symbol can be used by typing its exact name.
        let typed = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !matches.contains(typed), NSImage(systemSymbolName: typed, accessibilityDescription: nil) != nil {
            matches.insert(typed, at: 0)
        }
        return matches
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search, or type any SF Symbol name", text: filterState.projectedValue).textFieldStyle(.roundedBorder)
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
