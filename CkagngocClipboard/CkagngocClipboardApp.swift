import AppKit
import SwiftUI

@main
struct CkagngocClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var store: ClipboardStore!
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var toggleObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = ClipboardStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "document.on.clipboard",
            accessibilityDescription: "Ckagngoc Clipboard"
        )
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self
        statusItem?.button?.toolTip = "Ckagngoc Clipboard"

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 590)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(
                store: store,
                onClose: { [weak self] in self?.popover.performClose(nil) },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        toggleObserver = NotificationCenter.default.addObserver(
            forName: .toggleClipboardPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.togglePopover()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        removeMouseMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let shouldClose = MainActor.assumeIsolated {
                self?.shouldClosePopover(at: NSEvent.mouseLocation) ?? false
            }
            if shouldClose {
                MainActor.assumeIsolated {
                    self?.popover.performClose(nil)
                }
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shouldClosePopover(at: NSEvent.mouseLocation) else { return }
                self.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeMouseMonitors()
    }

    private func shouldClosePopover(at point: NSPoint) -> Bool {
        guard let popoverFrame = popover.contentViewController?.view.window?.frame,
              !popoverFrame.contains(point)
        else {
            return false
        }
        return !statusButtonFrame.contains(point)
    }

    private var statusButtonFrame: NSRect {
        guard let button = statusItem?.button,
              let window = button.window
        else {
            return .zero
        }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeMouseMonitors()
        if let toggleObserver {
            NotificationCenter.default.removeObserver(toggleObserver)
        }
    }
}
