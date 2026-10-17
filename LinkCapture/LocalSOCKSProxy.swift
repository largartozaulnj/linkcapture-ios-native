import Foundation
import Network

// TCP only. The proxy never decrypts HTTPS. WKWebView owns TLS/SNI/trust.
final class LocalSOCKSProxy {
    struct Endpoint { let port: UInt16; let username: String; let password: String }
    let resolver: DNSResolver
    private let queue = DispatchQueue(label: "LinkCapture.local-proxy")
    private var listener: NWListener?
    private var clients: [UUID: SOCKSTunnel] = [:]
    private let username = UUID().uuidString
    private let password = UUID().uuidString
    private let log: (String) -> Void
    private var startCompletions: [(Result<Endpoint, Error>) -> Void] = []
    private var startTimer: DispatchWorkItem?

    init(resolver: DNSResolver, log: @escaping (String) -> Void) { self.resolver = resolver; self.log = log }
    func start(completion: @escaping (Result<Endpoint, Error>) -> Void) {
        queue.async {
            if let port = self.listener?.port {
                completion(.success(Endpoint(port: port.rawValue, username: self.username, password: self.password))); return
            }
            self.startCompletions.append(completion)
            if self.listener != nil { return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                let timer = DispatchWorkItem { [weak self] in self?.finishStart(.failure(LinkError.timeout)); self?.stopOnQueue() }
                self.startTimer = timer; self.queue.asyncAfter(deadline: .now() + 8, execute: timer)
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener.port else { return }
                        self.log("Proxy local pronto em loopback; SOCKS5 autenticado, TCP.")
                        self.finishStart(.success(Endpoint(port: port.rawValue, username: self.username, password: self.password)))
                    case .failed(let error): self.finishStart(.failure(error)); self.stopOnQueue()
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self = self, self.clients.count < 64 else { connection.cancel(); return }
                    let id = UUID()
                    let tunnel = SOCKSTunnel(client: connection, resolver: self.resolver, username: self.username, password: self.password, queue: self.queue, log: self.log) { [weak self] in self?.clients.removeValue(forKey: id) }
                    self.clients[id] = tunnel; tunnel.start()
                }
                listener.start(queue: self.queue)
            } catch { self.finishStart(.failure(error)) }
        }
    }
    private func finishStart(_ result: Result<Endpoint, Error>) { startTimer?.cancel(); startTimer = nil; let completions = startCompletions; startCompletions.removeAll(); completions.forEach { $0(result) } }
    func closeConnections() { queue.async { let tunnels = Array(self.clients.values); tunnels.forEach { $0.close() } } }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() { finishStart(.failure(LinkError.protocolError)); listener?.cancel(); listener = nil; let tunnels = Array(clients.values); tunnels.forEach { $0.close() }; clients.removeAll() }
}

private final class SOCKSTunnel {
    private let client: NWConnection
    private var upstream: NWConnection?
    private let resolver: DNSResolver
    private let username: String, password: String
    private let queue: DispatchQueue
    private let log: (String) -> Void
    private let onClose: () -> Void
    private var closed = false
    private var timer: DispatchWorkItem?
    private var task: Task<Void, Never>?

