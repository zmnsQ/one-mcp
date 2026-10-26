import Foundation

/// Presentation only: following is explicit after a user scrolls, never inferred
/// from incoming log rows. IDs, not counts, detect arrivals at the buffer limit.
struct ServiceLogFollowState {
    private(set) var isFollowing = true
    private var unseenIDs: Set<UUID> = []
    var unseenCount: Int { unseenIDs.count }

    mutating func setFollowing(_ enabled: Bool) {
        isFollowing = enabled
        if enabled { resetUnread() }
    }

    mutating func resetUnread() { unseenIDs.removeAll() }

    mutating func receive(oldIDs: [UUID], newIDs: [UUID]) {
        guard !isFollowing else { resetUnread(); return }
        let current = Set(newIDs)
        unseenIDs.formIntersection(current)
        unseenIDs.formUnion(current.subtracting(Set(oldIDs)))
    }
}

/// Keep filter and row identity changes in a single observation transaction.
struct ServiceLogDisplaySnapshot: Equatable {
    let ids: [UUID]
    let errorsOnly: Bool
}
