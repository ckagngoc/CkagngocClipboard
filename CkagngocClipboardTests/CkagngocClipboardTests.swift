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
            duplicate.text,
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

        #expect(ClipboardHistory.adding(" \n\t ", to: [latest], limit: 10) == nil)
        #expect(ClipboardHistory.adding("already copied", to: [latest], limit: 10) == [latest])
    }

    @Test func clipboardHistoryKeepsPinnedEntriesAndEnforcesLimit() {
        let pinned = ClipboardEntry(text: "pinned", createdAt: Date(timeIntervalSince1970: 1), isPinned: true)
        let older = ClipboardEntry(text: "older", createdAt: Date(timeIntervalSince1970: 2))
        let newer = ClipboardEntry(text: "newer", createdAt: Date(timeIntervalSince1970: 3))

        let updated = ClipboardHistory.adding(
            "latest",
            to: [pinned, newer, older],
            limit: 3,
            date: Date(timeIntervalSince1970: 4)
        )

        #expect(updated?.count == 3)
        #expect(updated?.first?.id == pinned.id)
        #expect(updated?.contains(where: { $0.text == "latest" }) == true)
        #expect(updated?.contains(where: { $0.text == "older" }) == false)
    }
}
