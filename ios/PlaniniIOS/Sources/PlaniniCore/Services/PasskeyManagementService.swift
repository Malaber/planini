import Foundation

public struct PasskeyAPIRequest: Equatable, Sendable {
    public enum Method: String, Equatable, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public let method: Method
    public let path: String
    public let body: Data?
    public let accessToken: String

    public init(method: Method, path: String, body: Data?, accessToken: String) {
        self.method = method
        self.path = path
        self.body = body
        self.accessToken = accessToken
    }
}

public protocol PasskeyManagementTransport: Sendable {
    func send(request: PasskeyAPIRequest) async throws -> Data
}

public protocol PasskeyCredentialProvider: Sendable {
    func register(optionsJSON: Data, rpID: String) async throws -> Data
    func authenticate(optionsJSON: Data, rpID: String) async throws -> Data
}

public struct PasskeyRecord: Identifiable, Decodable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let lastUsedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try Self.decodeDate(from: container, forKey: .createdAt)
        guard container.contains(.lastUsedAt) else {
            throw DecodingError.keyNotFound(
                CodingKeys.lastUsedAt,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing last_used_at"
                )
            )
        }
        lastUsedAt = try container.decodeNil(forKey: .lastUsedAt)
            ? nil
            : Self.decodeDate(from: container, forKey: .lastUsedAt)
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)

        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractions.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Invalid ISO-8601 date"
        )
    }
}

public enum PasskeyManagementError: LocalizedError, Equatable, Sendable {
    case emptyName
    case nameTooLong(maximum: Int)
    case invalidBackendURL
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Passkey name is required."
        case let .nameTooLong(maximum):
            return "Passkey name must be \(maximum) characters or fewer."
        case .invalidBackendURL:
            return "The configured backend URL is missing a valid host."
        case .invalidResponse:
            return "The passkey server returned an invalid response."
        }
    }
}

public struct PasskeyManagementService: Sendable {
    private static let apiBase = "/api/v1/auth"
    private static let maximumNameLength = 120

    private let backendURL: URL
    private let accessToken: String
    private let transport: any PasskeyManagementTransport
    private let credentialProvider: any PasskeyCredentialProvider

    public init(
        backendURL: URL,
        accessToken: String,
        transport: any PasskeyManagementTransport,
        credentialProvider: any PasskeyCredentialProvider
    ) {
        self.backendURL = backendURL
        self.accessToken = accessToken
        self.transport = transport
        self.credentialProvider = credentialProvider
    }

    public func listPasskeys() async throws -> [PasskeyRecord] {
        _ = try backendHost()
        let data = try await send(method: .get, path: "\(Self.apiBase)/passkeys")
        return try decode([PasskeyRecord].self, from: data)
    }

    public func addPasskey(name: String) async throws -> PasskeyRecord {
        let name = try validatedName(name)
        let fallbackRPID = try backendHost()
        let optionsPath = "\(Self.apiBase)/passkeys/register/options"
        let verifyPath = "\(Self.apiBase)/passkeys/register/verify"
        let options = try await send(
            method: .post,
            path: optionsPath,
            body: try JSONEncoder().encode(PasskeyNamePayload(name: name))
        )
        let rpID = try relyingPartyIdentifier(
            from: options,
            ceremony: .registration,
            fallback: fallbackRPID
        )
        let credential = try await credentialProvider.register(optionsJSON: options, rpID: rpID)
        let response = try await send(
            method: .post,
            path: verifyPath,
            body: try credentialPayload(credential)
        )
        return try decode(PasskeyRecord.self, from: response)
    }

