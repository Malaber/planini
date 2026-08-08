import Foundation
import PlaniniCore

struct AppPasskeyManagementTransport: PasskeyManagementTransport {
    let backendURL: URL

    func send(request: PasskeyAPIRequest) async throws -> Data {
        var urlRequest = URLRequest(url: backendURL.appending(path: request.path))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(request.accessToken)", forHTTPHeaderField: "Authorization")
        if let body = request.body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let detail: String? = if
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let detail = payload["detail"] as? String,
                detail.isEmpty == false
            {
                detail
            } else {
                nil
            }
            if http.statusCode == 401 {
                if let detail, detail.hasPrefix("Could not verify") {
                    throw AppError.server(detail)
                }
                throw AppError.sessionExpired
            }
            if let detail {
                throw AppError.server(detail)
            }
            throw AppError.server("Request failed (\(http.statusCode)).")
        }
        return data
    }
}

#if canImport(AuthenticationServices)
import AuthenticationServices
import os.log
import UIKit

private let passkeyLog = Logger(subsystem: "de.malaber.planini.ios", category: "passkey")

struct ApplePasskeyClient: PasskeyCredentialProvider {
    func register(optionsJSON: Data, rpID: String) async throws -> Data {
        let optionsPayload = try decodedOptions(from: optionsJSON)
        let credential = try await register(
            optionsPayload: optionsPayload,
            relyingPartyIdentifier: rpID
        )
        return try JSONSerialization.data(withJSONObject: credential)
    }

    func authenticate(optionsJSON: Data, rpID: String) async throws -> Data {
        let optionsPayload = try decodedOptions(from: optionsJSON)
        let credential = try await authenticate(
            optionsPayload: optionsPayload,
            relyingPartyIdentifier: rpID
        )
        return try JSONSerialization.data(withJSONObject: credential)
    }

    func register(optionsPayload: [String: Any], relyingPartyIdentifier: String) async throws -> [String: Any] {
        let publicKey = (optionsPayload["publicKey"] as? [String: Any]) ?? optionsPayload
        guard
            let challengeText = publicKey["challenge"] as? String,
            let challenge = Data(base64URLEncoded: challengeText),
            let user = publicKey["user"] as? [String: Any],
            let userIDText = user["id"] as? String,
            let userID = Data(base64URLEncoded: userIDText)
        else {
            throw AppError.invalidResponse
        }

        let userName = (user["name"] as? String) ?? (user["displayName"] as? String) ?? "Planini"
        #if DEBUG
        logPasskeyRequest(
            operation: "registration",
            relyingPartyIdentifier: relyingPartyIdentifier,
            publicKey: publicKey,
            allowedCredentialCount: 0
        )
        #endif
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: userName,
            userID: userID
        )
        if let preference = userVerificationPreference(
            from: publicKey["userVerification"] as? String
        ) {
            request.userVerificationPreference = preference
        }
        if #available(iOS 17.4, *),
           let excludeCredentials = publicKey["excludeCredentials"] as? [[String: Any]]
        {
            request.excludedCredentials = credentialDescriptors(from: excludeCredentials)
        }

        let authorization = try await PasskeyCoordinator().perform(request: request)
        guard
            let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = credential.rawAttestationObject
        else {
            throw AppError.server("Passkey registration failed.")
        }

