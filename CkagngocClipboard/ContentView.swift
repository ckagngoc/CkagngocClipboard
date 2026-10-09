import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void
    let onQuit: () -> Void

    @State private var searchText = ""
    @State private var showingFavorites = false
    @State private var showingSettings = false
    @State private var showingClearConfirmation = false
    @State private var showingQuitConfirmation = false

    private var visibleItems: [ClipboardEntry] {
        store.entries.filter { entry in
            (!showingFavorites || entry.isPinned)
                && (searchText.isEmpty || entry.text.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            filterBar

            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { entry in
                            ClipboardRow(
                                entry: entry,
                                onCopy: {
                                    store.copy(entry)
                                    onClose()
                                },
                                onTogglePin: { store.togglePin(entry) },
                                onDelete: { store.delete(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            footer
        }
        .frame(width: 420, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
        .confirmationDialog(
            "Xóa toàn bộ lịch sử clipboard?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xóa toàn bộ", role: .destructive) {
                store.clear()
            }
        } message: {
            Text("Thao tác này không thể hoàn tác.")
        }
        .confirmationDialog(
            "Thoát Ckagngoc Clipboard?",
            isPresented: $showingQuitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Thoát", role: .destructive, action: onQuit)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("CkagngocLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("Ckagngoc Clipboard")
                    .font(.system(size: 17, weight: .bold))
                Text("Văn bản, hình ảnh và tệp đã sao chép")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cài đặt")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm trong clipboard…", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("clipboardSearchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            filterButton("Gần đây", icon: "clock", selected: !showingFavorites) {
                showingFavorites = false
            }
            filterButton("Đã ghim", icon: "pin.fill", selected: showingFavorites) {
                showingFavorites = true
            }

            Spacer()

            Text("\(visibleItems.count) mục")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func filterButton(
        _ title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .background(
                    selected ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty
                 ? (showingFavorites ? "Chưa có mục nào được ghim" : "Clipboard đang trống")
                 : "Không tìm thấy kết quả")
                .font(.system(size: 14, weight: .semibold))
            Text(searchText.isEmpty
                 ? "Văn bản, hình ảnh và tệp bạn sao chép sẽ xuất hiện ở đây."
                 : "Thử tìm bằng từ khóa khác.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("clipboardEmptyState")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            Text("Chọn mục để chép lại, sau đó nhấn ⌘V")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Xóa lịch sử") {
                showingClearConfirmation = true
            }
            .disabled(store.entries.isEmpty)
            .buttonStyle(.plain)
            .foregroundStyle(store.entries.isEmpty ? Color.secondary : Color.red)
            .accessibilityIdentifier("clearHistoryButton")
            Button {
                showingQuitConfirmation = true
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Thoát Ckagngoc Clipboard")
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCopy) {
                HStack(spacing: 12) {
                    if entry.isImage, let data = entry.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: entry.isFile ? "doc.on.doc" : "text.alignleft")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 5) {
                            if entry.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(entry.isImage ? "Hình ảnh" : (entry.isFile ? "Tệp" : "Văn bản"))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(entry.createdAt, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clipboardEntry-\(entry.id.uuidString)")

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                rowAction(
                    icon: entry.isPinned ? "pin.slash" : "pin",
                    help: entry.isPinned ? "Bỏ ghim" : "Ghim",
                    action: onTogglePin
                )
                rowAction(icon: "doc.on.doc", help: "Chép lại", action: onCopy)
                if isHovering {
                    rowAction(icon: "trash", help: "Xóa mục này", action: onDelete)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.09 : 0.035), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
    }

    private func rowAction(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @Environment(\.dismiss) private var dismiss

    @State private var isRecordingShortcut = false
    @State private var recordingError: String?
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cài đặt")
                        .font(.system(size: 20, weight: .bold))
                    Text("Tùy chỉnh cách Ckagngoc Clipboard hoạt động.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Phím tắt mở Ckagngoc Clipboard", systemImage: "keyboard")
                    .font(.system(size: 13, weight: .semibold))

                Button {
                    isRecordingShortcut = true
                    recordingError = nil
                } label: {
                    HStack {
                        Text(isRecordingShortcut ? "Nhấn tổ hợp phím…" : store.shortcut.displayString)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: isRecordingShortcut ? "dot.radiowaves.left.and.right" : "pencil")
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recordShortcutButton")

                if let recordingError {
                    Text(recordingError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                } else if let shortcutError = store.shortcutError {
                    Text(shortcutError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                } else {
                    Text("Cần có ít nhất một phím bổ trợ như ⌘, ⌥, ⇧ hoặc ⌃.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Quyền riêng tư", systemImage: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lịch sử văn bản được lưu cục bộ trên máy Mac này, tối đa 100 mục. Bạn có thể xóa bất cứ lúc nào.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 380, height: 330)
        .onChange(of: isRecordingShortcut) { _, isRecording in
            if isRecording {
                installKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingShortcut else { return event }
            let modifiers = Shortcut.modifiers(from: event.modifierFlags)
            guard modifiers != 0 else {
                recordingError = "Hãy giữ ít nhất một phím bổ trợ khi chọn phím tắt."
                return nil
            }

            let key = event.charactersIgnoringModifiers?.uppercased() ?? "KEY"
            let shortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers, key: key)
            do {
                try store.setShortcut(shortcut)
                isRecordingShortcut = false
                recordingError = nil
            } catch {
                recordingError = "Không thể đăng ký phím tắt này. Hãy thử tổ hợp khác."
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
