import SwiftUI

/// The template-variable selector bar shown at the top of a dashboard.
/// Honors each variable's `hide` mode and edits custom/interval/textbox
/// variables in place; query, datasource, and multi-value variables are
/// shown read-only (their values still flow to panels).
struct VariableBar: View {
    @ObservedObject var viewModel: DashboardDetailViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.variables) { variable in
                    VariableControl(variable: variable, viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}

private struct VariableControl: View {
    let variable: TemplateVariable
    @ObservedObject var viewModel: DashboardDetailViewModel

    var body: some View {
        HStack(spacing: 6) {
            if variable.hideMode == 0 {
                Text(variable.displayLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        if variable.type == "textbox" && variable.isEditable {
            TextboxControl(variable: variable, viewModel: viewModel)
        } else if variable.isEditable {
            menuControl
        } else {
            chipLabel(text: readOnlyText, editable: false)
        }
    }

    private var selectedValue: String {
        viewModel.selections[variable.name]?.first ?? variable.defaultValues.first ?? ""
    }

    private var selectedDisplay: String {
        if let option = variable.resolvedOptions.first(where: { $0.rawValue == selectedValue }) {
            return option.displayText
        }
        return selectedValue.isEmpty ? "—" : selectedValue
    }

    private var readOnlyText: String {
        let values = viewModel.selections[variable.name] ?? variable.defaultValues
        return values.isEmpty ? "—" : values.joined(separator: " + ")
    }

    private var menuControl: some View {
        Menu {
            ForEach(variable.resolvedOptions, id: \.self) { option in
                Button {
                    HapticManager.selection()
                    viewModel.updateSelection(variable, values: [option.rawValue])
                } label: {
                    if option.rawValue == selectedValue {
                        Label(option.displayText, systemImage: "checkmark")
                    } else {
                        Text(option.displayText)
                    }
                }
            }
        } label: {
            chipLabel(text: selectedDisplay, editable: true)
        }
    }

    private func chipLabel(text: String, editable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Image(systemName: editable ? "chevron.up.chevron.down" : "lock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TextboxControl: View {
    let variable: TemplateVariable
    @ObservedObject var viewModel: DashboardDetailViewModel
    @State private var text: String = ""

    var body: some View {
        TextField(variable.displayLabel, text: $text)
            .font(.caption)
            .textFieldStyle(.plain)
            .frame(minWidth: 80, maxWidth: 160)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .submitLabel(.done)
            .onSubmit { viewModel.updateSelection(variable, values: [text]) }
            .onAppear {
                text = viewModel.selections[variable.name]?.first ?? variable.defaultValues.first ?? ""
            }
    }
}
