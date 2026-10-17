import Foundation

struct DNSAnswer: Decodable {
    struct Record: Decodable { let type: Int; let TTL: Int; let data: String }
    let Status: Int
    let Answer: [Record]?
}

actor DNSResolver {
    enum Provider: String, CaseIterable { case cloudflare = "Cloudflare", google = "Google" }
    private struct Cached { let ips: [String]; let until: Date }
    private var cache: [String: Cached] = [:]
    var provider: Provider = .cloudflare
    let log: (String) -> Void
    private let session: URLSession

    init(log: @escaping (String) -> Void) {
        self.log = log
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.urlCache = nil
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        session = URLSession(configuration: config)
    }
    func reset(provider: Provider) { self.provider = provider; cache.removeAll() }
    func clear() { cache.removeAll() }

    func resolve(_ host: String) async throws -> [String] {
        if URLPolicy.literalIP(host) {
            guard URLPolicy.publicIP(host) else { throw LinkError.privateAddress }
            return [host]
        }
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, !host.hasSuffix(".local"), host != "localhost", host.contains("."), host.utf8.count <= 253 else { throw LinkError.privateAddress }
        if let cached = cache[host], cached.until > Date() { return cached.ips }
        let order: [Provider] = provider == .cloudflare ? [.cloudflare, .google] : [.google, .cloudflare]
        var failures: [String] = []
        for source in order {
            var records: [DNSAnswer.Record] = []
            for type in [1, 28] {
                do {
                    let base = source == .cloudflare ? "https://cloudflare-dns.com/dns-query" : "https://dns.google/resolve"
                    var components = URLComponents(string: base)!
                    components.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: String(type))]
                    var request = URLRequest(url: components.url!)
                    request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await session.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 131072 else { throw LinkError.dns("DoH indisponível") }
                    let answer = try JSONDecoder().decode(DNSAnswer.self, from: data)
                    log("DNS \(source.rawValue) \(host) tipo \(type) rcode=\(answer.Status)")
                    guard answer.Status == 0 else { throw LinkError.dns("rcode=\(answer.Status)") }
                    records += (answer.Answer ?? []).filter { $0.type == type && URLPolicy.publicIP($0.data) }
                } catch { failures.append("\(source.rawValue): \(error.localizedDescription)") }
            }
            var ips: [String] = []
            for record in records where !ips.contains(record.data) { ips.append(record.data) }
            if !ips.isEmpty {
                let ttl = max(1, min(records.map(\.TTL).min() ?? 30, 300))
                cache[host] = Cached(ips: ips, until: Date().addingTimeInterval(TimeInterval(ttl)))
                log("DNS alternativo \(host): \(ips.joined(separator: ", ")) TTL=\(ttl)")
                return ips
            }
        }
        throw LinkError.dns("Sem IP público válido: " + failures.suffix(4).joined(separator: "; "))
    }
}