        return [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "type": "public-key",
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "attestationObject": attestationObject.base64URLEncodedString(),
            ],
            "clientExtensionResults": [:],
        ]
    }

    private func credentialDescriptors(
        from credentials: [[String: Any]]
    ) -> [ASAuthorizationPlatformPublicKeyCredentialDescriptor] {
        credentials.compactMap { credential in
            guard
                let id = credential["id"] as? String,
                let credentialID = Data(base64URLEncoded: id)
            else {
                return nil
            }
            return ASAuthorizationPlatformPublicKeyCredentialDescriptor(
                credentialID: credentialID
            )
        }
    }

    private func userVerificationPreference(
        from value: String?
    ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference? {
        switch value {
        case "required":
            return .required
        case "preferred":
            return .preferred
        case "discouraged":
            return .discouraged
        default:
            return nil
        }
    }

    func authenticate(optionsPayload: [String: Any], relyingPartyIdentifier: String) async throws -> [String: Any] {
        let publicKey = (optionsPayload["publicKey"] as? [String: Any]) ?? optionsPayload
        guard
            let challengeText = publicKey["challenge"] as? String,
            let challenge = Data(base64URLEncoded: challengeText)
        else {
            throw AppError.invalidResponse
        }

        let allowCredentials = publicKey["allowCredentials"] as? [[String: Any]]
        #if DEBUG
        logPasskeyRequest(
            operation: "assertion",
            relyingPartyIdentifier: relyingPartyIdentifier,
            publicKey: publicKey,
            allowedCredentialCount: allowCredentials?.count ?? 0
        )
        #endif
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if let preference = userVerificationPreference(
            from: publicKey["userVerification"] as? String
        ) {
            request.userVerificationPreference = preference
        }

        if let allowCredentials, allowCredentials.isEmpty == false {
            request.allowedCredentials = credentialDescriptors(from: allowCredentials)
        }

        let authorization = try await PasskeyCoordinator().perform(request: request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw AppError.server("Passkey sign-in failed.")
        }

        return [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "type": "public-key",
            "response": [
                "authenticatorData": credential.rawAuthenticatorData.base64URLEncodedString(),
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "signature": credential.signature.base64URLEncodedString(),
                "userHandle": (credential.userID ?? Data()).base64URLEncodedString(),
            ],
            "clientExtensionResults": [:],
        ]
    }

    private func decodedOptions(from data: Data) throws -> [String: Any] {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AppError.invalidResponse
        }
        return payload
    }
}

#if DEBUG
private func logPasskeyRequest(
    operation: String,
    relyingPartyIdentifier: String,
    publicKey: [String: Any],
    allowedCredentialCount: Int
) {
    let challengeText = publicKey["challenge"] as? String ?? "<missing>"
    let userVerification = publicKey["userVerification"] as? String ?? "<missing>"
    let bundleID = Bundle.main.bundleIdentifier ?? "<missing>"
    passkeyLog.notice(
        "Starting passkey \(operation, privacy: .public). rpID=\(relyingPartyIdentifier, privacy: .public) bundleID=\(bundleID, privacy: .public) challengeLength=\(challengeText.count) allowCredentials=\(allowedCredentialCount) userVerification=\(userVerification, privacy: .public)"
    )
}
#endif

private final class PasskeyCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            #if DEBUG
            passkeyLog.debug(
                "Performing ASAuthorizationController request type=\(String(describing: type(of: request)), privacy: .public)"
            )
            #endif
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        #if DEBUG
        passkeyLog.notice(
            "ASAuthorizationController completed. credentialType=\(String(describing: type(of: authorization.credential)), privacy: .public)"
        )
        #endif
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        #if DEBUG
        let nsError = error as NSError
        passkeyLog.error(
            "ASAuthorizationController failed. type=\(String(describing: type(of: error)), privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public) userInfo=\(String(describing: nsError.userInfo), privacy: .public)"
        )
        #endif
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
#else
struct ApplePasskeyClient: PasskeyCredentialProvider {
    func register(optionsJSON: Data, rpID: String) async throws -> Data {
        _ = optionsJSON
        _ = rpID
        throw AppError.server("Passkeys are unavailable on this platform.")
    }

    func authenticate(optionsJSON: Data, rpID: String) async throws -> Data {
        _ = optionsJSON
        _ = rpID
        throw AppError.server("Passkeys are unavailable on this platform.")
    }

    func register(optionsPayload: [String: Any], relyingPartyIdentifier: String) async throws -> [String: Any] {
        _ = optionsPayload
        _ = relyingPartyIdentifier
        throw AppError.server("Passkeys are unavailable on this platform.")
    }

    func authenticate(optionsPayload: [String: Any], relyingPartyIdentifier: String) async throws -> [String: Any] {
        _ = optionsPayload
        _ = relyingPartyIdentifier
        throw AppError.server("Passkeys are unavailable on this platform.")
    }
}
#endif

private extension Data {
    init?(base64URLEncoded value: String) {
        let normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: padded)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
