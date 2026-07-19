import Foundation

actor PortalOperationCoordinator {
    struct Snapshot {
        let sessionId: String
        let startedAt: Date
        let activeOperation: String?
        let lastSuccessfulAutomationAt: Date?
        let lastError: String?

        var isBusy: Bool { activeOperation != nil }
    }

    enum Error: Swift.Error {
        case busy(activeOperation: String)
    }

    static let shared = PortalOperationCoordinator()

    private let sessionId = UUID().uuidString
    private let startedAt = Date()
    private var activeOperation: (id: UUID, name: String)?
    private var lastSuccessfulAutomationAt: Date?
    private var lastError: String?

    func begin(_ name: String) throws -> UUID {
        if let activeOperation {
            throw Error.busy(activeOperation: activeOperation.name)
        }

        let id = UUID()
        activeOperation = (id: id, name: name)
        return id
    }

    func finish(_ id: UUID, error: Swift.Error? = nil) {
        guard activeOperation?.id == id else { return }

        activeOperation = nil
        if let error {
            lastError = error.localizedDescription
        } else {
            lastSuccessfulAutomationAt = Date()
            lastError = nil
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            sessionId: sessionId,
            startedAt: startedAt,
            activeOperation: activeOperation?.name,
            lastSuccessfulAutomationAt: lastSuccessfulAutomationAt,
            lastError: lastError
        )
    }
}
