import Foundation

/// Presentation state only: fed by the existing runtime event stream, never a new poller.
enum MenuBarStatus: Equatable {
    case running, ready, starting, stopping, stopped, checking, failed, unknown

    var title: String {
        switch self {
        case .running: return "运行中"
        case .ready: return "已就绪"
        case .starting: return "启动中"
        case .stopping: return "停止中"
        case .stopped: return "已停止"
        case .checking: return "检查中"
        case .failed: return "错误"
        case .unknown: return "状态未确认"
        }
    }
    var symbol: String {
        switch self {
        case .running, .ready: return "checkmark.circle.fill"
        case .starting, .checking: return "hourglass"
        case .stopping: return "pause.circle"
        case .stopped: return "stop.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    static func server(_ raw: String?) -> Self {
        switch raw {
        case "running": return .running
        case "starting": return .starting
        case "stopping": return .stopping
        case "stopped", nil: return .stopped
        case "error", "failed": return .failed
        default: return .unknown
        }
    }
    static func tunnel(event: [String: Any]) -> Self {
        if event["errorCode"] is String { return .failed }
        if let exitCode = event["exitCode"] as? Int, exitCode != 0 { return .failed }
        if event["running"] as? Bool == true {
            if event["state"] as? String == "Stopping" { return .stopping }
            if let action = event["action"] as? String, action == "doctor" || action == "init" { return .checking }
            return event["ready"] as? Bool == true ? .ready : .running
        }
        return event["running"] as? Bool == false ? .stopped : .unknown
    }
    static func gateway(_ raw: String) -> Self {
        switch raw {
        case "Ready · loopback only": return .ready
        case "Checking": return .checking
        case "Connecting", "Starting": return .starting
        case "Stopping": return .stopping
        case "Stopped", "Stopped (exit 0)": return .stopped
        case "Disconnected": return .unknown
        default: return raw.hasPrefix("Stopped (exit ") ? .failed : .unknown
        }
    }
}

@MainActor extension HarborStore {
    var menuGatewayStatus: MenuBarStatus { .gateway(gatewayState) }
    // A disconnected controller cannot certify the shared daemon has stopped.
    private var menuRuntimeKnown: Bool { gatewayReady || gatewayState == "Stopped" || gatewayState.hasPrefix("Stopped (exit ") }
    var menuServers: [SharedServerSummary] {
        var rows = preferences.servers.map { SharedServerSummary(id: $0.id, name: $0.name, running: false, allowedTools: [], permissionsKnown: false) }
        for server in sharedRuntimeServers where !rows.contains(where: { $0.id == server.id }) { rows.append(server) }
        return rows
    }
    var menuTunnelIDs: [String] {
        let configured = preferences.effectiveTunnelRecords.map(\.id)
        return configured + runningTunnelKeys.filter { !configured.contains($0) }.sorted()
    }
    func menuServerStatus(_ id: String) -> MenuBarStatus {
        guard menuRuntimeKnown else { return .unknown }
        if !gatewayReady { return .stopped }
        return .server(states[id])
    }
    func menuTunnelStatus(_ id: String) -> MenuBarStatus {
        guard menuRuntimeKnown else { return .unknown }
        if !gatewayReady { return .stopped }
        return tunnelMenuStates[id] ?? (runningTunnelKeys.contains(id) ? .running : .stopped)
    }
    func menuTunnelName(_ id: String) -> String {
        preferences.effectiveTunnelRecords.first(where: { $0.id == id })?.name ?? "运行中的隧道（\(id)）"
    }
}