    init(client: NWConnection, resolver: DNSResolver, username: String, password: String, queue: DispatchQueue, log: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.client = client; self.resolver = resolver; self.username = username; self.password = password; self.queue = queue; self.log = log; self.onClose = onClose
    }
    func start() {
        arm(12)
        client.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state { case .ready: self.greeting(); case .failed: self.close(); default: break }
        }
        client.start(queue: queue)
    }
    func close() { guard !closed else { return }; closed = true; timer?.cancel(); task?.cancel(); client.cancel(); upstream?.cancel(); onClose() }
    private func arm(_ seconds: Double) { timer?.cancel(); let timer = DispatchWorkItem { [weak self] in self?.close() }; self.timer = timer; queue.asyncAfter(deadline: .now() + seconds, execute: timer) }
    // Exact reads tolerate arbitrary TCP fragmentation, and don't consume TLS bytes.
    private func read(_ count: Int, accumulated: Data = Data(), then: @escaping (Data) -> Void) {
        guard !closed, count > accumulated.count, count <= 4096 else { close(); return }
        client.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            var bytes = accumulated; if let data = data { bytes.append(data) }
            if bytes.count == count { then(bytes) }
            else if error != nil || complete { self.close() }
            else { self.read(count, accumulated: bytes, then: then) }
        }
    }
    private func send(_ bytes: [UInt8], then: @escaping () -> Void) {
        client.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            guard let self = self, !self.closed else { return }; if error != nil { self.close() } else { then() }
        })
    }
    private func greeting() {
        read(2) { [weak self] head in
            guard let self = self, head[0] == 5, head[1] > 0 else { self?.close(); return }
            self.read(Int(head[1])) { methods in
                guard methods.contains(2) else { self.send([5,255]) { self.close() }; return }
                self.send([5,2]) { self.authenticate() }
            }
        }
    }
    private func authenticate() {
        read(2) { [weak self] head in
            guard let self = self, head[0] == 1, head[1] > 0 else { self?.close(); return }
            self.read(Int(head[1])) { user in self.read(1) { length in
                guard length[0] > 0 else { self.close(); return }
                self.read(Int(length[0])) { pass in
                    guard String(data: user, encoding: .utf8) == self.username, String(data: pass, encoding: .utf8) == self.password else { self.send([1,1]) { self.close() }; return }
                    self.send([1,0]) { self.request() }
                }
            } }
        }
    }
    private func request() {
        read(4) { [weak self] head in
            guard let self = self, head[0] == 5, head[1] == 1, head[2] == 0 else { self?.reject(7); return }
            switch head[3] {
            case 3: self.read(1) { length in
                guard length[0] > 0 else { self.reject(8); return }
                self.read(Int(length[0])) { address in
                    guard let host = String(data: address, encoding: .utf8), host.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), !host.contains("/"), !host.contains("\\") else { self.reject(8); return }
                    self.port(host)
                }
            }
            case 1: self.read(4) { data in self.port(data.map { String($0) }.joined(separator: ".")) }
            case 4: self.read(16) { data in
                let bytes = Array(data)
                let host = stride(from: 0, to: 16, by: 2).map { String(UInt16(bytes[$0]) << 8 | UInt16(bytes[$0+1]), radix: 16) }.joined(separator: ":")
                self.port(host)
            }
            default: self.reject(8)
            }
        }
    }
    private func port(_ host: String) {
        read(2) { bytes in
            let port = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            guard port == 80 || port == 443 else { self.reject(2); return }
            self.arm(45)
            self.task = Task { [weak self] in
                guard let self = self else { return }
                do {
                    let ips = try await self.resolver.resolve(host)
                    self.queue.async { if !self.closed { self.connect(host, port, Array(ips.prefix(4)), index: 0) } }
                } catch { self.queue.async { self.log("DNS/proxy \(host): \(error.localizedDescription)"); self.reject(4) } }
            }
        }
    }
    private func connect(_ host: String, _ port: UInt16, _ ips: [String], index: Int) {
        guard !closed else { return }
        guard index < ips.count else { log("Conexão esgotada \(host):\(port)"); reject(5); return }
        let ip = ips[index]
        guard URLPolicy.publicIP(ip), let endpointPort = NWEndpoint.Port(rawValue: port) else { reject(2); return }
        // Numeric endpoint: no second DNS lookup between validation and connect.
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: endpointPort, using: .tcp)
        upstream = connection
        var advanced = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, !advanced, !self.closed else { return }; advanced = true; connection.cancel()
            self.log("TCP timeout \(host) IP=\(ip)"); self.connect(host, port, ips, index: index+1)
        }
        queue.asyncAfter(deadline: .now() + 8, execute: timeout)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.closed, !advanced else { return }
            switch state {
            case .ready:
                advanced = true; timeout.cancel()
                self.log("TCP conectado \(host):\(port) IP=\(ip). TLS ainda depende do WKWebView.")
                self.send([5,0,0,1,0,0,0,0,0,0]) { self.arm(120); self.pipe(self.client, connection); self.pipe(connection, self.client) }
            case .failed(let error):
                advanced = true; timeout.cancel(); connection.cancel()
                self.log("TCP \(host) IP=\(ip): \(error)"); self.connect(host, port, ips, index: index+1)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func reject(_ code: UInt8) { guard !closed else { return }; send([5,code,0,1,0,0,0,0,0,0]) { self.close() } }
    private func pipe(_ source: NWConnection, _ destination: NWConnection) {
        guard !closed else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            if let data = data, !data.isEmpty {
                self.arm(120)
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if error != nil || sendError != nil || complete { self.close() }
                    else { self.pipe(source, destination) }
                })
            } else if error != nil || complete { self.close() }
            else { self.pipe(source, destination) }
        }
    }
}
