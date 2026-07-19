import FlyingFox
import FlyingFoxMacros
import Foundation

struct LaunchAppBody: Decodable {
    let bundleIdentifier: String
}

struct LaunchAppResponse: Encodable {
    let message: String
}

struct TapBody: Decodable {
    let rect: String
    let count: Int?
    let longPress: Bool?
}

struct SwipeBody: Decodable {
    let x1: CGFloat
    let y1: CGFloat
    let x2: CGFloat
    let y2: CGFloat
    let durationMs: Double?
}

struct GestureResponse: Encodable {
    let message: String
}

struct ErrorResponse: Encodable {
    let error: String
    let code: String
    let retryable: Bool
}

struct TypeBody: Decodable {
    let rect: String?
    let text: String
    let clear: Bool?
}

struct KeyBody: Decodable {
    let key: Int
}

struct DateResponse: Encodable {
    let date: String
}

struct ScreenBounds: Encodable {
    let width: CGFloat
    let height: CGFloat
}

struct DeviceContext: Encodable {
    let screen_bounds: ScreenBounds
}

struct StateFullPhoneState: Encodable {
    let currentApp: String
    let packageName: String
    let keyboardVisible: Bool
    let isEditable: Bool
    let focusedElement: FocusedElement?
}

struct StateFullResponse: Encodable {
    let a11y_tree: String
    let phone_state: StateFullPhoneState
    let device_context: DeviceContext
}

struct HealthResponse: Encodable {
    let status: String
    let sessionId: String
    let startedAt: String
    let uptimeSeconds: Int
    let currentBundleIdentifier: String
    let busy: Bool
    let activeOperation: String?
    let lastSuccessfulAutomationAt: String?
    let lastError: String?
}

private enum PortalRequestError: LocalizedError {
    case busy(activeOperation: String)
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case .busy(let activeOperation):
            return "The portal is busy with \(activeOperation)."
        case .invalidRequest(let message):
            return message
        }
    }
}

