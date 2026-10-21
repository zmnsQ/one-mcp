import Foundation

// No secrets in defaults. The service/account remains the legacy stable Keychain
// identity so rebuilding into a timestamped app directory does not change it.
struct TunnelCredentialPolicy {
    static func account(workspace: String) -> String { workspace + ":__tunnel_key" }
    static func preference(workspace: String) -> String { "OneMCP.autofillTunnelKey.v1." + workspace }
    static func shouldAutofill(enabled: Bool, current: String) -> Bool { enabled && current.isEmpty }
}

@MainActor extension HarborStore {
    var remembersTunnelKey: Bool { UserDefaults.standard.bool(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID)) }
    func saveAndRememberTunnelKey() {
        guard !tunnelKey.isEmpty else { tunnelCredentialStatus = "请先输入要保存的 Runtime API Key。"; return }
        do {
            try SecretVault.write(tunnelKey, account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID))
            invalidateLegacyRecordCredentialAssociations()
            UserDefaults.standard.set(true, forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID))
            tunnelCredentialStatus = "已保存到此 Mac 钥匙串；本工作空间下次打开会自动填入。"
        } catch { tunnelCredentialStatus = "未能保存到钥匙串。请检查系统授权后重试。" }
    }
    func autofillRememberedTunnelKey() {
        for record in preferences.effectiveTunnelRecords { loadRecordTunnelKey(record.id, allowInteraction: false) }
        tunnelCredentialStatus = remembersTunnelKey ? "已启用本工作空间自动填入。" : "仅本次会话使用。"
        guard TunnelCredentialPolicy.shouldAutofill(enabled: remembersTunnelKey, current: tunnelKey) else { return }
        do {
            if let value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID), allowInteraction: false) {
                tunnelKey = value; tunnelCredentialStatus = "已从本机钥匙串自动填入。"
            } else { tunnelCredentialStatus = "钥匙串中未找到已保存的密钥，请重新输入并保存。" }
        } catch { tunnelCredentialStatus = "钥匙串尚未允许当前版本读取。点击“从钥匙串载入”，按 macOS 提示授权。" }
    }
    func loadRememberedTunnelKey() {
        do {
            if let value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID)) {
                tunnelKey = value; tunnelCredentialStatus = "已从本机钥匙串载入。"
            } else { tunnelCredentialStatus = "本工作空间尚未保存 Runtime API Key。" }
        } catch { tunnelCredentialStatus = "钥匙串载入未完成，当前会话值保持不变。" }
    }
    func forgetRememberedTunnelKey() {
        do {
            try SecretVault.delete(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID))
            UserDefaults.standard.removeObject(forKey: TunnelCredentialPolicy.preference(workspace: currentWorkspaceID))
            invalidateLegacyRecordCredentialAssociations()
            tunnelKey = ""; tunnelCredentialStatus = "已忘记本工作空间的已存密钥。正在运行的隧道不受影响；服务端密钥未撤销。"
        } catch { tunnelCredentialStatus = "钥匙串删除未完成，自动填入设置保持不变。" }
    }
}

extension TunnelCredentialPolicy {
    static func account(workspace: String, record: String) -> String { workspace + ":__tunnel_record:" + record }
    static func preference(workspace: String, record: String) -> String { "OneMCP.autofillTunnelRecord.v1." + workspace + "." + record }
}

@MainActor extension HarborStore {
    private func recordCredentialPreference(_ id: String) -> String {
        TunnelCredentialPolicy.preference(workspace: currentWorkspaceID, record: id)
    }
    private func mayReadLegacyRecordCredential(_ id: String) -> Bool {
        !UserDefaults.standard.bool(forKey: recordCredentialPreference(id) + ".ignoreLegacy") &&
        (id == "aggregate" || preferences.servers.contains(where: { $0.id == id }))
    }
    private func recordCredentialNeedsAssociation(_ record: TunnelRecord) -> Bool {
        let base = recordCredentialPreference(record.id)
        if UserDefaults.standard.bool(forKey: base + ".needsAccountAssociation") { return true }
        if let bound = UserDefaults.standard.string(forKey: base + ".accountID") {
            return bound != TunnelCredentialReferencePolicy.normalizedAccountID(record.accountID)
        }
        return TunnelCredentialReferencePolicy.normalizedAccountID(record.accountID) != nil &&
            (UserDefaults.standard.bool(forKey: base) || (mayReadLegacyRecordCredential(record.id) && remembersTunnelKey))
    }
    private func savedRecordCredentialAccountID(_ id: String) -> String? {
        let base = recordCredentialPreference(id)
        guard UserDefaults.standard.bool(forKey: base),
              !UserDefaults.standard.bool(forKey: base + ".needsAccountAssociation"),
              let account = TunnelCredentialReferencePolicy.normalizedAccountID(UserDefaults.standard.string(forKey: base + ".accountID")) else { return nil }
        let origin = UserDefaults.standard.string(forKey: base + ".origin") ?? "record"
        guard origin == "record" || (origin == "legacy" && remembersTunnelKey && mayReadLegacyRecordCredential(id)) else { return nil }
        return account
    }
    func reusableCredentialRecords(for accountID: String) -> [TunnelRecord] {
        TunnelCredentialReferencePolicy.reusableRecords(for: accountID, records: preferences.effectiveTunnelRecords,
                                                        savedAccountID: savedRecordCredentialAccountID)
    }

