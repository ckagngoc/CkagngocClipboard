import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import os

struct ClipboardEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, isPinned: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32
    var key: String

    static let defaultValue = Shortcut(
        keyCode: 9,
        modifiers: UInt32(controlKey | optionKey),
        key: "V"
    )

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }
}

enum ClipboardHistory {
    static func adding(
        _ text: String,
        to entries: [ClipboardEntry],
        limit: Int,
        date: Date = .now
    ) -> [ClipboardEntry]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard entries.first?.text != text else { return entries }

        var updatedEntries = entries
        if let existingIndex = updatedEntries.firstIndex(where: { $0.text == text }) {
            var existing = updatedEntries.remove(at: existingIndex)
            existing.createdAt = date
            updatedEntries.insert(existing, at: 0)
        } else {
            updatedEntries.insert(ClipboardEntry(text: text, createdAt: date), at: 0)
        }

        updatedEntries.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }

        while updatedEntries.count > limit {
            if let oldestUnpinned = updatedEntries.lastIndex(where: { !$0.isPinned }) {
                updatedEntries.remove(at: oldestUnpinned)
            } else {
                updatedEntries.removeLast()
            }
        }
        return updatedEntries
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]
    @Published private(set) var shortcut: Shortcut
    @Published var shortcutError: String?

    private let defaults: UserDefaults
    private let hotKey: GlobalHotKey
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
        category: "ClipboardHistory"
    )
    private var pollTimer: Timer?
    private let historyKey = "clipboardHistory"
    private let shortcutKey = "clipboardShortcut"
    private let maximumEntryCount = 100
    private var lastChangeCount: Int

    init(
        defaults: UserDefaults = .standard,
        hotKey: GlobalHotKey? = nil
    ) {
        self.defaults = defaults
        let hotKey = hotKey ?? GlobalHotKey()
        self.hotKey = hotKey
        self.entries = Self.loadEntries(from: defaults, key: "clipboardHistory")
        self.shortcut = Self.loadShortcut(from: defaults, key: "clipboardShortcut")
        self.lastChangeCount = NSPasteboard.general.changeCount

        hotKey.onPress = { [weak self] in
            NotificationCenter.default.post(name: .toggleClipboardPopover, object: nil)
            self?.shortcutError = nil
        }
        do {
            try registerShortcut()
        } catch {
            shortcutError = error.localizedDescription
        }
        if let currentText = NSPasteboard.general.string(forType: .string) {
            capture(currentText)
        }
        startMonitoring()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func capture(_ text: String) {
        guard let updatedEntries = ClipboardHistory.adding(
            text,
            to: entries,
            limit: maximumEntryCount
        ), updatedEntries != entries else { return }
        entries = updatedEntries
        persistEntries()
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        entries.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        persistEntries()
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
    }

    func clear() {
        entries.removeAll()
        persistEntries()
    }

    func setShortcut(_ newShortcut: Shortcut) throws {
        let previousShortcut = shortcut
        shortcut = newShortcut
        do {
            try registerShortcut()
            defaults.set(try JSONEncoder().encode(newShortcut), forKey: shortcutKey)
        } catch {
            shortcut = previousShortcut
            try? registerShortcut()
            throw error
        }
    }

    private func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.readPasteboardIfChanged()
            }
        }
    }

    private func readPasteboardIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        capture(text)
    }

    private func registerShortcut() throws {
        do {
            try hotKey.register(shortcut)
            shortcutError = nil
        } catch {
            shortcutError = error.localizedDescription
            throw error
        }
    }

    private func persistEntries() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: historyKey)
        } catch {
            logger.error("Unable to save clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadEntries(from defaults: UserDefaults, key: String) -> [ClipboardEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let entries = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            return entries.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
        } catch {
            Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
                category: "ClipboardHistory"
            ).error("Unable to read clipboard history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func loadShortcut(from defaults: UserDefaults, key: String) -> Shortcut {
        guard let data = defaults.data(forKey: key) else { return .defaultValue }
        do {
            return try JSONDecoder().decode(Shortcut.self, from: data)
        } catch {
            Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
                category: "ClipboardHistory"
            ).error("Unable to read clipboard shortcut: \(error.localizedDescription, privacy: .public)")
            return .defaultValue
        }
    }
}

extension Notification.Name {
    static let toggleClipboardPopover = Notification.Name("toggleClipboardPopover")
}
