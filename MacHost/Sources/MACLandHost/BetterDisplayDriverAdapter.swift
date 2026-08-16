import Foundation

@MainActor
final class BetterDisplayDriverAdapter: ThirdPartyDisplayDriverAdapter {
    let identifier = "betterdisplay-dnc"

    private let integration = BetterDisplayNotificationIntegration()
    private var virtualScreenSerial: String?

    let isConfigured = true

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: "/Applications/BetterDisplay.app")
    }

    func createDisplay(configuration: ThirdPartyDisplayConfiguration) async throws -> UInt32 {
        guard isAvailable else {
            throw RemoteDisplayProviderError.driverUnavailable(identifier)
        }

        let serial = "MACLAND-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let parameters: [String: String?] = [
            "type": "VirtualScreen",
            "virtualScreenName": "MACLand Remote Display",
            "virtualScreenSerial": serial,
            "useResolutionList": "on",
            "resolutionList": String(configuration.pixelWidth) + "x" + String(configuration.pixelHeight),
            "virtualScreenHiDPI": "off"
        ]

        let creationPayload = try await integration.send(commands: ["create"], parameters: parameters)
        let identifiersPayload: String?
        if Self.displayID(from: creationPayload) != nil {
            identifiersPayload = creationPayload
        } else {
            identifiersPayload = try await integration.send(
                commands: ["get"],
                parameters: ["identifiers": nil, "virtualScreenSerial": serial]
            )
        }

        guard let displayID = Self.displayID(from: identifiersPayload) else {
            throw RemoteDisplayProviderError.driverResponseInvalid
        }

        virtualScreenSerial = serial
        return displayID
    }

    func destroyDisplay() async throws {
        guard let serial = virtualScreenSerial else { return }
        guard isAvailable else {
            throw RemoteDisplayProviderError.driverUnavailable(identifier)
        }

        _ = try await integration.send(
            commands: ["discard"],
            parameters: [
                "type": "VirtualScreen",
                "virtualScreenSerial": serial
            ]
        )
        virtualScreenSerial = nil
    }

    private static func displayID(from payload: String?) -> UInt32? {
        guard
            let payload,
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return findDisplayID(in: object)
    }

    private static func findDisplayID(in object: Any) -> UInt32? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if key.caseInsensitiveCompare("displayID") == .orderedSame {
                    if let number = value as? NSNumber {
                        return number.uint32Value
                    }
                    if let string = value as? String, let number = UInt32(string) {
                        return number
                    }
                }

                if let displayID = findDisplayID(in: value) {
                    return displayID
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let displayID = findDisplayID(in: value) {
                    return displayID
                }
            }
        }

        return nil
    }
}

private final class BetterDisplayNotificationIntegration: NSObject, @unchecked Sendable {
    private static let requestName = Notification.Name("pro.betterdisplay.BetterDisplay.request")
    private static let responseName = Notification.Name("pro.betterdisplay.BetterDisplay.response")

    private let center = DistributedNotificationCenter.default()

    func send(
        commands: [String],
        parameters: [String: String?]
    ) async throws -> String? {
        let request = Request(
            uuid: UUID().uuidString,
            commands: commands,
            parameters: parameters
        )
        let data = try JSONEncoder().encode(request)
        guard let encodedRequest = String(data: data, encoding: .utf8) else {
            throw RemoteDisplayProviderError.driverResponseInvalid
        }

        let pending = PendingNotificationRequest(
            requestID: request.uuid,
            center: center
        )

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending.start(encodedRequest: encodedRequest, continuation: continuation)
            }
        }, onCancel: {
            pending.finish(error: CancellationError())
        })
    }

    private struct Request: Codable {
        let uuid: String
        let commands: [String]
        let parameters: [String: String?]
    }

    private struct Response: Codable {
        let uuid: String?
        let result: Bool?
        let payload: String?
    }

    private final class PendingNotificationRequest: @unchecked Sendable {
        private let requestID: String
        private let center: DistributedNotificationCenter
        private let lock = NSLock()

        private var continuation: CheckedContinuation<String?, Error>?
        private var observer: NSObjectProtocol?
        private var timeoutWorkItem: DispatchWorkItem?
        private var isFinished = false

        init(requestID: String, center: DistributedNotificationCenter) {
            self.requestID = requestID
            self.center = center
        }

        func start(
            encodedRequest: String,
            continuation: CheckedContinuation<String?, Error>
        ) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let observer = center.addObserver(
                forName: BetterDisplayNotificationIntegration.responseName,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.receive(notification)
            }

            lock.lock()
            if isFinished {
                lock.unlock()
                center.removeObserver(observer)
                return
            }
            self.observer = observer
            lock.unlock()

            center.postNotificationName(
                BetterDisplayNotificationIntegration.requestName,
                object: encodedRequest,
                userInfo: nil,
                deliverImmediately: true
            )

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.finish(error: RemoteDisplayProviderError.driverRequestTimedOut)
            }
            lock.lock()
            self.timeoutWorkItem = timeoutWorkItem
            let shouldSchedule = !isFinished
            lock.unlock()
            if shouldSchedule {
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + 15,
                    execute: timeoutWorkItem
                )
            }
        }

        func receive(_ notification: Notification) {
            guard
                let text = notification.object as? String,
                let data = text.data(using: .utf8),
                let response = try? JSONDecoder().decode(
                    BetterDisplayNotificationIntegration.Response.self,
                    from: data
                ),
                response.uuid == requestID
            else {
                return
            }

            guard response.result != false else {
                finish(error: RemoteDisplayProviderError.driverResponseInvalid)
                return
            }

            finish(value: response.payload)
        }

        func finish(value: String? = nil, error: Error? = nil) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            let continuation = self.continuation
            let observer = self.observer
            let timeoutWorkItem = self.timeoutWorkItem
            self.continuation = nil
            self.observer = nil
            self.timeoutWorkItem = nil
            lock.unlock()

            if let observer {
                center.removeObserver(observer)
            }
            timeoutWorkItem?.cancel()

            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(returning: value)
            }
        }
    }
}
