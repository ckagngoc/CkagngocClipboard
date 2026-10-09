import AppKit
import Carbon.HIToolbox
import Combine
import CryptoKit
import Foundation
import os
import Security
import UniformTypeIdentifiers

struct ClipboardEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool
    var imageData: Data?
    var imagePasteboardType: String?
    var fileURLs: [URL]?

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, isPinned: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.imageData = nil
        self.imagePasteboardType = nil
        self.fileURLs = nil
    }

    init(
        id: UUID = UUID(),
        imageData: Data,
        pasteboardType: String,
        createdAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = "Hình ảnh"
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.imageData = imageData
        self.imagePasteboardType = pasteboardType
        self.fileURLs = nil
    }

    init(id: UUID = UUID(), fileURLs: [URL], createdAt: Date = .now, isPinned: Bool = false) {
        self.id = id
        self.text = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.imageData = nil
        self.imagePasteboardType = nil
        self.fileURLs = fileURLs
    }

    var isImage: Bool {
        imageData != nil
    }

    var isFile: Bool {
        !(fileURLs?.isEmpty ?? true)
    }

    func hasSameContent(as other: ClipboardEntry) -> Bool {
        if let imageData, let otherImageData = other.imageData {
            return imageData == otherImageData && imagePasteboardType == other.imagePasteboardType
        }
        if let fileURLs, let otherFileURLs = other.fileURLs {
            return fileURLs == otherFileURLs
        }
        return !isImage && !other.isImage && !isFile && !other.isFile && text == other.text
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
        _ entry: ClipboardEntry,
        to entries: [ClipboardEntry],
        limit: Int,
        date: Date = .now
    ) -> [ClipboardEntry]? {
        guard entry.isImage || entry.isFile
                || !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        if let latest = entries.first, latest.hasSameContent(as: entry) {
            return entries
        }

        var updatedEntries = entries
        if let existingIndex = updatedEntries.firstIndex(where: { $0.hasSameContent(as: entry) }) {
            var existing = updatedEntries.remove(at: existingIndex)
            existing.createdAt = date
            updatedEntries.insert(existing, at: 0)
        } else {
            var newEntry = entry
            newEntry.createdAt = date
            updatedEntries.insert(newEntry, at: 0)
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
    private let historyFileURL: URL?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
        category: "ClipboardHistory"
    )
    private var pollTimer: Timer?
    private let historyKey = "clipboardHistory"
    private let shortcutKey = "clipboardShortcut"
    private let maximumEntryCount = 100
    private var lastChangeCount: Int
    private var canPersistHistory: Bool

    init(
        defaults: UserDefaults = .standard,
        hotKey: GlobalHotKey? = nil
    ) {
        self.defaults = defaults
        let hotKey = hotKey ?? GlobalHotKey()
        self.hotKey = hotKey
        self.historyFileURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("CkagngocClipboard", isDirectory: true)
            .appendingPathComponent("history.plist")
        let loadedHistory = Self.loadEntries(
            from: defaults,
            key: "clipboardHistory",
            fileURL: historyFileURL
        )
        self.entries = loadedHistory.entries
        self.canPersistHistory = loadedHistory.canPersist
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
        if loadedHistory.needsEncryption {
            persistEntries()
        }
        captureCurrentPasteboard()
        startMonitoring()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func capture(_ text: String) {
        capture(ClipboardEntry(text: text))
    }

    func capture(_ entry: ClipboardEntry) {
        guard let updatedEntries = ClipboardHistory.adding(
            entry,
            to: entries,
            limit: maximumEntryCount
        ), updatedEntries != entries else { return }
        entries = updatedEntries
        persistEntries()
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        guard Self.write(entry, to: pasteboard) else {
            logger.error("Unable to restore clipboard entry \(entry.id.uuidString, privacy: .public)")
            return
        }
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
        captureCurrentPasteboard()
    }

    private func captureCurrentPasteboard() {
        guard let entry = Self.entry(from: NSPasteboard.general) else { return }
        capture(entry)
    }

    static func entry(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        if let fileURLs = Self.fileURLs(from: pasteboard), !fileURLs.isEmpty {
            return ClipboardEntry(fileURLs: fileURLs)
        }
        if let image = Self.image(from: pasteboard) {
            return image
        }
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return ClipboardEntry(text: text)
    }

    @discardableResult
    static func write(_ entry: ClipboardEntry, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        if let imageData = entry.imageData, let type = entry.imagePasteboardType {
            return pasteboard.setData(imageData, forType: NSPasteboard.PasteboardType(type))
        }
        if let fileURLs = entry.fileURLs, !fileURLs.isEmpty {
            return pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
        }
        return pasteboard.setString(entry.text, forType: .string)
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]
        return objects?.map { $0 as URL }.filter(\.isFileURL)
    }

    private static func image(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        for type in pasteboard.types ?? [] where UTType(type.rawValue)?.conforms(to: .image) == true {
            guard let data = pasteboard.data(forType: type) else { continue }
            return ClipboardEntry(imageData: data, pasteboardType: type.rawValue)
        }
        return nil
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
            guard canPersistHistory else { return }
            guard let historyFileURL else {
                throw ClipboardPersistenceError.applicationSupportUnavailable
            }
            try FileManager.default.createDirectory(
                at: historyFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try ClipboardHistoryEncryption.encrypt(encoder.encode(entries))
            try data.write(to: historyFileURL, options: .atomic)
            defaults.removeObject(forKey: historyKey)
        } catch {
            logger.error("Unable to save clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadEntries(
        from defaults: UserDefaults,
        key: String,
        fileURL: URL?
    ) -> (entries: [ClipboardEntry], needsEncryption: Bool, canPersist: Bool) {
        let data: Data?
        let isLegacyDefaultsData: Bool
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                data = try Data(contentsOf: fileURL)
                isLegacyDefaultsData = false
            } catch {
                Logger(
                    subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
                    category: "ClipboardHistory"
                ).error("Unable to read clipboard history file: \(error.localizedDescription, privacy: .public)")
                data = nil
                isLegacyDefaultsData = false
                return ([], false, false)
            }
        } else {
            data = defaults.data(forKey: key)
            isLegacyDefaultsData = true
        }
        guard let data else { return ([], false, true) }
        do {
            let isEncrypted = ClipboardHistoryEncryption.isEncrypted(data)
            let decodedData = isEncrypted ? try ClipboardHistoryEncryption.decrypt(data) : data
            let entries: [ClipboardEntry]
            if isLegacyDefaultsData {
                entries = try JSONDecoder().decode([ClipboardEntry].self, from: decodedData)
            } else {
                entries = try PropertyListDecoder().decode([ClipboardEntry].self, from: decodedData)
            }
            let sortedEntries = entries.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
            return (sortedEntries, !isEncrypted, true)
        } catch {
            Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "CkagngocClipboard",
                category: "ClipboardHistory"
            ).error("Unable to read clipboard history: \(error.localizedDescription, privacy: .public)")
            return ([], false, false)
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

private enum ClipboardPersistenceError: LocalizedError {
    case applicationSupportUnavailable
    case encryptionFailed
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "The application support directory is unavailable."
        case .encryptionFailed:
            "Clipboard history could not be encrypted."
        case .keychainFailure(let status):
            "The clipboard encryption key could not be accessed (error \(status))."
        }
    }
}

enum ClipboardHistoryEncryption {
    private static let marker = Data("CKGCH1".utf8)
    private static let keychainService =
        "\(Bundle.main.bundleIdentifier ?? "CkagngocClipboard").clipboard-history"
    private static let keychainAccount = "encryption-key"

    static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: marker)
    }

    static func encrypt(_ data: Data) throws -> Data {
        try encrypt(data, using: encryptionKey())
    }

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw ClipboardPersistenceError.encryptionFailed
        }
        return marker + combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        try decrypt(data, using: encryptionKey())
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard isEncrypted(data) else { return data }
        let combined = Data(data.dropFirst(marker.count))
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func encryptionKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        guard status == errSecItemNotFound else {
            throw ClipboardPersistenceError.keychainFailure(status)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        var addQuery = query
        addQuery.removeValue(forKey: kSecReturnData as String)
        addQuery.removeValue(forKey: kSecMatchLimit as String)
        addQuery[kSecValueData as String] = keyData
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return try encryptionKey()
        }
        guard addStatus == errSecSuccess else {
            throw ClipboardPersistenceError.keychainFailure(addStatus)
        }
        return key
    }
}

extension Notification.Name {
    static let toggleClipboardPopover = Notification.Name("toggleClipboardPopover")
}
