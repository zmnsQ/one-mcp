import Foundation

/// Only explicit editor submission enters this state machine. Decoding old records
/// never creates a profile, starts a process, or changes credential permissions.
enum TunnelProfileCreation: String, Equatable {
    case submitted, running, succeeded, failed, unknown
    var isInFlight: Bool { self == .submitted || self == .running }
    var message: String {
        switch self {
        case .submitted: return "配置已保存，正在等待本地 Profile 创建结果…"
        case .running: return "正在创建本地 Profile；不会启动隧道。"
        case .succeeded: return "本地 Profile 已创建并保存，隧道尚未启动。"
        case .failed: return "配置已保留，但 Profile 创建未完成。检查下方错误；已有文件不会被覆盖，可改用已有 Profile 并检查连接。"
        case .unknown: return "创建结果尚未确认。请先恢复网关连接并检查已有 Profile，勿重复创建。配置已保留。"
        }
    }
    static func correlatedEvent(_ event: [String: Any], operationID: String) -> Self? {
        guard event["operationID"] as? String == operationID else { return nil }
        return self.event(event)
    }
    static func event(_ event: [String: Any]) -> Self? {
        guard event["action"] as? String == "init" else { return nil }
        if event["running"] as? Bool == true { return .running }
        if event["errorCode"] is String { return .failed }
        if let code = event["exitCode"] as? Int { return code == 0 ? .succeeded : .failed }
        return .unknown
    }
}
