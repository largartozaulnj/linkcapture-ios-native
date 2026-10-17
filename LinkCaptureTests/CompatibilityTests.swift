import XCTest
import SwiftUI
import WebKit
@testable import LinkCapture

@MainActor final class CompatibilityTests: XCTestCase {
    func testBrowserInitializesOnInstalledIOSAndHonorsSafeArea() async throws {
        let model = BrowserModel()
        XCTAssertNotNil(model.webView)
        XCTAssertTrue(model.webView.allowsBackForwardNavigationGestures)
        if #available(iOS 17.0, *) { XCTAssertTrue(model.proxyCapability.contains("iOS 17+")) }
        else { XCTAssertTrue(model.proxyCapability.contains("iOS 16")) }
        // Baseline snapshot of the native UI on this simulator. This is a
        // layout smoke test, not proof of site loading or DNS recovery.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { throw XCTSkip("Sem UIWindowScene disponível") }
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: BrowserScreen().preferredColorScheme(.dark))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.view.bounds.width, 0)
        XCTAssertGreaterThan(controller.view.safeAreaLayoutGuide.layoutFrame.height, 0)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "native-layout-\(UIDevice.current.systemVersion)"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
