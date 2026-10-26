import SwiftUI

/// Presentation-only mailbox. Retains tray navigation until the main view exists.
/// No service commands, configuration writes or background work are performed.
@MainActor final class HarborNavigationRouter: ObservableObject {
    static let shared = HarborNavigationRouter()
    @Published var destination: String?
    private init() {}
}
