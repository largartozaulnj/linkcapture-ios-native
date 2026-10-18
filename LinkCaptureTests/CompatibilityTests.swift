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
        let controller = UIHostingController(rootView: BrowserScreen(model: model).preferredColorScheme(.dark))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.view.bounds.width, 0)
        XCTAssertGreaterThan(controller.view.safeAreaLayoutGuide.layoutFrame.height, 0)
        let viewport = model.webView.convert(model.webView.bounds, to: controller.view)
        let safe = controller.view.safeAreaLayoutGuide.layoutFrame
        XCTAssertGreaterThan(viewport.width, 0)
        XCTAssertGreaterThan(viewport.height, 0)
        XCTAssertGreaterThanOrEqual(viewport.minY, safe.minY + 44, "Address bar must reserve space above the site")
        XCTAssertLessThanOrEqual(viewport.maxY, safe.maxY - 44, "Bottom controls must not overlap the site")
        XCTAssertGreaterThanOrEqual(viewport.minX, safe.minX - 1)
        XCTAssertLessThanOrEqual(viewport.maxX, safe.maxX + 1)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "native-layout-\(UIDevice.current.systemVersion)"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCompactAndWideLayoutsPreserveViewport() async throws {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { throw XCTSkip("No scene") }
        for size in [CGSize(width: 390, height: 750), CGSize(width: 750, height: 340)] {
            let model = BrowserModel()
            let host = UIHostingController(rootView: BrowserScreen(model: model).preferredColorScheme(.dark))
            let parent = UIViewController()
            let window = UIWindow(windowScene: scene)
            window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(host); parent.view.addSubview(host.view); host.didMove(toParent: parent)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.autoresizingMask = []
            try await Task.sleep(nanoseconds: 400_000_000)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let safe = host.view.safeAreaLayoutGuide.layoutFrame
            let viewport = model.webView.convert(model.webView.bounds, to: host.view)
            XCTAssertGreaterThan(viewport.height, 80)
            XCTAssertGreaterThanOrEqual(viewport.minY, safe.minY + 44)
            XCTAssertLessThanOrEqual(viewport.maxY, safe.maxY - 44)
            XCTAssertLessThanOrEqual(viewport.width, size.width + 1)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "browser-layout-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }

}
