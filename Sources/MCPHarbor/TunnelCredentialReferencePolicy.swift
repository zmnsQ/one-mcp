import Foundation

/// Decides whether a local saved credential may be reused, without reading secrets.
/// Labels are user declarations, not remote account verification. Never infer a label
/// from a tunnel ID, profile name, service name, or legacy workspace credential.
enum TunnelCredentialReferencePolicy {
    static func normalizedAccountID(_ value: String?) -> String? {
        guard let value else { return nil }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.utf16.count <= 100, !label.contains("\0") else { return nil }
        return label
    }

    static func reusableRecords(for accountID: String, records: [TunnelRecord],
                                savedAccountID: (String) -> String?) -> [TunnelRecord] {
        guard let account = normalizedAccountID(accountID) else { return [] }
        return records.filter {
            $0.transport == "openai" && $0.credentialSourceRecordID == nil &&
            normalizedAccountID($0.accountID) == account && savedAccountID($0.id) == account
        }
    }

    /// Session values are tied to the account in effect when they were entered or
    /// loaded. A configuration reload cannot silently move them to another account.
    static func sessionAccountMatches(_ boundAccountID: String?, record: TunnelRecord) -> Bool {
        (boundAccountID ?? "") == (normalizedAccountID(record.accountID) ?? "")
    }

    /// Reference lookup never falls back to a destination session value or another
    /// Keychain entry, even when the selected source is missing or access is denied.
    static func resolveKey(for record: TunnelRecord, in records: [TunnelRecord],
                           savedAccountID: (String) -> String?,
                           ownKey: () throws -> String,
                           readSource: (TunnelRecord) throws -> String?) throws -> String {
        guard let source = try source(for: record, in: records, savedAccountID: savedAccountID) else {
            return try ownKey()
        }
        do {
            guard let value = try readSource(source), !value.isEmpty else {
                throw TunnelCredentialReferenceError.sourceUnavailable
            }
            return value
        } catch { throw TunnelCredentialReferenceError.sourceUnavailable }
    }

    /// Resolves one explicit reference only. Chains, cycles, missing records, legacy
    /// unknown accounts, disabled opt-in and changed account bindings all fail closed.
    static func source(for record: TunnelRecord, in records: [TunnelRecord],
                       savedAccountID: (String) -> String?) throws -> TunnelRecord? {
        guard let sourceID = record.credentialSourceRecordID else { return nil }
        guard record.transport == "openai", !sourceID.isEmpty, sourceID != record.id else {
            throw TunnelCredentialReferenceError.invalidReference
        }
        guard let account = normalizedAccountID(record.accountID) else {
            throw TunnelCredentialReferenceError.unknownAccount
        }
        let matches = records.filter { $0.id == sourceID }
        guard matches.count == 1, let source = matches.first else {
            throw TunnelCredentialReferenceError.sourceNotFound
        }
        guard source.transport == "openai", source.credentialSourceRecordID == nil else {
            throw TunnelCredentialReferenceError.invalidReference
        }
        guard normalizedAccountID(source.accountID) == account else {
            throw TunnelCredentialReferenceError.accountMismatch
        }
        guard savedAccountID(source.id) == account else {
            throw TunnelCredentialReferenceError.sourceNotSaved
        }
        return source
    }
}

enum TunnelCredentialReferenceError: LocalizedError, Equatable {
    case invalidReference, unknownAccount, sourceNotFound, accountMismatch
    case sourceNotSaved, sourceUnavailable, accountChanged

    var errorDescription: String? {
        switch self {
        case .invalidReference: return "密钥引用无效。请选择同一账号下直接保存密钥的 OpenAI 隧道，不能引用自身或再次转引。"
        case .unknownAccount: return "请先明确设置本地账号标识，再复用已保存的密钥。"
        case .sourceNotFound: return "密钥来源隧道已移除或不唯一。请重新选择密钥来源。"
        case .accountMismatch: return "密钥来源与此隧道的账号标识不一致，未读取任何密钥。"
        case .sourceNotSaved: return "来源密钥未保存、已忘记或尚未明确关联到此账号。请检查来源隧道。"
        case .sourceUnavailable: return "未能读取来源隧道的已存密钥。请检查钥匙串项目和系统授权，不会改用其他密钥。"
        case .accountChanged: return "账号已更改。请明确关联已有钥匙串密钥，或输入并保存此账号的新密钥。"
        }
    }
}
