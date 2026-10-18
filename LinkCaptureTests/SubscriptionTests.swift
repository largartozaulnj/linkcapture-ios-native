import XCTest
@testable import LinkCapture

final class SubscriptionTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testUnknownExpirationNeverInventsDeadline() {
        var p = RenewalPreferences(); p.enabled = true
        XCTAssertTrue(RenewalPlan.make(p, now: date("2026-10-17T09:00:00Z"), calendar: calendar).isEmpty)
        XCTAssertNil(p.expiration)
    }
    func testSevenUniqueNotificationsAtConfiguredHour() {
        var p = RenewalPreferences(); p.enabled = true; p.expiration = date("2026-10-24T18:00:00Z")
        let plan = RenewalPlan.make(p, now: date("2026-10-17T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(plan.map(\.days), [6,5,4,3,2,1,0])
        XCTAssertEqual(Set(plan.map(\.identifier)).count, 7)
        XCTAssertTrue(plan.allSatisfy { calendar.component(.hour, from: $0.date) == 10 })
        XCTAssertTrue(plan.filter { $0.days <= 2 }.allSatisfy(\.sound))
        XCTAssertEqual(plan.first?.message, "Faltam 6 dias para renovar o LinkCapture.")
    }
    func testPastAlertsAndExpiredDatesAreNotScheduled() {
        var p = RenewalPreferences(); p.enabled = true; p.expiration = date("2026-10-24T18:00:00Z")
        let now = date("2026-10-23T11:00:00Z")
        XCTAssertEqual(RenewalPlan.make(p, now: now, calendar: calendar).map(\.days), [0])
        XCTAssertTrue(RenewalPlan.make(p, now: date("2026-10-25T00:00:00Z"), calendar: calendar).isEmpty)
        p.enabled = false
        XCTAssertTrue(RenewalPlan.make(p, now: now, calendar: calendar).isEmpty)
    }
    func testUrgentAlertsWorkWhenDailyAlertsAreDisabled() {
        var p = RenewalPreferences(); p.enabled = true; p.daily = false; p.expiration = date("2026-10-24T18:00:00Z")
        XCTAssertEqual(RenewalPlan.make(p, now: date("2026-10-17T09:00:00Z"), calendar: calendar).map(\.days), [2,1,0])
        p.urgent = false
        XCTAssertTrue(RenewalPlan.make(p, now: date("2026-10-17T09:00:00Z"), calendar: calendar).isEmpty)
    }
    func testFinalAlertIsBeforeEarlyExpirationAndRenewalChangesDates() {
        var p = RenewalPreferences(); p.enabled = true; p.expiration = date("2026-10-24T08:00:00Z")
        let now = date("2026-10-17T09:00:00Z")
        let old = RenewalPlan.make(p, now: now, calendar: calendar)
        XCTAssertEqual(old.last?.date, date("2026-10-24T07:59:00Z"))
        p.expiration = date("2026-10-31T08:00:00Z")
        let new = RenewalPlan.make(p, now: now, calendar: calendar)
        XCTAssertEqual(new.map(\.identifier), old.map(\.identifier))
        XCTAssertNotEqual(new.map(\.date), old.map(\.date))
    }
    func testDaylightSavingKeepsLocalReminderHour() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        var p = RenewalPreferences(); p.enabled = true; p.expiration = date("2026-03-10T18:00:00Z")
        let plan = RenewalPlan.make(p, now: date("2026-03-03T09:00:00Z"), calendar: c)
        XCTAssertEqual(plan.count, 7)
        XCTAssertTrue(plan.allSatisfy { c.component(.hour, from: $0.date) == 10 })
    }
    @MainActor func testReopeningDoesNotExtendStoredManualExpiration() throws {
        let name = "LinkCaptureTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var p = RenewalPreferences(); p.expiration = date("2026-10-24T18:00:00Z")
        defaults.set(try JSONEncoder().encode(p), forKey: SubscriptionModel.preferencesKey)
        XCTAssertEqual(SubscriptionModel(defaults: defaults).preferences.expiration, p.expiration)
        XCTAssertEqual(SubscriptionModel(defaults: defaults).preferences.expiration, p.expiration)
    }
    func testCatalogUsesExactBundleIDAndBuildForUpdates() throws {
        let data = Data(#"{"apps":[{"bundleIdentifier":"org.linkcapture.experimental","versions":[{"version":"0.2.0","buildVersion":"2","downloadURL":"https://example.com/app.ipa","size":123}]}]}"#.utf8)
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        XCTAssertNil(catalog.latest(for: "another.bundle"))
        XCTAssertEqual(catalog.latest(for: "org.linkcapture.experimental")?.buildVersion, "2")
        XCTAssertTrue(Catalog.isNewer(version: "0.2.0", build: "2", than: "0.1.0", currentBuild: "1"))
        XCTAssertTrue(Catalog.isNewer(version: "0.2.0", build: "3", than: "0.2.0", currentBuild: "2"))
        XCTAssertFalse(Catalog.isNewer(version: "0.2.0", build: "2", than: "0.2.0", currentBuild: "2"))
    }
}
