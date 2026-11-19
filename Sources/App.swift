import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DashboardStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID).count <= 1 else {
            NSApplication.shared.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("BurndownBar")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: Dashboard(store: store))
        popover.contentSize = NSSize(width: 398, height: 620)
        store.statusChanged = { [weak self] in self?.updateStatus() }
        store.start()
        // Show the dashboard on first launch so its location is immediately visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showPopover() }
    }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        button.title = store.statusPercent.map { " \($0)" } ?? (store.connectionError != nil ? " !" : "")
        button.toolTip = store.connectionError ?? "BurndownBar · \(store.healthyCount) of \(store.accounts.count) accounts ready · lowest quota remaining"
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh Quotas", action: #selector(refresh), keyEquivalent: "r")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit BurndownBar", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.now = Date()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func openDashboard() { showPopover() }
    @objc private func refresh() { Task { await store.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }
}

@main struct BurndownBar {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); return }
        if CommandLine.arguments.contains("--transport-tests") {
            Task { await TransportTests.run(); exit(0) }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--live-check") {
            Task { @MainActor in await LiveCheck.run(); exit(0) }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--render-previews") { PreviewRenderer.run(); return }
        if CommandLine.arguments.contains("--replace-running") {
            let existing = AppIdentity.allBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            existing.forEach { _ = $0.terminate() }
            let deadline = Date().addingTimeInterval(4)
            while existing.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
