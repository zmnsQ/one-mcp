import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: HarborStore?
    func applicationWillTerminate(_ notification: Notification) { store?.configurationWatchTask?.cancel(); store?.releaseConfigurationLease(); store?.detachSharedGateway() }
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
        if store.isAttachedGateway { store.detachSharedGateway(); return .terminateNow }
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
            CommandGroup(after: .saveItem) { Button("保存配置") { store.save() }.keyboardShortcut("s") }
        }
        MenuBarExtra {
            Label { Text("网关 · " + store.menuGatewayStatus.title) } icon: { Image(nsImage: store.menuGatewayStatus.menuImage) }
            Divider()
            Section("MCP 服务（\(store.menuServers.count)）") {
                if store.menuServers.isEmpty { Text("尚未添加 MCP 服务") }
                ForEach(store.menuServers, id: \.id) { server in
                    Label { Text(server.name + " · " + store.menuServerStatus(server.id).title) } icon: { Image(nsImage: store.menuServerStatus(server.id).menuImage) }
                }
            }
            Section("隧道（\(store.menuTunnelIDs.count)）") {
                if store.menuTunnelIDs.isEmpty { Text("尚未添加隧道") }
                ForEach(store.menuTunnelIDs, id: \.self) { id in
                    Label { Text(store.menuTunnelName(id) + " · " + store.menuTunnelStatus(id).title) } icon: { Image(nsImage: store.menuTunnelStatus(id).menuImage) }
                }
            }
            Text("就绪不代表远端调用已验证")
            Divider()
            Button("打开 One MCP") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("停止全部连接") {
                let alert = NSAlert(); alert.messageText = "停止共享网关及全部连接？"
                alert.informativeText = "所有连接到此实例的 AI 和应用都会受到影响。"
                alert.addButton(withTitle: "停止"); alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn { store.shutdown() }
            }
            Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: BrandMark.menuBarImage).accessibilityLabel("One MCP")
        }
    }
}