@HTTPHandler
struct DroidrunPortalHandler {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func jsonResponse<T: Encodable>(
        _ body: T,
        statusCode: HTTPStatusCode = .ok
    ) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        return try HTTPResponse(
            statusCode: statusCode,
            headers: [.contentType: "application/json"],
            body: encoder.encode(body)
        )
    }

    private func errorResponse(_ error: Swift.Error) -> HTTPResponse {
        let response: ErrorResponse
        let statusCode: HTTPStatusCode

        switch error {
        case PortalRequestError.busy:
            response = ErrorResponse(
                error: error.localizedDescription,
                code: "portal_busy",
                retryable: true
            )
            statusCode = .conflict
        case PortalRequestError.invalidRequest:
            response = ErrorResponse(
                error: error.localizedDescription,
                code: "invalid_request",
                retryable: false
            )
            statusCode = .badRequest
        case let toolError as DroidrunPortalTools.Error:
            response = ErrorResponse(
                error: toolError.localizedDescription,
                code: "automation_unavailable",
                retryable: true
            )
            statusCode = .serviceUnavailable
        default:
            response = ErrorResponse(
                error: error.localizedDescription,
                code: "automation_unavailable",
                retryable: true
            )
            statusCode = .serviceUnavailable
        }

        do {
            return try jsonResponse(response, statusCode: statusCode)
        } catch {
            return HTTPResponse(statusCode: .internalServerError)
        }
    }

    private func executeOperation(
        _ name: String,
        body: () async throws -> HTTPResponse
    ) async -> HTTPResponse {
        let operationId: UUID

        do {
            operationId = try await PortalOperationCoordinator.shared.begin(name)
        } catch PortalOperationCoordinator.Error.busy(let activeOperation) {
            return errorResponse(PortalRequestError.busy(activeOperation: activeOperation))
        } catch {
            return errorResponse(error)
        }

        do {
            let response = try await body()
            await PortalOperationCoordinator.shared.finish(operationId)
            return response
        } catch {
            await PortalOperationCoordinator.shared.finish(operationId, error: error)
            return errorResponse(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: HTTPRequest) async throws -> T {
        do {
            return try await JSONDecoder().decode(type, from: request.bodyData)
        } catch {
            throw PortalRequestError.invalidRequest("The request body is not valid JSON for this endpoint.")
        }
    }

    @HTTPRoute("GET /health")
    func health() async throws -> HTTPResponse {
        let snapshot = await PortalOperationCoordinator.shared.snapshot()
        let bundleIdentifier = await DroidrunPortalTools.shared.currentBundleIdentifier
        let response = HealthResponse(
            status: snapshot.isBusy ? "busy" : "ready",
            sessionId: snapshot.sessionId,
            startedAt: Self.iso8601Formatter.string(from: snapshot.startedAt),
            uptimeSeconds: max(0, Int(Date().timeIntervalSince(snapshot.startedAt))),
            currentBundleIdentifier: bundleIdentifier,
            busy: snapshot.isBusy,
            activeOperation: snapshot.activeOperation,
            lastSuccessfulAutomationAt: snapshot.lastSuccessfulAutomationAt.map(Self.iso8601Formatter.string),
            lastError: snapshot.lastError
        )
        return try jsonResponse(response)
    }

    @HTTPRoute("GET /state")
    func stateFull() async -> HTTPResponse {
        await executeOperation("state") {
            let state = try await DroidrunPortalTools.shared.fetchStateFull()
            return try jsonResponse(state)
        }
    }

    @HTTPRoute("GET /vision/screenshot")
    func takeScreenshot() async -> HTTPResponse {
        await executeOperation("screenshot") {
            let screenshot = try await DroidrunPortalTools.shared.takeScreenshot()
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "image/png"],
                body: screenshot
            )
        }
    }

    @HTTPRoute("POST /inputs/launch")
    func launchApp(_ request: HTTPRequest) async -> HTTPResponse {
        await executeOperation("launch") {
            let body = try await decode(LaunchAppBody.self, from: request)
            try await DroidrunPortalTools.shared.openApp(bundleIdentifier: body.bundleIdentifier)
            return try jsonResponse(LaunchAppResponse(message: "opened \(body.bundleIdentifier)"))
        }
    }

    @HTTPRoute("POST /gestures/tap")
    func tapElement(_ request: HTTPRequest) async -> HTTPResponse {
        await executeOperation("tap") {
            let body = try await decode(TapBody.self, from: request)
            try await DroidrunPortalTools.shared.tapElement(
                rect: body.rect,
                count: body.count,
                longPress: body.longPress
            )
            return try jsonResponse(GestureResponse(message: "tapped element"))
        }
    }

    @HTTPRoute("POST /gestures/swipe")
    func swipe(_ request: HTTPRequest) async -> HTTPResponse {
        await executeOperation("swipe") {
            let body = try await decode(SwipeBody.self, from: request)
            let durationSec = (body.durationMs ?? 300) / 1_000.0
            try await DroidrunPortalTools.shared.swipe(
                x1: body.x1,
                y1: body.y1,
                x2: body.x2,
                y2: body.y2,
                duration: durationSec
            )
            return try jsonResponse(GestureResponse(message: "swiped"))
        }
    }

    @HTTPRoute("POST /inputs/type")
    func enterText(_ request: HTTPRequest) async -> HTTPResponse {
        await executeOperation("type") {
            let body = try await decode(TypeBody.self, from: request)
            try await DroidrunPortalTools.shared.enterText(
                rect: body.rect,
                text: body.text,
                clear: body.clear == true
            )
            return try jsonResponse(GestureResponse(message: "entered text"))
        }
    }

    @HTTPRoute("POST /inputs/key")
    func pressKey(_ request: HTTPRequest) async -> HTTPResponse {
        await executeOperation("key") {
            let body = try await decode(KeyBody.self, from: request)
            guard let key = PortalHardwareKey(rawValue: body.key) else {
                throw PortalRequestError.invalidRequest(
                    "Unsupported key \(body.key). Supported keys: \(PortalHardwareKey.supportedKeysDescription)."
                )
            }

            try await DroidrunPortalTools.shared.pressKey(key: key)
            return try jsonResponse(GestureResponse(message: "pressed key"))
        }
    }

    @HTTPRoute("POST /gestures/back")
    func back() async -> HTTPResponse {
        await executeOperation("back") {
            try await DroidrunPortalTools.shared.back()
            return try jsonResponse(GestureResponse(message: "navigated back"))
        }
    }

    @HTTPRoute("GET /device/date")
    func date() async -> HTTPResponse {
        await executeOperation("date") {
            let date = await DroidrunPortalTools.shared.getDate()
            return try jsonResponse(DateResponse(date: date))
        }
    }
}
