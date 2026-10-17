import XCTest
import WebKit
import Network
import SwiftUI
import Darwin
@testable import LinkCapture

// Explicit opt-in: these tests contact public sites and must never be replaced
// by mocked DNS or a canned successful page. Run on simulator AND real iPhone.
@MainActor final class NetworkTests: XCTestCase {
    private var proxy: LocalSOCKSProxy?
    private var view: WKWebView?
    private var probe: NavigationProbe?
    private var window: UIWindow?
    override func tearDown() { proxy?.stop(); proxy = nil; view?.stopLoading(); view = nil; probe = nil; window?.isHidden = true; window = nil; super.tearDown() }
    private func enabled() throws { try XCTSkipUnless(ProcessInfo.processInfo.environment["LINKCAPTURE_NETWORK_TESTS"] == "1", "Teste de rede exige LINKCAPTURE_NETWORK_TESTS=1") }

    private func browse(_ text: String, useProxy: Bool) async throws -> NavigationProbe.Observation {
        let store = WKWebsiteDataStore.nonPersistent()
        if useProxy {
            guard #available(iOS 17.0, *) else { throw XCTSkip("API pública de proxy exige iOS 17. Teste direto continua disponível no iOS 16.") }
            let resolver = DNSResolver(log: { print($0) })
            let local = LocalSOCKSProxy(resolver: resolver, log: { print($0) }); proxy = local
            let endpoint = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LocalSOCKSProxy.Endpoint, Error>) in local.start { continuation.resume(with: $0) } }
            print("PROXY STEP: assign public refined property via Network C APIs"); fflush(stdout)
            BrowserModel.configureProxy(store: store, endpoint: endpoint)
            print("PROXY STEP: assignment returned"); fflush(stdout)
        }
        print("PROXY STEP: create WKWebView"); fflush(stdout)
        let config = WKWebViewConfiguration(); config.websiteDataStore = store
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: config)
        view = webView
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController(); controller.view = webView
            window.rootViewController = controller; window.makeKeyAndVisible(); self.window = window
        }
        let delegate = NavigationProbe(); probe = delegate; webView.navigationDelegate = delegate
        let result = await delegate.browse(webView, url: URL(string: text)!)
        let data = try JSONEncoder().encode(result)
        let image = try? await webView.takeSnapshot(configuration: nil)
        if let image = image {
            let screenshot = XCTAttachment(image: image); screenshot.name = "WKWebView-real-render"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "\(useProxy ? "proxy" : "direct")-\(URL(string: text)!.host!)-observation"; attachment.lifetime = .keepAlways; add(attachment)
        return result
    }
    func testNormalWKWebViewNavigation() async throws {
        try enabled(); let result = try await browse("https://example.com/?sd=3", useProxy: false)
        XCTAssertNil(result.error); XCTAssertEqual(result.status, 200); XCTAssertTrue(result.url.contains("sd=3")); XCTAssertGreaterThan(result.text, 20)
    }
    func testRealLocalProxyCarriesHTTPSTraffic() async throws {
        try enabled(); let result = try await browse("https://example.com/?sd=3", useProxy: true)
        XCTAssertNil(result.error); XCTAssertEqual(result.status, 200); XCTAssertTrue(result.url.contains("sd=3")); XCTAssertGreaterThan(result.text, 20)
    }
    func testNXDOMAINIsFailure() async throws {
        try enabled(); let result = try await browse("https://linkcapture-test.invalid/", useProxy: true)
        XCTAssertNotNil(result.error)
    }
    func testInvalidCertificateIsNotAccepted() async throws {
        try enabled(); let result = try await browse("https://expired.badssl.com/", useProxy: true)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.errorDomain, NSURLErrorDomain, "Falha genérica do proxy não comprova rejeição TLS")
        XCTAssertTrue([-1200, -1201, -1202, -1203, -1204].contains(result.errorCode ?? 0), "Exigir erro TLS/certificado, não um timeout ou falha TCP")
    }
    func test62qpixDirectBaseline() async throws {
        try enabled(); let result = try await browse("https://62qpix.vip", useProxy: false)
        // Baseline is recorded, not assumed to fail on every network.
        print("BASELINE \(result)")
    }
    func test62qpixRecoveryMustReachLaunchWithContent() async throws {
        try enabled(); let result = try await browse("https://62qpix.vip", useProxy: true)
        XCTAssertNil(result.error)
        XCTAssertTrue((200..<400).contains(result.status ?? 0))
        XCTAssertEqual(URL(string: result.url)?.host, "62qpix.vip")
        XCTAssertEqual(URL(string: result.url)?.path, "/launch", "Não afirmar recuperação se não atingir /launch")
        XCTAssertGreaterThan(result.text + result.graphics, 20, "HTTP 200 vazio não confirma o caso real")
    }
}

@MainActor private final class NavigationProbe: NSObject, WKNavigationDelegate {
    struct Observation: Codable { var url = ""; var status: Int?; var error: String?; var errorDomain: String?; var errorCode: Int?; var text = 0; var graphics = 0; var redirects: [String] = [] }
    private var observation = Observation()
    private var completion: CheckedContinuation<Observation, Never>?
    private var timeout: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    func browse(_ view: WKWebView, url: URL) async -> Observation {
        await withCheckedContinuation { continuation in
            completion = continuation
            timeout = Task { try? await Task.sleep(nanoseconds: 55_000_000_000); if !Task.isCancelled { self.observation.error = "Timeout de validação"; self.finish(view) } }
            view.load(URLRequest(url: url, timeoutInterval: 45))
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { settle?.cancel() }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) { observation.redirects.append(webView.url?.absoluteString ?? "pendente") }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame { observation.status = (navigationResponse.response as? HTTPURLResponse)?.statusCode }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle?.cancel()
        settle = Task {
            // Allow an actual JavaScript redirect instead of synthesizing /launch.
            try? await Task.sleep(nanoseconds: 8_000_000_000); guard !Task.isCancelled else { return }
            webView.evaluateJavaScript("({text:(document.body?.innerText||'').trim().length,graphics:document.querySelectorAll('img,canvas,video').length})") { value, _ in
                Task { @MainActor in
                    let dict = value as? [String: Any]; self.observation.text = dict?["text"] as? Int ?? 0; self.observation.graphics = dict?["graphics"] as? Int ?? 0
                    self.finish(webView)
                }
            }
        }
    }
    private func recordError(_ error: Error, view: WKWebView) {
        let ns = error as NSError
        observation.error = ns.localizedDescription; observation.errorDomain = ns.domain; observation.errorCode = ns.code
        finish(view)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { recordError(error, view: webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { recordError(error, view: webView) }
    private func finish(_ view: WKWebView) {
        guard let continuation = completion else { return }; completion = nil; timeout?.cancel(); settle?.cancel()
        observation.url = view.url?.absoluteString ?? ""; continuation.resume(returning: observation)
    }
}

