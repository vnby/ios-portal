//
//  droidrun_ios_portalUITests.swift
//  droidrun-ios-portalUITests
//
//  Created by Timo Beckmann on 03.06.25.
//

import XCTest
import FlyingFox

private enum PortalServerError: LocalizedError {
    case stoppedUnexpectedly

    var errorDescription: String? {
        "The portal HTTP server stopped unexpectedly."
    }
}

final class DroidrunPortalServer: XCTestCase {
    var server: HTTPServer!

    private static let basePort: in_port_t = 6643

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        let expectation = XCTestExpectation(description: "Stop server")
        Task {
            await server?.stop()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    @MainActor
    func testLoop() async throws {
        DroidrunPortalTools.shared.reset()

        let server = HTTPServer(
            port: Self.basePort,
            timeout: 60,
            handler: DroidrunPortalHandler()
        )
        self.server = server

        let serverTask = Task {
            try await server.run()
        }

        do {
            try await server.waitUntilListening(timeout: 10)
            print("Portal server listening on port \(Self.basePort)")

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard await server.listeningAddress != nil else {
                    try await serverTask.value
                    throw PortalServerError.stoppedUnexpectedly
                }
            }
        } catch {
            await server.stop(timeout: 2)
            serverTask.cancel()
            throw error
        }
    }
}
