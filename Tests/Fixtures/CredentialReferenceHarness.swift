import Foundation

@MainActor final class HarborStore {
    var preferences = Preferences()
    var currentWorkspaceID = "fixture-" + UUID().uuidString
    var tunnelKey = ""
    var tunnelCredentialStatus = ""
    var recordTunnelKeys: [String: String] = [:]
    var recordTunnelKeyAccountIDs: [String: String] = [:]
}
// Fake-only vault. This harness never links the real SecretVault implementation.
enum SecretVault {
    static var values: [String: String] = [:]
    static var reads: [String] = []
    static var writes: [String] = []
    static func read(account: String, allowInteraction: Bool = true) throws -> String? {
        reads.append(account); return values[account]
    }
    static func write(_ value: String, account: String) throws { writes.append(account); values[account] = value }
    static func delete(account: String) throws { values.removeValue(forKey: account) }
}

@main struct CredentialIntegrationFixture {
    @MainActor static func main() throws {
        let store = HarborStore()
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(store.currentWorkspaceID) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        // An account label alone must not require a nonexistent stored credential.
        let profileOnly = TunnelRecord(id: "profile-only", profileFile: "/fake/existing-profile", accountID: "work")
        store.preferences.tunnelRecords = [profileOnly]
        store.clearRecordTunnelKeyForAccountChange(profileOnly.id)
        let blankProfileKey = try store.resolveRecordTunnelKey(profileOnly)
        assert(blankProfileKey.isEmpty)
        var source = TunnelRecord(id: "source", accountID: "work")
        let target = TunnelRecord(id: "target", accountID: "work", credentialSourceRecordID: "source")
        store.preferences.tunnelRecords = [source, target]
        store.setRecordTunnelKey("fake-saved", for: source.id)
        assert(store.saveRecordTunnelKey(source.id))
        assert(store.reusableCredentialRecords(for: "work").map(\.id) == ["source"])
        let writes = SecretVault.writes.count
        assert(store.associateRecordCredentialWithAccount(source.id))
        assert(SecretVault.writes.count == writes && SecretVault.reads.isEmpty)
        let resolved = try store.resolveRecordTunnelKey(target); assert(resolved == "fake-saved")
        assert(store.recordTunnelKeys[target.id] == nil)
        assert(store.loadRecordTunnelKey(target.id) == false)
        assert(store.recordTunnelKeys[target.id] == "")
        // Configuration-only mutation cannot reuse the old session under another account.
        store.setRecordTunnelKey("fake-session", for: source.id)
        source.accountID = "personal"; store.preferences.tunnelRecords![0] = source
        do { _ = try store.resolveRecordTunnelKey(source); fatalError("stale session was reused") }
        catch { assert(error as? TunnelCredentialReferenceError == .accountChanged) }
        assert(store.reusableCredentialRecords(for: "personal").isEmpty)
        assert(store.recordTunnelKeyForEditing(source.id).isEmpty)
        assert(!store.saveRecordTunnelKey(source.id))
        let readsBeforeMismatch = SecretVault.reads.count
        do { _ = try store.resolveRecordTunnelKey(target); fatalError("cross-account source read") }
        catch { assert(error as? TunnelCredentialReferenceError == .accountMismatch) }
        assert(SecretVault.reads.count == readsBeforeMismatch)
        store.clearRecordTunnelKeyForAccountChange(source.id)
        assert(store.associateRecordCredentialWithAccount(source.id))
        assert(store.reusableCredentialRecords(for: "personal").map(\.id) == ["source"])
        store.forgetRecordTunnelKey(source.id)
        assert(store.reusableCredentialRecords(for: "personal").isEmpty)

        // Legacy opt-in remains unknown until explicit metadata-only association.
        let legacy = TunnelRecord(id: "aggregate", accountID: "work")
        let legacyTarget = TunnelRecord(id: "legacy-target", accountID: "work", credentialSourceRecordID: "aggregate")
        store.preferences.tunnelRecords = [legacy, legacyTarget]
        store.tunnelKey = "fake-legacy"
        store.saveAndRememberTunnelKey()
        assert(store.reusableCredentialRecords(for: "work").isEmpty)
        let legacyReads = SecretVault.reads.count, legacyWrites = SecretVault.writes.count
        assert(store.associateRecordCredentialWithAccount(legacy.id))
        assert(SecretVault.reads.count == legacyReads && SecretVault.writes.count == legacyWrites)
        let resolvedLegacy = try store.resolveRecordTunnelKey(legacyTarget); assert(resolvedLegacy == "fake-legacy")
        assert(SecretVault.reads.last == TunnelCredentialPolicy.account(workspace: store.currentWorkspaceID))
        store.tunnelKey = "fake-replacement"
        store.saveAndRememberTunnelKey()
        assert(store.reusableCredentialRecords(for: "work").isEmpty)
        do { _ = try store.resolveRecordTunnelKey(legacyTarget); fatalError("legacy replacement was silently reused") }
        catch { assert(error as? TunnelCredentialReferenceError == .sourceNotSaved) }
        assert(store.associateRecordCredentialWithAccount(legacy.id))
        store.forgetRememberedTunnelKey()
        assert(store.reusableCredentialRecords(for: "work").isEmpty)
        print("PASS production persistence against fake vault: explicit association without secret access, same-account use-time references, stale-session rejection, forget and legacy replacement invalidation")
    }
}
