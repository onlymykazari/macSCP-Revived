//
//  BreadcrumbView.swift
//  macSCP
//
//  Finder-style path bar for the file browser
//

import SwiftUI

struct BreadcrumbView: View {
    let components: [PathComponent]
    let onNavigate: (String) -> Void

    var isEditingPath = false
    var currentPath = "/"
    var isGoToEnabled = true
    var onGoToPath: (String) -> Void = { _ in }
    var onEditPath: () -> Void = {}
    var onCancelPathEdit: () -> Void = {}

    private let goToFolderHoverID = "go-to-folder"

    @State private var hoveredID: String?

    var body: some View {
        Group {
            if isEditingPath {
                goToPathBar
            } else {
                breadcrumbBar
            }
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Root
                        pathButton(icon: "externaldrive.fill", path: "/", isLast: components.isEmpty)

                        ForEach(components) { component in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 1)

                            pathButton(text: component.name, path: component.path, isLast: component.path == components.last?.path)
                                .id(component.path)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .onChange(of: components) { _, newComponents in
                    if let lastPath = newComponents.last?.path {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(lastPath, anchor: .trailing)
                        }
                    }
                }
            }

            goToFolderButton
        }
    }

    // MARK: - Go to Path Bar

    private var goToPathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.forward.square")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            GoToPathField(
                initialPath: currentPath,
                onSubmit: onGoToPath,
                onCancel: onCancelPathEdit
            )

            Button {
                onCancelPathEdit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel (esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var goToFolderButton: some View {
        Button {
            onEditPath()
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hoveredID == goToFolderHoverID ? .primary : .tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hoveredID == goToFolderHoverID ? Color.primary.opacity(0.06) : .clear)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isGoToEnabled)
        .help("Go to Folder (⇧⌘G)")
        .onHover { hovering in
            hoveredID = hovering ? goToFolderHoverID : nil
        }
    }

    @ViewBuilder
    private func pathButton(icon: String? = nil, text: String? = nil, path: String, isLast: Bool) -> some View {
        let isHovered = hoveredID == path

        Button {
            onNavigate(path)
        } label: {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                } else if let text = text {
                    Text(text)
                        .font(.system(size: 12, weight: isLast ? .medium : .regular))
                }
            }
            .foregroundStyle(isLast ? .primary : .tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? path : nil
        }
    }
}

// MARK: - Go to Path Field

/// Finder-style path entry field: focuses and selects its content on appear,
/// submits on Return and cancels on Escape or focus loss.
private struct GoToPathField: NSViewRepresentable {
    let initialPath: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = initialPath
        field.placeholderString = "Enter a remote path, e.g. /var/www"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.delegate = context.coordinator
        context.coordinator.field = field

        // Focus once the field is mounted in a window
        DispatchQueue.main.async {
            context.coordinator.focusAndSelectAllIfNeeded()
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        context.coordinator.focusAndSelectAllIfNeeded()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onSubmit: (String) -> Void
        var onCancel: () -> Void
        var field: NSTextField?
        private var didFocus = false
        private var isFinishing = false

        init(onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func focusAndSelectAllIfNeeded() {
            guard !didFocus, let field, let window = field.window else { return }
            didFocus = true
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        @objc func submit() {
            finish()
            onSubmit(field?.stringValue ?? "")
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Focus moved elsewhere (Return and Escape set isFinishing first)
            guard !isFinishing else { return }
            finish()
            onCancel()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            finish()
            onCancel()
            return true
        }

        private func finish() {
            isFinishing = true
            field?.window?.makeFirstResponder(nil)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        BreadcrumbView(
            components: [],
            onNavigate: { _ in }
        )

        Divider()

        BreadcrumbView(
            components: [
                PathComponent(name: "home", path: "/home"),
                PathComponent(name: "user", path: "/home/user"),
                PathComponent(name: "documents", path: "/home/user/documents")
            ],
            onNavigate: { _ in }
        )

        Divider()

        BreadcrumbView(
            components: [
                PathComponent(name: "var", path: "/var"),
                PathComponent(name: "www", path: "/var/www"),
                PathComponent(name: "html", path: "/var/www/html"),
                PathComponent(name: "myproject", path: "/var/www/html/myproject"),
                PathComponent(name: "src", path: "/var/www/html/myproject/src")
            ],
            onNavigate: { _ in }
        )

        Divider()

        BreadcrumbView(
            components: [],
            onNavigate: { _ in },
            isEditingPath: true,
            currentPath: "/var/www/html",
            onGoToPath: { _ in },
            onEditPath: {},
            onCancelPathEdit: {}
        )
    }
    .frame(width: 400)
}
