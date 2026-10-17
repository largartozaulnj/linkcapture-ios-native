import SwiftUI
import WebKit
import Network
import Security

@MainActor final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var webView: WKWebView!
    @Published var address = UserDefaults.standard.string(forKey: "lastURL") ?? "https://62qpix.vip"
    @Published var recovering = false
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var message = "Digite um link para começar."
    @Published var diagnostics: [String] = []
    @Published var originalURL = ""
    @Published var finalURL = ""
    @Published var attempt = 0
    @Published var mode = "Direto"
    @Published var identifiedError = "Nenhum"
    @Published var result = "Não testado"
    @Published var httpStatus: Int?
    @Published var controlsHidden = false
    private let store = WKWebsiteDataStore.nonPersistent()
    private var resolver: DNSResolver!
    private var proxy: LocalSOCKSProxy!
    private var observations: [NSKeyValueObservation] = []
    private var generation = UUID()
    private var recoveryTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var redirectCount = 0
    private var proxyActive = false
    private var stopped = false
    private var lastRequest: URLRequest?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "LinkCapture.path")
    @Published var connectionType = "Ainda não observada"

    override init() {
        super.init()
        let logger: (String) -> Void = { [weak self] entry in Task { @MainActor in self?.log(entry) } }
        resolver = DNSResolver(log: logger)
        proxy = LocalSOCKSProxy(resolver: resolver, log: logger)
        rebuild()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let description = path.status != .satisfied ? "Sem caminho disponível" : path.usesInterfaceType(.wifi) ? "Wi-Fi" : path.usesInterfaceType(.cellular) ? "Dados móveis" : "Outra interface"
            Task { @MainActor in
                guard let self = self else { return }
                self.connectionType = description
                self.log("Rede: \(description). Mudança de rede não reenvia formulários automaticamente.")
            }
        }
        pathMonitor.start(queue: pathQueue)
    }
    func log(_ value: String) {
        let time = ISO8601DateFormatter().string(from: Date())
        diagnostics.append("\(time) \(value)")
        if diagnostics.count > 400 { diagnostics.removeFirst(diagnostics.count - 400) }
    }
    private func rebuild() {
        observations.removeAll()
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView?.stopLoading()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false; view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        webView = view
        observations = [
            view.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.canGoBack = view.canGoBack } },
            view.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in Task { @MainActor in self?.canGoForward = view.canGoForward } },
            view.observe(\.url, options: [.new]) { [weak self] view, _ in Task { @MainActor in
                guard let self = self, self.webView === view, let url = view.url else { return }
                self.address = url.absoluteString; self.finalURL = url.absoluteString
            } }
        ]
    }
    func open(_ text: String? = nil, forceDNS: Bool = false) {
        do {
            let url = try URLPolicy.parse(text ?? address)
            cancelTasks(); generation = UUID(); stopped = false
            originalURL = url.absoluteString; finalURL = ""; identifiedError = "Nenhum"; result = "Em andamento"; httpStatus = nil
            address = url.absoluteString; attempt = 1; redirectCount = 0
            lastRequest = nil
            UserDefaults.standard.set(url.absoluteString, forKey: "lastURL")
            log("Navegação original=\(url.absoluteString)")
            if forceDNS { recover(url, initialProxy: true) }
            else { load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)) }
        } catch { message = error.localizedDescription }
    }
    func normalMode() {
        cancelTasks(); generation = UUID(); webView.stopLoading(); proxy.closeConnections()
        if #available(iOS 17.0, *) { store.__proxyConfigurations = [] }
        proxyActive = false; mode = "Direto"; rebuild()
        message = "Modo direto. O próximo link usará o DNS do sistema."; recovering = false; loading = false
    }
    func stop() { stopped = true; generation = UUID(); cancelTasks(); webView.stopLoading(); proxy.closeConnections(); recovering = false; loading = false; message = "Navegação interrompida."; result = "Interrompido pelo usuário" }
    private func cancelTasks() { recoveryTask?.cancel(); recoveryTask = nil; watchdog?.cancel(); watchdog = nil }
    private func load(_ request: URLRequest) {
        lastRequest = request; loading = true; message = "Abrindo link…"
        webView.load(request); watch()
    }
    private func watch() {
        watchdog?.cancel(); let token = generation
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self = self, token == self.generation, self.loading else { return }
            self.webView.stopLoading()
            self.failed(URLError(.timedOut), url: self.webView.url ?? self.lastRequest?.url)
        }
    }
    func back() { if webView.canGoBack { prepareHistory(); webView.goBack() } }
    func forward() { if webView.canGoForward { prepareHistory(); webView.goForward() } }
    private func prepareHistory() { generation = UUID(); cancelTasks(); attempt = 1; redirectCount = 0; stopped = false; recovering = false; httpStatus = nil }
    func reload() { open(webView.url?.absoluteString ?? address) }
    func home() { stop(); webView.isHidden = true; controlsHidden = false; message = "Digite ou cole um endereço." }
    func diagnoseDNS() {
        guard let url = try? URLPolicy.parse(address), let host = url.host else { message = "Confira a URL."; return }
        Task { do { let ips = try await resolver.resolve(host); log("Diagnóstico informativo \(host): \(ips.joined(separator: ", "))") } catch { log("Diagnóstico DNS: \(error.localizedDescription)") } }
    }
    private func recover(_ url: URL, initialProxy: Bool = false) {
        guard #available(iOS 17.0, *) else {
            // iOS 16 has no public per-WKWebView proxy configuration.
            // Retry a GET once using the normal stack; never replace HTTPS
            // hostname with an IP or claim that DoH changed the connection.
            guard !stopped, attempt < 2, lastRequest?.httpMethod == nil || lastRequest?.httpMethod == "GET" else {
                finishFailure("Sem recuperação disponível no iOS 16. Consulte DNS no Diagnóstico."); return
            }
            recovering = true; attempt += 1; mode = "Reteste direto (iOS 16)"
            log("iOS 16: proxy não disponível. Reteste direto; DoH apenas informativo.")
            recoveryTask?.cancel()
            let token = generation
            recoveryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self = self, token == self.generation else { return }
                self.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
            }
            return
        }
        guard !stopped, (attempt < 3 || initialProxy), lastRequest?.httpMethod == nil || lastRequest?.httpMethod == "GET" else {
            finishFailure("Sem recuperação automática segura disponível."); return
        }
        if !initialProxy { attempt += 1 }
        recovering = true; loading = true; httpStatus = nil
        let token = generation
        let provider: DNSResolver.Provider = attempt < 3 ? .cloudflare : .google
        log("Tentativa \(attempt): proxy local + \(provider.rawValue), URL=\(url.absoluteString)")
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self = self else { return }
            await self.resolver.reset(provider: provider)
            self.proxy.closeConnections()
            do {
                let endpoint = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LocalSOCKSProxy.Endpoint, Error>) in
                    self.proxy.start { continuation.resume(with: $0) }
                }
                guard !Task.isCancelled, token == self.generation else { return }
                Self.configureProxy(store: self.store, endpoint: endpoint)
                self.proxyActive = true; self.mode = "Proxy local / \(provider.rawValue)"
                self.rebuild(); self.redirectCount = 0
                self.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45))
            } catch { guard token == self.generation else { return }; self.log("Proxy indisponível: \(error.localizedDescription)"); self.finishFailure("Não foi possível iniciar a recuperação local.") }
        }
    }
    private func finishFailure(_ text: String) { watchdog?.cancel(); recovering = false; loading = false; result = "Falha ou inconclusivo"; message = text }
    private func failed(_ error: Error, url: URL?) {
        guard !stopped else { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        let category: String
        let retryable: Bool
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: category = "DNS"; retryable = true
            case NSURLErrorTimedOut: category = "Timeout"; retryable = true
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost: category = "Conexão"; retryable = true
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired: category = "TLS / certificado"; retryable = false
            case NSURLErrorNotConnectedToInternet: category = "Sem internet"; retryable = false
            default: category = "Navegação"; retryable = false
            }
        } else { category = "WebKit / processo"; retryable = false }
        identifiedError = "\(category): \(ns.domain) \(ns.code) — \(ns.localizedDescription)"
        log(identifiedError)
        if retryable, attempt < 3, let url = url ?? lastRequest?.url { recover(url) }
        else { finishFailure("Não foi possível abrir o link. Consulte Diagnóstico.") }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard self.webView === webView, !stopped else { return }
        webView.isHidden = false; loading = true; httpStatus = nil
        log("Início \(webView.url?.absoluteString ?? address)"); watch()
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        log("Redirecionamento HTTP → \(webView.url?.absoluteString ?? "URL pendente")")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard self.webView === webView, !stopped, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            log("Esquema externo bloqueado: \(scheme)")
            message = "O site tentou abrir um aplicativo externo."
            decisionHandler(.cancel); return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            if navigationAction.navigationType == .linkActivated {
                cancelTasks(); generation = UUID(); attempt = 1; redirectCount = 0; recovering = false; originalURL = url.absoluteString; result = "Em andamento"
            }
            redirectCount += 1; lastRequest = navigationAction.request
            log("Navegação principal \(navigationAction.request.httpMethod ?? "GET") \(url.absoluteString)")
            if redirectCount > 16 { decisionHandler(.cancel); identifiedError = "Limite de navegações/redirecionamentos"; finishFailure("O site repetiu navegações demais."); return }
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard self.webView === webView else { decisionHandler(.cancel); return }
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
            httpStatus = response.statusCode
            finalURL = response.url?.absoluteString ?? ""
            log("HTTP \(response.statusCode) URL=\(finalURL)")
            if response.statusCode >= 400 {
                identifiedError = "Servidor HTTP \(response.statusCode)"; result = "Erro HTTP"
                recovering = false
            }
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        log("Documento recebido. Ainda sem confirmação de conteúdo.")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, !stopped else { return }
        watchdog?.cancel(); loading = false
        finalURL = webView.url?.absoluteString ?? finalURL
        let token = generation
        // Evidence only. HTTP 200 and didFinish alone never mean success.
        let script = """
        (() => { const b=document.body; if(!b)return {text:0,graphics:0,error:false}; const t=(b.innerText||'').trim(); const r=b.getBoundingClientRect(); const graphics=[...b.querySelectorAll('img,canvas,video,svg')].filter(e=>{const q=e.getBoundingClientRect();return q.width>10&&q.height>10&&getComputedStyle(e).visibility!=='hidden'&&getComputedStyle(e).display!=='none'&&(e.tagName!=='IMG'||e.complete&&e.naturalWidth>0)}).length; return {text:r.width>0&&r.height>0?t.length:0,graphics,error:/^(404|403|502|503|access denied|server not found|site can.t be reached|servidor n.o encontrado)/i.test(t.slice(0,200))}; })()
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
            Task { @MainActor in
                guard let self = self, let webView = webView, self.webView === webView, self.generation == token else { return }
                let values = value as? [String: Any]
                let text = values?["text"] as? Int ?? 0, graphics = values?["graphics"] as? Int ?? 0
                let suspectedError = values?["error"] as? Bool ?? false
                self.log("Evidência DOM texto=\(text), gráficos=\(graphics), erroSuspeito=\(suspectedError), JS=\(error?.localizedDescription ?? "ok")")
                if (self.httpStatus ?? 0) >= 400 || suspectedError {
                    self.recovering = false; self.result = "Página de erro / HTTP"; self.message = "O site retornou um erro. Consulte Diagnóstico."
                } else if text > 20 || graphics > 0 {
                    self.recovering = false; self.result = "Conteúdo detectado; confirmação visual pendente"; self.message = "Confira o conteúdo exibido."
                } else {
                    self.result = "Conteúdo inconclusivo / possível página vazia"
                    // One bounded retry for empty documents; don't keep looping a blank page.
                    if self.attempt < 2, let url = webView.url { self.recover(url) }
                    else { self.recovering = false; self.message = "Conteúdo não confirmado. Consulte Diagnóstico." }
                }
            }
        }
    }
    func confirmVisibleContent() { result = "Conteúdo confirmado visualmente pelo usuário"; log(result + " URL=" + finalURL) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView { failed(error, url: (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView { failed(error, url: webView.url) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { guard self.webView === webView else { return }; log("Processo WebKit encerrado"); finishFailure("O processo da página foi encerrado. Toque em Atualizar.") }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            var error: CFError?
            let valid = SecTrustEvaluateWithError(trust, &error)
            log("TLS \(challenge.protectionSpace.host): confiança=\(valid), \(error.map { String(describing: $0) } ?? "avaliação do sistema")")
            if !valid { completionHandler(.cancelAuthenticationChallenge, nil); identifiedError = "TLS: certificado inválido"; finishFailure("Certificado HTTPS inválido. A conexão foi interrompida."); return }
        }
        completionHandler(.performDefaultHandling, nil)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank remains in the same native view, only on user navigation.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") { open(url.absoluteString) }
        else { log("Pop-up automático bloqueado") }
        return nil
    }
    var report: String {
        """
        LinkCapture iOS experimental — \(UIDevice.current.systemVersion)
        Original: \(originalURL)
        Atual/final observada: \(finalURL)
        Tentativas: \(attempt)
        Estratégia: \(mode)
        Capacidade de recuperação: \(proxyCapability)
        Rede observada: \(connectionType)
        HTTP principal: \(httpStatus.map(String.init) ?? "não observado")
        Erro: \(identifiedError)
        Resultado: \(result)
        \(diagnostics.joined(separator: "\n"))
        """
    }
    // NS_REFINED_FOR_SWIFT imports the PUBLIC Objective-C property as
    // __proxyConfigurations. Avoid the SDK 18.5 Swift overlay setter which
    // produced a null-function SIGSEGV in the real simulator network test.
    // These are documented public Network C APIs, not private selectors/KVC.
    @available(iOS 17.0, *)
    static func configureProxy(store: WKWebsiteDataStore, endpoint: LocalSOCKSProxy.Endpoint) {
        let host = nw_endpoint_create_host("127.0.0.1", String(endpoint.port))
        let configuration = nw_proxy_config_create_socksv5(host)
        nw_proxy_config_set_failover_allowed(configuration, false)
        nw_proxy_config_set_username_and_password(configuration, endpoint.username, endpoint.password)
        store.__proxyConfigurations = [configuration]
    }
    var proxyCapability: String {
        if #available(iOS 17.0, *) { return "Proxy local experimental disponível pela API pública (iOS 17+)" }
        return "iOS 16: reteste direto e diagnóstico DNS; proxy WKWebView indisponível"
    }
}