    public func renamePasskey(id: UUID, name: String) async throws -> PasskeyRecord {
        let name = try validatedName(name)
        let fallbackRPID = try backendHost()
        let id = id.uuidString.lowercased()
        let optionsPath = "\(Self.apiBase)/passkeys/\(id)/rename/options"
        let verifyPath = "\(Self.apiBase)/passkeys/\(id)/rename/verify"
        let options = try await send(
            method: .post,
            path: optionsPath,
            body: try JSONEncoder().encode(PasskeyNamePayload(name: name))
        )
        let rpID = try relyingPartyIdentifier(
            from: options,
            ceremony: .authentication,
            fallback: fallbackRPID
        )
        let credential = try await credentialProvider.authenticate(
            optionsJSON: options,
            rpID: rpID
        )
        let response = try await send(
            method: .post,
            path: verifyPath,
            body: try credentialPayload(credential)
        )
        return try decode(PasskeyRecord.self, from: response)
    }

    public func deletePasskey(id: UUID) async throws {
        let fallbackRPID = try backendHost()
        let id = id.uuidString.lowercased()
        let optionsPath = "\(Self.apiBase)/passkeys/\(id)/delete/options"
        let verifyPath = "\(Self.apiBase)/passkeys/\(id)/delete/verify"
        let options = try await send(method: .post, path: optionsPath)
        let rpID = try relyingPartyIdentifier(
            from: options,
            ceremony: .authentication,
            fallback: fallbackRPID
        )
        let credential = try await credentialProvider.authenticate(
            optionsJSON: options,
            rpID: rpID
        )
        let response = try await send(
            method: .post,
            path: verifyPath,
            body: try credentialPayload(credential)
        )
        _ = try decode(PasskeyDeletePayload.self, from: response)
    }

    private func send(
        method: PasskeyAPIRequest.Method,
        path: String,
        body: Data? = nil
    ) async throws -> Data {
        try await transport.send(
            request: PasskeyAPIRequest(
                method: method,
                path: path,
                body: body,
                accessToken: accessToken
            )
        )
    }

    private func backendHost() throws -> String {
        guard
            let host = backendURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
            host.isEmpty == false
        else {
            throw PasskeyManagementError.invalidBackendURL
        }
        return host
    }

    private func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            throw PasskeyManagementError.emptyName
        }
        guard name.unicodeScalars.count <= Self.maximumNameLength else {
            throw PasskeyManagementError.nameTooLong(maximum: Self.maximumNameLength)
        }
        return name
    }

    private func relyingPartyIdentifier(
        from data: Data,
        ceremony: PasskeyCeremony,
        fallback: String
    ) throws -> String {
        let root = try jsonObject(from: data)
        let options: [String: Any]
        if let wrapped = root["publicKey"] {
            guard let wrapped = wrapped as? [String: Any] else {
                throw PasskeyManagementError.invalidResponse
            }
            options = wrapped
        } else {
            options = root
        }

        switch ceremony {
        case .registration:
            if let rawRP = options["rp"] {
                guard let rp = rawRP as? [String: Any] else {
                    throw PasskeyManagementError.invalidResponse
                }
                if let rawID = rp["id"] {
                    guard let idText = rawID as? String else {
                        throw PasskeyManagementError.invalidResponse
                    }
                    let id = idText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if id.isEmpty == false {
                        return id
                    }
                }
            }
        case .authentication:
            if let rawID = options["rpId"] {
                guard let idText = rawID as? String else {
                    throw PasskeyManagementError.invalidResponse
                }
                let id = idText.trimmingCharacters(in: .whitespacesAndNewlines)
                if id.isEmpty == false {
                    return id
                }
            }
        }
        return fallback
    }

    private func credentialPayload(_ data: Data) throws -> Data {
        let credential = try jsonObject(from: data)
        return try JSONSerialization.data(withJSONObject: ["credential": credential])
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PasskeyManagementError.invalidResponse
        }
        guard let object = value as? [String: Any] else {
            throw PasskeyManagementError.invalidResponse
        }
        return object
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PasskeyManagementError.invalidResponse
        }
    }
}

private enum PasskeyCeremony {
    case registration
    case authentication
}

private struct PasskeyNamePayload: Encodable {
    let name: String
}

private struct PasskeyDeletePayload: Decodable {
    let message: String
}
