import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: HarborStore?
    func applicationWillTerminate(_ notification: Notification) { store?.configurationWatchTask?.cancel(); store?.releaseConfigurationLease() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        if store.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "退出前保存配置？"
            alert.informativeText = "配置包含尚未保存的修改。凭据仅在明确保存到 Keychain 后保留。"
            alert.addButton(withTitle: "保存并退出")
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "不保存")
            let result = alert.runModal()
            if result == .alertSecondButtonReturn { return .terminateCancel }
            if result == .alertFirstButtonReturn && !store.save() { return .terminateCancel }
        }
        guard store.anyProcessRunning else { return .terminateNow }
        store.shutdown()
        Task { @MainActor in
            for _ in 0..<150 {
                if !store.anyProcessRunning { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main struct MCPHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = HarborStore()
    var body: some Scene {
        WindowGroup("One MCP") {
            HarborView().environmentObject(store)
                .onAppear { delegate.store = store; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(after: .saveItem) { Button("Save Configuration") { store.save() }.keyboardShortcut("s") }
        }
        MenuBarExtra {
            Text(store.gatewayState)
            Button("Show One MCP") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("Stop All Connections") { store.shutdown() }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: BrandMark.menuBarImage).accessibilityLabel("One MCP")
        }
    }
}