    /// UI drafts must never re-label an old cached value after configuration reload.
    func sessionRecordTunnelKey(_ record: TunnelRecord) -> String {
        guard record.credentialSourceRecordID == nil,
              TunnelCredentialReferencePolicy.sessionAccountMatches(recordTunnelKeyAccountIDs[record.id], record: record) else { return "" }
        return recordTunnelKeys[record.id] ?? ""
    }
    func recordTunnelKeyForEditing(_ id: String) -> String {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == id }) else { return "" }
        return sessionRecordTunnelKey(record)
    }

    func setRecordTunnelKey(_ value: String, for id: String) {
        recordTunnelKeys[id] = value
        if value.isEmpty { recordTunnelKeyAccountIDs.removeValue(forKey: id) }
        else {
            let account = preferences.effectiveTunnelRecords.first(where: { $0.id == id })?.accountID
            recordTunnelKeyAccountIDs[id] = TunnelCredentialReferencePolicy.normalizedAccountID(account) ?? ""
        }
    }

    /// Non-secret metadata only. Call after explicit confirmation of which account
    /// owns this saved credential. No Keychain item is read, copied, moved or written.
    @discardableResult func associateRecordCredentialWithAccount(_ id: String) -> Bool {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == id }),
              record.transport == "openai", record.credentialSourceRecordID == nil,
              let account = TunnelCredentialReferencePolicy.normalizedAccountID(record.accountID) else {
            tunnelCredentialStatus = "请先保存账号标识，并在直接保存密钥的来源隧道上关联。"; return false
        }
        let base = recordCredentialPreference(id)
        let existingOrigin = UserDefaults.standard.string(forKey: base + ".origin") ?? "record"
        let origin: String
        if UserDefaults.standard.bool(forKey: base), existingOrigin == "record" {
            origin = "record"
        } else if mayReadLegacyRecordCredential(id), remembersTunnelKey {
            origin = "legacy"
        } else {
            tunnelCredentialStatus = "此隧道没有已启用记忆的密钥。请先输入密钥并保存到钥匙串。"; return false
        }
        UserDefaults.standard.set(account, forKey: base + ".accountID")
        UserDefaults.standard.set(origin, forKey: base + ".origin")
        UserDefaults.standard.set(true, forKey: base)
        UserDefaults.standard.removeObject(forKey: base + ".needsAccountAssociation")
        setRecordTunnelKey("", for: id)
        tunnelCredentialStatus = "已按你的确认关联账号。未读取或复制密钥；使用时仍须钥匙串授权。"
        return true
    }

    /// Preserve the existing Keychain item and opt-in so reassociation can be an
    /// explicit metadata-only action. Do not let cached/session keys cross accounts.
    func clearRecordTunnelKeyForAccountChange(_ id: String) {
        setRecordTunnelKey("", for: id)
        let base = recordCredentialPreference(id)
        let hasSavedCredential = UserDefaults.standard.bool(forKey: base) ||
            UserDefaults.standard.string(forKey: base + ".accountID") != nil ||
            UserDefaults.standard.string(forKey: base + ".origin") != nil ||
            (mayReadLegacyRecordCredential(id) && remembersTunnelKey)
        if hasSavedCredential { UserDefaults.standard.set(true, forKey: base + ".needsAccountAssociation") }
        else { UserDefaults.standard.removeObject(forKey: base + ".needsAccountAssociation") }
    }

    /// A workspace credential replacement is not proof it still belongs to any
    /// previously declared account. Require explicit reassociation of legacy refs.
    func invalidateLegacyRecordCredentialAssociations() {
        for record in preferences.effectiveTunnelRecords {
            if UserDefaults.standard.string(forKey: recordCredentialPreference(record.id) + ".origin") == "legacy" {
                clearRecordTunnelKeyForAccountChange(record.id)
            }
        }
    }

    @discardableResult func saveRecordTunnelKey(_ id: String, remember: Bool = true) -> Bool {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == id }),
              record.credentialSourceRecordID == nil else {
            tunnelCredentialStatus = "复用模式只保存引用，不会复制来源密钥。"; return false
        }
        guard let value = recordTunnelKeys[id], !value.isEmpty else { return false }
        guard TunnelCredentialReferencePolicy.sessionAccountMatches(recordTunnelKeyAccountIDs[id], record: record) else {
            tunnelCredentialStatus = TunnelCredentialReferenceError.accountChanged.localizedDescription; return false
        }
        do {
            try SecretVault.write(value, account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: id))
            let base = recordCredentialPreference(id)
            if remember { UserDefaults.standard.set(true, forKey: base) }
            UserDefaults.standard.set("record", forKey: base + ".origin")
            if let account = TunnelCredentialReferencePolicy.normalizedAccountID(record.accountID) {
                UserDefaults.standard.set(account, forKey: base + ".accountID")
            } else { UserDefaults.standard.removeObject(forKey: base + ".accountID") }
            UserDefaults.standard.removeObject(forKey: base + ".needsAccountAssociation")
            UserDefaults.standard.removeObject(forKey: base + ".ignoreLegacy")
            tunnelCredentialStatus = "此隧道密钥已保存到本机钥匙串。"
            return true
        } catch { tunnelCredentialStatus = "未能保存到钥匙串。"; return false }
    }

    /// Resolve references at use time without caching a source secret on another
    /// record. Same-account labels and local opt-in are checked before any read.
    func resolveRecordTunnelKey(_ record: TunnelRecord, allowInteraction: Bool = true) throws -> String {
        try TunnelCredentialReferencePolicy.resolveKey(for: record, in: preferences.effectiveTunnelRecords,
            savedAccountID: savedRecordCredentialAccountID,
            ownKey: {
                // An explicitly entered session key remains usable; account edits
                // must call clearRecordTunnelKeyForAccountChange before accepting it.
                if let value = recordTunnelKeys[record.id], !value.isEmpty {
                    guard TunnelCredentialReferencePolicy.sessionAccountMatches(recordTunnelKeyAccountIDs[record.id], record: record) else {
                        throw TunnelCredentialReferenceError.accountChanged
                    }
                    return value
                }
                if recordCredentialNeedsAssociation(record) { throw TunnelCredentialReferenceError.accountChanged }
                let base = recordCredentialPreference(record.id)
                guard UserDefaults.standard.bool(forKey: base) || (mayReadLegacyRecordCredential(record.id) && remembersTunnelKey) else { return "" }
                return try readOwnRecordTunnelKey(record, allowInteraction: allowInteraction) ?? ""
            },
            readSource: { source in
                let origin = UserDefaults.standard.string(forKey: recordCredentialPreference(source.id) + ".origin") ?? "record"
                let account = origin == "legacy" ? TunnelCredentialPolicy.account(workspace: currentWorkspaceID) :
                    TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: source.id)
                return try SecretVault.read(account: account, allowInteraction: allowInteraction)
            })
    }

    private func readOwnRecordTunnelKey(_ record: TunnelRecord, allowInteraction: Bool) throws -> String? {
        let base = recordCredentialPreference(record.id)
        if UserDefaults.standard.string(forKey: base + ".origin") == "legacy" {
            guard remembersTunnelKey, mayReadLegacyRecordCredential(record.id) else { return nil }
            return try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID), allowInteraction: allowInteraction)
        }
        var value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: record.id), allowInteraction: allowInteraction)
        // Preserve unbound legacy migration behavior. An account-bound credential
        // never falls back to a different legacy entry after deletion or denial.
        if value == nil, UserDefaults.standard.string(forKey: base + ".accountID") == nil, mayReadLegacyRecordCredential(record.id) {
            value = try SecretVault.read(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID), allowInteraction: allowInteraction)
        }
        return value
    }

    @discardableResult func loadRecordTunnelKey(_ id: String, allowInteraction: Bool = true) -> Bool {
        guard let record = preferences.effectiveTunnelRecords.first(where: { $0.id == id }) else { return false }
        guard record.credentialSourceRecordID == nil else {
            // Do not turn a reference into a copied session key.
            setRecordTunnelKey("", for: id)
            if allowInteraction { tunnelCredentialStatus = "此隧道直接引用来源密钥，运行时读取，不复制或自动填入。" }
            return false
        }
        guard !recordCredentialNeedsAssociation(record) else {
            if allowInteraction { tunnelCredentialStatus = TunnelCredentialReferenceError.accountChanged.localizedDescription }
            return false
        }
        let enabled = UserDefaults.standard.bool(forKey: recordCredentialPreference(id))
        let legacy = mayReadLegacyRecordCredential(id)
        guard allowInteraction || ((enabled || (legacy && remembersTunnelKey)) && (recordTunnelKeys[id] ?? "").isEmpty) else { return false }
        do {
            if let value = try readOwnRecordTunnelKey(record, allowInteraction: allowInteraction) {
                setRecordTunnelKey(value, for: id); tunnelCredentialStatus = "已从本机钥匙串载入。"
                return true
            }
        } catch { tunnelCredentialStatus = "钥匙串读取未完成；可点击载入并按 macOS 提示授权。" }
        return false
    }
    func forgetRecordTunnelKey(_ id: String) {
        do {
            try SecretVault.delete(account: TunnelCredentialPolicy.account(workspace: currentWorkspaceID, record: id))
            let base = recordCredentialPreference(id)
            for suffix in ["", ".accountID", ".origin", ".needsAccountAssociation"] { UserDefaults.standard.removeObject(forKey: base + suffix) }
            UserDefaults.standard.set(true, forKey: base + ".ignoreLegacy")
            setRecordTunnelKey("", for: id)
            tunnelCredentialStatus = "已删除此隧道的新格式密钥并取消引用资格；旧版工作空间密钥保留，服务端密钥未撤销。"
        } catch { tunnelCredentialStatus = "钥匙串删除未完成。" }
    }
}
