import Foundation
import Testing
@testable import PlaniniCore

struct PasskeyManagementServiceTests {
    private let backendURL = URL(string: "https://api.example.com/root")!
    private let accessToken = "test-access-token"
    private let passkeyID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func requestAndErrorPublicValuesAreStable() {
        let body = Data(#"{"name":"Phone"}"#.utf8)
        let request = PasskeyAPIRequest(
            method: .post,
            path: "/path",
            body: body,
            accessToken: accessToken
        )

        #expect(request.method == .post)
        #expect(PasskeyAPIRequest.Method.get.rawValue == "GET")
        #expect(PasskeyAPIRequest.Method.post.rawValue == "POST")
        #expect(request.path == "/path")
        #expect(request.body == body)
        #expect(request.accessToken == accessToken)
        #expect(PasskeyManagementError.emptyName.errorDescription == "Passkey name is required.")
        #expect(
            PasskeyManagementError.nameTooLong(maximum: 120).errorDescription
                == "Passkey name must be 120 characters or fewer."
        )
        #expect(
            PasskeyManagementError.invalidBackendURL.errorDescription
                == "The configured backend URL is missing a valid host."
        )
        #expect(
            PasskeyManagementError.invalidResponse.errorDescription
                == "The passkey server returned an invalid response."
        )
    }

    @Test func listsPasskeysUsingBearerRequestAndFlexibleDates() async throws {
        let response = Data(
            """
            [
              {
                "id": "\(passkeyID.uuidString)",
                "name": "Phone",
                "created_at": "2026-05-12T20:13:00.123456Z",
                "last_used_at": "2026-05-13T08:01:02Z"
              },
              {
                "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "name": "Laptop",
                "created_at": "2026-05-14T10:11:12Z",
                "last_used_at": null
              }
            ]
            """.utf8
        )
        let transport = RecordingPasskeyManagementTransport(responses: [response])
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        let passkeys = try await service.listPasskeys()

        #expect(passkeys.count == 2)
        #expect(passkeys[0].id == passkeyID)
        #expect(passkeys[0].name == "Phone")
        #expect(abs(passkeys[0].createdAt.timeIntervalSince1970 - 1_778_616_780.123) < 0.001)
        #expect(passkeys[0].lastUsedAt?.timeIntervalSince1970 == 1_778_659_262)
        #expect(passkeys[1].lastUsedAt == nil)
        let requests = await transport.requests
        #expect(
            requests == [
                PasskeyAPIRequest(
                    method: .get,
                    path: "/api/v1/auth/passkeys",
                    body: nil,
                    accessToken: accessToken
                )
            ]
        )
        #expect(await provider.calls.isEmpty)
    }

    @Test func addsPasskeyWithTrimmedNameAndWrappedRegistrationRPID() async throws {
        let options = Data(
            #"{"publicKey":{"challenge":"abc","rp":{"id":"passkeys.example.com"}}}"#.utf8
        )
        let credential = Data(#"{"id":"credential-one","type":"public-key"}"#.utf8)
        let response = passkeyRecordJSON(name: "Phone")
        let transport = RecordingPasskeyManagementTransport(responses: [options, response])
        let provider = RecordingPasskeyCredentialProvider(registrationCredential: credential)
        let service = makeService(transport: transport, provider: provider)

        let passkey = try await service.addPasskey(name: "  Phone \n")

        #expect(passkey.id == passkeyID)
        #expect(passkey.name == "Phone")
        let calls = await provider.calls
        #expect(calls == [.register(optionsJSON: options, rpID: "passkeys.example.com")])
        let requests = await transport.requests
        #expect(requests.map(\.method) == [.post, .post])
        #expect(
            requests.map(\.path) == [
                "/api/v1/auth/passkeys/register/options",
                "/api/v1/auth/passkeys/register/verify",
            ]
        )
        #expect(requests.allSatisfy { $0.accessToken == accessToken })
        #expect(try stringValue("name", in: requests[0].body) == "Phone")
        #expect(try nestedStringValue("id", parent: "credential", in: requests[1].body) == "credential-one")
    }

    @Test func addsPasskeyUsingBackendHostWhenRawRegistrationOptionsHaveNoRP() async throws {
        let options = Data(#"{"challenge":"abc"}"#.utf8)
        let response = passkeyRecordJSON(name: String(repeating: "x", count: 120))
        let transport = RecordingPasskeyManagementTransport(responses: [options, response])
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        _ = try await service.addPasskey(name: String(repeating: "x", count: 120))

        #expect(await provider.calls == [.register(optionsJSON: options, rpID: "api.example.com")])
    }

    @Test func emptyRegistrationRPIDFallsBackToBackendHost() async throws {
        let options = Data(#"{"rp":{"id":"   "}}"#.utf8)
        let transport = RecordingPasskeyManagementTransport(
            responses: [options, passkeyRecordJSON(name: "Phone")]
        )
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        _ = try await service.addPasskey(name: "Phone")

        #expect(await provider.calls == [.register(optionsJSON: options, rpID: "api.example.com")])
    }

    @Test func validatesNamesBeforeSendingRequests() async {
        let transport = RecordingPasskeyManagementTransport()
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        await #expect(throws: PasskeyManagementError.emptyName) {
            try await service.addPasskey(name: " \n ")
        }
        await #expect(throws: PasskeyManagementError.nameTooLong(maximum: 120)) {
            try await service.renamePasskey(
                id: passkeyID,
                name: String(repeating: "é", count: 121)
            )
        }

        #expect(await transport.requests.isEmpty)
        #expect(await provider.calls.isEmpty)
    }

    @Test func renamesPasskeyWithRawAssertionRPID() async throws {
        let options = Data(#"{"challenge":"abc","rpId":"assert.example.com"}"#.utf8)
        let credential = Data(
            #"{"id":"credential-two","response":{"signature":"signature"}}"#.utf8
        )
        let transport = RecordingPasskeyManagementTransport(
            responses: [options, passkeyRecordJSON(name: "Travel key")]
        )
        let provider = RecordingPasskeyCredentialProvider(
            authenticationCredential: credential
        )
        let service = makeService(transport: transport, provider: provider)

        let passkey = try await service.renamePasskey(id: passkeyID, name: " Travel key ")

        #expect(passkey.name == "Travel key")
        #expect(
            await provider.calls == [
                .authenticate(optionsJSON: options, rpID: "assert.example.com")
            ]
        )
        let requests = await transport.requests
        let id = passkeyID.uuidString.lowercased()
        #expect(
            requests.map(\.path) == [
                "/api/v1/auth/passkeys/\(id)/rename/options",
                "/api/v1/auth/passkeys/\(id)/rename/verify",
            ]
        )
        #expect(try stringValue("name", in: requests[0].body) == "Travel key")
        #expect(
            try nestedStringValue("id", parent: "credential", in: requests[1].body)
                == "credential-two"
        )
    }

    @Test func wrappedEmptyAssertionRPIDFallsBackToBackendHost() async throws {
        let options = Data(#"{"publicKey":{"challenge":"abc","rpId":""}}"#.utf8)
        let transport = RecordingPasskeyManagementTransport(
            responses: [options, passkeyRecordJSON(name: "Renamed")]
        )
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        _ = try await service.renamePasskey(id: passkeyID, name: "Renamed")

        #expect(
            await provider.calls == [
                .authenticate(optionsJSON: options, rpID: "api.example.com")
            ]
        )
    }

    @Test func deletesPasskeyByConfirmingWithAuthenticationCredential() async throws {
        let options = Data(
            #"{"publicKey":{"challenge":"abc","rpId":"delete.example.com"}}"#.utf8
        )
        let credential = Data(#"{"id":"other-credential"}"#.utf8)
        let transport = RecordingPasskeyManagementTransport(
            responses: [options, Data(#"{"message":"passkey deleted"}"#.utf8)]
        )
        let provider = RecordingPasskeyCredentialProvider(
            authenticationCredential: credential
        )
        let service = makeService(transport: transport, provider: provider)

        try await service.deletePasskey(id: passkeyID)

        #expect(
            await provider.calls == [
                .authenticate(optionsJSON: options, rpID: "delete.example.com")
            ]
        )
        let requests = await transport.requests
        let id = passkeyID.uuidString.lowercased()
        #expect(requests[0].path == "/api/v1/auth/passkeys/\(id)/delete/options")
        #expect(requests[0].body == nil)
        #expect(requests[1].path == "/api/v1/auth/passkeys/\(id)/delete/verify")
        #expect(
            try nestedStringValue("id", parent: "credential", in: requests[1].body)
                == "other-credential"
        )
    }

    @Test func rejectsBackendURLWithoutHostBeforeSending() async {
        let transport = RecordingPasskeyManagementTransport()
        let provider = RecordingPasskeyCredentialProvider()
        let service = PasskeyManagementService(
            backendURL: URL(fileURLWithPath: "/tmp/planini"),
            accessToken: accessToken,
            transport: transport,
            credentialProvider: provider
        )

        await #expect(throws: PasskeyManagementError.invalidBackendURL) {
            try await service.listPasskeys()
        }

        #expect(await transport.requests.isEmpty)
    }

    @Test func rejectsMalformedAndNonObjectOptions() async {
        let provider = RecordingPasskeyCredentialProvider()

        let malformedTransport = RecordingPasskeyManagementTransport(
            responses: [Data("not-json".utf8)]
        )
        let malformedService = makeService(transport: malformedTransport, provider: provider)
        await #expect(throws: PasskeyManagementError.invalidResponse) {
            try await malformedService.addPasskey(name: "Phone")
        }

        let arrayTransport = RecordingPasskeyManagementTransport(
            responses: [Data("[]".utf8)]
        )
        let arrayService = makeService(transport: arrayTransport, provider: provider)
        await #expect(throws: PasskeyManagementError.invalidResponse) {
            try await arrayService.renamePasskey(id: passkeyID, name: "Phone")
        }

        let invalidWrapperTransport = RecordingPasskeyManagementTransport(
            responses: [Data(#"{"publicKey":"invalid"}"#.utf8)]
        )
        let invalidWrapperService = makeService(
            transport: invalidWrapperTransport,
            provider: provider
        )
        await #expect(throws: PasskeyManagementError.invalidResponse) {
            try await invalidWrapperService.deletePasskey(id: passkeyID)
        }
    }

    @Test func rejectsMalformedRelyingPartyFields() async {
        let provider = RecordingPasskeyCredentialProvider()

        for optionsText in [
            #"{"rp":"invalid"}"#,
            #"{"rp":{"id":42}}"#,
        ] {
            let transport = RecordingPasskeyManagementTransport(
                responses: [Data(optionsText.utf8)]
            )
            let service = makeService(transport: transport, provider: provider)
            await #expect(throws: PasskeyManagementError.invalidResponse) {
                try await service.addPasskey(name: "Phone")
            }
        }

        let transport = RecordingPasskeyManagementTransport(
            responses: [Data(#"{"rpId":42}"#.utf8)]
        )
        let service = makeService(transport: transport, provider: provider)
        await #expect(throws: PasskeyManagementError.invalidResponse) {
            try await service.renamePasskey(id: passkeyID, name: "Phone")
        }
    }

    @Test func rejectsMalformedCredentialJSON() async {
        for credential in [Data("not-json".utf8), Data("[]".utf8)] {
            let options = Data(#"{"rp":{"id":"passkeys.example.com"}}"#.utf8)
            let transport = RecordingPasskeyManagementTransport(responses: [options])
            let provider = RecordingPasskeyCredentialProvider(
                registrationCredential: credential
            )
            let service = makeService(transport: transport, provider: provider)

            await #expect(throws: PasskeyManagementError.invalidResponse) {
                try await service.addPasskey(name: "Phone")
            }
            #expect(await transport.requests.count == 1)
        }
    }

    @Test func rejectsMalformedRecordsDatesAndDeleteResponses() async {
        let provider = RecordingPasskeyCredentialProvider()

        for response in [
            Data("not-json".utf8),
            Data(
                """
                [{
                  "id": "\(passkeyID.uuidString)",
                  "name": "Phone",
                  "created_at": "not-a-date",
                  "last_used_at": null
                }]
                """.utf8
            ),
            Data(
                """
                [{
                  "id": "\(passkeyID.uuidString)",
                  "name": "Phone",
                  "created_at": "2026-05-12T20:13:00Z"
                }]
                """.utf8
            ),
        ] {
            let transport = RecordingPasskeyManagementTransport(responses: [response])
            let service = makeService(transport: transport, provider: provider)
            await #expect(throws: PasskeyManagementError.invalidResponse) {
                try await service.listPasskeys()
            }
        }

        let options = Data(#"{"rpId":"delete.example.com"}"#.utf8)
        let deleteTransport = RecordingPasskeyManagementTransport(
            responses: [options, Data("{}".utf8)]
        )
        let deleteService = makeService(transport: deleteTransport, provider: provider)
        await #expect(throws: PasskeyManagementError.invalidResponse) {
            try await deleteService.deletePasskey(id: passkeyID)
        }
    }

    @Test func transportAndCredentialProviderErrorsPropagate() async {
        let transport = RecordingPasskeyManagementTransport(error: .transport)
        let provider = RecordingPasskeyCredentialProvider()
        let service = makeService(transport: transport, provider: provider)

        await #expect(throws: PasskeyManagementTestError.transport) {
            try await service.listPasskeys()
        }

        let options = Data(#"{"rp":{"id":"passkeys.example.com"}}"#.utf8)
        let providerTransport = RecordingPasskeyManagementTransport(responses: [options])
        let failingProvider = RecordingPasskeyCredentialProvider(error: .credentialProvider)
        let providerService = makeService(
            transport: providerTransport,
            provider: failingProvider
        )
        await #expect(throws: PasskeyManagementTestError.credentialProvider) {
            try await providerService.addPasskey(name: "Phone")
        }
    }

    private func makeService(
        transport: RecordingPasskeyManagementTransport,
        provider: RecordingPasskeyCredentialProvider
    ) -> PasskeyManagementService {
        PasskeyManagementService(
            backendURL: backendURL,
            accessToken: accessToken,
            transport: transport,
            credentialProvider: provider
        )
    }

    private func passkeyRecordJSON(name: String) -> Data {
        Data(
            """
            {
              "id": "\(passkeyID.uuidString)",
              "name": "\(name)",
              "created_at": "2026-05-12T20:13:00Z",
              "last_used_at": null
            }
            """.utf8
        )
    }

    private func stringValue(_ key: String, in data: Data?) throws -> String? {
        let data = try #require(data)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return object[key] as? String
    }

    private func nestedStringValue(
        _ key: String,
        parent: String,
        in data: Data?
    ) throws -> String? {
        let data = try #require(data)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let nested = try #require(object[parent] as? [String: Any])
        return nested[key] as? String
    }
}

