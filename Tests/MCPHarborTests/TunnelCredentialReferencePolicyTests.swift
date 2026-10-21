import Foundation
import XCTest
@testable import MCPHarbor

final class TunnelCredentialReferencePolicyTests: XCTestCase {
    private func record(_ id: String, account: String? = "work", source: String? = nil) -> TunnelRecord {
        TunnelRecord(id: id, name: id, accountID: account, credentialSourceRecordID: source)
    }
    private func saved(_ id: String) -> String? { id == "source" ? "work" : nil }

    func testOldRecordsRemainUnboundAndNewReferencesRoundTripWithoutSecrets() throws {
        let old = TunnelRecord(id: "old", name: "Old")
        let decodedOld = try JSONDecoder().decode(TunnelRecord.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decodedOld.accountID)
        XCTAssertNil(decodedOld.credentialSourceRecordID)
        let referenced = record("new", source: "source")
        let bytes = try JSONEncoder().encode(referenced)
        XCTAssertEqual(try JSONDecoder().decode(TunnelRecord.self, from: bytes), referenced)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["accountID"] as? String, "work")
        XCTAssertEqual(object["credentialSourceRecordID"] as? String, "source")
        XCTAssertNil(object["runtimeKey"])
        XCTAssertNil(object["apiKey"])
    }

    func testReuseRequiresExplicitSameAccountAndSavedLocalBinding() {
        let candidates = [record("source"), record("unbound", account: nil), record("other", account: "personal"),
                          record("session-only"), record("indirect", source: "source")]
        XCTAssertEqual(TunnelCredentialReferencePolicy.reusableRecords(for: " work ", records: candidates, savedAccountID: saved).map(\.id), ["source"])
        XCTAssertTrue(TunnelCredentialReferencePolicy.reusableRecords(for: "", records: candidates, savedAccountID: saved).isEmpty)
        XCTAssertTrue(TunnelCredentialReferencePolicy.reusableRecords(for: "Work", records: candidates, savedAccountID: saved).isEmpty)
        // A changed source account cannot silently relabel its existing saved key.
        XCTAssertTrue(TunnelCredentialReferencePolicy.reusableRecords(for: "personal", records: [record("source", account: "personal")], savedAccountID: saved).isEmpty)
    }

    func testReferenceRejectsUnknownDifferentRemovedAndUnrememberedSources() throws {
        let source = record("source")
        XCTAssertEqual(try TunnelCredentialReferencePolicy.source(for: record("new", source: "source"), in: [source], savedAccountID: saved), source)
        for target in [record("new", account: nil, source: "source"), record("new", account: "personal", source: "source"),
                       record("new", source: "missing"), record("new", source: ""), record("source", source: "source")] {
            XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: target, in: [source], savedAccountID: saved))
        }
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: record("new", source: "source"), in: [source], savedAccountID: { _ in nil }))
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: record("new", source: "source"), in: [source, source], savedAccountID: saved))
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: record("new", source: "source"), in: [record("source", account: nil)], savedAccountID: saved))
    }

    func testChainsCyclesAndNonOpenAITransportsAreRejected() {
        let target = record("new", source: "source")
        for source in [record("source", source: "third"), record("source", source: "new")] {
            XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: target, in: [source], savedAccountID: saved))
        }
        var cloud = record("source"); cloud.transport = "cloudflare"
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: target, in: [cloud], savedAccountID: saved))
        var cloudTarget = target; cloudTarget.transport = "cloudflare"
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.source(for: cloudTarget, in: [record("source")], savedAccountID: saved))
    }

    func testReferencedCredentialReadsSourceAtUseTimeNeverDestinationFallback() throws {
        let source = record("source"), target = record("new", source: "source")
        var ownReads = 0, sourceReads = 0
        var currentSource = "fake-first"
        func resolve() throws -> String {
            try TunnelCredentialReferencePolicy.resolveKey(for: target, in: [source], savedAccountID: saved,
                ownKey: { ownReads += 1; return "fake-stale-destination" },
                readSource: { chosen in
                    XCTAssertEqual(chosen.id, source.id); sourceReads += 1; return currentSource
                })
        }
        XCTAssertEqual(try resolve(), "fake-first")
        currentSource = "fake-rotated"
        XCTAssertEqual(try resolve(), "fake-rotated")
        XCTAssertEqual(sourceReads, 2)
        XCTAssertEqual(ownReads, 0)
    }

    func testMissingDeniedAndMismatchedReferencesNeverFallbackOrExposeErrorText() {
        let source = record("source"), target = record("new", source: "source")
        var ownReads = 0, sourceReads = 0
        for value: String? in [nil, ""] {
            XCTAssertThrowsError(try TunnelCredentialReferencePolicy.resolveKey(for: target, in: [source], savedAccountID: saved,
                ownKey: { ownReads += 1; return "stale" }, readSource: { _ in value })) { error in
                    XCTAssertEqual(error as? TunnelCredentialReferenceError, .sourceUnavailable)
                }
        }
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.resolveKey(for: target, in: [source], savedAccountID: saved,
            ownKey: { ownReads += 1; return "stale" },
            readSource: { _ in throw NSError(domain: "fake-sensitive-detail", code: 1) })) { error in
                XCTAssertFalse(error.localizedDescription.contains("fake-sensitive-detail"))
            }
        XCTAssertThrowsError(try TunnelCredentialReferencePolicy.resolveKey(for: record("new", account: "personal", source: "source"), in: [source], savedAccountID: saved,
            ownKey: { ownReads += 1; return "stale" }, readSource: { _ in sourceReads += 1; return "secret" }))
        XCTAssertEqual(ownReads, 0)
        XCTAssertEqual(sourceReads, 0)
    }

    func testOwnLegacyRecordStillUsesOwnCredentialPath() throws {
        var sourceReads = 0
        let key = try TunnelCredentialReferencePolicy.resolveKey(for: record("old", account: nil), in: [], savedAccountID: { _ in nil },
            ownKey: { "fake-legacy" }, readSource: { _ in sourceReads += 1; return nil })
        XCTAssertEqual(key, "fake-legacy")
        XCTAssertEqual(sourceReads, 0)
    }

    func testExternalAccountChangesInvalidateExistingSessionKeys() {
        XCTAssertTrue(TunnelCredentialReferencePolicy.sessionAccountMatches("work", record: record("source")))
        XCTAssertFalse(TunnelCredentialReferencePolicy.sessionAccountMatches("work", record: record("source", account: "personal")))
        XCTAssertFalse(TunnelCredentialReferencePolicy.sessionAccountMatches("work", record: record("source", account: nil)))
        XCTAssertFalse(TunnelCredentialReferencePolicy.sessionAccountMatches(nil, record: record("source", account: "work")))
        XCTAssertTrue(TunnelCredentialReferencePolicy.sessionAccountMatches(nil, record: record("legacy", account: nil)))
    }

    func testAccountLabelsAreConservativeAndBounded() {
        XCTAssertNil(TunnelCredentialReferencePolicy.normalizedAccountID(nil))
        XCTAssertNil(TunnelCredentialReferencePolicy.normalizedAccountID(" \n "))
        XCTAssertNil(TunnelCredentialReferencePolicy.normalizedAccountID("work\0other"))
        XCTAssertNil(TunnelCredentialReferencePolicy.normalizedAccountID(String(repeating: "a", count: 101)))
        XCTAssertEqual(TunnelCredentialReferencePolicy.normalizedAccountID("  My work account  "), "My work account")
    }
}
