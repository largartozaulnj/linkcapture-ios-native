import XCTest
@testable import LinkCapture

final class PolicyTests: XCTestCase {
    func testPreservesPathsParametersAndEscapes() throws {
        for text in ["https://62qpix.vip/launch?sd=3", "http://example.com/a?x=a%2Fb&sd=3#fim", "https://example.com/?x=1&x=2"] {
            XCTAssertEqual(try URLPolicy.parse(text).absoluteString, text)
        }
        XCTAssertEqual(try URLPolicy.parse("62qpix.vip?sd=3").absoluteString, "https://62qpix.vip?sd=3")
    }
    func testRejectsUnsafeAndAmbiguousURLs() {
        for text in ["", "javascript:alert(1)", "file:///etc/passwd", "intent://launch", "https://user:pass@example.com", "https://exa mple.com", "https://example.com\\@evil.com"] {
            XCTAssertThrowsError(try URLPolicy.parse(text), text)
        }
    }
    func testBlocksInternalAndReservedAddresses() {
        for ip in ["127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.0.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "198.18.0.1", "192.0.2.1", "198.51.100.1", "203.0.113.1", "::1", "::ffff:127.0.0.1", "fc00::1", "fe80::1", "64:ff9b::a00:1", "2001:db8::1", "2002:7f00:1::1", "ff02::1", "not-an-ip"] {
            XCTAssertFalse(URLPolicy.publicIP(ip), ip)
        }
    }
    func testAcceptsPublicAddresses() {
        for ip in ["1.1.1.1", "8.8.8.8", "104.18.22.74", "104.18.23.74", "2606:4700::1111", "2001:4860:4860::8888"] {
            XCTAssertTrue(URLPolicy.publicIP(ip), ip)
        }
    }
    func testDNSDecodingDoesNotTreatNXDOMAINAsSuccess() throws {
        let response = try JSONDecoder().decode(DNSAnswer.self, from: Data("{\"Status\":3}".utf8))
        XCTAssertEqual(response.Status, 3)
        XCTAssertNil(response.Answer)
    }
}