private enum PasskeyCredentialProviderCall: Equatable, Sendable {
    case register(optionsJSON: Data, rpID: String)
    case authenticate(optionsJSON: Data, rpID: String)
}

private enum PasskeyManagementTestError: Error, Equatable {
    case missingResponse
    case transport
    case credentialProvider
}

private actor RecordingPasskeyManagementTransport: PasskeyManagementTransport {
    private var responses: [Data]
    private let error: PasskeyManagementTestError?
    private(set) var requests: [PasskeyAPIRequest] = []

    init(
        responses: [Data] = [],
        error: PasskeyManagementTestError? = nil
    ) {
        self.responses = responses
        self.error = error
    }

    func send(request: PasskeyAPIRequest) async throws -> Data {
        requests.append(request)
        if let error {
            throw error
        }
        guard responses.isEmpty == false else {
            throw PasskeyManagementTestError.missingResponse
        }
        return responses.removeFirst()
    }
}

private actor RecordingPasskeyCredentialProvider: PasskeyCredentialProvider {
    private let registrationCredential: Data
    private let authenticationCredential: Data
    private let error: PasskeyManagementTestError?
    private(set) var calls: [PasskeyCredentialProviderCall] = []

    init(
        registrationCredential: Data = Data(#"{"id":"registered-credential"}"#.utf8),
        authenticationCredential: Data = Data(#"{"id":"authenticated-credential"}"#.utf8),
        error: PasskeyManagementTestError? = nil
    ) {
        self.registrationCredential = registrationCredential
        self.authenticationCredential = authenticationCredential
        self.error = error
    }

    func register(optionsJSON: Data, rpID: String) async throws -> Data {
        calls.append(.register(optionsJSON: optionsJSON, rpID: rpID))
        if let error {
            throw error
        }
        return registrationCredential
    }

    func authenticate(optionsJSON: Data, rpID: String) async throws -> Data {
        calls.append(.authenticate(optionsJSON: optionsJSON, rpID: rpID))
        if let error {
            throw error
        }
        return authenticationCredential
    }
}
