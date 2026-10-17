import Foundation
import Darwin

enum LinkError: LocalizedError {
    case invalidURL, privateAddress, dns(String), protocolError, timeout
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use uma URL HTTP ou HTTPS válida, sem credenciais."
        case .privateAddress: return "Destino interno, reservado ou porta não permitida."
        case .dns(let message): return message
        case .protocolError: return "Falha no protocolo do proxy local."
        case .timeout: return "Tempo limite de conexão."
        }
    }
}

enum URLPolicy {
    static func parse(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\\"), !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { throw LinkError.invalidURL }
        let candidate: String
        if text.hasPrefix("//") { candidate = "https:" + text }
        else if text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil { candidate = text }
        else { candidate = "https://" + text }
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { throw LinkError.invalidURL }
        return url
    }

    static func publicIP(_ text: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            let parts = text.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4 else { return false }
            let a = Int(parts[0]), b = Int(parts[1]), c = Int(parts[2])
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a == 169 && b == 254 || a == 172 && (16...31).contains(b) || a == 192 && b == 168 { return false }
            if a == 192 && b == 0 || a == 192 && b == 88 && c == 99 || a == 192 && b == 2 { return false }
            if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) || a == 203 && b == 0 && c == 113 { return false }
            return true
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, text, &v6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &v6) { Array($0) }
        // Deliberately restrict to global unicast; reject mapped IPv4,
        // NAT64, local, multicast, documentation, Teredo and 6to4.
        guard bytes[0] & 0xe0 == 0x20 else { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2 { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x02 { return false }
        if bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] < 0x10 { return false }
        return true
    }

    static func literalIP(_ host: String) -> Bool {
        var a = in_addr(); var b = in6_addr()
        return inet_pton(AF_INET, host, &a) == 1 || inet_pton(AF_INET6, host, &b) == 1
    }
}
