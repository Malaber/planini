import Foundation

public enum PlaniniLink: Equatable, Sendable {
    case passkeyAdd(token: String)
    case invite(token: String)
    case list(id: UUID)
    case publicList(token: String)
}

public enum PlaniniLinkParser {
    private static let tokenAllowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))

    public static func parse(
        _ rawValue: String,
        allowedWebHosts: Set<String>? = nil
    ) -> PlaniniLink? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil,
            let link = parse(url: url, allowedWebHosts: allowedWebHosts)
        {
            return link
        }

        if let token = passkeyAddToken(from: trimmed) {
            return .passkeyAdd(token: token)
        }
        return nil
    }

    public static func passkeyAddToken(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            if url.scheme?.lowercased() == "passkey-add" {
                if let host = url.host, let token = normalizedToken(host) {
                    return token
                }
                return url.path.split(separator: "/").first.map(String.init).flatMap(normalizedToken)
            }

            let segments = pathSegments(from: url)
            if
                let markerIndex = segments.firstIndex(of: "passkey-add"),
                markerIndex + 1 < segments.count
            {
                return normalizedToken(segments[markerIndex + 1])
            }
            if url.host == "passkey-add", let token = segments.first {
                return normalizedToken(token)
            }
        }

        for marker in ["/passkey-add/", "passkey-add/"] {
            guard let range = trimmed.range(of: marker) else { continue }
            let suffix = String(trimmed[range.upperBound...])
            if let token = normalizedToken(suffix) {
                return token
            }
        }

        return normalizedToken(trimmed)
    }

    private static func parse(url: URL, allowedWebHosts: Set<String>?) -> PlaniniLink? {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            guard hostIsAllowed(url.host, allowedWebHosts: allowedWebHosts) else { return nil }
            return parse(segments: pathSegments(from: url))
        }

        if scheme == "planini" {
            var segments: [String] = []
            if let host = url.host, host.isEmpty == false {
                segments.append(host)
            }
            segments.append(contentsOf: pathSegments(from: url))
            return parse(segments: segments)
        }

        return passkeyAddToken(from: url.absoluteString).map { .passkeyAdd(token: $0) }
    }

    private static func parse(segments: [String]) -> PlaniniLink? {
        guard segments.count >= 2 else { return nil }
        if segments.count >= 3, segments[0] == "public", segments[1] == "lists" {
            return normalizedToken(segments[2]).map { .publicList(token: $0) }
        }
        switch segments[0] {
        case "passkey-add":
            return normalizedToken(segments[1]).map { .passkeyAdd(token: $0) }
        case "invite":
            return normalizedToken(segments[1]).map { .invite(token: $0) }
        case "lists":
            return UUID(uuidString: segments[1]).map { .list(id: $0) }
        default:
            return nil
        }
    }

    private static func pathSegments(from url: URL) -> [String] {
        url.path.split(separator: "/").map(String.init)
    }

    private static func hostIsAllowed(_ host: String?, allowedWebHosts: Set<String>?) -> Bool {
        guard let allowedWebHosts else { return true }
        guard let host = host?.lowercased() else { return false }
        return allowedWebHosts.map { $0.lowercased() }.contains(host)
    }

    private static func normalizedToken(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["?", "#"] {
            if let range = value.range(of: separator) {
                value = String(value[..<range.lowerBound])
            }
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        value = value.removingPercentEncoding ?? value
        guard
            value.isEmpty == false,
            value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            value.rangeOfCharacter(from: tokenAllowedCharacters.inverted) == nil
        else {
            return nil
        }
        return value
    }
}
