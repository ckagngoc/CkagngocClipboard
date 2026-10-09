import AppKit
import Carbon.HIToolbox
import Testing
@testable import CkagngocClipboard

struct CkagngocClipboardTests {

    @Test func shortcutShowsModifiersInMacOrder() {
        let shortcut = Shortcut(
            keyCode: 9,
            modifiers: UInt32(cmdKey | optionKey | shiftKey | controlKey),
            key: "V"
        )

        #expect(shortcut.displayString == "⌃⌥⇧⌘V")
    }

    @Test func shortcutModifiersIgnoreCapsLockAndFunctionFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .capsLock, .function]

        #expect(Shortcut.modifiers(from: flags) == UInt32(cmdKey | optionKey))
    }

    @Test func clipboardHistoryPreservesWhitespaceAndMovesDuplicatesToTop() {
        let previous = ClipboardEntry(text: "older", createdAt: Date(timeIntervalSince1970: 1))
        let duplicate = ClipboardEntry(text: "  keep spaces\n", createdAt: Date(timeIntervalSince1970: 2))

        let updated = ClipboardHistory.adding(
            duplicate,
            to: [previous, duplicate],
            limit: 10,
            date: Date(timeIntervalSince1970: 3)
        )

        #expect(updated?.first?.id == duplicate.id)
        #expect(updated?.first?.text == "  keep spaces\n")
        #expect(updated?.first?.createdAt == Date(timeIntervalSince1970: 3))
        #expect(updated?.count == 2)
    }

    @Test func clipboardHistoryIgnoresBlankTextAndRepeatedLatestItem() {
        let latest = ClipboardEntry(text: "already copied")

        #expect(ClipboardHistory.adding(ClipboardEntry(text: " \n\t "), to: [latest], limit: 10) == nil)
        #expect(ClipboardHistory.adding(ClipboardEntry(text: "already copied"), to: [latest], limit: 10) == [latest])
    }

    @Test func clipboardHistoryKeepsPinnedEntriesAndEnforcesLimit() {
        let pinned = ClipboardEntry(text: "pinned", createdAt: Date(timeIntervalSince1970: 1), isPinned: true)
        let older = ClipboardEntry(text: "older", createdAt: Date(timeIntervalSince1970: 2))
        let newer = ClipboardEntry(text: "newer", createdAt: Date(timeIntervalSince1970: 3))

        let updated = ClipboardHistory.adding(
            ClipboardEntry(text: "latest"),
            to: [pinned, newer, older],
            limit: 3,
            date: Date(timeIntervalSince1970: 4)
        )

        #expect(updated?.count == 3)
        #expect(updated?.first?.id == pinned.id)
        #expect(updated?.contains(where: { $0.text == "latest" }) == true)
        #expect(updated?.contains(where: { $0.text == "older" }) == false)
    }

    @Test func clipboardHistorySupportsImagesAndFiles() {
        let image = ClipboardEntry(imageData: Data([0, 1, 2]), pasteboardType: "public.png")
        let files = ClipboardEntry(fileURLs: [
            URL(fileURLWithPath: "/tmp/one.pdf"),
            URL(fileURLWithPath: "/tmp/two.png")
        ])

        let imageHistory = ClipboardHistory.adding(image, to: [], limit: 10)
        let fileHistory = ClipboardHistory.adding(files, to: [], limit: 10)

        #expect(imageHistory?.first?.isImage == true)
        #expect(imageHistory?.first?.imageData == Data([0, 1, 2]))
        #expect(fileHistory?.first?.isFile == true)
        #expect(fileHistory?.first?.fileURLs?.count == 2)
    }

    @MainActor
    @Test func clipboardEntryDecodesHistorySavedBeforeImagesAndFilesWereSupported() throws {
        let legacyJSON = Data(
            #"{"id":"00000000-0000-0000-0000-000000000001","text":"old item","createdAt":0,"isPinned":false}"#.utf8
        )

        let entry = try JSONDecoder().decode(ClipboardEntry.self, from: legacyJSON)

        #expect(entry.text == "old item")
        #expect(entry.imageData == nil)
        #expect(entry.fileURLs == nil)
        #expect(!entry.isImage)
        #expect(!entry.isFile)
    }

    @MainActor
    @Test func binaryHistoryStoragePreservesImageDataAndFileURLs() throws {
        let entries = [
            ClipboardEntry(imageData: Data([2, 4, 6]), pasteboardType: "public.png", isPinned: true),
            ClipboardEntry(fileURLs: [URL(fileURLWithPath: "/tmp/archive.zip")])
        ]
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        let encoded = try encoder.encode(entries)
        let decoded = try PropertyListDecoder().decode([ClipboardEntry].self, from: encoded)

        #expect(decoded == entries)
        #expect(encoded.first == 0x62)
    }

    @Test func clipboardHistoryIdentifiesRepeatedImagesAndFileLists() {
        let image = ClipboardEntry(imageData: Data([4, 5, 6]), pasteboardType: "public.png")
        let files = ClipboardEntry(fileURLs: [URL(fileURLWithPath: "/tmp/document.pdf")])

        #expect(ClipboardHistory.adding(image, to: [image], limit: 10) == [image])
        #expect(ClipboardHistory.adding(files, to: [files], limit: 10) == [files])
    }

    @MainActor
    @Test func pasteboardReaderCapturesImageData() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let imageData = Data([8, 7, 6])
        pasteboard.clearContents()
        #expect(pasteboard.setData(imageData, forType: .png))

        let entry = try #require(ClipboardStore.entry(from: pasteboard))

        #expect(entry.isImage)
        #expect(entry.imageData == imageData)
        #expect(entry.imagePasteboardType == NSPasteboard.PasteboardType.png.rawValue)
    }

    @MainActor
    @Test func pasteboardReaderCapturesMultipleFileURLs() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let urls = [
            URL(fileURLWithPath: "/tmp/one.pdf"),
            URL(fileURLWithPath: "/tmp/two.png")
        ]
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects(urls.map { $0 as NSURL }))

        let entry = try #require(ClipboardStore.entry(from: pasteboard))

        #expect(entry.isFile)
        #expect(entry.fileURLs == urls)
    }

    @MainActor
    @Test func pasteboardReaderFallsBackToText() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.setString("clipboard text", forType: .string))

        let entry = try #require(ClipboardStore.entry(from: pasteboard))

        #expect(!entry.isImage)
        #expect(!entry.isFile)
        #expect(entry.text == "clipboard text")
    }

    @MainActor
    @Test func restoringEntriesPreservesImageFileAndTextPasteboardTypes() throws {
        let imagePasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let image = ClipboardEntry(imageData: Data([1, 3, 5]), pasteboardType: "public.png")
        #expect(ClipboardStore.write(image, to: imagePasteboard))
        #expect(imagePasteboard.data(forType: .png) == image.imageData)

        let filePasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let files = ClipboardEntry(fileURLs: [URL(fileURLWithPath: "/tmp/recovered.txt")])
        #expect(ClipboardStore.write(files, to: filePasteboard))
        #expect(ClipboardStore.entry(from: filePasteboard)?.fileURLs == files.fileURLs)

        let textPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let text = ClipboardEntry(text: "restored text")
        #expect(ClipboardStore.write(text, to: textPasteboard))
        #expect(textPasteboard.string(forType: .string) == text.text)
    }
}
